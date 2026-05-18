# Localization Compare Report

- XGBoost model loaded: True
- XGBoost feature count: 132
- XGBoost class count: 30
- XGBoost message: XGBoost model is available for later phases.

- Python evaluated leak-method rows: 87
- MATLAB evaluated leak-method rows: 87
- Python evaluated leak count: 29
- MATLAB evaluated leak count: 29
- XGBoost prediction rows: 29
- XGBoost top-1 zone hits: 5
- XGBoost top-3 zone hits: 12

## Summary Differences
### Global sensitivity
- `evaluated_leaks`: MATLAB=29, Python=29, diff=0
- `top1_within_300m`: MATLAB=13, Python=13, diff=0
- `top5_within_300m`: MATLAB=13, Python=13, diff=0
- `top10_within_300m`: MATLAB=14, Python=14, diff=0
- `top1_rate`: MATLAB=0.448275862068966, Python=0.4482758620689655, diff=-4.996e-16
- `top5_rate`: MATLAB=0.448275862068966, Python=0.4482758620689655, diff=-4.996e-16
- `top10_rate`: MATLAB=0.482758620689655, Python=0.4827586206896552, diff=1.66533e-16
- `median_top1_error_m`: MATLAB=341.19043527772, Python=341.19043527772004, diff=5.68434e-14
- `mean_top1_error_m`: MATLAB=621.370304949414, Python=621.3703049494144, diff=3.41061e-13
- `mean_candidate_count`: MATLAB=782.0, Python=782.0, diff=0

### MAS sensitivity
- `evaluated_leaks`: MATLAB=29, Python=29, diff=0
- `top1_within_300m`: MATLAB=13, Python=13, diff=0
- `top5_within_300m`: MATLAB=16, Python=16, diff=0
- `top10_within_300m`: MATLAB=16, Python=16, diff=0
- `top1_rate`: MATLAB=0.448275862068966, Python=0.4482758620689655, diff=-4.996e-16
- `top5_rate`: MATLAB=0.551724137931034, Python=0.5517241379310345, diff=4.44089e-16
- `top10_rate`: MATLAB=0.551724137931034, Python=0.5517241379310345, diff=4.44089e-16
- `median_top1_error_m`: MATLAB=341.19043527772, Python=341.19043527772004, diff=5.68434e-14
- `mean_top1_error_m`: MATLAB=616.831207390771, Python=616.8312073907706, diff=-4.54747e-13
- `mean_candidate_count`: MATLAB=78.0, Python=78.0, diff=0

### XGBoost top-3 zones + sensitivity
- `evaluated_leaks`: MATLAB=29, Python=29, diff=0
- `top1_within_300m`: MATLAB=12, Python=12, diff=0
- `top5_within_300m`: MATLAB=13, Python=13, diff=0
- `top10_within_300m`: MATLAB=14, Python=14, diff=0
- `top1_rate`: MATLAB=0.413793103448276, Python=0.41379310344827586, diff=-1.66533e-16
- `top5_rate`: MATLAB=0.448275862068966, Python=0.4482758620689655, diff=-4.996e-16
- `top10_rate`: MATLAB=0.482758620689655, Python=0.4827586206896552, diff=1.66533e-16
- `median_top1_error_m`: MATLAB=381.179916345287, Python=381.1799163452868, diff=-1.7053e-13
- `mean_top1_error_m`: MATLAB=653.01375996837, Python=653.0137599683701, diff=1.13687e-13
- `mean_candidate_count`: MATLAB=78.8620689655172, Python=78.86206896551724, diff=4.26326e-14

## Per-Leak Error Differences
- Matched leak-method rows: 87
- Only MATLAB rows: 0
- Only Python rows: 0
- `top1_error_m` absolute diff: mean=8.24148e-13, max=4.77485e-12
- `top5_min_error_m` absolute diff: mean=7.53298e-13, max=4.88853e-12
- `top10_min_error_m` absolute diff: mean=6.20418e-13, max=4.88853e-12
- `candidate_count` absolute diff: mean=0, max=0

## Largest Top-1 Error Difference
- leak=p654, method=Global sensitivity, MATLAB=1006.73290333137, Python=1006.7329033313653

## Difference Notes
- Large differences usually point to residual window alignment, sensitivity matrix orientation, MAS candidate selection, node/junction ID mapping, or pipe-midpoint distance semantics.
- Large XGBoost differences usually point to feature ordering, zone label/index handling, pickle/library version differences, candidate zone filtering, or residual window alignment.
