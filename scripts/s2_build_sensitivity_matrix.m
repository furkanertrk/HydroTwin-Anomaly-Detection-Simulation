%% s2_build_sensitivity_matrix.m — Localization için duyarlılık matrisi
clc; clear;

% Proje köküne git
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('📁 Proje kökü: %s\n', pwd);

% Toolkit ve helper'lar
run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Config ve model yükle
cfg = load_config();
d = load_ltown();

%% Basınç sensörlerinin EPANET indekslerini bul
n_sensors = length(cfg.pressure_sensors);
sensor_indices = zeros(n_sensors, 1);
for i = 1:n_sensors
    sensor_indices(i) = d.getNodeIndex(cfg.pressure_sensors{i});
end
fprintf('✓ %d basınç sensörü haritalandı\n', n_sensors);

%% Tüm junction'ları al
junction_ids = d.getNodeJunctionNameID;
n_junctions = length(junction_ids);
junction_indices = zeros(n_junctions, 1);
for i = 1:n_junctions
    junction_indices(i) = d.getNodeIndex(junction_ids{i});
end
fprintf('✓ %d junction belirlendi\n', n_junctions);

%% Baseline (steady-state)
fprintf('\n📊 Baseline (sızıntısız) hidrolik çözümü...\n');
tic;

d.setTimeSimulationDuration(3600);
d.setTimeHydraulicStep(3600);

d.solveCompleteHydraulics;
all_pressures = d.getNodePressure();
P_baseline = all_pressures(sensor_indices);

fprintf('   ✓ Baseline hesaplandı (%.1f sn)\n', toc);
fprintf('   Baseline ortalama basınç: %.2f m\n', mean(P_baseline));

%% Sensitivity matrix
fprintf('\n⚙️  Sensitivity matrix inşası başlıyor...\n');
fprintf('   Junction sayısı: %d\n', n_junctions);

S = zeros(n_sensors, n_junctions);
emitter_coeff = 0.75;

fprintf('\n');
t_start = tic;
for i = 1:n_junctions
    d.setNodeEmitterCoeff(junction_indices(i), emitter_coeff);
    
    d.solveCompleteHydraulics;
    all_pressures = d.getNodePressure();
    P_leak = all_pressures(sensor_indices);
    
    S(:, i) = P_baseline - P_leak;
    
    d.setNodeEmitterCoeff(junction_indices(i), 0);
    
    if mod(i, 50) == 0 || i == n_junctions
        elapsed = toc(t_start);
        rate = i / elapsed;
        eta = (n_junctions - i) / rate;
        fprintf('   %4d/%d  [%.1f%%]  geçen: %.1f sn  kalan: %.1f sn\n', ...
                i, n_junctions, 100*i/n_junctions, elapsed, eta);
    end
end

total_time = toc(t_start);
fprintf('\n✅ Sensitivity matrix hazır (%.1f saniye)\n', total_time);

%% Normalize
S_norm = S ./ (vecnorm(S, 2, 1) + 1e-9);

%% İstatistikler
fprintf('\n📊 Matrix istatistikleri:\n');
fprintf('   Boyut:          %d × %d\n', size(S,1), size(S,2));
fprintf('   Min duyarlılık: %.4f m\n', min(S(:)));
fprintf('   Max duyarlılık: %.4f m\n', max(S(:)));
fprintf('   Ortalama:       %.4f m\n', mean(S(:)));
fprintf('   Medyan:         %.4f m\n', median(S(:)));

%% Kaydet
save('data/sensitivity_matrix.mat', ...
     'S', 'S_norm', ...
     'junction_ids', 'junction_indices', ...
     'sensor_indices', 'P_baseline', ...
     'emitter_coeff', '-v7.3');

fprintf('\n💾 Kaydedildi: data/sensitivity_matrix.mat\n');

d.unload;