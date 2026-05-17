"""Plot generation for detection outputs."""

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
