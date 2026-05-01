%% s4c_tune_detector_params.m -- parameter sweep for CUSUM and XBar/FDM
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

addpath(genpath('scripts/helpers'));

cfg = load_config();
base = load('data/nominal_baseline.mat', 'P_nominal');
scada2018 = cache_scada('2018');
scada2019 = cache_scada('2019');

N_CALIB = 288;

cusum_delta_grid = [1.0 1.5 2.0 3.0];
cusum_eta_grid = [5 10 15 20 30 40 60];
xbar_window_grid = [36 72];       % 3h, 6h
xbar_sigma_grid = [2.5 3.0 3.5 4.0 5.0];
xbar_persist_grid = [1 2 3];

configs = strings(0, 1);
kind = strings(0, 1);
p1 = [];
p2 = [];
p3 = [];

for dlt = cusum_delta_grid
    for eta = cusum_eta_grid
        configs(end+1, 1) = sprintf('CUSUM_d%.1f_eta%.0f', dlt, eta);
        kind(end+1, 1) = "CUSUM";
        p1(end+1, 1) = dlt;
        p2(end+1, 1) = eta;
        p3(end+1, 1) = NaN;
    end
end

for win = xbar_window_grid
    for sig = xbar_sigma_grid
        for kp = xbar_persist_grid
            configs(end+1, 1) = sprintf('XBar_w%d_sig%.1f_k%d', win, sig, kp);
            kind(end+1, 1) = "XBarFDM";
            p1(end+1, 1) = win;
            p2(end+1, 1) = sig;
            p3(end+1, 1) = kp;
        end
    end
end

n_cfg = numel(configs);
summary = table('Size', [n_cfg, 12], ...
    'VariableTypes', {'string','string','double','double','double','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'config','kind','param1','param2','param3','detected','false_alarm','abrupt_detected','incipient_detected','median_delay_h','mean_delay_h','score'});

residual_cases = build_residual_cases(cfg, base.P_nominal, scada2018, scada2019, N_CALIB);

for c = 1:n_cfg
    detected = false(height(cfg.leakages), 1);
    false_alarm = false(height(cfg.leakages), 1);
    delays = NaN(height(cfg.leakages), 1);

    for k = 1:numel(residual_cases)
        rc = residual_cases(k);
        if ~rc.usable
            continue;
        end

        if kind(c) == "CUSUM"
            alarm_idx = detect_cusum(rc.res_norm, N_CALIB, p1(c), p2(c));
        else
            alarm_idx = detect_xbar_fdm(rc.res_norm, N_CALIB, round(p1(c)), p2(c), round(p3(c)));
        end

        if isnan(alarm_idx)
            continue;
        end

        alarm_time = rc.time(alarm_idx);
        false_alarm(k) = alarm_time < rc.leak_start;
        detected(k) = ~false_alarm(k);
        delays(k) = hours(alarm_time - rc.leak_start);
    end

    abrupt = strcmp(string(cfg.leakages.leakType), 'abrupt');
    incipient = strcmp(string(cfg.leakages.leakType), 'incipient');

    summary.config(c) = configs(c);
    summary.kind(c) = kind(c);
    summary.param1(c) = p1(c);
    summary.param2(c) = p2(c);
    summary.param3(c) = p3(c);
    summary.detected(c) = sum(detected);
    summary.false_alarm(c) = sum(false_alarm);
    summary.abrupt_detected(c) = sum(detected & abrupt);
    summary.incipient_detected(c) = sum(detected & incipient);
    summary.median_delay_h(c) = median(delays(detected), 'omitnan');
    summary.mean_delay_h(c) = mean(delays(detected), 'omitnan');

    % Simple ranking: reward detections, penalize false alarms and very late alarms.
    summary.score(c) = summary.detected(c) ...
        - 2.0 * summary.false_alarm(c) ...
        - 0.01 * max(0, summary.median_delay_h(c));
end

summary = sortrows(summary, 'score', 'descend');
out_file = fullfile('data', 'detector_param_sweep.csv');
writetable(summary, out_file);

fprintf('\nSaved: %s\n', out_file);
fprintf('\nTop detector configs:\n');
disp(summary(1:min(15, height(summary)), :));

%% Local helpers
function cases = build_residual_cases(cfg, P_nominal_year, scada2018, scada2019, n_calib)
    n = height(cfg.leakages);
    template = struct('usable', false, 'leak_start', NaT, 'time', [], 'res_norm', []);
    cases = repmat(template, n, 1);

    for k = 1:n
        leak = cfg.leakages(k, :);
        leak_start = leak.startTime;
        leak_end = leak.endTime;
        leak_year = year(leak_start);

        if leak_year == 2018
            scada = scada2018;
        else
            scada = scada2019;
        end

        demo_start = dateshift(leak_start, 'start', 'day') - days(1);
        demo_end = min([leak_end, scada.time(end)]);
        demo_mask = (scada.time >= demo_start) & (scada.time <= demo_end);

        cases(k).leak_start = leak_start;
        if sum(demo_mask) < (n_calib + 12)
            continue;
        end

        P_measured = scada.pressures(demo_mask, :);
        t = scada.time(demo_mask);
        if t(1) > demo_start || leak_start <= t(n_calib)
            continue;
        end

        P_nominal = nominal_slice_for_time(t, P_nominal_year, leak_year);
        bias = mean(P_measured(1:n_calib, :) - P_nominal(1:n_calib, :), 1);
        residual = (P_nominal + bias) - P_measured;

        cases(k).usable = true;
        cases(k).time = t;
        cases(k).res_norm = vecnorm(residual, 2, 2);
    end
end

function P_nominal_window = nominal_slice_for_time(t, P_nominal_year, y)
    year_start = datetime(y, 1, 1, 0, 0, 0);
    idx = round(minutes(t - year_start) / 5) + 1;
    idx = max(1, min(size(P_nominal_year, 1), idx));
    P_nominal_window = P_nominal_year(idx, :);
end

function alarm_idx = detect_cusum(res_norm, n_calib, delta, eta)
    calib_tail = res_norm(floor(n_calib/2)+1:n_calib);
    center = mean(calib_tail, 'omitnan');
    scale = max(std(calib_tail, 'omitnan'), 1e-6);
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

function alarm_idx = detect_xbar_fdm(res_norm, n_calib, window_size, sigma_mult, k_persist)
    score = NaN(size(res_norm));
    for i = 2*window_size:numel(res_norm)
        prev_mean = mean(res_norm(i-2*window_size+1:i-window_size), 'omitnan');
        curr_mean = mean(res_norm(i-window_size+1:i), 'omitnan');
        score(i) = curr_mean - prev_mean;
    end

    calib_scores = score(2*window_size:n_calib);
    center = mean(calib_scores, 'omitnan');
    scale = max(std(calib_scores, 'omitnan'), 1e-6);
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
