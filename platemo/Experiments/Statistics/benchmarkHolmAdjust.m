function adjustedP = benchmarkHolmAdjust(rawP)
% Holm step-down adjustment while preserving the input shape.
originalSize = size(rawP);
rawP = rawP(:);
adjustedP = NaN(size(rawP));
valid = isfinite(rawP);
if ~any(valid)
    adjustedP = reshape(adjustedP,originalSize);
    return;
end

values = min(max(rawP(valid),0),1);
[sortedP,order] = sort(values,'ascend');
m = numel(sortedP);
stepDown = (m-(1:m)' + 1).*sortedP;
stepDown = cummax(stepDown);
stepDown = min(stepDown,1);
adjusted = NaN(size(values));
adjusted(order) = stepDown;
adjustedP(valid) = adjusted;
adjustedP = reshape(adjustedP,originalSize);
end
