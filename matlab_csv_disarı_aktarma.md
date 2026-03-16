% 1. Zaman, Debi ve YENİ Basınç verilerini hafızadan çek
zaman = out.sensor_data.Time;
debi = out.sensor_data.Data;
basinc = out.pressure_data.Data; % Senin eklediğin yeni sensörün verisi

% 2. Bunları 3 sütunlu bir Tabloya dönüştür
veri_tablosu = table(zaman, debi, basinc, 'VariableNames', {'Time', 'Flow_Rate', 'Pressure'});

% 3. Tabloyu bilgisayarına CSV olarak kaydet
writetable(veri_tablosu, 'veriler/hydrotwin_sensor_data_v3.csv');