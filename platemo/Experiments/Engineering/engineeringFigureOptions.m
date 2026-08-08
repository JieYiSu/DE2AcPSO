function options = engineeringFigureOptions()
%ENGINEERINGFIGUREOPTIONS Interactive defaults for engineering figures.
%   The trajectory figures remain open so their view and layout can be
%   adjusted in MATLAB before the user saves them manually.

options.autoSave = false;
options.closeAfterSave = false;
options.windowState = 'maximized';
options.figurePosition = [40 40 1500 1150];
options.layoutPosition = [0.035 0.23 0.93 0.69];
options.legendCenterX = 0.5;
options.legendBottom = 0.055;
end
