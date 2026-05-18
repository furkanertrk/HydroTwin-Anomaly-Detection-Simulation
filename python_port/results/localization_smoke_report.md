# Localization Smoke Report

## Inputs
- INP file: `D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown\data\L-TOWN.inp`
- Detection source: `D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown\python_port\results\detection_comparison.csv`
- Distance threshold: 300.0 m

## EPANET Mapping
- Junction count: 782
- Link count: 909
- Pipe count: 905
- Sample junction: `{'junction_id': 'n1', 'x': 138.22, 'y': 1549.64}`
- Sample pipe endpoint: `{'link_id': 'p1', 'start_node': 'n62', 'end_node': 'n61'}`
- Sample pipe midpoint: `{'pipe_id': 'p1', 'x': 725.4100000000001, 'y': 1109.115, 'start_node': 'n62', 'end_node': 'n61'}`

## Sensitivity Matrix
- S shape: (33, 782)
- S_norm shape: (33, 782)
- Junction count: 782
- Sensor count: 33
- First 5 junction IDs: ['n1', 'n2', 'n3', 'n4', 'n5']
- First 5 sensor indices: [np.int64(1), np.int64(4), np.int64(31), np.int64(54), np.int64(105)]

## Zone Map
- Zone count: 30
- Junction count: 782
- Zone candidate count min/mean/max: 17/26.1/37
- Example junction-zone mapping: `('n1', 30)`

## CUSUM Events
- Selected event count: 29
- First events: `[{'leak_id': 'p257', 'leak_start_time': Timestamp('2018-01-08 13:30:00'), 'alarm_time': Timestamp('2018-01-10 15:05:00')}, {'leak_id': 'p461', 'leak_start_time': Timestamp('2018-01-23 04:25:00'), 'alarm_time': Timestamp('2018-02-02 18:20:00')}, {'leak_id': 'p232', 'leak_start_time': Timestamp('2018-01-31 02:35:00'), 'alarm_time': Timestamp('2018-02-02 17:40:00')}]`

## Residual Window Checks
- Checked events: 2
- Successful checks: 2
- p257: status=ok, calibration=288, localization=288, measured=(103392, 33), nominal=(103392, 33), residual_vector=(33,), message=ok
- p461: status=ok, calibration=288, localization=288, measured=(20301, 33), nominal=(20301, 33), residual_vector=(33,), message=ok

## XGBoost Availability
- Model path: `D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown\data\xgb_zone_model.pkl`
- Exists: True
- Loadable: True
- Model class: xgboost.sklearn.XGBClassifier
- Feature count: 132
- Class count: 30
- Message: XGBoost model is available for later phases.

## Outputs
- Mapping check CSV: `D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown\python_port\results\localization_mapping_check.csv`
- Event check CSV: `D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown\python_port\results\localization_event_check.csv`

## Phase 3B-2 Readiness
- Safe to continue: True
- Recommendation: proceed with Global/MAS/XGBoost localization implementation.
