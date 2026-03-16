import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix
import matplotlib.pyplot as plt
import seaborn as sns
import joblib

print("[SİSTEM] Temiz Baseline Verisi Yükleniyor...")
df = pd.read_csv('hydrotwin_clean_data.csv')

df['Severity_Label'] = (df['Time'] >= 50).astype(int)

X = df[['Flow_Rate']]
y = df['Severity_Label']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42, stratify=y)

print("\n[AI] XGBoost 'Uzman Cerrah' Modeli Eğitiliyor...")
xgb_model = xgb.XGBClassifier(n_estimators=100, learning_rate=0.1, max_depth=5, random_state=42)
xgb_model.fit(X_train, y_train)

print("[AI] Test verileri üzerinde sınıflandırma yapılıyor...")
y_pred = xgb_model.predict(X_test)

accuracy = accuracy_score(y_test, y_pred)
print(f"\n==========================================")
print(f"🌟 XGBOOST BAŞARI ORANI: % {accuracy * 100:.2f}")
print(f"==========================================")

print("\nDetaylı Sınıflandırma Raporu (Precision & Recall):")
print(classification_report(y_test, y_pred, target_names=['Normal Akış (0)', 'Sızıntı (1)']))

cm = confusion_matrix(y_test, y_pred)
plt.figure(figsize=(6, 5))
sns.heatmap(cm, annot=True, fmt='d', cmap='Purples', cbar=False, 
            xticklabels=['Tahmin: Normal', 'Tahmin: Sızıntı'], 
            yticklabels=['Gerçek: Normal', 'Gerçek: Sızıntı'])
plt.title('XGBoost: Sızıntı Sınıflandırma Matrisi', fontweight='bold')
plt.show()

joblib.dump(xgb_model, 'hydrotwin_xgboost.pkl')
print("\n[BAŞARILI] XGBoost Modeli 'hydrotwin_xgboost.pkl' olarak kaydedildi!")