function bestValue = quick_start(platemoRoot)
%QUICK_START Run a small DE2AcPSO check on SOP F11.

if nargin < 1 || isempty(platemoRoot)
    error('DE2AcPSO:MissingPlatEMORoot', ...
        'Provide the directory that contains platemo.m.');
end
platemoRoot = char(platemoRoot);
if exist(fullfile(platemoRoot,'platemo.m'),'file') ~= 2
    error('DE2AcPSO:InvalidPlatEMORoot', ...
        'platemo.m was not found in %s.',platemoRoot);
end

repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(platemoRoot));
addpath(genpath(fullfile(repositoryRoot,'platemo')));

rng(1,'twister');
problem = SOP_F11('N',50,'D',30,'maxFE',250);
algorithm = DE2AcPSO('parameter',num2cell([0.1,0.2,20,50]), ...
    'save',0,'metName',{'Min_value'});
algorithm.Solve(problem);
history = algorithm.CalMetric('Min_value');
bestValue = history(end);
fprintf('DE2AcPSO quick check: FE=%d, best objective=%.6e\n', ...
    problem.FE,bestValue);
end
