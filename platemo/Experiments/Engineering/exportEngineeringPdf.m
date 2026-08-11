function exportEngineeringPdf(fig,pdfFile,svgFile)
%EXPORTENGINEERINGPDF Preserve requested fonts in vector engineering figures.
removeSvgAfterExport = nargin < 3 || isempty(svgFile);
if removeSvgAfterExport
    svgFile = [tempname '.svg'];
end
svgCleanup = onCleanup(@() cleanIntermediateSvg(svgFile,removeSvgAfterExport));

exportgraphics(fig,svgFile,'ContentType','vector');
svgText = fileread(svgFile);
sizeTokens = regexp(svgText, ...
    '<svg\s+width="([^"]+)"\s+height="([^"]+)"','tokens','once');
if isempty(sizeTokens)
    error('DE2AcPSO:SvgSizeMissing', ...
        'Unable to read the exported SVG dimensions from %s.',svgFile);
end

chromeExe = findChromeExecutable();
svgText = regexprep(svgText,'^\s*<\?xml[^>]*\?>\s*','');
htmlFile = [tempname '.html'];
profileDir = tempname;
mkdir(profileDir);
cleanup = onCleanup(@() cleanTemporaryFiles(htmlFile,profileDir));

htmlText = sprintf([ ...
    '<!doctype html><html><head><meta charset="utf-8">' ...
    '<style>@page{size:%s %s;margin:0}' ...
    'html,body{margin:0;width:%s;height:%s;overflow:hidden}' ...
    'svg{display:block;width:%s;height:%s}</style></head><body>%s' ...
    '</body></html>'], ...
    sizeTokens{1},sizeTokens{2},sizeTokens{1},sizeTokens{2}, ...
    sizeTokens{1},sizeTokens{2},svgText);
writeUtf8Text(htmlFile,htmlText);

if isfile(pdfFile)
    delete(pdfFile);
end
htmlUri = ['file:///' strrep(htmlFile,'\','/')];
command = sprintf([ ...
    '"%s" --headless=new --disable-gpu --no-first-run ' ...
    '--no-pdf-header-footer --run-all-compositor-stages-before-draw ' ...
    '--virtual-time-budget=2000 --user-data-dir="%s" ' ...
    '--print-to-pdf="%s" "%s"'], ...
    chromeExe,profileDir,pdfFile,htmlUri);
[status,commandOutput] = system(command);

startTime = tic;
previousBytes = -1;
stableChecks = 0;
while toc(startTime) < 15
    if isfile(pdfFile)
        fileInfo = dir(pdfFile);
        if fileInfo.bytes > 0 && fileInfo.bytes == previousBytes
            stableChecks = stableChecks + 1;
            if stableChecks >= 2
                break;
            end
        else
            previousBytes = fileInfo.bytes;
            stableChecks = 0;
        end
    end
    pause(0.2);
end
if status ~= 0 || ~isfile(pdfFile) || dir(pdfFile).bytes == 0
    error('DE2AcPSO:PdfExportFailed', ...
        'Chrome PDF export failed for %s. Output: %s',pdfFile,commandOutput);
end
end

function chromeExe = findChromeExecutable()
candidates = { ...
    fullfile(getenv('ProgramFiles'),'Google','Chrome','Application','chrome.exe'), ...
    fullfile(getenv('ProgramFiles(x86)'),'Google','Chrome','Application','chrome.exe'), ...
    fullfile(getenv('ProgramFiles(x86)'),'Microsoft','Edge','Application','msedge.exe'), ...
    fullfile(getenv('ProgramFiles'),'Microsoft','Edge','Application','msedge.exe')};
existing = candidates(cellfun(@isfile,candidates));
if isempty(existing)
    error('DE2AcPSO:BrowserMissing', ...
        'Google Chrome or Microsoft Edge is required for font-preserving PDF export.');
end
chromeExe = existing{1};
end

function writeUtf8Text(fileName,textValue)
fileId = fopen(fileName,'w','n','UTF-8');
if fileId < 0
    error('DE2AcPSO:HtmlWriteFailed','Unable to create %s.',fileName);
end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId,textValue,'char');
end

function cleanIntermediateSvg(svgFile,removeSvgAfterExport)
if removeSvgAfterExport && isfile(svgFile)
    delete(svgFile);
end
end

function cleanTemporaryFiles(htmlFile,profileDir)
if isfile(htmlFile)
    delete(htmlFile);
end
if isfolder(profileDir)
    rmdir(profileDir,'s');
end
end
