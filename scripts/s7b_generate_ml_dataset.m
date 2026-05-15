%% s7b_generate_ml_dataset.m -- Synthetic residual dataset for zone ML
% The real BattLeDIM leaks are reserved for evaluation only. Training data is
% generated from the EPANET-derived sensitivity matrix with realistic noise.
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

%% Parameters
N_ZONES = 30;
N_SAMPLES_PER_NODE = 20;
N_WINDOW = 288;                 % 24h at 5 min sampling
RNG_SEED = 4242;

LEAK_MAGNITUDES = [0.50 0.75 1.00 1.25 1.50 2.00];
MAGNITUDE_JITTER = 0.08;
NOISE_LEVELS = [0.02 0.05 0.10 0.15];
SENSOR_BIAS_SIGMA = 0.03;
SENSOR_DRIFT_SIGMA = 0.03;
DROPOUT_PROB = 0.05;
MAX_DROPOUT_SENSORS = 2;
DROPOUT_SCALE = 0.10;

out_csv = fullfile('data', 'ml_localization_dataset.csv');
out_mat = fullfile('data', 'ml_localization_dataset.mat');

fprintf('\nGenerating synthetic ML localization dataset\n');
fprintf('  Samples per junction: %d\n', N_SAMPLES_PER_NODE);
fprintf('  Window length: %d samples\n', N_WINDOW);
fprintf('  RNG seed: %d\n\n', RNG_SEED);

if ~isfile(fullfile('data', 'sensitivity_matrix.mat'))
    error('Missing data/sensitivity_matrix.mat. Run scripts/s2_build_sensitivity_matrix.m first.');
end
if ~isfile(fullfile('data', 'node_zone_map.mat'))
    error('Missing data/node_zone_map.mat. Run scripts/s7a_build_zones.m first.');
end

sens = load(fullfile('data', 'sensitivity_matrix.mat'), 'S', 'S_norm', 'junction_ids');
zone_data = load(fullfile('data', 'node_zone_map.mat'), 'node_zone_map', 'N_ZONES');
node_zone_map = zone_data.node_zone_map;

if isfield(zone_data, 'N_ZONES') && zone_data.N_ZONES ~= N_ZONES
    warning('node_zone_map.mat was built with N_ZONES=%d; this script is configured for N_ZONES=%d.', ...
        zone_data.N_ZONES, N_ZONES);
end

junction_ids = string(sens.junction_ids(:));
n_junctions = numel(junction_ids);
n_sensors = size(sens.S, 1);

[is_mapped, loc] = ismember(junction_ids, string(node_zone_map.junction_id));
if ~all(is_mapped)
    missing = junction_ids(~is_mapped);
    error('Zone map is missing %d sensitivity junctions. First missing: %s', ...
        numel(missing), missing(1));
end
node_zone_map = node_zone_map(loc, :);

feature_names = make_feature_names(n_sensors);
n_features = numel(feature_names);
expected_features = 4 * n_sensors;
if n_features ~= expected_features
    error('Feature count mismatch: got %d, expected %d.', n_features, expected_features);
end

n_rows = n_junctions * N_SAMPLES_PER_NODE;
feature_matrix = zeros(n_rows, n_features);
true_junction_id = strings(n_rows, 1);
true_junction_index = zeros(n_rows, 1);
true_zone_id = zeros(n_rows, 1);
x = zeros(n_rows, 1);
y = zeros(n_rows, 1);
leak_magnitude = zeros(n_rows, 1);

rng(RNG_SEED, 'twister');
row = 0;
for j = 1:n_junctions
    base_signature = sens.S(:, j)';
    signal_scale = max(max(abs(base_signature)), 0.05);

    for s = 1:N_SAMPLES_PER_NODE
        row = row + 1;

        mag = LEAK_MAGNITUDES(randi(numel(LEAK_MAGNITUDES)));
        mag = max(0.05, mag * (1 + MAGNITUDE_JITTER * randn));
        noise_level = NOISE_LEVELS(randi(numel(NOISE_LEVELS)));

        base_signal = mag * base_signature;
        residual_window = repmat(base_signal, N_WINDOW, 1);

        sensor_bias = SENSOR_BIAS_SIGMA * signal_scale * randn(1, n_sensors);
        sensor_drift = SENSOR_DRIFT_SIGMA * signal_scale * randn(1, n_sensors);
        drift_ramp = linspace(0, 1, N_WINDOW)' * sensor_drift;
        noise = noise_level * signal_scale * randn(N_WINDOW, n_sensors);

        residual_window = residual_window + sensor_bias + drift_ramp + noise;

        if rand < DROPOUT_PROB
            n_drop = randi([1, min(MAX_DROPOUT_SENSORS, n_sensors)]);
            drop_idx = randperm(n_sensors, n_drop);
            residual_window(:, drop_idx) = DROPOUT_SCALE * residual_window(:, drop_idx);
        end

        feature_matrix(row, :) = extract_residual_features(residual_window);
        true_junction_id(row) = junction_ids(j);
        true_junction_index(row) = node_zone_map.junction_index(j);
        true_zone_id(row) = node_zone_map.zone_id(j);
        x(row) = node_zone_map.x(j);
        y(row) = node_zone_map.y(j);
        leak_magnitude(row) = mag;
    end

    if mod(j, 50) == 0 || j == n_junctions
        fprintf('  %4d/%d junctions processed\n', j, n_junctions);
    end
end

%% Validation
if any(~isfinite(feature_matrix(:)))
    error('Feature matrix contains NaN or Inf values.');
end
if any(ismissing(true_junction_id))
    error('Some true_junction_id labels are missing.');
end
valid_zones = unique(node_zone_map.zone_id);
if any(~ismember(true_zone_id, valid_zones))
    error('Some true_zone_id labels are not present in node_zone_map.');
end
if size(feature_matrix, 2) ~= 132
    error('Expected 132 feature columns for 33 sensors, got %d.', size(feature_matrix, 2));
end

meta = table( ...
    true_junction_id, true_junction_index, true_zone_id, x, y, leak_magnitude, ...
    'VariableNames', {'true_junction_id','true_junction_index','true_zone_id','x','y','leak_magnitude'});
features = array2table(feature_matrix, 'VariableNames', feature_names);
ml_dataset = [meta, features];

writetable(ml_dataset, out_csv);
save(out_mat, ...
    'ml_dataset', 'feature_names', 'N_ZONES', 'N_SAMPLES_PER_NODE', 'N_WINDOW', ...
    'RNG_SEED', 'LEAK_MAGNITUDES', 'NOISE_LEVELS', 'SENSOR_BIAS_SIGMA', ...
    'SENSOR_DRIFT_SIGMA', 'DROPOUT_PROB', '-v7.3');

fprintf('\nSaved: %s\n', out_csv);
fprintf('Saved: %s\n', out_mat);
fprintf('Rows: %d\n', height(ml_dataset));
fprintf('Feature columns: %d\n', numel(feature_names));
fprintf('s7b complete.\n');

%% Local helpers
function names = make_feature_names(n_sensors)
    prefixes = ["r_mean", "r_std", "r_max", "r_norm"];
    names = strings(1, numel(prefixes) * n_sensors);
    p = 0;
    for k = 1:numel(prefixes)
        for i = 1:n_sensors
            p = p + 1;
            names(p) = sprintf('%s_%d', prefixes(k), i);
        end
    end
    names = cellstr(names);
end

function feature_row = extract_residual_features(residual_window)
    r_mean = mean(residual_window, 1, 'omitnan');
    r_std = std(residual_window, 0, 1, 'omitnan');
    r_max = max(residual_window, [], 1);
    r_norm = r_mean ./ (norm(r_mean) + 1e-9);
    feature_row = [r_mean, r_std, r_max, r_norm];
end
