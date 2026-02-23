function lag_map = build_lag_map(data)
%BUILD_LAG_MAP Constrói mapa (empresa,ano,tri) → índice para lag O(N)
%
% Em vez de buscar com máscara O(N) para cada observação (total O(N²)),
% esta função pré-constrói um HashMap que permite lookup O(1).
%
% USO:
%   lag_map = build_lag_map(data);
%   key = sprintf('%d_%d_%d', emp_id, ano_ant, tri_ant);
%   if lag_map.isKey(key)
%       idx_lag = lag_map(key);
%   end
%
% INPUT:
%   data - Tabela com colunas: empresa, ano, (trimestre opcional)
%
% OUTPUT:
%   lag_map - containers.Map: chave = 'empID_ano_tri' → valor = índice na tabela
%             Em caso de duplicatas, armazena a PRIMEIRA ocorrência.
%
% NOTA: Se houver duplicatas (empresa,ano,tri), a primeira ocorrência é
%       preservada — consistente com o comportamento anterior de find(...,'first').
%
% Autor: Fabio de Medeiros Souza
% Data: Fevereiro 2025

n_obs = height(data);

% Normalizar empresa para numérico
empresa_ids = normalize_empresa_ids(data.empresa);

% Extrair trimestres
if ismember('trimestre', data.Properties.VariableNames)
    trimestres = data.trimestre;
else
    trimestres = zeros(n_obs, 1);
end

anos = data.ano;

% Pré-alocar mapa com capacidade estimada
lag_map = containers.Map('KeyType', 'char', 'ValueType', 'int32');

for idx = 1:n_obs
    key = sprintf('%d_%d_%d', empresa_ids(idx), anos(idx), trimestres(idx));
    % Apenas primeira ocorrência (protege contra duplicatas)
    if ~lag_map.isKey(key)
        lag_map(key) = int32(idx);
    end
end

end


% =========================================================================
% FUNÇÃO AUXILIAR: Normaliza identificador de firma para vetor numérico
% =========================================================================
function ids_num = normalize_empresa_ids(empresa)

    if isnumeric(empresa)
        ids_num = double(empresa);
    elseif iscell(empresa)
        [~, ~, ids_num] = unique(empresa);
        ids_num = double(ids_num);
    elseif isstring(empresa) || ischar(empresa)
        [~, ~, ids_num] = unique(empresa);
        ids_num = double(ids_num);
    elseif iscategorical(empresa)
        ids_num = double(empresa);
    else
        try
            ids_num = double(empresa);
        catch
            error('normalize_empresa_ids: tipo não suportado: %s', class(empresa));
        end
    end
end
