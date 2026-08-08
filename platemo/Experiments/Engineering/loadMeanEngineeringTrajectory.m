function info = loadMeanEngineeringTrajectory(dataDir,algName,scenario, ...
    runs,D,maxFE,startPos,endPos,numSamples)
% Load the final best individual from every run, decode each route to the
% same number of samples, and return the pointwise mean route.

info = struct('pathX',[],'pathY',[],'plotX',[],'plotY',[], ...
    'obj',NaN,'finalFE',NaN, ...
    'status','missing','files',"",'n',0,'completed',0);
allX = NaN(runs,numSamples);
allY = NaN(runs,numSamples);
objectives = NaN(runs,1);
finalFEs = NaN(runs,1);
sourceFiles = strings(runs,1);
used = 0;

for run = 1:runs
    sourceFile = fullfile(dataDir,sprintf('%s_Scen%d_Run%d.mat', ...
        algName,scenario,run));
    if exist(sourceFile,'file') ~= 2
        continue;
    end
    loaded = load(sourceFile,'result');
    if ~isfield(loaded,'result') || isempty(loaded.result) || ...
            ~iscell(loaded.result)
        continue;
    end
    validRows = find(~cellfun(@isempty,loaded.result(:,1)) & ...
        ~cellfun(@isempty,loaded.result(:,2)));
    if isempty(validRows)
        continue;
    end
    finalRow = validRows(end);
    [decs,objs] = localPopulationData(loaded.result{finalRow,2},D);
    if isempty(decs) || isempty(objs)
        continue;
    end
    [bestObjective,bestIndex] = min(objs(:,1));
    [pathX,pathY] = RobotPathPlanning.DecodeTrajectory( ...
        decs(bestIndex,:),startPos,endPos,numSamples);

    used = used+1;
    allX(used,:) = pathX;
    allY(used,:) = pathY;
    objectives(used) = bestObjective;
    finalFEs(used) = double(loaded.result{finalRow,1}(1));
    sourceFiles(used) = string(sourceFile);
end

if used == 0
    return;
end
allX = allX(1:used,:);
allY = allY(1:used,:);
objectives = objectives(1:used);
finalFEs = finalFEs(1:used);
sourceFiles = sourceFiles(1:used);
info.pathX = mean(allX,1,'omitnan');
info.pathY = mean(allY,1,'omitnan');
[info.plotX,info.plotY] = smoothMeanRoute( ...
    info.pathX,info.pathY,startPos,endPos);
info.obj = mean(objectives,'omitnan');
info.finalFE = mean(finalFEs,'omitnan');
info.n = used;
info.completed = sum(finalFEs >= maxFE);
info.files = strjoin(sourceFiles,newline);
info.status = sprintf('mean of %d/%d runs (%d completed)', ...
    used,runs,info.completed);
end

function [plotX,plotY] = smoothMeanRoute(meanX,meanY,startPos,endPos)
% Smooth only the displayed mean route.  Work in the lateral coordinate so
% progress from start to goal remains monotone and endpoints stay exact.
n = numel(meanX);
goal = endPos(:)'-startPos(:)';
routeLength = norm(goal);
forward = goal/routeLength;
lateralAxis = [-forward(2),forward(1)];
progress = linspace(0,routeLength,n)';
base = startPos(:)' + progress*forward;
meanRoute = [meanX(:),meanY(:)];
lateral = sum((meanRoute-base).*lateralAxis,2);
window = max(5,2*floor(n/18)+1);
smoothLateral = movmean(lateral,window,'Endpoints','shrink');
plotRoute = base + smoothLateral*lateralAxis;
plotRoute(1,:) = startPos(:)';
plotRoute(end,:) = endPos(:)';
plotX = plotRoute(:,1)';
plotY = plotRoute(:,2)';
end

function [decs,objs] = localPopulationData(population,D)
decs = [];
objs = [];
try
    decs = population.decs;
    objs = population.objs;
catch
    if isnumeric(population) && size(population,2) == D+1
        decs = population(:,1:D);
        objs = population(:,end);
    end
end
if isempty(decs) || isempty(objs) || size(decs,2) ~= D
    decs = [];
    objs = [];
end
end
