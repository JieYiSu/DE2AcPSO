clear; clc; close all;

% Engineering trajectory comparison for the synthetic path-cost study.
% The optimization variables are two-dimensional control points. The third
% plotting coordinate is the threat-field value plus a visual clearance;
% it is not an independently optimized altitude.

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
addpath(genpath(rootDir));

scenarioIds = [1 2];
runs = 20;
D = 500;
maxFE = 1000;
numConvergencePoints = 25;
baselineIndex = 6;
refreshBestCache = false;
figureOptions = engineeringFigureOptions();
if strcmpi(getenv('DE2ACPSO_AUTOSAVE_FIGURES'),'1')
    figureOptions.autoSave = true;
    figureOptions.closeAfterSave = true;
end
problemVersion = 'synthetic-path-cost-v2';
experimentFolder = 'DE2AcPSO_PathCost';

algNames = {'L2SMEA','SADEAMSS','SAMSO','GORS_SSLPSO','SHPSO','DE2AcPSO'};
displayNames = {'L2SMEA','SADEAMSS','SAMSO','GORS-SSLPSO','SHPSO','DE2AcPSO'};
% Paper-consistent palette. L2SMEA and SAMSO use the two unused colors in
% the same muted palette because they have no completed D >= 500 curves in
% the manuscript figures.
algorithmColors = [0.929 0.694 0.125; ... % L2SMEA: yellow
                   0.960 0.640 0.780; ... % SADEAMSS: pink
                   0.850 0.325 0.098; ... % SAMSO: orange
                   0.510 0.810 0.910; ... % GORS_SSLPSO: light blue
                   0.360 0.450 0.760; ... % SHPSO: blue-violet
                   0.130 0.680 0.320];    % DE2AcPSO: green
comparisonColors = algorithmColors(1:5,:);
baselineColor = algorithmColors(baselineIndex,:);

dataDir = fullfile(rootDir,'Data',experimentFolder);
figureDir = fullfile(dataDir,'Figures');
statisticsDir = fullfile(dataDir,'Statistics');
if ~exist(figureDir,'dir')
    mkdir(figureDir);
end
if ~exist(statisticsDir,'dir')
    mkdir(statisticsDir);
end

sceneFile = fullfile(dataDir,'ScenPos.mat');
assert(exist(sceneFile,'file') == 2, ...
    'ScenPos.mat was not found. Run main.m once to create the shared scene.');
sceneData = load(sceneFile,'ScenPos');
assert(size(sceneData.ScenPos,1) >= max(scenarioIds), ...
    'ScenPos.mat does not contain all requested scenarios.');
for scenario = scenarioIds
    assert(~isempty(sceneData.ScenPos{scenario,1}) && ...
           ~isempty(sceneData.ScenPos{scenario,2}), ...
           'Scenario %d has no saved start/end positions.',scenario);
end

statisticsFiles = Export_Engineering_Statistics(dataDir,statisticsDir,algNames, ...
    baselineIndex,scenarioIds,D,runs,maxFE,numConvergencePoints); 

for scenario = scenarioIds
startPos = sceneData.ScenPos{scenario,1};
endPos = sceneData.ScenPos{scenario,2};

cacheFile = fullfile(figureDir,sprintf('MeanTrajectoryCache_Scen%d_D%d.mat',scenario,D));
cacheKey = struct('scenario',scenario,'runs',runs,'D',D,'maxFE',maxFE, ...
                  'problemVersion',problemVersion,'version',5);
cacheIsValid = false;
if ~refreshBestCache && exist(cacheFile,'file') == 2
    cached = load(cacheFile,'meanTrajectory','cacheKey');
    cacheIsValid = isfield(cached,'meanTrajectory') && isfield(cached,'cacheKey') && ...
                   isequal(cached.cacheKey,cacheKey);
end
if cacheIsValid
    meanTrajectory = cached.meanTrajectory;
    fprintf('Loaded cached mean trajectories: %s\n',cacheFile);
else
    meanTrajectory = repmat(struct('pathX',[],'pathY',[],'plotX',[], ...
        'plotY',[],'obj',NaN, ...
        'finalFE',NaN,'status','missing','files',"",'n',0,'completed',0), ...
                  numel(algNames),1);
    for a = 1:numel(algNames)
        meanTrajectory(a) = loadMeanEngineeringTrajectory(dataDir,algNames{a}, ...
            scenario,runs,D,maxFE,startPos,endPos,350);
    end
    save(cacheFile,'meanTrajectory','cacheKey');
end
for a = 1:numel(algNames)
    fprintf('%-14s  %-34s  mean FE=%7.1f  mean cost=%s\n', ...
        algNames{a},meanTrajectory(a).status,meanTrajectory(a).finalFE, ...
        formatCost(meanTrajectory(a).obj));
end

baseline = meanTrajectory(baselineIndex);
assert(~isempty(baseline.pathX), ...
    'No DE2AcPSO trajectory is available for Scenario %d.',scenario);

gridAxis = linspace(-100,100,91);
[XGrid,YGrid] = meshgrid(gridAxis,gridAxis);
ZGrid = RobotPathPlanning.Get_Obstacle_Cost(XGrid,YGrid,scenario);
penaltyThreshold = RobotPathPlanning.GetCollisionThreshold(scenario);
zRange = max(ZGrid(:)) - min(ZGrid(:));
visualOffset = max(2,0.035*zRange);
zLimits = [min(ZGrid(:)), max(ZGrid(:)) + 3*visualOffset];

baseX = baseline.plotX;
baseY = baseline.plotY;
baseZ = RobotPathPlanning.Get_Obstacle_Cost(baseX,baseY,scenario) + visualOffset;

fig = figure('Color','w','Units','pixels', ...
    'Position',figureOptions.figurePosition,'Visible','on');
fig.WindowState = figureOptions.windowState;
[axesPositions,legendBand] = engineeringFigureLayout();
legendHandles = gobjects(numel(algNames)+3,1);
legendLabels = [displayNames,{'Start','Goal','Penalty threshold'}];

% One three-dimensional reference view avoids repeating the same threat
% surface in every pairwise panel.
ax3 = axes(fig,'Position',axesPositions(1,:));
hold(ax3,'on');
surf(ax3,XGrid,YGrid,ZGrid,'EdgeColor','none','FaceAlpha',0.78, ...
    'HandleVisibility','off');
shading(ax3,'interp');
contour3(ax3,XGrid,YGrid,ZGrid,[penaltyThreshold penaltyThreshold], ...
    'k--','LineWidth',1.5,'HandleVisibility','off');
plot3(ax3,baseX,baseY,baseZ,'Color',baselineColor,'LineWidth',3.6, ...
    'HandleVisibility','off');
startZ = RobotPathPlanning.Get_Obstacle_Cost( ...
    startPos(1),startPos(2),scenario) + 1.7*visualOffset;
endZ = RobotPathPlanning.Get_Obstacle_Cost( ...
    endPos(1),endPos(2),scenario) + 1.7*visualOffset;
scatter3(ax3,startPos(1),startPos(2),startZ,110,[0.10 0.75 0.15], ...
    'filled','p','MarkerEdgeColor','k','HandleVisibility','off');
scatter3(ax3,endPos(1),endPos(2),endZ,110,[0.95 0.15 0.65], ...
    'filled','p','MarkerEdgeColor','k','HandleVisibility','off');
title(ax3,'DE2AcPSO on threat surface','Interpreter','none', ...
    'FontName','Times New Roman','FontSize',16,'FontWeight','bold');
xlabel(ax3,'X','FontName','Times New Roman');
ylabel(ax3,'Y','FontName','Times New Roman');
zlabel(ax3,'Threat cost','FontName','Times New Roman');
xlim(ax3,[-100 100]); ylim(ax3,[-100 100]); zlim(ax3,zLimits);
view(ax3,43,31); grid(ax3,'on'); box(ax3,'on');
xticks(ax3,[-100 0 100]);
xticklabels(ax3,{'-100','0','100'});
yticks(ax3,[-100 100]);
yticklabels(ax3,{'','100'});
set(ax3,'FontName','Times New Roman','FontSize',14,'LineWidth',0.9, ...
    'SortMethod','childorder','Color',[0.98 0.98 0.98]);
colormap(ax3,parula(256));

for k = 1:numel(algNames)
    legendHandles(k) = plot3(ax3,NaN,NaN,NaN,'Color',algorithmColors(k,:), ...
        'LineWidth',3.0,'DisplayName',displayNames{k});
end
legendHandles(end-2) = plot3(ax3,NaN,NaN,NaN,'LineStyle','none', ...
    'Marker','p','MarkerSize',9,'MarkerFaceColor',[0.10 0.75 0.15], ...
    'MarkerEdgeColor','k','DisplayName','Start');
legendHandles(end-1) = plot3(ax3,NaN,NaN,NaN,'LineStyle','none', ...
    'Marker','p','MarkerSize',9,'MarkerFaceColor',[0.95 0.15 0.65], ...
    'MarkerEdgeColor','k','DisplayName','Goal');
legendHandles(end) = plot3(ax3,NaN,NaN,NaN,'Color','k', ...
    'LineStyle','--','LineWidth',1.5,'DisplayName','Penalty threshold');

% Five larger planar panels provide the pairwise route comparisons.
for a = 1:baselineIndex-1
    if ~isempty(meanTrajectory(a).pathX)
        pathX = meanTrajectory(a).plotX;
        pathY = meanTrajectory(a).plotY;
    else
        pathX = [];
        pathY = [];
    end

    ax2 = axes(fig,'Position',axesPositions(a+1,:));
    hold(ax2,'on');
    contourf(ax2,XGrid,YGrid,ZGrid,28,'LineColor','none', ...
        'HandleVisibility','off');
    contour(ax2,XGrid,YGrid,ZGrid,[penaltyThreshold penaltyThreshold], ...
        'k--','LineWidth',1.5,'HandleVisibility','off');
    plot(ax2,baseX,baseY,'Color',baselineColor,'LineWidth',3.6, ...
        'HandleVisibility','off');
    if ~isempty(pathX)
        plot(ax2,pathX,pathY,'Color',comparisonColors(a,:), ...
            'LineWidth',3.2,'HandleVisibility','off');
    else
        text(ax2,0,0,'No saved trajectory','HorizontalAlignment','center', ...
            'FontName','Times New Roman','FontSize',14,'FontWeight','bold', ...
            'Color',[0.45 0 0]);
    end
    scatter(ax2,startPos(1),startPos(2),90,[0.10 0.75 0.15], ...
        'filled','p','MarkerEdgeColor','k','HandleVisibility','off');
    scatter(ax2,endPos(1),endPos(2),90,[0.95 0.15 0.65], ...
        'filled','p','MarkerEdgeColor','k','HandleVisibility','off');
    title(ax2,sprintf('%s vs DE2AcPSO',displayNames{a}), ...
        'Interpreter','none','FontName','Times New Roman','FontSize',16, ...
        'FontWeight','bold');
    xlabel(ax2,'X','FontName','Times New Roman');
    ylabel(ax2,'Y','FontName','Times New Roman');
    axis(ax2,'equal'); xlim(ax2,[-100 100]); ylim(ax2,[-100 100]);
    xticks(ax2,[-100 -50 50 100]);
    yticks(ax2,[-100 -50 0 50 100]);
    xticklabels(ax2,{'-100','-50','50','100'});
    yticklabels(ax2,{'-100','-50','0','50','100'});
    box(ax2,'on'); grid(ax2,'on');
    set(ax2,'FontName','Times New Roman','FontSize',14,'LineWidth',0.9, ...
        'Layer','top','TickLabelInterpreter','none', ...
        'Color',[0.98 0.98 0.98]);
    colormap(ax2,parula(256));
end

globalLegend = legend(ax3,legendHandles,legendLabels, ...
    'Orientation','horizontal','NumColumns',5, ...
    'Interpreter','none','FontName','Times New Roman','FontSize',13, ...
    'Box','off','Color','none');
globalLegend.Units = 'normalized';
globalLegend.AutoUpdate = 'off';

drawnow;
legendPosition = globalLegend.Position;
legendPosition(1) = legendBand(1) + (legendBand(3)-legendPosition(3))/2;
legendPosition(2) = legendBand(2) + (legendBand(4)-legendPosition(4))/2;
globalLegend.Position = legendPosition;
drawnow;

summary = table(string(algNames(:)),[meanTrajectory.obj]', ...
    [meanTrajectory.finalFE]',[meanTrajectory.n]',[meanTrajectory.completed]', ...
    string({meanTrajectory.status})',string({meanTrajectory.files})', ...
    'VariableNames',{'Algorithm','MeanFinalCost','MeanFinalFE','RunsUsed', ...
    'CompletedRuns','Status','SourceFiles'});
writetable(summary,fullfile(statisticsDir,sprintf( ...
    'Trajectory_Summary_Scen%d_D%d.xlsx',scenario,D)));

if figureOptions.autoSave
    pngFile = fullfile(figureDir,sprintf( ...
        'Trajectory_Comparison_Scen%d_D%d.png',scenario,D));
    exportgraphics(fig,pngFile,'Resolution',1200);
    pdfFile = fullfile(figureDir,sprintf( ...
        'Trajectory_Comparison_Scen%d_D%d.pdf',scenario,D));
    exportEngineeringPdf(fig,pdfFile);
    fprintf('Saved comparison figures:\n  %s\n  %s\n',pngFile,pdfFile);
    if figureOptions.closeAfterSave
        close(fig);
    end
else
    fprintf(['Scenario %d figure is open for manual adjustment and saving.\n' ...
        'Use File > Save As, or call exportgraphics(gcf,fileName,' ...
        '''Resolution'',1200).\n'],scenario);
end
end

function textValue = formatCost(value)
    if isfinite(value)
        textValue = sprintf('%.3e',value);
    else
        textValue = 'N/A';
    end
end
