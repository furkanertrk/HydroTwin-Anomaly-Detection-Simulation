"""Localization entry point for the Python port."""

from __future__ import annotations

import argparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run leak localization comparisons.")
    parser.add_argument("--detector", default="CUSUM", help="Detector rows to use from detection outputs.")
    parser.add_argument("--top-k", type=int, default=10, help="Number of node candidates to report.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(f"Localization skeleton ready: detector={args.detector}, top_k={args.top_k}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
