#!/usr/bin/env python
"""Train or run the HydroTwin XGBoost zone localizer.

The model is trained on synthetic sensitivity-derived residual features, not on
the 33 real BattLeDIM leaks. Its role is zone-level search-space reduction; the
final leak node is still selected by the MATLAB sensitivity localizer.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


FEATURE_PREFIXES = ("r_mean_", "r_std_", "r_max_", "r_norm_")
DEFAULT_TOP_K = 3


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def feature_sort_key(name: str) -> tuple[int, int]:
    for prefix_index, prefix in enumerate(FEATURE_PREFIXES):
        if name.startswith(prefix):
            try:
                sensor_index = int(name[len(prefix) :])
            except ValueError:
                sensor_index = 10**9
            return prefix_index, sensor_index
    return 10**9, 10**9


def find_feature_columns(df: pd.DataFrame) -> list[str]:
    feature_cols = [
        c for c in df.columns if any(c.startswith(prefix) for prefix in FEATURE_PREFIXES)
    ]
    feature_cols = sorted(feature_cols, key=feature_sort_key)
    if len(feature_cols) != 132:
        raise ValueError(f"Expected 132 feature columns, found {len(feature_cols)}.")
    return feature_cols


def require_training_packages() -> None:
    missing = []
    for pkg in ("sklearn", "joblib"):
        try:
            __import__(pkg)
        except Exception:
            missing.append(pkg)
    if missing:
        raise RuntimeError(
            "Missing Python ML dependencies: "
            + ", ".join(missing)
            + ". Install with: python -m pip install xgboost scikit-learn joblib"
        )


def build_model(n_classes: int, random_seed: int) -> tuple[Any, str]:
    require_training_packages()

    try:
        from xgboost import XGBClassifier

        model = XGBClassifier(
            n_estimators=350,
            max_depth=5,
            learning_rate=0.05,
            subsample=0.90,
            colsample_bytree=0.90,
            objective="multi:softprob",
            eval_metric="mlogloss",
            num_class=n_classes,
            tree_method="hist",
            random_state=random_seed,
            n_jobs=-1,
        )
        return model, "xgboost.XGBClassifier"
    except Exception as xgb_error:
        print(f"XGBoost unavailable, falling back to sklearn: {xgb_error}", file=sys.stderr)

    try:
        from sklearn.ensemble import HistGradientBoostingClassifier

        model = HistGradientBoostingClassifier(
            max_iter=250,
            learning_rate=0.06,
            max_leaf_nodes=31,
            l2_regularization=0.001,
            random_state=random_seed,
        )
        return model, "sklearn.HistGradientBoostingClassifier"
    except Exception as hgb_error:
        print(f"HistGradientBoosting unavailable, falling back to RandomForest: {hgb_error}", file=sys.stderr)

    from sklearn.ensemble import RandomForestClassifier

    model = RandomForestClassifier(
        n_estimators=350,
        max_depth=None,
        min_samples_leaf=2,
        random_state=random_seed,
        n_jobs=-1,
        class_weight="balanced_subsample",
    )
    return model, "sklearn.RandomForestClassifier"


def grouped_zone_split(
    df: pd.DataFrame, test_size: float, random_seed: int
) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(random_seed)
    train_nodes: list[int] = []
    test_nodes: list[int] = []
    node_zone = df[["true_junction_index", "true_zone_id"]].drop_duplicates()

    for _, group in node_zone.groupby("true_zone_id"):
        nodes = group["true_junction_index"].to_numpy(copy=True)
        rng.shuffle(nodes)
        if len(nodes) <= 1:
            train_nodes.extend(nodes.tolist())
            continue
        n_test = max(1, int(round(len(nodes) * test_size)))
        n_test = min(n_test, len(nodes) - 1)
        test_nodes.extend(nodes[:n_test].tolist())
        train_nodes.extend(nodes[n_test:].tolist())

    train_nodes_set = set(train_nodes)
    test_nodes_set = set(test_nodes)
    overlap = train_nodes_set.intersection(test_nodes_set)
    if overlap:
        raise RuntimeError(f"Grouped split failed; {len(overlap)} nodes overlap.")

    train_mask = df["true_junction_index"].isin(train_nodes_set).to_numpy()
    test_mask = df["true_junction_index"].isin(test_nodes_set).to_numpy()
    return train_mask, test_mask


def topk_from_proba(model: Any, proba: np.ndarray, class_labels: np.ndarray, top_k: int) -> tuple[np.ndarray, np.ndarray]:
    model_classes = getattr(model, "classes_", np.arange(proba.shape[1]))
    model_classes = np.asarray(model_classes, dtype=int)
    mapped_labels = class_labels[model_classes]

    order = np.argsort(proba, axis=1)[:, ::-1][:, :top_k]
    top_labels = mapped_labels[order]
    top_probs = np.take_along_axis(proba, order, axis=1)
    return top_labels, top_probs


def train(args: argparse.Namespace) -> None:
    from joblib import dump
    from sklearn.metrics import classification_report, confusion_matrix

    dataset_path = Path(args.dataset)
    if not dataset_path.is_absolute():
        dataset_path = project_root() / dataset_path
    if not dataset_path.exists():
        raise FileNotFoundError(f"Dataset not found: {dataset_path}")

    df = pd.read_csv(dataset_path)
    feature_cols = find_feature_columns(df)
    required = {"true_junction_index", "true_zone_id"}
    missing = required.difference(df.columns)
    if missing:
        raise ValueError(f"Dataset missing required columns: {sorted(missing)}")

    if df[feature_cols].isna().any().any():
        raise ValueError("Dataset contains NaN feature values.")

    class_labels = np.array(sorted(df["true_zone_id"].unique()), dtype=int)
    label_to_index = {label: i for i, label in enumerate(class_labels)}
    y = df["true_zone_id"].map(label_to_index).to_numpy(dtype=int)
    X = df[feature_cols].to_numpy(dtype=np.float32)

    train_mask, test_mask = grouped_zone_split(df, args.test_size, args.random_seed)
    if np.intersect1d(
        df.loc[train_mask, "true_junction_index"].unique(),
        df.loc[test_mask, "true_junction_index"].unique(),
    ).size:
        raise RuntimeError("Train/test split has junction overlap.")

    model, model_type = build_model(len(class_labels), args.random_seed)
    model.fit(X[train_mask], y[train_mask])

    y_pred = model.predict(X[test_mask])
    proba = model.predict_proba(X[test_mask])
    top_labels, top_probs = topk_from_proba(model, proba, class_labels, args.top_k)

    y_true_labels = class_labels[y[test_mask]]
    y_pred_labels = class_labels[np.asarray(y_pred, dtype=int)]
    top1_accuracy = float(np.mean(y_pred_labels == y_true_labels))
    top3_accuracy = float(np.mean([truth in row for truth, row in zip(y_true_labels, top_labels)]))

    labels = class_labels.tolist()
    cm = confusion_matrix(y_true_labels, y_pred_labels, labels=labels)
    report = classification_report(
        y_true_labels,
        y_pred_labels,
        labels=labels,
        output_dict=True,
        zero_division=0,
    )

    metrics = {
        "model_type": model_type,
        "dataset": str(dataset_path),
        "n_rows": int(len(df)),
        "n_features": int(len(feature_cols)),
        "n_classes": int(len(class_labels)),
        "train_rows": int(train_mask.sum()),
        "test_rows": int(test_mask.sum()),
        "train_junctions": int(df.loc[train_mask, "true_junction_index"].nunique()),
        "test_junctions": int(df.loc[test_mask, "true_junction_index"].nunique()),
        "top1_zone_accuracy": top1_accuracy,
        "top3_zone_accuracy": top3_accuracy,
        "class_labels": labels,
        "confusion_matrix": cm.tolist(),
        "classification_report": report,
    }

    predictions = df.loc[test_mask, [c for c in df.columns if c not in feature_cols]].copy()
    predictions["pred_zone"] = y_pred_labels
    predictions["top1_correct"] = predictions["pred_zone"].to_numpy() == y_true_labels
    predictions["top3_zones"] = ["|".join(str(int(z)) for z in row) for row in top_labels]
    predictions["top3_probabilities"] = ["|".join(f"{p:.6f}" for p in row) for row in top_probs]
    predictions["top3_correct"] = [truth in row for truth, row in zip(y_true_labels, top_labels)]

    model_out = resolve_output(args.model_out)
    metrics_out = resolve_output(args.metrics_out)
    predictions_out = resolve_output(args.predictions_out)
    model_out.parent.mkdir(parents=True, exist_ok=True)

    dump(
        {
            "model": model,
            "model_type": model_type,
            "feature_names": feature_cols,
            "class_labels": class_labels,
            "top_k_default": args.top_k,
        },
        model_out,
    )
    metrics_out.write_text(json.dumps(to_jsonable(metrics), indent=2), encoding="utf-8")
    predictions.to_csv(predictions_out, index=False)

    print("\nHydroTwin zone localizer trained")
    print(f"  Model: {model_type}")
    print(f"  Top-1 zone accuracy: {top1_accuracy:.4f}")
    print(f"  Top-{args.top_k} zone accuracy: {top3_accuracy:.4f}")
    print(f"  Saved model: {model_out}")
    print(f"  Saved metrics: {metrics_out}")
    print(f"  Saved predictions: {predictions_out}")


def predict(args: argparse.Namespace) -> None:
    try:
        from joblib import load
    except Exception as exc:
        raise RuntimeError(
            "joblib is required for prediction. Install with: python -m pip install joblib"
        ) from exc

    model_path = resolve_output(args.model_out)
    if not model_path.exists():
        raise FileNotFoundError(f"Model file not found: {model_path}")

    input_path = Path(args.predict)
    if not input_path.is_absolute():
        input_path = project_root() / input_path
    if not input_path.exists():
        raise FileNotFoundError(f"Prediction input not found: {input_path}")

    bundle = load(model_path)
    model = bundle["model"]
    feature_cols = list(bundle["feature_names"])
    class_labels = np.asarray(bundle["class_labels"], dtype=int)

    df = pd.read_csv(input_path)
    missing = [c for c in feature_cols if c not in df.columns]
    if missing:
        raise ValueError(f"Prediction input is missing feature columns: {missing[:5]}")
    if df[feature_cols].isna().any().any():
        raise ValueError("Prediction input contains NaN feature values.")

    X = df[feature_cols].to_numpy(dtype=np.float32)
    proba = model.predict_proba(X)
    top_labels, top_probs = topk_from_proba(model, proba, class_labels, args.top_k)

    output = df[[c for c in df.columns if c not in feature_cols]].copy()
    output["xgb_top1_zone"] = top_labels[:, 0]
    output["xgb_top3_zones"] = ["|".join(str(int(z)) for z in row) for row in top_labels]
    output["xgb_top3_probabilities"] = ["|".join(f"{p:.6f}" for p in row) for row in top_probs]

    out_path = Path(args.predict_output)
    if not out_path.is_absolute():
        out_path = project_root() / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(out_path, index=False)
    print(f"Saved predictions: {out_path}")


def resolve_output(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return project_root() / path


def to_jsonable(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): to_jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [to_jsonable(v) for v in value]
    if isinstance(value, tuple):
        return [to_jsonable(v) for v in value]
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.floating,)):
        if math.isnan(float(value)):
            return None
        return float(value)
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train or run the HydroTwin XGBoost-assisted zone localizer."
    )
    parser.add_argument("--dataset", default="data/ml_localization_dataset.csv")
    parser.add_argument("--model-out", default="data/xgb_zone_model.pkl")
    parser.add_argument("--metrics-out", default="data/xgb_zone_metrics.json")
    parser.add_argument("--predictions-out", default="data/xgb_zone_predictions.csv")
    parser.add_argument("--test-size", type=float, default=0.20)
    parser.add_argument("--random-seed", type=int, default=42)
    parser.add_argument("--top-k", type=int, default=DEFAULT_TOP_K)
    parser.add_argument("--predict", help="CSV file to score instead of training.")
    parser.add_argument("--predict-output", default="data/xgb_hybrid_zone_predictions.csv")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.predict:
            predict(args)
        else:
            train(args)
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
