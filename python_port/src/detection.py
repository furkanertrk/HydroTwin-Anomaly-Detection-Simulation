"""CUSUM, XBar/FDM, and hybrid leak detection."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd

from .config import HydroTwinConfig, Leakage
from .data_loader import NominalBaseline, PressureScada


N_CALIB = 288
K_PERSIST = 12
CUSUM_DELTA = 3.0
CUSUM_ETA = 60.0
XBAR_WINDOW = 36
XBAR_SIGMA = 4.0
XBAR_PERSIST = 1

METHOD_LABELS = {
    "cusum": "CUSUM",
    "xbar_fdm": "XBarFDM",
    "hybrid": "Hybrid",
}
ACTIVE_METHODS = ["CUSUM", "XBarFDM", "Hybrid"]
COMPARABLE_METHODS = ["CUSUM", "XBarFDM"]
OUTPUT_COLUMNS = [
    "method",
    "leak_id",
    "start_time",
    "demo_start",
    "leak_type",
    "year",
    "alarmed",
    "detected",
    "false_alarm_before_leak",
    "alarm_time",
    "alarm_delay_h",
    "threshold",
    "calib_center",
    "calib_scale",
    "missed",
    "detection_delay_hours",
    "leak_start_time",
    "leak_end_time",
]


@dataclass(frozen=True)
class DetectorResult:
    alarm_idx: int | None
    threshold: float | None
    center: float | None
    scale: float | None


@dataclass(frozen=True)
class ResidualCase:
    leakage: Leakage
    demo_start: pd.Timestamp
    time: pd.Series
    residual: np.ndarray
    res_norm: np.ndarray
    usable: bool
    skip_reason: str = ""


def compare_detectors(
    cfg: HydroTwinConfig,
    baseline: NominalBaseline,
    scada_by_year: dict[int, PressureScada],
    method: str,
    years: Iterable[int],
) -> tuple[pd.DataFrame, list[ResidualCase]]:
    rows: list[dict[str, object]] = []
    residual_cases: list[ResidualCase] = []
    methods = _selected_methods(method)
    year_set = set(years)

    for leakage in cfg.leakages:
        if leakage.year not in year_set:
            continue
        if leakage.year not in scada_by_year:
            raise KeyError(f"Missing SCADA data for year {leakage.year}")

        case = build_residual_case(leakage, baseline, scada_by_year[leakage.year])
        residual_cases.append(case)
        detector_results = _run_all_detectors(case) if case.usable else {}

        for method_name in methods:
            result = detector_results.get(method_name)
            rows.append(_make_output_row(leakage, case, method_name, result))

    return pd.DataFrame(rows, columns=OUTPUT_COLUMNS), residual_cases


def build_residual_case(
    leakage: Leakage,
    baseline: NominalBaseline,
    scada: PressureScada,
) -> ResidualCase:
    leak_start = pd.Timestamp(leakage.start_time)
    leak_end = pd.Timestamp(leakage.end_time)
    demo_start = leak_start.normalize() - pd.Timedelta(days=1)
    demo_end = min(leak_end, pd.Timestamp(scada.time.iloc[-1]))
    mask = (scada.time >= demo_start) & (scada.time <= demo_end)

    if int(mask.sum()) < (N_CALIB + K_PERSIST):
        return _empty_case(leakage, demo_start, "not enough samples in demo window")

    measured = scada.pressures[mask.to_numpy(), :]
    demo_time = scada.time[mask].reset_index(drop=True)
    if demo_time.empty:
        return _empty_case(leakage, demo_start, "empty demo window")
    if pd.Timestamp(demo_time.iloc[0]) > demo_start:
        return _empty_case(leakage, demo_start, "demo does not start at calibration day")
    if leak_start <= pd.Timestamp(demo_time.iloc[N_CALIB - 1]):
        return _empty_case(leakage, demo_start, "clean previous-day calibration unavailable")

    nominal = nominal_slice_for_time(demo_time, baseline.p_nominal, leakage.year)
    if measured.shape[1] != nominal.shape[1]:
        raise ValueError(
            f"Pressure width mismatch for {leakage.link_id}: "
            f"SCADA={measured.shape[1]}, nominal={nominal.shape[1]}"
        )

    bias = np.nanmean(measured[:N_CALIB, :] - nominal[:N_CALIB, :], axis=0)
    residual = (nominal + bias) - measured
    res_norm = np.linalg.norm(residual, axis=1)
    return ResidualCase(
        leakage=leakage,
        demo_start=demo_start,
        time=demo_time,
        residual=residual,
        res_norm=res_norm,
        usable=True,
    )


def nominal_slice_for_time(
    time: pd.Series,
    p_nominal_year: np.ndarray,
    year: int,
) -> np.ndarray:
    year_start = pd.Timestamp(datetime(year, 1, 1, 0, 0, 0))
    minutes_from_start = (time - year_start).dt.total_seconds().to_numpy() / 60.0
    idx = np.rint(minutes_from_start / 5.0).astype(int)
    idx = np.clip(idx, 0, p_nominal_year.shape[0] - 1)
    return p_nominal_year[idx, :]


def detect_cusum(
    res_norm: np.ndarray,
    n_calib: int = N_CALIB,
    delta: float = CUSUM_DELTA,
    eta: float = CUSUM_ETA,
) -> DetectorResult:
    calib_tail = res_norm[n_calib // 2 : n_calib]
    center = float(np.nanmean(calib_tail))
    scale = max(_nanstd(calib_tail), 1e-6)
    k_ref = 0.5 * delta * scale
    threshold = eta * scale

    s_pos = 0.0
    for idx in range(n_calib, len(res_norm)):
        s_pos = max(0.0, s_pos + float(res_norm[idx]) - (center + k_ref))
        if s_pos > threshold:
            return DetectorResult(idx, float(threshold), center, float(scale))
    return DetectorResult(None, float(threshold), center, float(scale))


def detect_xbar_fdm(
    res_norm: np.ndarray,
    n_calib: int = N_CALIB,
    window_size: int = XBAR_WINDOW,
    sigma_mult: float = XBAR_SIGMA,
    k_persist: int = XBAR_PERSIST,
) -> DetectorResult:
    score = np.full_like(res_norm, np.nan, dtype=float)
    for idx in range(2 * window_size - 1, len(res_norm)):
        prev_mean = np.nanmean(res_norm[idx - 2 * window_size + 1 : idx - window_size + 1])
        curr_mean = np.nanmean(res_norm[idx - window_size + 1 : idx + 1])
        score[idx] = curr_mean - prev_mean

    calib_scores = score[2 * window_size - 1 : n_calib]
    center = float(np.nanmean(calib_scores))
    scale = max(_nanstd(calib_scores), 1e-6)
    threshold = center + sigma_mult * scale
    return DetectorResult(
        alarm_idx=persistent_threshold_alarm(score, threshold, n_calib, k_persist),
        threshold=float(threshold),
        center=center,
        scale=float(scale),
    )


def persistent_threshold_alarm(
    values: np.ndarray,
    threshold: float,
    start_idx: int,
    k_persist: int,
) -> int | None:
    counter = 0
    for idx in range(start_idx, len(values)):
        value = values[idx]
        if not np.isnan(value) and value > threshold:
            counter += 1
            if counter >= k_persist:
                return idx
        else:
            counter = 0
    return None


def write_detection_outputs(df: pd.DataFrame, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    out = df.copy()
    for col in ("start_time", "demo_start", "alarm_time", "leak_start_time", "leak_end_time"):
        out[col] = pd.to_datetime(out[col], errors="coerce").dt.strftime("%Y-%m-%d %H:%M:%S")
        out[col] = out[col].fillna("")
    out.to_csv(output_path, index=False)


def compare_with_existing(new_df: pd.DataFrame, existing_path: Path, report_path: Path) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    if not existing_path.exists():
        report_path.write_text(
            f"# Detection Compare Report\n\nExisting MATLAB output not found: `{existing_path}`\n",
            encoding="utf-8",
        )
        return

    existing = pd.read_csv(existing_path)
    removed_name = "Plan" + "C"
    old_existing_count = len(existing)
    existing = existing[existing["method"].isin(COMPARABLE_METHODS)].copy()
    compared_new = new_df[new_df["method"].isin(COMPARABLE_METHODS)].copy()
    new_norm = _normalize_for_compare(compared_new)
    old_norm = _normalize_for_compare(existing)
    keys = ["method", "leak_id", "year"]
    comparable = [
        "detected",
        "false_alarm_before_leak",
        "alarm_time",
        "alarm_delay_h",
        "threshold",
        "calib_center",
        "calib_scale",
    ]
    merged = old_norm.merge(new_norm, on=keys, how="outer", suffixes=("_matlab", "_python"), indicator=True)

    lines = ["# Detection Compare Report", ""]
    lines.append(f"- Active Python methods: {', '.join(ACTIVE_METHODS)}")
    lines.append(f"- Compared methods: {', '.join(COMPARABLE_METHODS)}")
    lines.append(f"- MATLAB rows before filtering: {old_existing_count}")
    lines.append(f"- MATLAB rows after filtering: {len(existing)}")
    lines.append(f"- Python rows: {len(new_df)}")
    lines.append(f"- Python rows compared: {len(compared_new)}")
    lines.append(f"- Matched rows: {int((merged['_merge'] == 'both').sum())}")
    lines.append(f"- Only MATLAB rows: {int((merged['_merge'] == 'left_only').sum())}")
    lines.append(f"- Only Python rows: {int((merged['_merge'] == 'right_only').sum())}")
    lines.append("")
    lines.append(
        f"{removed_name} was an experimental method and has been removed from the Python port. "
        f"Existing MATLAB {removed_name} rows are ignored during comparison."
    )
    lines.append(
        "Existing MATLAB Hybrid rows are also ignored because they were based on the removed experimental method; "
        "the Python Hybrid method now combines CUSUM and XBar/FDM."
    )
    lines.append("")

    both = merged[merged["_merge"] == "both"].copy()
    mismatch_counts: dict[str, int] = {}
    for col in comparable:
        left = f"{col}_matlab"
        right = f"{col}_python"
        if left not in both or right not in both:
            continue
        mismatch_counts[col] = int(_mismatch_mask(both[left], both[right], col).sum())

    lines.append("## Column Mismatches")
    if mismatch_counts:
        for col, count in mismatch_counts.items():
            lines.append(f"- `{col}`: {count}")
    else:
        lines.append("- No comparable columns found.")
    lines.append("")

    examples = _mismatch_examples(both, comparable)
    if not examples.empty:
        lines.append("## First Differences")
        lines.append("")
        lines.append("```text")
        lines.append(examples.to_string(index=False))
        lines.append("```")
        lines.append("")

    lines.append("## Notes")
    lines.append("- Differences can come from datetime parsing, MAT/HDF5 orientation, baseline index alignment, numeric quantile/std behavior, or MATLAB/Python indexing.")
    report_path.write_text("\n".join(lines), encoding="utf-8")


def _run_all_detectors(case: ResidualCase) -> dict[str, DetectorResult]:
    cusum = detect_cusum(case.res_norm)
    xbar = detect_xbar_fdm(case.res_norm)
    hybrid_idx = _min_ignore_none((cusum.alarm_idx, xbar.alarm_idx))
    return {
        "CUSUM": cusum,
        "XBarFDM": xbar,
        "Hybrid": DetectorResult(hybrid_idx, None, None, None),
    }


def _make_output_row(
    leakage: Leakage,
    case: ResidualCase,
    method_name: str,
    result: DetectorResult | None,
) -> dict[str, object]:
    alarm_time: pd.Timestamp | pd.NaTType = pd.NaT
    alarm_delay_h = np.nan
    alarmed = False
    detected = False
    false_alarm = False

    if case.usable and result and result.alarm_idx is not None:
        alarmed = True
        alarm_time = pd.Timestamp(case.time.iloc[result.alarm_idx])
        alarm_delay_h = (alarm_time - pd.Timestamp(leakage.start_time)).total_seconds() / 3600.0
        false_alarm = alarm_time < pd.Timestamp(leakage.start_time)
        detected = not false_alarm

    return {
        "method": method_name,
        "leak_id": leakage.link_id,
        "start_time": pd.Timestamp(leakage.start_time),
        "demo_start": case.demo_start,
        "leak_type": leakage.leak_type,
        "year": float(leakage.year),
        "alarmed": alarmed,
        "detected": detected,
        "false_alarm_before_leak": false_alarm,
        "alarm_time": alarm_time,
        "alarm_delay_h": alarm_delay_h,
        "threshold": result.threshold if result else np.nan,
        "calib_center": result.center if result else np.nan,
        "calib_scale": result.scale if result else np.nan,
        "missed": not detected,
        "detection_delay_hours": alarm_delay_h,
        "leak_start_time": pd.Timestamp(leakage.start_time),
        "leak_end_time": pd.Timestamp(leakage.end_time),
    }


def _selected_methods(method: str) -> list[str]:
    if method == "all":
        return ACTIVE_METHODS.copy()
    return [METHOD_LABELS[method]]


def _empty_case(leakage: Leakage, demo_start: pd.Timestamp, reason: str) -> ResidualCase:
    return ResidualCase(
        leakage=leakage,
        demo_start=demo_start,
        time=pd.Series([], dtype="datetime64[ns]"),
        residual=np.empty((0, 0)),
        res_norm=np.array([], dtype=float),
        usable=False,
        skip_reason=reason,
    )


def _nanstd(values: np.ndarray) -> float:
    finite_count = int(np.isfinite(values).sum())
    if finite_count <= 1:
        return 0.0
    return float(np.nanstd(values, ddof=1))


def _min_ignore_none(values: Iterable[int | None]) -> int | None:
    present = [value for value in values if value is not None]
    return min(present) if present else None


def _normalize_for_compare(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    if "year" in out:
        out["year"] = pd.to_numeric(out["year"], errors="coerce").astype("Int64")
    for col in ("detected", "false_alarm_before_leak"):
        if col in out:
            out[col] = out[col].map(_to_bool)
    if "alarm_time" in out:
        out["alarm_time"] = pd.to_datetime(out["alarm_time"], errors="coerce").dt.strftime("%Y-%m-%d %H:%M:%S")
        out["alarm_time"] = out["alarm_time"].fillna("")
    return out


def _to_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if pd.isna(value):
        return False
    if isinstance(value, (int, float, np.integer, np.floating)):
        return bool(value)
    return str(value).strip().lower() in {"true", "1", "yes"}


def _mismatch_mask(left: pd.Series, right: pd.Series, col: str) -> pd.Series:
    if col in {"threshold", "calib_center", "calib_scale", "alarm_delay_h"}:
        lnum = pd.to_numeric(left, errors="coerce")
        rnum = pd.to_numeric(right, errors="coerce")
        return pd.Series(
            ~np.isclose(lnum, rnum, rtol=1e-6, atol=1e-6, equal_nan=True),
            index=left.index,
        )
    return left.fillna("").astype(str) != right.fillna("").astype(str)


def _mismatch_examples(both: pd.DataFrame, comparable: list[str]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for _, row in both.iterrows():
        for col in comparable:
            left = f"{col}_matlab"
            right = f"{col}_python"
            if left not in both or right not in both:
                continue
            if bool(_mismatch_mask(pd.Series([row[left]]), pd.Series([row[right]]), col).iloc[0]):
                rows.append(
                    {
                        "method": row["method"],
                        "leak_id": row["leak_id"],
                        "year": row["year"],
                        "column": col,
                        "matlab": row[left],
                        "python": row[right],
                    }
                )
                break
        if len(rows) >= 15:
            break
    return pd.DataFrame(rows)
