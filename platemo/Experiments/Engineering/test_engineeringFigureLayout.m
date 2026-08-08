function tests = test_engineeringFigureLayout
%TEST_ENGINEERINGFIGURELAYOUT Regression tests for publication figure spacing.
tests = functiontests(localfunctions);
end

function testLegendDoesNotOverlapBottomAxes(testCase)
[axesPositions,legendPosition] = engineeringFigureLayout();

bottomAxes = axesPositions(4:6,:);
legendTop = legendPosition(2) + legendPosition(4);
bottomAxesBottom = min(bottomAxes(:,2));

verifyGreaterThanOrEqual(testCase,bottomAxesBottom-legendTop,0.04);
end

function testAxesStayInsideFigure(testCase)
[axesPositions,legendPosition] = engineeringFigureLayout();
allPositions = [axesPositions; legendPosition];

verifySize(testCase,axesPositions,[6 4]);
verifyGreaterThanOrEqual(testCase,min(allPositions(:)),0);
verifyLessThanOrEqual(testCase,max(allPositions(:,1)+allPositions(:,3)),1);
verifyLessThanOrEqual(testCase,max(allPositions(:,2)+allPositions(:,4)),1);
end
function testRowsHaveRoomForLabels(testCase)
[axesPositions,~] = engineeringFigureLayout();
bottomRowTop = max(axesPositions(4:6,2)+axesPositions(4:6,4));
topRowBottom = min(axesPositions(1:3,2));

verifyGreaterThanOrEqual(testCase,topRowBottom-bottomRowTop,0.10);
end
function testExportedPdfUsesTimesNewRoman(testCase)
experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
figureDir = fullfile(rootDir,'Data','DE2AcPSO_PathCost','Figures');

for scenario = 1:2
    pdfFile = fullfile(figureDir,sprintf( ...
        'Trajectory_Comparison_Scen%d_D500.pdf',scenario));
    [status,fontReport] = system(sprintf('pdffonts "%s"',pdfFile));

    verifyEqual(testCase,status,0);
    verifyTrue(testCase,contains(fontReport,'TimesNewRoman'));
    verifyFalse(testCase,contains(fontReport,'Cascadia'));
end
end
