import pandas as pd
import numpy as np

dosyalar = [
    {"giris": "hydrotwin_sensor_data_v3.csv", "cikis": "hydrotwin_full_iot_data.csv", "tip": "Gürültülü (Gerçek Dünya)"},
    {"giris": "hydrotwin_sensor_data_v3_clean.csv", "cikis": "hydrotwin_full_iot_data_clean.csv", "tip": "Temiz (İdeal Baseline)"}
]

for dosya in dosyalar:
    print(f"\n[SİSTEM] {dosya['tip']} veri seti okunuyor: {dosya['giris']}")
    try:
        df = pd.read_csv(dosya['giris'])
        
        df['pH_Level'] = np.random.normal(loc=7.2, scale=0.02, size=len(df))

        sizi_baslangici = 50.0
        sizi_indeksleri = df.index[df['Time'] >= sizi_baslangici].tolist()

        if sizi_indeksleri:
            artis_egrisi = np.linspace(0.0, 1.3, len(sizi_indeksleri))
            df.loc[df['Time'] >= sizi_baslangici, 'pH_Level'] += artis_egrisi

        df.to_csv(dosya['cikis'], index=False)
        print(f"[BAŞARILI] 4 Sensörlü (Zaman, Debi, Basınç, pH) veri seti '{dosya['cikis']}' olarak kaydedildi!")
        
    except FileNotFoundError:
        print(f"[HATA] '{dosya['giris']}' dosyası bulunamadı. Lütfen klasörde olduğundan emin ol.")

print("\n[BİLGİ] Tüm veri zenginleştirme işlemleri tamamlandı. Proje Dashboard (Arayüz) aşamasına hazır!")