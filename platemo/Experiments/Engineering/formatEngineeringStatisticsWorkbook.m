function formatEngineeringStatisticsWorkbook(workbookFile,bestIndicesByScenario)
%FORMATENGINEERINGSTATISTICSWORKBOOK Bold best Statistics-sheet values.
%   Algorithm indices correspond to columns B, C, ... in the Statistics
%   sheet. Each cell entry may contain one or more tied best algorithms.

arguments
    workbookFile (1,:) char
    bestIndicesByScenario (:,1) cell
end

if ~ispc || isempty(which('actxserver'))
    warning('EngineeringStats:ExcelFormattingUnavailable', ...
        'Excel automation is unavailable; best-value bolding was skipped.');
    return;
end

excel = actxserver('Excel.Application');
excel.Visible = false;
excel.DisplayAlerts = false;
workbook = [];
try
    workbook = excel.Workbooks.Open(workbookFile);
    worksheet = workbook.Worksheets.Item('Statistics');
    for scenarioIndex = 1:numel(bestIndicesByScenario)
        algorithmIndices = bestIndicesByScenario{scenarioIndex};
        for algorithmIndex = algorithmIndices(:)'
            cellAddress = sprintf('%s%d', ...
                excelColumnName(algorithmIndex+1),scenarioIndex+1);
            cellRange = get(worksheet,'Range',cellAddress);
            set(cellRange.Font,'Bold',true);
        end
    end
    workbook.Save();
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
    name = [char(double('A')+remainder),name];
    column = floor((column-1)/26);
end
end
