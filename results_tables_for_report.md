# Results Tables for Report

## Leak Detection Performance

The final detection stage uses the tuned CUSUM detector. CUSUM was selected because it achieved the highest detection coverage while keeping the false-alarm count acceptable for the project scope.

| Detector | Detected leaks | False alarms | Abrupt detected | Incipient detected | Median alarm delay | Mean alarm delay |
|---|---:|---:|---:|---:|---:|---:|
| PlanC | 26/33 | 1/33 | 10/15 | 16/18 | 284.2 h | 418.4 h |
| CUSUM tuned | 29/33 | 3/33 | 12/15 | 17/18 | 79.0 h | 202.6 h |
| XBar/FDM | 18/33 | 3/33 | 6/15 | 12/18 | 278.5 h | 717.2 h |
| Hybrid | 29/33 | 3/33 | 12/15 | 17/18 | 79.0 h | 202.6 h |

## Fair CUSUM Localization Comparison

The localization methods were compared using the same 29 CUSUM-detected leaks, the same alarm times, the same 24-hour residual windows, and the same pipe-midpoint distance definition.

| Localization method | Evaluated leaks | Top-1 <=300 m | Top-5 <=300 m | Top-10 <=300 m | Median Top-1 error | Mean Top-1 error | Mean candidate count |
|---|---:|---:|---:|---:|---:|---:|---:|
| Global sensitivity | 29 | 13/29 (44.8%) | 13/29 (44.8%) | 14/29 (48.3%) | 341.2 m | 621.4 m | 782.0 |
| MAS sensitivity | 29 | 13/29 (44.8%) | 16/29 (55.2%) | 16/29 (55.2%) | 341.2 m | 616.8 m | 78.0 |
| XGBoost top-3 zones + sensitivity | 29 | 12/29 (41.4%) | 13/29 (44.8%) | 14/29 (48.3%) | 381.2 m | 653.0 m | 78.9 |

## Abrupt vs Incipient Localization

| Localization method | Abrupt Top-1 | Incipient Top-1 | Abrupt Top-10 | Incipient Top-10 |
|---|---:|---:|---:|---:|
| Global sensitivity | 83.3% | 17.6% | 83.3% | 23.5% |
| MAS sensitivity | 75.0% | 23.5% | 83.3% | 35.3% |
| XGBoost top-3 zones + sensitivity | 75.0% | 17.6% | 83.3% | 23.5% |

## XGBoost Zone-Level Results

| Evaluation setting | Top-1 zone hit | Top-3 zone hit |
|---|---:|---:|
| Synthetic held-out junction split | 72.2% | 97.4% |
| Real CUSUM-detected BattLeDIM leaks | 5/29 (17.2%) | 12/29 (41.4%) |

This gap shows that the synthetic zone classifier learned the generated sensitivity patterns well, but did not transfer strongly enough to real leak residuals to be selected as the final localization method.

## Worst Five Leaks by Method

| Method | Worst leaks by Top-1 error |
|---|---|
| Global sensitivity | p800, p810, p721, p193, p455 |
| MAS sensitivity | p810, p800, p721, p193, p710 |
| XGBoost top-3 zones + sensitivity | p800, p810, p721, p193, p455 |
