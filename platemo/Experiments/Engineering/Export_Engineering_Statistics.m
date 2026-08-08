function files = Export_Engineering_Statistics(dataDir,outputDir,algNames, ...
    baselineIndex,scenarioIds,D,runs,maxFE,numSamplePoints)
% Export two-scenario Holm-adjusted Wilcoxon statistics and convergence tables.
% '+' means the comparison algorithm is significantly better than the
% baseline in this minimization problem; '-' means worse; '=' means no
% significant difference at alpha = 0.05.

arguments
    dataDir (1,:) char
    outputDir (1,:) char
    algNames (1,:) cell
    baselineIndex (1,1) double {mustBeInteger,mustBePositive}
    scenarioIds (1,:) double {mustBeInteger,mustBePositive}
    D (1,1) double {mustBeInteger,mustBePositive}
    runs (1,1) double {mustBeInteger,mustBePositive}
    maxFE (1,1) double {mustBePositive}
    numSamplePoints (1,1) double {mustBeInteger,mustBePositive}
end

assert(baselineIndex <= numel(algNames),'baselineIndex exceeds algNames.');
scenarioIds = unique(scenarioIds,'stable');
if exist(outputDir,'dir') ~= 7
    mkdir(outputDir);
end

definitions = makeDefinitions(scenarioIds,runs,numSamplePoints);
numScenarios = numel(scenarioIds);
numAlgorithms = numel(algNames);
paperRows = cell(numScenarios+1,numAlgorithms+1);
detailTables = cell(numScenarios,1);
finalValuesByScenario = cell(numScenarios,1);
allSigns = repmat("",numScenarios,numAlgorithms);
bestIndicesByScenario = cell(numScenarios,1);
files.convergence = cell(numScenarios,1);

for scenarioIndex = 1:numScenarios
    scenario = scenarioIds(scenarioIndex);
    [meanTable,countTable,finalTable,finalValues,finalFEs] = ...
        processScenario(dataDir,algNames,scenario,D,runs,maxFE,numSamplePoints);

    details = buildWilcoxonTable(finalValues,finalFEs,algNames, ...
        baselineIndex,maxFE);
    details = addvars(details,repmat(scenario,height(details),1), ...
        'Before',1,'NewVariableNames','Scenario');
    detailTables{scenarioIndex} = details;
    finalValuesByScenario{scenarioIndex} = finalValues;
    bestIndicesByScenario{scenarioIndex} = ...
        findBestMinimizationAlgorithms(finalValues);

    convergenceFile = fullfile(outputDir,sprintf( ...
        'Convergence_Mean_Scen%d_D%d.xlsx',scenario,D));
    if exist(convergenceFile,'file') == 2
        delete(convergenceFile);
    end
    writetable(definitions,convergenceFile,'Sheet','Definitions');
    writetable(meanTable,convergenceFile,'Sheet','MeanConvergence');
    writetable(countTable,convergenceFile,'Sheet','RunCounts');
    writetable(finalTable,convergenceFile,'Sheet','FinalValues');
    files.convergence{scenarioIndex} = convergenceFile;

    fprintf('Saved Scenario %d mean convergence workbook (%d points): %s\n', ...
        scenario,numSamplePoints,convergenceFile);
    reportIncompleteRuns(finalValues,finalFEs,algNames,runs,maxFE,scenario);
end

rawPValues = [];
for scenarioIndex = 1:numScenarios
    rawPValues = [rawPValues;detailTables{scenarioIndex}.PValue]; %#ok<AGROW>
end
adjustedPValues = holmAdjust(rawPValues);
offset = 0;
for scenarioIndex = 1:numScenarios
    details = detailTables{scenarioIndex};
    numRows = height(details);
    details.HolmPValue = adjustedPValues(offset+(1:numRows));
    finalValues = finalValuesByScenario{scenarioIndex};
    for row = 1:numRows
        algorithmIndex = find(string(algNames) == details.Algorithm(row),1);
        competitor = finalValues(isfinite(finalValues(:,algorithmIndex)),algorithmIndex);
        reference = finalValues(isfinite(finalValues(:,baselineIndex)),baselineIndex);
        if isempty(competitor) || isempty(reference) || ...
                ~isfinite(details.HolmPValue(row))
            details.Sign(row) = "NA";
        else
            details.Sign(row) = string(engineeringStatsSign( ...
                competitor,reference,details.HolmPValue(row)));
        end
    end
    detailTables{scenarioIndex} = details;
    scenario = scenarioIds(scenarioIndex);
    [paperRows(scenarioIndex,:),allSigns(scenarioIndex,:)] = ...
        buildPaperScenarioRow(details,finalValues,algNames,baselineIndex,scenario);
    offset = offset + numRows;
end

paperRows{end,1} = '+/-/=/NA';
for algorithmIndex = 1:numAlgorithms
    if algorithmIndex == baselineIndex
        paperRows{end,algorithmIndex+1} = '';
    else
        signs = allSigns(:,algorithmIndex);
        paperRows{end,algorithmIndex+1} = sprintf('%d / %d / %d / %d', ...
            sum(signs == "+"),sum(signs == "-"),sum(signs == "="), ...
            sum(signs == "NA"));
    end
end
variableNames = [{'Scenario'},matlab.lang.makeValidName(algNames)];
paperTable = cell2table(paperRows,'VariableNames',variableNames);
detailTable = vertcat(detailTables{:});

files.wilcoxon = fullfile(outputDir,sprintf('Wilcoxon_Statistics_D%d.xlsx',D));
if exist(files.wilcoxon,'file') == 2
    delete(files.wilcoxon);
end
writetable(definitions,files.wilcoxon,'Sheet','Definitions');
writetable(paperTable,files.wilcoxon,'Sheet','Statistics');
writetable(detailTable,files.wilcoxon,'Sheet','Details');
formatEngineeringStatisticsWorkbook(files.wilcoxon,bestIndicesByScenario);
fprintf('Saved two-scenario Wilcoxon workbook: %s\n',files.wilcoxon);
end

function bestIndices = findBestMinimizationAlgorithms(finalValues)
algorithmMeans = mean(finalValues,1,'omitnan');
finiteMeans = algorithmMeans(isfinite(algorithmMeans));
if isempty(finiteMeans)
    bestIndices = [];
    return;
end
bestMean = min(finiteMeans);
tolerance = max(1,abs(bestMean))*1e-12;
bestIndices = find(isfinite(algorithmMeans) & ...
    abs(algorithmMeans-bestMean) <= tolerance);
end

function definitions = makeDefinitions(scenarioIds,runs,numSamplePoints)
definitions = table( ...
    ["Test";"MultiplicityCorrection";"Alternative";"Alpha";"Objective";"Scenarios"; ...
     "RunsPlanned";"ConvergencePoints";"SignMeaning"; ...
     "IncompleteCurveHandling"], ...
    ["Wilcoxon rank-sum (Mann-Whitney U)";"Holm across all scenario-comparator tests"; ...
     "Two-sided";"0.05"; ...
     "Minimization";string(mat2str(scenarioIds));string(runs); ...
     string(numSamplePoints); ...
     "+ competitor better; - competitor worse; = not significant"; ...
     "Carry the last available best-so-far value forward"], ...
    'VariableNames',{'Setting','Value'});
end

function [meanTable,countTable,finalTable,finalValues,finalFEs] = ...
    processScenario(dataDir,algNames,scenario,D,runs,maxFE,numSamplePoints)
numAlgorithms = numel(algNames);
runCurves = cell(numAlgorithms,runs);
finalValues = NaN(runs,numAlgorithms);
finalFEs = NaN(runs,numAlgorithms);

for algorithmIndex = 1:numAlgorithms
    for run = 1:runs
        sourceFile = fullfile(dataDir,sprintf('%s_Scen%d_Run%d.mat', ...
            algNames{algorithmIndex},scenario,run));
        [fes,fitness] = loadRunConvergence(sourceFile,D);
        if isempty(fes)
            continue;
        end
        runCurves{algorithmIndex,run} = [fes(:),fitness(:)];
        finalFEs(run,algorithmIndex) = fes(end);
        if hasMultipleFEs([fes(:),fitness(:)]) && fes(end) >= maxFE
            finalValues(run,algorithmIndex) = fitness(end);
        end
    end
end

allFirstFEs = cellfun(@firstFE,runCurves);
validFirstFEs = allFirstFEs(isfinite(allFirstFEs));
assert(~isempty(validFirstFEs), ...
    'No valid result curves were found for Scenario %d in %s.',scenario,dataDir);
% A one-point/incomplete result can contain only FE=maxFE.  It must not
% determine the common sampling start, otherwise all 25 requested points
% collapse to maxFE.  Use only genuine multi-point histories to determine
% the common start; single-point runs are still included (as a constant
% curve) wherever their data are available.
hasHistory = cellfun(@hasMultipleFEs,runCurves);
historyFirstFEs = allFirstFEs(hasHistory & isfinite(allFirstFEs));
if isempty(historyFirstFEs)
    startFE = min(validFirstFEs);
else
    startFE = max(historyFirstFEs);
end
if maxFE == startFE
    error('EngineeringStats:NoConvergenceHistory', ...
        ['Only FE=%d was found for Scenario %d. Genuine convergence histories ' ...
         'are required to export %d distinct sampling points.'], ...
        maxFE,scenario,numSamplePoints);
else
    uniformFEs = round(linspace(startFE,maxFE,numSamplePoints))';
    if numel(unique(uniformFEs)) ~= numSamplePoints
        uniformFEs = unique(round(linspace(startFE,maxFE,numSamplePoints)), ...
            'stable')';
        assert(numel(uniformFEs) == numSamplePoints, ...
            'Could not construct %d distinct FE samples.',numSamplePoints);
    end
end

meanConvergence = NaN(numSamplePoints,numAlgorithms);
convergenceCounts = zeros(numSamplePoints,numAlgorithms);
alignedRuns = NaN(numSamplePoints,runs,numAlgorithms);
for algorithmIndex = 1:numAlgorithms
    for run = 1:runs
        curve = runCurves{algorithmIndex,run};
        if isempty(curve)
            continue;
        end
        alignedRuns(:,run,algorithmIndex) = alignCurve(curve,uniformFEs);
    end
    values = alignedRuns(:,:,algorithmIndex);
    meanConvergence(:,algorithmIndex) = mean(values,2,'omitnan');
    convergenceCounts(:,algorithmIndex) = sum(isfinite(values),2);
end

variableNames = matlab.lang.makeUniqueStrings( ...
    matlab.lang.makeValidName(algNames,'ReplacementStyle','delete'));
meanTable = array2table([uniformFEs,meanConvergence], ...
    'VariableNames',[{'FEs'},variableNames]);
countTable = array2table([uniformFEs,convergenceCounts], ...
    'VariableNames',[{'FEs'},strcat('N_',variableNames)]);
finalTable = array2table([(1:runs)',finalValues,finalFEs], ...
    'VariableNames',[{'Run'},variableNames,strcat('FinalFE_',variableNames)]);
end

function tableValue = buildWilcoxonTable(finalValues,finalFEs,algNames, ...
    baselineIndex,maxFE)
comparisonIndices = setdiff(1:numel(algNames),baselineIndex,'stable');
numComparisons = numel(comparisonIndices);
algorithm = strings(numComparisons,1);
baseline = repmat(string(algNames{baselineIndex}),numComparisons,1);
competitorN = zeros(numComparisons,1);
baselineN = zeros(numComparisons,1);
competitorCompleted = zeros(numComparisons,1);
baselineCompleted = zeros(numComparisons,1);
competitorMean = NaN(numComparisons,1);
competitorStd = NaN(numComparisons,1);
baselineMean = NaN(numComparisons,1);
baselineStd = NaN(numComparisons,1);
medianDifference = NaN(numComparisons,1);
pValue = NaN(numComparisons,1);
signLabel = strings(numComparisons,1);

for row = 1:numComparisons
    algorithmIndex = comparisonIndices(row);
    competitor = finalValues(isfinite(finalValues(:,algorithmIndex)),algorithmIndex);
    reference = finalValues(isfinite(finalValues(:,baselineIndex)),baselineIndex);

    algorithm(row) = string(algNames{algorithmIndex});
    competitorN(row) = numel(competitor);
    baselineN(row) = numel(reference);
    competitorCompleted(row) = numel(competitor);
    baselineCompleted(row) = numel(reference);
    if isempty(competitor) || isempty(reference)
        signLabel(row) = "NA";
        continue;
    end
    competitorMean(row) = mean(competitor);
    competitorStd(row) = std(competitor);
    baselineMean(row) = mean(reference);
    baselineStd(row) = std(reference);
    medianDifference(row) = median(competitor)-median(reference);
    pValue(row) = wilcoxonRankSumP(competitor,reference);
    signLabel(row) = string(engineeringStatsSign( ...
        competitor,reference,pValue(row)));
end

tableValue = table(algorithm,baseline,competitorN,baselineN, ...
    competitorCompleted,baselineCompleted,competitorMean, ...
    competitorStd,baselineMean,baselineStd,medianDifference,pValue, ...
    signLabel,'VariableNames',{'Algorithm','Baseline','CompetitorN','BaselineN', ...
    'CompetitorCompleted','BaselineCompleted','CompetitorMean','CompetitorStd', ...
    'BaselineMean','BaselineStd','MedianDifference','PValue','Sign'});
end

function [row,signs] = buildPaperScenarioRow(details,finalValues,algNames, ...
    baselineIndex,scenario)
row = cell(1,numel(algNames)+1);
signs = repmat("",1,numel(algNames));
row{1} = sprintf('Scenario_%d',scenario);
for algorithmIndex = 1:numel(algNames)
    values = finalValues(isfinite(finalValues(:,algorithmIndex)),algorithmIndex);
    if isempty(values)
        resultText = 'N/A';
    else
        resultText = sprintf('%.4e (%.2e)',mean(values),std(values));
    end
    if algorithmIndex == baselineIndex
        row{algorithmIndex+1} = resultText;
    else
        detailRow = find(details.Algorithm == string(algNames{algorithmIndex}),1);
        signText = details.Sign(detailRow);
        row{algorithmIndex+1} = sprintf('%s %s',resultText,char(signText));
        signs(algorithmIndex) = signText;
    end
end
end

function reportIncompleteRuns(finalValues,finalFEs,algNames,runs,maxFE,scenario)
for algorithmIndex = 1:numel(algNames)
    available = sum(isfinite(finalFEs(:,algorithmIndex)));
    completed = sum(isfinite(finalValues(:,algorithmIndex)));
    if available < runs || completed < runs
        warning('Scenario %d, %s: found %d/%d runs, %d reached maxFE=%d.', ...
            scenario,algNames{algorithmIndex},available,runs,completed,maxFE);
    end
end
end

function pValue = wilcoxonRankSumP(x,y)
x = x(isfinite(x));
y = y(isfinite(y));
if isempty(x) || isempty(y)
    pValue = 1;
    return;
end

if exist('ranksum','file') == 2
    pValue = ranksum(x,y);
    return;
end

combined = [x(:);y(:)];
ranks = tiedRanks(combined);
nX = numel(x);
nY = numel(y);
uX = sum(ranks(1:nX))-nX*(nX+1)/2;
meanU = nX*nY/2;
tieCounts = groupcounts(combined);
tieAdjustment = sum(tieCounts.^3-tieCounts);
n = nX+nY;
variance = nX*nY/12*((n+1)-tieAdjustment/(n*(n-1)));
if variance <= 0
    pValue = 1;
    return;
end
z = (abs(uX-meanU)-0.5)/sqrt(variance);
pValue = min(1,erfc(abs(z)/sqrt(2)));
end

function ranks = tiedRanks(values)
[sortedValues,order] = sort(values);
sortedRanks = zeros(size(sortedValues));
index = 1;
while index <= numel(sortedValues)
    last = index;
    while last < numel(sortedValues) && sortedValues(last+1) == sortedValues(index)
        last = last+1;
    end
    sortedRanks(index:last) = mean(index:last);
    index = last+1;
end
ranks = zeros(size(values));
ranks(order) = sortedRanks;
end

function counts = groupcounts(values)
[~,~,groups] = unique(values);
counts = accumarray(groups,1);
end

function aligned = alignCurve(curve,uniformFEs)
[fes,uniqueIndices] = unique(curve(:,1),'last');
fitness = curve(uniqueIndices,2);
[fes,order] = sort(fes);
fitness = cummin(fitness(order));
aligned = NaN(numel(uniformFEs),1);
available = uniformFEs >= fes(1);
if numel(fes) == 1
    aligned(available) = fitness;
else
    aligned(available) = interp1(fes,fitness,uniformFEs(available), ...
        'previous','extrap');
end
end

function value = firstFE(curve)
if isempty(curve)
    value = NaN;
else
    value = curve(1,1);
end
end

function value = hasMultipleFEs(curve)
value = ~isempty(curve) && size(curve,1) >= 2 && ...
        numel(unique(curve(:,1))) >= 2;
end

function [fes,fitness] = loadRunConvergence(sourceFile,D)
fes = [];
fitness = [];
if exist(sourceFile,'file') ~= 2
    return;
end
try
    loaded = load(sourceFile,'result');
    if ~isfield(loaded,'result') || isempty(loaded.result)
        return;
    end
    result = loaded.result;
    if ~iscell(result)
        return;
    end
    for row = 1:size(result,1)
        if isempty(result{row,1}) || size(result,2) < 2 || isempty(result{row,2})
            continue;
        end
        currentFE = double(result{row,1}(1));
        currentFitness = populationBestObjective(result{row,2},D);
        if isfinite(currentFE) && isfinite(currentFitness)
            fes(end+1,1) = currentFE; %#ok<AGROW>
            fitness(end+1,1) = currentFitness; %#ok<AGROW>
        end
    end
    [fes,uniqueIndices] = unique(fes,'last');
    fitness = cummin(fitness(uniqueIndices));
catch errorInfo
    warning('Could not read %s: %s',sourceFile,errorInfo.message);
    fes = [];
    fitness = [];
end
end

function objective = populationBestObjective(population,D)
objective = NaN;
try
    objectives = population.objs;
    objective = min(objectives(:,1));
catch
    if isnumeric(population) && size(population,2) == D+1
        objective = min(population(:,end));
    end
end
end

function adjustedP = holmAdjust(rawP)
originalSize = size(rawP);
rawP = rawP(:);
adjustedP = NaN(size(rawP));
valid = isfinite(rawP);
if any(valid)
    values = min(max(rawP(valid),0),1);
    [sortedP,order] = sort(values,'ascend');
    m = numel(sortedP);
    stepDown = (m-(1:m)' + 1).*sortedP;
    stepDown = min(cummax(stepDown),1);
    adjusted = NaN(size(values));
    adjusted(order) = stepDown;
    adjustedP(valid) = adjusted;
end
adjustedP = reshape(adjustedP,originalSize);
end
