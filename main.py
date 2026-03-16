import subprocess
import sys
import time
import os

def baslat():
    print("="*65)
    print("HYDROTWIN SİSTEMİ BAŞLATILIYOR...")
    print("="*65)

    # 1. Adım: Watchdog Servisini Arka Planda Başlat
    print("[1/2] Watchdog (Co-Simulation) servisi ayaklandırılıyor...")
    # sys.executable, bilgisayarındaki doğru Python sürümünü otomatik bulur
    watchdog_process = subprocess.Popen([sys.executable, "watchdog_entegrasyon.py"])
    
    # Watchdog'un tam olarak uyanması için 2 saniye bekle
    time.sleep(2)

    # 2. Adım: Streamlit Dashboard'unu Başlat
    print("[2/2] Streamlit Canlı İzleme Paneli başlatılıyor...")
    # cwd="dashboard" parametresi ile terminalin önce o klasöre girmesini sağlıyoruz
    dashboard_process = subprocess.Popen(
        [sys.executable, "-m", "streamlit", "run", "dashboard.py"], 
        cwd="dashboard" 
    )

    print("\n TÜM SİSTEMLER AKTİF!")
    print("Sistemi kapatmak için bu terminalde CTRL+C tuşlarına basabilirsiniz.\n")

    # 3. Adım: Sistemi Açık Tut ve Kapanış Komutunu (CTRL+C) Bekle
    try:
        # Kodun hemen bitmemesi için sonsuz bir bekleme döngüsü
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        # Kullanıcı CTRL+C'ye bastığında devreye girer
        print("\n" + "="*65)
        print(" SİSTEM KAPATILIYOR... LÜTFEN BEKLEYİN.")
        print("="*65)
        
        # Arka planda çalışan uygulamalara "kapan" sinyali gönder
        print("Watchdog servisi durduruluyor...")
        watchdog_process.terminate()
        
        print("Streamlit sunucusu durduruluyor...")
        dashboard_process.terminate()

        # Uygulamaların tamamen kapanmasını bekle
        watchdog_process.wait()
        dashboard_process.wait()
        
        print(" Sistem güvenli bir şekilde kapatıldı.")

if __name__ == "__main__":
    baslat()