function tests = test_engineeringFigureOptions
tests = functiontests(localfunctions);
end

function testDefaultsLeaveLargeInteractiveFigureOpenForManualSave(testCase)
options = engineeringFigureOptions();
verifyFalse(testCase,options.autoSave);
verifyFalse(testCase,options.closeAfterSave);
verifyEqual(testCase,options.windowState,'maximized');
verifyGreaterThan(testCase,options.layoutPosition(2), ...
    options.legendBottom+0.04);
verifyGreaterThanOrEqual(testCase,options.figurePosition(3),1500);
verifyGreaterThanOrEqual(testCase,options.figurePosition(4),1100);
end

function testLegendUsesNaturalWidthAndIsCenteredInFigure(testCase)
options = engineeringFigureOptions();
naturalPosition = [0.08 0.42 0.64 0.05];
centeredPosition = centerEngineeringLegendPosition(naturalPosition,options);

verifyEqual(testCase,centeredPosition(1)+centeredPosition(3)/2,0.5, ...
    'AbsTol',1e-12);
verifyEqual(testCase,centeredPosition(2),options.legendBottom, ...
    'AbsTol',1e-12);
verifyEqual(testCase,centeredPosition(3:4),naturalPosition(3:4), ...
    'AbsTol',1e-12);
end
