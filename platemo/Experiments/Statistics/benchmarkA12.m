function effect = benchmarkA12(proposed,competitor)
% Vargha--Delaney A12 for minimization: P(proposed < competitor) + 0.5 ties.
proposed = proposed(isfinite(proposed));
competitor = competitor(isfinite(competitor));
if isempty(proposed) || isempty(competitor)
    effect = NaN;
    return;
end

pairwise = proposed(:) < competitor(:)';
ties = proposed(:) == competitor(:)';
effect = (sum(pairwise,'all') + 0.5*sum(ties,'all'))/numel(pairwise);
end
