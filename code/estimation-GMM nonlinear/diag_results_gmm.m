% Ver resultados de todos os starts do setor 4
diag = results.gmm_acf.diagnostics{4};

% Tabela resumo de todos os starts
for s = 1:length(diag.all_results)
    r = diag.all_results{s};
    if ~isempty(r)
        fprintf('Start %2d | Q=%.6e | flag=%d | β=[%.4f, %.4f, %.4f, %.4f, %.4f]\n', ...
            s, r.fval, r.exitflag, r.beta(1), r.beta(2), r.beta(3), r.beta(4), r.beta(5));
    end
end

% Ver também o beta final e norm_g
fprintf('\nÓtimo final: β=[%.4f, %.4f, %.4f, %.4f, %.4f]\n', ...
    diag.g_at_optimum');
fprintf('norm_g = %.6e | fval = %.6e\n', diag.norm_g, diag.fval);

