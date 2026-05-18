"""XGBoost zone model availability checks."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


DEFAULT_TOP_K = 3


@dataclass(frozen=True)
class XGBoostAvailability:
    path: Path
    exists: bool
    loadable: bool
    model_class: str = ""
    feature_count: int | None = None
    class_count: int | None = None
    message: str = ""


@dataclass(frozen=True)
class ZonePredictionResult:
    predictions: pd.DataFrame
    availability: XGBoostAvailability


def check_xgb_model(path: Path) -> XGBoostAvailability:
    """Check whether the existing zone model can be loaded without predicting."""
    if not path.exists():
        return XGBoostAvailability(
            path=path,
            exists=False,
            loadable=False,
            message="XGBoost unavailable, will fallback to Global/MAS: model file is missing.",
        )
    try:
        from joblib import load

        obj = load(path)
        model = obj.get("model") if isinstance(obj, dict) else obj
        feature_names = obj.get("feature_names", []) if isinstance(obj, dict) else []
        class_labels = obj.get("class_labels", []) if isinstance(obj, dict) else []
        return XGBoostAvailability(
            path=path,
            exists=True,
            loadable=True,
            model_class=f"{model.__class__.__module__}.{model.__class__.__name__}",
            feature_count=len(feature_names) if feature_names is not None else None,
            class_count=len(class_labels) if class_labels is not None else None,
            message="XGBoost model is available for later phases.",
        )
    except Exception as exc:
        return XGBoostAvailability(
            path=path,
            exists=True,
            loadable=False,
            message=f"XGBoost unavailable, will fallback to Global/MAS: {exc}",
        )


def predict_zone_topk(
    model_path: Path,
    features: pd.DataFrame,
    top_k: int = DEFAULT_TOP_K,
) -> ZonePredictionResult:
    """Predict top-k zones using the existing trained bundle; never retrains."""
    availability = check_xgb_model(model_path)
    if not availability.loadable:
        return ZonePredictionResult(predictions=pd.DataFrame(), availability=availability)

    from joblib import load

    bundle = load(model_path)
    model = bundle["model"] if isinstance(bundle, dict) else bundle
    feature_names = list(bundle.get("feature_names", [])) if isinstance(bundle, dict) else []
    class_labels = np.asarray(bundle.get("class_labels", []), dtype=int) if isinstance(bundle, dict) else np.array([])
    if len(feature_names) != 132:
        return ZonePredictionResult(
            predictions=pd.DataFrame(),
            availability=XGBoostAvailability(
                path=model_path,
                exists=True,
                loadable=False,
                model_class=f"{model.__class__.__module__}.{model.__class__.__name__}",
                feature_count=len(feature_names),
                class_count=len(class_labels),
                message=f"XGBoost unavailable, will fallback to Global/MAS: expected 132 features, got {len(feature_names)}.",
            ),
        )

    missing = [name for name in feature_names if name not in features.columns]
    if missing:
        return ZonePredictionResult(
            predictions=pd.DataFrame(),
            availability=XGBoostAvailability(
                path=model_path,
                exists=True,
                loadable=False,
                model_class=f"{model.__class__.__module__}.{model.__class__.__name__}",
                feature_count=len(feature_names),
                class_count=len(class_labels),
                message=f"XGBoost unavailable, will fallback to Global/MAS: missing feature columns {missing[:5]}.",
            ),
        )

    x = features[feature_names].to_numpy(dtype=np.float32)
    if not np.isfinite(x).all():
        return ZonePredictionResult(
            predictions=pd.DataFrame(),
            availability=XGBoostAvailability(
                path=model_path,
                exists=True,
                loadable=False,
                model_class=f"{model.__class__.__module__}.{model.__class__.__name__}",
                feature_count=len(feature_names),
                class_count=len(class_labels),
                message="XGBoost unavailable, will fallback to Global/MAS: feature matrix contains NaN/Inf.",
            ),
        )

    proba = model.predict_proba(x)
    top_labels, top_probs = _topk_from_proba(model, proba, class_labels, top_k)
    output = features[[col for col in ("feature_case_index", "leak_id") if col in features.columns]].copy()
    output["xgb_top1_zone"] = top_labels[:, 0]
    output["xgb_top3_zones"] = ["|".join(str(int(zone)) for zone in row) for row in top_labels]
    output["xgb_top3_probabilities"] = ["|".join(f"{prob:.6f}" for prob in row) for row in top_probs]
    return ZonePredictionResult(predictions=output, availability=availability)


def _topk_from_proba(
    model: object,
    proba: np.ndarray,
    class_labels: np.ndarray,
    top_k: int,
) -> tuple[np.ndarray, np.ndarray]:
    model_classes = getattr(model, "classes_", np.arange(proba.shape[1]))
    model_classes = np.asarray(model_classes, dtype=int)
    mapped_labels = class_labels[model_classes]
    order = np.argsort(proba, axis=1)[:, ::-1][:, :top_k]
    top_labels = mapped_labels[order]
    top_probs = np.take_along_axis(proba, order, axis=1)
    return top_labels, top_probs
