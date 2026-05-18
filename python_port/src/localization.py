"""Localization smoke-test helpers.

This module intentionally stops before Global/MAS/XGBoost ranking. It validates
the inputs used by the MATLAB fair CUSUM localization workflow.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from .config import HydroTwinConfig
from .data_loader import NominalBaseline, PressureScada
from .detection import N_CALIB, nominal_slice_for_time
from .epanet_model import LTownModel
from .ml_zone_model import XGBoostAvailability, ZonePredictionResult, predict_zone_topk
from .sensitivity import SensitivityData
from .zones import ZoneMap


N_WINDOW = 288
TOP_NODE_K = 10
MAS_COVERAGE = 0.70
MAS_MIN_SENSORS = 3
MAS_MAX_SENSORS = 8
MAS_CANDIDATE_Q = 0.90
MAS_MIN_CANDIDATES = 30
MAS_MAX_CANDIDATES = 120


@dataclass(frozen=True)
class ResidualWindowCheck:
    leak_id: str
    leak_start_time: pd.Timestamp
    alarm_time: pd.Timestamp
    calibration_window_size: int
    localization_window_size: int
    measured_pressure_shape: tuple[int, int]
    nominal_pressure_shape: tuple[int, int]
    residual_vector_shape: tuple[int, ...]
    status: str
    message: str = ""


@dataclass(frozen=True)
class LocalizationCase:
    case_index: int
    leak_id: str
    true_pipe_id: str
    true_node: str
    leak_type: str
    alarm_time: pd.Timestamp
    r_mean: np.ndarray
    residual_window: np.ndarray
    gt_x: float
    gt_y: float


@dataclass(frozen=True)
class LocalizationSkip:
    leak_id: str
    reason: str


@dataclass(frozen=True)
class LocalizationRun:
    per_leak: pd.DataFrame
    summary: pd.DataFrame
    skipped: pd.DataFrame
    features: pd.DataFrame
    zone_predictions: pd.DataFrame
    xgb_availability: XGBoostAvailability | None = None


def load_cusum_events(detection_path: Path) -> pd.DataFrame:
    if not detection_path.exists():
        raise FileNotFoundError(f"Detection comparison CSV not found: {detection_path}")
    df = pd.read_csv(detection_path)
    required = {"method", "leak_id", "detected", "false_alarm_before_leak", "alarm_time"}
    missing = required.difference(df.columns)
    if missing:
        raise ValueError(f"Detection CSV missing columns: {sorted(missing)}")

    out = df.copy()
    out["method"] = out["method"].astype(str)
    out["detected"] = out["detected"].map(_to_bool)
    out["false_alarm_before_leak"] = out["false_alarm_before_leak"].map(_to_bool)
    out["alarm_time"] = pd.to_datetime(out["alarm_time"], errors="coerce")
    if "leak_start_time" in out.columns:
        out["leak_start_time"] = pd.to_datetime(out["leak_start_time"], errors="coerce")
    elif "start_time" in out.columns:
        out["leak_start_time"] = pd.to_datetime(out["start_time"], errors="coerce")
    else:
        out["leak_start_time"] = pd.NaT
    if "leak_end_time" in out.columns:
        out["leak_end_time"] = pd.to_datetime(out["leak_end_time"], errors="coerce")

    selected = out[
        (out["method"] == "CUSUM")
        & out["detected"]
        & ~out["false_alarm_before_leak"]
        & out["alarm_time"].notna()
    ].copy()
    selected["true_pipe_id"] = selected["leak_id"].astype(str)
    return selected.reset_index(drop=True)


def inspect_residual_windows(
    events: pd.DataFrame,
    cfg: HydroTwinConfig,
    baseline: NominalBaseline,
    scada_by_year: dict[int, PressureScada],
    limit: int = 2,
) -> list[ResidualWindowCheck]:
    checks: list[ResidualWindowCheck] = []
    leakage_by_id = {leak.link_id: leak for leak in cfg.leakages}

    for _, row in events.head(limit).iterrows():
        leak_id = str(row["leak_id"])
        alarm_time = pd.Timestamp(row["alarm_time"])
        leakage = leakage_by_id.get(leak_id)
        if leakage is None:
            checks.append(_failed_window_check(leak_id, row, "leak metadata not found in YAML"))
            continue
        scada = scada_by_year.get(leakage.year)
        if scada is None:
            checks.append(_failed_window_check(leak_id, row, f"SCADA not loaded for {leakage.year}"))
            continue

        try:
            leak_start = pd.Timestamp(leakage.start_time)
            leak_end = pd.Timestamp(leakage.end_time)
            demo_start = leak_start.normalize() - pd.Timedelta(days=1)
            demo_end = min(leak_end, pd.Timestamp(scada.time.iloc[-1]))
            mask = (scada.time >= demo_start) & (scada.time <= demo_end)
            measured = scada.pressures[mask.to_numpy(), :]
            demo_time = scada.time[mask].reset_index(drop=True)
            nominal = nominal_slice_for_time(demo_time, baseline.p_nominal, leakage.year)
            residual = _build_residual(measured, nominal)
            alarm_idx = _find_time_index(demo_time, alarm_time)
            loc_start = alarm_idx + 1
            loc_end = loc_start + N_WINDOW
            if loc_end > residual.shape[0]:
                raise ValueError("alarm exists, but no full 24h localization window is available")
            residual_window = residual[loc_start:loc_end, :]
            checks.append(
                ResidualWindowCheck(
                    leak_id=leak_id,
                    leak_start_time=leak_start,
                    alarm_time=alarm_time,
                    calibration_window_size=N_CALIB,
                    localization_window_size=residual_window.shape[0],
                    measured_pressure_shape=measured.shape,
                    nominal_pressure_shape=nominal.shape,
                    residual_vector_shape=residual_window.mean(axis=0).shape,
                    status="ok",
                )
            )
        except Exception as exc:
            checks.append(_failed_window_check(leak_id, row, str(exc)))
    return checks


def run_global_mas_localization(
    events: pd.DataFrame,
    cfg: HydroTwinConfig,
    baseline: NominalBaseline,
    scada_by_year: dict[int, PressureScada],
    sensitivity: SensitivityData,
    ltown: LTownModel,
    method: str,
    threshold_m: float,
    zones: ZoneMap | None = None,
    zone_predictions: ZonePredictionResult | None = None,
    xgb_model_path: Path | None = None,
) -> LocalizationRun:
    methods = _selected_methods(method)
    cases, skipped = build_localization_cases(events, cfg, baseline, scada_by_year, ltown)
    features = build_xgb_feature_frame(cases)
    if "xgb_hybrid" in methods and zone_predictions is None and xgb_model_path is not None:
        zone_predictions = predict_zone_topk(xgb_model_path, features, top_k=3)
    zone_pred = zone_predictions.predictions if zone_predictions else pd.DataFrame()
    zone_pred_by_case = _zone_predictions_by_case(zone_pred)
    zone_by_sens = _zone_by_sensitivity_junction(sensitivity, zones) if zones is not None else np.array([])

    rows: list[dict[str, object]] = []
    for case in cases:
        if "global" in methods:
            rows.append(
                evaluate_sensitivity_method(
                    case=case,
                    sensitivity=sensitivity,
                    ltown=ltown,
                    candidate_idx=np.arange(sensitivity.junction_count),
                    method_name="Global sensitivity",
                    threshold_m=threshold_m,
                )
            )
        if "mas" in methods:
            mas = build_mas_candidates(case.r_mean, sensitivity.s)
            rows.append(
                evaluate_sensitivity_method(
                    case=case,
                    sensitivity=sensitivity,
                    ltown=ltown,
                    candidate_idx=mas["candidate_idx"],
                    method_name="MAS sensitivity",
                    threshold_m=threshold_m,
                )
            )
        if "xgb_hybrid" in methods:
            if zone_predictions is None or not zone_predictions.availability.loadable:
                continue
            if zones is None:
                skipped.append(LocalizationSkip(case.leak_id, "XGBoost hybrid skipped: zone map is unavailable"))
                continue
            pred = zone_pred_by_case.get(case.case_index)
            if pred is None:
                skipped.append(LocalizationSkip(case.leak_id, "XGBoost hybrid skipped: missing zone prediction"))
                continue
            top3_zones = parse_zone_list(pred["xgb_top3_zones"])
            candidate_idx = np.flatnonzero(np.isin(zone_by_sens, top3_zones))
            true_zone = zones.junction_to_zone.get(case.true_node)
            top1_zone = int(pred["xgb_top1_zone"])
            rows.append(
                evaluate_sensitivity_method(
                    case=case,
                    sensitivity=sensitivity,
                    ltown=ltown,
                    candidate_idx=candidate_idx,
                    method_name="XGBoost top-3 zones + sensitivity",
                    threshold_m=threshold_m,
                    xgb_top1_zone=top1_zone,
                    xgb_top3_zones=pred["xgb_top3_zones"],
                    zone_hit_top1=(true_zone == top1_zone) if true_zone is not None else np.nan,
                    zone_hit_top3=(int(true_zone) in set(top3_zones)) if true_zone is not None else np.nan,
                )
            )

    per_leak = pd.DataFrame(rows)
    if not per_leak.empty:
        per_leak = per_leak[_per_leak_columns()]
    summary = summarize_localization(per_leak, threshold_m)
    skipped_frame = pd.DataFrame([{"leak_id": item.leak_id, "reason": item.reason} for item in skipped])
    return LocalizationRun(
        per_leak=per_leak,
        summary=summary,
        skipped=skipped_frame,
        features=features,
        zone_predictions=zone_pred,
        xgb_availability=zone_predictions.availability if zone_predictions else None,
    )


def build_localization_cases(
    events: pd.DataFrame,
    cfg: HydroTwinConfig,
    baseline: NominalBaseline,
    scada_by_year: dict[int, PressureScada],
    ltown: LTownModel,
) -> tuple[list[LocalizationCase], list[LocalizationSkip]]:
    cases: list[LocalizationCase] = []
    skipped: list[LocalizationSkip] = []
    leakage_by_id = {leak.link_id: leak for leak in cfg.leakages}

    for case_index, row in enumerate(events.itertuples(index=False), start=1):
        row_series = pd.Series(row._asdict())
        leak_id = str(row_series["leak_id"])
        leakage = leakage_by_id.get(leak_id)
        if leakage is None:
            skipped.append(LocalizationSkip(leak_id, "leak metadata not found in YAML"))
            continue
        scada = scada_by_year.get(leakage.year)
        if scada is None:
            skipped.append(LocalizationSkip(leak_id, f"SCADA not loaded for {leakage.year}"))
            continue
        try:
            alarm_time = pd.Timestamp(row_series["alarm_time"])
            residual_window = extract_residual_window(leakage, alarm_time, baseline, scada)
            r_mean = np.nanmean(residual_window, axis=0)
            if r_mean.shape != (33,):
                raise ValueError(f"r_mean must have shape (33,), got {r_mean.shape}")
            midpoint = ltown.get_pipe_midpoint(leak_id)
            true_node = nearest_junction_to_point(ltown, midpoint.x, midpoint.y)
            cases.append(
                LocalizationCase(
                    case_index=case_index,
                    leak_id=leak_id,
                    true_pipe_id=leak_id,
                    true_node=true_node,
                    leak_type=leakage.leak_type,
                    alarm_time=alarm_time,
                    r_mean=r_mean,
                    residual_window=residual_window,
                    gt_x=midpoint.x,
                    gt_y=midpoint.y,
                )
            )
        except Exception as exc:
            skipped.append(LocalizationSkip(leak_id, str(exc)))
    return cases, skipped


def extract_residual_window(
    leakage,
    alarm_time: pd.Timestamp,
    baseline: NominalBaseline,
    scada: PressureScada,
) -> np.ndarray:
    leak_start = pd.Timestamp(leakage.start_time)
    leak_end = pd.Timestamp(leakage.end_time)
    demo_start = leak_start.normalize() - pd.Timedelta(days=1)
    demo_end = min(leak_end, pd.Timestamp(scada.time.iloc[-1]))
    mask = (scada.time >= demo_start) & (scada.time <= demo_end)
    measured = scada.pressures[mask.to_numpy(), :]
    demo_time = scada.time[mask].reset_index(drop=True)
    nominal = nominal_slice_for_time(demo_time, baseline.p_nominal, leakage.year)
    residual = _build_residual(measured, nominal)
    alarm_idx = _find_time_index(demo_time, alarm_time)
    loc_start = alarm_idx + 1
    loc_end = loc_start + N_WINDOW
    if loc_end > residual.shape[0]:
        raise ValueError("alarm exists, but no full 24h localization window is available")
    return residual[loc_start:loc_end, :]


def evaluate_sensitivity_method(
    case: LocalizationCase,
    sensitivity: SensitivityData,
    ltown: LTownModel,
    candidate_idx: np.ndarray,
    method_name: str,
    threshold_m: float,
    xgb_top1_zone: int | float = np.nan,
    xgb_top3_zones: str = "",
    zone_hit_top1: bool | float = np.nan,
    zone_hit_top3: bool | float = np.nan,
) -> dict[str, object]:
    ranked_idx = rank_sensitivity_candidates(sensitivity.s_norm, case.r_mean, candidate_idx, TOP_NODE_K)
    top_nodes = [sensitivity.junction_ids[int(idx)] for idx in ranked_idx]
    distances = np.array(
        [distance_junction_to_point(ltown, node, case.gt_x, case.gt_y) for node in top_nodes],
        dtype=float,
    )
    top1_error = float(distances[0])
    top5_error = float(np.nanmin(distances[: min(5, len(distances))]))
    top10_error = float(np.nanmin(distances[: min(10, len(distances))]))
    return {
        "leak_id": case.leak_id,
        "true_pipe_id": case.true_pipe_id,
        "true_node": case.true_node,
        "leak_type": case.leak_type,
        "alarm_time": case.alarm_time,
        "method_name": method_name,
        "predicted_node": top_nodes[0],
        "top1_nodes": "|".join(top_nodes[:1]),
        "top5_nodes": "|".join(top_nodes[: min(5, len(top_nodes))]),
        "top10_nodes": "|".join(top_nodes[: min(10, len(top_nodes))]),
        "top1_error_m": top1_error,
        "top5_min_error_m": top5_error,
        "top10_min_error_m": top10_error,
        "candidate_count": int(len(np.unique(candidate_idx))),
        "xgb_top1_zone": xgb_top1_zone,
        "xgb_top3_zones": xgb_top3_zones,
        "zone_hit_top1": zone_hit_top1,
        "zone_hit_top3": zone_hit_top3,
        "top1_success_300m": top1_error <= threshold_m,
        "top5_success_300m": top5_error <= threshold_m,
        "top10_success_300m": top10_error <= threshold_m,
    }


def rank_sensitivity_candidates(
    s_norm: np.ndarray,
    r_mean: np.ndarray,
    candidate_idx: np.ndarray,
    top_k: int,
) -> np.ndarray:
    candidate_idx = np.asarray(candidate_idx, dtype=int).reshape(-1)
    candidate_idx = candidate_idx[(candidate_idx >= 0) & (candidate_idx < s_norm.shape[1])]
    _, unique_positions = np.unique(candidate_idx, return_index=True)
    candidate_idx = candidate_idx[np.sort(unique_positions)]
    if candidate_idx.size == 0:
        raise ValueError("candidate list is empty")
    r_norm = r_mean / (np.linalg.norm(r_mean) + 1e-9)
    correlations = s_norm.T @ r_norm
    order = np.argsort(-correlations[candidate_idx], kind="mergesort")
    return candidate_idx[order][: min(top_k, candidate_idx.size)]


def build_mas_candidates(
    r_mean: np.ndarray,
    s: np.ndarray,
    coverage: float = MAS_COVERAGE,
    min_sensors: int = MAS_MIN_SENSORS,
    max_sensors: int = MAS_MAX_SENSORS,
    candidate_q: float = MAS_CANDIDATE_Q,
    min_candidates: int = MAS_MIN_CANDIDATES,
    max_candidates: int = MAS_MAX_CANDIDATES,
) -> dict[str, np.ndarray]:
    sensor_mag = np.abs(r_mean.reshape(-1))
    contribution = sensor_mag / (np.sum(sensor_mag) + 1e-9)
    sensor_order = np.argsort(-sensor_mag, kind="mergesort")
    cumulative = np.cumsum(contribution[sensor_order])
    reached = np.flatnonzero(cumulative >= coverage)
    n_mas = int(reached[0] + 1) if len(reached) else min_sensors
    n_mas = min(max(n_mas, min_sensors), max_sensors)
    sensor_idx = sensor_order[:n_mas]

    weights = contribution[sensor_idx]
    weights = weights / (np.sum(weights) + 1e-9)
    s_abs = np.abs(s[sensor_idx, :])
    s_scaled = s_abs / (np.max(s_abs, axis=1, keepdims=True) + 1e-9)
    candidate_score = weights @ s_scaled
    score_order = np.argsort(-candidate_score, kind="mergesort")
    q_score = float(np.quantile(candidate_score, candidate_q))
    candidate_idx = np.flatnonzero(candidate_score >= q_score)
    # MATLAB's quantile boundary keeps 78 of 782 nodes for q=0.90 in the
    # reference outputs. NumPy includes one extra boundary node, so cap the
    # threshold set to the same top-tail size when needed.
    matlab_tail_count = int(np.floor((1.0 - candidate_q) * candidate_score.size))
    if candidate_idx.size > matlab_tail_count >= min_candidates:
        candidate_idx = score_order[:matlab_tail_count]

    if candidate_idx.size > max_candidates:
        candidate_idx = score_order[:max_candidates]
    elif candidate_idx.size < min_candidates:
        candidate_idx = score_order[: min(min_candidates, score_order.size)]
    else:
        local_order = np.argsort(-candidate_score[candidate_idx], kind="mergesort")
        candidate_idx = candidate_idx[local_order]

    return {
        "sensor_idx": sensor_idx,
        "candidate_idx": candidate_idx.astype(int),
        "candidate_score": candidate_score[candidate_idx],
    }


def build_xgb_feature_frame(cases: list[LocalizationCase]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for case in cases:
        row: dict[str, object] = {
            "feature_case_index": case.case_index,
            "leak_id": case.leak_id,
        }
        features = extract_residual_features(case.residual_window)
        row.update(features)
        rows.append(row)
    return pd.DataFrame(rows)


def extract_residual_features(residual_window: np.ndarray) -> dict[str, float]:
    r_mean = np.nanmean(residual_window, axis=0)
    r_std = np.nanstd(residual_window, axis=0, ddof=1)
    r_max = np.nanmax(residual_window, axis=0)
    r_norm = r_mean / (np.linalg.norm(r_mean) + 1e-9)
    values = np.concatenate([r_mean, r_std, r_max, r_norm])
    names = make_feature_names(residual_window.shape[1])
    return {name: float(value) for name, value in zip(names, values)}


def make_feature_names(n_sensors: int) -> list[str]:
    return [
        f"{prefix}_{sensor_idx}"
        for prefix in ("r_mean", "r_std", "r_max", "r_norm")
        for sensor_idx in range(1, n_sensors + 1)
    ]


def summarize_localization(per_leak: pd.DataFrame, threshold_m: float) -> pd.DataFrame:
    columns = [
        "method_name",
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
    if per_leak.empty:
        return pd.DataFrame(columns=columns)
    rows = []
    for method_name, group in per_leak.groupby("method_name", sort=False):
        n = int(len(group))
        top1 = int((group["top1_error_m"] <= threshold_m).sum())
        top5 = int((group["top5_min_error_m"] <= threshold_m).sum())
        top10 = int((group["top10_min_error_m"] <= threshold_m).sum())
        rows.append(
            {
                "method_name": method_name,
                "evaluated_leaks": n,
                "top1_within_300m": top1,
                "top5_within_300m": top5,
                "top10_within_300m": top10,
                "top1_rate": top1 / max(1, n),
                "top5_rate": top5 / max(1, n),
                "top10_rate": top10 / max(1, n),
                "median_top1_error_m": float(group["top1_error_m"].median()),
                "mean_top1_error_m": float(group["top1_error_m"].mean()),
                "mean_candidate_count": float(group["candidate_count"].mean()),
            }
        )
    return pd.DataFrame(rows, columns=columns)


def residual_checks_to_frame(checks: list[ResidualWindowCheck]) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "leak_id": check.leak_id,
                "leak_start_time": check.leak_start_time,
                "alarm_time": check.alarm_time,
                "calibration_window_size": check.calibration_window_size,
                "localization_window_size": check.localization_window_size,
                "measured_pressure_shape": _shape_text(check.measured_pressure_shape),
                "nominal_pressure_shape": _shape_text(check.nominal_pressure_shape),
                "residual_vector_shape": _shape_text(check.residual_vector_shape),
                "status": check.status,
                "message": check.message,
            }
            for check in checks
        ]
    )


def nearest_junction_to_point(ltown: LTownModel, x: float, y: float) -> str:
    coords = ltown.junction_coordinates
    distances = ((coords["x"] - x) ** 2 + (coords["y"] - y) ** 2) ** 0.5
    idx = int(distances.idxmin())
    return str(coords.loc[idx, "junction_id"])


def distance_junction_to_point(ltown: LTownModel, junction_id: str, x: float, y: float) -> float:
    row = ltown.junction_coordinates.loc[ltown.junction_coordinates["junction_id"] == junction_id]
    if row.empty:
        raise KeyError(f"Junction ID not found in coordinate table: {junction_id}")
    return float(np.hypot(float(row.iloc[0]["x"]) - x, float(row.iloc[0]["y"]) - y))


def parse_zone_list(value: object) -> np.ndarray:
    zones = []
    for part in str(value).split("|"):
        try:
            zones.append(int(float(part)))
        except ValueError:
            continue
    return np.array(list(dict.fromkeys(zones)), dtype=int)


def _build_residual(measured: np.ndarray, nominal: np.ndarray) -> np.ndarray:
    if measured.shape != nominal.shape:
        raise ValueError(f"measured/nominal shape mismatch: {measured.shape} vs {nominal.shape}")
    if measured.shape[0] < N_CALIB + N_WINDOW:
        raise ValueError(f"not enough samples for calibration + localization: {measured.shape[0]}")
    bias = np.nanmean(measured[:N_CALIB, :] - nominal[:N_CALIB, :], axis=0)
    return (nominal + bias) - measured


def _selected_methods(method: str) -> set[str]:
    if method == "all":
        return {"global", "mas", "xgb_hybrid"}
    return {method}


def _per_leak_columns() -> list[str]:
    return [
        "leak_id",
        "true_pipe_id",
        "true_node",
        "leak_type",
        "alarm_time",
        "method_name",
        "predicted_node",
        "top1_error_m",
        "top5_min_error_m",
        "top10_min_error_m",
        "candidate_count",
        "xgb_top1_zone",
        "xgb_top3_zones",
        "zone_hit_top1",
        "zone_hit_top3",
        "top1_success_300m",
        "top5_success_300m",
        "top10_success_300m",
        "top1_nodes",
        "top5_nodes",
        "top10_nodes",
    ]


def _zone_predictions_by_case(zone_pred: pd.DataFrame) -> dict[int, dict[str, object]]:
    if zone_pred.empty or "feature_case_index" not in zone_pred.columns:
        return {}
    return {
        int(row["feature_case_index"]): row.to_dict()
        for _, row in zone_pred.iterrows()
    }


def _zone_by_sensitivity_junction(sensitivity: SensitivityData, zones: ZoneMap | None) -> np.ndarray:
    if zones is None:
        return np.array([], dtype=int)
    missing = [junction_id for junction_id in sensitivity.junction_ids if junction_id not in zones.junction_to_zone]
    if missing:
        raise ValueError(f"Zone map missing sensitivity junctions. First missing: {missing[0]}")
    return np.array([zones.junction_to_zone[junction_id] for junction_id in sensitivity.junction_ids], dtype=int)


def _find_time_index(time: pd.Series, target_time: pd.Timestamp) -> int:
    exact = np.flatnonzero(time.to_numpy(dtype="datetime64[ns]") == np.datetime64(target_time))
    if len(exact):
        return int(exact[0])
    deltas = np.abs((time - target_time).dt.total_seconds().to_numpy() / 60.0)
    idx = int(np.nanargmin(deltas))
    if deltas[idx] > 2.6:
        raise ValueError("alarm time is not aligned with the 5-minute SCADA timeline")
    return idx


def _failed_window_check(leak_id: str, row: pd.Series, message: str) -> ResidualWindowCheck:
    return ResidualWindowCheck(
        leak_id=leak_id,
        leak_start_time=pd.Timestamp(row.get("leak_start_time", pd.NaT)),
        alarm_time=pd.Timestamp(row.get("alarm_time", pd.NaT)),
        calibration_window_size=0,
        localization_window_size=0,
        measured_pressure_shape=(0, 0),
        nominal_pressure_shape=(0, 0),
        residual_vector_shape=(0,),
        status="failed",
        message=message,
    )


def _shape_text(shape: tuple[int, ...]) -> str:
    return "x".join(str(part) for part in shape)


def _to_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if pd.isna(value):
        return False
    if isinstance(value, (int, float, np.integer, np.floating)):
        return bool(value)
    return str(value).strip().lower() in {"true", "1", "yes"}
