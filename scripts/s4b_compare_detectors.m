%% s4b_compare_detectors.m -- Plan C vs CUSUM vs X-bar/FDM detection
% Uses the same digital-twin residual as s4, then compares three alarm rules:
%   1) PlanC: adaptive residual norm threshold + persistence
%   2) CUSUM: positive cumulative shift on residual norm
%   3) XBarFDM: finite-difference of moving average residual norm
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

addpath(genpath('scripts/helpers'));

%% Load data
cfg = load_config();
base = load('data/nominal_baseline.mat', 'P_nominal');

scada2018 = cache_scada('2018');
scada2019 = cache_scada('2019');

%% Shared Plan C window parameters
N_CALIB = 288;              % 24h, 5 min samples
K_PERSIST = 12;             % 1h persistence for PlanC
THRESHOLD_Q = 0.95;
THRESHOLD_GAIN = 1.30;

%% Literature-inspired detector parameters
CUSUM_DELTA = 3.0;          % tuned by s4c_tune_detector_params
CUSUM_ETA = 60.0;           % tuned by s4c_tune_detector_params

XBAR_WINDOW = 36;           % 3h moving windows; tuned by s4c_tune_detector_params
XBAR_SIGMA = 4.0;
XBAR_PERSIST = 1;

methods = ["PlanC"; "CUSUM"; "XBarFDM"; "Hybrid"];
n_leaks = height(cfg.leakages);
n_rows = n_leaks * numel(methods);

results = table('Size', [n_rows, 14], ...
    'VariableTypes', { ...
        'string','string','datetime','datetime','string','double', ...
        'logical','logical','logical','datetime','double','double','double','double'}, ...
    'VariableNames', { ...
        'method','leak_id','start_time','demo_start','leak_type','year', ...
        'alarmed','detected','false_alarm_before_leak','alarm_time','alarm_delay_h', ...
        'threshold','calib_center','calib_scale'});

row = 0;
for k = 1:n_leaks
    leak = cfg.leakages(k, :);
    leak_id = string(leak.linkID{1});
    leak_start = leak.startTime;
    leak_end = leak.endTime;
    leak_year = year(leak_start);
    leak_type = string(leak.leakType{1});

    if leak_year == 2018
        scada = scada2018;
    else
        scada = scada2019;
    end

    demo_start = dateshift(leak_start, 'start', 'day') - days(1);
    demo_end = min([leak_end, scada.time(end)]);
    demo_mask = (scada.time >= demo_start) & (scada.time <= demo_end);

    usable = sum(demo_mask) >= (N_CALIB + K_PERSIST);
    if usable
        P_measured = scada.pressures(demo_mask, :);
        demo_time = scada.time(demo_mask);
        P_nominal = nominal_slice_for_time(demo_time, base.P_nominal, leak_year);
        usable = demo_time(1) <= demo_start && leak_start > demo_time(N_CALIB);
    else
        P_measured = [];
        demo_time = datetime.empty(0, 1);
        P_nominal = [];
    end

    if usable
        bias = mean(P_measured(1:N_CALIB, :) - P_nominal(1:N_CALIB, :), 1);
        residual = (P_nominal + bias) - P_measured;
        res_norm = vecnorm(residual, 2, 2);

        [plan_idx, plan_thr, plan_center, plan_scale] = detect_planc( ...
            res_norm, N_CALIB, K_PERSIST, THRESHOLD_Q, THRESHOLD_GAIN);
        [cusum_idx, cusum_thr, cusum_center, cusum_scale] = detect_cusum( ...
            res_norm, N_CALIB, CUSUM_DELTA, CUSUM_ETA);
        [xbar_idx, xbar_thr, xbar_center, xbar_scale] = detect_xbar_fdm( ...
            res_norm, N_CALIB, XBAR_WINDOW, XBAR_SIGMA, XBAR_PERSIST);

        hybrid_idx = min_ignore_nan([plan_idx; cusum_idx]);

        method_idx = [plan_idx; cusum_idx; xbar_idx; hybrid_idx];
        thresholds = [plan_thr; cusum_thr; xbar_thr; NaN];
        centers = [plan_center; cusum_center; xbar_center; NaN];
        scales = [plan_scale; cusum_scale; xbar_scale; NaN];
    else
        method_idx = [NaN; NaN; NaN; NaN];
        thresholds = [NaN; NaN; NaN; NaN];
        centers = [NaN; NaN; NaN; NaN];
        scales = [NaN; NaN; NaN; NaN];
    end

    for m = 1:numel(methods)
        row = row + 1;
        results.method(row) = methods(m);
        results.leak_id(row) = leak_id;
        results.start_time(row) = leak_start;
        results.demo_start(row) = demo_start;
        results.leak_type(row) = leak_type;
        results.year(row) = leak_year;
        results.threshold(row) = thresholds(m);
        results.calib_center(row) = centers(m);
        results.calib_scale(row) = scales(m);
        results.alarm_delay_h(row) = NaN;
        results.alarmed(row) = false;
        results.detected(row) = false;
        results.false_alarm_before_leak(row) = false;

        if usable && ~isnan(method_idx(m))
            alarm_time = demo_time(method_idx(m));
            alarm_delay_h = hours(alarm_time - leak_start);
            is_false_alarm = alarm_time < leak_start;

            results.alarmed(row) = true;
            results.alarm_time(row) = alarm_time;
            results.alarm_delay_h(row) = alarm_delay_h;
            results.false_alarm_before_leak(row) = is_false_alarm;
            results.detected(row) = ~is_false_alarm;
        end
    end
end

out_file = fullfile('data', 'detection_comparison.csv');
writetable(results, out_file);
fprintf('\nSaved: %s\n', out_file);

fprintf('\n============================================================\n');
fprintf('  DETECTOR COMPARISON\n');
fprintf('============================================================\n');
for m = 1:numel(methods)
    t = results(results.method == methods(m), :);
    print_method_stats(methods(m), t);
end
fprintf('============================================================\n');

%% Local helpers
function P_nominal_window = nominal_slice_for_time(t, P_nominal_year, y)
    year_start = datetime(y, 1, 1, 0, 0, 0);
    idx = round(minutes(t - year_start) / 5) + 1;
    idx = max(1, min(size(P_nominal_year, 1), idx));
    P_nominal_window = P_nominal_year(idx, :);
end

function [alarm_idx, threshold, center, scale] = detect_planc(res_norm, n_calib, k_persist, q, gain)
    calib_tail = res_norm(floor(n_calib/2)+1:n_calib);
    center = quantile(calib_tail, q);
    scale = std(calib_tail, 'omitnan');
    threshold = center * gain;
    alarm_idx = persistent_threshold_alarm(res_norm, threshold, n_calib, k_persist);
end

function [alarm_idx, threshold, center, scale] = detect_cusum(res_norm, n_calib, delta, eta)
    calib_tail = res_norm(floor(n_calib/2)+1:n_calib);
    center = mean(calib_tail, 'omitnan');
    scale = std(calib_tail, 'omitnan');
    scale = max(scale, 1e-6);

    k_ref = 0.5 * delta * scale;
    threshold = eta * scale;

    s_pos = 0;
    alarm_idx = NaN;
    for i = n_calib+1:numel(res_norm)
        s_pos = max(0, s_pos + res_norm(i) - (center + k_ref));
        if s_pos > threshold
            alarm_idx = i;
            return;
        end
    end
end

function [alarm_idx, threshold, center, scale] = detect_xbar_fdm(res_norm, n_calib, window_size, sigma_mult, k_persist)
    score = NaN(size(res_norm));
    for i = 2*window_size:numel(res_norm)
        prev_mean = mean(res_norm(i-2*window_size+1:i-window_size), 'omitnan');
        curr_mean = mean(res_norm(i-window_size+1:i), 'omitnan');
        score(i) = curr_mean - prev_mean;
    end

    calib_scores = score(2*window_size:n_calib);
    center = mean(calib_scores, 'omitnan');
    scale = std(calib_scores, 'omitnan');
    scale = max(scale, 1e-6);
    threshold = center + sigma_mult * scale;

    alarm_idx = persistent_threshold_alarm(score, threshold, n_calib, k_persist);
end

function alarm_idx = persistent_threshold_alarm(x, threshold, start_idx, k_persist)
    alarm_idx = NaN;
    counter = 0;
    for i = start_idx+1:numel(x)
        if ~isnan(x(i)) && x(i) > threshold
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

function y = min_ignore_nan(x)
    x = x(~isnan(x));
    if isempty(x)
        y = NaN;
    else
        y = min(x);
    end
end

function print_method_stats(label, t)
    fprintf('\n--- %s ---\n', label);
    fprintf('Alarmed:     %d/%d (%.1f%%)\n', sum(t.alarmed), height(t), 100*mean(t.alarmed));
    fprintf('False alarm: %d/%d (%.1f%%)\n', ...
        sum(t.false_alarm_before_leak), height(t), 100*mean(t.false_alarm_before_leak));
    fprintf('Detected:    %d/%d (%.1f%%)\n', sum(t.detected), height(t), 100*mean(t.detected));

    if any(t.detected)
        fprintf('Delay median/mean/max: %.1f / %.1f / %.1f h\n', ...
            median(t.alarm_delay_h(t.detected), 'omitnan'), ...
            mean(t.alarm_delay_h(t.detected), 'omitnan'), ...
            max(t.alarm_delay_h(t.detected)));
    end

    abrupt = strcmp(t.leak_type, 'abrupt');
    incipient = strcmp(t.leak_type, 'incipient');
    fprintf('Abrupt detected:    %d/%d (%.1f%%)\n', ...
        sum(t.detected & abrupt), sum(abrupt), 100*sum(t.detected & abrupt)/max(1, sum(abrupt)));
    fprintf('Incipient detected: %d/%d (%.1f%%)\n', ...
        sum(t.detected & incipient), sum(incipient), 100*sum(t.detected & incipient)/max(1, sum(incipient)));
end
