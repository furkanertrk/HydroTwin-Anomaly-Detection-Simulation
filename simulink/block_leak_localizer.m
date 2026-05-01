function leak_node_idx = Leak_Localizer(residual)
%#codegen
% Mantık:
%   1) İlk 288 sample (24h) kalibrasyon → 0
%   2) Adaptif threshold + 12 sample persistence → alarm tetiklendi
%   3) Alarm sonrası 288 sample (24h) bekle
%   4) Son 288 sample'ın ortalamasıyla LOCALIZE et + DONDUR

persistent S_norm last_idx threshold buffer t_idx N_calib N_window K counter alarm_t init

if isempty(init)
    data      = coder.load('digital_twin_data.mat');
    S_norm    = data.S_norm;
    threshold = data.threshold_adaptive;
    last_idx  = 0;
    N_window  = int32(288);
    buffer    = zeros(33, 288);
    t_idx     = int32(0);
    N_calib   = int32(288);
    K         = int32(12);
    counter   = int32(0);
    alarm_t   = int32(-1);
    init      = true;
end

t_idx = t_idx + 1;

buffer(:, 1:end-1) = buffer(:, 2:end);
buffer(:, end)     = residual;

if t_idx <= N_calib
    leak_node_idx = 0;
    return;
end

if alarm_t < 0
    if norm(residual) > threshold
        counter = counter + 1;
        if counter >= K
            alarm_t = t_idx;
        end
    else
        counter = int32(0);
    end
    leak_node_idx = 0;
    return;
end

if last_idx == 0 && (t_idx - alarm_t) >= N_window
    r_avg = mean(buffer, 2);
    r     = r_avg / (norm(r_avg) + 1e-9);
    corr  = S_norm' * r;
    [~, idx] = max(corr);
    last_idx = double(idx);
end

leak_node_idx = last_idx;
end