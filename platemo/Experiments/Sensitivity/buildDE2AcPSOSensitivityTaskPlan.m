function plan = buildDE2AcPSOSensitivityTaskPlan(configRows,configIndices, ...
    dimensions,runIndices,baseSeed,maxFE,cacheDir)
%BUILDDE2ACPSOSENSITIVITYTASKPLAN Build and deduplicate sensitivity cases.

nRows = numel(configIndices)*numel(dimensions)*numel(runIndices);
rowTemplate = struct( ...
    'Factor','','FactorSymbol','','Level',NaN,'ParameterValues',[], ...
    'Dimension',NaN,'Run',NaN,'Seed',NaN,'TaskIndex',NaN);
taskTemplate = struct( ...
    'Dimension',NaN,'Run',NaN,'Seed',NaN,'ParameterValues',[], ...
    'CacheFile','');
rows = repmat(rowTemplate,nRows,1);
tasks = repmat(taskTemplate,0,1);
taskByCacheFile = containers.Map('KeyType','char','ValueType','double');

rowIndex = 0;
for configPosition = 1:numel(configIndices)
    configIndex = configIndices(configPosition);
    parameterValues = [configRows{configIndex,5:8}];
    for dimensionIndex = 1:numel(dimensions)
        D = dimensions(dimensionIndex);
        for runPosition = 1:numel(runIndices)
            runIndex = runIndices(runPosition);
            seed = baseSeed + 1000*D + runIndex;
            cacheFile = fullfile(cacheDir,caseFileName( ...
                D,runIndex,maxFE,parameterValues));

            if isKey(taskByCacheFile,cacheFile)
                taskIndex = taskByCacheFile(cacheFile);
            else
                taskIndex = numel(tasks) + 1;
                taskByCacheFile(cacheFile) = taskIndex;
                tasks(taskIndex,1) = struct( ...
                    'Dimension',D,'Run',runIndex,'Seed',seed, ...
                    'ParameterValues',parameterValues, ...
                    'CacheFile',cacheFile);
            end

            rowIndex = rowIndex + 1;
            rows(rowIndex) = struct( ...
                'Factor',configRows{configIndex,1}, ...
                'FactorSymbol',configRows{configIndex,2}, ...
                'Level',configRows{configIndex,3}, ...
                'ParameterValues',parameterValues, ...
                'Dimension',D,'Run',runIndex,'Seed',seed, ...
                'TaskIndex',taskIndex);
        end
    end
end

plan = struct('Rows',rows,'Tasks',tasks,'RowToTask', ...
    reshape([rows.TaskIndex],[],1),'NumRows',nRows,'NumTasks',numel(tasks));
end

function name = caseFileName(D,runIndex,maxFE,parameterValues)
name = sprintf('F11_D%d_Run%02d_FE%d_R2_%s_PDI_%s_CM_%s_EA_%s.mat', ...
    D,runIndex,maxFE,numberToken(parameterValues(1)), ...
    numberToken(parameterValues(2)),numberToken(parameterValues(3)), ...
    numberToken(parameterValues(4)));
end

function text = numberToken(value)
text = strrep(sprintf('%.12g',value),'.','p');
text = strrep(text,'-','m');
text = strrep(text,'+','');
end
