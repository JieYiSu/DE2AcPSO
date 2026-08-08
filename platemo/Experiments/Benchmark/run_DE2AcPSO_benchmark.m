function statusTable = run_DE2AcPSO_benchmark(mode,includeComparators)
%RUN_DE2ACPSO_BENCHMARK Run the smoke check or paper benchmark suite.

if nargin < 1 || isempty(mode)
    mode = 'smoke';
end
if nargin < 2 || isempty(includeComparators)
    includeComparators = false;
end
mode = lower(char(mode));

switch mode
    case 'smoke'
        functionIds = 11;
        dimensions = 30;
        runs = 1;
        maxFE = 250;
    case 'paper'
        functionIds = [1,5,8,9,10,11,12,13];
        dimensions = [30,50,100,200,500,1000];
        runs = 20;
        maxFE = 1000;
    otherwise
        error('DE2AcPSO:InvalidBenchmarkMode', ...
            'Mode must be ''smoke'' or ''paper''.');
end

if includeComparators
    algorithmNames = {'L2SMEA','SADEAMSS','SAMSO', ...
        'GORS_SSLPSO','SHPSO','DE2AcPSO'};
else
    algorithmNames = {'DE2AcPSO'};
end

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
cd(rootDir);
addpath(genpath(rootDir));

N = 50;
savePoints = 25;
numCases = numel(algorithmNames)*numel(functionIds)* ...
    numel(dimensions)*runs;
rows = cell(numCases,7);
row = 0;

for algorithmIndex = 1:numel(algorithmNames)
    algorithmName = algorithmNames{algorithmIndex};
    if isempty(which(algorithmName))
        warning('DE2AcPSO:MissingAlgorithm', ...
            'Skipping unavailable algorithm %s.',algorithmName);
        continue;
    end
    for functionId = functionIds
        problemName = sprintf('SOP_F%d',functionId);
        if isempty(which(problemName))
            error('DE2AcPSO:MissingProblem', ...
                'Required PlatEMO problem %s was not found.',problemName);
        end
        for D = dimensions
            for run = 1:runs
                row = row + 1;
                timer = tic;
                message = '';
                state = 'completed';
                try
                    platemo('algorithm',str2func(algorithmName), ...
                        'problem',str2func(problemName),'N',N,'D',D, ...
                        'maxFE',maxFE,'save',savePoints,'run',run);
                catch errorInfo
                    state = 'failed';
                    message = sprintf('%s: %s', ...
                        errorInfo.identifier,errorInfo.message);
                end
                rows(row,:) = {algorithmName,functionId,D,run,maxFE, ...
                    state,toc(timer)};
                if ~isempty(message)
                    warning('DE2AcPSO:BenchmarkCaseFailed','%s',message);
                end
            end
        end
    end
end

rows = rows(1:row,:);
statusTable = cell2table(rows,'VariableNames', ...
    {'Algorithm','Function','Dimension','Run','MaxFE','Status','Seconds'});
outputDir = fullfile(rootDir,'Data','DE2AcPSO_Reproduction');
if exist(outputDir,'dir') ~= 7
    mkdir(outputDir);
end
writetable(statusTable,fullfile(outputDir, ...
    sprintf('benchmark_%s_status.csv',mode)));
end
