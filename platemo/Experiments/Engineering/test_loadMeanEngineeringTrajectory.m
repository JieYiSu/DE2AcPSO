function tests = test_loadMeanEngineeringTrajectory
addpath(genpath(fileparts(mfilename('fullpath'))));
tests = functiontests(localfunctions);
end

function testReturnsPointwiseMeanOfTwentyDecodedFinalRoutes(testCase)
fixtureDir = tempname;
mkdir(fixtureDir);
cleaner = onCleanup(@()rmdir(fixtureDir,'s')); %#ok<NASGU>
startPos = [-80 -80];
endPos = [80 80];
numSamples = 41;
expectedX = zeros(20,numSamples);
expectedY = zeros(20,numSamples);

for run = 1:20
    dec = [-40, -30+run/2, 10, 20-run/4];
    result = {1000,struct('decs',dec,'objs',run)}; %#ok<NASGU>
    save(fullfile(fixtureDir,sprintf('ALG_Scen1_Run%d.mat',run)),'result');
    [expectedX(run,:),expectedY(run,:)] = ...
        RobotPathPlanning.DecodeTrajectory(dec,startPos,endPos,numSamples);
end

actual = loadMeanEngineeringTrajectory(fixtureDir,'ALG',1,20,4,1000, ...
    startPos,endPos,numSamples);
verifyEqual(testCase,actual.n,20);
verifyEqual(testCase,actual.completed,20);
verifyEqual(testCase,actual.obj,10.5,'AbsTol',1e-12);
verifyEqual(testCase,actual.pathX,mean(expectedX,1),'AbsTol',1e-12);
verifyEqual(testCase,actual.pathY,mean(expectedY,1),'AbsTol',1e-12);
verifyEqual(testCase,actual.plotX([1 end]),[startPos(1),endPos(1)], ...
    'AbsTol',1e-12);
verifyEqual(testCase,actual.plotY([1 end]),[startPos(2),endPos(2)], ...
    'AbsTol',1e-12);
end
