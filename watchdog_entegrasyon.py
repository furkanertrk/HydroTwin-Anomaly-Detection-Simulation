import time
import os
import pandas as pd
import numpy as np
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Senin klasör yapına göre özel yollar (Paths)
# MATLAB'in veriyi kaydettiği yer (İzlenecek Dosya)
KAYNAK_DOSYA = os.path.join("veriler", "hydrotwin_sensor_data_v3.csv") 

# Streamlit Dashboard'un okuduğu yer (Yazılacak Dosya)
HEDEF_DOSYA = os.path.join("dashboard", "hydrotwin_full_iot_data.csv")

class VeriYakalaHandler(FileSystemEventHandler):
    def on_modified(self, event):
        # Eğer değişen dosya bizim kaynak dosyamızsa (MATLAB güncellediyse)
        if event.src_path.endswith("hydrotwin_sensor_data_v3.csv"):
            print(f"\n[WATCHDOG]  SİMÜLASYON VERİSİ GÜNCELLENDİ: {KAYNAK_DOSYA}")
            self.veriyi_isle_ve_zenginlestir()

    def veriyi_isle_ve_zenginlestir(self):
        try:
            # MATLAB'in dosyaya yazma işlemini tamamen bitirmesi için 2 saniye bekle
            time.sleep(2) 
            
            print("[BATCH PROCESSING] Ham veriler (Debi, Basınç) Python katmanına çekiliyor...")
            df = pd.read_csv(KAYNAK_DOSYA)
            
            # --- pH ve Su Kalitesi (Gri Su) Sentezi ---
            print("[CO-SIMULATION] pH ve Su Kalitesi değerleri sentezleniyor...")
            df['pH_Level'] = np.random.normal(loc=7.2, scale=0.02, size=len(df))
            
            # =================================================================
            # AKILLI SIZINTI TESPİT ALGORİTMASI (Dinamik Tetikleyici)
            # =================================================================
            # Debideki (veya basınçtaki) ardışık satırlar arasındaki farkı hesapla
            debi_farki = df['Flow_Rate'].diff()
            
            # En büyük sıçramanın yaşandığı satırın indeksini bul
            krilma_noktasi_indeks = debi_farki.idxmax()
            
            # O satırdaki 'Time' değerini alarak sızıntı başlangıcını otomatik belirle
            sizi_baslangici = df.loc[krilma_noktasi_indeks, 'Time']
            
            # Ufak gürültüleri sızıntı sanmaması için bir güvenlik eşiği (Örn: Sıçrama 5'ten büyükse sızıntıdır)
            if debi_farki.max() > 5.0:
                print(f"[AKILLI TESPİT] ⚡ Sızıntı anı otomatik olarak {sizi_baslangici}. saniyede yakalandı!")
            else:
                sizi_baslangici = 999999.0 # Sızıntı yoksa sonsuz bir süreye at
                print("[AKILLI TESPİT] Sistemde belirgin bir sızıntı tespit edilmedi.")
            # =================================================================

            sizi_indeksleri = df.index[df['Time'] >= sizi_baslangici].tolist()

            if sizi_indeksleri:
                artis_egrisi = np.linspace(0.0, 1.3, len(sizi_indeksleri))
                df.loc[df['Time'] >= sizi_baslangici, 'pH_Level'] += artis_egrisi

            # Dashboard'un okuduğu hedef klasöre kaydet
            df.to_csv(HEDEF_DOSYA, index=False)
            print(f"[BAŞARILI] Veri zenginleştirildi ve {HEDEF_DOSYA} konumuna aktarıldı.")
            print("🚀 Dashboard otomatik olarak güncelleniyor!\n")
            print("⏳ Watchdog nöbette... MATLAB'den yeni simülasyon bekleniyor...")
            
        except Exception as e:
            print(f"[HATA] Dosya okunurken/yazılırken bir sorun oluştu: {e}")

if __name__ == "__main__":
    # Sadece "veriler" klasörünün içini izle
    izlenecek_klasor = "veriler" 
    
    olay_yoneticisi = VeriYakalaHandler()
    gozlemci = Observer()
    # recursive=False çünkü alt klasörlere inmesine gerek yok
    gozlemci.schedule(olay_yoneticisi, path=izlenecek_klasor, recursive=False) 
    gozlemci.start()
    
    print("="*65)
    print("🐕 HYDROTWIN WATCHDOG (CO-SIMULATION) SİSTEMİ AKTİF")
    print(f"İzlenen Klasör: '{izlenecek_klasor}/' | Çıkış için CTRL+C'ye basın.")
    print("="*65)

    try:
        while True:
            time.sleep(1) # Sistemi yormadan uykuda bekle
    except KeyboardInterrupt:
        gozlemci.stop()
        print("\n[WATCHDOG] Sistem güvenli bir şekilde kapatıldı.")
    gozlemci.join()