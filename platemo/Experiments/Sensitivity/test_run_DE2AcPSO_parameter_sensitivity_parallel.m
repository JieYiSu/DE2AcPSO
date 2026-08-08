function tests = test_run_DE2AcPSO_parameter_sensitivity_parallel
tests = functiontests(localfunctions);
end

function testRejectsInvalidParallelWorkerCount(testCase)
verifyError(testCase,@()run_DE2AcPSO_parameter_sensitivity( ...
    'pilot',30,1,1,false,-1),'Sensitivity:InvalidParallelWorkers');
end

function testTaskPlanDeduplicatesSharedDefaultConfiguration(testCase)
configRows = { ...
    'R2Gate','$\tau_{R^2}$',0.1,1,0.1,0.2,20,50; ...
    'PDIProbability','$p_{\mathrm{PDI}}$',0.2,2,0.1,0.2,20,50};

plan = buildDE2AcPSOSensitivityTaskPlan(configRows,[1 2],30,1, ...
    814729,250,tempname);

verifyEqual(testCase,plan.NumRows,2);
verifyEqual(testCase,plan.NumTasks,1);
verifyEqual(testCase,plan.RowToTask,[1;1]);
verifyEqual(testCase,plan.Tasks(1).Dimension,30);
verifyEqual(testCase,plan.Tasks(1).Run,1);
verifyEqual(testCase,plan.Tasks(1).Seed,844730);
verifyEqual(testCase,plan.Tasks(1).ParameterValues,[0.1 0.2 20 50]);
end

function testLatexCaptionReportsExperimentSize(testCase)
run_DE2AcPSO_parameter_sensitivity( ...
    'pilot',30,1:18,1:2,true,0);

experimentDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(experimentDir));
tableFile = fullfile(rootDir,'Data', ...
    'DE2AcPSO_F11_ParameterSensitivity', ...
    'F11_ParameterSensitivity_pilot_Table.tex');
tableText = fileread(tableFile);

verifySubstring(testCase,tableText,'2 independent runs');
verifySubstring(testCase,tableText,'\mathrm{FE}_{\max}=250');
end
