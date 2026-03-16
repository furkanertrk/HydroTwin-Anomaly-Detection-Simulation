# HydroTwin — AI Agent Rehber Dosyası

## 🎯 Proje Özeti

**HydroTwin**, kampüs/bina ölçeğinde su dağıtım ağının **Dijital İkiz (Digital Twin)** teknolojisi ile modellenmesini amaçlayan bir dönem projesidir. Sistem, MATLAB/Simulink ile fiziksel boru hattı simülasyonu yaparak sentetik sensör verisi üretir ve Python'da eğitilen **Yapay Zeka** modelleri ile sızıntı tespiti + su kalitesi analizi gerçekleştirir.

**Öğrenci:** Furkan Ertürk — `24100011810`  
**Dönem:** 2025-2026 Bahar Dönemi

---

## 📁 Proje Dizin Yapısı

```
Dönem Projesi/
├── 24100011810_Furkan_Erturk.docx          # Ana proje raporu (IEEE yolunda)
├── matlab_csv_disarı_aktarma.md            # MATLAB'dan CSV export rehberi (Basınç dahil)
├── hafta2.slx                              # Simulink — Temel hidrolik model (baseline)
├── hafta3.slx                              # Simulink — Sızıntı bloğu + Basınç sensörü ekli
├── slprj/                                  # Simulink build dosyaları (otomatik)
│
├── veriler/                                # Ham ve işlenmiş veri setleri
│   ├── hydrotwin_sensor_data_v3.csv        # Simulink çıktısı [Time, Flow_Rate, Pressure] — gürültülü
│   ├── hydrotwin_sensor_data_v3_clean.csv  # Simulink çıktısı [Time, Flow_Rate, Pressure] — temiz
│   ├── hydrotwin_full_iot_data.csv         # Nihai 4 sensörlü veri [+pH_Level] — gürültülü (100001×4)
│   └── hydrotwin_full_iot_data_clean.csv   # Nihai 4 sensörlü veri [+pH_Level] — temiz
│
├── etiketleme/
│   ├── etiketleme.py                       # İlk etiketleme + EDA (eski, sadece Flow_Rate)
│   ├── veri_duzenleme_ve_ayarlama.py       # pH_Level ekleme + gri su senaryosu (Co-Simulation)
│   ├── hydrotwin_full_iot_data.csv         # → Kopyası (çıktı)
│   ├── hydrotwin_full_iot_data_clean.csv   # → Kopyası (çıktı)
│   └── Figure_1.png                        # EDA grafiği
│
├── model eğitimi/
│   ├── egitim_randomforest.py              # Random Forest (tek feature — Flow_Rate)
│   ├── egitim_xgboost.py                   # XGBoost (tek feature — baseline)
│   ├── yeniden_egitim_isola_xgboost.py     # ✅ NİHAİ: 3 sensörlü IsoForest + XGBoost eğitimi
│   ├── egitilen_model_calistirma.py        # RF modeli ile anlık tahmin scripti
│   ├── hydrotwin_rf_model.pkl              # Eğitilmiş Random Forest (~76 MB)
│   ├── hydrotwin_xgboost.pkl              # Eğitilmiş XGBoost (nihai)
│   ├── hydrotwin_isolation_forest.pkl     # Eğitilmiş Isolation Forest (nihai)
│   ├── hydrotwin_scaler.pkl               # StandardScaler (3 feature)
│   ├── hydrotwin_full_iot_data.csv        # Eğitim verisi kopyası
│   ├── hydrotwin_full_iot_data_clean.csv  # Temiz baseline verisi
│   ├── hydrotwin_clean_data.csv           # Eski temiz veri (Flow_Rate only)
│   ├── hydrotwin_sensor_data.csv          # Eski veri (v1)
│   └── Figure_1.png                       # Confusion matrix
│
├── anomali taspiti model egitimi/          # Hafta 6 — İlk anomali tespiti denemeleri
│   ├── egitim.py                           # Isolation Forest + Autoencoder (eski, 2 feature)
│   ├── hydrotwin_autoencoder.keras         # Autoencoder modeli (eski)
│   ├── hydrotwin_iso.pkl                   # IsoForest modeli (eski)
│   ├── hydrotwin_scaler.pkl               # Scaler (eski)
│   ├── models/                            # İkinci iterasyon model dosyaları
│   └── Figure_1.png                       # Anomali grafiği
│
├── dashboard/
│   ├── dashboard.py                        # ✅ Streamlit Dashboard — Canlı izleme paneli
│   ├── hydrotwin_full_iot_data.csv        # Dashboard veri kaynağı
│   ├── hydrotwin_xgboost.pkl              # Dashboard AI modeli
│   ├── hydrotwin_isolation_forest.pkl     # Dashboard IsoForest
│   └── hydrotwin_scaler.pkl               # Dashboard Scaler
│
├── Çalışma Raporu/
│   ├── 20.02.2026 çalışma raporu.docx     # İlk çalışma raporu
│   └── calisma_raporu_16.03.2026.md       # Güncel çalışma raporu (4 aşamalı)
│
├── agent.md                               # ← Bu dosya
├── progress.md                            # Hafta-hafta ilerleme
└── task.md                                # Kalan görevler checklist
```

---

## 🔧 Teknoloji Yığını

| Katman            | Araç / Kütüphane                                  |
|-------------------|----------------------------------------------------|
| Simülasyon        | MATLAB R2024a + Simulink                           |
| Veri İşleme       | Python 3.12, Pandas, NumPy                         |
| Görselleştirme    | Matplotlib, Seaborn, Streamlit (Dashboard)         |
| ML — Denetimli    | scikit-learn (RandomForest), XGBoost               |
| ML — Denetimsiz   | scikit-learn (IsolationForest), TensorFlow/Keras (AE — eski) |
| Model Saklama     | joblib (.pkl), Keras (.keras/.h5)                  |
| Dashboard         | Streamlit (web tabanlı, lokal sunucu)              |
| GPU               | NVIDIA RTX 4060                                    |

---

## 🧠 Mevcut Model Pipeline (Güncel — 3 Sensörlü)

### Veri Akışı
```
Simulink (hafta3.slx)
  → CSV export [Time, Flow_Rate, Pressure]
    → Python co-simulation (pH_Level ekleme)
      → hydrotwin_full_iot_data.csv [Time, Flow_Rate, Pressure, pH_Level] (100001×4)
        → AI Modelleri → Dashboard
```

### Nihai Eğitim Scripti: `yeniden_egitim_isola_xgboost.py`
- **Features:** `[Flow_Rate, Pressure, pH_Level]` (3 sensör)
- **Etiket:** `Anomaly_Label` → `Time >= 50` ise 1, değilse 0
- **Scaler:** StandardScaler (3 feature normalize)
- **Isolation Forest:** n_estimators=100, contamination=0.01 → **%54.63** başarı
  - Akademik bulgu: Sızıntı süresi %50 → "nadir olay" algılaması zor
- **XGBoost:** n_estimators=100, learning_rate=0.1, max_depth=5 → **%100** başarı
- **Modeller:** `hydrotwin_xgboost.pkl`, `hydrotwin_isolation_forest.pkl`, `hydrotwin_scaler.pkl`

### Dashboard: `dashboard/dashboard.py`
- Streamlit web arayüzü (`streamlit run dashboard.py`)
- Zaman slider ile simülasyon anı kontrol
- Anlık metrikler: Debi, Basınç, pH
- XGBoost ile canlı sızıntı/gri su kararı
- Çift çizgili hidrolik grafik + pH grafiği
- Downsampling optimizasyonu (800 satır limiti)

---

## ⚠️ Bilinen Sorunlar ve Notlar

1. **`anomali taspiti model egitimi/egitim.py`** — Eski dosya, hala bug'lı (`df["time"]`/`df["leak"]` hataları). Artık ana eğitim dosyası `model eğitimi/yeniden_egitim_isola_xgboost.py` olarak güncellendiği için kritik değil.
2. **Isolation Forest %54.63** — Düşük, ama sızıntı/normal oranı %50/%50 olduğu için beklenen. Raporda akademik yorum olarak kullanılacak.
3. **Sızıntı konumlandırma** ve **şiddet tahmini** (multi-class severity) henüz tamamlanmadı.
4. **Dashboard** henüz Watchdog/Batch Processing ile Simulink'e bağlanmadı (statik CSV okuyor).
5. CSV dosya kopyaları birden fazla klasörde mevcut — disk alanı optimizasyonu yapılabilir.

---

## 📌 Kurallar (Bu Projeye Özel)

- Python dosyaları **UTF-8** encoding kullanmalı.
- Modeller `.pkl` (joblib) formatında kaydedilir.
- Simulink dosyaları `.slx` — doğrudan düzenleme yapılmaz (MATLAB gerekir).
- Dashboard: `streamlit run dashboard.py` ile çalıştırılır (normal `python` komutu çalışmaz).
- Nihai veri kaynağı: `hydrotwin_full_iot_data.csv` (4 sütun, 100001 satır).
- Rapor IEEE formatına uygun biçimde yazılacak (Hafta 11).
