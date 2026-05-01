function d = load_ltown(inp_filename)
% load_ltown  L-TOWN (veya başka) .inp dosyasını güvenli şekilde açar
%   d = load_ltown()                    → 'L-TOWN.inp' açar
%   d = load_ltown('L-TOWN_Real.inp')   → belirtilen dosyayı açar
%
% Proje kök klasöründen çalıştırılmalı (HydroTwin_LTown/).

    if nargin < 1
        inp_filename = 'L-TOWN.inp';
    end
    
    project_root = pwd;
    data_dir = fullfile(project_root, 'data');
    
    if ~exist(fullfile(data_dir, inp_filename), 'file')
        error('Dosya bulunamadı: %s', fullfile(data_dir, inp_filename));
    end
    
    % Toolkit'in path quirk'ünü bypass et
    cd(data_dir);
    try
        d = epanet(inp_filename);
        cd(project_root);   % Başarılı → eski klasöre dön
    catch ME
        cd(project_root);   % Hata olsa bile eski klasöre dön
        rethrow(ME);
    end
end