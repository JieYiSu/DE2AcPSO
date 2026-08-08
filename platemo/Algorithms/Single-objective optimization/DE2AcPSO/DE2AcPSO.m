classdef DE2AcPSO < ALGORITHM
% <single> <real> <expensive>
% DE2AcPSO: Dual-engine enhanced adaptive compact particle swarm optimization
%
% Parameters (default values):
%   R2Gate              = 0.10
%   PDIProbability      = 0.20
%   CandidateMultiplier = 20
%   EliteArchiveSize    = 50
%
% See the repository README and CITATION.cff for installation, experiment,
% and citation information.
%
% -------------------------------------------------------------------------
% This algorithm is specifically designed for computationally expensive 
% optimization problems. It alternates between two synergistic engines:
% Engine 1: A rank-1 anisotropic local quadratic surrogate with a guarded
%           analytic proposal.
% Engine 2: An elite-difference-direction-injected cPSO assisted by a
%           global RBF.
% -------------------------------------------------------------------------

    methods
        function main(Algorithm, Problem)
            %% Parameter Initialization
            [R2Gate,PDIProbability,CandidateMultiplier,EliteArchiveSize] = ...
                Algorithm.ParameterSet(0.1,0.2,20,50);
            R2Gate              = min(1,max(0,R2Gate));
            PDIProbability      = min(1,max(0,PDIProbability));
            CandidateMultiplier = max(1,round(CandidateMultiplier));
            EliteArchiveSize    = max(2,round(EliteArchiveSize));

            DB_MaxFE = Problem.maxFE;
            DB_D = Problem.D;
            DB_X = zeros(DB_MaxFE, DB_D);
            DB_Y = inf(DB_MaxFE, 1);
            
            % Adaptive initial population size based on dimensionality
            if DB_D < 100; N_init = 100; else; N_init = 150; end
            
            % Latin Hypercube Sampling (LHS) for initial design of experiments
            P = lhsdesign(N_init, DB_D);
            PopDec = repmat(Problem.lower, N_init, 1) + P .* repmat(Problem.upper - Problem.lower, N_init, 1);
            Archive = Problem.Evaluation(PopDec);
            
            DB_X(1:N_init, :) = Archive.decs;
            DB_Y(1:N_init) = Archive.objs;
            DB_Count = N_init;
            
            % Initialize multi-distribution parameters for cPSO
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
                
                % Dynamic minimum standard deviation to balance exploration and exploitation
                domain_span = Problem.upper - Problem.lower;
                min_sigma = max(1e-250, domain_span .* (1e-3 * (1 - FE_ratio)^3)); 
                
                % Alternating execution of the Dual Engines
                if mod(iter, 2) == 0
                    %% Engine 1: Rank-1 Anisotropic Local Quadratic Model
                    K_local = min(DB_Count, DB_D + 6); 
                    Local_X = X_all(sort_idx(1:K_local), :);
                    Local_Y = Y_all(sort_idx(1:K_local));
                    
                    % Define the local scaling radius from the selected archive subset
                    R_local = max(sqrt(sum((Local_X - DB_BestX).^2, 2)));
                    if R_local < 1e-250; R_local = 1e-250; end
                    
                    Z_local = (Local_X - DB_BestX) / R_local;
                    
                    % Extract the dominant search direction (Rank-1 Subspace)
                    if K_local > 1
                        v_dom = Z_local(2, :) - Z_local(1, :);
                    else
                        v_dom = randn(1, DB_D);
                    end
                    v_norm = norm(v_dom) + 1e-250;
                    v_dom = v_dom / v_norm; 
                    
                    Proj_Z = (Z_local * v_dom').^2; 
                    
                    % Objective value normalization
                    Y_min = min(Local_Y); dY = max(Local_Y) - Y_min; 
                    if dY < 1e-250; dY = 1e-250; end
                    Y_norm = (Local_Y - Y_min) / dY;
                    
                    % Construct the augmented polynomial basis
                    P_iso = [ones(K_local, 1), sum(Z_local.^2, 2), Proj_Z, Z_local];
                    
                    % Condition the basis matrix to prevent numerical instability
                    P_norms = sqrt(sum(P_iso.^2, 1));
                    P_norms(P_norms < 1e-200) = 1; 
                    P_scaled = P_iso ./ P_norms;
                    
                    % Fast dual ridge regression via Woodbury matrix identity
                    K_P = size(P_scaled, 1);
                    reg_lambda = 1e-6; 
                    dual_coef = (P_scaled * P_scaled' + reg_lambda * eye(K_P)) \ Y_norm;
                    coef_scaled = P_scaled' * dual_coef;
                    
                    coef = coef_scaled ./ P_norms';
                    
                    % Goodness-of-fit assessment (R-squared)
                    Y_pred = P_iso * coef;
                    SS_res = sum((Y_norm - Y_pred).^2);
                    SS_tot = sum((Y_norm - mean(Y_norm)).^2);
                    R2 = 1 - (SS_res / (SS_tot + 1e-250));
                    
                    if R2 < R2Gate
                        % Fallback strategies if the quadratic surrogate is inaccurate
                        rand_action = rand();
                        if rand_action < 0.33
                            % Strategy A: Partial orthogonal reflection
                            mask = rand(1, DB_D) < 0.2; 
                            x_infill = DB_BestX;
                            x_infill(mask) = Problem.lower(mask) + Problem.upper(mask) - DB_BestX(mask);
                        elseif rand_action < 0.66
                            % Strategy B: Levy flight mutation
                            beta = 1.5;
                            sigma_u = (gamma(1+beta)*sin(pi*beta/2)/(gamma((1+beta)/2)*beta*2^((beta-1)/2)))^(1/beta);
                            u = randn(1, DB_D) * sigma_u;
                            v = randn(1, DB_D);
                            step = u ./ abs(v).^(1/beta);
                            scale_factor = 1e-3 * (1 - FE_ratio);
                            x_infill = DB_BestX + step .* domain_span .* scale_factor;
                        else
                            % Strategy C: Gaussian shrinking perturbation
                            shrink_factor = 1e-2 * (1 - FE_ratio)^2;
                            x_infill = DB_BestX + randn(1, DB_D) .* domain_span .* shrink_factor;
                        end
                    else
                        % Surrogate-guided optimization using analytical gradients
                        step_cap = max(1e-6, min(2.5, R2 * 2.5)); 
                        
                        % This safeguard bounds only the isotropic curvature;
                        % it does not guarantee a positive-definite Hessian.
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
                        
                        % Calculate a guarded stationary step and cap its norm
                        step_Z_norm = -(1/c1) * b_grad + (c2 * v_dot_g / (c1 * denominator)) * v_dom';
                        step_Z_norm = step_Z_norm'; 
                        
                        if norm(step_Z_norm) > step_cap
                            step_Z_norm = step_Z_norm * (step_cap / norm(step_Z_norm));
                        end
                        x_infill = DB_BestX + step_Z_norm * R_local;
                    end
                    
                else
                    %% Engine 2: Promising-Difference-Injected cPSO with Global RBF
                    Global_RBF = Fit_RBF_Full_Stable(X_all, Y_all);
                    
                    if DB_Count > 1; best2_x = X_all(sort_idx(2), :); else; best2_x = DB_BestX; end
                    
                    % Distribution 1: Local exploitation around the best-known solution
                    mu(1, :) = DB_BestX;
                    sigma_vec(1, :) = max(abs(DB_BestX - best2_x), min_sigma); 
                    
                    % Distribution 2: Elite-guided regional exploration
                    top_K = max(2, round(0.5 * DB_Count));
                    mu(2, :) = mean(X_all(sort_idx(1:top_K), :), 1);
                    sigma_vec(2, :) = max(abs(DB_BestX - mu(2, :)), min_sigma);
                    
                    % Distribution 3: Momentum-based global exploration
                    pop_std_all = std(X_all, 1, 1);
                    rand_idx1 = randi(DB_Count);
                    rand_idx2 = randi(DB_Count);
                    diff_momentum = abs(X_all(rand_idx1, :) - X_all(rand_idx2, :));
                    mu(3, :) = DB_BestX; 
                    sigma_vec(3, :) = max([pop_std_all; diff_momentum; min_sigma], [], 1); 
                    
                    % Calculate the best-to-elite-mean direction for injection
                    Elite_Dir = DB_BestX - mu(2, :);
                    norm_Dir = norm(Elite_Dir) + 1e-200;
                    Elite_Dir = Elite_Dir / norm_Dir; 
                    
                    % Generate candidate solutions using cPSO paradigms
                    N_cands = min(2000, CandidateMultiplier * DB_D);
                    Cands_Pool = zeros(N_cands, DB_D);
                    chunk = floor(N_cands / K_dist);
                    
                    for k = 1:K_dist
                        start_idx = (k-1)*chunk + 1;
                        if k == K_dist; end_idx = N_cands; else; end_idx = k*chunk; end
                        num_c = end_idx - start_idx + 1;
                        
                        base_step = zeros(num_c, DB_D);
                        is_gauss = rand(num_c, 1) < 0.5; 
                        
                        % Hybrid Gaussian and Cauchy sampling
                        num_gauss = sum(is_gauss);
                        if num_gauss > 0
                            base_step(is_gauss, :) = randn(num_gauss, DB_D) .* sigma_vec(k, :);
                        end
                        if (num_c - num_gauss) > 0
                            base_step(~is_gauss, :) = tan(pi*(rand(num_c - num_gauss, DB_D)-0.5)) .* sigma_vec(k, :);
                        end
                        
                        % Apply elite-difference direction injection
                        inject_step = zeros(num_c, DB_D);
                        is_inject = rand(num_c, 1) < PDIProbability;
                        num_inject = sum(is_inject);
                        
                        if num_inject > 0
                            inject_step(is_inject, :) = randn(num_inject, 1) .* norm(sigma_vec(k, :)) .* Elite_Dir;
                        end
                        
                        Cands_Pool(start_idx:end_idx, :) = repmat(mu(k, :), num_c, 1) + base_step + inject_step;
                    end
                    
                    Cands_Pool = Boundary_Reflection(Cands_Pool, Problem.lower, Problem.upper);
                    
                    % RBF Surrogate Evaluation and Acquisition Function Modeling
                    V_Y = Predict_RBF_Full_Stable(Global_RBF, Cands_Pool);
                    
                    X_norm_cands = (Cands_Pool - Global_RBF.X_min) ./ Global_RBF.span;
                    elite_count = min(EliteArchiveSize, DB_Count);
                    dist_to_eval = pdist2(X_norm_cands, Global_RBF.X_norm_db(sort_idx(1:elite_count), :));
                    min_dist = min(dist_to_eval, [], 2);
                    
                    % Normalize predictions and distance-based exploration scores
                    V_Y_norm = (V_Y - min(V_Y)) ./ (max(V_Y) - min(V_Y) + 1e-200);
                    Dist_norm = (min_dist - min(min_dist)) ./ (max(min_dist) - min(min_dist) + 1e-200);
                    
                    % Adaptive prediction-distance acquisition criterion
                    explore_weight = max(0.05, 0.5 * (1 - FE_ratio)^2); 
                    Acquisition_Func = V_Y_norm - explore_weight .* Dist_norm;
                    
                    [~, best_cand_idx] = min(Acquisition_Func);
                    x_infill = Cands_Pool(best_cand_idx, :);
                end
                
                % Ensure strict feasibility
                x_infill = Boundary_Reflection(x_infill, Problem.lower, Problem.upper);
                
                % Stagnation prevention mechanism (Diversity preservation)
                pop_spread = max(std(X_all, 1, 1)); 
                min_dist_limit = max(1e-250, 1e-8 * pop_spread);
                
                if min(sqrt(sum((X_all - x_infill).^2, 2))) < min_dist_limit
                    x_infill = DB_BestX + randn(1, DB_D) .* ((Problem.upper - Problem.lower) * 1e-4);
                    x_infill = Boundary_Reflection(x_infill, Problem.lower, Problem.upper);
                end
                
                % Exact objective evaluation
                NewSol = Problem.Evaluation(x_infill);
                Archive = [Archive, NewSol];
                
                % Update database
                DB_Count = DB_Count + 1;
                DB_X(DB_Count, :) = NewSol.dec;
                DB_Y(DB_Count) = NewSol.obj;
            end
        end
    end
end

%% Dimension-Adaptive Soft Reflection Boundary
function X = Boundary_Reflection(X, lb, ub)
    % Handles boundary violations by adaptively reflecting the variables 
    % back into the feasible domain.
    if size(lb, 1) == 1; lb = repmat(lb, size(X, 1), 1); end
    if size(ub, 1) == 1; ub = repmat(ub, size(X, 1), 1); end
    
    out_upper = X > ub;
    if any(out_upper(:))
        % Adaptively generate random matrices matching the out-of-bound shape
        X(out_upper) = ub(out_upper) - rand(size(X(out_upper))) .* mod(X(out_upper) - ub(out_upper), ub(out_upper) - lb(out_upper));
    end
    
    out_lower = X < lb;
    if any(out_lower(:))
        X(out_lower) = lb(out_lower) + rand(size(X(out_lower))) .* mod(lb(out_lower) - X(out_lower), ub(out_lower) - lb(out_lower));
    end
    
    % Strict clamping to guarantee feasibility
    X = max(min(X, ub), lb); 
end

%% Global Radial Basis Function (RBF) Construction
function model = Fit_RBF_Full_Stable(X, Y)
    % Constructs a globally stable RBF surrogate model with an augmented 
    % linear polynomial tail and fixed ridge regularization.
    N = size(X, 1); D = size(X, 2);
    X_min = min(X, [], 1);
    X_max = max(X, [], 1);
    span = max(X_max - X_min, 1e-200); 
    X_norm = (X - X_min) ./ span;
    
    Y_min = min(Y); dY = max(Y) - Y_min;
    if dY < 1e-200; dY = 1e-200; end
    Y_norm = (Y - Y_min) / dY;
    
    % Cubic kernel formulation
    dist_mat = pdist2(X_norm, X_norm) / sqrt(D);
    Phi = dist_mat.^3; 
    
    P = [X_norm, ones(N, 1)];
    A = [Phi, P; P', zeros(D+1, D+1)];
    b = [Y_norm; zeros(D+1, 1)];
    
    % Fixed diagonal ridge regularization for numerical conditioning
    reg_fixed = 1e-6;
    reg_matrix = reg_fixed * eye(N + D + 1);
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

%% RBF Surrogate Prediction
function Y_pred = Predict_RBF_Full_Stable(model, X_test)
    % Predicts the objective values of candidate solutions using the fitted RBF.
    X_norm_test = (X_test - model.X_min) ./ model.span;
    dist_mat = pdist2(X_norm_test, model.X_norm_db) / sqrt(model.D);
    Phi_test = dist_mat.^3;
    P_test = [X_norm_test, ones(size(X_test, 1), 1)];
    V_Y_norm = Phi_test * model.weights + P_test * model.tail;
    Y_pred = V_Y_norm * model.dY + model.Y_min;
end
