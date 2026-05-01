function scada = load_scada(year_str)
% load_scada  BattLeDIM SCADA verisini yükler (2018 veya 2019)
%   scada = load_scada('2018')
%   scada = load_scada('2019')

    if nargin < 1, year_str = '2018'; end
    data_dir = 'data';
    
    fprintf('📥 SCADA verisi yükleniyor: %s\n', year_str);
    tic;
    
    % Pressures (meters)
    fname = fullfile(data_dir, [year_str '_SCADA_Pressures.csv']);
    [scada.pressures, scada.pressure_names, scada.time] = ...
        read_scada_csv(fname, true);
    
    % Flows (m^3/h)
    fname = fullfile(data_dir, [year_str '_SCADA_Flows.csv']);
    [scada.flows, scada.flow_names] = read_scada_csv(fname, false);
    
    % Levels (meters)
    fname = fullfile(data_dir, [year_str '_SCADA_Levels.csv']);
    [scada.levels, scada.level_names] = read_scada_csv(fname, false);
    
    % Demands / AMR (L/h)
    fname = fullfile(data_dir, [year_str '_SCADA_Demands.csv']);
    [scada.demands_Lh, scada.demand_names] = read_scada_csv(fname, false);
    scada.demands_m3h = scada.demands_Lh / 1000;   % L/h → m³/h
    
    elapsed = toc;
    
    fprintf('✅ SCADA yüklendi (%.1f saniye)\n', elapsed);
    fprintf('   Zaman aralığı: %s → %s\n', ...
            string(scada.time(1)), string(scada.time(end)));
    fprintf('   Örnek sayısı:  %d (her sensör için)\n', length(scada.time));
    fprintf('   Basınç sensörü: %d kolon\n', size(scada.pressures,2));
    fprintf('   Akış sensörü:   %d kolon\n', size(scada.flows,2));
    fprintf('   Seviye sensörü: %d kolon\n', size(scada.levels,2));
    fprintf('   AMR sayısı:     %d kolon\n', size(scada.demands_m3h,2));
    fprintf('   Toplam NaN:     P=%d, F=%d, L=%d, D=%d\n', ...
        sum(isnan(scada.pressures(:))), sum(isnan(scada.flows(:))), ...
        sum(isnan(scada.levels(:))),    sum(isnan(scada.demands_Lh(:))));
end


function [data_matrix, col_names, time_vec] = read_scada_csv(fname, return_time)
% Robust CSV okuyucu — BattLeDIM Avrupa formatı için
% Delimiter: ;   Decimal: ,

    % Import options ile doğru formatı belirt
    opts = detectImportOptions(fname, ...
        'Delimiter', ';', ...
        'DecimalSeparator', ',', ...
        'VariableNamingRule', 'preserve');
    
    % Zaman kolonunu datetime olarak, geri kalanını double olarak zorla
    var_names = opts.VariableNames;
    opts = setvartype(opts, var_names{1}, 'datetime');
    opts = setvaropts(opts, var_names{1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    for k = 2:length(var_names)
        opts = setvartype(opts, var_names{k}, 'double');
    end
    
    T = readtable(fname, opts);
    
    col_names = T.Properties.VariableNames(2:end);
    data_matrix = T{:, 2:end};
    
    if return_time
        time_vec = T{:, 1};
    else
        time_vec = [];
    end
end