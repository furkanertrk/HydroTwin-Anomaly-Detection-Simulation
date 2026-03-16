import joblib
#Modeli Başka Bir Dosyada/Zamanda Yükleme (Sanki bilgisayarı yeni açmışsın gibi)

print("\n[SİSTEM] Kaydedilen model diskten okunuyor...")

yuklenen_model = joblib.load('hydrotwin_rf_model.pkl')

# 3. Yüklenen Model ile Gerçek Zamanlı Test (Simülasyon)

# Diyelim ki sensörden anlık olarak '1390.5' debi verisi geldi. Bakalım AI ne diyecek?

anlik_sensor_verisi = [[1390.5]] # Çift köşeli parantez önemli (2D array bekler)

# Sızıntı var mı yok mu tahmin et (0 veya 1 döner)

anlik_tahmin = yuklenen_model.predict(anlik_sensor_verisi)

if anlik_tahmin[0] == 1:

    print(f"🚨 DİKKAT! Sensör Verisi: {anlik_sensor_verisi[0][0]} -> DURUM: SIZINTI TESPİT EDİLDİ!")

else:

    print(f"✅ Sistem Normal. Sensör Verisi: {anlik_sensor_verisi[0][0]} -> DURUM: TEMİZ AKIŞ.")