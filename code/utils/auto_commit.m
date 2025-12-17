function auto_commit(mensagem, arquivos)
    %AUTO_COMMIT Faz commit automaticamente
    %
    % Uso:
    %   auto_commit('feat: atualiza resultados', 'results/')
    %   auto_commit('docs: atualiza artigo', 'paper/')
    %   auto_commit('auto: resultados da estimação')  % Adiciona tudo
    
    if nargin < 2
        arquivos = '.';  % Adiciona tudo por padrão
    end
    
    if nargin < 1
        mensagem = sprintf('auto: commit automático %s', datestr(now, 'yyyy-mm-dd HH:MM'));
    end
    
    fprintf('========================================\n');
    fprintf('AUTO-COMMIT\n');
    fprintf('========================================\n\n');
    
    % Adicionar arquivos
    fprintf('Adicionando arquivos: %s\n', arquivos);
    cmd_add = sprintf('git add %s', arquivos);
    [status, output] = system(cmd_add);
    
    if status ~= 0
        error('Erro ao adicionar arquivos: %s', output);
    end
    
    % Verificar se há mudanças para commitar
    [~, status_output] = system('git status --porcelain');
    
    if isempty(strtrim(status_output))
        fprintf('⚠️  Nenhuma mudança para commitar.\n');
        return;
    end
    
    % Fazer commit
    fprintf('Commitando com mensagem: "%s"\n', mensagem);
    cmd_commit = sprintf('git commit -m "%s"', mensagem);
    [status, output] = system(cmd_commit);
    
    if status ~= 0
        error('Erro ao fazer commit: %s', output);
    end
    
    fprintf('✓ Commit realizado\n');
    
    % Fazer push (opcional)
    resposta = input('Fazer push para GitHub? (s/n): ', 's');
    if strcmpi(resposta, 's')
        fprintf('Fazendo push...\n');
        [status, output] = system('git push origin main');
        
        if status ~= 0
            warning('Erro ao fazer push: %s', output);
        else
            fprintf('✓ Push realizado\n');
        end
    end
    
    fprintf('\n✅ Processo concluído!\n');
end