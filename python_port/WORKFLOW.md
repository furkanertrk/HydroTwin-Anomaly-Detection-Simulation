# HydroTwin Python Port Workflow

Bu dosya, Python portunun uçtan uca iş akışını hocaya anlatmak için
hazırlanmıştır. MATLAB, Simulink ve MATLAB EPANET Toolkit dosyaları korunur;
çalışan Python pipeline `python_port/` içindedir.

## Genel Pipeline Akışı

Python port dört ana adımdan oluşur:

1. Detection: SCADA basınç verileri ve nominal baseline kullanılarak kaçak
   alarm zamanı bulunur.
2. Localization: CUSUM ile güvenilir şekilde tespit edilen kaçak olayları için
   kaçak konumu tahmin edilir.
3. Error analysis: Tahmin edilen düğüm ile gerçek kaçak borusu arasındaki hata
   analiz edilir.
4. Visualization/reporting: CSV raporları ve final grafikler üretilir.

Ana uçtan uca komut:

```bash
python python_port/run_all.py --compare-existing --plot
```

## run_all.py Ne Yapar?

`run_all.py`, Python portunun ana orkestrasyon scriptidir. Sırasıyla şu
komutları çalıştırır:

1. `run_detection.py`
2. `run_localization.py`
3. `run_error_analysis.py`

`--compare-existing` verilirse Python çıktıları mevcut MATLAB CSV çıktılarıyla
karşılaştırılır. `--plot` verilirse final PNG grafikler de oluşturulur.

## Detection Akışı

Detection tarafında şu veri akışı kullanılır:

1. `dataset_configuration.yaml` içinden kaçak bilgileri ve sensör listeleri
   okunur.
2. `2018_SCADA_Pressures.csv` ve `2019_SCADA_Pressures.csv` dosyaları `;`
   ayırıcı ve `,` ondalık formatı ile okunur.
3. `nominal_baseline.mat` içinden nominal basınç matrisi alınır.
4. Her kaçak için önceki gün başlangıç alınır.
5. İlk 24 saatlik bölüm calibration window olarak kullanılır.
6. Bias correction uygulanır.
7. Residual ve residual norm hesaplanır.
8. Detection yöntemleri alarm zamanı üretir.
9. Detection delay, false alarm ve missed/detected metrikleri hesaplanır.

Aktif detection yöntemleri:

- CUSUM
- XBarFDM
- Hybrid = earliest(CUSUM, XBarFDM)

PlanC aktif pipeline'da yoktur. Deneysel bir yöntem olarak çıkarılmıştır ve
Python portunda aktif detector, CLI seçeneği veya final çıktı yöntemi değildir.

## Localization Akışı

Localization tarafında ana referans CUSUM detected eventleridir. Akış:

1. `python_port/results/detection_comparison.csv` okunur.
2. Sadece şu eventler seçilir:
   - `method == "CUSUM"`
   - `detected == true`
   - `false_alarm_before_leak == false`
3. Her event için SCADA pressure ve nominal baseline yeniden hizalanır.
4. Calibration window ile bias hesaplanır.
5. Alarm zamanından sonra localization residual window seçilir.
6. Ortalama residual vector `r_mean` çıkarılır.
7. Sensitivity matrix ile candidate node skorları hesaplanır.
8. Top-1, Top-5 ve Top-10 tahminleri üretilir.
9. Tahmin edilen junction ile gerçek kaçak pipe midpoint arasındaki mesafe
   hesaplanır.
10. 300 m başarı eşiği ile başarı metrikleri üretilir.

Aktif localization yöntemleri:

- Global sensitivity
- MAS sensitivity
- XGBoost top-3 zones + sensitivity

XGBoost modeli yeniden eğitilmez. Mevcut `data/xgb_zone_model.pkl` dosyası
predict-only kullanılır.

## Error Analysis Akışı

Error analysis, localization çıktılarının daha açıklanabilir hale getirilmesini
sağlar:

1. `localization_fair_cusum_per_leak.csv` okunur.
2. Top-1, Top-5 ve Top-10 hata metrikleri kontrol edilir.
3. 300 m başarı kolonları üretilir.
4. True zone ve predicted zone bilgileri eklenir.
5. Sensitivity strength hesaplanır.
6. Weak sensitivity ve blind spot bayrakları üretilir.
7. Confidence gap ve confidence ratio hesaplanır.
8. Her leak-method satırı için failure mode atanır.

Failure mode sınıfları:

- success_within_300m
- weak_sensitivity
- wrong_zone
- low_confidence
- candidate_filter_miss
- large_distance_error
- unknown

## Hangi Input Dosyaları Kullanılıyor?

Ana input dosyaları:

- `data/dataset_configuration.yaml`
- `data/2018_SCADA_Pressures.csv`
- `data/2019_SCADA_Pressures.csv`
- `data/nominal_baseline.mat`
- `data/sensitivity_matrix.mat`
- `data/node_zone_map.csv`
- `data/L-TOWN.inp`
- `data/L-TOWN_Real.inp` fallback olarak
- `data/xgb_zone_model.pkl`

Karşılaştırma için kullanılan MATLAB çıktıları:

- `data/detection_comparison.csv`
- `data/localization_fair_cusum_per_leak.csv`
- `data/localization_fair_cusum_summary.csv`
- `data/localization_error_analysis.csv`

## Hangi Python Dosyaları Çalışıyor?

Ana çalıştırma dosyaları:

- `python_port/run_all.py`
- `python_port/run_detection.py`
- `python_port/run_localization.py`
- `python_port/run_error_analysis.py`
- `python_port/run_visualization.py`

Kullanılan temel modüller:

- `python_port/src/config.py`
- `python_port/src/data_loader.py`
- `python_port/src/baseline.py`
- `python_port/src/detection.py`
- `python_port/src/localization.py`
- `python_port/src/sensitivity.py`
- `python_port/src/zones.py`
- `python_port/src/epanet_model.py`
- `python_port/src/ml_zone_model.py`
- `python_port/src/metrics.py`
- `python_port/src/plots.py`

## Hangi Yöntemler Kullanılıyor?

Detection:

- CUSUM
- XBarFDM
- Hybrid = earliest(CUSUM, XBarFDM)

Localization:

- Global sensitivity
- MAS sensitivity
- XGBoost top-3 zones + sensitivity

Distance metric:

- Gerçek kaçak konumu pipe midpoint olarak alınır.
- Tahmin edilen junction koordinatı ile pipe midpoint arasındaki Euclidean
  mesafe hesaplanır.
- Başarı eşiği 300 m'dir.

## Hangi Çıktılar Üretiliyor?

Detection çıktıları:

- `python_port/results/detection_comparison.csv`
- `python_port/results/detection_compare_report.md`
- `python_port/figures/demo_residual_norm.png`

Localization çıktıları:

- `python_port/results/localization_fair_cusum_per_leak.csv`
- `python_port/results/localization_fair_cusum_summary.csv`
- `python_port/results/localization_fair_cusum_features.csv`
- `python_port/results/localization_fair_cusum_zone_predictions.csv`
- `python_port/results/localization_compare_report.md`

Error analysis çıktıları:

- `python_port/results/localization_error_analysis.csv`
- `python_port/results/localization_error_compare_report.md`

Final figürler:

- `python_port/figures/localization_error_histogram.png`
- `python_port/figures/top1_error_by_method.png`
- `python_port/figures/xgb_zone_hit_vs_error.png`
- `python_port/figures/sensitivity_strength_map.png`

## Hocaya Anlatılacak Kısa Özet

Bu projede MATLAB/Simulink ağırlıklı HydroTwin L-Town kaçak tespit ve
lokalizasyon akışı Python-only hale getirilmiştir. MATLAB dosyaları silinmeden
korunmuş, yeni çalışan sistem `python_port/` altında ayrı tutulmuştur.

Detection aşamasında SCADA basınçları nominal baseline ile karşılaştırılır,
residual norm üretilir ve CUSUM, XBarFDM ve bu iki yöntemin earliest alarm
birleşimi olan Hybrid detector çalıştırılır. Deneysel PlanC yöntemi final
pipeline'dan tamamen çıkarılmıştır.

Localization aşamasında yalnızca güvenilir CUSUM tespitleri kullanılır.
Sensitivity matrix üzerinden Global sensitivity, MAS sensitivity ve XGBoost
top-3 zones + sensitivity yöntemleri çalıştırılır. Tahmin edilen junction ile
gerçek kaçak pipe midpoint arasındaki mesafe hesaplanır ve 300 m başarı eşiği
ile değerlendirme yapılır.

Son aşamada error analysis CSV'leri, MATLAB karşılaştırma raporları ve final
grafikler üretilir. `run_all.py --compare-existing --plot` komutu Python
pipeline'ını uçtan uca çalıştırır.
