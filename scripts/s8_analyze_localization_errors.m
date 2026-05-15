%% s8_analyze_localization_errors.m -- Diagnose localization success/failure
% Analyzes the fair CUSUM localization comparison without retraining models.
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Inputs / outputs
per_leak_file = fullfile('data', 'localization_fair_cusum_per_leak.csv');
fair_summary_file = fullfile('data', 'localization_fair_cusum_summary.csv');
feature_file = fullfile('data', 'localization_fair_cusum_features.csv');
zone_map_file = fullfile('data', 'node_zone_map.csv');
sensitivity_file = fullfile('data', 'sensitivity_matrix.mat');

analysis_file = fullfile('data', 'localization_error_analysis.csv');
summary_file = fullfile('data', 'localization_error_summary.csv');
fig_dir = fullfile(project_root, 'figures');
if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end

MAS_COVERAGE = 0.70;
MAS_MIN_SENSORS = 3;
MAS_MAX_SENSORS = 8;
MAS_CANDIDATE_Q = 0.90;
MAS_MIN_CANDIDATES = 30;
MAS_MAX_CANDIDATES = 120;

required_files = {per_leak_file, fair_summary_file, feature_file, zone_map_file, sensitivity_file};
for i = 1:numel(required_files)
    if ~isfile(required_files{i})
        error('Required file is missing: %s', required_files{i});
    end
end

%% Load data
per_leak = readtable(per_leak_file, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
fair_summary = readtable(fair_summary_file, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
features = readtable(feature_file, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
zone_map = readtable(zone_map_file, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
sens = load(sensitivity_file, 'S', 'S_norm', 'junction_ids');

assert_has_columns(per_leak, {'leak_id','true_pipe_id','true_node','method_name', ...
    'predicted_node','top1_error_m','top5_min_error_m','top10_min_error_m', ...
    'candidate_count','xgb_top1_zone','xgb_top3_zones','zone_hit_top1','zone_hit_top3'});
assert_has_columns(features, {'feature_case_index','leak_id'});
assert_has_columns(zone_map, {'junction_id','junction_index','x','y','zone_id'});

junction_ids = string(sens.junction_ids(:));
n_sensors = size(sens.S_norm, 1);
feature_names = make_feature_names(n_sensors);
mean_feature_names = feature_names(1:n_sensors);
missing_features = setdiff(string(feature_names), string(features.Properties.VariableNames));
if ~isempty(missing_features)
    error('Feature file is missing columns. First missing: %s', missing_features(1));
end

%% Sensitivity strength and weak/blind region tags
sensitivity_strength = vecnorm(sens.S, 2, 1)';
strength_q20 = quantile(sensitivity_strength, 0.20);
strength_q10 = quantile(sensitivity_strength, 0.10);

strength_table = table( ...
    junction_ids, sensitivity_strength, ...
    sensitivity_strength <= strength_q20, ...
    sensitivity_strength <= strength_q10, ...
    'VariableNames', {'true_node','true_sensitivity_strength','weak_sensitivity_q20','blind_sensitivity_q10'});

per_leak = outerjoin(per_leak, strength_table, ...
    'Keys', 'true_node', ...
    'MergeKeys', true, ...
    'Type', 'left');

%% Compute confidence from ranked correlation scores using the same residual means
per_leak.confidence_gap = NaN(height(per_leak), 1);
per_leak.confidence_ratio = NaN(height(per_leak), 1);
per_leak.true_zone_id = NaN(height(per_leak), 1);
per_leak.predicted_zone_id = NaN(height(per_leak), 1);
per_leak.failure_mode = strings(height(per_leak), 1);

zone_by_node = containers.Map(cellstr(string(zone_map.junction_id)), num2cell(zone_map.zone_id));
[is_mapped, zone_loc] = ismember(junction_ids, string(zone_map.junction_id));
if ~all(is_mapped)
    missing = junction_ids(~is_mapped);
    error('Zone map missing %d sensitivity junctions. First missing: %s', numel(missing), missing(1));
end
zone_by_sens = zone_map.zone_id(zone_loc);

for i = 1:height(per_leak)
    leak_id = per_leak.leak_id(i);
    fidx = find(features.leak_id == leak_id, 1);
    if isempty(fidx)
        continue;
    end

    r_mean = table2array(features(fidx, mean_feature_names))';
    method_name = per_leak.method_name(i);

    if method_name == "Global sensitivity"
        candidate_idx = (1:numel(junction_ids))';
    elseif method_name == "MAS sensitivity"
        mas = build_mas_candidates(r_mean, sens.S, MAS_COVERAGE, MAS_MIN_SENSORS, ...
            MAS_MAX_SENSORS, MAS_CANDIDATE_Q, MAS_MIN_CANDIDATES, MAS_MAX_CANDIDATES);
        candidate_idx = mas.candidate_idx;
    elseif startsWith(method_name, "XGBoost")
        zones = parse_zone_list(per_leak.xgb_top3_zones(i));
        candidate_idx = find(ismember(zone_by_sens, zones));
    else
        candidate_idx = [];
    end

    if isempty(candidate_idx)
        continue;
    end

    [~, sorted_corr] = rank_sensitivity_candidates(sens.S_norm, r_mean, candidate_idx, 10);
    if numel(sorted_corr) >= 2
        per_leak.confidence_gap(i) = sorted_corr(1) - sorted_corr(2);
        per_leak.confidence_ratio(i) = sorted_corr(1) / (abs(sorted_corr(2)) + 1e-9);
    end

    per_leak.true_zone_id(i) = zone_for_node(per_leak.true_node(i), zone_by_node);
    per_leak.predicted_zone_id(i) = zone_for_node(per_leak.predicted_node(i), zone_by_node);
end

per_leak.top1_success_300m = per_leak.top1_error_m <= 300;
per_leak.top5_success_300m = per_leak.top5_min_error_m <= 300;
per_leak.top10_success_300m = per_leak.top10_min_error_m <= 300;

for i = 1:height(per_leak)
    if per_leak.top1_success_300m(i)
        per_leak.failure_mode(i) = "success_top1";
    elseif per_leak.top10_success_300m(i)
        per_leak.failure_mode(i) = "residual_ambiguity_top10_success";
    elseif startsWith(per_leak.method_name(i), "XGBoost") && ~logical_or_false(per_leak.zone_hit_top3(i))
        per_leak.failure_mode(i) = "wrong_candidate_reduction";
    elseif logical_or_false(per_leak.blind_sensitivity_q10(i))
        per_leak.failure_mode(i) = "weak_sensitivity_region";
    elseif logical_or_false(per_leak.weak_sensitivity_q20(i))
        per_leak.failure_mode(i) = "low_sensitivity_region";
    else
        per_leak.failure_mode(i) = "residual_ambiguity_or_model_mismatch";
    end
end

%% Method-level summaries
methods = unique(per_leak.method_name, 'stable');
summary_rows = cell(numel(methods), 25);
for i = 1:numel(methods)
    m = methods(i);
    t = per_leak(per_leak.method_name == m, :);
    summary_rows(i, :) = make_summary_row(m, t);
end
analysis_summary = cell2table(summary_rows, 'VariableNames', { ...
    'method_name','evaluated_leaks','top1_within_300m','top5_within_300m', ...
    'top10_within_300m','top1_rate','top5_rate','top10_rate', ...
    'top1_error_min_m','top1_error_median_m','top1_error_mean_m','top1_error_max_m', ...
    'candidate_count_min','candidate_count_median','candidate_count_mean','candidate_count_max', ...
    'confidence_gap_median','confidence_ratio_median','abrupt_top1_rate','incipient_top1_rate', ...
    'abrupt_top10_rate','incipient_top10_rate','weak_sensitivity_failures', ...
    'xgb_zone_hit_top1','xgb_zone_hit_top3'});

%% Worst 5 per method
worst_rows = {};
for i = 1:numel(methods)
    m = methods(i);
    t = sortrows(per_leak(per_leak.method_name == m, :), 'top1_error_m', 'descend');
    n = min(5, height(t));
    fprintf('\nWorst %d leaks for %s:\n', n, m);
    for j = 1:n
        fprintf('  %-8s top1=%7.1fm top10=%7.1fm mode=%s\n', ...
            t.leak_id(j), t.top1_error_m(j), t.top10_min_error_m(j), t.failure_mode(j));
        worst_rows(end+1, :) = {m, j, t.leak_id(j), t.leak_type(j), ...
            t.top1_error_m(j), t.top10_min_error_m(j), t.failure_mode(j)}; %#ok<SAGROW>
    end
end

worst_table = cell2table(worst_rows, 'VariableNames', { ...
    'method_name','worst_rank','leak_id','leak_type','top1_error_m', ...
    'top10_min_error_m','failure_mode'});

%% Write outputs
writetable(per_leak, analysis_file);
writetable(analysis_summary, summary_file);

fprintf('\nSaved: %s\n', analysis_file);
fprintf('Saved: %s\n', summary_file);

%% Figures
make_error_histogram(per_leak, fullfile(fig_dir, 'localization_error_histogram.png'));
make_top1_bar(analysis_summary, fullfile(fig_dir, 'top1_error_by_method.png'));
make_sensitivity_map(zone_map, strength_table, per_leak, fullfile(fig_dir, 'sensitivity_strength_map.png'));
make_xgb_zone_hit_plot(per_leak, fullfile(fig_dir, 'xgb_zone_hit_vs_error.png'));

fprintf('\nSaved figures in: %s\n', fig_dir);
disp(analysis_summary);

%% High-level cause diagnostics
failures = per_leak(~per_leak.top10_success_300m, :);
xgb = per_leak(startsWith(per_leak.method_name, "XGBoost"), :);
fprintf('\nFailure diagnostics:\n');
fprintf('  Top-10 failures in weak/blind sensitivity regions: %d/%d\n', ...
    sum(logical_or_false(failures.weak_sensitivity_q20) | logical_or_false(failures.blind_sensitivity_q10)), ...
    height(failures));
fprintf('  XGBoost zone top-1 hit: %d/%d\n', sum(logical_or_false(xgb.zone_hit_top1)), height(xgb));
fprintf('  XGBoost zone top-3 hit: %d/%d\n', sum(logical_or_false(xgb.zone_hit_top3)), height(xgb));

[~, best_idx] = max(analysis_summary.top10_rate + 0.001 * analysis_summary.top5_rate);
fprintf('  Recommended final localizer: %s\n', analysis_summary.method_name(best_idx));

%% Local helpers
function assert_has_columns(t, names)
    missing = setdiff(string(names), string(t.Properties.VariableNames));
    if ~isempty(missing)
        error('Table is missing required columns: %s', strjoin(cellstr(missing), ', '));
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

function [ranked_idx, sorted_corr] = rank_sensitivity_candidates(S_norm, r_mean, candidate_idx, top_k)
    candidate_idx = unique(candidate_idx(:), 'stable');
    candidate_idx = candidate_idx(candidate_idx >= 1 & candidate_idx <= size(S_norm, 2));
    r_norm = r_mean ./ (norm(r_mean) + 1e-9);
    correlations = S_norm' * r_norm;
    [sorted_corr_all, order] = sort(correlations(candidate_idx), 'descend');
    ranked_idx_all = candidate_idx(order);
    take_k = min(top_k, numel(ranked_idx_all));
    ranked_idx = ranked_idx_all(1:take_k);
    sorted_corr = sorted_corr_all(1:take_k);
end

function zone_id = zone_for_node(node_id, zone_by_node)
    key = char(string(node_id));
    if isKey(zone_by_node, key)
        zone_id = zone_by_node(key);
    else
        zone_id = NaN;
    end
end

function zones = parse_zone_list(x)
    parts = split(string(x), "|");
    zones = str2double(parts);
    zones = zones(~isnan(zones));
    zones = unique(zones(:)', 'stable');
end

function tf = logical_or_false(x)
    if islogical(x)
        tf = x;
    elseif isnumeric(x)
        tf = x ~= 0 & ~isnan(x);
    elseif isstring(x) || ischar(x)
        sx = lower(string(x));
        tf = sx == "true" | sx == "1";
    else
        tf = false(size(x));
    end
end

function row = make_summary_row(method_name, t)
    is_xgb = startsWith(method_name, "XGBoost");
    if is_xgb
        xgb_hit1 = sum(logical_or_false(t.zone_hit_top1));
        xgb_hit3 = sum(logical_or_false(t.zone_hit_top3));
    else
        xgb_hit1 = NaN;
        xgb_hit3 = NaN;
    end

    abrupt = lower(t.leak_type) == "abrupt";
    incipient = lower(t.leak_type) == "incipient";
    abrupt_top1 = mean_or_nan(t.top1_success_300m(abrupt));
    incipient_top1 = mean_or_nan(t.top1_success_300m(incipient));
    abrupt_top10 = mean_or_nan(t.top10_success_300m(abrupt));
    incipient_top10 = mean_or_nan(t.top10_success_300m(incipient));

    row = { ...
        method_name, ...
        height(t), ...
        sum(t.top1_success_300m), ...
        sum(t.top5_success_300m), ...
        sum(t.top10_success_300m), ...
        mean(t.top1_success_300m), ...
        mean(t.top5_success_300m), ...
        mean(t.top10_success_300m), ...
        min(t.top1_error_m), ...
        median(t.top1_error_m, 'omitnan'), ...
        mean(t.top1_error_m, 'omitnan'), ...
        max(t.top1_error_m), ...
        min(t.candidate_count), ...
        median(t.candidate_count, 'omitnan'), ...
        mean(t.candidate_count, 'omitnan'), ...
        max(t.candidate_count), ...
        median(t.confidence_gap, 'omitnan'), ...
        median(t.confidence_ratio, 'omitnan'), ...
        abrupt_top1, ...
        incipient_top1, ...
        abrupt_top10, ...
        incipient_top10, ...
        sum((~t.top10_success_300m) & (logical_or_false(t.weak_sensitivity_q20) | logical_or_false(t.blind_sensitivity_q10))), ...
        xgb_hit1, ...
        xgb_hit3};
end

function y = mean_or_nan(x)
    if isempty(x)
        y = NaN;
    else
        y = mean(x, 'omitnan');
    end
end

function mas = build_mas_candidates(r_mean, S, coverage, min_sensors, max_sensors, candidate_q, min_candidates, max_candidates)
    sensor_mag = abs(r_mean(:));
    contribution = sensor_mag / (sum(sensor_mag) + 1e-9);
    [~, sensor_order] = sort(sensor_mag, 'descend');

    n_mas = find(cumsum(contribution(sensor_order)) >= coverage, 1, 'first');
    if isempty(n_mas)
        n_mas = min_sensors;
    end
    n_mas = min(max(n_mas, min_sensors), max_sensors);
    mas.sensor_idx = sensor_order(1:n_mas);

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

function make_error_histogram(per_leak, out_path)
    fig = figure('Visible', 'off', 'Color', 'w');
    hold on;
    methods = unique(per_leak.method_name, 'stable');
    for i = 1:numel(methods)
        t = per_leak(per_leak.method_name == methods(i), :);
        histogram(t.top1_error_m, 'BinWidth', 200, 'DisplayStyle', 'stairs', 'LineWidth', 1.5);
    end
    xline(300, '--k', '300 m');
    grid on;
    xlabel('Top-1 localization error (m)');
    ylabel('Leak count');
    legend(methods, 'Location', 'best', 'Interpreter', 'none');
    title('Localization error distribution');
    exportgraphics(fig, out_path, 'Resolution', 180);
    close(fig);
end

function make_top1_bar(summary, out_path)
    fig = figure('Visible', 'off', 'Color', 'w');
    bar(categorical(summary.method_name), summary.top1_error_median_m);
    grid on;
    ylabel('Median Top-1 error (m)');
    title('Median Top-1 error by method');
    ax = gca;
    ax.TickLabelInterpreter = 'none';
    exportgraphics(fig, out_path, 'Resolution', 180);
    close(fig);
end

function make_sensitivity_map(zone_map, strength_table, per_leak, out_path)
    z = outerjoin(zone_map, strength_table, ...
        'LeftKeys', 'junction_id', 'RightKeys', 'true_node', ...
        'MergeKeys', false, 'Type', 'left');
    fig = figure('Visible', 'off', 'Color', 'w');
    scatter(z.x, z.y, 16, z.true_sensitivity_strength, 'filled');
    hold on;
    unique_leaks = unique(per_leak(:, {'leak_id','true_node'}), 'rows');
    [~, loc] = ismember(unique_leaks.true_node, string(zone_map.junction_id));
    loc = loc(loc > 0);
    scatter(zone_map.x(loc), zone_map.y(loc), 42, 'r', 'LineWidth', 1.2);
    axis equal;
    grid on;
    colorbar;
    xlabel('x');
    ylabel('y');
    title('Sensitivity strength map and evaluated leak nodes');
    exportgraphics(fig, out_path, 'Resolution', 180);
    close(fig);
end

function make_xgb_zone_hit_plot(per_leak, out_path)
    xgb = per_leak(startsWith(per_leak.method_name, "XGBoost"), :);
    if isempty(xgb)
        return;
    end
    hit = logical_or_false(xgb.zone_hit_top3);
    fig = figure('Visible', 'off', 'Color', 'w');
    boxchart(categorical(hit), xgb.top1_error_m);
    grid on;
    xlabel('True zone in XGBoost top-3');
    ylabel('Top-1 error (m)');
    title('XGBoost zone hit vs localization error');
    exportgraphics(fig, out_path, 'Resolution', 180);
    close(fig);
end
