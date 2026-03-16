import joblib

print("\n[SİSTEM] Kaydedilen model diskten okunuyor...")

yuklenen_model = joblib.load('hydrotwin_rf_model.pkl')



anlik_sensor_verisi = [[1390.5]]


anlik_tahmin = yuklenen_model.predict(anlik_sensor_verisi)

if anlik_tahmin[0] == 1:

    print(f"🚨 DİKKAT! Sensör Verisi: {anlik_sensor_verisi[0][0]} -> DURUM: SIZINTI TESPİT EDİLDİ!")

else:

    print(f"✅ Sistem Normal. Sensör Verisi: {anlik_sensor_verisi[0][0]} -> DURUM: TEMİZ AKIŞ.")