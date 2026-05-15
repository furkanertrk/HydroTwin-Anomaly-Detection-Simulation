%% s7f_fair_compare_localizers_cusum.m -- Fair localization comparison on CUSUM leaks
% Uses the exact same CUSUM-detected real leak events, alarm times, residual
% windows, and pipe-midpoint distance reference for all localizers.
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

MAS_AVAILABLE = exist('quantile', 'file') == 2;
MAS_COVERAGE = 0.70;
MAS_MIN_SENSORS = 3;
MAS_MAX_SENSORS = 8;
MAS_CANDIDATE_Q = 0.90;
MAS_MIN_CANDIDATES = 30;
MAS_MAX_CANDIDATES = 120;

PYTHON_EXE = getenv('HYDROTWIN_PYTHON');
if strlength(PYTHON_EXE) == 0
    bundled_python = 'C:\Users\furkan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe';
    if isfile(bundled_python)
        PYTHON_EXE = bundled_python;
    else
        PYTHON_EXE = 'python';
    end
end

feature_file = fullfile(project_root, 'data', 'localization_fair_cusum_features.csv');
zone_pred_file = fullfile(project_root, 'data', 'localization_fair_cusum_zone_predictions.csv');
per_leak_file = fullfile(project_root, 'data', 'localization_fair_cusum_per_leak.csv');
summary_file = fullfile(project_root, 'data', 'localization_fair_cusum_summary.csv');
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

fprintf('\nFair CUSUM localization comparison\n');
fprintf('  Detector source: %s\n', DETECTOR_METHOD);
fprintf('  Top node candidates reported: %d\n', TOP_NODE_K);
fprintf('  XGB top zones: %d\n', TOP_ZONE_K);
fprintf('  Python: %s\n\n', PYTHON_EXE);

cfg = load_config();
base = load(fullfile('data', 'nominal_baseline.mat'), 'P_nominal');
sens = load(fullfile('data', 'sensitivity_matrix.mat'), 'S', 'S_norm', 'junction_ids');
zone_data = load(fullfile('data', 'node_zone_map.mat'), 'node_zone_map');
node_zone_map = zone_data.node_zone_map;

junction_ids = string(sens.junction_ids(:));
n_sensors = size(sens.S_norm, 1);
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
fprintf('Usable CUSUM-detected leaks: %d\n', height(det));

scada2018 = cache_scada('2018');
scada2019 = cache_scada('2019');

d = load_ltown();
coords = d.getNodeCoordinates;
node_x = coords{1};
node_y = coords{2};

feature_names = make_feature_names(n_sensors);
n_cases = height(det);
feature_matrix = zeros(n_cases, numel(feature_names));
feature_case_index = zeros(n_cases, 1);
feature_leak_id = strings(n_cases, 1);
feature_count = 0;

case_data = repmat(struct( ...
    'ready', false, ...
    'leak_id', "", ...
    'true_pipe_id', "", ...
    'true_node', "", ...
    'leak_type', "", ...
    'alarm_time', NaT, ...
    'r_mean', [], ...
    'gt_x', NaN, ...
    'gt_y', NaN, ...
    'skip_reason', ""), n_cases, 1);

for k = 1:n_cases
    leak_id = string(det.leak_id(k));
    case_data(k).leak_id = leak_id;
    case_data(k).true_pipe_id = leak_id;

    try
        leak = cfg.leakages(string(cfg.leakages.linkID) == leak_id, :);
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
        r_mean = mean(residual_window, 1, 'omitnan')';
        gt = pipe_midpoint(d, leak_id, node_x, node_y);

        feature_count = feature_count + 1;
        feature_matrix(feature_count, :) = extract_residual_features(residual_window);
        feature_case_index(feature_count) = k;
        feature_leak_id(feature_count) = leak_id;

        case_data(k).ready = true;
        case_data(k).leak_type = string(leak.leakType{1});
        case_data(k).alarm_time = alarm_time;
        case_data(k).r_mean = r_mean;
        case_data(k).gt_x = gt.x;
        case_data(k).gt_y = gt.y;
        case_data(k).true_node = nearest_junction_to_point(d, junction_ids, gt.x, gt.y, node_x, node_y);
    catch ME
        case_data(k).skip_reason = string(ME.message);
        fprintf('  %-8s skipped before comparison: %s\n', leak_id, ME.message);
    end
end

if feature_count == 0
    d.unload;
    error('No fair comparison feature rows could be generated.');
end

%% XGBoost zone prediction for the exact same residual windows
feature_matrix = feature_matrix(1:feature_count, :);
feature_case_index = feature_case_index(1:feature_count);
feature_leak_id = feature_leak_id(1:feature_count);
feature_meta = table(feature_case_index, feature_leak_id, ...
    'VariableNames', {'feature_case_index','leak_id'});
feature_table = [feature_meta, array2table(feature_matrix, 'VariableNames', feature_names)];
writetable(feature_table, feature_file);
fprintf('\nSaved fair feature file: %s\n', feature_file);

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

xgb_top1_zone_by_case = NaN(n_cases, 1);
xgb_top3_zones_by_case = strings(n_cases, 1);
for p = 1:height(zone_pred)
    case_idx = zone_pred.feature_case_index(p);
    xgb_top1_zone_by_case(case_idx) = zone_pred.xgb_top1_zone(p);
    xgb_top3_zones_by_case(case_idx) = zone_pred.xgb_top3_zones(p);
end

%% Evaluate all localizers on the same ready cases
result_rows = {};
for k = 1:n_cases
    if ~case_data(k).ready
        continue;
    end

    r_mean = case_data(k).r_mean;
    gt_x = case_data(k).gt_x;
    gt_y = case_data(k).gt_y;

    % 1) Global sensitivity localization.
    global_candidates = (1:numel(junction_ids))';
    result_rows(end+1, :) = evaluate_method( ...
        d, sens.S_norm, junction_ids, global_candidates, r_mean, gt_x, gt_y, ...
        node_x, node_y, case_data(k), "Global sensitivity", ...
        NaN, "", NaN, NaN, TOP_NODE_K); %#ok<SAGROW>

    % 2) MAS sensitivity localization.
    if MAS_AVAILABLE
        try
            mas = build_mas_candidates( ...
                r_mean, sens.S, cfg.pressure_sensors, MAS_COVERAGE, MAS_MIN_SENSORS, ...
                MAS_MAX_SENSORS, MAS_CANDIDATE_Q, MAS_MIN_CANDIDATES, MAS_MAX_CANDIDATES);
            result_rows(end+1, :) = evaluate_method( ...
                d, sens.S_norm, junction_ids, mas.candidate_idx, r_mean, gt_x, gt_y, ...
                node_x, node_y, case_data(k), "MAS sensitivity", ...
                NaN, "", NaN, NaN, TOP_NODE_K); %#ok<SAGROW>
        catch ME
            warning('MAS skipped for %s: %s', case_data(k).leak_id, ME.message);
        end
    else
        warning('MAS implementation unavailable. MAS row skipped.');
    end

    % 3) XGBoost top-3 zones + sensitivity localization.
    zones = parse_zone_list(xgb_top3_zones_by_case(k));
    xgb_candidates = find(ismember(zone_by_sens, zones));
    xgb_top1_zone = xgb_top1_zone_by_case(k);
    true_zone = zone_for_node(case_data(k).true_node, node_zone_map);
    zone_hit_top1 = ~isnan(true_zone) && ~isnan(xgb_top1_zone) && true_zone == xgb_top1_zone;
    zone_hit_top3 = ~isnan(true_zone) && any(zones == true_zone);

    result_rows(end+1, :) = evaluate_method( ...
        d, sens.S_norm, junction_ids, xgb_candidates, r_mean, gt_x, gt_y, ...
        node_x, node_y, case_data(k), "XGBoost top-3 zones + sensitivity", ...
        xgb_top1_zone, xgb_top3_zones_by_case(k), zone_hit_top1, zone_hit_top3, TOP_NODE_K); %#ok<SAGROW>
end

if isempty(result_rows)
    d.unload;
    error('No localization rows were produced.');
end

per_leak = cell2table(result_rows, 'VariableNames', { ...
    'leak_id','true_pipe_id','true_node','leak_type','alarm_time','method_name', ...
    'predicted_node','top1_error_m','top5_min_error_m','top10_min_error_m', ...
    'candidate_count','xgb_top1_zone','xgb_top3_zones','zone_hit_top1','zone_hit_top3'});
writetable(per_leak, per_leak_file);

methods = unique(per_leak.method_name, 'stable');
summary_rows = cell(numel(methods), 11);
for i = 1:numel(methods)
    m = methods(i);
    t = per_leak(per_leak.method_name == m, :);
    summary_rows(i, :) = make_summary_row(m, t);
end
summary = cell2table(summary_rows, 'VariableNames', { ...
    'method_name','evaluated_leaks','top1_within_300m','top5_within_300m', ...
    'top10_within_300m','top1_rate','top5_rate','top10_rate', ...
    'median_top1_error_m','mean_top1_error_m','mean_candidate_count'});
writetable(summary, summary_file);

fprintf('\nSaved: %s\n', per_leak_file);
fprintf('Saved: %s\n\n', summary_file);
disp(summary);

d.unload;
fprintf('s7f complete.\n');

%% Local helpers
function row = evaluate_method(d, S_norm, junction_ids, candidate_idx, r_mean, gt_x, gt_y, node_x, node_y, case_info, method_name, xgb_top1_zone, xgb_top3_zones, zone_hit_top1, zone_hit_top3, top_k)
    if isempty(candidate_idx)
        error('Candidate list is empty for method %s and leak %s.', method_name, case_info.leak_id);
    end

    ranked_idx = rank_sensitivity_candidates(S_norm, r_mean, candidate_idx, top_k);
    top_names = junction_ids(ranked_idx);
    distances = distances_to_nodes(d, top_names, gt_x, gt_y, node_x, node_y);

    row = { ...
        case_info.leak_id, ...
        case_info.true_pipe_id, ...
        case_info.true_node, ...
        case_info.leak_type, ...
        case_info.alarm_time, ...
        method_name, ...
        top_names(1), ...
        distances(1), ...
        min(distances(1:min(5, numel(distances)))), ...
        min(distances(1:min(10, numel(distances)))), ...
        numel(unique(candidate_idx)), ...
        xgb_top1_zone, ...
        xgb_top3_zones, ...
        zone_hit_top1, ...
        zone_hit_top3};
end

function row = make_summary_row(method_name, t)
    n = height(t);
    top1_count = sum(t.top1_error_m <= 300);
    top5_count = sum(t.top5_min_error_m <= 300);
    top10_count = sum(t.top10_min_error_m <= 300);

    row = { ...
        method_name, ...
        n, ...
        top1_count, ...
        top5_count, ...
        top10_count, ...
        top1_count / max(1, n), ...
        top5_count / max(1, n), ...
        top10_count / max(1, n), ...
        median(t.top1_error_m, 'omitnan'), ...
        mean(t.top1_error_m, 'omitnan'), ...
        mean(t.candidate_count, 'omitnan')};
end

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
    candidate_idx = candidate_idx(candidate_idx >= 1 & candidate_idx <= size(S_norm, 2));
    r_norm = r_mean ./ (norm(r_mean) + 1e-9);
    correlations = S_norm' * r_norm;
    [~, order] = sort(correlations(candidate_idx), 'descend');
    ranked_idx = candidate_idx(order);
    ranked_idx = ranked_idx(1:min(top_k, numel(ranked_idx)));
end

function mas = build_mas_candidates(r_mean, S, pressure_sensors, coverage, min_sensors, max_sensors, candidate_q, min_candidates, max_candidates)
    sensor_mag = abs(r_mean(:));
    contribution = sensor_mag / (sum(sensor_mag) + 1e-9);
    [~, sensor_order] = sort(sensor_mag, 'descend');

    n_mas = find(cumsum(contribution(sensor_order)) >= coverage, 1, 'first');
    if isempty(n_mas)
        n_mas = min_sensors;
    end
    n_mas = min(max(n_mas, min_sensors), max_sensors);
    mas.sensor_idx = sensor_order(1:n_mas);
    mas.sensor_ids = string(pressure_sensors(mas.sensor_idx));

    weights = contribution(mas.sensor_idx);
    weights = weights / (sum(weights) + 1e-9);

    S_abs = abs(S(mas.sensor_idx, :));
    S_scaled = S_abs ./ (max(S_abs, [], 2) + 1e-9);
    candidate_score = weights' * S_scaled;

    [~, score_order] = sort(candidate_score, 'descend');
    q_score = quantile(candidate_score, candidate_q);
    candidate_idx = find(candidate_score >= q_score);

    if numel(candidate_idx) > max_candidates
        candidate_idx = score_order(1:max_candidates);
    elseif numel(candidate_idx) < min_candidates
        candidate_idx = score_order(1:min(min_candidates, numel(score_order)));
    else
        [~, local_order] = sort(candidate_score(candidate_idx), 'descend');
        candidate_idx = candidate_idx(local_order);
    end

    mas.candidate_idx = candidate_idx(:);
    mas.candidate_score = candidate_score(mas.candidate_idx);
end

function zones = parse_zone_list(x)
    parts = split(string(x), "|");
    zones = str2double(parts);
    zones = zones(~isnan(zones));
    zones = unique(zones(:)', 'stable');
end

function zone_id = zone_for_node(node_id, node_zone_map)
    idx = find(string(node_zone_map.junction_id) == string(node_id), 1);
    if isempty(idx)
        zone_id = NaN;
    else
        zone_id = node_zone_map.zone_id(idx);
    end
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
