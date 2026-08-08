function results = run_tests(platemoRoot)
%RUN_TESTS Run the DE2AcPSO MATLAB unit tests from the repository checkout.

repositoryRoot = fileparts(mfilename('fullpath'));
payloadRoot = fullfile(repositoryRoot,'platemo');
addpath(genpath(payloadRoot));

if nargin >= 1 && ~isempty(platemoRoot)
    platemoRoot = char(platemoRoot);
    if exist(fullfile(platemoRoot,'platemo.m'),'file') ~= 2
        error('DE2AcPSO:InvalidPlatEMORoot', ...
            'platemo.m was not found in %s.',platemoRoot);
    end
    addpath(genpath(platemoRoot));
end

testEntries = dir(fullfile(payloadRoot,'**','test_*.m'));
testFiles = fullfile({testEntries.folder},{testEntries.name});
if isempty(testFiles)
    error('DE2AcPSO:NoTests','No MATLAB test files were found.');
end

generatedDataDir = fullfile(payloadRoot,'Data');
dataDirectoryExisted = exist(generatedDataDir,'dir') == 7;
cleanup = onCleanup(@()cleanupGeneratedData( ...
    generatedDataDir,dataDirectoryExisted));

results = runtests(testFiles);
disp(table(results));
if any([results.Failed])
    error('DE2AcPSO:TestsFailed','One or more DE2AcPSO tests failed.');
end
clear cleanup
end

function cleanupGeneratedData(dataDir,directoryExisted)
if ~directoryExisted && exist(dataDir,'dir') == 7
    rmdir(dataDir,'s');
end
end
