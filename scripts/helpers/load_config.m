function cfg = load_config(yaml_path)
% load_config  BattLeDIM dataset_configuration.yaml dosyasını okur
%   cfg = load_config('data/dataset_configuration.yaml')
%
% Döner: cfg.leakages (table), cfg.pressure_sensors, cfg.flow_sensors,
%        cfg.level_sensors, cfg.amrs

    if nargin < 1
        yaml_path = fullfile('data', 'dataset_configuration.yaml');
    end
    
    txt = fileread(yaml_path);
    lines = strsplit(txt, newline);
    
    cfg = struct();
    cfg.leakages = table();
    cfg.pressure_sensors = {};
    cfg.flow_sensors = {};
    cfg.level_sensors = {};
    cfg.amrs = {};
    
    section = '';
    leak_rows = {};
    
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if isempty(line) || startsWith(line, '#') || startsWith(line, 'Comments')
            continue;
        end
        
        % Section başlıklarını yakala
        if endsWith(line, ':') && ~startsWith(line, '-')
            section = erase(line, ':');
            continue;
        end
        
        % Section içeriklerini işle
        if startsWith(line, '- ')
            val = strtrim(extractAfter(line, '- '));
            if startsWith(val, '#'), continue; end
            
            switch section
                case 'leakages'
                    % p257, 2018-01-08 13:30, 2019-12-31 23:55, 0.011843, incipient, 2018-01-25 08:30
                    parts = strtrim(strsplit(val, ','));
                    if length(parts) == 6
                        leak_rows(end+1, :) = { ...
                            parts{1}, ...
                            datetime(parts{2}, 'InputFormat','yyyy-MM-dd HH:mm'), ...
                            datetime(parts{3}, 'InputFormat','yyyy-MM-dd HH:mm'), ...
                            str2double(parts{4}), ...
                            parts{5}, ...
                            datetime(parts{6}, 'InputFormat','yyyy-MM-dd HH:mm')};
                    end
                case 'pressure_sensors'
                    cfg.pressure_sensors{end+1} = val;
                case 'flow_sensors'
                    cfg.flow_sensors{end+1} = val;
                case 'level_sensors'
                    cfg.level_sensors{end+1} = val;
                case 'amrs'
                    cfg.amrs{end+1} = val;
            end
        end
    end
    
    % Leakages'ı table'a çevir
    if ~isempty(leak_rows)
        cfg.leakages = cell2table(leak_rows, 'VariableNames', ...
            {'linkID','startTime','endTime','diameter_m','leakType','peakTime'});
    end
    
    fprintf('✅ Config yüklendi:\n');
    fprintf('   Sızıntı sayısı:      %d\n', height(cfg.leakages));
    fprintf('   Basınç sensörü:      %d\n', length(cfg.pressure_sensors));
    fprintf('   Akış sensörü:        %d\n', length(cfg.flow_sensors));
    fprintf('   Seviye sensörü:      %d\n', length(cfg.level_sensors));
    fprintf('   AMR sayısı:          %d\n', length(cfg.amrs));
end