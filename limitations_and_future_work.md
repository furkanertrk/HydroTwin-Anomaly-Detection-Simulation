# Limitations and Future Work

## Current Limitations

## 1. Incipient Leak Localization Remains Difficult

Abrupt leaks are localized more reliably than incipient leaks. With MAS sensitivity, Top-10 success was 83.3% for abrupt leaks but 35.3% for incipient leaks. This suggests that slowly developing leaks produce residual signatures that are weaker, more delayed, or more easily confused with model mismatch and demand uncertainty.

## 2. Residual Ambiguity

Many localization failures are not caused by a single wrong calculation, but by ambiguity in the residual signature. The confidence gaps between the best and second-best sensitivity candidates are extremely small. This means several nodes can explain the measured residual pattern almost equally well.

This is visible in the failure diagnosis:

| Method | Dominant failure pattern |
|---|---|
| Global sensitivity | Residual ambiguity / model mismatch |
| MAS sensitivity | Residual ambiguity / model mismatch |
| XGBoost + sensitivity | Wrong candidate reduction |

## 3. Weak Sensitivity Regions

Some leaks occur in areas where the 33 pressure sensors have weak sensitivity. The sensitivity strength analysis showed that weak or blind sensitivity regions contribute to localization failures. Leak `p800` is a clear example: it appears in the worst leak list and is marked as a low-sensitivity-region failure.

## 4. XGBoost Synthetic-to-Real Gap

The XGBoost model learned the synthetic sensitivity-generated dataset well, but did not transfer strongly to real leak residuals:

| Setting | Top-1 zone hit | Top-3 zone hit |
|---|---:|---:|
| Synthetic held-out junction split | 72.2% | 97.4% |
| Real CUSUM-detected leaks | 5/29 | 12/29 |

This indicates that the synthetic training data is still too idealized or does not fully capture real SCADA effects, demand uncertainty, leak growth dynamics, sensor drift, and calibration mismatch.

## 5. Single-Leak Assumption

The current localization evaluation assumes one dominant leak event in the post-alarm residual window. Real water networks may contain overlapping leaks, background leakage, valve operations, abnormal demand changes, or sensor faults.

## Future Work

## 1. Improve Synthetic ML Training Data

XGBoost should not be discarded, but it needs better synthetic-to-real adaptation. Future synthetic data should include:

- stronger seasonal demand uncertainty,
- leak growth profiles for incipient leaks,
- realistic sensor noise and drift,
- partial calibration errors,
- pressure-dependent leakage behavior,
- multiple leak magnitudes and durations,
- simulated background leakage.

## 2. Train ML on Zones, Not Exact Nodes

The current XGBoost design already uses zone-level classification, which is the right direction. Future work should tune zone definitions instead of relying only on k-means spatial clusters. Better zones could be based on:

- hydraulic distance,
- pipe connectivity,
- pressure sensor influence,
- sensitivity similarity,
- DMA-like network partitions.

## 3. Add Confidence-Aware Reporting

HydroTwin should report whether localization is confident or ambiguous. A practical confidence output can combine:

- correlation gap,
- correlation ratio,
- candidate count,
- sensitivity strength near the predicted node,
- agreement between MAS and global sensitivity,
- XGBoost zone agreement if enabled.

## 4. Add Pipe-Level Localization

The current output is node-level localization, while BattLeDIM leaks are pipe events. Future evaluation should report:

- predicted node to true pipe midpoint distance,
- nearest predicted pipe candidate,
- pipe-level Top-k success,
- node-to-pipe conversion using network topology.

## 5. Explore PSO or Optimization-Based Refinement

After MAS narrows the candidate space, an optimization step could estimate both leak location and leak magnitude. This would align HydroTwin with real-time digital twin and PSO-based localization literature while keeping the current sensitivity method as a fast first-stage localizer.

## 6. Sensor Placement and Blind Spot Analysis

The weak sensitivity analysis should be extended into a sensor placement study. Candidate future outputs:

- sensitivity strength map,
- blind-zone map,
- recommended additional pressure sensor locations,
- expected localization improvement from new sensors.

## Final Recommendation

For the current project version, the final method should remain:

```text
CUSUM detection + MAS sensitivity localization
```

XGBoost should be presented as an experimental module and future-work direction, not as the final localization method.
