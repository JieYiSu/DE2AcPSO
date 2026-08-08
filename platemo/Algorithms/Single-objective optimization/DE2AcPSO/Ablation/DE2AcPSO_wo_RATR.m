classdef DE2AcPSO_wo_RATR < ALGORITHM
% <single> <real> <expensive>
% DE2AcPSO_wo_RATR: DE2AcPSO without Rank-1 Anisotropic Trust-Region Quadratic Surrogate

    methods
        function main(Algorithm, Problem)
            %% Parameter Initialization
            DB_MaxFE = Problem.maxFE;
            DB_D = Problem.D;
            DB_X = zeros(DB_MaxFE, DB_D);
            DB_Y = inf(DB_MaxFE, 1);
            
            if DB_D < 100; N_init = 100; else; N_init = 150; end
            
            P = lhsdesign(N_init, DB_D);
            PopDec = repmat(Problem.lower, N_init, 1) + P .* repmat(Problem.upper - Problem.lower, N_init, 1);
            Archive = Problem.Evaluation(PopDec);
            
            DB_X(1:N_init, :) = Archive.decs;
            DB_Y(1:N_init) = Archive.objs;
            DB_Count = N_init;
            
            K_dist = 3; 
            mu = zeros(K_dist, DB_D);
            sigma_vec = zeros(K_dist, DB_D); 
            
            %% Main Optimization Loop
            while Algorithm.NotTerminated(Archive)
                X_all = DB_X(1:DB_Count, :);
                Y_all = DB_Y(1:DB_Count);
                [~, sort_idx] = sort(Y_all);
                DB_BestX = X_all(sort_idx(1), :); 
                
                iter = DB_Count - N_init;
                FE_ratio = DB_Count / DB_MaxFE; 
                domain_span = Problem.upper - Problem.lower;
                min_sigma = max(1e-250, domain_span .* (1e-3 * (1 - FE_ratio)^3)); 
                
                if mod(iter, 2) == 0
                    % ---------------- 消融点 1：彻底移除 RATR 代理模型求解，退化为普通局部随机搜索 ----------------
                    shrink_factor = 1e-2 * (1 - FE_ratio)^2;
                    x_infill = DB_BestX + randn(1, DB_D) .* domain_span .* shrink_factor;
                    % -----------------------------------------------------------------------------------------
                    
                else
                    %% Engine 2: Principal-Direction Injected cPSO with Global RBF
                    Global_RBF = Fit_RBF_Full_Stable(X_all, Y_all);
                    
                    if DB_Count > 1; best2_x = X_all(sort_idx(2), :); else; best2_x = DB_BestX; end
                    
                    mu(1, :) = DB_BestX;
                    sigma_vec(1, :) = max(abs(DB_BestX - best2_x), min_sigma); 
                    
                    top_K = max(2, round(0.5 * DB_Count));
                    mu(2, :) = mean(X_all(sort_idx(1:top_K), :), 1);
                    sigma_vec(2, :) = max(abs(DB_BestX - mu(2, :)), min_sigma);
                    
                    pop_std_all = std(X_all, 1, 1);
                    rand_idx1 = randi(DB_Count);
                    rand_idx2 = randi(DB_Count);
                    diff_momentum = abs(X_all(rand_idx1, :) - X_all(rand_idx2, :));
                    mu(3, :) = DB_BestX; 
                    sigma_vec(3, :) = max([pop_std_all; diff_momentum; min_sigma], [], 1); 
                    
                    Elite_Dir = DB_BestX - mu(2, :);
                    norm_Dir = norm(Elite_Dir) + 1e-200;
                    Elite_Dir = Elite_Dir / norm_Dir; 
                    
                    N_cands = min(2000, 20 * DB_D);
                    Cands_Pool = zeros(N_cands, DB_D);
                    chunk = floor(N_cands / K_dist);
                    
                    for k = 1:K_dist
                        start_idx = (k-1)*chunk + 1;
                        if k == K_dist; end_idx = N_cands; else; end_idx = k*chunk; end
                        num_c = end_idx - start_idx + 1;
                        
                        base_step = zeros(num_c, DB_D);
                        is_gauss = rand(num_c, 1) < 0.5; 
                        
                        num_gauss = sum(is_gauss);
                        if num_gauss > 0
                            base_step(is_gauss, :) = randn(num_gauss, DB_D) .* sigma_vec(k, :);
                        end
                        if (num_c - num_gauss) > 0
                            base_step(~is_gauss, :) = tan(pi*(rand(num_c - num_gauss, DB_D)-0.5)) .* sigma_vec(k, :);
                        end
                        
                        inject_step = zeros(num_c, DB_D);
                        is_inject = rand(num_c, 1) < 0.2; 
                        num_inject = sum(is_inject);
                        if num_inject > 0
                            inject_step(is_inject, :) = randn(num_inject, 1) .* norm(sigma_vec(k, :)) .* Elite_Dir;
                        end
                        
                        Cands_Pool(start_idx:end_idx, :) = repmat(mu(k, :), num_c, 1) + base_step + inject_step;
                    end
                    
                    Cands_Pool = Boundary_Reflection(Cands_Pool, Problem.lower, Problem.upper);
                    
                    V_Y = Predict_RBF_Full_Stable(Global_RBF, Cands_Pool);
                    
                    X_norm_cands = (Cands_Pool - Global_RBF.X_min) ./ Global_RBF.span;
                    dist_to_eval = pdist2(X_norm_cands, Global_RBF.X_norm_db(sort_idx(1:min(50, DB_Count)), :));
                    min_dist = min(dist_to_eval, [], 2);
                    
                    V_Y_norm = (V_Y - min(V_Y)) ./ (max(V_Y) - min(V_Y) + 1e-200);
                    Dist_norm = (min_dist - min(min_dist)) ./ (max(min_dist) - min(min_dist) + 1e-200);
                    
                    explore_weight = max(0.05, 0.5 * (1 - FE_ratio)^2); 
                    Acquisition_Func = V_Y_norm - explore_weight .* Dist_norm;
                    
                    [~, best_cand_idx] = min(Acquisition_Func);
                    x_infill = Cands_Pool(best_cand_idx, :);
                end
                
                x_infill = Boundary_Reflection(x_infill, Problem.lower, Problem.upper);
                
                pop_spread = max(std(X_all, 1, 1)); 
                min_dist_limit = max(1e-250, 1e-8 * pop_spread);
                
                if min(sqrt(sum((X_all - x_infill).^2, 2))) < min_dist_limit
                    x_infill = DB_BestX + randn(1, DB_D) .* ((Problem.upper - Problem.lower) * 1e-4);
                    x_infill = Boundary_Reflection(x_infill, Problem.lower, Problem.upper);
                end
                
                NewSol = Problem.Evaluation(x_infill);
                Archive = [Archive, NewSol];
                
                DB_Count = DB_Count + 1;
                DB_X(DB_Count, :) = NewSol.dec;
                DB_Y(DB_Count) = NewSol.obj;
            end
        end
    end
end

function X = Boundary_Reflection(X, lb, ub)
    if size(lb, 1) == 1; lb = repmat(lb, size(X, 1), 1); end
    if size(ub, 1) == 1; ub = repmat(ub, size(X, 1), 1); end
    out_upper = X > ub;
    if any(out_upper(:))
        X(out_upper) = ub(out_upper) - rand(size(X(out_upper))) .* mod(X(out_upper) - ub(out_upper), ub(out_upper) - lb(out_upper));
    end
    out_lower = X < lb;
    if any(out_lower(:))
        X(out_lower) = lb(out_lower) + rand(size(X(out_lower))) .* mod(lb(out_lower) - X(out_lower), ub(out_lower) - lb(out_lower));
    end
    X = max(min(X, ub), lb); 
end

function model = Fit_RBF_Full_Stable(X, Y)
    N = size(X, 1); D = size(X, 2);
    X_min = min(X, [], 1);
    X_max = max(X, [], 1);
    span = max(X_max - X_min, 1e-200); 
    X_norm = (X - X_min) ./ span;
    Y_min = min(Y); dY = max(Y) - Y_min;
    if dY < 1e-200; dY = 1e-200; end
    Y_norm = (Y - Y_min) / dY;
    dist_mat = pdist2(X_norm, X_norm) / sqrt(D);
    Phi = dist_mat.^3; 
    P = [X_norm, ones(N, 1)];
    A = [Phi, P; P', zeros(D+1, D+1)];
    b = [Y_norm; zeros(D+1, 1)];
    reg_base = 1e-6;
    reg_dynamic = max(reg_base, 10^(-8 + (N/1000))); 
    reg_matrix = diag([repmat(reg_dynamic, N, 1); repmat(reg_base, D+1, 1)]);
    A = A + reg_matrix;
    if rcond(A) < 1e-12
        sol = pinv(A) * b;
    else
        sol = A \ b;
    end
    model.weights = sol(1:N);
    model.tail = sol(N+1:end);
    model.X_min = X_min;
    model.span = span;
    model.Y_min = Y_min;
    model.dY = dY;
    model.D = D;
    model.X_norm_db = X_norm;
end

function Y_pred = Predict_RBF_Full_Stable(model, X_test)
    X_norm_test = (X_test - model.X_min) ./ model.span;
    dist_mat = pdist2(X_norm_test, model.X_norm_db) / sqrt(model.D);
    Phi_test = dist_mat.^3;
    P_test = [X_norm_test, ones(size(X_test, 1), 1)];
    V_Y_norm = Phi_test * model.weights + P_test * model.tail;
    Y_pred = V_Y_norm * model.dY + model.Y_min;
end