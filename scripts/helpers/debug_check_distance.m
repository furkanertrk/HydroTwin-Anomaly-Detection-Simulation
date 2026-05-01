function debug_check_distance(idx)
% Verilen junction indeksinin p673'e mesafesini hesaplar

project_root = 'D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown';
cd(project_root);
fprintf('📁 Proje kökü: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

load('digital_twin_data.mat', 'junction_ids');
d = load_ltown();
all_coords = d.getNodeCoordinates;
nx = all_coords{1};
ny = all_coords{2};

ji = zeros(length(junction_ids), 1);
for i = 1:length(junction_ids)
    ji(i) = d.getNodeIndex(junction_ids{i});
end

p673 = find(strcmp(junction_ids, 'n673'));
xi = nx(ji);
yi = ny(ji);
dist = sqrt((xi(idx) - xi(p673))^2 + (yi(idx) - yi(p673))^2);

if dist <= 300
    flag = '✅ (BattLeDIM standardına uygun, <300m)';
else
    flag = '❌ (>300m)';
end

fprintf('\n📍 Junction idx %d = %s\n', idx, junction_ids{idx});
fprintf('   p673''e mesafe: %.0f m %s\n\n', dist, flag);

d.unload;
end