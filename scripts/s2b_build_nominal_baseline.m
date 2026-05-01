%% s2b_build_nominal_baseline.m — Yıllık nominal basınç (manual stepping)
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('📁 Proje kökü: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

cfg = load_config();
d = load_ltown();

% Sensör indeksleri
n_sensors = length(cfg.pressure_sensors);
sensor_indices = zeros(n_sensors, 1);
for i = 1:n_sensors
    sensor_indices(i) = d.getNodeIndex(cfg.pressure_sensors{i});
end
fprintf('✓ %d basınç sensörü haritalandı\n', n_sensors);

% TÜM emitter'ları sıfırla (temiz nominal)
junction_ids = d.getNodeJunctionNameID;
for i = 1:length(junction_ids)
    d.setNodeEmitterCoeff(d.getNodeIndex(junction_ids{i}), 0);
end
fprintf('✓ Emitter''lar sıfırlandı\n');

%% EPS ayarları: 1 yıl, 5 dakika reporting
year_seconds = 365 * 24 * 3600;
step_seconds = 300;
d.setTimeSimulationDuration(year_seconds);
d.setTimeHydraulicStep(step_seconds);
d.setTimeReportingStep(step_seconds);

%% Manuel stepping — sadece 33 sensörü kaydet
n_steps = floor(year_seconds / step_seconds) + 1;
P_nominal    = zeros(n_steps, n_sensors);
nominal_time = zeros(n_steps, 1);

fprintf('\n⏳ Nominal hidrolik (manual stepping)...\n');
fprintf('   Beklenen: %d timestep, ~30-60 sn\n', n_steps);

d.openHydraulicAnalysis;
d.initializeHydraulicAnalysis(0);

idx = 0;
last_t = -1;
tstep = 1;
t_start = tic;

while tstep > 0
    t = d.runHydraulicAnalysis;
    
    % Sadece reporting step katlarında kaydet
    if t ~= last_t && mod(t, step_seconds) == 0
        idx = idx + 1;
        P_all = d.getNodePressure;
        P_nominal(idx, :) = P_all(sensor_indices);
        nominal_time(idx) = t;
        last_t = t;
        
        if mod(idx, 10000) == 0
            elapsed = toc(t_start);
            eta = elapsed * (n_steps - idx) / idx;
            fprintf('   %6d/%d  [%.1f%%]  geçen: %.1f sn  kalan: %.1f sn\n', ...
                    idx, n_steps, 100*idx/n_steps, elapsed, eta);
        end
    end
    
    tstep = d.nextHydraulicAnalysisStep;
end

d.closeHydraulicAnalysis;

% Boşları kırp
P_nominal    = P_nominal(1:idx, :);
nominal_time = nominal_time(1:idx);

fprintf('\n✅ Tamamlandı: %.1f sn — %d sample × %d sensör\n', ...
        toc(t_start), size(P_nominal,1), size(P_nominal,2));
fprintf('   min=%.2f  max=%.2f  ort=%.2f m\n', ...
        min(P_nominal(:)), max(P_nominal(:)), mean(P_nominal(:)));

%% Kaydet
save('data/nominal_baseline.mat', 'P_nominal', 'nominal_time', ...
     'sensor_indices', '-v7.3');
fprintf('💾 data/nominal_baseline.mat (%.1f MB)\n', ...
        numel(P_nominal)*8/1e6);

d.unload;