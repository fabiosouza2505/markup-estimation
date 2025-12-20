function safe_push(mensagem)
    %SAFE_PUSH Push seguro que sempre sincroniza primeiro
    %
    % Uso:
    %   safe_push('feat: nova funcionalidade')
    
    % 1. Pull primeiro
    fprintf('1. Sincronizando com GitHub...\n');
    [status, output] = system('git pull origin main');
    
    if status ~= 0
        error('Erro no pull: %s', output);
    end
    
    if contains(output, 'Already up to date')
        fprintf('   ✓ Já estava atualizado\n');
    else
        fprintf('   ✓ Mudanças baixadas do GitHub\n');
    end
    
    % 2. Add e commit
    fprintf('\n2. Commitando mudanças locais...\n');
    system('git add .');
    
    cmd = sprintf('git commit -m "%s"', mensagem);
    [status, output] = system(cmd);
    
    if contains(output, 'nothing to commit')
        fprintf('   ℹ Nenhuma mudança para commitar\n');
    elseif status == 0
        fprintf('   ✓ Commit realizado\n');
    else
        fprintf('   ⚠ Aviso: %s\n', output);
    end
    
    % 3. Pull novamente (por segurança)
    fprintf('\n3. Verificando novamente...\n');
    [~, output] = system('git pull origin main');
    
    if contains(output, 'Already up to date')
        fprintf('   ✓ Tudo sincronizado\n');
    else
        fprintf('   ⚠ Novas mudanças baixadas!\n');
    end
    
    % 4. Push
    fprintf('\n4. Enviando para GitHub...\n');
    [status, output] = system('git push origin main');
    
    if status ~= 0
        error('Erro no push: %s\nTente novamente ou resolva conflitos', output);
    end
    
    fprintf('   ✓ Push realizado com sucesso!\n');
    
    fprintf('\n========================================\n');
    fprintf('✅ SINCRONIZAÇÃO COMPLETA!\n');
    fprintf('========================================\n');
end