%% s7a_build_zones.m -- Build k-means junction zones for ML-assisted localization
% HydroTwin Phase 3B:
% XGBoost will predict likely leak zones; physics/sensitivity still performs
% final node-level localization.
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Parameters
N_ZONES = 30;
RNG_SEED = 42;
MAKE_FIGURE = true;

out_csv = fullfile('data', 'node_zone_map.csv');
out_mat = fullfile('data', 'node_zone_map.mat');
out_png = fullfile('data', sprintf('node_zones_k%d.png', N_ZONES));

fprintf('\nBuilding node zones with k-means\n');
fprintf('  Zones: %d\n', N_ZONES);
fprintf('  RNG seed: %d\n\n', RNG_SEED);

d = [];
try
    d = load_ltown();
    coords = d.getNodeCoordinates;
    node_x = coords{1};
    node_y = coords{2};

    raw_junction_ids = d.getNodeJunctionNameID;
    junction_ids = string(raw_junction_ids(:));
    n_junctions = numel(junction_ids);
    junction_indices = zeros(n_junctions, 1);
    x = zeros(n_junctions, 1);
    y = zeros(n_junctions, 1);

    for i = 1:n_junctions
        junction_indices(i) = d.getNodeIndex(char(junction_ids(i)));
        x(i) = node_x(junction_indices(i));
        y(i) = node_y(junction_indices(i));
    end

    if N_ZONES >= n_junctions
        error('N_ZONES must be smaller than the number of junctions (%d).', n_junctions);
    end

    if exist('kmeans', 'file') ~= 2
        error('MATLAB kmeans function not found. Install/enable Statistics and Machine Learning Toolbox.');
    end

    rng(RNG_SEED, 'twister');
    xy = [x, y];
    [zone_id, centroids, sumd] = kmeans( ...
        xy, N_ZONES, ...
        'Replicates', 10, ...
        'MaxIter', 1000, ...
        'Start', 'plus', ...
        'Display', 'final');

    node_zone_map = table( ...
        junction_ids, junction_indices, x, y, zone_id, ...
        'VariableNames', {'junction_id','junction_index','x','y','zone_id'});

    zone_counts = groupsummary(node_zone_map, 'zone_id');
    fprintf('\nZone size summary:\n');
    fprintf('  Min junctions per zone: %d\n', min(zone_counts.GroupCount));
    fprintf('  Max junctions per zone: %d\n', max(zone_counts.GroupCount));
    fprintf('  Mean junctions per zone: %.1f\n', mean(zone_counts.GroupCount));

    writetable(node_zone_map, out_csv);
    save(out_mat, 'node_zone_map', 'N_ZONES', 'RNG_SEED', 'centroids', 'sumd');

    fprintf('\nSaved: %s\n', out_csv);
    fprintf('Saved: %s\n', out_mat);

    if MAKE_FIGURE
        try
            fig = figure('Visible', 'off', 'Color', 'w');
            scatter(x, y, 14, zone_id, 'filled');
            axis equal;
            grid on;
            colormap(turbo(N_ZONES));
            colorbar;
            title(sprintf('L-TOWN junction zones (k=%d)', N_ZONES));
            xlabel('x');
            ylabel('y');
            exportgraphics(fig, out_png, 'Resolution', 180);
            close(fig);
            fprintf('Saved: %s\n', out_png);
        catch ME
            warning('Zone figure was not generated: %s', ME.message);
        end
    end

    d.unload;
catch ME
    if ~isempty(d)
        try
            d.unload;
        catch
        end
    end
    rethrow(ME);
end

fprintf('\ns7a complete.\n');
