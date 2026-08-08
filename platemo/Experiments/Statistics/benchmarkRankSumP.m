function pValue = benchmarkRankSumP(x,y)
% Two-sided Wilcoxon rank-sum p-value with a small toolbox-free fallback.
x = x(isfinite(x));
y = y(isfinite(y));
if isempty(x) || isempty(y)
    pValue = NaN;
    return;
end
if exist('ranksum','file') == 2
    pValue = ranksum(x,y,'tail','both');
    return;
end

combined = [x(:);y(:)];
[sortedValues,order] = sort(combined);
sortedRanks = zeros(size(sortedValues));
startIndex = 1;
while startIndex <= numel(sortedValues)
    endIndex = startIndex;
    while endIndex < numel(sortedValues) && ...
            sortedValues(endIndex+1) == sortedValues(startIndex)
        endIndex = endIndex + 1;
    end
    sortedRanks(startIndex:endIndex) = mean(startIndex:endIndex);
    startIndex = endIndex + 1;
end
ranks = zeros(size(combined));
ranks(order) = sortedRanks;
nX = numel(x);
nY = numel(y);
u = sum(ranks(1:nX))-nX*(nX+1)/2;
n = nX+nY;
[~,~,groups] = unique(combined);
tieGroups = accumarray(groups,1);
tieCorrection = sum(tieGroups.^3-tieGroups);
variance = nX*nY/12*((n+1)-tieCorrection/(n*(n-1)));
if variance <= 0
    pValue = 1;
else
    z = (abs(u-nX*nY/2)-0.5)/sqrt(variance);
    pValue = min(1,erfc(abs(z)/sqrt(2)));
end
end
