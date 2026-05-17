# Detection Compare Report

- Active Python methods: CUSUM, XBarFDM, Hybrid
- Compared methods: CUSUM, XBarFDM
- MATLAB rows before filtering: 132
- MATLAB rows after filtering: 66
- Python rows: 99
- Python rows compared: 66
- Matched rows: 66
- Only MATLAB rows: 0
- Only Python rows: 0

PlanC was an experimental method and has been removed from the Python port. Existing MATLAB PlanC rows are ignored during comparison.
Existing MATLAB Hybrid rows are also ignored because they were based on the removed experimental method; the Python Hybrid method now combines CUSUM and XBar/FDM.

## Column Mismatches
- `detected`: 0
- `false_alarm_before_leak`: 0
- `alarm_time`: 0
- `alarm_delay_h`: 0
- `threshold`: 0
- `calib_center`: 0
- `calib_scale`: 0

## Notes
- Differences can come from datetime parsing, MAT/HDF5 orientation, baseline index alignment, numeric quantile/std behavior, or MATLAB/Python indexing.