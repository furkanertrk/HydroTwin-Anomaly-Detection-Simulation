%% s7e_compare_localizers.m -- Compare global, MAS, and XGB hybrid localizers
clc; clear;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cd(project_root);
fprintf('Project root: %s\n', pwd);

out_file = fullfile('data', 'localization_comparison_summary.csv');
rows = {};

global_file = fullfile('data', 'evaluation_results_plan_c.csv');
if isfile(global_file)
    plan_c = readtable(global_file, ...
        'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
    if all(ismember(["localized","top1_distance_m","top5_min_distance_m","top10_min_distance_m"], string(plan_c.Properties.VariableNames)))
        localized = logical(plan_c.localized);
        mean_candidates = get_global_candidate_count();
        rows(end+1, :) = make_summary_row( ...
            "Global sensitivity", ...
            plan_c.top1_distance_m(localized), ...
            plan_c.top5_min_distance_m(localized), ...
            plan_c.top10_min_distance_m(localized), ...
            repmat(mean_candidates, sum(localized), 1));
    else
        warning('evaluation_results_plan_c.csv exists but lacks global localization columns.');
    end

    mas_cols = ["mas_localized","mas_top1_distance_m","mas_top5_min_distance_m", ...
        "mas_top10_min_distance_m","mas_candidate_count"];
    if all(ismember(mas_cols, string(plan_c.Properties.VariableNames)))
        mas_localized = logical(plan_c.mas_localized);
        rows(end+1, :) = make_summary_row( ...
            "MAS sensitivity", ...
            plan_c.mas_top1_distance_m(mas_localized), ...
            plan_c.mas_top5_min_distance_m(mas_localized), ...
            plan_c.mas_top10_min_distance_m(mas_localized), ...
            plan_c.mas_candidate_count(mas_localized));
    else
        warning('MAS columns not found. Re-run scripts/s4_evaluate_all_leaks.m after the MAS update to include this row.');
    end
else
    warning('Missing %s. Global/MAS rows will be skipped.', global_file);
end

xgb_file = fullfile('data', 'xgb_hybrid_localization_results.csv');
if isfile(xgb_file)
    xgb = readtable(xgb_file, ...
        'TextType', 'string', 'VariableNamingRule', 'preserve', 'Delimiter', ',');
    required = ["evaluated","top1_error_m","top5_min_error_m","top10_min_error_m","candidate_count"];
    if all(ismember(required, string(xgb.Properties.VariableNames)))
        evaluated = logical(xgb.evaluated);
        rows(end+1, :) = make_summary_row( ...
            "XGBoost top-3 zones + sensitivity", ...
            xgb.top1_error_m(evaluated), ...
            xgb.top5_min_error_m(evaluated), ...
            xgb.top10_min_error_m(evaluated), ...
            xgb.candidate_count(evaluated));
    else
        warning('xgb_hybrid_localization_results.csv lacks required columns.');
    end
else
    warning('Missing %s. XGBoost hybrid row will be skipped.', xgb_file);
end

if isempty(rows)
    summary = table( ...
        strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', { ...
            'method_name','evaluated_leaks','top1_within_300m','top5_within_300m', ...
            'top10_within_300m','top1_within_300m_pct','top5_within_300m_pct', ...
            'top10_within_300m_pct','median_top1_error_m','mean_candidate_count'});
else
    summary = cell2table(rows, 'VariableNames', { ...
        'method_name','evaluated_leaks','top1_within_300m','top5_within_300m', ...
        'top10_within_300m','top1_within_300m_pct','top5_within_300m_pct', ...
        'top10_within_300m_pct','median_top1_error_m','mean_candidate_count'});
end

writetable(summary, out_file);
fprintf('\nSaved: %s\n', out_file);
disp(summary);
fprintf('s7e complete.\n');

%% Local helpers
function row = make_summary_row(method_name, top1, top5, top10, candidate_count)
    top1 = top1(isfinite(top1));
    top5 = top5(isfinite(top5));
    top10 = top10(isfinite(top10));
    candidate_count = candidate_count(isfinite(candidate_count));
    n = numel(top1);

    if n == 0
        row = {method_name, 0, 0, 0, 0, NaN, NaN, NaN, NaN, NaN};
        return;
    end

    top1_count = sum(top1 <= 300);
    top5_count = sum(top5 <= 300);
    top10_count = sum(top10 <= 300);
    row = { ...
        method_name, ...
        n, ...
        top1_count, ...
        top5_count, ...
        top10_count, ...
        100 * top1_count / n, ...
        100 * top5_count / n, ...
        100 * top10_count / n, ...
        median(top1, 'omitnan'), ...
        mean(candidate_count, 'omitnan')};
end

function n = get_global_candidate_count()
    n = NaN;
    try
        sens_info = whos('-file', fullfile('data', 'sensitivity_matrix.mat'), 'S_norm');
        if ~isempty(sens_info)
            n = sens_info.size(2);
        end
    catch
    end
end
