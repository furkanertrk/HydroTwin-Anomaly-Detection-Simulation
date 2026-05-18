"""Analyze Python localization errors and compare with MATLAB outputs."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

from src.localization import build_mas_candidates, parse_zone_list
from src.paths import DATA_DIR, FIGURES_DIR, RESULTS_DIR
from src.plots import (
    plot_localization_error_histogram,
    plot_sensitivity_strength_map,
    plot_top1_error_by_method,
    plot_xgb_zone_hit_vs_error,
)
from src.sensitivity import load_sensitivity_matrix
from src.zones import load_node_zone_map


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze localization errors.")
    parser.add_argument("--compare-existing", action="store_true")
    parser.add_argument("--plot", action="store_true")
    parser.add_argument("--threshold-m", type=float, default=300.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    per_leak_path = RESULTS_DIR / "localization_fair_cusum_per_leak.csv"
    feature_path = RESULTS_DIR / "localization_fair_cusum_features.csv"
    if not per_leak_path.exists():
        raise FileNotFoundError(f"Run localization first; missing {per_leak_path}")

    per_leak = pd.read_csv(per_leak_path)
    features = pd.read_csv(feature_path) if feature_path.exists() else pd.DataFrame()
    sensitivity = load_sensitivity_matrix(DATA_DIR / "sensitivity_matrix.mat")
    zones = load_node_zone_map(DATA_DIR / "node_zone_map.csv")
    analysis, zone_strength = build_error_analysis(per_leak, features, sensitivity, zones, args.threshold_m)

    analysis_path = RESULTS_DIR / "localization_error_analysis.csv"
    analysis.to_csv(analysis_path, index=False)
    print(f"Saved localization error analysis: {analysis_path}")

    if args.compare_existing:
        report_path = RESULTS_DIR / "localization_error_compare_report.md"
        write_compare_report(analysis, DATA_DIR / "localization_error_analysis.csv", report_path)
        print(f"Saved localization error compare report: {report_path}")

    if args.plot:
        FIGURES_DIR.mkdir(parents=True, exist_ok=True)
        plot_localization_error_histogram(per_leak, FIGURES_DIR / "localization_error_histogram.png")
        summary_path = RESULTS_DIR / "localization_fair_cusum_summary.csv"
        if summary_path.exists():
            plot_top1_error_by_method(pd.read_csv(summary_path), FIGURES_DIR / "top1_error_by_method.png")
        plot_xgb_zone_hit_vs_error(per_leak, FIGURES_DIR / "xgb_zone_hit_vs_error.png")
        plot_sensitivity_strength_map(zone_strength, analysis, FIGURES_DIR / "sensitivity_strength_map.png")
        print(f"Saved localization figures in: {FIGURES_DIR}")

    return 0


def build_error_analysis(
    per_leak: pd.DataFrame,
    features: pd.DataFrame,
    sensitivity,
    zones,
    threshold_m: float,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    out = per_leak.copy()
    for col in ["top1_error_m", "top5_min_error_m", "top10_min_error_m", "candidate_count"]:
        out[col] = pd.to_numeric(out[col], errors="coerce")

    out["top1_success_300m"] = out["top1_error_m"] <= threshold_m
    out["top5_success_300m"] = out["top5_min_error_m"] <= threshold_m
    out["top10_success_300m"] = out["top10_min_error_m"] <= threshold_m

    strength = np.linalg.norm(sensitivity.s, axis=0)
    strength_by_node = dict(zip(sensitivity.junction_ids, strength))
    q20 = float(np.quantile(strength, 0.20))
    q10 = float(np.quantile(strength, 0.10))
    zone_by_node = zones.junction_to_zone

    out["sensitivity_strength"] = out["true_node"].map(strength_by_node)
    out["weak_sensitivity_flag"] = out["sensitivity_strength"] <= q20
    out["blind_spot_flag"] = out["sensitivity_strength"] <= q10
    out["true_zone"] = out["true_node"].map(zone_by_node)
    out["predicted_zone"] = out["predicted_node"].map(zone_by_node)

    confidence = compute_confidence(out, features, sensitivity, zones)
    out = out.merge(confidence, on=["leak_id", "method_name"], how="left")
    out["failure_mode"] = out.apply(classify_failure_mode, axis=1)

    zone_strength = zones.table.copy()
    zone_strength["sensitivity_strength"] = zone_strength["junction_id"].map(strength_by_node)
    zone_strength["weak_sensitivity_flag"] = zone_strength["sensitivity_strength"] <= q20
    zone_strength["blind_spot_flag"] = zone_strength["sensitivity_strength"] <= q10

    columns = [
        "leak_id",
        "method_name",
        "true_pipe_id",
        "true_node",
        "predicted_node",
        "top1_error_m",
        "top5_min_error_m",
        "top10_min_error_m",
        "top1_success_300m",
        "top5_success_300m",
        "top10_success_300m",
        "candidate_count",
        "true_zone",
        "predicted_zone",
        "xgb_top1_zone",
        "xgb_top3_zones",
        "zone_hit_top1",
        "zone_hit_top3",
        "sensitivity_strength",
        "confidence_gap",
        "confidence_ratio",
        "weak_sensitivity_flag",
        "blind_spot_flag",
        "failure_mode",
    ]
    for col in columns:
        if col not in out.columns:
            out[col] = np.nan
    return out[columns], zone_strength


def compute_confidence(per_leak: pd.DataFrame, features: pd.DataFrame, sensitivity, zones) -> pd.DataFrame:
    if features.empty:
        return pd.DataFrame(columns=["leak_id", "method_name", "confidence_gap", "confidence_ratio"])
    mean_cols = [f"r_mean_{idx}" for idx in range(1, sensitivity.sensor_count + 1)]
    if any(col not in features.columns for col in mean_cols):
        return pd.DataFrame(columns=["leak_id", "method_name", "confidence_gap", "confidence_ratio"])

    feature_by_leak = features.set_index("leak_id")
    zone_by_sens = np.array([zones.junction_to_zone[jid] for jid in sensitivity.junction_ids], dtype=int)
    rows = []
    for _, row in per_leak.iterrows():
        leak_id = row["leak_id"]
        if leak_id not in feature_by_leak.index:
            continue
        r_mean = feature_by_leak.loc[leak_id, mean_cols].to_numpy(dtype=float)
        method = row["method_name"]
        if method == "Global sensitivity":
            candidate_idx = np.arange(sensitivity.junction_count)
        elif method == "MAS sensitivity":
            candidate_idx = build_mas_candidates(r_mean, sensitivity.s)["candidate_idx"]
        elif method == "XGBoost top-3 zones + sensitivity":
            candidate_idx = np.flatnonzero(np.isin(zone_by_sens, parse_zone_list(row.get("xgb_top3_zones", ""))))
        else:
            candidate_idx = np.array([], dtype=int)
        gap, ratio = confidence_for_candidates(sensitivity.s_norm, r_mean, candidate_idx)
        rows.append(
            {
                "leak_id": leak_id,
                "method_name": method,
                "confidence_gap": gap,
                "confidence_ratio": ratio,
            }
        )
    return pd.DataFrame(rows)


def confidence_for_candidates(s_norm: np.ndarray, r_mean: np.ndarray, candidate_idx: np.ndarray) -> tuple[float, float]:
    candidate_idx = np.asarray(candidate_idx, dtype=int).reshape(-1)
    candidate_idx = candidate_idx[(candidate_idx >= 0) & (candidate_idx < s_norm.shape[1])]
    if candidate_idx.size < 2:
        return np.nan, np.nan
    r_norm = r_mean / (np.linalg.norm(r_mean) + 1e-9)
    correlations = s_norm.T @ r_norm
    sorted_scores = np.sort(correlations[candidate_idx])[::-1]
    gap = float(sorted_scores[0] - sorted_scores[1])
    ratio = float(sorted_scores[0] / (abs(sorted_scores[1]) + 1e-9))
    return gap, ratio


def classify_failure_mode(row: pd.Series) -> str:
    if bool(row.get("top1_success_300m", False)):
        return "success_within_300m"
    if str(row.get("method_name", "")).startswith("XGBoost") and not _to_bool(row.get("zone_hit_top3")):
        return "wrong_zone"
    if _to_bool(row.get("blind_spot_flag")) or _to_bool(row.get("weak_sensitivity_flag")):
        return "weak_sensitivity"
    if pd.notna(row.get("confidence_gap")) and float(row["confidence_gap"]) < 1e-6:
        return "low_confidence"
    if not _to_bool(row.get("top10_success_300m")):
        return "large_distance_error"
    if str(row.get("method_name", "")).startswith("XGBoost") and _to_bool(row.get("zone_hit_top3")):
        return "candidate_filter_miss"
    return "unknown"


def write_compare_report(new_df: pd.DataFrame, old_path: Path, report_path: Path) -> None:
    lines = ["# Localization Error Compare Report", ""]
    if not old_path.exists():
        lines.append(f"Existing MATLAB error analysis not found: `{old_path}`")
        report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return
    old_df = normalize_existing_error_analysis(pd.read_csv(old_path))
    keys = ["leak_id", "method_name"]
    old = old_df.copy()
    new = new_df.copy()
    lines.append(f"- MATLAB rows: {len(old)}")
    lines.append(f"- Python rows: {len(new)}")
    lines.append("")
    lines.append("## Method Row Counts")
    for method in sorted(set(old["method_name"]).union(set(new["method_name"]))):
        lines.append(
            f"- {method}: MATLAB={int((old['method_name'] == method).sum())}, "
            f"Python={int((new['method_name'] == method).sum())}"
        )

    merged = old.merge(new, on=keys, how="outer", suffixes=("_matlab", "_python"), indicator=True)
    lines.append("")
    lines.append("## Row Matching")
    lines.append(f"- Matched rows: {int((merged['_merge'] == 'both').sum())}")
    lines.append(f"- Only MATLAB rows: {int((merged['_merge'] == 'left_only').sum())}")
    lines.append(f"- Only Python rows: {int((merged['_merge'] == 'right_only').sum())}")

    both = merged[merged["_merge"] == "both"].copy()
    lines.append("")
    lines.append("## Numeric Differences")
    for col in [
        "top1_error_m",
        "top5_min_error_m",
        "top10_min_error_m",
        "candidate_count",
        "sensitivity_strength",
        "confidence_gap",
        "confidence_ratio",
    ]:
        left_col = f"{col}_matlab"
        right_col = f"{col}_python"
        if left_col not in both.columns or right_col not in both.columns:
            lines.append(f"- `{col}`: not comparable")
            continue
        left = pd.to_numeric(both[left_col], errors="coerce")
        right = pd.to_numeric(both[right_col], errors="coerce")
        diff = (left - right).abs()
        lines.append(f"- `{col}` abs diff: mean={diff.mean():.6g}, max={diff.max():.6g}")

    lines.append("")
    lines.append("## Boolean / Category Differences")
    for col in [
        "top1_success_300m",
        "top5_success_300m",
        "top10_success_300m",
        "zone_hit_top1",
        "zone_hit_top3",
    ]:
        left_col = f"{col}_matlab"
        right_col = f"{col}_python"
        if left_col not in both.columns or right_col not in both.columns:
            lines.append(f"- `{col}`: not comparable")
            continue
        left = both[left_col].map(_to_bool)
        right = both[right_col].map(_to_bool)
        mismatch = (left != right).sum()
        lines.append(f"- `{col}` mismatches: {int(mismatch)}")

    lines.append("")
    lines.append("## Category Differences")
    for col in [
        "failure_mode",
    ]:
        left_col = f"{col}_matlab"
        right_col = f"{col}_python"
        if left_col not in both.columns or right_col not in both.columns:
            lines.append(f"- `{col}`: not comparable")
            continue
        mismatch = (both[left_col].fillna("").astype(str) != both[right_col].fillna("").astype(str)).sum()
        lines.append(f"- `{col}` mismatches: {int(mismatch)}")

    lines.extend(
        [
            "",
            "## Notes",
            "- Differences can come from confidence score recomputation, failure-mode label simplification, sensitivity strength naming, or boolean formatting.",
            "- Python failure modes use: success_within_300m, weak_sensitivity, wrong_zone, low_confidence, candidate_filter_miss, large_distance_error, unknown.",
        ]
    )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def normalize_existing_error_analysis(df: pd.DataFrame) -> pd.DataFrame:
    """Map MATLAB diagnostic column names onto Python's final report schema."""
    out = df.copy()
    aliases = {
        "true_sensitivity_strength": "sensitivity_strength",
        "weak_sensitivity_q20": "weak_sensitivity_flag",
        "blind_sensitivity_q10": "blind_spot_flag",
        "true_zone_id": "true_zone",
        "predicted_zone_id": "predicted_zone",
    }
    for source, target in aliases.items():
        if target not in out.columns and source in out.columns:
            out[target] = out[source]
    return out


def _to_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if pd.isna(value):
        return False
    return str(value).strip().lower() in {"true", "1", "1.0", "yes"}


if __name__ == "__main__":
    raise SystemExit(main())
