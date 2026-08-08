function tests = test_DE2AcPSO_benchmark_statistics
% Unit tests for the benchmark statistics helpers.
tests = functiontests(localfunctions);
end

function testHolmAdjustment(testCase)
actual = benchmarkHolmAdjust([0.01;0.04;0.03;NaN]);
expected = [0.03;0.06;0.06;NaN];
verifyEqual(testCase,actual,expected,'AbsTol',1e-12);
end

function testVarghaDelaneyUsesMinimizationDirection(testCase)
verifyEqual(testCase,benchmarkA12([1;2],[3;4]),1,'AbsTol',1e-12);
verifyEqual(testCase,benchmarkA12([3;4],[1;2]),0,'AbsTol',1e-12);
verifyEqual(testCase,benchmarkA12([1;2],[1;2]),0.5,'AbsTol',1e-12);
end

function testResultLoaderRejectsInitializationOnlyRecord(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s'));

completeFile = fullfile(folder,'complete.mat');
result = cell(2,2);
result(:,1) = {100;1000};
metric.Min_value = [4;1];
save(completeFile,'result','metric');

failedFile = fullfile(folder,'failed.mat');
result = cell(1,2);
result{1,1} = 1000;
metric.Min_value = 4;
save(failedFile,'result','metric');

[value,completed,finalFE] = benchmarkLoadFinalObjective(completeFile,1000);
verifyEqual(testCase,value,1);
verifyTrue(testCase,completed);
verifyEqual(testCase,finalFE,1000);

[value,completed,finalFE] = benchmarkLoadFinalObjective(failedFile,1000);
verifyTrue(testCase,isnan(value));
verifyFalse(testCase,completed);
verifyEqual(testCase,finalFE,1000);

clear cleanup
end
