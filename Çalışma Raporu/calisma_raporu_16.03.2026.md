# 16 Mart 2026 - HydroTwin Projesi Geliştirme Raporu

### Aşama 1: İdeal (Baseline) Fiziksel Modelin Kurulması ve İlk AI Testi

* **Yapılan İşlem:** Simulink modelindeki "Band-Limited White Noise" (Gürültü) blokları kaldırılarak, sistemin saf fiziksel tepkisini ölçmek adına ideal (baseline) debi verisi üretildi. Bu temiz veriyle XGBoost modeli eğitilerek %99.98 gibi kusursuz bir taban çizgisi (baseline) başarı oranı elde edildi.
* **Karşılaşılan Sorun:** Eğitim aşamasında `ModuleNotFoundError: No module named 'xgboost'` hatası alındı.
* **Çözüm:** Terminal üzerinden `pip install xgboost` komutuyla eksik kütüphane kurularak sorun hızlıca aşıldı.
* **Kritik Tespit:** Üretilen verinin proje kapsamındaki "gri su analizi" için yetersiz olduğu, sadece Debi (`Flow_Rate`) verisinin bulunduğu tespit edildi. Sisteme Basınç ve pH metriklerinin eklenmesine karar verildi.

### Aşama 2: Çoklu Sensör (IoT) Altyapısının Kurulması

* **Yapılan İşlem:** Simulink fizik modeline paralel bağlı bir **Basınç Sensörü (Pressure Sensor)** eklendi. Kimyasal özellikler Simulink'te hesaplanamadığı için Python kullanılarak "Co-Simulation" (Eş-Simülasyon) yöntemiyle **pH (Su Kalitesi)** verisi sentetik olarak üretilip sisteme entegre edildi. Sızıntı anında şebekeye "Gri Su" karıştığı senaryosu kodlandı.
* **Karşılaşılan Sorun:** MATLAB verileri dışarı aktarırken `Unrecognized field name "pressure_data"` hatası verdi.
* **Çözüm:** Simulink'teki yeni "To Workspace" bloğunun varsayılan isminin (`simout`) manuel olarak `pressure_data` şeklinde değiştirilmesiyle veri senkronizasyonu sağlandı.

### Aşama 3: Çok Katmanlı Yapay Zeka (AI) Modellerinin Nihai Eğitimi

* **Yapılan İşlem:** Hafta 6 (AI Modül 1) ve Hafta 7 (AI Modül 2) hedefleri doğrultusunda, elde edilen 3 sensörlü (Debi, Basınç, pH) nihai veri setiyle modeller yeniden eğitildi.
* **Performans Sonuçları:** * **Isolation Forest:** %54.63 başarı gösterdi. (Sızıntı süresinin toplam sürenin %50'sini kapsaması, "nadir olay" arayan bu algoritmanın teorik sınırlarına takılmasına neden oldu. Bu durum jüriye sunulacak akademik bir bulgu olarak kaydedildi).
* **XGBoost:** Çoklu sensör verisindeki örüntüleri yakalayarak sızıntı ve gri su tespitinde %100 başarı oranına ulaştı. Modeller `.pkl` formatında diske kaydedildi.



### Aşama 4: Canlı İzleme Paneli (Streamlit Dashboard) Geliştirimi

* **Yapılan İşlem:** Projenin görsel vitrini olan, gerçek zamanlı sensör verilerini ve XGBoost kararlarını anlık gösteren "Zaman Makineli" bir web arayüzü kodlandı.
* **Karşılaşılan Sorun 1:** Python kodu standart yöntemle çalıştırıldığında `Thread 'MainThread': missing ScriptRunContext!` hatası alındı ve web sunucusu başlamadı.
* **Çözüm 1:** Kodun `streamlit run dashboard.py` komutuyla kendi lokal web sunucusu üzerinden başlatılmasıyla sorun çözüldü.
* **Karşılaşılan Sorun 2:** Simülasyon verisinin devasa boyutu (on binlerce satır) nedeniyle tarayıcıda grafikler çizilirken aşırı kasma ve donma yaşandı.
* **Çözüm 2 (Mühendislik Optimizasyonu):** Arka planda yapay zekaya verinin tamamı verilirken, ön planda (grafiklerde) veriyi ekrana basmadan önce seyreltici bir algoritma **(Downsampling)** yazıldı. Bu sayede UI performansı kayıpsız bir şekilde hızlandırıldı ve sistem akıcı hale getirildi.

