function X_poly = build_polynomial_features(X, degree)
    %BUILD_POLYNOMIAL_FEATURES Gera termos polinomiais até grau especificado
    %   Análogo ao PolynomialFeatures do sklearn com include_bias=True
    
    [n, p] = size(X);
    
    % Começar com bias (constante)
    X_poly = ones(n, 1);
    
    % Grau 1: termos lineares
    X_poly = [X_poly, X];
    
    % Grau 2: todos os pares (incluindo quadrados)
    if degree >= 2
        for i = 1:p
            for j = i:p
                X_poly = [X_poly, X(:,i) .* X(:,j)];
            end
        end
    end
    
    % Grau 3: todas as triplas (incluindo cubos)
    if degree >= 3
        for i = 1:p
            for j = i:p
                for k = j:p
                    X_poly = [X_poly, X(:,i) .* X(:,j) .* X(:,k)];
                end
            end
        end
    end
end