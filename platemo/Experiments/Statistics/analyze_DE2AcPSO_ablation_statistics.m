function statistics = analyze_DE2AcPSO_ablation_statistics(dataDir,outputDir)
% Holm-corrected ablation analysis at D = 500 using completed runs only.
if nargin < 1 || isempty(dataDir)
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    dataDir = fullfile(root,'Data');
end
if nargin < 2
    outputDir = '';
end

algorithms = {'DE2AcPSO_wo_ACDP','DE2AcPSO_wo_PDI', ...
    'DE2AcPSO_wo_RATR','DE2AcPSO'};
displayNames = {'w/o ACDP','w/o PDI','w/o RATR','DE2AcPSO'};
functionIds = [1,5,8,9,10,11,12,13];
dimension = 500;
runs = 20;
maxFE = 1000;
proposedIndex = 4;

numRows = numel(functionIds)*(proposedIndex-1);
functionColumn = zeros(numRows,1);
variantColumn = strings(numRows,1);
variantN = zeros(numRows,1);
proposedN = zeros(numRows,1);
variantMean = NaN(numRows,1);
proposedMean = NaN(numRows,1);
variantMedian = NaN(numRows,1);
proposedMedian = NaN(numRows,1);
rawP = NaN(numRows,1);
a12 = NaN(numRows,1);
row = 0;

for functionId = functionIds
    values = NaN(runs,numel(algorithms));
    for algorithmIndex = 1:numel(algorithms)
        for run = 1:runs
            fileName = sprintf('%s_SOP_F%d_M1_D%d_%d.mat', ...
                algorithms{algorithmIndex},functionId,dimension,run);
            resultFile = fullfile(dataDir,algorithms{algorithmIndex},fileName);
            [value,completed] = benchmarkLoadFinalObjective(resultFile,maxFE);
            if completed
                values(run,algorithmIndex) = value;
            end
        end
    end
    proposed = values(:,proposedIndex);
    proposed = proposed(isfinite(proposed));
    for algorithmIndex = 1:proposedIndex-1
        row = row + 1;
        variant = values(:,algorithmIndex);
        variant = variant(isfinite(variant));
        functionColumn(row) = functionId;
        variantColumn(row) = string(displayNames{algorithmIndex});
        variantN(row) = numel(variant);
        proposedN(row) = numel(proposed);
        if numel(variant) == runs && numel(proposed) == runs
            variantMean(row) = mean(variant);
            proposedMean(row) = mean(proposed);
            variantMedian(row) = median(variant);
            proposedMedian(row) = median(proposed);
            rawP(row) = benchmarkRankSumP(variant,proposed);
            a12(row) = benchmarkA12(proposed,variant);
        end
    end
end

holmP = benchmarkHolmAdjust(rawP);
signLabel = repmat("NA",numRows,1);
for i = 1:numRows
    if ~isfinite(holmP(i))
        continue;
    elseif holmP(i) >= 0.05
        signLabel(i) = "=";
    elseif variantMean(i) < proposedMean(i)
        signLabel(i) = "+";
    elseif variantMean(i) > proposedMean(i)
        signLabel(i) = "-";
    else
        signLabel(i) = "=";
    end
end

statistics = table(functionColumn,repmat(dimension,numRows,1),variantColumn, ...
    variantN,proposedN,variantMean,proposedMean,variantMedian, ...
    proposedMedian,rawP,holmP,a12,signLabel,'VariableNames', ...
    {'Function','Dimension','Variant','VariantN','DE2AcPSON','VariantMean', ...
    'DE2AcPSOMean','VariantMedian','DE2AcPSOMedian','RawP','HolmP', ...
    'A12DE2VsVariant','Sign'});

if ~isempty(outputDir)
    if exist(outputDir,'dir') ~= 7
        mkdir(outputDir);
    end
    writetable(statistics,fullfile(outputDir,'ablation_holm_comparisons.csv'));
end

variants = unique(statistics.Variant,'stable');
for i = 1:numel(variants)
    signs = statistics.Sign(statistics.Variant == variants(i));
    fprintf('%s: +/-/=/NA = %d/%d/%d/%d\n',variants(i), ...
        sum(signs == "+"),sum(signs == "-"),sum(signs == "="),sum(signs == "NA"));
end
disp(statistics(:,{'Function','Variant','RawP','HolmP','A12DE2VsVariant','Sign'}));
end
