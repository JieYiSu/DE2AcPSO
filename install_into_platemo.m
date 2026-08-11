function report = install_into_platemo(platemoRoot,overwriteExisting)
%INSTALL_INTO_PLATEMO Install the DE2AcPSO payload into an existing PlatEMO.

if nargin < 1 || isempty(platemoRoot)
    error('DE2AcPSO:MissingPlatEMORoot', ...
        'Provide the directory that contains platemo.m.');
end
if nargin < 2 || isempty(overwriteExisting)
    overwriteExisting = false;
end
platemoRoot = char(platemoRoot);
overwriteExisting = logical(overwriteExisting);

if exist(fullfile(platemoRoot,'platemo.m'),'file') ~= 2
    error('DE2AcPSO:InvalidPlatEMORoot', ...
        'platemo.m was not found in %s.',platemoRoot);
end

repositoryRoot = fileparts(mfilename('fullpath'));
payloadRoot = fullfile(repositoryRoot,'platemo');
entries = dir(fullfile(payloadRoot,'**','*'));
entries = entries(~[entries.isdir]);

installed = strings(0,1);
skipped = strings(0,1);
for i = 1:numel(entries)
    sourceFile = fullfile(entries(i).folder,entries(i).name);
    relativePath = sourceFile(numel(payloadRoot)+2:end);
    destinationFile = fullfile(platemoRoot,relativePath);
    destinationFolder = fileparts(destinationFile);
    if exist(destinationFolder,'dir') ~= 7
        mkdir(destinationFolder);
    end
    if exist(destinationFile,'file') == 2 && ~overwriteExisting
        skipped(end+1,1) = string(relativePath);
        continue;
    end
    copyfile(sourceFile,destinationFile,'f');
    installed(end+1,1) = string(relativePath);
end

addpath(genpath(platemoRoot));
rehash;
report = struct('PlatEMORoot',string(platemoRoot), ...
    'Installed',installed,'Skipped',skipped);
fprintf('Installed %d file(s); skipped %d existing file(s).\n', ...
    numel(installed),numel(skipped));
end
