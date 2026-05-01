%% s4_evaluate_all_leaks.m -- Plan C batch evaluation for all BattLeDIM leaks
% Offline batch equivalent of the real-time Simulink logic:
% nominal baseline + 24h bias calibration + adaptive threshold +
% 12-sample persistence + alarm-aware 24h localization window.
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

run('toolkit/start_toolkit.m');
addpath(genpath('scripts/helpers'));

%% Load data
cfg = load_config();
sens = load('data/sensitivity_matrix.mat', ...
    'S', 'S_norm', 'junction_ids', 'sensor_indices');
base = load('data/nominal_baseline.mat', 'P_nominal', 'nominal_time');

d = load_ltown();
coords = d.getNodeCoordinates;
node_x = coords{1};
node_y = coords{2};

scada2018 = cache_scada('2018');
scada2019 = cache_scada('2019');

%% Plan C parameters
N_CALIB = 288;              % 24h, 5 min samples
N_WINDOW = 288;             % 24h localization average
K_PERSIST = 12;             % 1h persistence
THRESHOLD_Q = 0.95;
THRESHOLD_GAIN = 1.30;
TOP_K = 10;

% MAS localization parameters. MAS first selects the most affected sensors,
% then limits candidate junctions to nodes those sensors can strongly observe.
MAS_COVERAGE = 0.70;
MAS_MIN_SENSORS = 3;
MAS_MAX_SENSORS = 8;
MAS_CANDIDATE_Q = 0.90;
MAS_MIN_CANDIDATES = 30;
MAS_MAX_CANDIDATES = 120;

n_leaks = height(cfg.leakages);
fprintf('\nPlan C batch evaluation: %d leaks\n\n', n_leaks);

results = table('Size', [n_leaks, 41], ...
    'VariableTypes', { ...
        'string','datetime','datetime','datetime','datetime','string','double','double', ...
        'logical','logical','logical','double','datetime','double','datetime', ...
        'double','double','string','double','double','double','double', ...
        'double','double','double','logical','logical','logical','string', ...
        'double','double','double','double','double','double','double', ...
        'logical','logical','double','double','string'}, ...
    'VariableNames', { ...
        'leak_id','start_time','end_time','demo_start','calibration_end','leak_type','diameter_mm','year', ...
        'detected','false_alarm_before_leak','localized','alarm_delay_h','alarm_time','localization_delay_h','localization_time', ...
        'threshold_m','calib_q95_m','predicted_node','top1_distance_m','top5_min_distance_m', ...
        'top10_min_distance_m','mean_top10_distance_m','top1_correlation','confidence_gap','confidence_ratio', ...
        'within_300m_top1','within_300m_top10', ...
        'mas_localized','mas_predicted_node','mas_top1_distance_m','mas_top5_min_distance_m', ...
        'mas_top10_min_distance_m','mas_mean_top10_distance_m','mas_top1_correlation', ...
        'mas_confidence_gap','mas_confidence_ratio','mas_within_300m_top1','mas_within_300m_top10', ...
        'mas_sensor_count','mas_candidate_count','mas_sensor_ids'});

for k = 1:n_leaks
    leak = cfg.leakages(k, :);
    leak_id = string(leak.linkID{1});
    leak_start = leak.startTime;
    leak_end = leak.endTime;
    leak_year = year(leak_start);
    leak_type = string(leak.leakType{1});
    diameter_mm = leak.diameter_m * 1000;

    results.leak_id(k) = leak_id;
    results.start_time(k) = leak_start;
    results.end_time(k) = leak_end;
    demo_start = dateshift(leak_start, 'start', 'day') - days(1);
    calibration_end = demo_start + hours(24);

    results.demo_start(k) = demo_start;
    results.calibration_end(k) = calibration_end;
    results.leak_type(k) = leak_type;
    results.diameter_mm(k) = diameter_mm;
    results.year(k) = leak_year;
    results.detected(k) = false;
    results.false_alarm_before_leak(k) = false;
    results.localized(k) = false;
    results.alarm_delay_h(k) = NaN;
    results.localization_delay_h(k) = NaN;
    results.threshold_m(k) = NaN;
    results.calib_q95_m(k) = NaN;
    results.predicted_node(k) = "";
    results.top1_distance_m(k) = NaN;
    results.top5_min_distance_m(k) = NaN;
    results.top10_min_distance_m(k) = NaN;
    results.mean_top10_distance_m(k) = NaN;
    results.top1_correlation(k) = NaN;
    results.confidence_gap(k) = NaN;
    results.confidence_ratio(k) = NaN;
    results.within_300m_top1(k) = false;
    results.within_300m_top10(k) = false;
    results.mas_localized(k) = false;
    results.mas_predicted_node(k) = "";
    results.mas_top1_distance_m(k) = NaN;
    results.mas_top5_min_distance_m(k) = NaN;
    results.mas_top10_min_distance_m(k) = NaN;
    results.mas_mean_top10_distance_m(k) = NaN;
    results.mas_top1_correlation(k) = NaN;
    results.mas_confidence_gap(k) = NaN;
    results.mas_confidence_ratio(k) = NaN;
    results.mas_within_300m_top1(k) = false;
    results.mas_within_300m_top10(k) = false;
    results.mas_sensor_count(k) = NaN;
    results.mas_candidate_count(k) = NaN;
    results.mas_sensor_ids(k) = "";

    if leak_year == 2018
        scada = scada2018;
    else
        scada = scada2019;
    end

    demo_end = min([leak_end, scada.time(end)]);
    demo_mask = (scada.time >= demo_start) & (scada.time <= demo_end);

    if sum(demo_mask) < (N_CALIB + K_PERSIST + N_WINDOW)
        fprintf('%2d/%d  %-8s skipped: not enough samples in demo window\n', ...
            k, n_leaks, leak_id);
        continue;
    end

    P_measured = scada.pressures(demo_mask, :);
    demo_time = scada.time(demo_mask);
    P_nominal = nominal_slice_for_time(demo_time, base.P_nominal, leak_year);

    if demo_time(1) > demo_start || leak_start <= demo_time(N_CALIB)
        fprintf('%2d/%d  %-8s skipped: clean previous-day calibration is not available\n', ...
            k, n_leaks, leak_id);
        continue;
    end

    if size(P_measured, 2) ~= size(P_nominal, 2)
        error('Pressure width mismatch: SCADA=%d, nominal=%d', ...
            size(P_measured, 2), size(P_nominal, 2));
    end

    % 1) Digital twin: nominal baseline + online bias correction.
    bias = mean(P_measured(1:N_CALIB, :) - P_nominal(1:N_CALIB, :), 1);
    P_predicted = P_nominal + bias;

    % 2) Residual convention: twin - measured.
    residual = P_predicted - P_measured;
    res_norm = vecnorm(residual, 2, 2);

    % 3) Adaptive threshold from the clean calibration tail.
    calib_tail = res_norm(floor(N_CALIB/2)+1:N_CALIB);
    calib_q95 = quantile(calib_tail, THRESHOLD_Q);
    threshold = calib_q95 * THRESHOLD_GAIN;

    % 4) Real-time detector: ignore calibration, then require persistence.
    alarm_idx = find_alarm_idx(res_norm, threshold, N_CALIB, K_PERSIST);
    if isnan(alarm_idx)
        results.threshold_m(k) = threshold;
        results.calib_q95_m(k) = calib_q95;
        fprintf('%2d/%d  %-8s %-9s no alarm   threshold=%.2f m\n', ...
            k, n_leaks, leak_id, leak_type, threshold);
        continue;
    end

    alarm_time = demo_time(alarm_idx);
    alarm_delay_h = hours(alarm_time - leak_start);

    if alarm_time < leak_start
        results.false_alarm_before_leak(k) = true;
        results.alarm_time(k) = alarm_time;
        results.alarm_delay_h(k) = alarm_delay_h;
        results.threshold_m(k) = threshold;
        results.calib_q95_m(k) = calib_q95;
        fprintf('%2d/%d  %-8s %-9s false alarm %6.1fh before leak  threshold=%.2f m\n', ...
            k, n_leaks, leak_id, leak_type, abs(alarm_delay_h), threshold);
        continue;
    end

    results.detected(k) = true;
    results.alarm_time(k) = alarm_time;
    results.alarm_delay_h(k) = alarm_delay_h;
    results.threshold_m(k) = threshold;
    results.calib_q95_m(k) = calib_q95;

    % 5) Alarm-aware localization: wait 24h, average last 24h, latch result.
    loc_idx = alarm_idx + N_WINDOW;
    if loc_idx > size(residual, 1)
        fprintf('%2d/%d  %-8s %-9s alarm=%6.1fh  no localization window\n', ...
            k, n_leaks, leak_id, leak_type, alarm_delay_h);
        continue;
    end

    r_avg = mean(residual(loc_idx-N_WINDOW+1:loc_idx, :), 1)';
    full_loc = rank_localization_candidates( ...
        sens.S_norm, sens.junction_ids, r_avg, 1:numel(sens.junction_ids), TOP_K);
    mas = build_mas_candidates( ...
        r_avg, sens.S, cfg.pressure_sensors, MAS_COVERAGE, MAS_MIN_SENSORS, ...
        MAS_MAX_SENSORS, MAS_CANDIDATE_Q, MAS_MIN_CANDIDATES, MAS_MAX_CANDIDATES);
    mas_loc = rank_localization_candidates( ...
        sens.S_norm, sens.junction_ids, r_avg, mas.candidate_idx, TOP_K);

    try
        gt = pipe_midpoint(d, leak_id, node_x, node_y);
        distances = distances_to_nodes(d, full_loc.top_names, gt.x, gt.y, node_x, node_y);
        mas_distances = distances_to_nodes(d, mas_loc.top_names, gt.x, gt.y, node_x, node_y);
    catch ME
        warning('Ground truth distance failed for %s: %s', leak_id, ME.message);
        continue;
    end

    results.localized(k) = true;
    results.localization_time(k) = demo_time(loc_idx);
    results.localization_delay_h(k) = hours(demo_time(loc_idx) - leak_start);
    results.predicted_node(k) = string(full_loc.top_names{1});
    results.top1_distance_m(k) = distances(1);
    results.top5_min_distance_m(k) = min(distances(1:min(5, numel(distances))));
    results.top10_min_distance_m(k) = min(distances);
    results.mean_top10_distance_m(k) = mean(distances);
    results.top1_correlation(k) = full_loc.top1_correlation;
    results.confidence_gap(k) = full_loc.confidence_gap;
    results.confidence_ratio(k) = full_loc.confidence_ratio;
    results.within_300m_top1(k) = distances(1) <= 300;
    results.within_300m_top10(k) = min(distances) <= 300;

    results.mas_localized(k) = true;
    results.mas_predicted_node(k) = string(mas_loc.top_names{1});
    results.mas_top1_distance_m(k) = mas_distances(1);
    results.mas_top5_min_distance_m(k) = min(mas_distances(1:min(5, numel(mas_distances))));
    results.mas_top10_min_distance_m(k) = min(mas_distances);
    results.mas_mean_top10_distance_m(k) = mean(mas_distances);
    results.mas_top1_correlation(k) = mas_loc.top1_correlation;
    results.mas_confidence_gap(k) = mas_loc.confidence_gap;
    results.mas_confidence_ratio(k) = mas_loc.confidence_ratio;
    results.mas_within_300m_top1(k) = mas_distances(1) <= 300;
    results.mas_within_300m_top10(k) = min(mas_distances) <= 300;
    results.mas_sensor_count(k) = numel(mas.sensor_idx);
    results.mas_candidate_count(k) = numel(mas.candidate_idx);
    results.mas_sensor_ids(k) = string(strjoin(cellstr(mas.sensor_ids(:)), '|'));

    fprintf('%2d/%d  %-8s %-9s alarm=%6.1fh  loc=%6.1fh  top1=%6.0fm  best10=%6.0fm  mas1=%6.0fm  pred=%s  mas=%s\n', ...
        k, n_leaks, leak_id, leak_type, ...
        results.alarm_delay_h(k), results.localization_delay_h(k), ...
        results.top1_distance_m(k), results.top10_min_distance_m(k), ...
        results.mas_top1_distance_m(k), results.predicted_node(k), results.mas_predicted_node(k));
end

%% Save and summarize
out_file = fullfile('data', 'evaluation_results_plan_c.csv');
writetable(results, out_file);
fprintf('\nSaved: %s\n', out_file);

valid_detected = results.detected;
valid_localized = results.localized;

fprintf('\n============================================================\n');
fprintf('  PLAN C AGGREGATE METRICS\n');
fprintf('============================================================\n');
print_detection_stats('ALL LEAKS', results);

abrupt_mask = strcmp(results.leak_type, 'abrupt');
incipient_mask = strcmp(results.leak_type, 'incipient');
print_detection_stats('ABRUPT', results(abrupt_mask, :));
print_detection_stats('INCIPIENT', results(incipient_mask, :));

if any(valid_localized)
    fprintf('\n--- LOCALIZATION, localized only (n=%d) ---\n', sum(valid_localized));
    fprintf('Top-1 <=300m:  %d/%d (%.1f%%)\n', ...
        sum(results.within_300m_top1(valid_localized)), sum(valid_localized), ...
        100 * mean(results.within_300m_top1(valid_localized)));
    fprintf('Top-5 <=300m:  %d/%d (%.1f%%)\n', ...
        sum(results.top5_min_distance_m(valid_localized) <= 300), sum(valid_localized), ...
        100 * mean(results.top5_min_distance_m(valid_localized) <= 300));
    fprintf('Top-10 <=300m: %d/%d (%.1f%%)\n', ...
        sum(results.within_300m_top10(valid_localized)), sum(valid_localized), ...
        100 * mean(results.within_300m_top10(valid_localized)));
    fprintf('Top-1 distance median/mean: %.0f / %.0f m\n', ...
        median(results.top1_distance_m(valid_localized), 'omitnan'), ...
        mean(results.top1_distance_m(valid_localized), 'omitnan'));
    fprintf('Confidence gap median/mean: %.4f / %.4f\n', ...
        median(results.confidence_gap(valid_localized), 'omitnan'), ...
        mean(results.confidence_gap(valid_localized), 'omitnan'));
    fprintf('Alarm delay median/mean: %.1f / %.1f h\n', ...
        median(results.alarm_delay_h(valid_detected), 'omitnan'), ...
        mean(results.alarm_delay_h(valid_detected), 'omitnan'));
end
print_mas_localization_stats('MAS ALL LEAKS', results);
print_mas_localization_stats('MAS ABRUPT', results(abrupt_mask, :));
print_mas_localization_stats('MAS INCIPIENT', results(incipient_mask, :));
fprintf('============================================================\n');

d.unload;

%% Local helpers
function P_nominal_window = nominal_slice_for_time(t, P_nominal_year, y)
    year_start = datetime(y, 1, 1, 0, 0, 0);
    idx = round(minutes(t - year_start) / 5) + 1;
    idx = max(1, min(size(P_nominal_year, 1), idx));
    P_nominal_window = P_nominal_year(idx, :);
end

function alarm_idx = find_alarm_idx(res_norm, threshold, n_calib, k_persist)
    alarm_idx = NaN;
    counter = 0;
    for i = n_calib+1:numel(res_norm)
        if res_norm(i) > threshold
            counter = counter + 1;
            if counter >= k_persist
                alarm_idx = i;
                return;
            end
        else
            counter = 0;
        end
    end
end

function gt = pipe_midpoint(d, leak_id, node_x, node_y)
    link_idx = d.getLinkIndex(char(leak_id));
    link_nodes = d.getLinkNodesIndex(link_idx);
    gt.x = (node_x(link_nodes(1)) + node_x(link_nodes(2))) / 2;
    gt.y = (node_y(link_nodes(1)) + node_y(link_nodes(2))) / 2;
end

function distances = distances_to_nodes(d, node_names, gt_x, gt_y, node_x, node_y)
    distances = zeros(numel(node_names), 1);
    for i = 1:numel(node_names)
        node_idx = d.getNodeIndex(node_names{i});
        distances(i) = hypot(node_x(node_idx) - gt_x, node_y(node_idx) - gt_y);
    end
end

function loc = rank_localization_candidates(S_norm, junction_ids, r_avg, candidate_idx, top_k)
    candidate_idx = candidate_idx(:);
    candidate_idx = candidate_idx(candidate_idx >= 1 & candidate_idx <= size(S_norm, 2));
    candidate_idx = unique(candidate_idx, 'stable');

    r_norm = r_avg / (norm(r_avg) + 1e-9);
    all_corr = S_norm' * r_norm;

    [sorted_corr, order] = sort(all_corr(candidate_idx), 'descend');
    ranked_idx = candidate_idx(order);
    take_k = min(top_k, numel(ranked_idx));

    loc.node_idx = ranked_idx(1:take_k);
    loc.top_names = junction_ids(loc.node_idx);
    loc.sorted_corr = sorted_corr(1:take_k);
    loc.top1_correlation = loc.sorted_corr(1);

    if take_k >= 2
        loc.confidence_gap = loc.sorted_corr(1) - loc.sorted_corr(2);
        loc.confidence_ratio = loc.sorted_corr(1) / (abs(loc.sorted_corr(2)) + 1e-9);
    else
        loc.confidence_gap = NaN;
        loc.confidence_ratio = NaN;
    end
end

function mas = build_mas_candidates(r_avg, S, pressure_sensors, coverage, min_sensors, max_sensors, candidate_q, min_candidates, max_candidates)
    sensor_mag = abs(r_avg(:));
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

function print_detection_stats(label, t)
    n = height(t);
    if n == 0
        return;
    end

    detected = t.detected;
    localized = t.localized;

    fprintf('\n--- %s (n=%d) ---\n', label, n);
    fprintf('False alarms before leak: %d/%d (%.1f%%)\n', ...
        sum(t.false_alarm_before_leak), n, 100 * mean(t.false_alarm_before_leak));
    fprintf('Detected:   %d/%d (%.1f%%)\n', sum(detected), n, 100 * mean(detected));
    fprintf('Localized:  %d/%d (%.1f%%)\n', sum(localized), n, 100 * mean(localized));

    if any(detected)
        fprintf('Alarm delay: median=%.1fh  mean=%.1fh  max=%.1fh\n', ...
            median(t.alarm_delay_h(detected), 'omitnan'), ...
            mean(t.alarm_delay_h(detected), 'omitnan'), ...
            max(t.alarm_delay_h(detected)));
    end

    if any(localized)
        fprintf('Top-1 <=300m:  %d/%d (%.1f%%)\n', ...
            sum(t.within_300m_top1(localized)), sum(localized), ...
            100 * mean(t.within_300m_top1(localized)));
        fprintf('Top-5 <=300m:  %d/%d (%.1f%%)\n', ...
            sum(t.top5_min_distance_m(localized) <= 300), sum(localized), ...
            100 * mean(t.top5_min_distance_m(localized) <= 300));
        fprintf('Top-10 <=300m: %d/%d (%.1f%%)\n', ...
            sum(t.within_300m_top10(localized)), sum(localized), ...
            100 * mean(t.within_300m_top10(localized)));
        fprintf('Top-1 distance: median=%.0fm  mean=%.0fm\n', ...
            median(t.top1_distance_m(localized), 'omitnan'), ...
            mean(t.top1_distance_m(localized), 'omitnan'));
    end
end

function print_mas_localization_stats(label, t)
    localized = t.mas_localized;
    if ~any(localized)
        return;
    end

    fprintf('\n--- %s, localized only (n=%d) ---\n', label, sum(localized));
    fprintf('MAS Top-1 <=300m:  %d/%d (%.1f%%)\n', ...
        sum(t.mas_within_300m_top1(localized)), sum(localized), ...
        100 * mean(t.mas_within_300m_top1(localized)));
    fprintf('MAS Top-5 <=300m:  %d/%d (%.1f%%)\n', ...
        sum(t.mas_top5_min_distance_m(localized) <= 300), sum(localized), ...
        100 * mean(t.mas_top5_min_distance_m(localized) <= 300));
    fprintf('MAS Top-10 <=300m: %d/%d (%.1f%%)\n', ...
        sum(t.mas_within_300m_top10(localized)), sum(localized), ...
        100 * mean(t.mas_within_300m_top10(localized)));
    fprintf('MAS Top-1 distance median/mean: %.0f / %.0f m\n', ...
        median(t.mas_top1_distance_m(localized), 'omitnan'), ...
        mean(t.mas_top1_distance_m(localized), 'omitnan'));
    fprintf('MAS confidence gap median/mean: %.4f / %.4f\n', ...
        median(t.mas_confidence_gap(localized), 'omitnan'), ...
        mean(t.mas_confidence_gap(localized), 'omitnan'));
    fprintf('MAS sensors median/mean: %.0f / %.1f\n', ...
        median(t.mas_sensor_count(localized), 'omitnan'), ...
        mean(t.mas_sensor_count(localized), 'omitnan'));
    fprintf('MAS candidates median/mean: %.0f / %.1f\n', ...
        median(t.mas_candidate_count(localized), 'omitnan'), ...
        mean(t.mas_candidate_count(localized), 'omitnan'));
end
