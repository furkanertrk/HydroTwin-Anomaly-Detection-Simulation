%% s6_visualize_demo.m — p673 Plan C demo görselleştirme
% Hocaya göstermek için: residual norm + lokalizasyon haritası + özet
clc; clear; close all;

project_root = 'D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown';
cd(project_root);
fprintf('📁 Proje kökü: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Veri yükle
load('digital_twin_data.mat');
load('data/sensitivity_matrix.mat', 'sensor_indices');
scada = cache_scada('2018');
cfg   = load_config();

demo_start = datetime('2018-03-04 00:00:00');
demo_end   = datetime('2018-03-25 00:00:00');
demo_mask  = (scada.time >= demo_start) & (scada.time <= demo_end);
P_measured = scada.pressures(demo_mask, :);
demo_time  = scada.time(demo_mask);

%% p673 ground truth (config'den)
leak_start = datetime('2018-03-05 15:45:00');
leak_end   = datetime('2018-03-23 10:25:00');

%% Plan C pipeline
N_calib   = 288;            % 24h kalibrasyon
K_persist = 12;             % 1h persistence (gürültüye karşı)
N_window  = 288;            % 24h lokalizasyon penceresi

% 1) Bias kalibrasyonu
bias = mean(P_measured(1:N_calib,:) - P_nominal_demo(1:N_calib,:), 1);

% 2) Residual zaman serisi
P_predicted = P_nominal_demo + bias;
residual    = P_predicted - P_measured;
res_norm    = vecnorm(residual, 2, 2);

% 3) Adaptif threshold: kalibrasyonun 95. percentilini × 1.3
%    (max yerine percentile → tek spike threshold'u zırhlamaz)
calib_late = res_norm(N_calib/2+1 : N_calib);
threshold  = quantile(calib_late, 0.95) * 1.3;
fprintf('📐 Adaptif threshold: %.2f m  (q95=%.2f × 1.3, calib max=%.2f)\n', ...
        threshold, quantile(calib_late, 0.95), max(calib_late));

% 4) Alarm tetikleme
alarm_t = NaN;
counter = 0;
for t = N_calib+1 : length(res_norm)
    if res_norm(t) > threshold
        counter = counter + 1;
        if counter >= K_persist
            alarm_t = t;
            break;
        end
    else
        counter = 0;
    end
end

if isnan(alarm_t)
    error('❌ Alarm tetiklenemedi! Threshold çok yüksek olabilir.');
end

% 5) Lokalizasyon: alarm + 24h sonra
loc_t   = alarm_t + N_window;
if loc_t > size(residual,1)
    loc_t = size(residual,1);
end
r_avg   = mean(residual(loc_t-N_window+1 : loc_t, :), 1)';
r_n     = r_avg / (norm(r_avg) + 1e-9);
corr    = S_norm' * r_n;
[~, leak_idx] = max(corr);
leak_node = junction_ids{leak_idx};

%% Koordinatlar
d = load_ltown();
all_coords = d.getNodeCoordinates;
nx = all_coords{1};
ny = all_coords{2};

all_junc_ids = d.getNodeJunctionNameID;
all_junc_idx = zeros(length(all_junc_ids), 1);
for i = 1:length(all_junc_ids)
    all_junc_idx(i) = d.getNodeIndex(all_junc_ids{i});
end
junc_x = nx(all_junc_idx);
junc_y = ny(all_junc_idx);

link_count   = d.getLinkCount;
link_from_to = d.getNodesConnectingLinksIndex;

sensor_x = nx(sensor_indices);
sensor_y = ny(sensor_indices);

p673_idx_full = d.getNodeIndex('n673');
p673_x = nx(p673_idx_full);
p673_y = ny(p673_idx_full);

pred_idx_full = d.getNodeIndex(leak_node);
pred_x = nx(pred_idx_full);
pred_y = ny(pred_idx_full);

dist_err = sqrt((pred_x - p673_x)^2 + (pred_y - p673_y)^2);

d.unload;

%% ───── ŞEKİL 1: Residual norm zaman serisi ─────
fig1 = figure('Position',[100 100 1200 480], 'Color','w');
plot(demo_time, res_norm, 'LineWidth', 1.2, 'Color',[0.15 0.45 0.75]);
hold on;

yline(threshold, ':', 'Color',[0.4 0.4 0.4], 'LineWidth', 1.2, ...
      'HandleVisibility','off');

h_leak  = xline(leak_start,           '--', 'Color',[0.85 0.15 0.15], 'LineWidth',1.5);
h_alarm = xline(demo_time(alarm_t),   '--', 'Color',[0.95 0.55 0.10], 'LineWidth',1.5);
h_loc   = xline(demo_time(loc_t),     '--', 'Color',[0.20 0.65 0.30], 'LineWidth',1.5);

ymax = max(res_norm) * 1.05;
ylim([0 ymax * 1.20]);
text(leak_start,         ymax*1.16, ' Sızıntı (n673)', ...
     'Color',[0.85 0.15 0.15], 'FontSize',10, 'FontWeight','bold');
text(demo_time(alarm_t), ymax*1.09, sprintf(' Alarm  (+%.1fh)', ...
     hours(demo_time(alarm_t) - leak_start)), ...
     'Color',[0.95 0.55 0.10], 'FontSize',10, 'FontWeight','bold');
text(demo_time(loc_t),   ymax*1.02, sprintf(' Lokalizasyon  (+%.1fh)', ...
     hours(demo_time(loc_t) - leak_start)), ...
     'Color',[0.20 0.65 0.30], 'FontSize',10, 'FontWeight','bold');

% Threshold etiketi sağa
text(demo_end - hours(2), threshold+0.15, ...
     sprintf('threshold = %.2f m', threshold), ...
     'Color',[0.4 0.4 0.4], 'FontSize',9, 'HorizontalAlignment','right');

xlabel('Zaman', 'FontSize',12);
ylabel('||residual||  [m]', 'FontSize',12);
title('Plan C — Residual norm ve real-time alarm', 'FontSize',13);
grid on;
set(gca, 'FontSize',11);
legend([h_leak h_alarm h_loc], ...
       {'Sızıntı başlangıcı','Alarm tetikleme','Lokalizasyon kararı'}, ...
       'Location','northeast', 'FontSize',10);

exportgraphics(fig1, 'demo_residual_norm.png', 'Resolution',150);
fprintf('💾 demo_residual_norm.png\n');

%% ───── ŞEKİL 2: Lokalizasyon haritası ─────
fig2 = figure('Position',[100 100 900 800], 'Color','w');
hold on; axis equal;

for k = 1:link_count
    n1 = link_from_to(k, 1);
    n2 = link_from_to(k, 2);
    plot([nx(n1) nx(n2)], [ny(n1) ny(n2)], '-', ...
         'Color',[0.78 0.78 0.78], 'LineWidth', 0.5);
end

plot(junc_x, junc_y, '.', 'Color',[0.65 0.65 0.65], 'MarkerSize', 3);

plot(sensor_x, sensor_y, '^', 'MarkerFaceColor',[0.20 0.45 0.85], ...
     'MarkerEdgeColor','k', 'MarkerSize', 7, 'LineWidth', 0.5);

theta = linspace(0, 2*pi, 100);
plot(p673_x + 300*cos(theta), p673_y + 300*sin(theta), '--', ...
     'Color',[0.20 0.65 0.30], 'LineWidth', 1.2);

plot([p673_x pred_x], [p673_y pred_y], '-', 'Color',[0.5 0.5 0.5], 'LineWidth', 1);
plot(pred_x, pred_y, 'o', 'MarkerFaceColor',[1.0 0.85 0.10], ...
     'MarkerEdgeColor','k', 'MarkerSize', 14, 'LineWidth', 1.2);

plot(p673_x, p673_y, 'p', 'MarkerFaceColor',[0.90 0.15 0.15], ...
     'MarkerEdgeColor','k', 'MarkerSize', 22, 'LineWidth', 1.2);

text(p673_x + 30, p673_y + 30, 'n673 (gerçek)', 'FontSize',11, ...
     'FontWeight','bold', 'Color',[0.7 0.1 0.1]);
text(pred_x + 30, pred_y - 30, sprintf('%s (tahmin)', leak_node), ...
     'FontSize',11, 'FontWeight','bold', 'Color',[0.6 0.45 0.0]);

xlabel('X [m]', 'FontSize',12); ylabel('Y [m]', 'FontSize',12);
title(sprintf('Plan C — Lokalizasyon: %s → %s  (hata: %.0f m)', ...
      'n673', leak_node, dist_err), 'FontSize',13);
legend({'Borular','Junction''lar','Basınç sensörleri', ...
        '300m yarıçap','Tahmin–gerçek mesafe', ...
        sprintf('Tahmin (%s)', leak_node), 'Gerçek (n673)'}, ...
       'Location','bestoutside', 'FontSize',10);
grid on;
set(gca, 'FontSize',11);

exportgraphics(fig2, 'demo_localization_map.png', 'Resolution',150);
fprintf('💾 demo_localization_map.png\n');

%% ───── ÖZET METİN ─────
alarm_delay_h = hours(demo_time(alarm_t) - leak_start);
loc_delay_h   = hours(demo_time(loc_t)   - leak_start);

fprintf('\n═══════════════════════════════════════════════════════\n');
fprintf('   HydroTwin Plan C — p673 Demo Sonuçları\n');
fprintf('═══════════════════════════════════════════════════════\n');
fprintf('Sızıntı:           %s (n673, abrupt, BattLeDIM ground truth)\n', ...
        string(leak_start));
fprintf('Alarm tetikleme:   %s  (gecikme: %.1f saat)\n', ...
        string(demo_time(alarm_t)), alarm_delay_h);
fprintf('Lokalizasyon:      %s  (gecikme: %.1f saat)\n', ...
        string(demo_time(loc_t)), loc_delay_h);
fprintf('Tahmin:            %s\n', leak_node);
fprintf('Lokalizasyon hatası: %.0f m  ', dist_err);
if dist_err <= 300
    fprintf('✅ (BattLeDIM <300m)\n');
else
    fprintf('❌ (>300m)\n');
end
fprintf('Kalibrasyon bias:  ort=%.2f m  (model gerçeğe oturdu)\n', mean(bias));
fprintf('Adaptif threshold: %.2f m  (kalibrasyon q95 × 1.3)\n', threshold);
fprintf('Persistence:       %d sample (%d saat)\n', K_persist, K_persist*5/60);
fprintf('Residual artışı:   PRE=%.2f → POST=%.2f m\n', ...
        mean(res_norm(demo_time<leak_start)), ...
        mean(res_norm(demo_time>=leak_start+hours(6))));
fprintf('═══════════════════════════════════════════════════════\n');
fprintf('💾 İki PNG kaydedildi: proje köküne\n');