function P_predicted = Digital_Twin(P_measured)
%#codegen
% Plan C: model-driven nominal + online bias correction (ilk 24h)

persistent P_nom bias t_idx N_calib init

if isempty(init)
    data    = coder.load('digital_twin_data.mat');
    P_nom   = data.P_nominal_demo;
    bias    = zeros(33, 1);
    t_idx   = int32(0);
    N_calib = int32(288);
    init    = true;
end

t_idx = t_idx + 1;

ti = t_idx;
if ti > int32(size(P_nom, 1))
    ti = int32(size(P_nom, 1));
end

P_nom_now = P_nom(ti, :)';

if t_idx <= N_calib
    alpha = 1.0 / double(t_idx);
    bias  = bias * (1 - alpha) + (P_measured - P_nom_now) * alpha;
end

P_predicted = P_nom_now + bias;
end