%% s3_run_digital_twin.m — Simulink modelini programatik oluştur
clc; clear;
addpath(genpath('toolkit'));
addpath(genpath('scripts/helpers'));
load('project_config.mat');
load('sensitivity_matrix.mat');

% SCADA verisini yükle
scada_P = readtable('data/2018_SCADA_Pressures.csv');
scada_D = readtable('data/2018_SCADA_Demands.csv');  % AMR tüketimleri

% MATLAB workspace'ine timeseries olarak koy (From Workspace bloğu okuyacak)
t = (0:size(scada_P,1)-1)' * 300;  % 5 dakika = 300 saniye
ts_pressure  = timeseries(table2array(scada_P(:, 2:end)), t, 'Name','scada_pressure');
ts_demand    = timeseries(table2array(scada_D(:, 2:end)), t, 'Name','scada_demand');

assignin('base','ts_pressure',ts_pressure);
assignin('base','ts_demand',ts_demand);
assignin('base','S_norm',S_norm);
assignin('base','junction_ids',{junction_ids});

% Simulink modelini oluştur
model_name = 'ltown_digital_twin';
if exist([model_name '.slx'], 'file')
    delete([model_name '.slx']);
end
new_system(model_name);
open_system(model_name);

% Blokları yerleştir (pozisyonlar: [x1 y1 x2 y2])
add_block('simulink/Sources/From Workspace', [model_name '/SCADA_Pressure'],...
    'VariableName','ts_pressure', 'Position',[50 50 150 100]);

add_block('simulink/Sources/From Workspace', [model_name '/SCADA_Demand'],...
    'VariableName','ts_demand', 'Position',[50 150 150 200]);

% Dijital ikiz bloğu (MATLAB Function)
add_block('simulink/User-Defined Functions/MATLAB Function',...
    [model_name '/Digital_Twin'], 'Position',[250 130 400 200]);
% Not: Bu bloğun içine elle digital_twin_step çağrısını yapıştıracaksın
%      (programatik içerik yazmak zor; Simulink açılınca çift tıklayıp kodu koy)

% Residual (Sum bloğu)
add_block('simulink/Math Operations/Sum', [model_name '/Residual'],...
    'Inputs','+-', 'Position',[500 80 550 130]);

% Leak detector
add_block('simulink/User-Defined Functions/MATLAB Function',...
    [model_name '/Leak_Detector'], 'Position',[650 60 800 130]);

% Leak localizer
add_block('simulink/User-Defined Functions/MATLAB Function',...
    [model_name '/Leak_Localizer'], 'Position',[650 160 800 230]);

% Alarm scope
add_block('simulink/Sinks/Scope', [model_name '/Alarm_Scope'],...
    'Position',[900 80 960 120]);

% Display for leak location
add_block('simulink/Sinks/Display', [model_name '/Leak_Location'],...
    'Position',[900 180 1000 220]);

% To Workspace (sonuçları kaydet)
add_block('simulink/Sinks/To Workspace', [model_name '/Results'],...
    'VariableName','detection_results', 'Position',[900 260 1000 300]);

% Bağlantıları kur
add_line(model_name, 'SCADA_Pressure/1', 'Residual/1');
add_line(model_name, 'SCADA_Demand/1',   'Digital_Twin/1');
add_line(model_name, 'Digital_Twin/1',   'Residual/2');
add_line(model_name, 'Residual/1',       'Leak_Detector/1');
add_line(model_name, 'Residual/1',       'Leak_Localizer/1');
add_line(model_name, 'Leak_Detector/1',  'Alarm_Scope/1');
add_line(model_name, 'Leak_Localizer/1', 'Leak_Location/1');
add_line(model_name, 'Leak_Detector/1',  'Results/1');

% Simülasyon parametreleri (real-time için)
set_param(model_name, 'StopTime', '86400*7');   % 7 gün demo
set_param(model_name, 'SolverType','Fixed-step');
set_param(model_name, 'FixedStep','300');       % 5 dk'lık adım

save_system(model_name, fullfile('simulink', [model_name '.slx']));
fprintf('✅ Simulink modeli oluşturuldu: simulink/%s.slx\n', model_name);
fprintf('   Açıp MATLAB Function bloklarının içine yukarıdaki helper\n');
fprintf('   fonksiyonların çağrılarını yapıştır, sonra Run''a bas.\n');