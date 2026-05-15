# Discussion

HydroTwin was evaluated as a digital-twin-based leak detection and localization pipeline for the BattLeDIM 2020 L-TOWN network. The final pipeline uses EPANET-derived nominal pressures, online bias correction, residual monitoring, CUSUM leak detection, and MAS-based sensitivity localization.

## Detection Discussion

The tuned CUSUM detector was selected as the final detector because it detected 29 of the 33 real leak events, compared with 26 for PlanC and 18 for XBar/FDM. CUSUM also reduced the median alarm delay to 79.0 hours, compared with 284.2 hours for PlanC. This is important because localization depends on a post-alarm residual window; later alarms delay the point at which the system can begin localization.

The tradeoff is a higher false-alarm count. CUSUM produced 3 false alarms, while PlanC produced 1. For this project, higher leak coverage was prioritized because the localization phase can only be evaluated after a valid detection event.

## Localization Discussion

The fair CUSUM comparison shows that MAS sensitivity is the best final localization method. It achieved the same Top-1 success rate as global sensitivity, but improved Top-5 and Top-10 performance while reducing the candidate search space from all 782 junctions to about 78 candidates.

This is a strong practical advantage. Global sensitivity evaluates the whole network for every alarm. MAS sensitivity uses the residual window to identify the most affected pressure sensors, then narrows the candidate nodes using sensitivity strength. The final node is still selected by physics-based residual-to-sensitivity correlation, so the method remains interpretable and defensible.

## XGBoost Discussion

XGBoost was added as an experimental ML-assisted search-space reduction layer. It was not trained on the 33 real BattLeDIM leaks, because that would severely overfit. Instead, it was trained on 15,640 synthetic residual samples generated from the EPANET sensitivity matrix.

On the synthetic held-out node split, XGBoost performed well: 72.2% Top-1 zone accuracy and 97.4% Top-3 zone accuracy. However, on real CUSUM-detected leaks, the zone transfer was much weaker: 5/29 Top-1 zone hits and 12/29 Top-3 zone hits. This synthetic-to-real gap explains why XGBoost was not selected as the final localizer.

When XGBoost predicts the wrong zone set, the final sensitivity correlation is restricted to the wrong candidate space. In those cases, even a good physics-based localizer cannot recover the correct node because the true area has already been removed from the search space.

## Failure Diagnosis

The failure analysis indicates three main causes:

| Cause | Evidence |
|---|---|
| Residual ambiguity or model mismatch | Global and MAS failures are dominated by residual ambiguity/model mismatch. Confidence gaps are very small, so multiple candidate nodes often produce nearly identical correlation scores. |
| Weak sensitivity regions | Some hard leaks, especially p800, lie in low-sensitivity regions. Weak/blind sensitivity accounts for part of the Top-10 failures, but it is not the only cause. |
| Wrong candidate reduction | XGBoost failures are mainly caused by incorrect zone selection. The real Top-3 zone hit rate was only 12/29. |

Incipient leaks remain harder than abrupt leaks. MAS achieved 83.3% Top-10 success on abrupt leaks but only 35.3% on incipient leaks. This matches the expected behavior: incipient leaks produce slower and weaker pressure changes, so their residual signatures are less distinct.

## Final Interpretation

The final result supports a hybrid but physics-first design. CUSUM provides the best detection coverage. MAS sensitivity gives the best localization balance between accuracy, candidate reduction, and interpretability. XGBoost is promising as a future ML module, but the current synthetic training setup does not yet transfer well enough to real BattLeDIM residuals.
