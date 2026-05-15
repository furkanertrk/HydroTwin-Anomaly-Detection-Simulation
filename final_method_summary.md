# Final HydroTwin Method Summary

## Selected Final Pipeline

The final HydroTwin pipeline is:

1. EPANET digital twin generates nominal leak-free pressure behavior.
2. SCADA pressure measurements are aligned at 5-minute resolution.
3. A 24-hour clean calibration window estimates sensor bias:

```text
bias = mean(P_measured(1:N_CALIB,:) - P_nominal(1:N_CALIB,:), 1)
P_predicted = P_nominal + bias
residual = P_predicted - P_measured
```

4. Tuned CUSUM detects leaks from the residual norm.
5. After an alarm, HydroTwin waits for a 24-hour residual localization window.
6. MAS sensitivity localization selects the most affected sensors and reduces the candidate junction set.
7. Final node localization is performed using sensitivity correlation inside the MAS candidate set.

## Final Detector: Tuned CUSUM

CUSUM was selected as the final detector because it produced the best detection coverage:

| Metric | CUSUM result |
|---|---:|
| Detected leaks | 29/33 |
| False alarms | 3/33 |
| Abrupt detected | 12/15 |
| Incipient detected | 17/18 |
| Median alarm delay | 79.0 h |

PlanC had fewer false alarms, but detected fewer leaks and had much longer median delay. XBar/FDM was weaker overall.

## Final Localizer: MAS Sensitivity

MAS sensitivity was selected as the final localization method.

| Metric | MAS result |
|---|---:|
| Evaluated CUSUM detections | 29 |
| Top-1 <=300 m | 13/29 |
| Top-5 <=300 m | 16/29 |
| Top-10 <=300 m | 16/29 |
| Median Top-1 error | 341.2 m |
| Mean candidate count | 78 |

MAS was selected because it preserved the same Top-1 success as global sensitivity, improved Top-5 and Top-10 success, and reduced the candidate space by approximately 90%.

## Why Global Sensitivity Was Not Selected

Global sensitivity is useful as a baseline because it searches all 782 junctions. However, it does not reduce the search space and achieved lower Top-5 and Top-10 success than MAS:

| Method | Top-5 <=300 m | Top-10 <=300 m | Mean candidates |
|---|---:|---:|---:|
| Global sensitivity | 13/29 | 14/29 | 782 |
| MAS sensitivity | 16/29 | 16/29 | 78 |

For a real-time digital twin, MAS provides a more operationally useful candidate list.

## Why XGBoost Was Not Selected

XGBoost was evaluated only as a zone-level search-space reduction module. It was trained on synthetic residual samples generated from the sensitivity matrix, not on real leak labels.

| XGBoost evaluation | Top-1 zone hit | Top-3 zone hit |
|---|---:|---:|
| Synthetic held-out junction split | 72.2% | 97.4% |
| Real CUSUM-detected leaks | 5/29 | 12/29 |

The real zone-hit rate is too low for final deployment. When XGBoost misses the correct zone, the true node is excluded before sensitivity localization begins. Therefore, XGBoost is retained as an experimental/future-work component rather than the final method.

## Final Framing

HydroTwin is a physics-first digital twin pipeline with statistical detection and sensitivity-based localization:

```text
EPANET nominal baseline
    -> bias-corrected residual
    -> CUSUM leak detection
    -> MAS candidate reduction
    -> sensitivity-correlation node localization
```

XGBoost remains an optional research module for future ML-assisted candidate reduction.
