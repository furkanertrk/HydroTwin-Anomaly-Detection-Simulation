"""Localization smoke-test entry point for the HydroTwin Python port."""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from src.config import load_config
from src.data_loader import load_nominal_baseline, load_pressure_scada
from src.epanet_model import LTownModel, load_ltown_model
from src.localization import (
    inspect_residual_windows,
    load_cusum_events,
    residual_checks_to_frame,
    run_global_mas_localization,
)
from src.ml_zone_model import XGBoostAvailability, check_xgb_model
from src.paths import DATA_DIR, RESULTS_DIR
from src.paths import FIGURES_DIR
from src.plots import plot_localization_error_histogram, plot_top1_error_by_method
from src.plots import plot_xgb_zone_hit_vs_error
from src.sensitivity import SensitivityData, load_sensitivity_matrix
from src.zones import ZoneMap, load_node_zone_map


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate localization loaders, ID mapping, and CUSUM event inputs."
    )
    parser.add_argument("--smoke-test", action="store_true", help="Run mapping and residual-window checks.")
    parser.add_argument("--method", choices=["global", "mas", "xgb_hybrid", "all"], default="all")
    parser.add_argument(
        "--use-python-detection",
        action="store_true",
        help="Use python_port/results/detection_comparison.csv instead of data/detection_comparison.csv.",
    )
    parser.add_argument("--threshold-m", type=float, default=300.0, help="Success distance threshold in meters.")
    parser.add_argument("--compare-existing", action="store_true")
    parser.add_argument("--plot", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    ltown = load_ltown_model(DATA_DIR)
    sensitivity = load_sensitivity_matrix(DATA_DIR / "sensitivity_matrix.mat")
    zones = load_node_zone_map(DATA_DIR / "node_zone_map.csv")
    xgb = check_xgb_model(DATA_DIR / "xgb_zone_model.pkl")

    detection_path = (
        RESULTS_DIR / "detection_comparison.csv"
        if args.use_python_detection
        else DATA_DIR / "detection_comparison.csv"
    )
    events = load_cusum_events(detection_path)

    cfg = load_config(DATA_DIR / "dataset_configuration.yaml")
    baseline = load_nominal_baseline(DATA_DIR / "nominal_baseline.mat")
    years = sorted({int(year) for year in events["leak_start_time"].dt.year.dropna().unique()})
    if not years:
        years = [2018, 2019]
    scada_by_year = {year: load_pressure_scada(DATA_DIR, year) for year in years}

    if not args.smoke_test:
        run = run_global_mas_localization(
            events=events,
            cfg=cfg,
            baseline=baseline,
            scada_by_year=scada_by_year,
            sensitivity=sensitivity,
            ltown=ltown,
            method=args.method,
            threshold_m=args.threshold_m,
            zones=zones,
            xgb_model_path=DATA_DIR / "xgb_zone_model.pkl",
        )
        per_leak_path = RESULTS_DIR / "localization_fair_cusum_per_leak.csv"
        summary_path = RESULTS_DIR / "localization_fair_cusum_summary.csv"
        skipped_path = RESULTS_DIR / "localization_skipped_events.csv"
        feature_path = RESULTS_DIR / "localization_fair_cusum_features.csv"
        zone_pred_path = RESULTS_DIR / "localization_fair_cusum_zone_predictions.csv"
        _write_csv(run.per_leak, per_leak_path)
        _write_csv(run.summary, summary_path)
        _write_csv(run.skipped, skipped_path)
        _write_csv(run.features, feature_path)
        _write_csv(run.zone_predictions, zone_pred_path)
        print(f"Saved localization per-leak results: {per_leak_path}")
        print(f"Saved localization summary: {summary_path}")
        if not run.skipped.empty:
            print(f"Saved skipped event report: {skipped_path}")

        if args.compare_existing:
            report_path = RESULTS_DIR / "localization_compare_report.md"
            compare_with_existing_localization(
                run.per_leak,
                run.summary,
                DATA_DIR / "localization_fair_cusum_per_leak.csv",
                DATA_DIR / "localization_fair_cusum_summary.csv",
                report_path,
                run.xgb_availability,
            )
            print(f"Saved localization compare report: {report_path}")

        if args.plot:
            histogram_path = FIGURES_DIR / "localization_error_histogram.png"
            bar_path = FIGURES_DIR / "top1_error_by_method.png"
            plot_localization_error_histogram(run.per_leak, histogram_path)
            plot_top1_error_by_method(run.summary, bar_path)
            xgb_plot_path = FIGURES_DIR / "xgb_zone_hit_vs_error.png"
            plot_xgb_zone_hit_vs_error(run.per_leak, xgb_plot_path)
            print(f"Saved localization error histogram: {histogram_path}")
            print(f"Saved top-1 error plot: {bar_path}")
            print(f"Saved XGBoost zone-hit plot: {xgb_plot_path}")
        return 0

    residual_checks = inspect_residual_windows(events, cfg, baseline, scada_by_year, limit=2)

    mapping_path = RESULTS_DIR / "localization_mapping_check.csv"
    event_path = RESULTS_DIR / "localization_event_check.csv"
    report_path = RESULTS_DIR / "localization_smoke_report.md"

    _write_mapping_check(mapping_path, ltown, sensitivity, zones, args.threshold_m)
    _write_event_check(event_path, events, residual_checks)
    _write_report(
        report_path=report_path,
        ltown=ltown,
        sensitivity=sensitivity,
        zones=zones,
        events=events,
        residual_checks=residual_checks,
        xgb=xgb,
        detection_path=detection_path,
        mapping_path=mapping_path,
        event_path=event_path,
        threshold_m=args.threshold_m,
    )

    print(f"Saved localization smoke report: {report_path}")
    print(f"Saved mapping check: {mapping_path}")
    print(f"Saved event check: {event_path}")
    return 0


def compare_with_existing_localization(
    new_per_leak: pd.DataFrame,
    new_summary: pd.DataFrame,
    old_per_leak_path: Path,
    old_summary_path: Path,
    report_path: Path,
    xgb_availability=None,
) -> None:
    lines = ["# Localization Compare Report", ""]
    if xgb_availability is not None:
        lines.append(f"- XGBoost model loaded: {xgb_availability.loadable}")
        lines.append(f"- XGBoost feature count: {xgb_availability.feature_count if xgb_availability.feature_count is not None else 'n/a'}")
        lines.append(f"- XGBoost class count: {xgb_availability.class_count if xgb_availability.class_count is not None else 'n/a'}")
        lines.append(f"- XGBoost message: {xgb_availability.message}")
    lines.append("")

    if not old_per_leak_path.exists() or not old_summary_path.exists():
        lines.append("Existing MATLAB fair CUSUM localization outputs were not found.")
        report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return

    old_per = pd.read_csv(old_per_leak_path)
    old_sum = pd.read_csv(old_summary_path)
    methods = ["Global sensitivity", "MAS sensitivity", "XGBoost top-3 zones + sensitivity"]
    old_per = old_per[old_per["method_name"].isin(methods)].copy()
    old_sum = old_sum[old_sum["method_name"].isin(methods)].copy()
    new_per = new_per_leak[new_per_leak["method_name"].isin(methods)].copy()
    new_sum = new_summary[new_summary["method_name"].isin(methods)].copy()

    lines.append(f"- Python evaluated leak-method rows: {len(new_per)}")
    lines.append(f"- MATLAB evaluated leak-method rows: {len(old_per)}")
    lines.append(f"- Python evaluated leak count: {new_per['leak_id'].nunique() if not new_per.empty else 0}")
    lines.append(f"- MATLAB evaluated leak count: {old_per['leak_id'].nunique() if not old_per.empty else 0}")
    xgb_new = new_per[new_per["method_name"] == "XGBoost top-3 zones + sensitivity"].copy()
    if not xgb_new.empty:
        lines.append(f"- XGBoost prediction rows: {len(xgb_new)}")
        lines.append(f"- XGBoost top-1 zone hits: {int(_to_bool_series(xgb_new['zone_hit_top1']).sum())}")
        lines.append(f"- XGBoost top-3 zone hits: {int(_to_bool_series(xgb_new['zone_hit_top3']).sum())}")
    lines.append("")

    lines.append("## Summary Differences")
    merged_summary = old_sum.merge(new_sum, on="method_name", suffixes=("_matlab", "_python"), how="outer", indicator=True)
    comparable_summary = [
        "evaluated_leaks",
        "top1_within_300m",
        "top5_within_300m",
        "top10_within_300m",
        "top1_rate",
        "top5_rate",
        "top10_rate",
        "median_top1_error_m",
        "mean_top1_error_m",
        "mean_candidate_count",
    ]
    for _, row in merged_summary.iterrows():
        method_name = row["method_name"]
        lines.append(f"### {method_name}")
        if row["_merge"] != "both":
            lines.append(f"- Match status: {row['_merge']}")
            continue
        for col in comparable_summary:
            left = row.get(f"{col}_matlab")
            right = row.get(f"{col}_python")
            diff = _numeric_diff(left, right)
            lines.append(f"- `{col}`: MATLAB={left}, Python={right}, diff={diff}")
        lines.append("")

    lines.append("## Per-Leak Error Differences")
    keys = ["leak_id", "method_name"]
    merged = old_per.merge(new_per, on=keys, suffixes=("_matlab", "_python"), how="outer", indicator=True)
    only_old = merged[merged["_merge"] == "left_only"][keys]
    only_new = merged[merged["_merge"] == "right_only"][keys]
    lines.append(f"- Matched leak-method rows: {int((merged['_merge'] == 'both').sum())}")
    lines.append(f"- Only MATLAB rows: {len(only_old)}")
    lines.append(f"- Only Python rows: {len(only_new)}")
    if not only_old.empty:
        lines.append(f"- Missing in Python: {only_old.to_dict(orient='records')}")
    if not only_new.empty:
        lines.append(f"- Missing in MATLAB: {only_new.to_dict(orient='records')}")

    both = merged[merged["_merge"] == "both"].copy()
    for col in ["top1_error_m", "top5_min_error_m", "top10_min_error_m", "candidate_count"]:
        left = pd.to_numeric(both.get(f"{col}_matlab"), errors="coerce")
        right = pd.to_numeric(both.get(f"{col}_python"), errors="coerce")
        abs_diff = (left - right).abs()
        lines.append(
            f"- `{col}` absolute diff: mean={abs_diff.mean():.6g}, max={abs_diff.max():.6g}"
        )

    if not both.empty:
        left = pd.to_numeric(both["top1_error_m_matlab"], errors="coerce")
        right = pd.to_numeric(both["top1_error_m_python"], errors="coerce")
        worst_idx = (left - right).abs().idxmax()
        worst = both.loc[worst_idx]
        lines.append("")
        lines.append("## Largest Top-1 Error Difference")
        lines.append(
            f"- leak={worst['leak_id']}, method={worst['method_name']}, "
            f"MATLAB={worst['top1_error_m_matlab']}, Python={worst['top1_error_m_python']}"
        )

    lines.extend(
        [
            "",
            "## Difference Notes",
            "- Large differences usually point to residual window alignment, sensitivity matrix orientation, MAS candidate selection, node/junction ID mapping, or pipe-midpoint distance semantics.",
            "- Large XGBoost differences usually point to feature ordering, zone label/index handling, pickle/library version differences, candidate zone filtering, or residual window alignment.",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_csv(df: pd.DataFrame, path: Path) -> None:
    out = df.copy()
    for col in out.columns:
        if pd.api.types.is_datetime64_any_dtype(out[col]):
            out[col] = out[col].dt.strftime("%Y-%m-%d %H:%M:%S").fillna("")
    path.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(path, index=False)


def _numeric_diff(left: object, right: object) -> str:
    try:
        return f"{float(right) - float(left):.6g}"
    except Exception:
        return "n/a"


def _to_bool_series(series: pd.Series) -> pd.Series:
    return series.map(lambda value: str(value).strip().lower() in {"true", "1", "1.0"})


def _write_mapping_check(
    output_path: Path,
    ltown: LTownModel,
    sensitivity: SensitivityData,
    zones: ZoneMap,
    threshold_m: float,
) -> None:
    sample_pipes = ["p257", "p461", "p673"]
    rows: list[dict[str, object]] = []
    for pipe_id in sample_pipes:
        if pipe_id not in set(ltown.link_endpoints["link_id"]):
            continue
        midpoint = ltown.get_pipe_midpoint(pipe_id)
        nearest = _nearest_junction(ltown, midpoint.x, midpoint.y)
        rows.append(
            {
                "check_type": "pipe_midpoint_distance",
                "pipe_id": pipe_id,
                "start_node": midpoint.start_node,
                "end_node": midpoint.end_node,
                "midpoint_x": midpoint.x,
                "midpoint_y": midpoint.y,
                "sample_junction_id": nearest["junction_id"],
                "distance_m": nearest["distance_m"],
                "within_threshold": nearest["distance_m"] <= threshold_m,
                "junction_in_sensitivity": nearest["junction_id"] in sensitivity.junction_to_col,
                "junction_zone_id": zones.junction_to_zone.get(nearest["junction_id"]),
            }
        )
    pd.DataFrame(rows).to_csv(output_path, index=False)


def _write_event_check(
    output_path: Path,
    events: pd.DataFrame,
    residual_checks,
) -> None:
    event_cols = [
        "method",
        "leak_id",
        "true_pipe_id",
        "leak_start_time",
        "alarm_time",
        "detected",
        "false_alarm_before_leak",
    ]
    event_frame = events.loc[:, [col for col in event_cols if col in events.columns]].copy()
    event_frame["event_selected"] = True
    residual_frame = residual_checks_to_frame(residual_checks).drop(
        columns=["leak_start_time", "alarm_time"],
        errors="ignore",
    )
    merged = event_frame.merge(residual_frame, on="leak_id", how="left")
    merged.to_csv(output_path, index=False)


def _write_report(
    report_path: Path,
    ltown: LTownModel,
    sensitivity: SensitivityData,
    zones: ZoneMap,
    events: pd.DataFrame,
    residual_checks,
    xgb: XGBoostAvailability,
    detection_path: Path,
    mapping_path: Path,
    event_path: Path,
    threshold_m: float,
) -> None:
    ltown_summary = ltown.smoke_summary()
    zone_sizes = zones.zone_size_summary()
    ok_windows = sum(1 for check in residual_checks if check.status == "ok")
    safe_to_continue = (
        ltown.junction_count == 782
        and ltown.pipe_count > 0
        and sensitivity.s.shape == (33, 782)
        and sensitivity.s_norm.shape == (33, 782)
        and zones.zone_count == 30
        and len(events) > 0
        and ok_windows == len(residual_checks)
    )

    lines = [
        "# Localization Smoke Report",
        "",
        "## Inputs",
        f"- INP file: `{ltown.inp_path}`",
        f"- Detection source: `{detection_path}`",
        f"- Distance threshold: {threshold_m:.1f} m",
        "",
        "## EPANET Mapping",
        f"- Junction count: {ltown.junction_count}",
        f"- Link count: {ltown.link_count}",
        f"- Pipe count: {ltown.pipe_count}",
        f"- Sample junction: `{ltown_summary['sample_junction']}`",
        f"- Sample pipe endpoint: `{ltown_summary['sample_link']}`",
        f"- Sample pipe midpoint: `{ltown_summary['sample_midpoint']}`",
        "",
        "## Sensitivity Matrix",
        f"- S shape: {sensitivity.s.shape}",
        f"- S_norm shape: {sensitivity.s_norm.shape}",
        f"- Junction count: {sensitivity.junction_count}",
        f"- Sensor count: {sensitivity.sensor_count}",
        f"- First 5 junction IDs: {list(sensitivity.junction_ids[:5])}",
        f"- First 5 sensor indices: {list(sensitivity.sensor_indices[:5])}",
        "",
        "## Zone Map",
        f"- Zone count: {zones.zone_count}",
        f"- Junction count: {zones.junction_count}",
        f"- Zone candidate count min/mean/max: {zone_sizes['min']:.0f}/{zone_sizes['mean']:.1f}/{zone_sizes['max']:.0f}",
        f"- Example junction-zone mapping: `{next(iter(zones.junction_to_zone.items()))}`",
        "",
        "## CUSUM Events",
        f"- Selected event count: {len(events)}",
        f"- First events: `{_first_events_text(events)}`",
        "",
        "## Residual Window Checks",
        f"- Checked events: {len(residual_checks)}",
        f"- Successful checks: {ok_windows}",
    ]
    for check in residual_checks:
        lines.append(
            f"- {check.leak_id}: status={check.status}, calibration={check.calibration_window_size}, "
            f"localization={check.localization_window_size}, measured={check.measured_pressure_shape}, "
            f"nominal={check.nominal_pressure_shape}, residual_vector={check.residual_vector_shape}, "
            f"message={check.message or 'ok'}"
        )
    lines.extend(
        [
            "",
            "## XGBoost Availability",
            f"- Model path: `{xgb.path}`",
            f"- Exists: {xgb.exists}",
            f"- Loadable: {xgb.loadable}",
            f"- Model class: {xgb.model_class or 'n/a'}",
            f"- Feature count: {xgb.feature_count if xgb.feature_count is not None else 'n/a'}",
            f"- Class count: {xgb.class_count if xgb.class_count is not None else 'n/a'}",
            f"- Message: {xgb.message}",
            "",
            "## Outputs",
            f"- Mapping check CSV: `{mapping_path}`",
            f"- Event check CSV: `{event_path}`",
            "",
            "## Phase 3B-2 Readiness",
            f"- Safe to continue: {safe_to_continue}",
        ]
    )
    if safe_to_continue:
        lines.append("- Recommendation: proceed with Global/MAS/XGBoost localization implementation.")
    else:
        lines.append("- Recommendation: fix the failed smoke checks before implementing ranking.")
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _nearest_junction(ltown: LTownModel, x: float, y: float) -> dict[str, object]:
    coords = ltown.junction_coordinates.copy()
    distances = ((coords["x"] - x) ** 2 + (coords["y"] - y) ** 2) ** 0.5
    idx = int(distances.idxmin())
    return {"junction_id": str(coords.loc[idx, "junction_id"]), "distance_m": float(distances.loc[idx])}


def _first_events_text(events: pd.DataFrame, count: int = 3) -> str:
    cols = ["leak_id", "leak_start_time", "alarm_time"]
    present = [col for col in cols if col in events.columns]
    return events.loc[: count - 1, present].to_dict(orient="records")


if __name__ == "__main__":
    raise SystemExit(main())
