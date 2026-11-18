function v = smooth_bouts(llr, A, prior)
%SMOOTH_BOUTS Temporal smoothing of one behavior over one run of valid seconds.
%
%   v = smooth_bouts(llr, A, prior)
%   llr   : per-second score; A: 2x2 switch probabilities (off/on);
%   prior : share of time on. Returns v (1 = on, 0 = off): the on/off sequence
%           that best fits the scores while paying the cost of each switch, so
%           short flickers are removed.
%
% This is the step the paper calls temporal smoothing. It is its own file so
% that run_classifier.m, build_ethograms.m and score_labels.m all use the same
% one.
n = numel(llr); lA = log(A+realmin);
d = zeros(n,2); ps = zeros(n,2);
d(1,:) = log([1-prior prior]+realmin) + [0 llr(1)];
for t = 2:n
    for s = 1:2
        [d(t,s), ps(t,s)] = max(d(t-1,:) + lA(:,s)');
    end
    d(t,:) = d(t,:) + [0 llr(t)];
end
v = zeros(n,1); [~,v(n)] = max(d(n,:));
for t = n-1:-1:1, v(t) = ps(t+1, v(t+1)); end
v = v - 1;
end
