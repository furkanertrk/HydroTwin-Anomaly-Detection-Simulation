"""Detection entry point for the HydroTwin Python port."""

from __future__ import annotations

import argparse

from src.config import load_config
from src.data_loader import load_nominal_baseline, load_pressure_scada, read_leak_metadata_csv
from src.detection import compare_detectors, compare_with_existing, write_detection_outputs
from src.paths import DATA_DIR, FIGURES_DIR, RESULTS_DIR
from src.plots import plot_demo_residual_norm


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run leak detection comparisons.")
    parser.add_argument("--method", choices=["all", "cusum", "xbar_fdm", "hybrid"], default="all")
    parser.add_argument("--year", choices=["2018", "2019", "both"], default="both")
    parser.add_argument("--compare-existing", action="store_true")
    parser.add_argument("--plot-demo", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    years = _parse_years(args.year)

    cfg = load_config(DATA_DIR / "dataset_configuration.yaml")
    baseline = load_nominal_baseline(DATA_DIR / "nominal_baseline.mat")
    scada_by_year = {year: load_pressure_scada(DATA_DIR, year) for year in years}

    _check_supplemental_leak_csvs(years)
    results, residual_cases = compare_detectors(
        cfg=cfg,
        baseline=baseline,
        scada_by_year=scada_by_year,
        method=args.method,
        years=years,
    )

    output_csv = RESULTS_DIR / "detection_comparison.csv"
    write_detection_outputs(results, output_csv)
    print(f"Saved detection comparison: {output_csv}")

    if args.compare_existing:
        report_path = RESULTS_DIR / "detection_compare_report.md"
        compare_with_existing(results, DATA_DIR / "detection_comparison.csv", report_path)
        print(f"Saved comparison report: {report_path}")

    if args.plot_demo:
        case = _first_usable_case(residual_cases)
        if case is None:
            raise RuntimeError("No usable residual case found for demo plot.")
        figure_path = FIGURES_DIR / "demo_residual_norm.png"
        plot_demo_residual_norm(case, figure_path)
        print(f"Saved residual demo figure: {figure_path}")

    return 0


def _parse_years(value: str) -> list[int]:
    if value == "both":
        return [2018, 2019]
    return [int(value)]


def _check_supplemental_leak_csvs(years: list[int]) -> None:
    for year in years:
        path = DATA_DIR / f"{year}_Leakages.csv"
        if path.exists():
            try:
                read_leak_metadata_csv(path)
            except Exception as exc:
                print(f"Warning: supplemental leak CSV could not be parsed and was skipped: {path} ({exc})")


def _first_usable_case(cases):
    for case in cases:
        if case.usable:
            return case
    return None


if __name__ == "__main__":
    raise SystemExit(main())
