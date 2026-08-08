function analysis = analyze_DE2AcPSO_benchmark_statistics(dataDir,outputDir)
% Recompute benchmark inference from completed PlatEMO runs only.
% Per-instance rank-sum p-values are Holm-adjusted as one benchmark family.
% Friedman analyses use instance medians on common completed blocks.

if nargin < 1 || isempty(dataDir)
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    dataDir = fullfile(root,'Data');
end
if nargin < 2
    outputDir = '';
end

algorithms = {'L2SMEA','SADEAMSS','SAMSO','GORS_SSLPSO','SHPSO','DE2AcPSO'};
displayNames = {'L2SMEA','SADEAMSS','SAMSO','GORS-SSLPSO','SHPSO','DE2AcPSO'};
functionIds = [1,5,8,9,10,11,12,13];
dimensions = [30,50,100,200,500,1000];
runs = 20;
maxFE = 1000;
proposedIndex = numel(algorithms);
competitorIndices = 1:proposedIndex-1;

numAlgorithms = numel(algorithms);
numInstances = numel(functionIds)*numel(dimensions);
valuesByInstance = cell(numInstances,1);
completedByInstance = zeros(numInstances,numAlgorithms);
instanceMedians = NaN(numInstances,numAlgorithms);
instanceFunctions = zeros(numInstances,1);
instanceDimensions = zeros(numInstances,1);

numDescriptive = numInstances*numAlgorithms;
descFunction = zeros(numDescriptive,1);
descDimension = zeros(numDescriptive,1);
descAlgorithm = strings(numDescriptive,1);
descCompleted = zeros(numDescriptive,1);
descMean = NaN(numDescriptive,1);
descStd = NaN(numDescriptive,1);
descMedian = NaN(numDescriptive,1);
descIQR = NaN(numDescriptive,1);

instanceIndex = 0;
descriptiveIndex = 0;
for functionId = functionIds
    for dimension = dimensions
        instanceIndex = instanceIndex + 1;
        instanceFunctions(instanceIndex) = functionId;
        instanceDimensions(instanceIndex) = dimension;
        values = NaN(runs,numAlgorithms);
        for algorithmIndex = 1:numAlgorithms
            for run = 1:runs
                fileName = sprintf('%s_SOP_F%d_M1_D%d_%d.mat', ...
                    algorithms{algorithmIndex},functionId,dimension,run);
                resultFile = fullfile(dataDir,algorithms{algorithmIndex},fileName);
                [value,completed] = benchmarkLoadFinalObjective(resultFile,maxFE);
                if completed
                    values(run,algorithmIndex) = value;
                end
            end

            validValues = values(isfinite(values(:,algorithmIndex)),algorithmIndex);
            completedByInstance(instanceIndex,algorithmIndex) = numel(validValues);
            descriptiveIndex = descriptiveIndex + 1;
            descFunction(descriptiveIndex) = functionId;
            descDimension(descriptiveIndex) = dimension;
            descAlgorithm(descriptiveIndex) = string(displayNames{algorithmIndex});
            descCompleted(descriptiveIndex) = numel(validValues);
            if ~isempty(validValues)
                descMean(descriptiveIndex) = mean(validValues);
                descStd(descriptiveIndex) = std(validValues);
                descMedian(descriptiveIndex) = median(validValues);
                quartiles = quantile(validValues,[0.25,0.75]);
                descIQR(descriptiveIndex) = quartiles(2)-quartiles(1);
                instanceMedians(instanceIndex,algorithmIndex) = ...
                    descMedian(descriptiveIndex);
            end
        end
        valuesByInstance{instanceIndex} = values;
    end
end

descriptive = table(descFunction,descDimension,descAlgorithm,descCompleted, ...
    descMean,descStd,descMedian,descIQR,'VariableNames', ...
    {'Function','Dimension','Algorithm','CompletedRuns','Mean','Std','Median','IQR'});

numComparisons = numInstances*numel(competitorIndices);
compInstance = zeros(numComparisons,1);
compFunction = zeros(numComparisons,1);
compDimension = zeros(numComparisons,1);
compAlgorithm = strings(numComparisons,1);
compN = zeros(numComparisons,1);
proposedN = zeros(numComparisons,1);
compMean = NaN(numComparisons,1);
proposedMean = NaN(numComparisons,1);
compMedian = NaN(numComparisons,1);
proposedMedian = NaN(numComparisons,1);
rawP = NaN(numComparisons,1);
a12 = NaN(numComparisons,1);

comparisonIndex = 0;
for i = 1:numInstances
    values = valuesByInstance{i};
    proposed = values(:,proposedIndex);
    proposed = proposed(isfinite(proposed));
    for algorithmIndex = competitorIndices
        comparisonIndex = comparisonIndex + 1;
        competitor = values(:,algorithmIndex);
        competitor = competitor(isfinite(competitor));
        compInstance(comparisonIndex) = i;
        compFunction(comparisonIndex) = instanceFunctions(i);
        compDimension(comparisonIndex) = instanceDimensions(i);
        compAlgorithm(comparisonIndex) = string(displayNames{algorithmIndex});
        compN(comparisonIndex) = numel(competitor);
        proposedN(comparisonIndex) = numel(proposed);
        if numel(competitor) == runs && numel(proposed) == runs
            compMean(comparisonIndex) = mean(competitor);
            proposedMean(comparisonIndex) = mean(proposed);
            compMedian(comparisonIndex) = median(competitor);
            proposedMedian(comparisonIndex) = median(proposed);
            rawP(comparisonIndex) = benchmarkRankSumP(competitor,proposed);
            a12(comparisonIndex) = benchmarkA12(proposed,competitor);
        end
    end
end

holmP = benchmarkHolmAdjust(rawP);
signLabel = repmat("NA",numComparisons,1);
for i = 1:numComparisons
    if ~isfinite(holmP(i))
        continue;
    end
    if holmP(i) >= 0.05
        signLabel(i) = "=";
    elseif compMean(i) < proposedMean(i)
        signLabel(i) = "+";
    elseif compMean(i) > proposedMean(i)
        signLabel(i) = "-";
    else
        signLabel(i) = "=";
    end
end

comparisons = table(compInstance,compFunction,compDimension,compAlgorithm, ...
    compN,proposedN,compMean,proposedMean,compMedian,proposedMedian, ...
    rawP,holmP,a12,signLabel, ...
    'VariableNames',{'Instance','Function','Dimension','Competitor', ...
    'CompetitorN','DE2AcPSON','CompetitorMean','DE2AcPSOMean', ...
    'CompetitorMedian','DE2AcPSOMedian','RawP','HolmP', ...
    'A12DE2VsCompetitor','Sign'});

counts = buildCounts(comparisons,dimensions);
globalStatistics = buildGlobalStatistics(valuesByInstance,instanceMedians, ...
    completedByInstance,comparisons,displayNames,runs,proposedIndex);

analysis = struct();
analysis.settings = struct('Algorithms',{displayNames},'Functions',functionIds, ...
    'Dimensions',dimensions,'Runs',runs,'MaxFE',maxFE, ...
    'PerInstanceHolmFamilySize',sum(isfinite(rawP)));
analysis.descriptive = descriptive;
analysis.comparisons = comparisons;
analysis.counts = counts;
analysis.global = globalStatistics;

if ~isempty(outputDir)
    if exist(outputDir,'dir') ~= 7
        mkdir(outputDir);
    end
    writetable(descriptive,fullfile(outputDir,'benchmark_descriptive_statistics.csv'));
    writetable(comparisons,fullfile(outputDir,'benchmark_holm_comparisons.csv'));
    writetable(counts,fullfile(outputDir,'benchmark_sign_counts.csv'));
    writetable(globalStatistics,fullfile(outputDir,'benchmark_global_statistics.csv'));
    save(fullfile(outputDir,'benchmark_statistics.mat'),'analysis');
end

fprintf('Completed Holm family: %d comparisons.\n',sum(isfinite(rawP)));
disp(counts);
disp(globalStatistics);
end

function counts = buildCounts(comparisons,dimensions)
groupNames = ["Low-to-medium";"High";"All"];
groupMasks = {ismember(comparisons.Dimension,dimensions(1:3)), ...
    ismember(comparisons.Dimension,dimensions(4:6)),true(height(comparisons),1)};
competitors = unique(comparisons.Competitor,'stable');
numRows = numel(groupNames)*numel(competitors);
group = strings(numRows,1);
competitor = strings(numRows,1);
better = zeros(numRows,1);
worse = zeros(numRows,1);
noDifference = zeros(numRows,1);
notAvailable = zeros(numRows,1);
row = 0;
for groupIndex = 1:numel(groupNames)
    for competitorIndex = 1:numel(competitors)
        row = row + 1;
        mask = groupMasks{groupIndex} & ...
            comparisons.Competitor == competitors(competitorIndex);
        signs = comparisons.Sign(mask);
        group(row) = groupNames(groupIndex);
        competitor(row) = competitors(competitorIndex);
        better(row) = sum(signs == "+");
        worse(row) = sum(signs == "-");
        noDifference(row) = sum(signs == "=");
        notAvailable(row) = sum(signs == "NA");
    end
end
counts = table(group,competitor,better,worse,noDifference,notAvailable, ...
    'VariableNames',{'Group','Competitor','BetterThanDE2','WorseThanDE2', ...
    'NoDifference','NotAvailable'});
end

function globalStatistics = buildGlobalStatistics(valuesByInstance,medians, ...
    completed,comparisons,displayNames,runs,proposedIndex)
families = { ...
    struct('Name',"Six algorithms, complete cases",'Indices',1:6), ...
    struct('Name',"Four algorithms, all dimensions",'Indices',[2,4,5,6])};

familyColumn = strings(0,1);
instancesColumn = zeros(0,1);
algorithmColumn = strings(0,1);
averageRankColumn = zeros(0,1);
friedmanChiSquareColumn = zeros(0,1);
friedmanDFColumn = zeros(0,1);
friedmanPColumn = zeros(0,1);
kendallWColumn = zeros(0,1);
holmPColumn = NaN(0,1);
medianA12Column = NaN(0,1);

for familyIndex = 1:numel(families)
    family = families{familyIndex};
    instanceMask = all(completed(:,family.Indices) == runs,2);
    data = medians(instanceMask,family.Indices);
    ranks = rankRows(data);
    [friedmanP,friedmanChiSquare,friedmanDF] = runFriedman(data);
    kendallW = friedmanChiSquare/(size(data,1)*(numel(family.Indices)-1));
    averageRanks = mean(ranks,1);
    proposedPosition = find(family.Indices == proposedIndex,1);
    comparisonPositions = setdiff(1:numel(family.Indices),proposedPosition,'stable');
    postHocRawP = NaN(numel(comparisonPositions),1);
    for i = 1:numel(comparisonPositions)
        postHocRawP(i) = pairedRankP( ...
            ranks(:,comparisonPositions(i)),ranks(:,proposedPosition));
    end
    postHocHolmP = benchmarkHolmAdjust(postHocRawP);

    selectedInstances = find(instanceMask);
    for position = 1:numel(family.Indices)
        algorithmIndex = family.Indices(position);
        familyColumn(end+1,1) = family.Name; %#ok<AGROW>
        instancesColumn(end+1,1) = size(data,1); %#ok<AGROW>
        algorithmColumn(end+1,1) = string(displayNames{algorithmIndex}); %#ok<AGROW>
        averageRankColumn(end+1,1) = averageRanks(position); %#ok<AGROW>
        friedmanChiSquareColumn(end+1,1) = friedmanChiSquare; %#ok<AGROW>
        friedmanDFColumn(end+1,1) = friedmanDF; %#ok<AGROW>
        friedmanPColumn(end+1,1) = friedmanP; %#ok<AGROW>
        kendallWColumn(end+1,1) = kendallW; %#ok<AGROW>
        if algorithmIndex ~= proposedIndex
            postHocIndex = find(comparisonPositions == position,1);
            holmPColumn(end+1,1) = postHocHolmP(postHocIndex); %#ok<AGROW>
            mask = ismember(comparisons.Instance,selectedInstances) & ...
                comparisons.Competitor == string(displayNames{algorithmIndex});
            effects = comparisons.A12DE2VsCompetitor(mask);
            effects = effects(isfinite(effects));
            medianA12Column(end+1,1) = median(effects); %#ok<AGROW>
        else
            holmPColumn(end+1,1) = NaN; %#ok<AGROW>
            medianA12Column(end+1,1) = NaN; %#ok<AGROW>
        end
    end
end

globalStatistics = table(familyColumn,instancesColumn,algorithmColumn, ...
    averageRankColumn,friedmanChiSquareColumn,friedmanDFColumn, ...
    friedmanPColumn,kendallWColumn,holmPColumn,medianA12Column, ...
    'VariableNames',{'Family','Instances','Algorithm','AverageRank', ...
    'FriedmanChiSquare','FriedmanDF','FriedmanP','KendallW', ...
    'HolmPVsDE2','MedianA12DE2VsCompetitor'});
end

function ranks = rankRows(data)
ranks = NaN(size(data));
for row = 1:size(data,1)
    [sortedValues,order] = sort(data(row,:),'ascend');
    sortedRanks = zeros(size(sortedValues));
    first = 1;
    while first <= numel(sortedValues)
        last = first;
        while last < numel(sortedValues) && ...
                sortedValues(last+1) == sortedValues(first)
            last = last + 1;
        end
        sortedRanks(first:last) = mean(first:last);
        first = last + 1;
    end
    ranks(row,order) = sortedRanks;
end
end

function [pValue,chiSquare,df] = runFriedman(data)
if exist('friedman','file') ~= 2
    error('BenchmarkStatistics:FriedmanUnavailable', ...
        'MATLAB Statistics and Machine Learning Toolbox is required.');
end
[pValue,anovaTable] = friedman(data,1,'off');
chiSquare = anovaTable{2,5};
df = anovaTable{2,3};
end

function pValue = pairedRankP(x,y)
if exist('signrank','file') ~= 2
    error('BenchmarkStatistics:SignRankUnavailable', ...
        'MATLAB Statistics and Machine Learning Toolbox is required.');
end
if all(x == y)
    pValue = 1;
else
    pValue = signrank(x,y,'tail','both');
end
end
