"""Regenerate Python localization and detection figures from existing outputs."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
PYTHON_PORT_DIR = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate HydroTwin Python figures from current results.")
    parser.add_argument("--threshold-m", type=float, default=300.0)
    parser.add_argument("--include-detection-demo", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.include_detection_demo:
        subprocess.run(
            [
                sys.executable,
                str(PYTHON_PORT_DIR / "run_detection.py"),
                "--method",
                "all",
                "--year",
                "both",
                "--plot-demo",
            ],
            cwd=ROOT_DIR,
            check=True,
        )
    subprocess.run(
        [
            sys.executable,
            str(PYTHON_PORT_DIR / "run_error_analysis.py"),
            "--plot",
            "--threshold-m",
            str(args.threshold_m),
        ],
        cwd=ROOT_DIR,
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
