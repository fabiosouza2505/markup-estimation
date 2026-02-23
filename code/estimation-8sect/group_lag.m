function lagged = group_lag(values, group_ids, n_lag)
    %GROUP_LAG Calcula lag respeitando fronteiras entre grupos
    %
    %   lagged = group_lag(values, group_ids, n_lag)
    %
    %   Para cada grupo (empresa), aplica lag de n_lag períodos.
    %   Observações que cruzariam fronteiras recebem NaN.
    
    lagged = NaN(size(values));
    unique_groups = unique(group_ids);
    
    for g = 1:length(unique_groups)
        idx = find(group_ids == unique_groups(g));
        
        if length(idx) > n_lag
            lagged(idx(n_lag+1:end)) = values(idx(1:end-n_lag));
        end
        % Observações com lag insuficiente permanecem NaN
    end
end