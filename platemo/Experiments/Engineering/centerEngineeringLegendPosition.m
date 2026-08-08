function centeredPosition = centerEngineeringLegendPosition( ...
    naturalPosition,options)
%CENTERENGINEERINGLEGENDPOSITION Center a naturally sized legend.

arguments
    naturalPosition (1,4) double
    options (1,1) struct
end

centeredPosition = naturalPosition;
centeredPosition(1) = options.legendCenterX-naturalPosition(3)/2;
centeredPosition(2) = options.legendBottom;
end
