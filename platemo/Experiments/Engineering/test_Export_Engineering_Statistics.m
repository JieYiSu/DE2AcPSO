function tests = test_Export_Engineering_Statistics
% Regression tests for the engineering statistics export.
tests = functiontests(localfunctions);
end

function testExportsTwoScenariosAsXlsxWithTwentyFivePoints(testCase)
fixtureDir = tempname;
outputDir = tempname;
mkdir(fixtureDir);
mkdir(outputDir);
cleaner = onCleanup(@()cleanupFixture(fixtureDir,outputDir)); %#ok<NASGU>

algorithms = {'COMP','DE2AcPSO'};
for scenario = 1:2
    for run = 1:20
        if scenario == 1
            competitorOffset = 0;
            baselineOffset = 10;
        else
            competitorOffset = 20;
            baselineOffset = 0;
        end
        result = {[10], struct('objs',run + competitorOffset); ...
            [50], struct('objs',run/2 + competitorOffset); ...
            [100], struct('objs',run/4 + competitorOffset)}; %#ok<NASGU>
        save(fullfile(fixtureDir,sprintf('COMP_Scen%d_Run%d.mat', ...
            scenario,run)),'result');

        result = {[10], struct('objs',run + baselineOffset); ...
            [50], struct('objs',run/2 + baselineOffset); ...
            [100], struct('objs',run/4 + baselineOffset)}; %#ok<NASGU>
        save(fullfile(fixtureDir,sprintf('DE2AcPSO_Scen%d_Run%d.mat', ...
            scenario,run)),'result');
    end
end

Export_Engineering_Statistics(fixtureDir,outputDir,algorithms,2,[1 2],1,20,100,25);
meanTable1 = readtable(fullfile(outputDir,'Convergence_Mean_Scen1_D1.xlsx'), ...
    'Sheet','MeanConvergence');
meanTable2 = readtable(fullfile(outputDir,'Convergence_Mean_Scen2_D1.xlsx'), ...
    'Sheet','MeanConvergence');
statistics = readtable(fullfile(outputDir,'Wilcoxon_Statistics_D1.xlsx'), ...
    'Sheet','Statistics');
details = readtable(fullfile(outputDir,'Wilcoxon_Statistics_D1.xlsx'), ...
    'Sheet','Details');

verifySize(testCase,meanTable1,[25 3]);
verifySize(testCase,meanTable2,[25 3]);
verifyEqual(testCase,meanTable1.FEs(1),10);
verifyEqual(testCase,meanTable1.FEs(end),100);
verifyEqual(testCase,height(statistics),3);
verifyEqual(testCase,string(statistics.Scenario), ...
    ["Scenario_1";"Scenario_2";"+/-/=/NA"]);
verifyEqual(testCase,string(statistics.COMP(3)),"1 / 1 / 0 / 0");
verifyEqual(testCase,details.CompetitorN,[20;20]);
verifyEqual(testCase,details.BaselineN,[20;20]);
verifyTrue(testCase,all(isfinite(details.HolmPValue)));
verifyEqual(testCase,string(details.Sign),["+";"-"]);
verifyEqual(testCase,exist(fullfile(outputDir,'Wilcoxon_Scen1_D1.csv'),'file'),0);

wilcoxonFile = fullfile(outputDir,'Wilcoxon_Statistics_D1.xlsx');
assumeTrue(testCase,ispc && ~isempty(which('actxserver')), ...
    'Excel automation is required to verify workbook font formatting.');
verifyTrue(testCase,readExcelCellBold(wilcoxonFile,'Statistics',2,2));
verifyFalse(testCase,readExcelCellBold(wilcoxonFile,'Statistics',2,3));
verifyFalse(testCase,readExcelCellBold(wilcoxonFile,'Statistics',3,2));
verifyTrue(testCase,readExcelCellBold(wilcoxonFile,'Statistics',3,3));
end

function testSignLabelsUseCompetitorRelativeToBaseline(testCase)
verifyEqual(testCase,engineeringStatsSign((1:20)',(11:30)',0.01),'+');
verifyEqual(testCase,engineeringStatsSign((11:30)',(1:20)',0.01),'-');
verifyEqual(testCase,engineeringStatsSign((1:20)',(1:20)',0.05),'=');
end

function testSinglePointRunDoesNotCollapseAllSamplingFEsToMaxFE(testCase)
fixtureDir = tempname;
outputDir = tempname;
mkdir(fixtureDir);
mkdir(outputDir);
cleaner = onCleanup(@()cleanupFixture(fixtureDir,outputDir)); %#ok<NASGU>

algorithms = {'COMP','DE2AcPSO'};
for run = 1:20
    result = {[100], struct('objs',100-run); ...
              [500], struct('objs',50-run/2); ...
              [1000],struct('objs',25-run/4)}; %#ok<NASGU>
    save(fullfile(fixtureDir,sprintf('DE2AcPSO_Scen1_Run%d.mat',run)),'result');

    if run == 1
        % Reproduces an initialization-only/incomplete file whose first
        % and only saved point is maxFE.
        result = {[1000],struct('objs',80)}; %#ok<NASGU>
    else
        result = {[100], struct('objs',120-run); ...
                  [500], struct('objs',70-run/2); ...
                  [1000],struct('objs',35-run/4)}; %#ok<NASGU>
    end
    save(fullfile(fixtureDir,sprintf('COMP_Scen1_Run%d.mat',run)),'result');
end

Export_Engineering_Statistics(fixtureDir,outputDir,algorithms,2,1,1,20,1000,25);
meanTable = readtable(fullfile(outputDir,'Convergence_Mean_Scen1_D1.xlsx'), ...
    'Sheet','MeanConvergence');
countTable = readtable(fullfile(outputDir,'Convergence_Mean_Scen1_D1.xlsx'), ...
    'Sheet','RunCounts');
details = readtable(fullfile(outputDir,'Wilcoxon_Statistics_D1.xlsx'), ...
    'Sheet','Details');

verifyEqual(testCase,height(meanTable),25);
verifyEqual(testCase,meanTable.FEs(1),100);
verifyEqual(testCase,meanTable.FEs(end),1000);
verifyEqual(testCase,numel(unique(meanTable.FEs)),25);
verifyGreaterThan(testCase,range(meanTable.COMP),0);
verifyGreaterThan(testCase,range(meanTable.DE2AcPSO),0);
verifyEqual(testCase,countTable.N_COMP(1),19);
verifyEqual(testCase,countTable.N_COMP(end),20);
verifyEqual(testCase,details.CompetitorN,19);
verifyEqual(testCase,details.CompetitorCompleted,19);
verifyEqual(testCase,details.BaselineN,20);
end

function cleanupFixture(varargin)
for i = 1:nargin
    if exist(varargin{i},'dir') == 7
        rmdir(varargin{i},'s');
    end
end
end

function isBold = readExcelCellBold(workbookFile,sheetName,row,column)
excel = actxserver('Excel.Application');
excel.Visible = false;
excel.DisplayAlerts = false;
workbook = [];
try
    workbook = excel.Workbooks.Open(workbookFile);
    worksheet = workbook.Worksheets.Item(sheetName);
    cellAddress = sprintf('%s%d',excelColumnName(column),row);
    cellRange = get(worksheet,'Range',cellAddress);
    isBold = logical(get(cellRange.Font,'Bold'));
    workbook.Close(false);
    workbook = [];
    excel.Quit();
catch errorInfo
    if ~isempty(workbook)
        workbook.Close(false);
    end
    excel.Quit();
    rethrow(errorInfo);
end
end

function name = excelColumnName(column)
name = '';
while column > 0
    remainder = mod(column-1,26);
    name = [char(double('A')+remainder),name]; %#ok<AGROW>
    column = floor((column-1)/26);
end
end
