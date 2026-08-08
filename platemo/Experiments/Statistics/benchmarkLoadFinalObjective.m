function [value,completed,finalFE,numHistory] = benchmarkLoadFinalObjective(file,maxFE)
% Load a PlatEMO result and reject initialization-only records.
value = NaN;
completed = false;
finalFE = NaN;
numHistory = 0;
if exist(file,'file') ~= 2
    return;
end

saved = load(file,'result','metric');
if ~isfield(saved,'result') || ~isfield(saved,'metric') || ...
        ~isfield(saved.metric,'Min_value')
    return;
end

result = saved.result;
if iscell(result)
    if isempty(result)
        return;
    end
    feValues = NaN(size(result,1),1);
    for i = 1:size(result,1)
        candidate = result{i,1};
        if isnumeric(candidate) && ~isempty(candidate)
            feValues(i) = candidate(end);
        end
    end
else
    if isempty(result)
        return;
    end
    feValues = result(:,1);
end

objectiveValues = saved.metric.Min_value(:);
numHistory = min(numel(feValues),numel(objectiveValues));
if numHistory == 0
    return;
end
feValues = feValues(1:numHistory);
objectiveValues = objectiveValues(1:numHistory);
valid = isfinite(feValues) & isfinite(objectiveValues);
feValues = feValues(valid);
objectiveValues = objectiveValues(valid);
numHistory = numel(feValues);
if numHistory == 0
    return;
end

finalFE = max(feValues);
value = objectiveValues(end);
completed = numHistory >= 2 && finalFE >= maxFE;
if ~completed
    value = NaN;
end
end
