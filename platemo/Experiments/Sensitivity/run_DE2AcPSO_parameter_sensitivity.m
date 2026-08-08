function summaryTable = run_DE2AcPSO_parameter_sensitivity(mode,dimensions, ...
    configIndices,runIndices,finalizeOutputs,parallelWorkers)
%RUN_DE2ACPSO_PARAMETER_SENSITIVITY OFAT study on SOP_F11.
%
%   run_DE2AcPSO_parameter_sensitivity('pilot')
%   run_DE2AcPSO_parameter_sensitivity('full')
%   run_DE2AcPSO_parameter_sensitivity('full',500,2:18,1:10,false)
%   run_DE2AcPSO_parameter_sensitivity('full',[30 500], ...
%       1:18,1:10,true,8)
%
% The study varies one DE2AcPSO control parameter at a time on the
% generalized Griewank function (SOP_F11) at D = 30 and 500.
% Parameter levels are paired through common random seeds. The full mode
% uses 10 runs and 1000 function evaluations; pilot mode is intended only
% to validate the workflow. Per-case MAT files make interrupted runs
% resumable. Raw data, summary statistics, and a LaTeX results table are
% written to Data/DE2AcPSO_F11_ParameterSensitivity. Set parallelWorkers
% to an integer greater than one to use a process-based parallel pool.

if nargin < 1 || isempty(mode)
    mode = 'pilot';
end
mode = lower(char(mode));
if ~ismember(mode,{'pilot','full'})
    error('Sensitivity:InvalidMode', ...
        'Mode must be ''pilot'' or ''full''.');
end

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
cd(rootDir);
addpath(genpath(rootDir));

outputDir = fullfile(rootDir,'Data','DE2AcPSO_F11_ParameterSensitivity');
cacheDir = fullfile(outputDir,[upperFirst(mode) '_CaseCache']);
if ~exist(outputDir,'dir')
    mkdir(outputDir);
end
if ~exist(cacheDir,'dir')
    mkdir(cacheDir);
end

if strcmp(mode,'full')
    nRuns = 10;
    maxFE = 1000;
else
    nRuns = 2;
    maxFE = 250;
end

allDimensions = [30, 500];
if nargin < 2 || isempty(dimensions)
    dimensions = allDimensions;
else
    dimensions = reshape(dimensions,1,[]);
    if any(~ismember(dimensions,allDimensions))
        error('Sensitivity:InvalidDimension', ...
            'Dimensions must be selected from [30, 200, 500].');
    end
end
N = 50;
baseSeed = 814729;
defaultValues = [0.1, 0.2, 20, 50];

factorNames = {'R2Gate','PDIProbability','CandidateMultiplier', ...
               'EliteArchiveSize'};
factorSymbols = {'$\tau_{R^2}$','$p_{\mathrm{PDI}}$', ...
                 '$\kappa_c$','$K_{\mathrm{elite}}$'};
levelSets = { ...
    [0, 0.05, 0.10, 0.20, 0.30], ...
    [0, 0.10, 0.20, 0.30, 0.40], ...
    [1, 2, 3, 20], ...
    [20, 50, 100, 200]};

configRows = {};
for factorIndex = 1:numel(factorNames)
    levels = levelSets{factorIndex};
    for levelIndex = 1:numel(levels)
        values = defaultValues;
        values(factorIndex) = levels(levelIndex);
        configRows(end+1,:) = {factorNames{factorIndex}, ...
        factorSymbols{factorIndex}, levels(levelIndex), ...
            factorIndex, values(1), values(2), values(3), values(4)}; %#ok<AGROW>
    end
end

if nargin < 3 || isempty(configIndices)
    configIndices = 1:size(configRows,1);
else
    configIndices = reshape(configIndices,1,[]);
    if any(configIndices < 1 | configIndices > size(configRows,1) | ...
            configIndices ~= round(configIndices))
        error('Sensitivity:InvalidConfiguration', ...
            'Configuration indices must be integers from 1 to %d.', ...
            size(configRows,1));
    end
end
if nargin < 4 || isempty(runIndices)
    runIndices = 1:nRuns;
else
    runIndices = reshape(runIndices,1,[]);
    if any(runIndices < 1 | runIndices > nRuns | ...
            runIndices ~= round(runIndices))
        error('Sensitivity:InvalidRun', ...
            'Run indices must be integers from 1 to %d.',nRuns);
    end
end
if nargin < 5 || isempty(finalizeOutputs)
    finalizeOutputs = true;
end
finalizeOutputs = logical(finalizeOutputs);
if nargin < 6 || isempty(parallelWorkers)
    parallelWorkers = 0;
end
if ~isnumeric(parallelWorkers) || ~isscalar(parallelWorkers) || ...
        ~isfinite(parallelWorkers) || parallelWorkers < 0 || ...
        parallelWorkers ~= round(parallelWorkers)
    error('Sensitivity:InvalidParallelWorkers', ...
        'parallelWorkers must be a nonnegative integer scalar.');
end

plan = buildDE2AcPSOSensitivityTaskPlan(configRows,configIndices, ...
    dimensions,runIndices,baseSeed,maxFE,cacheDir);
nRows = plan.NumRows;
Factor = strings(nRows,1);
FactorSymbol = strings(nRows,1);
Level = nan(nRows,1);
R2Gate = nan(nRows,1);
PDIProbability = nan(nRows,1);
CandidateMultiplier = nan(nRows,1);
EliteArchiveSize = nan(nRows,1);
Dimension = nan(nRows,1);
Run = nan(nRows,1);
Seed = nan(nRows,1);
FinalFE = nan(nRows,1);
FinalObjective = nan(nRows,1);
RuntimeSeconds = nan(nRows,1);
Status = strings(nRows,1);

fprintf('DE2AcPSO F11 parameter sensitivity: %s mode, %d runs/configuration.\n', ...
    mode,nRuns);
taskResults = cell(plan.NumTasks,1);
taskSources = cell(plan.NumTasks,1);
if parallelWorkers > 1
    pool = ensureProcessPool(parallelWorkers);
    fprintf(['Executing %d unique case(s) with %d process-based ', ...
        'parallel worker(s); %d result row(s) will be assembled.\n'], ...
        plan.NumTasks,pool.NumWorkers,plan.NumRows);
    tasks = plan.Tasks;
    parfor taskIndex = 1:plan.NumTasks
        [taskResults{taskIndex},taskSources{taskIndex}] = ...
            executeSensitivityTask(tasks(taskIndex),N,maxFE);
    end
else
    fprintf('Executing %d unique case(s) serially.\n',plan.NumTasks);
    for taskIndex = 1:plan.NumTasks
        [taskResults{taskIndex},taskSources{taskIndex}] = ...
            executeSensitivityTask(plan.Tasks(taskIndex),N,maxFE);
    end
end

for rowIndex = 1:nRows
    row = plan.Rows(rowIndex);
    parameterValues = row.ParameterValues;
    result = taskResults{row.TaskIndex};
    source = taskSources{row.TaskIndex};

    Factor(rowIndex) = string(row.Factor);
    FactorSymbol(rowIndex) = string(row.FactorSymbol);
    Level(rowIndex) = row.Level;
    R2Gate(rowIndex) = parameterValues(1);
    PDIProbability(rowIndex) = parameterValues(2);
    CandidateMultiplier(rowIndex) = parameterValues(3);
    EliteArchiveSize(rowIndex) = parameterValues(4);
    Dimension(rowIndex) = row.Dimension;
    Run(rowIndex) = row.Run;
    Seed(rowIndex) = row.Seed;
    FinalFE(rowIndex) = result.finalFE;
    FinalObjective(rowIndex) = result.objective;
    RuntimeSeconds(rowIndex) = result.runtime;
    Status(rowIndex) = string(result.status);

    fprintf('%s = %g, F11 D=%d, run %02d/%02d: %s/%s, FE=%d, f=%.6e\n', ...
        row.Factor,row.Level,row.Dimension,row.Run,nRuns,result.status, ...
        source,result.finalFE,result.objective);
end

if ~finalizeOutputs
    summaryTable = table();
    fprintf(['Cache worker completed %d configuration(s), %d dimension(s), ', ...
        'and %d run index/indices without writing aggregate outputs.\n'], ...
        numel(configIndices),numel(dimensions),numel(runIndices));
    return;
end

rawTable = table(Factor,FactorSymbol,Level,R2Gate,PDIProbability, ...
    CandidateMultiplier,EliteArchiveSize,Dimension,Run,Seed,FinalFE, ...
    FinalObjective,RuntimeSeconds,Status);
rawCsv = fullfile(outputDir,sprintf('F11_ParameterSensitivity_%s_Raw.csv',mode));
rawMat = fullfile(outputDir,sprintf('F11_ParameterSensitivity_%s_Raw.mat',mode));
writetable(rawTable,rawCsv);
save(rawMat,'rawTable','configRows','mode','nRuns','maxFE','dimensions', ...
    'defaultValues');

summaryRows = cell(size(configRows,1)*numel(dimensions),12);
summaryIndex = 0;
for configIndex = 1:size(configRows,1)
    factorName = configRows{configIndex,1};
    factorSymbol = configRows{configIndex,2};
    level = configRows{configIndex,3};
    for D = dimensions
        summaryIndex = summaryIndex + 1;
        mask = rawTable.Factor == string(factorName) & ...
               abs(rawTable.Level-level) < 1e-12 & ...
               rawTable.Dimension == D;
        objectives = rawTable.FinalObjective(mask);
        runtimes = rawTable.RuntimeSeconds(mask);
        finalFE = rawTable.FinalFE(mask);
        validObjectives = isfinite(objectives);
        objectives = objectives(validObjectives);
        runtimes = runtimes(isfinite(runtimes));
        finalFE = finalFE(isfinite(finalFE));

        if isempty(objectives)
            meanObjective = NaN;
            stdObjective = NaN;
            medianObjective = NaN;
            iqrObjective = NaN;
        else
            meanObjective = mean(objectives);
            stdObjective = std(objectives,0);
            medianObjective = median(objectives);
            iqrObjective = iqr(objectives);
        end
        if isempty(runtimes)
            meanRuntime = NaN;
        else
            meanRuntime = mean(runtimes);
        end
        if isempty(finalFE)
            completionRate = 0;
        else
            completionRate = mean(finalFE >= maxFE);
        end

        summaryRows(summaryIndex,:) = {factorName,factorSymbol,level,D, ...
            numel(objectives),meanObjective,stdObjective,medianObjective, ...
            iqrObjective,meanRuntime,completionRate, ...
            abs(level-defaultValues(configRows{configIndex,4})) < 1e-12};
    end
end

summaryTable = cell2table(summaryRows,'VariableNames',{ ...
    'Factor','FactorSymbol','Level','Dimension','NCompleted', ...
    'MeanObjective','StdObjective','MedianObjective','IQRObjective', ...
    'MeanRuntimeSeconds','CompletionRate','IsDefault'});
numericNames = {'Level','Dimension','NCompleted','MeanObjective', ...
    'StdObjective','MedianObjective','IQRObjective','MeanRuntimeSeconds', ...
    'CompletionRate'};
for i = 1:numel(numericNames)
    if iscell(summaryTable.(numericNames{i}))
        summaryTable.(numericNames{i}) = cell2mat(summaryTable.(numericNames{i}));
    end
end
if iscell(summaryTable.IsDefault)
    summaryTable.IsDefault = cell2mat(summaryTable.IsDefault);
end
summaryTable = addPairedStatistics(rawTable,summaryTable,configRows, ...
    dimensions,defaultValues);

summaryCsv = fullfile(outputDir, ...
    sprintf('F11_ParameterSensitivity_%s_Summary.csv',mode));
summaryMat = fullfile(outputDir, ...
    sprintf('F11_ParameterSensitivity_%s_Summary.mat',mode));
writetable(summaryTable,summaryCsv);
save(summaryMat,'summaryTable');
latexTable = writeLatexSummary(summaryTable,outputDir,mode,nRuns,maxFE,dimensions);
fprintf('F11 sensitivity outputs written to:\n%s\n',outputDir);
end

function result = runOneCase(seed,D,N,maxFE,parameterValues)
result = struct('finalFE',0,'objective',NaN,'runtime',NaN,'status','failed');
try
    rng(seed,'twister');
    Problem = SOP_F11('N',N,'D',D,'maxFE',maxFE);
    Algorithm = DE2AcPSO('parameter',num2cell(parameterValues), ...
        'save',0,'metName',{'Min_value'});
    Algorithm.Solve(Problem);
    result.finalFE = Problem.FE;
    result.runtime = Algorithm.metric.runtime;
    if Problem.FE >= maxFE
        objective = Algorithm.CalMetric('Min_value');
        result.objective = objective(end);
        result.status = 'completed';
    else
        result.status = 'incomplete';
    end
catch err
    result.status = sprintf('failed:%s',err.identifier);
end
end

function [result,source] = executeSensitivityTask(task,N,maxFE)
if exist(task.CacheFile,'file') == 2
    try
        loaded = load(task.CacheFile,'result');
        if isfield(loaded,'result') && isstruct(loaded.result)
            result = loaded.result;
            source = 'cached';
            return;
        end
    catch
        % Recompute unreadable or incomplete cache files.
    end
end

result = runOneCase(task.Seed,task.Dimension,N,maxFE, ...
    task.ParameterValues);
saveTaskCache(task.CacheFile,result,task,N,maxFE);
source = 'computed';
end

function saveTaskCache(cacheFile,result,task,N,maxFE)
seed = task.Seed;
D = task.Dimension;
parameterValues = task.ParameterValues;
temporaryFile = [tempname(fileparts(cacheFile)) '.mat'];
cleanup = onCleanup(@()deleteIfPresent(temporaryFile));
save(temporaryFile,'result','seed','D','N','maxFE','parameterValues');
movefile(temporaryFile,cacheFile,'f');
end

function deleteIfPresent(fileName)
if exist(fileName,'file') == 2
    delete(fileName);
end
end

function pool = ensureProcessPool(parallelWorkers)
if exist('parpool','file') ~= 2 || ...
        ~license('test','Distrib_Computing_Toolbox')
    error('Sensitivity:ParallelToolboxUnavailable', ...
        ['Parallel Computing Toolbox is required when parallelWorkers ', ...
         'is greater than one.']);
end

pool = gcp('nocreate');
if isempty(pool)
    pool = parpool('Processes',parallelWorkers);
elseif isa(pool,'parallel.ThreadPool')
    error('Sensitivity:ThreadPoolUnsupported', ...
        ['An existing thread-based pool is active. Delete it and rerun ', ...
         'so that a process-based pool can be created for PlatEMO.']);
elseif pool.NumWorkers ~= parallelWorkers
    warning('Sensitivity:ExistingPoolSize', ...
        ['Using the existing process pool with %d workers instead of ', ...
         'the requested %d workers.'],pool.NumWorkers,parallelWorkers);
end
end

function summaryTable = addPairedStatistics(rawTable,summaryTable, ...
    configRows,dimensions,defaultValues)
summaryTable.FriedmanP = nan(height(summaryTable),1);
summaryTable.WilcoxonPVsDefault = nan(height(summaryTable),1);
summaryTable.HolmPVsDefault = nan(height(summaryTable),1);
summaryTable.MedianDifferenceVsDefault = nan(height(summaryTable),1);

if exist('friedman','file') ~= 2 || exist('signrank','file') ~= 2
    warning('Sensitivity:StatisticsUnavailable', ...
        ['friedman or signrank is unavailable. Descriptive statistics ', ...
         'were generated without paired inferential tests.']);
    return;
end

for factorIndex = 1:numel(defaultValues)
    factorName = configRows{find(cell2mat(configRows(:,4)) == ...
        factorIndex,1),1};
    factorMask = strcmp(rawTable.Factor,factorName);
    levels = unique(rawTable.Level(factorMask),'stable');
    defaultLevel = defaultValues(factorIndex);
    defaultColumn = find(abs(levels-defaultLevel) < 1e-12,1);

    for D = dimensions
        dimensionMask = factorMask & rawTable.Dimension == D;
        runs = unique(rawTable.Run(dimensionMask));
        pairedObjectives = nan(numel(runs),numel(levels));
        for levelIndex = 1:numel(levels)
            for runIndex = 1:numel(runs)
                observationMask = dimensionMask & ...
                    abs(rawTable.Level-levels(levelIndex)) < 1e-12 & ...
                    rawTable.Run == runs(runIndex);
                value = rawTable.FinalObjective(observationMask);
                if isscalar(value) && isfinite(value)
                    pairedObjectives(runIndex,levelIndex) = value;
                end
            end
        end

        completeRows = all(isfinite(pairedObjectives),2);
        pairedObjectives = pairedObjectives(completeRows,:);
        if size(pairedObjectives,1) >= 2 && numel(levels) >= 3
            friedmanP = friedman(pairedObjectives,1,'off');
        else
            friedmanP = NaN;
        end

        rawP = nan(numel(levels),1);
        medianDifference = nan(numel(levels),1);
        defaultValuesForRuns = pairedObjectives(:,defaultColumn);
        for levelIndex = 1:numel(levels)
            if levelIndex == defaultColumn || isempty(defaultValuesForRuns)
                continue;
            end
            differences = pairedObjectives(:,levelIndex) - ...
                defaultValuesForRuns;
            medianDifference(levelIndex) = median(differences);
            if all(abs(differences) <= 1e-14)
                rawP(levelIndex) = 1;
            else
                rawP(levelIndex) = signrank( ...
                    pairedObjectives(:,levelIndex),defaultValuesForRuns);
            end
        end
        adjustedP = holmAdjust(rawP);

        for levelIndex = 1:numel(levels)
            summaryMask = strcmp(summaryTable.Factor,factorName) & ...
                summaryTable.Dimension == D & ...
                abs(summaryTable.Level-levels(levelIndex)) < 1e-12;
            summaryTable.FriedmanP(summaryMask) = friedmanP;
            summaryTable.WilcoxonPVsDefault(summaryMask) = rawP(levelIndex);
            summaryTable.HolmPVsDefault(summaryMask) = adjustedP(levelIndex);
            summaryTable.MedianDifferenceVsDefault(summaryMask) = ...
                medianDifference(levelIndex);
        end
    end
end
end

function adjustedP = holmAdjust(rawP)
adjustedP = nan(size(rawP));
validIndices = find(isfinite(rawP));
if isempty(validIndices)
    return;
end
[sortedP,order] = sort(rawP(validIndices));
m = numel(sortedP);
scaledP = (m-(1:m)'+1).*sortedP;
adjustedSorted = min(1,cummax(scaledP));
adjustedP(validIndices(order)) = adjustedSorted;
end

function fileName = writeLatexSummary(summaryTable,outputDir,mode,nRuns,maxFE,dimensions)
fileName = fullfile(outputDir, ...
    sprintf('F11_ParameterSensitivity_%s_Table.tex',mode));
fid = fopen(fileName,'w');
if fid < 0
    warning('Sensitivity:TableWriteFailed','Could not write %s.',fileName);
    return;
end
cleanup = onCleanup(@()fclose(fid));

fprintf(fid,'%% Generated by run_DE2AcPSO_parameter_sensitivity.m\n');
fprintf(fid,'\\begin{table*}[!t]\n\\centering\n');
fprintf(fid,'\\caption{One-factor-at-a-time parameter sensitivity of DE2AcPSO on SOP $F_{11}$. ');
fprintf(fid,'Each cell reports the mean objective value (standard deviation) over ');
fprintf(fid,'%d independent runs with $\\mathrm{FE}_{\\max}=%d$; lower values are better. ', ...
    nRuns,maxFE);
fprintf(fid,'Bold denotes the default setting and $\\dagger$ denotes a significant ');
fprintf(fid,'paired difference from the default after Holm correction ($p<0.05$).}\n');
fprintf(fid,'\\label{tab:parameter_sensitivity_results}\n');
fprintf(fid,'\\scriptsize\n\\setlength{\\tabcolsep}{5pt}\n');
fprintf(fid,'\\resizebox{\\textwidth}{!}{%%\n');
fprintf(fid,'\\begin{tabular}{ccccc}\n\\toprule\n');
fprintf(fid,'Parameter & Level');
for D = dimensions
    fprintf(fid,' & $D=%d$',D);
end
fprintf(fid,' \\\\\n\\midrule\n');

factorOrder = unique(summaryTable.Factor,'stable');
for factorIndex = 1:numel(factorOrder)
    factorName = factorOrder{factorIndex};
    rows = summaryTable(strcmp(summaryTable.Factor,factorName),:);
    levels = unique(rows.Level,'stable');
    for levelIndex = 1:numel(levels)
        level = levels(levelIndex);
        levelRows = rows(abs(rows.Level-level)<1e-12,:);
        isDefault = any(levelRows.IsDefault);
        if levelIndex == 1
            factorText = rows.FactorSymbol{1};
        else
            factorText = '';
        end
        if isDefault
            levelText = ['\textbf{' formatLevel(level) '}'];
        else
            levelText = formatLevel(level);
        end
        fprintf(fid,'%s & %s',factorText,levelText);
        for D = dimensions
            resultRow = levelRows(levelRows.Dimension==D,:);
            if isempty(resultRow) || ~isfinite(resultRow.MeanObjective(1))
                cellText = '--';
            else
                cellText = sprintf('%.4e (%.2e)', ...
                    resultRow.MeanObjective(1),resultRow.StdObjective(1));
                if isDefault
                    cellText = sprintf('\\textbf{%s}',cellText);
                elseif isfinite(resultRow.HolmPVsDefault(1)) && ...
                        resultRow.HolmPVsDefault(1) < 0.05
                    cellText = sprintf('%s$^{\\dagger}$',cellText);
                end
            end
            fprintf(fid,' & %s',cellText);
        end
        fprintf(fid,' \\\\\n');
    end
    if factorIndex < numel(factorOrder)
        fprintf(fid,'\\midrule\n');
    end
end
fprintf(fid,'\\bottomrule\n\\end{tabular}}\n\\end{table*}\n');
fprintf(fid,'%% Mode: %s; generated from actual MATLAB runs.\n',mode);
end

function text = formatLevel(value)
if abs(value-round(value)) < 1e-12
    text = sprintf('%d',round(value));
else
    text = sprintf('%.2f',value);
end
end

function text = upperFirst(value)
text = value;
text(1) = upper(text(1));
end
