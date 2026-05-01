function [P_pred, Q_pred] = digital_twin_step(demand_vec, t_idx)
%#codegen - Simulink MATLAB Function bloğu için

    persistent d initialized;
    if isempty(initialized)
        d = epanet('data/L-Town.inp');
        d.openHydraulicAnalysis;
        d.initializeHydraulicAnalysis;
        initialized = true;
    end
    
    % Gerçek ölçülen talepleri modele enjekte et
    d.setNodeBaseDemands(demand_vec);
    
    % Tek adım hidrolik çözüm
    t_hyd = d.runHydraulicAnalysis;
    P_pred = d.getNodePressure;
    Q_pred = d.getLinkFlows;
    
    % Sonraki adım için ilerle
    d.nextHydraulicAnalysisStep;
end