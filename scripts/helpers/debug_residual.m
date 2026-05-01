%% debug_residual.m — Offline tanı v2: residual + lokalizasyon derinleştirme
clc; clear; close all;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

load('digital_twin_data.mat');   % S_norm, junction_ids, P_nominal_demo
load('data/sensitivity_matrix.mat', 'sensor_indices');
scada = cache_scada('2018');

cfg = load_config();

demo_start = datetime('2018-03-04 00:00:00');
demo_end   = datetime('2018-03-25 00:00:00');
demo_mask  = (scada.time >= demo_start) & (scada.time <= demo_end);
P_measured = scada.pressures(demo_mask, :);
demo_time  = scada.time(demo_mask);

%% 1) Bias kalibrasyonu
N        = size(P_measured, 1);
N_calib  = 288;
bias     = mean(P_measured(1:N_calib,:) - P_nominal_demo(1:N_calib,:), 1);

fprintf('📐 Bias: ort=%.2f m | min=%.2f | max=%.2f\n', ...
        mean(bias), min(bias), max(bias));

%% 2) Residual hesapla (twin - measured)
P_predicted = P_nominal_demo + bias;
residual    = P_predicted - P_measured;
res_norm    = vecnorm(residual, 2, 2);

leak_start = datetime('2018-03-05 13:55:00');

mask_pre  = demo_time < leak_start;
% Daha dar pencere: leak +6h ile +30h arası (steady-state sızıntı)
mask_post = (demo_time >= leak_start + hours(6)) & (demo_time <= leak_start + hours(30));

fprintf('\n📊 Residual norm: PRE ort=%.2f | POST ort=%.2f\n', ...
        mean(res_norm(mask_pre)), mean(res_norm(mask_post)));

%% 3) Junction koordinatları (mesafe hesabı için)
d = load_ltown();
all_coords = d.getNodeCoordinates;
node_x = all_coords{1};
node_y = all_coords{2};
junction_indices = zeros(length(junction_ids), 1);
for i = 1:length(junction_ids)
    junction_indices(i) = d.getNodeIndex(junction_ids{i});
end
junc_x = node_x(junction_indices);
junc_y = node_y(junction_indices);
d.unload;

p673_idx = find(strcmp(junction_ids, 'n673'));
p673_x = junc_x(p673_idx);
p673_y = junc_y(p673_idx);

%% 4) En çok düşen sensörleri görelim (model-driven residual)
r_vec = mean(residual(mask_post,:), 1)';
[sorted_r, sorted_s] = sort(r_vec, 'descend');

fprintf('\n🔍 Sızıntı sonrası en çok düşen 5 sensör (model-driven):\n');
for i = 1:5
    sname = cfg.pressure_sensors{sorted_s(i)};
    fprintf('   %d. %s  düşüş=%.2f m\n', i, sname, sorted_r(i));
end

%% 5) ÜÇ FARKLI residual yönteminin lokalizasyonunu kıyasla
methods = struct();
methods(1).name = 'Plan C (twin - measured, MEAN)';
methods(1).res  = mean(residual(mask_post,:), 1)';

methods(2).name = 'Plan C (twin - measured, MEDIAN)';
methods(2).res  = median(residual(mask_post,:), 1)';

% Pure data baseline (sızıntı öncesi 24h vs sonrası 24h SCADA farkı)
mask_pre_24h  = (demo_time >= leak_start - hours(24)) & (demo_time < leak_start);
delta_scada   = mean(P_measured(mask_pre_24h,:), 1)' - mean(P_measured(mask_post,:), 1)';
methods(3).name = 'Pure data (pre-SCADA - post-SCADA)';
methods(3).res  = delta_scada;

fprintf('\n═══════════════════════════════════════════════════════\n');
fprintf('🎯 LOKALİZASYON KIYASI (3 yöntem)\n');
fprintf('═══════════════════════════════════════════════════════\n');

for m = 1:length(methods)
    r       = methods(m).res;
    r_n     = r / (norm(r) + 1e-9);
    corr    = S_norm' * r_n;
    [~, sort_idx] = sort(corr, 'descend');
    rank    = find(sort_idx == p673_idx);
    [~, top5] = maxk(corr, 5);
    
    % Top-1'in p673'e mesafesi
    dist_top1 = sqrt((junc_x(top5(1)) - p673_x)^2 + (junc_y(top5(1)) - p673_y)^2);
    
    fprintf('\n[%d] %s\n', m, methods(m).name);
    fprintf('   p673 sıralaması: %d / %d\n', rank, length(corr));
    fprintf('   Top-1: %s  (p673''e mesafe: %.0f m)\n', ...
            junction_ids{top5(1)}, dist_top1);
    fprintf('   Top-5 corr: ');
    for i = 1:5
        fprintf('%.3f ', corr(top5(i)));
    end
    fprintf('\n   Top-5 nodes: ');
    for i = 1:5
        d_i = sqrt((junc_x(top5(i)) - p673_x)^2 + (junc_y(top5(i)) - p673_y)^2);
        fprintf('%s(%.0fm) ', junction_ids{top5(i)}, d_i);
    end
    fprintf('\n');
end

%% 6) p673'e en yakın sensör hangisi, kaç metre?
sensor_dists = zeros(length(sensor_indices), 1);
for i = 1:length(sensor_indices)
    sx = node_x(sensor_indices(i));
    sy = node_y(sensor_indices(i));
    sensor_dists(i) = sqrt((sx - p673_x)^2 + (sy - p673_y)^2);
end
[~, nearest_s] = sort(sensor_dists, 'ascend');
fprintf('\n📡 p673''e en yakın 3 sensör:\n');
for i = 1:3
    fprintf('   %s  (%.0f m, residual=%.2f m)\n', ...
            cfg.pressure_sensors{nearest_s(i)}, sensor_dists(nearest_s(i)), ...
            r_vec(nearest_s(i)));
end

%% 7) Plot
figure('Position',[100 100 1200 500]);
plot(demo_time, res_norm, 'LineWidth', 1);
hold on;
xline(leak_start, 'r--', 'p673', 'LineWidth', 1.5);
xline(leak_start + hours(6),  'k:', '+6h');
xline(leak_start + hours(30), 'k:', '+30h');
yline(2.0, 'g--', 'thr=2.0');
xlabel('Zaman'); ylabel('||residual|| [m]');
title('Residual norm — p673 demo');
grid on;