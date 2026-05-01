%% s5_build_simulink_model.m — Dijital İkiz Simulink Modeli Oluşturucu
clc; clear; close all;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('📁 Proje kökü: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Veri ve config yükle (workspace'e koy, Simulink okuyacak)
fprintf('\n📥 Workspace hazırlanıyor...\n');

cfg = load_config();
load('data/sensitivity_matrix.mat');
scada = cache_scada('2018');

% p673 demo'su için zaman penceresi (sızıntıdan önce + sonra)
demo_start = datetime('2018-03-04 00:00:00');   % 1 gün önce
demo_end   = datetime('2018-03-25 00:00:00');   % 2 gün sonra
demo_mask  = (scada.time >= demo_start) & (scada.time <= demo_end);

% Time vector (saniye cinsinden, simulink From Workspace için)
demo_time_seconds = seconds(scada.time(demo_mask) - demo_start);
demo_pressures = scada.pressures(demo_mask, :);

% Workspace'e timeseries olarak koy
ts_pressure = timeseries(demo_pressures, demo_time_seconds, 'Name','SCADA_Pressure');
assignin('base', 'ts_pressure', ts_pressure);
assignin('base', 'demo_start', demo_start);

fprintf('   ✓ Demo verisi: %s → %s (%d sample)\n', ...
        string(demo_start), string(demo_end), length(demo_time_seconds));

%% Nominal baseline'ı yükle ve demo penceresine kırp
fprintf('\n📐 Nominal baseline kırpılıyor...\n');
nb = load('data/nominal_baseline.mat');

year_start = datetime('2018-01-01 00:00:00');
demo_start_sec = seconds(demo_start - year_start);
demo_end_sec   = seconds(demo_end   - year_start);

mask_nom = (nb.nominal_time >= demo_start_sec) & (nb.nominal_time <= demo_end_sec);
P_nominal_demo = nb.P_nominal(mask_nom, :);

%% Adaptif threshold offline hesabı (kalibrasyon q95 × 1.3)
fprintf('\n📐 Adaptif threshold hesaplanıyor...\n');
N_calib_offline = 288;
bias_offline = mean(demo_pressures(1:N_calib_offline,:) - P_nominal_demo(1:N_calib_offline,:), 1);
res_offline  = (P_nominal_demo + bias_offline) - demo_pressures;
norm_offline = vecnorm(res_offline, 2, 2);
calib_late   = norm_offline(N_calib_offline/2+1 : N_calib_offline);
threshold_adaptive = quantile(calib_late, 0.95) * 1.3;
fprintf('   ✓ threshold = %.2f m  (q95=%.2f × 1.3)\n', ...
        threshold_adaptive, quantile(calib_late, 0.95));

fprintf('   ✓ Nominal demo: %d sample × %d sensör\n', size(P_nominal_demo));

% Simulink coder.load için TEK dosyaya konsolide et
save('digital_twin_data.mat', ...
     'S_norm', 'junction_ids', 'P_nominal_demo', 'threshold_adaptive', '-v7.3');
fprintf('   ✓ digital_twin_data.mat güncellendi\n');

%% Simulink modelini oluştur
model_name = 'hydrotwin_realtime';

% Eski model varsa kapat ve sil
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
if exist(['simulink/' model_name '.slx'], 'file')
    delete(['simulink/' model_name '.slx']);
end

new_system(model_name);
open_system(model_name);

fprintf('\n🏗️  Simulink modeli inşa ediliyor: %s\n', model_name);

%% Block layout (positions: [x1 y1 x2 y2])
add_block('simulink/Sources/From Workspace', [model_name '/SCADA_Source'], ...
    'VariableName','ts_pressure', ...
    'Position',[50 100 180 160]);

add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [model_name '/Digital_Twin'], ...
    'Position',[270 90 430 170]);

% Residual = Twin - SCADA  (sızıntıda POZİTİF, S konvansiyonu ile uyumlu)
add_block('simulink/Math Operations/Sum', [model_name '/Residual'], ...
    'Inputs','-+', ...
    'IconShape','rectangular', ...
    'Position',[510 110 560 160]);

add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [model_name '/Leak_Detector'], ...
    'Position',[640 50 800 130]);

add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [model_name '/Leak_Localizer'], ...
    'Position',[640 170 800 250]);

add_block('simulink/Sinks/Scope', [model_name '/Pressure_Scope'], ...
    'Position',[510 30 570 80]);

add_block('simulink/Sinks/Display', [model_name '/Alarm_Display'], ...
    'Position',[870 70 990 110]);

add_block('simulink/Sinks/Display', [model_name '/Leak_Location_Display'], ...
    'Position',[870 190 990 230]);

add_block('simulink/Sinks/To Workspace', [model_name '/Save_Results'], ...
    'VariableName','sim_results', ...
    'Position',[870 270 990 310]);

%% Connections — DİKKAT: Residual girişleri sıralaması -+ ile uyumlu
% Residual port 1 = SCADA (eksi), Residual port 2 = Twin (artı)
add_line(model_name, 'SCADA_Source/1', 'Digital_Twin/1');
add_line(model_name, 'SCADA_Source/1', 'Residual/1');     % - (eksi)
add_line(model_name, 'SCADA_Source/1', 'Pressure_Scope/1');
add_line(model_name, 'Digital_Twin/1', 'Residual/2');     % + (artı)
add_line(model_name, 'Residual/1', 'Leak_Detector/1');
add_line(model_name, 'Residual/1', 'Leak_Localizer/1');
add_line(model_name, 'Leak_Detector/1', 'Alarm_Display/1');
add_line(model_name, 'Leak_Localizer/1', 'Leak_Location_Display/1');
add_line(model_name, 'Leak_Detector/1', 'Save_Results/1');

%% Simulation parameters
set_param(model_name, 'StopTime', num2str(max(demo_time_seconds)));
set_param(model_name, 'SolverType', 'Fixed-step');
set_param(model_name, 'FixedStep', '300');   % 5 dakika

%% Save
if ~exist('simulink', 'dir')
    mkdir('simulink');
end
save_system(model_name, fullfile('simulink', [model_name '.slx']));

fprintf('\n✅ Simulink modeli oluşturuldu!\n');
fprintf('   Konum: simulink/%s.slx\n', model_name);
fprintf('\n📝 SONRAKI ADIM (manuel):\n');
fprintf('   1. Simulink modeli açıldı\n');
fprintf('   2. Digital_Twin bloğuna çift tıkla, içine kod yapıştır\n');
fprintf('   3. Leak_Detector bloğuna kod yapıştır (threshold=1.5)\n');
fprintf('   4. Leak_Localizer bloğuna kod yapıştır\n');
fprintf('   5. Run butonuna bas → demo başlar\n');