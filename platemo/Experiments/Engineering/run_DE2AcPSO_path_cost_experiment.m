clear; clc; close all;

% Reproducible synthetic path-cost experiment runner.
% Existing completed files are reused by default. Set overwriteExisting to
% true only when a complete rerun is intended.

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
cd(rootDir);
addpath(genpath(rootDir));

N = 50;
maxFE = 1000;
runs = 20;
D = 500;
scenarioIds = [1 2];
savePoints = 25;
overwriteExisting = false;
useParallel = true;
parallelWorkers = 5; % Conservative default for a 16 GB workstation.
sceneSeed = 20260731;
problemVersion = 'synthetic-path-cost-v2';
experimentFolder = 'DE2AcPSO_PathCost';

algorithms = {@L2SMEA,@SADEAMSS,@SAMSO,@GORS_SSLPSO,@SHPSO,@DE2AcPSO};
algNames = {'L2SMEA','SADEAMSS','SAMSO','GORS_SSLPSO','SHPSO','DE2AcPSO'};

targetDir = fullfile(rootDir,'Data',experimentFolder);
if ~exist(targetDir,'dir')
    mkdir(targetDir);
end

sceneFile = fullfile(targetDir,'ScenPos.mat');
if exist(sceneFile,'file') == 2
    loadedScene = load(sceneFile,'ScenPos');
    ScenPos = loadedScene.ScenPos;
else
    legacySceneFile = fullfile(rootDir,'Data','Engin','ScenPos.mat');
    if exist(legacySceneFile,'file') == 2
        loadedScene = load(legacySceneFile,'ScenPos');
        ScenPos = loadedScene.ScenPos;
    else
        ScenPos = cell(max(scenarioIds),2);
    end
end
if size(ScenPos,1) < max(scenarioIds)
    ScenPos{max(scenarioIds),2} = [];
end

rng(sceneSeed,'twister');
lb = -100;
ub = 100;
for sc = scenarioIds
    if isempty(ScenPos{sc,1}) || isempty(ScenPos{sc,2})
        ScenPos{sc,1} = [lb + 0.4*(ub-lb)*rand(), lb + 0.4*(ub-lb)*rand()];
        ScenPos{sc,2} = [ub - 0.4*(ub-lb)*rand(), ub - 0.4*(ub-lb)*rand()];
    end
end
save(sceneFile,'ScenPos','sceneSeed','problemVersion');

renderScenarioMaps(targetDir,scenarioIds,ScenPos);

if useParallel
    currentPool = gcp('nocreate');
    if isempty(currentPool)
        currentPool = parpool('local',parallelWorkers);
    elseif currentPool.NumWorkers ~= parallelWorkers
        warning('Using the existing pool with %d workers (configured value: %d).', ...
            currentPool.NumWorkers,parallelWorkers);
    end
end

totalTasks = numel(algorithms)*numel(scenarioIds)*runs;
statusRows = cell(totalTasks,9);
statusIndex = 0;
for algIndex = 1:numel(algorithms)
    algorithm = algorithms{algIndex};
    algName = algNames{algIndex};
    algorithmDir = fullfile(rootDir,'Data',algName);
    if ~exist(algorithmDir,'dir')
        mkdir(algorithmDir);
    end

    for sc = scenarioIds
        startPos = ScenPos{sc,1};
        endPos = ScenPos{sc,2};
        fprintf('\n%s, Scenario %d, D=%d\n',algName,sc,D);

        runNeeded = true(1,runs);
        workerMessage = repmat({''},1,runs);
        workerSeconds = zeros(1,runs);

        for run = 1:runs
            targetFile = fullfile(targetDir,sprintf('%s_Scen%d_Run%d.mat',algName,sc,run));
            if ~overwriteExisting && exist(targetFile,'file') == 2
                runNeeded(run) = false;
                workerMessage{run} = 'reused existing file';
            elseif overwriteExisting && exist(targetFile,'file') == 2
                delete(targetFile);
            end

            if runNeeded(run)
                tempFile = fullfile(algorithmDir,sprintf( ...
                    '%s_RobotPathPlanning_M1_D%d_%d.mat',algName,D,run));
                if exist(tempFile,'file') == 2
                    delete(tempFile);
                end
            end
        end

        if useParallel
            parfor run = 1:runs
                if runNeeded(run)
                    timer = tic;
                    try
                        platemo('algorithm',algorithm, ...
                            'problem',{@RobotPathPlanning,sc,startPos,endPos}, ...
                            'N',N,'D',D,'maxFE',maxFE,'save',savePoints,'run',run);
                        workerMessage{run} = 'worker completed';
                    catch errorInfo
                        workerMessage{run} = sprintf('%s: %s', ...
                            errorInfo.identifier,errorInfo.message);
                    end
                    workerSeconds(run) = toc(timer);
                end
            end
        else
            for run = 1:runs
                if runNeeded(run)
                    timer = tic;
                    try
                        platemo('algorithm',algorithm, ...
                            'problem',{@RobotPathPlanning,sc,startPos,endPos}, ...
                            'N',N,'D',D,'maxFE',maxFE,'save',savePoints,'run',run);
                        workerMessage{run} = 'worker completed';
                    catch errorInfo
                        workerMessage{run} = sprintf('%s: %s', ...
                            errorInfo.identifier,errorInfo.message);
                    end
                    workerSeconds(run) = toc(timer);
                end
            end
        end

        for run = 1:runs
            targetFile = fullfile(targetDir,sprintf('%s_Scen%d_Run%d.mat',algName,sc,run));
            tempFile = fullfile(algorithmDir,sprintf( ...
                '%s_RobotPathPlanning_M1_D%d_%d.mat',algName,D,run));

            if runNeeded(run) && exist(tempFile,'file') == 2
                movefile(tempFile,targetFile,'f');
            end

            [finalFE,runState] = inspectResult(targetFile,maxFE);
            if strcmp(runState,'missing') && ~isempty(workerMessage{run})
                runState = 'failed';
            end
            statusIndex = statusIndex + 1;
            statusRows(statusIndex,:) = {algName,sc,run,D,problemVersion, ...
                                         finalFE,runState,workerSeconds(run), ...
                                         workerMessage{run}};
            fprintf('  Run %02d: %-20s FE=%4d  %s\n', ...
                run,runState,finalFE,workerMessage{run});
        end

        statusTable = cell2table(statusRows(1:statusIndex,:),'VariableNames', ...
            {'Algorithm','Scenario','Run','Dimension','ProblemVersion', ...
             'FinalFE','Status','Seconds','Message'});
        writetable(statusTable,fullfile(targetDir,'Experiment_Status.csv'));
        save(fullfile(targetDir,'Experiment_Status.mat'),'statusTable');
    end
end

fprintf('\nSynthetic path-cost experiment processing finished.\n');

function renderScenarioMaps(targetDir,scenarioIds,ScenPos)
    axisValues = linspace(-100,100,201);
    [XGrid,YGrid] = meshgrid(axisValues,axisValues);
    for sc = scenarioIds
        ZGrid = RobotPathPlanning.Get_Obstacle_Cost(XGrid,YGrid,sc);
        fig = figure('Visible','off','Color','w','Position',[100 100 850 650]);
        contourf(XGrid,YGrid,ZGrid,50,'LineColor','none');
        hold on;
        scatter(ScenPos{sc,1}(1),ScenPos{sc,1}(2),160,[0.10 0.75 0.15], ...
            'filled','p','MarkerEdgeColor','k');
        scatter(ScenPos{sc,2}(1),ScenPos{sc,2}(2),160,[0.95 0.15 0.65], ...
            'filled','p','MarkerEdgeColor','k');
        colormap(turbo(256)); colorbar;
        axis equal tight; box on;
        xlabel('X'); ylabel('Y');
        title(sprintf('Scenario %d threat map',sc));
        exportgraphics(fig,fullfile(targetDir,sprintf('2D_Map_Scenario_%d.png',sc)), ...
            'Resolution',300);
        close(fig);
    end
end

function [finalFE,state] = inspectResult(file,maxFE)
    finalFE = 0;
    state = 'missing';
    if exist(file,'file') ~= 2
        return;
    end
    try
        loaded = load(file,'result');
        validRows = find(~cellfun(@isempty,loaded.result(:,1)) & ...
                         ~cellfun(@isempty,loaded.result(:,2)));
        if isempty(validRows)
            state = 'invalid';
            return;
        end
        validRow = validRows(end);
        finalFE = loaded.result{validRow,1};
        if finalFE >= maxFE && numel(validRows) > 1
            state = 'completed';
        else
            state = 'initialization-only';
        end
    catch
        state = 'invalid';
    end
end
