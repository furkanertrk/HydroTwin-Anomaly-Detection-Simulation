%% s1_setup.m — EPANET toolkit kurulumu + veri sanity check
clc; clear; close all;

% Toolkit'i path'e ekle
addpath(genpath(fullfile(pwd, 'toolkit')));
addpath(genpath(fullfile(pwd, 'scripts', 'helpers')));

% L-Town modelini yükle
d = epanet(fullfile('data', 'L-Town.inp'));

% Ağ özet bilgisi
fprintf('=== L-Town Özet ===\n');
fprintf('Düğüm sayısı:       %d\n', d.getNodeCount);
fprintf('  - Junction:       %d\n', d.getNodeJunctionCount);
fprintf('  - Reservoir:      %d\n', d.getNodeReservoirCount);
fprintf('  - Tank:           %d\n', d.getNodeTankCount);
fprintf('Link sayısı:        %d\n', d.getLinkCount);
fprintf('  - Pipe:           %d\n', d.getLinkPipeCount);
fprintf('  - Pump:           %d\n', d.getLinkPumpCount);
fprintf('  - Valve:          %d\n', d.getLinkValveCount);

% Ağı görselleştir (sensörleri de işaretle)
figure('Position',[100 100 1000 700]);
d.plot('highlightnode', {'n54','n105','n415'}, ...    % örnek sensör düğümleri
       'highlightlink', {'p227'});                     % örnek sensör borusu
title('L-Town Water Distribution Network');

% Sensör listesini BattLeDIM dökümanından çıkar
% (BattLeDIM PDF'inde 33 basınç sensörünün düğüm ID'leri verilmiş)
sensor_nodes = {'n1','n4','n31','n54','n105','n114','n163','n188','n215',...
                'n229','n288','n296','n332','n342','n410','n415','n429',...
                'n458','n469','n495','n506','n516','n519','n549','n613',...
                'n636','n644','n679','n722','n726','n740','n752','n769'};
flow_sensors = {'p227','p235','p331'};  % akış sensörleri

% Sensör index'lerini kaydet
sensor_node_idx = zeros(length(sensor_nodes),1);
for i = 1:length(sensor_nodes)
    sensor_node_idx(i) = d.getNodeIndex(sensor_nodes{i});
end

% Proje değişkenlerini kaydet
save('project_config.mat', 'sensor_nodes', 'sensor_node_idx', 'flow_sensors');

d.unload;
fprintf('\n✅ Kurulum tamam. project_config.mat kaydedildi.\n');