function numeric_array = str2double_br(cell_array)
    %STR2DOUBLE_BR Converte cell array com formato brasileiro para double
    %
    % Formato brasileiro usa:
    %   - Vírgula como separador decimal (,)
    %   - Ponto como separador de milhares (.)
    %
    % Exemplo:
    %   "1.234.567,89" → 1234567.89
    %
    % SINTAXE:
    %   numeric_array = str2double_br(cell_array)
    %
    % INPUT:
    %   cell_array - Cell array de strings
    %
    % OUTPUT:
    %   numeric_array - Array numérico (double)
    
    % Inicializar array de saída
    n = length(cell_array);
    numeric_array = zeros(n, 1);
    
    % Processar cada elemento
    for i = 1:n
        elem = cell_array{i};
        
        % Se já for numérico, manter
        if isnumeric(elem)
            numeric_array(i) = elem;
            continue;
        end
        
        % Se for char/string, converter
        if ischar(elem) || isstring(elem)
            % Converter para char se for string
            if isstring(elem)
                elem = char(elem);
            end
            
            % Remover espaços em branco
            elem = strtrim(elem);
            
            % Se vazio, marcar como NaN
            if isempty(elem)
                numeric_array(i) = NaN;
                continue;
            end
            
            % Converter formato brasileiro para formato MATLAB
            % 1. Remover pontos (separador de milhares)
            elem = strrep(elem, '.', '');
            
            % 2. Substituir vírgula por ponto (decimal)
            elem = strrep(elem, ',', '.');
            
            % 3. Converter para número
            num = str2double(elem);
            
            % Armazenar (será NaN se conversão falhar)
            numeric_array(i) = num;
        else
            % Tipo não suportado
            numeric_array(i) = NaN;
        end
    end
    
end