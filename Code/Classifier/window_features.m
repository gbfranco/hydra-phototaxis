function [G, v] = window_features(T)
%WINDOW_FEATURES The classifier's 51 inputs for every second of one animal.
%
%   [G, v] = window_features(T)   T = one <stem>_features1fps.csv table
%                                 G = n x 51, v = logical(T.valid)
%
% The 8 kinematic descriptors (log foot/body/head speed, length change rate,
% log |bending rate|, log |axis rotation rate|, log |head angle rate|, body
% length / the animal's median length), set to NaN on invalid seconds, then at
% each scale (7, 21, 61 s: +-3, +-10, +-30 s) their moving mean and SD and the
% net length change. Column order: per scale, 8 means, 8 SDs, net change.
EPS = 1e-3; SCALES = [7 21 61];
v = logical(T.valid);
Lmed = median(T.L(v),'omitnan');
F = [ log(T.v_foot+EPS), log(T.v_body+EPS), log(T.v_head+EPS), T.dL, ...
      log(abs(T.dbend)+EPS), log(abs(T.daxis)+EPS), log(abs(T.dheadRel)+EPS), ...
      T.L/Lmed ];
F(~v,:) = NaN;
G = [];
for s = SCALES
    G = [G, movmean(F,s,1,'omitnan'), movstd(F,s,1,'omitnan')]; %#ok<AGROW>
    Lc = T.L/Lmed; Lc(~v) = NaN;
    G = [G, movmean([0; diff(Lc)],s,1,'omitnan')*s]; %#ok<AGROW>  net length change
end
end
