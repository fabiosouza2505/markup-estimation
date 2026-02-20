for sec = 1:8
    diag = results.gmm_acf.diagnostics{sec};
    fprintf('\n=== SETOR %d (%s) ===\n', sec, results.gmm_acf.setores{sec});
    fprintf('μ=%.3f | R²=%.3f | fval=%.6e | norm_g=%.4f\n', ...
        results.gmm_acf.markup_stats{sec}.mean, diag.rsquared, diag.fval, diag.norm_g);
    fprintf('β₁(W=I) = [%.4f, %.4f, %.4f, %.4f, %.4f]\n', diag.beta_step1);
    fprintf('β₂(Ŵ)   = [%.4f, %.4f, %.4f, %.4f, %.4f]\n', ...
        diag.beta_opt_bounded(1), diag.beta_opt_bounded(2), ...
        diag.beta_opt_bounded(3), diag.beta_opt_bounded(4), diag.beta_opt_bounded(5));
    if isfield(diag, 'J_stat') && ~isnan(diag.J_stat)
        fprintf('J-Hansen = %.3f (p=%.4f, df=%d)\n', diag.J_stat, diag.J_pval, diag.J_df);
    end
    % Bounds check
    labels = {'β_v','β_k','β_vv','β_kk','β_vk'};
    beta = diag.beta_opt_bounded;
    lb = diag.bounds.lb; ub = diag.bounds.ub;
    for j = 1:5
        if beta(j) <= lb(j) + 0.01 || beta(j) >= ub(j) - 0.01
            fprintf('  ⚠ %s=%.4f no bound [%.2f, %.2f]\n', labels{j}, beta(j), lb(j), ub(j));
        end
    end
end