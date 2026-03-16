import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import IsolationForest
import xgboost as xgb
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix
import joblib

print("[SİSTEM] 4 Sensörlü Nihai Dijital İkiz Verisi Yükleniyor...")
df = pd.read_csv('hydrotwin_full_iot_data.csv')

df['Anomaly_Label'] = (df['Time'] >= 50).astype(int)

features = ['Flow_Rate', 'Pressure', 'pH_Level']
X = df[features]
y = df['Anomaly_Label']

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train_normal = X_scaled[df['Time'] < 50]

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.3, random_state=42, stratify=y)


print("\n[AI - Hafta 6] Isolation Forest (Pratisyen Hekim) Eğitiliyor...")
iso_forest = IsolationForest(n_estimators=100, contamination=0.01, random_state=42)
iso_forest.fit(X_train_normal)

y_pred_iso = iso_forest.predict(X_scaled)
y_pred_iso_formatted = np.where(y_pred_iso == -1, 1, 0)

print(f"🌟 ISOLATION FOREST BAŞARISI (3 Sensörlü): % {accuracy_score(y, y_pred_iso_formatted) * 100:.2f}")


print("\n[AI - Hafta 7] XGBoost (Uzman Cerrah) Eğitiliyor...")
xgb_model = xgb.XGBClassifier(n_estimators=100, learning_rate=0.1, max_depth=5, random_state=42)
xgb_model.fit(X_train, y_train)

y_pred_xgb = xgb_model.predict(X_test)

print(f"🌟 XGBOOST BAŞARISI (3 Sensörlü): % {accuracy_score(y_test, y_pred_xgb) * 100:.2f}")
print("\n📊 Su Kalitesi ve Sızıntı Sınıflandırma Raporu (XGBoost):")
print(classification_report(y_test, y_pred_xgb, target_names=['Normal Su (0)', 'Sızıntı + Gri Su Karışımı (1)']))


joblib.dump(iso_forest, 'hydrotwin_isolation_forest.pkl')
joblib.dump(xgb_model, 'hydrotwin_xgboost.pkl')
joblib.dump(scaler, 'hydrotwin_scaler.pkl')

print("\n[BAŞARILI] Tüm Çok Katmanlı Yapay Zeka Modelleri (.pkl) Diske Kaydedildi!")
print("Rapor Hedefleri: İlerleme %65 Tamamlandı!")