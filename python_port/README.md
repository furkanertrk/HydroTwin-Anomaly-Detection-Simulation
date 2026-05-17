# HydroTwin L-Town Python Port

This folder is the Python-only port workspace for the HydroTwin L-Town leak
detection and localization project. The original MATLAB, Simulink, and MATLAB
EPANET Toolkit files remain untouched.

## Scope of this first phase

The detection pipeline is implemented in Python. Localization, hydraulic
simulation, and ML-assisted localization remain staged for later port phases.

## Intended layout

```text
python_port/
  README.md
  requirements.txt
  run_all.py
  run_detection.py
  run_localization.py
  run_error_analysis.py
  run_visualization.py
  src/
    config.py
    paths.py
    data_loader.py
    epanet_model.py
    baseline.py
    sensitivity.py
    detection.py
    localization.py
    zones.py
    ml_zone_model.py
    metrics.py
    plots.py
    utils.py
  results/
  figures/
  cache/
```

## Key source data

The Python port should read inputs from the parent project, especially:

- `data/dataset_configuration.yaml`
- `data/L-TOWN.inp`
- `data/L-TOWN_Real.inp`
- `data/2018_SCADA_Pressures.csv`
- `data/2019_SCADA_Pressures.csv`
- `data/2018_SCADA_Demands.csv`
- `data/2019_SCADA_Demands.csv`
- `data/2018_SCADA_Flows.csv`
- `data/2019_SCADA_Flows.csv`
- `data/2018_SCADA_Levels.csv`
- `data/2019_SCADA_Levels.csv`
- `data/sensitivity_matrix.mat`
- `data/nominal_baseline.mat`
- `data/node_zone_map.mat`
- `data/ml_localization_dataset.csv`
- `data/detection_comparison.csv`
- `data/localization_fair_cusum_per_leak.csv`
- `data/localization_fair_cusum_features.csv`
- `data/localization_fair_cusum_summary.csv`
- `digital_twin_data.mat`

## EPANET / WNTR status

L-TOWN input files are available:

- `data/L-TOWN.inp`
- `data/L-TOWN_Real.inp`
- `data/L-TOWN_temp.inp`
- `toolkit/networks/L-Town/L-TOWN.inp`
- `data/4017659.zip` also contains `L-TOWN.inp` and `L-TOWN_Real.inp`

The Python port should try WNTR first. If WNTR cannot reproduce every MATLAB
EPANET Toolkit hydraulic behavior exactly, the port should clearly document the
gap and run the detection/localization pipeline from existing CSV and MAT
intermediate outputs.

## MAT files discovered

`digital_twin_data.mat` contains:

- `P_nominal_demo` shape `[6049, 33]`
- `S_norm` shape `[33, 782]`
- `junction_ids` shape `[1, 782]`
- `threshold_adaptive` shape `[1, 1]`

`data/sensitivity_matrix.mat` contains:

- `P_baseline`
- `S`
- `S_norm`
- `emitter_coeff`
- `junction_ids`
- `junction_indices`
- `sensor_indices`

`data/nominal_baseline.mat` contains:

- `P_nominal`
- `nominal_time`
- `sensor_indices`

`data/node_zone_map.mat` contains:

- `node_zone_map`
- `N_ZONES`
- `RNG_SEED`
- `centroids`
- `sumd`

`data/ml_localization_dataset.mat` contains:

- `ml_dataset`
- `feature_names`
- `N_ZONES`
- `N_SAMPLES_PER_NODE`
- `N_WINDOW`
- `RNG_SEED`
- `LEAK_MAGNITUDES`
- `NOISE_LEVELS`
- `SENSOR_BIAS_SIGMA`
- `SENSOR_DRIFT_SIGMA`
- `DROPOUT_PROB`

`data/scada_2018.mat` and `data/scada_2019.mat` contain a `scada` struct with:

- `pressures`
- `pressure_names`
- `time`
- `flows`
- `flow_names`
- `levels`
- `level_names`
- `demands_Lh`
- `demand_names`
- `demands_m3h`

## MATLAB script dependency map

- `s1_setup.m` uses MATLAB EPANET Toolkit, `data/L-Town.inp`, and writes
  `project_config.mat`.
- `s2_build_sensitivity_matrix.m` uses `load_config`, `load_ltown`, EPANET
  emitter simulations, and writes `data/sensitivity_matrix.mat`.
- `s2b_build_nominal_baseline.m` uses `load_config`, `load_ltown`, EPANET EPS
  stepping, and writes `data/nominal_baseline.mat`.
- `s3_run_digital_twin.m` is an early Simulink-oriented digital twin script and
  depends on `project_config.mat`, `sensitivity_matrix.mat`, and SCADA CSVs.
- `s4_evaluate_all_leaks.m` uses config, sensitivity matrix, nominal baseline,
  SCADA cache, and L-TOWN coordinates. Its localization parts are not active in
  the current Python detection port.
- `s4b_compare_detectors.m` uses config, nominal baseline, SCADA cache, and
  compares detector families. The Python detection port keeps CUSUM, XBarFDM,
  and a Hybrid method based on those two active detectors.
- `s4c_tune_detector_params.m` uses config, nominal baseline, SCADA cache, and
  writes detector parameter sweep results.
- `s5_build_simulink_model.m` prepares `digital_twin_data.mat` and builds the
  Simulink model. It should not be directly ported; its runtime behavior should
  be represented by Python scripts.
- `s6_visualize_demo.m` uses `digital_twin_data.mat`, sensitivity matrix, SCADA
  cache, config, and L-TOWN coordinates to create demo figures.
- `s7a_build_zones.m` uses L-TOWN junction coordinates and k-means to write
  `node_zone_map.csv/.mat`.
- `s7b_generate_ml_dataset.m` uses sensitivity matrix and zone map to generate
  synthetic ML features.
- `s7c_train_xgb_zone_localizer.py` is already Python and should be cleaned into
  `src/ml_zone_model.py` later.
- `s7d_evaluate_xgb_hybrid_localizer.m` uses CUSUM detections, nominal baseline,
  sensitivity matrix, zone map, SCADA cache, L-TOWN coordinates, and the XGB
  Python model.
- `s7e_compare_localizers.m` summarizes global, MAS, and XGB hybrid localization
  outputs.
- `s7f_fair_compare_localizers_cusum.m` evaluates global, MAS, and XGB
  localizers on the same CUSUM-detected events and residual windows.
- `s8_analyze_localization_errors.m` analyzes fair localization outputs and
  writes error-analysis CSVs and figures.

## Files that are report or presentation outputs

These are useful for validation and final write-up, but should not be treated
as primary algorithm inputs:

- `figures/*.png`
- root-level `*.pdf`
- root-level report markdown files such as `final_method_summary.md`,
  `limitations_and_future_work.md`, `results_tables_for_report.md`, and
  `discussion_for_report.md`
- `sunum/`
- `hocaya_sunum*.zip`
- `HydroTwin_Ara_Raporu.docx`
- `HydroTwin_Ara_Raporu.pdf`

## Critical risks for the Python port

- MATLAB `-v7.3` MAT files require `h5py`; older MAT files require
  `scipy.io.loadmat`.
- WNTR may not match MATLAB EPANET Toolkit behavior exactly for every hydraulic
  setting, emitter simulation, or time-step convention.
- L-TOWN has both `L-TOWN.inp` and much larger `L-TOWN_Real.inp`; the config
  names `L-TOWN_Real.inp`, while several MATLAB scripts default to
  `L-TOWN.inp`.
- MATLAB code uses 1-based node indices from EPANET; Python arrays and pandas
  use 0-based indexing.
- SCADA CSV files use semicolon delimiters, comma decimals, and explicit
  `yyyy-MM-dd HH:mm:ss` timestamps.
- Localization distance metrics depend on EPANET node/link coordinate lookup and
  pipe midpoint ground truth.
- Fair localization depends on exact CUSUM alarm times and identical 24-hour
  residual windows.
