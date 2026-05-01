function [leak_node_id, confidence] = leak_localizer(residual, S_norm, junction_ids)
%#codegen
    % Residual vektörünü normalize et
    r_norm = residual / (norm(residual) + 1e-9);
    
    % Sensitivity matrix'in her sütunuyla korelasyon
    corr_vec = abs(S_norm' * r_norm);
    
    % En yüksek korelasyonlu düğüm
    [confidence, idx] = max(corr_vec);
    leak_node_id = junction_ids{idx};
end