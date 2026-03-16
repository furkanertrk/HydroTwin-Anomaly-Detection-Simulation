# HydroTwin — Görev Listesi (Task Checklist)

> **Mevcut Durum:** Hafta 7 tamamlanıyor → Hafta 8'e geçiş  
> **Son Güncelleme:** 16 Mart 2026

---

## ✅ Tamamlanan Görevler (Hafta 1-7)

- [x] Simulink hidrolik model (hafta2.slx, hafta3.slx)
- [x] Sızıntı Bloğu (Leak Block) tasarımı
- [x] Simulink'e Basınç Sensörü ekleme
- [x] Sentetik veri üretimi (100.001 satır, gürültülü + temiz)
- [x] CSV export rehberi (MATLAB → Python)
- [x] pH_Level ekleme (Python co-simulation)
- [x] 4 sensörlü nihai veri seti: `hydrotwin_full_iot_data.csv`
- [x] Etiketleme ve EDA
- [x] Random Forest eğitimi (baseline)
- [x] Isolation Forest eğitimi (3 sensör, %54.63)
- [x] XGBoost eğitimi (3 sensör, %100 başarı)
- [x] Streamlit Dashboard (canlı izleme, downsampling)
- [x] 16 Mart 2026 çalışma raporu

---

## 📌 Hafta 7 — Kalan İşler (Öncelik: ORTA)

- [ ] Sızıntı **şiddeti tahmini** (Severity Estimation)
  - Multi-class etiketleme: 0-Normal, 1-Küçük Sızıntı, 2-Büyük Sızıntı
  - Regresyon veya çok sınıflı sınıflandırma (XGBoost / RF)
- [ ] Sızıntı **konumlandırma** (Leak Localization)
  - Basınç düğüm farkları ile korelasyon analizi
  - Ters hidrolik modelleme (istersen basitleştirilebilir)
- [ ] Gri su kalite sınıflandırma — 3 sınıf (Temiz/Gri/Siyah)
  - Decision Tree veya XGBoost ile pH + Pressure bazlı

---

## 📌 Hafta 8 — Simulink-Python Entegrasyonu (Öncelik: YÜKSEK)

- [ ] `watchdog` Python kütüphanesi ile CSV dosya değişikliği izleme
  ```
  pip install watchdog
  ```
- [ ] Simulink CSV yazarken → Python otomatik algılama + AI tahmin
- [ ] Entegrasyon hata yönetimi (dosya kilitli, eksik satır vs.)
- [ ] Uçtan uca test: Simulink çalışıyor → Dashboard canlı güncellenyor

---

## 📌 Hafta 9 — Dashboard İyileştirme

- [ ] Sızıntı alarm geçmişi (log tablosu / timeline)
- [ ] Sistem Sağlık Skoru hesaplama ve gösterimi
- [ ] Su Kalite Sınıfı gösterimi (renk kodlu)
- [ ] Isolation Forest anomali skoru grafiği ekleme
- [ ] Dashboard UI/CSS iyileştirmeleri
- [ ] Multi-page yapı (Streamlit pages)

---

## 📌 Hafta 10 — Test ve Stres Senaryoları

- [ ] Aşırı basınç senaryosu
- [ ] Çoklu sızıntı (2+ eşzamanlı)
- [ ] Sensör kaybı / eksik veri senaryosu
- [ ] False Positive / False Negative detaylı analiz
- [ ] K-Fold Cross Validation ekleme (raporda vaat edildi)
- [ ] ROC-AUC eğrisi çizme
- [ ] Dashboard gecikme testi

---

## 📌 Hafta 11 — Raporlama

- [ ] IEEE formatında final raporu
- [ ] Kullanıcı kılavuzu (kurulum + çalıştırma)
- [ ] GitHub reposu düzenleme (README, requirements.txt, .gitignore)
- [ ] Kod temizliği ve docstring ekleme

---

## 📌 Hafta 12 — Final ve Teslim

- [ ] Demo / tanıtım videosu
- [ ] Sunum slaytları
- [ ] Danışman ile son kontrol
- [ ] Proje teslimi

---

## 🐛 Bilinen Bug'lar ve Teknik Borçlar

| # | Dosya | Sorun | Durum |
|---|-------|-------|-------|
| 1 | `anomali taspiti/egitim.py` | `df["time"]`/`df["leak"]` sütun hataları | ⚪ Kritik değil — eski dosya, yeni eğitim scripti var |
| 2 | `anomali taspiti/egitim.py` | `df.drop(columns=["Time","Flow_Rate"])` tüm sütunları siliyor | ⚪ Aynı — eski dosya |
| 3 | Genel | CSV dosyaları birden fazla klasörde tekrarlanıyor (~25 MB israf) | 🟡 Düşük öncelik |
| 4 | `egitim_xgboost.py` | Tek feature (`Flow_Rate`) kullanıyor — nihai script değil | ⚪ Bilgi — `yeniden_egitim` dosyası nihai |
| 5 | Dashboard | Statik CSV okuyor, Simulink ile canlı bağlantı yok | 🟡 Hafta 8'de çözülecek |
