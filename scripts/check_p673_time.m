%% check_p673_time.m — p673 sızıntı zamanını config'den çek
clc; clear;
project_root = 'D:\DATA\Neu_Bm_3\Bahar_Donemi\Donem_Projesi\Donem_projesi_2\HydroTwin_LTown';
cd(project_root);
addpath(genpath('scripts/helpers'));

cfg = load_config();

% Tüm sızıntı yapısını ekrana dök
disp('Cfg.leaks içerik (ilk 5):');
if isstruct(cfg.leaks)
    disp(cfg.leaks(1:min(5,end)));
elseif iscell(cfg.leaks)
    for i = 1:min(5, length(cfg.leaks))
        disp(cfg.leaks{i});
    end
end

% p673'ü ara
fprintf('\n🔎 p673 araması:\n');
if isstruct(cfg.leaks)
    for i = 1:length(cfg.leaks)
        f = fieldnames(cfg.leaks(i));
        for j = 1:length(f)
            v = cfg.leaks(i).(f{j});
            if (ischar(v) || isstring(v)) && contains(string(v), 'p673', 'IgnoreCase',true)
                fprintf('  Leak %d:\n', i); disp(cfg.leaks(i)); break;
            end
            if (ischar(v) || isstring(v)) && contains(string(v), '673', 'IgnoreCase',true)
                fprintf('  Leak %d (sadece 673 içeren):\n', i); disp(cfg.leaks(i)); break;
            end
        end
    end
end