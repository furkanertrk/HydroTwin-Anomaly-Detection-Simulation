%% s7d_evaluate_xgb_hybrid_localizer.m -- Real leak evaluation of XGB zone + sensitivity
% Uses tuned CUSUM alarms from detection_comparison.csv. XGBoost predicts
% top-k zones, then node localization remains sensitivity-correlation based.
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Parameters
DETECTOR_METHOD = "CUSUM";
TOP_ZONE_K = 3;
TOP_NODE_K = 10;
N_CALIB = 288;
N_WINDOW = 288;
PYTHON_EXE = getenv('HYDROTWIN_PYTHON');
if strlength(PYTHON_EXE) == 0
    bundled_python = 'C:\Users\furkan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe';
    if isfile(bundled_python)
        PYTHON_EXE = bundled_python;
    else
        PYTHON_EXE = 'python';
    end
end

feature_file = fullfile(project_root, 'data', 'xgb_hybrid_real_features.csv');
zone_pred_file = fullfile(project_root, 'data', 'xgb_hybrid_zone_predictions.csv');
out_file = fullfile(project_root, 'data', 'xgb_hybrid_localization_results.csv');
model_file = fullfile(project_root, 'data', 'xgb_zone_model.pkl');
py_script = fullfile(project_root, 'scripts', 's7c_train_xgb_zone_localizer.py');

required_files = { ...
    fullfile(project_root, 'data', 'detection_comparison.csv'), ...
    fullfile(project_root, 'data', 'nominal_baseline.mat'), ...
    fullfile(project_root, 'data', 'sensitivity_matrix.mat'), ...
    fullfile(project_root, 'data', 'node_zone_map.mat'), ...
    model_file, ...
    py_script};
for i = 1:numel(required_files)
    if ~isfile(required_files{i})
        error('Required file is missing: %s', required_files{i});
    end
end

fprintf('\nEvaluating XGBoost-assisted hybrid localizer\n');
fprintf('  Detector source: %s\n', DETECTOR_METHOD);
fprintf('  Top predicted zones: %d\n', TOP_ZONE_K);
fprintf('  Python: %s\n\n', PYTHON_EXE);

cfg = load_config();
base = load(fullfile('data', 'nominal_baseline.mat'), 'P_nominal');
sens = load(fullfile('data', 'sensitivity_matrix.mat'), 'S_norm', 'junction_ids');
zone_data = load(fullfile('data', 'node_zone_map.mat'), 'node_zone_map');
node_zone_map = zone_data.node_zone_map;

junction_ids = string(sens.junction_ids(:));
[is_mapped, zone_loc] = ismember(junction_ids, string(node_zone_map.junction_id));
if ~all(is_mapped)
    missing = junction_ids(~is_mapped);
    error('node_zone_map is missing %d sensitivity junctions. First missing: %s', ...
        numel(missing), missing(1));
end
zone_by_sens = node_zone_map.zone_id(zone_loc);

det = readtable(fullfile('data', 'detection_comparison.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
assert_has_columns(det, {'method','leak_id','detected','false_alarm_before_leak','alarm_time'});
det = det(det.method == DETECTOR_METHOD & logical(det.detected) & ~logical(det.false_alarm_before_leak), :);
fprintf('Usable detected leaks from %s: %d\n', DETECTOR_METHOD, height(det));

scada2018 = cache_scada('2018');
scada2019 = cache_scada('2019');

d = load_ltown();
coords = d.getNodeCoordinates;
node_x = coords{1};
node_y = coords{2};

n_cases = height(det);
feature_names = make_feature_names(size(sens.S_norm, 1));
feature_matrix = zeros(n_cases, numel(feature_names));
feature_case_index = zeros(n_cases, 1);
feature_leak_id = strings(n_cases, 1);
feature_count = 0;

leak_id = strings(n_cases, 1);
true_pipe_id = strings(n_cases, 1);
true_node = strings(n_cases, 1);
predicted_node = strings(n_cases, 1);
top1_error_m = NaN(n_cases, 1);
top5_min_error_m = NaN(n_cases, 1);
top10_min_error_m = NaN(n_cases, 1);
xgb_top1_zone = NaN(n_cases, 1);
xgb_top3_zones = strings(n_cases, 1);
candidate_count = zeros(n_cases, 1);
method_name = repmat("XGB_top3_zone_sensitivity", n_cases, 1);
evaluated = false(n_cases, 1);
skip_reason = strings(n_cases, 1);

for k = 1:n_cases
    leak_id(k) = string(det.leak_id(k));
    true_pipe_id(k) = leak_id(k);
    try
        leak = cfg.leakages(string(cfg.leakages.linkID) == leak_id(k), :);
        if height(leak) ~= 1
            error('Leak metadata not found or ambiguous.');
        end

        leak_start = leak.startTime;
        leak_end = leak.endTime;
        leak_year = year(leak_start);
        alarm_time = ensure_datetime(det.alarm_time(k));

        if leak_year == 2018
            scada = scada2018;
        else
            scada = scada2019;
        end

        demo_start = dateshift(leak_start, 'start', 'day') - days(1);
        demo_end = min([leak_end, scada.time(end)]);
        demo_mask = (scada.time >= demo_start) & (scada.time <= demo_end);
        if sum(demo_mask) < (N_CALIB + N_WINDOW)
            error('Not enough samples in demo window.');
        end

        P_measured = scada.pressures(demo_mask, :);
        demo_time = scada.time(demo_mask);
        if demo_time(1) > demo_start || leak_start <= demo_time(N_CALIB)
            error('Clean previous-day calibration is not available.');
        end

        P_nominal = nominal_slice_for_time(demo_time, base.P_nominal, leak_year);
        bias = mean(P_measured(1:N_CALIB, :) - P_nominal(1:N_CALIB, :), 1);
        residual = (P_nominal + bias) - P_measured;

        alarm_idx = find_time_index(demo_time, alarm_time);
        loc_idx = alarm_idx + N_WINDOW;
        if loc_idx > size(residual, 1)
            error('Alarm exists, but no 24h localization window is available.');
        end

        residual_window = residual(loc_idx-N_WINDOW+1:loc_idx, :);
        feature_count = feature_count + 1;
        feature_matrix(feature_count, :) = extract_residual_features(residual_window);
        feature_case_index(feature_count) = k;
        feature_leak_id(feature_count) = leak_id(k);

        gt = pipe_midpoint(d, leak_id(k), node_x, node_y);
        true_node(k) = nearest_junction_to_point(d, junction_ids, gt.x, gt.y, node_x, node_y);
        skip_reason(k) = "ready_for_prediction";
    catch ME
        skip_reason(k) = string(ME.message);
        fprintf('  %-8s skipped before XGB prediction: %s\n', leak_id(k), ME.message);
    end
end

if feature_count == 0
    d.unload;
    error('No real leak feature rows could be generated.');
end

feature_matrix = feature_matrix(1:feature_count, :);
feature_case_index = feature_case_index(1:feature_count);
feature_leak_id = feature_leak_id(1:feature_count);
feature_meta = table(feature_case_index, feature_leak_id, ...
    'VariableNames', {'feature_case_index','leak_id'});
feature_table = [feature_meta, array2table(feature_matrix, 'VariableNames', feature_names)];
writetable(feature_table, feature_file);
fprintf('\nSaved real-leak feature file: %s\n', feature_file);

cmd = sprintf('"%s" "%s" --predict "%s" --predict-output "%s" --model-out "%s" --top-k %d', ...
    PYTHON_EXE, py_script, feature_file, zone_pred_file, model_file, TOP_ZONE_K);
[status, cmdout] = system(cmd);
fprintf('%s\n', cmdout);
if status ~= 0
    d.unload;
    error('Python zone prediction failed. Command: %s', cmd);
end

zone_pred = readtable(zone_pred_file, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
assert_has_columns(zone_pred, {'feature_case_index','leak_id','xgb_top1_zone','xgb_top3_zones'});

for p = 1:height(zone_pred)
    k = zone_pred.feature_case_index(p);
    try
        zones = parse_zone_list(zone_pred.xgb_top3_zones(p));
        if isempty(zones)
            error('Python returned empty top-k zone list.');
        end

        xgb_top1_zone(k) = zone_pred.xgb_top1_zone(p);
        xgb_top3_zones(k) = zone_pred.xgb_top3_zones(p);

        candidate_idx = find(ismember(zone_by_sens, zones));
        candidate_count(k) = numel(candidate_idx);
        if isempty(candidate_idx)
            error('No candidate junctions found for predicted zones.');
        end

        r_mean = feature_matrix(p, 1:size(sens.S_norm, 1))';
        ranked_idx = rank_sensitivity_candidates(sens.S_norm, r_mean, candidate_idx, TOP_NODE_K);
        top_names = junction_ids(ranked_idx);

        gt = pipe_midpoint(d, leak_id(k), node_x, node_y);
        distances = distances_to_nodes(d, top_names, gt.x, gt.y, node_x, node_y);

        predicted_node(k) = top_names(1);
        top1_error_m(k) = distances(1);
        top5_min_error_m(k) = min(distances(1:min(5, numel(distances))));
        top10_min_error_m(k) = min(distances);
        evaluated(k) = true;
        skip_reason(k) = "";

        fprintf('  %-8s top1=%7.1fm  top10=%7.1fm  zones=%s  candidates=%d\n', ...
            leak_id(k), top1_error_m(k), top10_min_error_m(k), xgb_top3_zones(k), candidate_count(k));
    catch ME
        skip_reason(k) = string(ME.message);
        fprintf('  %-8s skipped after XGB prediction: %s\n', leak_id(k), ME.message);
    end
end

results = table( ...
    leak_id, true_pipe_id, true_node, predicted_node, ...
    top1_error_m, top5_min_error_m, top10_min_error_m, ...
    xgb_top1_zone, xgb_top3_zones, candidate_count, method_name, evaluated, skip_reason);
writetable(results, out_file);

fprintf('\nSaved: %s\n', out_file);
fprintf('Evaluated leaks: %d/%d\n', sum(evaluated), n_cases);
if any(evaluated)
    fprintf('Top-1 <=300m: %d/%d\n', sum(top1_error_m(evaluated) <= 300), sum(evaluated));
    fprintf('Top-5 <=300m: %d/%d\n', sum(top5_min_error_m(evaluated) <= 300), sum(evaluated));
    fprintf('Top-10 <=300m: %d/%d\n', sum(top10_min_error_m(evaluated) <= 300), sum(evaluated));
end

d.unload;
fprintf('s7d complete.\n');

%% Local helpers
function assert_has_columns(t, names)
    missing = setdiff(string(names), string(t.Properties.VariableNames));
    if ~isempty(missing)
        error('Table is missing required columns: %s', strjoin(cellstr(missing), ', '));
    end
end

function P_nominal_window = nominal_slice_for_time(t, P_nominal_year, y)
    year_start = datetime(y, 1, 1, 0, 0, 0);
    idx = round(minutes(t - year_start) / 5) + 1;
    idx = max(1, min(size(P_nominal_year, 1), idx));
    P_nominal_window = P_nominal_year(idx, :);
end

function t = ensure_datetime(x)
    if isdatetime(x)
        t = x;
    else
        sx = string(x);
        try
            t = datetime(sx, 'InputFormat', 'dd-MMM-yyyy HH:mm:ss', 'Locale', 'en_US');
        catch
            t = datetime(sx);
        end
    end
end

function idx = find_time_index(demo_time, target_time)
    idx = find(demo_time == target_time, 1);
    if isempty(idx)
        [delta_min, idx] = min(abs(minutes(demo_time - target_time)));
        if delta_min > 2.6
            error('Alarm time is not aligned with the 5-minute SCADA timeline.');
        end
    end
end

function gt = pipe_midpoint(d, leak_id, node_x, node_y)
    link_idx = d.getLinkIndex(char(leak_id));
    link_nodes = d.getLinkNodesIndex(link_idx);
    gt.x = (node_x(link_nodes(1)) + node_x(link_nodes(2))) / 2;
    gt.y = (node_y(link_nodes(1)) + node_y(link_nodes(2))) / 2;
end

function nearest_node = nearest_junction_to_point(d, junction_ids, gt_x, gt_y, node_x, node_y)
    best_distance = Inf;
    nearest_node = "";
    for i = 1:numel(junction_ids)
        node_idx = d.getNodeIndex(char(junction_ids(i)));
        distance = hypot(node_x(node_idx) - gt_x, node_y(node_idx) - gt_y);
        if distance < best_distance
            best_distance = distance;
            nearest_node = junction_ids(i);
        end
    end
end

function distances = distances_to_nodes(d, node_names, gt_x, gt_y, node_x, node_y)
    distances = zeros(numel(node_names), 1);
    for i = 1:numel(node_names)
        node_idx = d.getNodeIndex(char(node_names(i)));
        distances(i) = hypot(node_x(node_idx) - gt_x, node_y(node_idx) - gt_y);
    end
end

function ranked_idx = rank_sensitivity_candidates(S_norm, r_mean, candidate_idx, top_k)
    candidate_idx = unique(candidate_idx(:), 'stable');
    r_norm = r_mean ./ (norm(r_mean) + 1e-9);
    correlations = S_norm' * r_norm;
    [~, order] = sort(correlations(candidate_idx), 'descend');
    ranked_idx = candidate_idx(order);
    ranked_idx = ranked_idx(1:min(top_k, numel(ranked_idx)));
end

function zones = parse_zone_list(x)
    parts = split(string(x), "|");
    zones = str2double(parts);
    zones = zones(~isnan(zones));
    zones = unique(zones(:)', 'stable');
end

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
