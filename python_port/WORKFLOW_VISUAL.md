# HydroTwin Python Port — Görsel İş Akışı

Bu doküman, `python_port/` içindeki Python-only HydroTwin pipeline’ının **hangi sırayla çalıştığını**, **hangi dosyaların devreye girdiğini** ve **her aşamada hangi yöntemin kullanıldığını** görsel olarak anlatır.

> Önerilen yer: `python_port/WORKFLOW_VISUAL.md`

---

## 0. Tek Komutla Genel Akış

```powershell
py -3.12 python_port\run_all.py --compare-existing --plot
```

```mermaid
flowchart LR
    A[run_all.py] --> B[run_detection.py]
    B --> C[run_localization.py]
    C --> D[run_error_analysis.py]
    D --> E[CSV raporları + PNG grafikler]

    B -. compare .-> M1[MATLAB detection outputs]
    C -. compare .-> M2[MATLAB fair CUSUM localization outputs]
    D -. compare .-> M3[MATLAB error analysis outputs]
```

---

## 1. Büyük Resim: Veri → Detection → Localization → Error Analysis

```mermaid
flowchart TD
    subgraph INPUTS[Input Dosyaları]
        A1[data/dataset_configuration.yaml]
        A2[data/2018_SCADA_Pressures.csv]
        A3[data/2019_SCADA_Pressures.csv]
        A4[data/nominal_baseline.mat]
        A5[data/sensitivity_matrix.mat]
        A6[data/node_zone_map.csv]
        A7[data/L-TOWN.inp]
        A8[data/xgb_zone_model.pkl]
    end

    subgraph DETECTION[1. Detection]
        B1[SCADA pressure oku]
        B2[Nominal baseline ile hizala]
        B3[Bias correction]
        B4[Residual norm hesapla]
        B5[CUSUM / XBarFDM / Hybrid]
    end

    subgraph LOCALIZATION[2. Localization]
        C1[CUSUM detected event seç]
        C2[Residual localization window]
        C3[Sensitivity ranking]
        C4[Global / MAS / XGBoost Hybrid]
        C5[Top-1 / Top-5 / Top-10 error]
    end

    subgraph ERROR[3. Error Analysis]
        D1[300 m başarı eşiği]
        D2[Failure mode]
        D3[Sensitivity diagnostics]
        D4[Grafikler]
    end

    INPUTS --> DETECTION
    DETECTION --> R1[results/detection_comparison.csv]
    R1 --> LOCALIZATION
    LOCALIZATION --> R2[results/localization_fair_cusum_per_leak.csv]
    LOCALIZATION --> R3[results/localization_fair_cusum_summary.csv]
    R2 --> ERROR
    R3 --> ERROR
    ERROR --> R4[results/localization_error_analysis.csv]
    ERROR --> F[figures/*.png]
```

---

## 2. Dosya Bazlı Çalışma Haritası

```mermaid
flowchart TB
    subgraph RUN[Çalıştırma Scriptleri]
        R0[run_all.py]
        R1[run_detection.py]
        R2[run_localization.py]
        R3[run_error_analysis.py]
        R4[run_visualization.py]
    end

    subgraph SRC[src/ modülleri]
        S1[config.py]
        S2[data_loader.py]
        S3[baseline.py]
        S4[detection.py]
        S5[localization.py]
        S6[sensitivity.py]
        S7[zones.py]
        S8[epanet_model.py]
        S9[ml_zone_model.py]
        S10[metrics.py]
        S11[plots.py]
    end

    R0 --> R1
    R0 --> R2
    R0 --> R3

    R1 --> S1
    R1 --> S2
    R1 --> S3
    R1 --> S4
    R1 --> S10
    R1 --> S11

    R2 --> S2
    R2 --> S3
    R2 --> S5
    R2 --> S6
    R2 --> S7
    R2 --> S8
    R2 --> S9
    R2 --> S10
    R2 --> S11

    R3 --> S5
    R3 --> S6
    R3 --> S7
    R3 --> S10
    R3 --> S11

    R4 --> S11
```

---

## 3. Detection İş Akışı

**Komut:**

```powershell
py -3.12 python_port\run_detection.py --method all --year both --compare-existing --plot-demo
```

```mermaid
flowchart TD
    A[dataset_configuration.yaml] --> B[Leak metadata + sensor config]
    C[2018/2019 SCADA pressure CSV] --> D[SCADA pressure matrix]
    E[nominal_baseline.mat] --> F[Nominal pressure matrix]

    B --> G[Leak event döngüsü]
    D --> G
    F --> G

    G --> H[Calibration window: ilk 288 örnek]
    H --> I[Bias correction]
    I --> J[Residual hesapla]
    J --> K[Residual norm]

    K --> L1[CUSUM]
    K --> L2[XBarFDM]
    L1 --> L3[Hybrid = earliest alarm]
    L2 --> L3

    L1 --> M[Alarm time + delay + false alarm]
    L2 --> M
    L3 --> M

    M --> N[results/detection_comparison.csv]
    M --> O[results/detection_compare_report.md]
    K --> P[figures/demo_residual_norm.png]
```

| Yöntem | Ne yapar? | Durum |
|---|---|---|
| CUSUM | Küçük ama sürekli sapmaları kümülatif izler | Aktif |
| XBarFDM | Ortalama/sapma temelli alarm üretir | Aktif |
| Hybrid | CUSUM ve XBarFDM içinde erken alarm vereni seçer | Aktif |
| PlanC | Eski deneysel yöntem | Çıkarıldı |

> PlanC final pipeline’da yoktur. CLI seçeneği, aktif detector ve final CSV yöntemi değildir.

---

## 4. Localization İş Akışı

**Komut:**

```powershell
py -3.12 python_port\run_localization.py --method all --use-python-detection --threshold-m 300 --compare-existing --plot
```

Localization sadece güvenilir CUSUM eventlerini kullanır:

```text
method == "CUSUM"
detected == true
false_alarm_before_leak == false
```

```mermaid
flowchart LR
    A[results/detection_comparison.csv] --> B{method == CUSUM?}
    B -- hayır --> X[Atla]
    B -- evet --> C{detected == true?}
    C -- hayır --> X
    C -- evet --> D{false_alarm_before_leak == false?}
    D -- hayır --> X
    D -- evet --> E[29 localization event]
```

---

## 5. Residual Window ve Sensitivity Ranking

```mermaid
flowchart TD
    A[Leak start öncesi 1 gün] --> B[Calibration window: 288 örnek]
    B --> C[Bias = mean(P_measured - P_nominal)]
    C --> D[Residual = P_nominal + bias - P_measured]
    D --> E[Alarm sonrası localization window: 288 örnek]
    E --> F[r_mean: 33 sensörlük residual vector]
    F --> G[r_norm = r_mean / norm(r_mean)]
    G --> H[score = S_norm.T @ r_norm]
    H --> I[Junction ranking]
    I --> J[Top-1 / Top-5 / Top-10]
```

| Özellik | Değer |
|---|---:|
| Pressure sensor sayısı | 33 |
| Junction candidate sayısı | 782 |
| `S` shape | `(33, 782)` |
| `S_norm` shape | `(33, 782)` |

---

## 6. Localization Yöntemleri

```mermaid
flowchart TD
    A[r_mean residual vector] --> B[Global sensitivity]
    A --> C[MAS sensitivity]
    A --> D[XGBoost top-3 zones + sensitivity]

    B --> B1[Tüm 782 junction candidate]
    B1 --> B2[Sensitivity correlation ranking]

    C --> C1[Residual'a göre etkili sensör seçimi]
    C1 --> C2[Candidate set daraltma]
    C2 --> C3[Sensitivity correlation ranking]

    D --> D1[132 feature]
    D1 --> D2[XGBoost zone prediction]
    D2 --> D3[Top-3 zone candidate junctionları]
    D3 --> D4[Sensitivity correlation ranking]

    B2 --> E[Top-1 / Top-5 / Top-10]
    C3 --> E
    D4 --> E
```

| Yöntem | Candidate alanı | Mantık |
|---|---:|---|
| Global sensitivity | 782 junction | Tüm ağı arar |
| MAS sensitivity | Ortalama ~78 junction | Sensör etkisine göre arama alanını daraltır |
| XGBoost top-3 zones + sensitivity | Top-3 zone junctionları | Önce zone tahmini, sonra sensitivity ranking |

---

## 7. EPANET / L-TOWN Mapping

`src/epanet_model.py`, `data/L-TOWN.inp` dosyasını WNTR ile okur.

```mermaid
flowchart LR
    A[data/L-TOWN.inp] --> B[WNTR loader]
    B --> C[Junction coordinates]
    B --> D[Pipe endpoints]
    D --> E[Pipe midpoint]
    C --> F[Predicted junction coordinate]
    E --> G[True leak location]
    F --> H[Euclidean distance]
    G --> H
    H --> I[top1/top5/top10 error_m]
```

```text
true leak location = pipe midpoint
predicted location = predicted junction coordinate
error = EuclideanDistance(predicted junction, true pipe midpoint)
threshold = 300 m
```

---

## 8. XGBoost Hybrid Detayı

```mermaid
sequenceDiagram
    participant R as Residual Event
    participant F as Feature Builder
    participant X as XGBoost Model
    participant Z as Zone Map
    participant S as Sensitivity Ranking
    participant O as Output

    R->>F: 132 feature hazırla
    F->>X: predict_proba(features)
    X->>Z: top-1 zone + top-3 zones
    Z->>S: top-3 zone içindeki junctionları ver
    S->>O: Top-1 / Top-5 / Top-10 node prediction
```

```text
Model: data/xgb_zone_model.pkl
Kullanım: predict-only
Training: yapılmaz
```

---

## 9. Error Analysis Akışı

**Komut:**

```powershell
py -3.12 python_port\run_error_analysis.py --compare-existing --plot --threshold-m 300
```

```mermaid
flowchart TD
    A[localization_fair_cusum_per_leak.csv] --> B[Top-k error metrikleri]
    B --> C[300 m success flags]
    C --> D[Zone hit bilgileri]
    D --> E[Sensitivity strength]
    E --> F[Confidence gap / ratio]
    F --> G[Failure mode assignment]
    G --> H[localization_error_analysis.csv]
    G --> I[localization_error_compare_report.md]
    G --> J[PNG figürler]
```

| Failure mode | Anlamı |
|---|---|
| `success_within_300m` | Tahmin 300 m içinde başarılı |
| `weak_sensitivity` | Sensitivity sinyali zayıf |
| `wrong_zone` | XGBoost zone tahmini yanlış |
| `low_confidence` | Skor farkı/güven düşük |
| `candidate_filter_miss` | Doğru bölge candidate filtreye girmemiş |
| `large_distance_error` | Tahmin ciddi uzak |
| `unknown` | Net sınıfa girmeyen durum |

---

## 10. Üretilen Çıktılar

```mermaid
flowchart LR
    A[Detection] --> A1[detection_comparison.csv]
    A --> A2[detection_compare_report.md]
    A --> A3[demo_residual_norm.png]

    B[Localization] --> B1[localization_fair_cusum_per_leak.csv]
    B --> B2[localization_fair_cusum_summary.csv]
    B --> B3[localization_fair_cusum_features.csv]
    B --> B4[localization_fair_cusum_zone_predictions.csv]
    B --> B5[localization_compare_report.md]

    C[Error Analysis] --> C1[localization_error_analysis.csv]
    C --> C2[localization_error_compare_report.md]

    D[Figures] --> D1[localization_error_histogram.png]
    D --> D2[top1_error_by_method.png]
    D --> D3[xgb_zone_hit_vs_error.png]
    D --> D4[sensitivity_strength_map.png]
```

---

## 11. Sonuç Özeti

| Aşama | Method | Durum |
|---|---|---|
| Detection | CUSUM | Aktif |
| Detection | XBarFDM | Aktif |
| Detection | Hybrid = earliest(CUSUM, XBarFDM) | Aktif |
| Detection | PlanC | Çıkarıldı |
| Localization | Global sensitivity | Aktif, 29 leak |
| Localization | MAS sensitivity | Aktif, 29 leak |
| Localization | XGBoost top-3 zones + sensitivity | Aktif, 29 leak |

---

## 12. Hocaya 60 Saniyelik Anlatım

> MATLAB/Simulink ağırlıklı HydroTwin L-TOWN kaçak tespit ve konumlandırma hattını Python-only hale getirdim. Detection tarafında SCADA pressure verileri nominal baseline ile karşılaştırılıyor, residual norm üzerinden CUSUM, XBarFDM ve Hybrid detector çalışıyor. Localization tarafında sadece güvenilir CUSUM eventleri seçiliyor. Sonra Global sensitivity, MAS sensitivity ve XGBoost top-3 zones + sensitivity yöntemleriyle kaçak konumu tahmin ediliyor. Gerçek konum pipe midpoint olarak alınıyor, tahmin edilen junction ile arasındaki Euclidean mesafe hesaplanıyor ve 300 metre başarı eşiğiyle değerlendiriliyor. Python çıktıları MATLAB sonuçlarıyla floating point seviyesinde eşleşiyor.

---

## 13. Demo Sırası

1. `README.md` açılır.
2. `WORKFLOW_VISUAL.md` içindeki genel akış diyagramı gösterilir.
3. Terminalde uçtan uca pipeline çalıştırılır:

```powershell
py -3.12 python_port\run_all.py --compare-existing --plot
```

4. Şu dosyalar gösterilir:

```text
python_port/results/detection_compare_report.md
python_port/results/localization_compare_report.md
python_port/results/localization_fair_cusum_summary.csv
python_port/results/localization_error_analysis.csv
python_port/figures/top1_error_by_method.png
python_port/figures/localization_error_histogram.png
python_port/figures/xgb_zone_hit_vs_error.png
```

5. Son cümle:

> MATLAB dosyaları korunarak Python tarafında ayrı ve çalıştırılabilir bir port oluşturuldu. Pipeline tek komutla çalışıyor ve mevcut MATLAB çıktılarıyla karşılaştırma raporları üretiyor.
