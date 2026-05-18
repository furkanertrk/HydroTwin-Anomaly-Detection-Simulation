"""Run the Python-only HydroTwin detection and localization pipeline."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
PYTHON_PORT_DIR = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run detection, localization, error analysis, and plots.")
    parser.add_argument("--compare-existing", action="store_true", help="Compare Python outputs with MATLAB CSV outputs.")
    parser.add_argument("--plot", action="store_true", help="Generate final PNG figures.")
    parser.add_argument("--threshold-m", type=float, default=300.0, help="Localization success threshold in meters.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_step(
        [
            sys.executable,
            str(PYTHON_PORT_DIR / "run_detection.py"),
            "--method",
            "all",
            "--year",
            "both",
            *(["--compare-existing"] if args.compare_existing else []),
            *(["--plot-demo"] if args.plot else []),
        ]
    )
    run_step(
        [
            sys.executable,
            str(PYTHON_PORT_DIR / "run_localization.py"),
            "--method",
            "all",
            "--use-python-detection",
            "--threshold-m",
            str(args.threshold_m),
            *(["--compare-existing"] if args.compare_existing else []),
            *(["--plot"] if args.plot else []),
        ]
    )
    run_step(
        [
            sys.executable,
            str(PYTHON_PORT_DIR / "run_error_analysis.py"),
            "--threshold-m",
            str(args.threshold_m),
            *(["--compare-existing"] if args.compare_existing else []),
            *(["--plot"] if args.plot else []),
        ]
    )
    print("Pipeline completed.")
    return 0


def run_step(command: list[str]) -> None:
    display = " ".join(f'"{part}"' if " " in part else part for part in command)
    print(f"\n$ {display}")
    subprocess.run(command, cwd=ROOT_DIR, check=True)


if __name__ == "__main__":
    raise SystemExit(main())
