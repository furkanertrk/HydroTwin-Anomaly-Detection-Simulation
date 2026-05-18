"""Plot generation for detection and localization outputs."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from .detection import ResidualCase, detect_cusum


def plot_demo_residual_norm(case: ResidualCase, out_path: Path) -> None:
    """Plot residual norm and the CUSUM alarm for one usable case."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if not case.usable or len(case.res_norm) == 0:
        raise ValueError("Cannot plot residual norm for an unusable residual case.")

    result = detect_cusum(case.res_norm)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(12, 4.8))
    ax.plot(pd.to_datetime(case.time), case.res_norm, linewidth=1.3, label="Residual norm")
    if result.alarm_idx is not None:
        alarm_time = pd.Timestamp(case.time.iloc[result.alarm_idx])
        ax.axvline(alarm_time, color="tab:orange", linestyle=":", linewidth=1.2, label="CUSUM alarm")
    ax.axvline(pd.Timestamp(case.leakage.start_time), color="tab:green", linestyle="-.", linewidth=1.2, label="Leak start")
    ax.set_title(f"Residual norm demo - {case.leakage.link_id}")
    ax.set_xlabel("Time")
    ax.set_ylabel("Residual norm")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_localization_error_histogram(per_leak: pd.DataFrame, out_path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8.5, 4.8))
    for method_name, group in per_leak.groupby("method_name", sort=False):
        ax.hist(group["top1_error_m"], bins=16, alpha=0.55, label=method_name)
    ax.axvline(300, color="tab:green", linestyle="--", linewidth=1.2, label="300 m")
    ax.set_title("Localization top-1 error distribution")
    ax.set_xlabel("Top-1 error (m)")
    ax.set_ylabel("Leak count")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_top1_error_by_method(summary: pd.DataFrame, out_path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8.5, 4.8))
    palette = ["#4C78A8", "#F58518", "#54A24B", "#B279A2", "#E45756"]
    colors = [palette[idx % len(palette)] for idx in range(len(summary))]
    ax.bar(summary["method_name"], summary["median_top1_error_m"], color=colors)
    ax.axhline(300, color="tab:green", linestyle="--", linewidth=1.2, label="300 m")
    ax.set_title("Median top-1 localization error")
    ax.set_xlabel("Method")
    ax.set_ylabel("Median top-1 error (m)")
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(loc="best")
    fig.autofmt_xdate(rotation=15)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_xgb_zone_hit_vs_error(per_leak: pd.DataFrame, out_path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out_path.parent.mkdir(parents=True, exist_ok=True)
    xgb = per_leak[per_leak["method_name"] == "XGBoost top-3 zones + sensitivity"].copy()
    if xgb.empty:
        fig, ax = plt.subplots(figsize=(8, 4.5))
        ax.text(0.5, 0.5, "XGBoost hybrid rows unavailable", ha="center", va="center")
        ax.set_axis_off()
        fig.tight_layout()
        fig.savefig(out_path, dpi=150)
        plt.close(fig)
        return

    xgb["zone_hit_top3_bool"] = xgb["zone_hit_top3"].map(
        lambda value: str(value).strip().lower() in {"true", "1", "1.0"}
    )
    colors = xgb["zone_hit_top3_bool"].map({True: "#4C78A8", False: "#E45756"})
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.scatter(range(len(xgb)), xgb["top1_error_m"], c=colors, s=42, alpha=0.85)
    ax.axhline(300, color="tab:green", linestyle="--", linewidth=1.2, label="300 m")
    ax.set_title("XGBoost zone hit vs top-1 error")
    ax.set_xlabel("Evaluated leak index")
    ax.set_ylabel("Top-1 error (m)")
    ax.grid(True, alpha=0.25)
    ax.scatter([], [], c="#4C78A8", label="Top-3 zone hit")
    ax.scatter([], [], c="#E45756", label="Top-3 zone miss")
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_sensitivity_strength_map(zone_map: pd.DataFrame, analysis: pd.DataFrame, out_path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8, 6))
    strength_col = "sensitivity_strength"
    scatter = ax.scatter(
        zone_map["x"],
        zone_map["y"],
        c=zone_map[strength_col],
        s=16,
        cmap="viridis",
        alpha=0.85,
    )
    leak_nodes = analysis[["leak_id", "true_node"]].drop_duplicates()
    leaks = leak_nodes.merge(zone_map, left_on="true_node", right_on="junction_id", how="inner")
    if not leaks.empty:
        ax.scatter(leaks["x"], leaks["y"], s=46, facecolors="none", edgecolors="red", linewidths=1.2)
    ax.set_title("Sensitivity strength map")
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.axis("equal")
    ax.grid(True, alpha=0.25)
    fig.colorbar(scatter, ax=ax, label="Sensitivity strength")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
