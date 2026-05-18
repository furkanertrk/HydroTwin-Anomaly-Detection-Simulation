# HydroTwin L-Town Python Port

This directory contains the Python-only port of the HydroTwin L-Town leak
detection and localization workflow. The original MATLAB, Simulink, MATLAB
EPANET Toolkit, and source data folders are left untouched; Python outputs are
written under `python_port/results/` and `python_port/figures/`.

## Implemented Pipeline

Detection methods:

- CUSUM
- XBarFDM
- Hybrid = earliest(CUSUM, XBarFDM)

Localization methods:

- Global sensitivity
- MAS sensitivity
- XGBoost top-3 zones + sensitivity

The removed experimental detector is not part of the final Python pipeline.
The Simulink real-time model is represented by Python command-line scripts
rather than a one-to-one model conversion.

## Setup

Use Python 3.11+ and install the dependencies from this directory:

```bash
python -m pip install -r python_port/requirements.txt
```

The port uses `pathlib` paths relative to the repository root. It reads SCADA
CSV files with semicolon separators and comma decimals, reads MATLAB MAT files
with `scipy.io.loadmat` plus an HDF5 fallback, and uses ID-based node/link
mapping for EPANET/WNTR data.

## Main Commands

Run the full pipeline:

```bash
python python_port/run_all.py --compare-existing --plot
```

Run detection only:

```bash
python python_port/run_detection.py --method all --year both --compare-existing --plot-demo
```

Run localization only:

```bash
python python_port/run_localization.py --method all --use-python-detection --threshold-m 300 --compare-existing --plot
```

Run error analysis only:

```bash
python python_port/run_error_analysis.py --compare-existing --plot --threshold-m 300
```

Regenerate plots from existing outputs:

```bash
python python_port/run_visualization.py --include-detection-demo --threshold-m 300
```

Run the localization smoke test:

```bash
python python_port/run_localization.py --smoke-test --use-python-detection --threshold-m 300
```

## Outputs

Detection:

- `python_port/results/detection_comparison.csv`
- `python_port/results/detection_compare_report.md`
- `python_port/figures/demo_residual_norm.png`

Localization:

- `python_port/results/localization_fair_cusum_per_leak.csv`
- `python_port/results/localization_fair_cusum_summary.csv`
- `python_port/results/localization_fair_cusum_features.csv`
- `python_port/results/localization_fair_cusum_zone_predictions.csv`
- `python_port/results/localization_compare_report.md`

Error analysis and figures:

- `python_port/results/localization_error_analysis.csv`
- `python_port/results/localization_error_compare_report.md`
- `python_port/figures/localization_error_histogram.png`
- `python_port/figures/top1_error_by_method.png`
- `python_port/figures/xgb_zone_hit_vs_error.png`
- `python_port/figures/sensitivity_strength_map.png`

Smoke-test diagnostics:

- `python_port/results/localization_smoke_report.md`
- `python_port/results/localization_mapping_check.csv`
- `python_port/results/localization_event_check.csv`

## Data Inputs

The Python port reads these existing project inputs:

- `data/dataset_configuration.yaml`
- `data/2018_SCADA_Pressures.csv`
- `data/2019_SCADA_Pressures.csv`
- `data/nominal_baseline.mat`
- `data/sensitivity_matrix.mat`
- `data/node_zone_map.csv`
- `data/L-TOWN.inp` with fallback to `data/L-TOWN_Real.inp`
- `data/xgb_zone_model.pkl`
- MATLAB comparison CSVs under `data/`

## Comparison Status

The detection output is compared with `data/detection_comparison.csv` after
filtering out methods that are not part of the final Python detector set.

The fair CUSUM localization output is compared with:

- `data/localization_fair_cusum_per_leak.csv`
- `data/localization_fair_cusum_summary.csv`

The error-analysis output is compared with:

- `data/localization_error_analysis.csv`

Current Python localization runs preserve the 29 CUSUM-detected leak events and
match the MATLAB fair CUSUM Global, MAS, and XGBoost hybrid outputs at floating
point tolerance.

## Known Limitations

- WNTR is used for model parsing and coordinate/link mapping, while hydraulic
  intermediate data still comes from existing CSV/MAT outputs.
- MATLAB HDF5 arrays are transposed when needed so sensitivity and baseline
  matrices align as `(33, 782)` and `(time, 33)`.
- Node, junction, pipe, and zone matching is ID-based to avoid EPANET ordering
  differences between MATLAB and Python.
- The XGBoost model is loaded predict-only from the existing pickle file; model
  version compatibility is a runtime risk.
- Failure-mode labels in the Python error analysis are intentionally simple and
  explainable: success within 300 m, weak sensitivity, wrong zone, low
  confidence, candidate filter miss, large distance error, or unknown.
