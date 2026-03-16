import pandas as pd
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import joblib

# 1. Veriyi Oku ve Hazırla
print("Veri yükleniyor...")
df = pd.read_csv('hydrotwin_sensor_data.csv')
df['Leak_Label'] = (df['Time'] >= 50).astype(int)

# Girdi (X) ve Çıktı (y) belirleme
# İleride buraya Basınç (Pressure) verisini de ekleyeceğiz, şimdilik sadece Debi (Flow_Rate)
X = df[['Flow_Rate']] 
y = df['Leak_Label']

# Veriyi Böl
X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.30, random_state=42, stratify=y)
X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.50, random_state=42, stratify=y_temp)

# 2. YAPAY ZEKA MODELİNİ EĞİTME (Model Training)
print("\n[AI] Random Forest Modeli Eğitiliyor (Lütfen bekleyin, RTX 4060'ın gücü devreye giriyor!)...")
# 100 karar ağacı (n_estimators=100) ile ormanı kuruyoruz
rf_model = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
rf_model.fit(X_train, y_train)

# 3. TEST VE DOĞRULAMA (Prediction)
print("[AI] Test verileri üzerinde sızıntı tahmini yapılıyor...")
y_pred = rf_model.predict(X_test)

# 4. SONUÇLAR VE BAŞARI ORANI (Evaluation)
accuracy = accuracy_score(y_test, y_pred)
print(f"\n==========================================")
print(f"🌟 MODEL BAŞARI ORANI (Accuracy): % {accuracy * 100:.2f}")
print(f"==========================================")

print("\nDetaylı Sınıflandırma Raporu:")
print(classification_report(y_test, y_pred, target_names=['Normal (0)', 'Sızıntı (1)']))

# 5. KARMAŞIKLIK MATRİSİ (Confusion Matrix) Görselleştirme
cm = confusion_matrix(y_test, y_pred)
plt.figure(figsize=(6, 5))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', cbar=False, 
            xticklabels=['Tahmin: Normal', 'Tahmin: Sızıntı'], 
            yticklabels=['Gerçek: Normal', 'Gerçek: Sızıntı'])
plt.title('Yapay Zeka Karar Matrisi (Confusion Matrix)', fontweight='bold')
plt.show()


#Eğitilmiş Modeli Bilgisayara Kaydetme (.pkl formatında)
model_dosya_adi = 'hydrotwin_rf_model.pkl'
joblib.dump(rf_model, model_dosya_adi)
print(f"\n[BAŞARILI] Yapay zeka modeli '{model_dosya_adi}' adıyla bilgisayarına kaydedildi!")
