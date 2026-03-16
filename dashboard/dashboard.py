import streamlit as st
import pandas as pd
import joblib

st.set_page_config(page_title="HydroTwin Paneli", layout="wide")
st.title("🌊 HydroTwin: Dijital İkiz ve Kestirimci Bakım Paneli")
st.markdown("Fiziksel su şebekesinden gelen IoT sensör verileri ve XGBoost Yapay Zeka analiz ekranı.")

@st.cache_data
def veri_yukle():
    return pd.read_csv('hydrotwin_full_iot_data.csv')

@st.cache_resource
def model_yukle():
    xgb = joblib.load('hydrotwin_xgboost.pkl')
    scaler = joblib.load('hydrotwin_scaler.pkl')
    return xgb, scaler

df = veri_yukle()
xgb_model, scaler = model_yukle()

st.sidebar.header("Zaman Makinesi ⏱️")
st.sidebar.write("Simülasyon anını kaydırarak yapay zekanın tepkisini izleyin.")
anlik_zaman = st.sidebar.slider("Geçen Süre (Saniye)", int(df['Time'].min()), int(df['Time'].max()), 10)

anlik_veri = df[df['Time'] == anlik_zaman].iloc[-1]

X_anlik = pd.DataFrame([anlik_veri[['Flow_Rate', 'Pressure', 'pH_Level']]])
X_scaled = scaler.transform(X_anlik)

tahmin = xgb_model.predict(X_scaled)[0]

col1, col2, col3, col4 = st.columns(4)
col1.metric("Zaman", f"{anlik_zaman} s")
col2.metric("Debi (L/s)", f"{anlik_veri['Flow_Rate']:.2f}")
col3.metric("Basınç (kPa)", f"{anlik_veri['Pressure']:.2f}")
col4.metric("pH Seviyesi", f"{anlik_veri['pH_Level']:.2f}")

st.markdown("---")

if tahmin == 1:
    st.error("🚨 DİKKAT: SİSTEMDE SIZINTI VE GRİ SU KARIŞIMI TESPİT EDİLDİ! XGBoost Acil Bakım Öneriyor.")
else:
    st.success("✅ Sistem Normal: Akış, Basınç ve Su Kalitesi İdeal Seviyede.")

st.subheader("📈 Sensör Geçmişi (0. Saniyeden Şu Ana Kadar)")
gecmis_veri = df[df['Time'] <= anlik_zaman]

if len(gecmis_veri) > 800:
    adim = len(gecmis_veri) // 800
    cizim_verisi = gecmis_veri.iloc[::adim]
else:
    cizim_verisi = gecmis_veri

st.line_chart(cizim_verisi.set_index('Time')[['Flow_Rate', 'Pressure']])

st.subheader("🧪 Su Kalitesi Değişimi (pH)")
st.line_chart(cizim_verisi.set_index('Time')[['pH_Level']], color="#ffaa00")