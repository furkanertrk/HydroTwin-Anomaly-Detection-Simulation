# Localization Error Compare Report

- MATLAB rows: 87
- Python rows: 87

## Method Row Counts
- Global sensitivity: MATLAB=29, Python=29
- MAS sensitivity: MATLAB=29, Python=29
- XGBoost top-3 zones + sensitivity: MATLAB=29, Python=29

## Row Matching
- Matched rows: 87
- Only MATLAB rows: 0
- Only Python rows: 0

## Numeric Differences
- `top1_error_m` abs diff: mean=8.37052e-13, max=4.88853e-12
- `top5_min_error_m` abs diff: mean=7.60689e-13, max=4.88853e-12
- `top10_min_error_m` abs diff: mean=6.20704e-13, max=4.88853e-12
- `candidate_count` abs diff: mean=0, max=0
- `sensitivity_strength` abs diff: mean=2.58414e-16, max=5.55112e-16
- `confidence_gap` abs diff: mean=1.59537e-16, max=5.55137e-16
- `confidence_ratio` abs diff: mean=2.47567e-15, max=5.32907e-15

## Boolean / Category Differences
- `top1_success_300m` mismatches: 0
- `top5_success_300m` mismatches: 0
- `top10_success_300m` mismatches: 0
- `zone_hit_top1` mismatches: 0
- `zone_hit_top3` mismatches: 0

## Category Differences
- `failure_mode` mismatches: 87

## Notes
- Differences can come from confidence score recomputation, failure-mode label simplification, sensitivity strength naming, or boolean formatting.
- Python failure modes use: success_within_300m, weak_sensitivity, wrong_zone, low_confidence, candidate_filter_miss, large_distance_error, unknown.
