% scripts/helpers/ altına kaydet: cache_scada.m
function scada = cache_scada(year_str)
    cache_file = fullfile('data', sprintf('scada_%s.mat', year_str));
    
    if exist(cache_file, 'file')
        fprintf('⚡ Cache''den yükleniyor: %s\n', cache_file);
        tic;
        S = load(cache_file);
        scada = S.scada;
        fprintf('✅ Cache yükleme: %.2f saniye\n', toc);
    else
        fprintf('📥 İlk yükleme (cache oluşturulacak)...\n');
        scada = load_scada(year_str);
        
        % Flow NaN'lerini temizle (PUMP_1 = pompa duruşları)
        for j = 1:length(scada.flow_names)
            nan_mask = isnan(scada.flows(:,j));
            if any(nan_mask)
                scada.flows(nan_mask, j) = 0;
                fprintf('   %s: %d NaN → 0\n', scada.flow_names{j}, sum(nan_mask));
            end
        end
        
        fprintf('💾 Cache kaydediliyor...\n');
        save(cache_file, 'scada', '-v7.3');
        fprintf('✅ Cache hazır: %s\n', cache_file);
    end
end