function signLabel = engineeringStatsSign(competitorValues,baselineValues,pValue)
% Label a minimization comparison from the competitor's perspective.
competitorValues = competitorValues(isfinite(competitorValues));
baselineValues = baselineValues(isfinite(baselineValues));

if isempty(competitorValues) || isempty(baselineValues) || pValue >= 0.05
    signLabel = '=';
    return;
end

direction = median(competitorValues)-median(baselineValues);
if direction == 0
    direction = mean(competitorValues)-mean(baselineValues);
end
if direction < 0
    signLabel = '+';
elseif direction > 0
    signLabel = '-';
else
    signLabel = '=';
end
end
