classdef DE2AcPSO_wo_ACDP < ALGORITHM
% <single> <real> <expensive>
% DE2AcPSO_wo_ACDP: DE2AcPSO without Adaptive Constraint-Aware Diversity Preservation
% (Removes stagnation prevention re-kicks and replaces adaptive reflection with standard clamping)

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
                    %% Engine 1: Rank-1 Anisotropic Trust-Region Quadratic Model
                    K_local = min(DB_Count, DB_D + 6); 
                    Local_X = X_all(sort_idx(1:K_local), :);
                    Local_Y = Y_all(sort_idx(1:K_local));
                    
                    R_local = max(sqrt(sum((Local_X - DB_BestX).^2, 2)));
                    if R_local < 1e-250; R_local = 1e-250; end
                    
                    Z_local = (Local_X - DB_BestX) / R_local;
                    
                    if K_local > 1
                        v_dom = Z_local(2, :) - Z_local(1, :);
                    else
                        v_dom = randn(1, DB_D);
                    end
                    v_norm = norm(v_dom) + 1e-250;
                    v_dom = v_dom / v_norm; 
                    
                    Proj_Z = (Z_local * v_dom').^2; 
                    
                    Y_min = min(Local_Y); dY = max(Local_Y) - Y_min; 
                    if dY < 1e-250; dY = 1e-250; end
                    Y_norm = (Local_Y - Y_min) / dY;
                    
                    P_iso = [ones(K_local, 1), sum(Z_local.^2, 2), Proj_Z, Z_local];
                    
                    P_norms = sqrt(sum(P_iso.^2, 1));
                    P_norms(P_norms < 1e-200) = 1; 
                    P_scaled = P_iso ./ P_norms;
                    
                    K_P = size(P_scaled, 1);
                    reg_lambda = 1e-6; 
                    dual_coef = (P_scaled * P_scaled' + reg_lambda * eye(K_P)) \ Y_norm;
                    coef_scaled = P_scaled' * dual_coef;
                    
                    coef = coef_scaled ./ P_norms';
                    
                    Y_pred = P_iso * coef;
                    SS_res = sum((Y_norm - Y_pred).^2);
                    SS_tot = sum((Y_norm - mean(Y_norm)).^2);
                    R2 = 1 - (SS_res / (SS_tot + 1e-250));
                    
                    if R2 < 0.1 
                        rand_action = rand();
                        if rand_action < 0.33
                            mask = rand(1, DB_D) < 0.2; 
                            x_infill = DB_BestX;
                            x_infill(mask) = Problem.lower(mask) + Problem.upper(mask) - DB_BestX(mask);
                        elseif rand_action < 0.66
                            beta = 1.5;
                            sigma_u = (gamma(1+beta)*sin(pi*beta/2)/(gamma((1+beta)/2)*beta*2^((beta-1)/2)))^(1/beta);
                            u = randn(1, DB_D) * sigma_u;
                            v = randn(1, DB_D);
                            step = u ./ abs(v).^(1/beta);
                            scale_factor = 1e-3 * (1 - FE_ratio);
                            x_infill = DB_BestX + step .* domain_span .* scale_factor;
                        else
                            shrink_factor = 1e-2 * (1 - FE_ratio)^2;
                            x_infill = DB_BestX + randn(1, DB_D) .* domain_span .* shrink_factor;
                        end
                    else
                        trust_ratio = max(1e-6, min(2.5, R2 * 2.5)); 
                        
                        a_iso = max(coef(2), 1e-12);   
                        a_dir = coef(3);               
                        b_grad = coef(4:end);          
                        
                        c1 = 2 * a_iso;
                        c2 = 2 * a_dir;
                        v_dot_g = v_dom * b_grad; 
                        
                        denominator = c1 + c2;
                        if abs(denominator) < 1e-12
                            denominator = sign(denominator + 1e-200) * 1e-12; 
                        end
                        
                        step_Z_norm = -(1/c1) * b_grad + (c2 * v_dot_g / (c1 * denominator)) * v_dom';
                        step_Z_norm = step_Z_norm'; 
                        
                        if norm(step_Z_norm) > trust_ratio
                            step_Z_norm = step_Z_norm * (trust_ratio / norm(step_Z_norm));
                        end
                        x_infill = DB_BestX + step_Z_norm * R_local;
                    end
                    
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
                    
                    % ---------------- 消融点 3：不使用自适应软反射，使用硬截断边界约束 ----------------
                    Cands_Pool = min(max(Cands_Pool, Problem.lower), Problem.upper);
                    % --------------------------------------------------------------------------------
                    
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
                
                % ---------------- 消融点 3：移除停滞预防/多样性保活机制（不剔除极度靠近的重复点） ----------------
                x_infill = min(max(x_infill, Problem.lower), Problem.upper);
                % -----------------------------------------------------------------------------------------
                
                NewSol = Problem.Evaluation(x_infill);
                Archive = [Archive, NewSol];
                
                DB_Count = DB_Count + 1;
                DB_X(DB_Count, :) = NewSol.dec;
                DB_Y(DB_Count) = NewSol.obj;
            end
        end
    end
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