function statusTable = run_DE2AcPSO_ablation(mode)
%RUN_DE2ACPSO_ABLATION Run the D=500 ablation experiment.

if nargin < 1 || isempty(mode)
    mode = 'smoke';
end
mode = lower(char(mode));
switch mode
    case 'smoke'
        functionIds = 11;
        runs = 1;
        maxFE = 250;
    case 'paper'
        functionIds = [1,5,8,9,10,11,12,13];
        runs = 20;
        maxFE = 1000;
    otherwise
        error('DE2AcPSO:InvalidAblationMode', ...
            'Mode must be ''smoke'' or ''paper''.');
end

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
cd(rootDir);
addpath(genpath(rootDir));

algorithmNames = {'DE2AcPSO_wo_ACDP','DE2AcPSO_wo_PDI', ...
    'DE2AcPSO_wo_RATR','DE2AcPSO'};
D = 500;
N = 50;
savePoints = 25;
rows = cell(numel(algorithmNames)*numel(functionIds)*runs,7);
row = 0;

for algorithmIndex = 1:numel(algorithmNames)
    algorithmName = algorithmNames{algorithmIndex};
    if isempty(which(algorithmName))
        error('DE2AcPSO:MissingAblationVariant', ...
            'Required variant %s was not found.',algorithmName);
    end
    for functionId = functionIds
        problemName = sprintf('SOP_F%d',functionId);
        for run = 1:runs
            row = row + 1;
            timer = tic;
            state = 'completed';
            try
                platemo('algorithm',str2func(algorithmName), ...
                    'problem',str2func(problemName),'N',N,'D',D, ...
                    'maxFE',maxFE,'save',savePoints,'run',run);
            catch errorInfo
                state = sprintf('failed:%s',errorInfo.identifier);
            end
            rows(row,:) = {algorithmName,functionId,D,run,maxFE, ...
                state,toc(timer)};
        end
    end
end

statusTable = cell2table(rows,'VariableNames', ...
    {'Algorithm','Function','Dimension','Run','MaxFE','Status','Seconds'});
outputDir = fullfile(rootDir,'Data','DE2AcPSO_Reproduction');
if exist(outputDir,'dir') ~= 7
    mkdir(outputDir);
end
writetable(statusTable,fullfile(outputDir, ...
    sprintf('ablation_%s_status.csv',mode)));
end
