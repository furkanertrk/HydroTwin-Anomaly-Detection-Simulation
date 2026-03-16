# HydroTwin — İlerleme Raporu (Progress)

> **Son Güncelleme:** 16 Mart 2026  
> **Mevcut Hafta:** 7 (kısmen tamamlandı), Hafta 8'e geçiş aşaması  
> **Genel İlerleme:** ~%65-70

---

## ✅ Tamamlanan Haftalar

### Hafta 1 — Literatür Taraması ve Sistem Mimarisi (%5)
- [x] 12 akademik kaynak incelendi (MDPI, IEEE, Springer, RSC Advances)
- [x] Sistem mimari şeması: Simulink → CSV → Python → AI → Dashboard
- [x] Sensör parametre aralıkları belirlendi
- [x] Darcy-Weisbach denklemi referans olarak dokümante edildi

### Hafta 2 — Temel Hidrolik Modelleme (%15)
- [x] `hafta2.slx` → Rezervuar, pompa, ana boru hattı blokları
- [x] "Sağlıklı Akış" baseline senaryosu çalıştırıldı

### Hafta 3 — Sızıntı Bloğu Tasarımı (%25)
- [x] `hafta3.slx` → Leak Block tasarlandı
- [x] t=50 saniyede tetiklenen sızıntı senaryosu
- [x] **Basınç Sensörü (Pressure Sensor)** Simulink'e eklendi (Aşama 2'de)

### Hafta 4 — Sentetik Veri Üretimi (%35)
- [x] 100.001 satırlık sensör verisi CSV'ye aktarıldı
- [x] Gaussian White Noise eklendi (gürültülü versiyon)
- [x] Temiz (baseline) versiyon da üretildi
- [x] `hydrotwin_sensor_data_v3.csv` → [Time, Flow_Rate, Pressure] — 3 sütunlu!
- [x] MATLAB CSV export rehberi yazıldı (`matlab_csv_disarı_aktarma.md`)

### Hafta 5 — Veri Ön İşleme ve EDA (%40)
- [x] Veri temizleme, etiketleme (`Leak_Label` / `Anomaly_Label`)
- [x] Train/Val/Test bölmesi (stratified)
- [x] Zaman serisi görselleştirmesi (sızıntı noktası t=50)
- [x] **pH_Level** sentetik olarak Python co-simulation ile eklendi
  - Normal: ~7.2 (±0.02 gürültü)
  - Sızıntı (t≥50): 7.2 → 8.5 (yavaş artan gri su karışımı)
- [x] Nihai 4 sensörlü veri: `hydrotwin_full_iot_data.csv` [Time, Flow_Rate, Pressure, pH_Level]
- [x] Script: `etiketleme/veri_duzenleme_ve_ayarlama.py`

### Hafta 6 — Anomali Tespiti (AI Modül 1) (%55)
- [x] İlk deneme: Isolation Forest + Autoencoder (2 feature) → `anomali taspiti model egitimi/egitim.py`
- [x] Yeniden eğitim: 3 sensörlü Isolation Forest → `yeniden_egitim_isola_xgboost.py`
  - IsolationForest(n_estimators=100, contamination=0.01, random_state=42)
  - Başarı: **%54.63** (sızıntı oranı %50 → "nadir olay" algılama sınırı)
  - Akademik bulgu olarak kaydedildi
- [x] Modeller `.pkl` olarak kaydedildi

### Hafta 7 — Sınıflandırma ve Konumlandırma (AI Modül 2) (%65)
- [x] **Random Forest** eğitildi: tek feature baseline (`egitim_randomforest.py`)
- [x] **XGBoost baseline** eğitildi: tek feature, %99.98 başarı (`egitim_xgboost.py`)
- [x] **XGBoost nihai** eğitildi: 3 sensör, **%100 başarı** (`yeniden_egitim_isola_xgboost.py`)
  - XGBClassifier(n_estimators=100, learning_rate=0.1, max_depth=5)
  - Sızıntı + Gri Su Karışımı tespiti
- [x] Modeller kaydedildi: `hydrotwin_xgboost.pkl`, `hydrotwin_scaler.pkl`
- [x] Eğitilmiş modelle anlık tahmin scripti: `egitilen_model_calistirma.py`
- [ ] Sızıntı şiddeti tahmini (Severity — multi-class) — **henüz yapılmadı**
- [ ] Sızıntı konumlandırma (Leak Localization) — **henüz yapılmadı**

---

## 🆕 Ekstra İlerleme (Hafta 7 sırasında erken başlandı)

### Dashboard (Streamlit) — Normalde Hafta 9 hedefi
- [x] `dashboard/dashboard.py` geliştirildi!
- [x] Zaman Slider ile canlı simülasyon kontrolü
- [x] Anlık metrikler: Debi, Basınç, pH
- [x] XGBoost ile canlı sızıntı/gri su alarm sistemi
- [x] Çift çizgili hidrolik grafik (Flow_Rate + Pressure)
- [x] pH değişim grafiği
- [x] Downsampling optimizasyonu (800 satır limiti) → performans çözüldü
- [x] Çalışma raporu yazıldı: `Çalışma Raporu/calisma_raporu_16.03.2026.md`

---

## ⏳ Yapılacak Haftalar

### Hafta 8 — Simulink-Python Entegrasyonu (%75 hedef)
- [ ] Watchdog / Batch Processing yapısı (Simulink → CSV → Python anlık okuma)
- [ ] Uçtan uca prototype: Simulink çalışırken dashboard canlı güncelleme

### Hafta 9 — Dashboard İyileştirme (%85 hedef)
- [ ] Sızıntı geçmişi / log tablosu ekleme
- [ ] Sistem Sağlık Skoru widget'ı
- [ ] Su Kalite Sınıfı gösterimi (Temiz/Gri/Siyah)
- [ ] Responsive tasarım ve CSS iyileştirmeleri

### Hafta 10 — Stres Testleri (%90 hedef)
- [ ] Çoklu sızıntı, sensör kaybı, aşırı basınç senaryoları
- [ ] False Positive / False Negative analizi
- [ ] K-Fold Cross Validation + ROC-AUC

### Hafta 11 — Raporlama (%95 hedef)
- [ ] IEEE formatında teknik rapor
- [ ] Kullanıcı kılavuzu + GitHub repo

### Hafta 12 — Final Sunumu (%100)
- [ ] Tanıtım videosu + sunum materyalleri + teslim
