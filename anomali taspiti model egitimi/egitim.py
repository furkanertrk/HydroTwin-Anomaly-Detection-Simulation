import pandas as pd
import numpy as np

from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import IsolationForest
from sklearn.metrics import classification_report, confusion_matrix

from tensorflow import keras
from tensorflow.keras import layers

# ================================
# 1. DATA LOAD
# ================================

print("Veri yükleniyor...")

df = pd.read_csv("hydrotwin_sensor_data2.csv")

time = df["time"].values
labels = df["leak"].values

features = df.drop(columns=["Time", "Flow_Rate"]).values


# ================================
# 2. SCALE
# ================================

scaler = StandardScaler()
features = scaler.fit_transform(features)


# ================================
# 3. TRAIN TEST SPLIT
# ================================

# ilk 50 saniye kesin normal

train_mask = time < 50
test_mask = time >= 50

X_train = features[train_mask]
X_test = features[test_mask]

y_test = labels[test_mask]


# ================================
# 4. WINDOW CREATION
# ================================

WINDOW = 10

def create_windows(X, y=None):

    windows = []
    labels = []

    for i in range(len(X) - WINDOW):

        w = X[i:i+WINDOW]
        windows.append(w)

        if y is not None:
            labels.append(int(np.max(y[i:i+WINDOW])))

    if y is None:
        return np.array(windows)

    return np.array(windows), np.array(labels)


X_train_w = create_windows(X_train)

X_test_w, y_test_w = create_windows(X_test, y_test)

X_train_flat = X_train_w.reshape(len(X_train_w), -1)
X_test_flat = X_test_w.reshape(len(X_test_w), -1)


# ================================
# 5. ISOLATION FOREST
# ================================

print("Isolation Forest eğitiliyor")

iso = IsolationForest(
    n_estimators=300,
    contamination=0.05,
    random_state=42,
    n_jobs=-1
)

iso.fit(X_train_flat)

iso_scores = -iso.decision_function(X_test_flat)

iso_thr = np.percentile(-iso.decision_function(X_train_flat), 95)

iso_pred = (iso_scores > iso_thr).astype(int)


# ================================
# 6. AUTOENCODER
# ================================

print("Autoencoder eğitiliyor")

input_dim = X_train_flat.shape[1]

model = keras.Sequential([
    
    layers.Dense(128, activation="relu", input_shape=(input_dim,)),
    layers.Dense(64, activation="relu"),
    layers.Dense(32, activation="relu"),
    
    layers.Dense(64, activation="relu"),
    layers.Dense(128, activation="relu"),
    
    layers.Dense(input_dim)
])

model.compile(
    optimizer="adam",
    loss="mse"
)

early = keras.callbacks.EarlyStopping(
    patience=10,
    restore_best_weights=True
)

model.fit(
    X_train_flat,
    X_train_flat,
    epochs=200,
    batch_size=256,
    validation_split=0.1,
    callbacks=[early],
    verbose=1
)


# ================================
# 7. AE SCORE
# ================================

recon = model.predict(X_test_flat)

mse = np.mean((X_test_flat - recon)**2, axis=1)

train_recon = model.predict(X_train_flat)

train_mse = np.mean((X_train_flat - train_recon)**2, axis=1)

ae_thr = np.percentile(train_mse, 95)

ae_pred = (mse > ae_thr).astype(int)


# ================================
# 8. FUSION
# ================================

fusion = ((iso_pred + ae_pred) >= 1).astype(int)


# ================================
# 9. RESULTS
# ================================

print("\nIsolation Forest")
print(classification_report(y_test_w, iso_pred))

print("\nAutoencoder")
print(classification_report(y_test_w, ae_pred))

print("\nFusion")
print(classification_report(y_test_w, fusion))


print("\nConfusion Matrix (Fusion)")
print(confusion_matrix(y_test_w, fusion))


# ================================
# 10. SAVE
# ================================

model.save("autoencoder.keras")

import joblib

joblib.dump(iso, "iso_model.pkl")
joblib.dump(scaler, "scaler.pkl")

print("Modeller kaydedildi")