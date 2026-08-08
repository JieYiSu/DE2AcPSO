function [axesPositions,legendPosition] = engineeringFigureLayout()
%ENGINEERINGFIGURELAYOUT Fixed normalized positions for six panels and legend.

columnX = [0.055 0.365 0.675];
axesWidth = 0.27;
axesHeight = 0.30;
topY = 0.625;
bottomY = 0.200;

axesPositions = [columnX(1) topY    axesWidth axesHeight; ...
                 columnX(2) topY    axesWidth axesHeight; ...
                 columnX(3) topY    axesWidth axesHeight; ...
                 columnX(1) bottomY axesWidth axesHeight; ...
                 columnX(2) bottomY axesWidth axesHeight; ...
                 columnX(3) bottomY axesWidth axesHeight];
legendPosition = [0.06 0.035 0.88 0.09];
end
