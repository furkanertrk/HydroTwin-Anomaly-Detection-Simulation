function alarm = Leak_Detector(residual)
%#codegen
% Adaptif threshold + persistence: q95×1.3 üstünde 12 sample (1h) → alarm
% Latching: bir kere yandı mı söndürmez

persistent threshold K counter state t_idx N_calib init

if isempty(init)
    data      = coder.load('digital_twin_data.mat');
    threshold = data.threshold_adaptive;
    K         = int32(12);
    counter   = int32(0);
    state     = false;
    t_idx     = int32(0);
    N_calib   = int32(288);
    init      = true;
end

t_idx = t_idx + 1;

if t_idx <= N_calib
    alarm = 0;
    return;
end

if norm(residual) > threshold
    counter = counter + 1;
    if counter >= K
        state = true;
    end
else
    counter = int32(0);
end

alarm = double(state);
end