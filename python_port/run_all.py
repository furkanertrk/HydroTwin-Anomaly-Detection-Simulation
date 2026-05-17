"""Run the HydroTwin Python pipeline.

Phase 1 placeholder: the pipeline skeleton exists, but algorithms are not
ported yet.
"""

from __future__ import annotations

import argparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the HydroTwin Python pipeline.")
    parser.add_argument("--stage", choices=["all", "detection", "localization", "analysis", "visualization"], default="all")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(f"Python port skeleton ready. Requested stage: {args.stage}")
    print("Algorithm implementation starts in the next phase.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
