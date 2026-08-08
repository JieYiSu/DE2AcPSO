clear; clc; close all;

% Re-run only failed engineering runs using the current saved scene.
experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
cd(rootDir);
addpath(genpath(rootDir));

N = 50;
maxFE = 1000;
runs = 20;
D = 500;
savePoints = 25;
useParallel = true;
parallelWorkers = 2;
restartParallelPool = true;
experimentFolder = 'DE2AcPSO_PathCost';
problemVersion = 'synthetic-path-cost-v2';
retryInitializationOnly = false;
dryRun = strcmp(getenv('PLATEMO_RERUN_DRY_RUN'),'1');

algorithms = {@L2SMEA,@SADEAMSS,@SAMSO,@GORS_SSLPSO,@SHPSO,@DE2AcPSO};
algNames = {'L2SMEA','SADEAMSS','SAMSO','GORS_SSLPSO','SHPSO','DE2AcPSO'};

targetDir = fullfile(rootDir,'Data',experimentFolder);
sceneFile = fullfile(targetDir,'ScenPos.mat');
statusFile = fullfile(targetDir,'Experiment_Status.csv');
assert(exist(sceneFile,'file') == 2, ...
    'Current ScenPos.mat was not found: %s',sceneFile);
assert(exist(statusFile,'file') == 2, ...
    'Experiment_Status.csv was not found: %s',statusFile);

sceneData = load(sceneFile,'ScenPos');
ScenPos = sceneData.ScenPos;
statusTable = readtable(statusFile,'TextType','string');
statusTable.Algorithm = string(statusTable.Algorithm);
statusTable.Status = string(statusTable.Status);
statusTable.Message = string(statusTable.Message);
if ismember('ProblemVersion',statusTable.Properties.VariableNames)
    statusTable.ProblemVersion = string(statusTable.ProblemVersion);
else
    statusTable.ProblemVersion = repmat(string(problemVersion),height(statusTable),1);
end

% Build a stable job list from failed rows only.
maximumJobs = height(statusTable);
jobAlgorithm = cell(maximumJobs,1);
jobAlgorithmName = cell(maximumJobs,1);
jobScenario = zeros(maximumJobs,1);
jobRun = zeros(maximumJobs,1);
jobStart = cell(maximumJobs,1);
jobEnd = cell(maximumJobs,1);
jobCount = 0;
for row = 1:height(statusTable)
    isFailed = statusTable.Status(row) == "failed";
    isSameVersion = statusTable.ProblemVersion(row) == string(problemVersion);
    if retryInitializationOnly
        isFailed = isFailed || statusTable.Status(row) == "initialization-only";
    end
    if ~(isFailed && isSameVersion)
        continue;
    end

    algorithmIndex = find(strcmp(algNames,statusTable.Algorithm(row)),1);
    if isempty(algorithmIndex)
        continue;
    end
    scenario = statusTable.Scenario(row);
    run = statusTable.Run(row);
    if scenario > size(ScenPos,1) || isempty(ScenPos{scenario,1}) || ...
            isempty(ScenPos{scenario,2})
        warning('Skipping %s scenario %d run %d: start/end positions are missing.', ...
            statusTable.Algorithm(row),scenario,run);
        continue;
    end

    targetFile = fullfile(targetDir,sprintf('%s_Scen%d_Run%d.mat', ...
        algNames{algorithmIndex},scenario,run));
    if exist(targetFile,'file') == 2
        [~,currentState] = inspectResult(targetFile,maxFE);
        if strcmp(currentState,'completed')
            continue;
        end
    end

    jobCount = jobCount + 1;
    jobAlgorithm{jobCount} = algorithms{algorithmIndex};
    jobAlgorithmName{jobCount} = algNames{algorithmIndex};
    jobScenario(jobCount) = scenario;
    jobRun(jobCount) = run;
    jobStart{jobCount} = ScenPos{scenario,1};
    jobEnd{jobCount} = ScenPos{scenario,2};
end

if jobCount == 0
    disp('No failed runs need to be re-run.');
    return;
end
jobAlgorithm = jobAlgorithm(1:jobCount);
jobAlgorithmName = jobAlgorithmName(1:jobCount);
jobScenario = jobScenario(1:jobCount);
jobRun = jobRun(1:jobCount);
jobStart = jobStart(1:jobCount);
jobEnd = jobEnd(1:jobCount);

fprintf('Found %d failed run(s):\n',jobCount);
for job = 1:jobCount
    fprintf('  %s scenario %d run %02d, start=[%.3f %.3f], end=[%.3f %.3f]\n', ...
        jobAlgorithmName{job},jobScenario(job),jobRun(job), ...
        jobStart{job}(1),jobStart{job}(2),jobEnd{job}(1),jobEnd{job}(2));
end
if dryRun
    disp('Dry run only; no files were changed and no algorithms were started.');
    return;
end

for job = 1:jobCount
    targetFile = fullfile(targetDir,sprintf('%s_Scen%d_Run%d.mat', ...
        jobAlgorithmName{job},jobScenario(job),jobRun(job)));
    if exist(targetFile,'file') == 2
        delete(targetFile);
    end
end

lockFile = fullfile(targetDir,'.rerun_failed.lock');
if exist(lockFile,'file') == 2
    error('A failed-run recovery job is already active: %s',lockFile);
end
lockId = fopen(lockFile,'w');
assert(lockId > 0,'Cannot create recovery lock file.');
startedAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
fprintf(lockId,'Started: %s\n',startedAt);
fclose(lockId);
lockCleanup = onCleanup(@()releaseLock(lockFile)); %#ok<NASGU>

if useParallel
    pool = gcp('nocreate');
    if restartParallelPool && ~isempty(pool)
        delete(pool);
        pool = [];
    end
    if isempty(pool)
        pool = parpool('local',parallelWorkers);
    elseif pool.NumWorkers ~= parallelWorkers
        warning('Using existing pool with %d workers.',pool.NumWorkers);
    end
end

workerMessage = repmat({''},jobCount,1);
workerSeconds = zeros(jobCount,1);
parfor job = 1:jobCount
    algorithmDir = fullfile(rootDir,'Data',jobAlgorithmName{job});
    if ~exist(algorithmDir,'dir')
        mkdir(algorithmDir);
    end
    tempFile = fullfile(algorithmDir,sprintf( ...
        '%s_RobotPathPlanning_M1_D%d_%d.mat',jobAlgorithmName{job},D,jobRun(job)));
    if exist(tempFile,'file') == 2
        delete(tempFile);
    end

    timer = tic;
    try
        platemo('algorithm',jobAlgorithm{job}, ...
            'problem',{@RobotPathPlanning,jobScenario(job),jobStart{job},jobEnd{job}}, ...
            'N',N,'D',D,'maxFE',maxFE,'save',savePoints,'run',jobRun(job));
        workerMessage{job} = 'worker completed';
    catch errorInfo
        workerMessage{job} = sprintf('%s: %s',errorInfo.identifier,errorInfo.message);
    end
    workerSeconds(job) = toc(timer);
end

rerunRows = cell(jobCount,9);
for job = 1:jobCount
    targetFile = fullfile(targetDir,sprintf('%s_Scen%d_Run%d.mat', ...
        jobAlgorithmName{job},jobScenario(job),jobRun(job)));
    algorithmDir = fullfile(rootDir,'Data',jobAlgorithmName{job});
    tempFile = fullfile(algorithmDir,sprintf( ...
        '%s_RobotPathPlanning_M1_D%d_%d.mat',jobAlgorithmName{job},D,jobRun(job)));
    if exist(tempFile,'file') == 2
        movefile(tempFile,targetFile,'f');
    end

    [finalFE,state] = inspectResult(targetFile,maxFE);
    if strcmp(state,'missing') && ~isempty(workerMessage{job})
        state = 'failed';
    end
    rerunRows(job,:) = {jobAlgorithmName{job},jobScenario(job),jobRun(job),D, ...
        problemVersion,finalFE,state,workerSeconds(job),workerMessage{job}};

    row = statusTable.Algorithm == string(jobAlgorithmName{job}) & ...
          statusTable.Scenario == jobScenario(job) & ...
          statusTable.Run == jobRun(job);
    if any(row)
        statusTable.FinalFE(row) = finalFE;
        statusTable.Status(row) = string(state);
        statusTable.Seconds(row) = workerSeconds(job);
        statusTable.Message(row) = string(workerMessage{job});
    end
    fprintf('%s scenario %d run %02d: %s FE=%d %s\n', ...
        jobAlgorithmName{job},jobScenario(job),jobRun(job),state,finalFE,workerMessage{job});
end

writetable(statusTable,statusFile);
save(fullfile(targetDir,'Experiment_Status.mat'),'statusTable');
rerunTable = cell2table(rerunRows,'VariableNames', ...
    {'Algorithm','Scenario','Run','Dimension','ProblemVersion', ...
     'FinalFE','Status','Seconds','Message'});
writetable(rerunTable,fullfile(targetDir,'Rerun_Failed_Status.csv'));
save(fullfile(targetDir,'Rerun_Failed_Status.mat'),'rerunTable');
disp('Failed-run recovery finished.');

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
        finalFE = loaded.result{validRows(end),1};
        if finalFE >= maxFE && numel(validRows) > 1
            state = 'completed';
        else
            state = 'initialization-only';
        end
    catch
        state = 'invalid';
    end
end

function releaseLock(lockFile)
    if exist(lockFile,'file') == 2
        delete(lockFile);
    end
end
