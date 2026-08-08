classdef RobotPathPlanning < PROBLEM
% <single> <real> <expensive>
% Synthetic two-dimensional threat-field path-cost optimization problem.
    properties
        scenario_id; % Scenario identifier
        start_pos;   % Start coordinate
        end_pos;     % Goal coordinate
        delay_time;  % Optional simulated evaluation delay in seconds
    end
    methods
        %% Default problem settings
        function Setting(obj)
            [obj.scenario_id, obj.start_pos, obj.end_pos] = obj.ParameterSet(1, [-80, -80], [80, 80]);
            
            % Each intermediate control point contributes an x-y pair.
            if isempty(obj.D)
                obj.D = 500; 
            end
            if mod(obj.D,2) ~= 0
                error('RobotPathPlanning:InvalidDimension', ...
                    'D must be even because each control point contains x and y.');
            end
            
            % Basic problem properties
            obj.delay_time = 0;
            obj.M = 1; 
            obj.lower = repmat(-100, 1, obj.D); 
            obj.upper = repmat(100, 1, obj.D);  
            obj.encoding = repmat(1, 1, obj.D); 
        end
        
        %% Objective evaluation
        function PopObj = CalObj(obj, PopDec)
            N = size(PopDec, 1);
            PopObj = zeros(N, 1);
            for i = 1 : N
                pause(obj.delay_time);
                PopObj(i) = obj.Trajectory_Fitness(PopDec(i, :));
            end
        end
    end
    
    methods(Access = private)
        function total_cost = Trajectory_Fitness(obj, X)
            total_cost = RobotPathPlanning.EvaluateTrajectory( ...
                X,obj.start_pos,obj.end_pos,obj.scenario_id,200);
        end
    end

    %% Public static utilities used by the experiment and plotting scripts
    methods(Static)
        function [px,py,ctrl] = DecodeTrajectory(X,start_pos,end_pos,num_samples)
            % Convert unordered x-y candidates into a forward robot route.
            if nargin < 4 || isempty(num_samples)
                num_samples = 200;
            end
            X = X(:)';
            if mod(numel(X),2) ~= 0
                error('RobotPathPlanning:InvalidDecision', ...
                    'The decision vector must contain x-y coordinate pairs.');
            end
            num_mid = numel(X)/2;
            mid_pts = reshape(X,2,num_mid)';
            start_pos = start_pos(:)';
            end_pos = end_pos(:)';
            goalVector = end_pos-start_pos;
            routeLength = norm(goalVector);
            if routeLength <= eps
                error('RobotPathPlanning:CoincidentEndpoints', ...
                    'Start and end positions must be different.');
            end
            forward = goalVector/routeLength;
            lateralAxis = [-forward(2),forward(1)];

            relative = mid_pts-start_pos;
            progress = relative*forward';
            lateral = relative*lateralAxis';
            interior = progress > 1e-8 & progress < routeLength-1e-8;
            progress = progress(interior);
            lateral = lateral(interior);
            [progress,order] = sort(progress);
            lateral = lateral(order);
            if isempty(progress)
                progressNodes = [0;routeLength];
                lateralNodes = [0;0];
            else
                [uniqueProgress,~,group] = unique(progress);
                meanLateral = accumarray(group,lateral,[],@mean);
                progressNodes = [0;uniqueProgress;routeLength];
                lateralNodes = [0;meanLateral;0];
            end

            queryProgress = linspace(0,routeLength,num_samples)';
            queryLateral = pchip(progressNodes,lateralNodes,queryProgress);
            basePoints = start_pos + queryProgress*forward;

            lowerLateral = -inf(num_samples,1);
            upperLateral = inf(num_samples,1);
            for coordinate = 1:2
                axisValue = lateralAxis(coordinate);
                if abs(axisValue) <= eps
                    continue;
                end
                boundA = (-100-basePoints(:,coordinate))/axisValue;
                boundB = ( 100-basePoints(:,coordinate))/axisValue;
                lowerLateral = max(lowerLateral,min(boundA,boundB));
                upperLateral = min(upperLateral,max(boundA,boundB));
            end
            queryLateral = min(upperLateral,max(lowerLateral,queryLateral));
            route = basePoints + queryLateral*lateralAxis;
            route(1,:) = start_pos;
            route(end,:) = end_pos;
            px = route(:,1)';
            py = route(:,2)';
            ctrl = start_pos + progressNodes*forward + lateralNodes*lateralAxis;
        end

        function [totalCost,components] = EvaluateTrajectory( ...
                X,start_pos,end_pos,scenario_id,num_samples)
            if nargin < 5 || isempty(num_samples)
                num_samples = 200;
            end
            [px,py] = RobotPathPlanning.DecodeTrajectory( ...
                X,start_pos,end_pos,num_samples);
            dx = diff(px);
            dy = diff(py);
            segmentLength = hypot(dx,dy);
            distance = sum(segmentLength);

            threat = RobotPathPlanning.Get_Obstacle_Cost(px,py,scenario_id);
            threatMid = (threat(1:end-1)+threat(2:end))/2;
            collisionThreshold = RobotPathPlanning.GetCollisionThreshold(scenario_id);
            normalizedThreat = max(0,threatMid)/max(collisionThreshold,eps);
            threatExposure = sum(normalizedThreat.*segmentLength);
            intrusion = max(0,(threatMid-collisionThreshold)/max(collisionThreshold,eps));
            collisionLength = sum(segmentLength(intrusion > 0));
            collisionSeverity = sum(intrusion.^2.*segmentLength);

            firstVector = [dx(1:end-1);dy(1:end-1)]';
            secondVector = [dx(2:end);dy(2:end)]';
            dotProduct = sum(firstVector.*secondVector,2);
            normProduct = vecnorm(firstVector,2,2).*vecnorm(secondVector,2,2)+1e-12;
            turnPenalty = sum((1-dotProduct./normProduct).^2);

            boundaryViolation = sum(max(0,abs(px)-100).^2) + ...
                                sum(max(0,abs(py)-100).^2);
            totalCost = distance + 5*threatExposure + 50*turnPenalty + ...
                        5e4*collisionLength + 1e5*collisionSeverity + ...
                        1e5*boundaryViolation;

            components = struct('distance',distance, ...
                'threatExposure',threatExposure, ...
                'collisionLength',collisionLength, ...
                'collisionSeverity',collisionSeverity, ...
                'smoothness',turnPenalty, ...
                'boundaryViolation',boundaryViolation, ...
                'collisionThreshold',collisionThreshold);
        end

        function threshold = GetCollisionThreshold(scenario_id)
            persistent scenarioThresholds
            key = sprintf('scenario_%d',scenario_id);
            if isempty(scenarioThresholds) || ~isfield(scenarioThresholds,key)
                sampleAxis = linspace(-100,100,101);
                [sampleX,sampleY] = meshgrid(sampleAxis,sampleAxis);
                values = RobotPathPlanning.Get_Obstacle_Cost( ...
                    sampleX,sampleY,scenario_id);
                values = sort(values(:),'ascend');
                thresholdIndex = max(1,round(0.78*numel(values)));
                if isempty(scenarioThresholds)
                    scenarioThresholds = struct();
                end
                scenarioThresholds.(key) = values(thresholdIndex);
            end
            threshold = scenarioThresholds.(key);
        end

        function cost = Get_Obstacle_Cost(x, y, sc)
            noise = 3 * (sin(0.08*x) + cos(0.08*y));
            switch sc
                case 1
                    cost = 10 * (sin(0.05*x).^2 + cos(0.05*y).^2) + 20;
                case 2
                    cost = 30 + 15*sin(0.04*x).*cos(0.04*y) + 8*cos(0.05*x+0.05*y);
                    cost = max(cost, 0);
                case 3
                    cost = 20 + 80 * exp(-((x-10).^2 + (y-5).^2) / 600);
                    cost = max(cost, 0);
                case 4
                    wall1 = 100 ./ (1 + exp(-0.3 * (x - 20)));
                    wall2 = 100 ./ (1 + exp( 0.3 * (x + 20)));
                    cost = wall1 + wall2 + 20 * abs(sin(0.1*y)) + 20;
                case 5
                    height = 0.5*x + 0.3*y;
                    cost = 20 + 50 * abs(height) / 50 + 10 * (height/50).^2;
                case 6
                    valley = 5 * (x/15).^2;  
                    ridge = 30 * exp(-(y/20).^2);  
                    cost = 20 + valley + ridge; 
                    cost = max(cost, 0);
                case 7
                    wall_h = 80 ./ (1 + exp(-0.2 * (sin(0.1*x).*sin(0.1*y) - 0.5)));
                    wall_v = 80 ./ (1 + exp(-0.2 * (cos(0.1*x).*cos(0.1*y) - 0.5)));
                    cost = wall_h + wall_v + 15;
                case 8
                    cost = 25 + 10*sin(0.06*x).*cos(0.08*y) + 8*cos(0.1*x+0.06*y) + 6*sin(0.08*y).*cos(0.06*x);
                    cost = cost + 15 * exp(-((x+20).^2 + (y+15).^2) / 800);
                    cost = cost + 15 * exp(-((x-25).^2 + (y-20).^2) / 900);
                    cost = max(cost, 0);
                otherwise
                    cost = zeros(size(x));
            end
            cost = max(cost, 0) + noise; 
        end
    end
end
