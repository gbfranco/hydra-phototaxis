function F = build_features_1fps_smoothed(stem, inDir, outDir, W)
%BUILD_FEATURES_1FPS_SMOOTHED Per-second movement measures from one cleaned trace.
%
%   F = build_features_1fps_smoothed(stem, inDir, outDir, W)
%   reads <inDir>\<stem>_clean.csv (clean_pose_v4.m), writes
%   <outDir>\<stem>_features1fps.csv and returns it as table F: smoothed
%   positions, body length and shape, their rates of change (slope over 5
%   frames), speeds, and valid (= posture_ok).
%
% Foot, body and head positions are median-filtered (window W frames; the
% paper uses W = 3) right after the posture_ok masking, before anything is
% derived from them: foot position carries frame-to-frame jitter that a length
% measure (contraction) mostly cancels but a position measure (v_foot) does
% not. The filter runs separately within each valid (posture_ok) run, so a
% window never bridges a masked-out gap.

if nargin < 4 || isempty(W), W = 5; end
T = readtable(fullfile(inDir,[stem '_clean.csv']));
n = height(T);
ok = T.posture_ok;

fx = T.foot_x_mm; fy = T.foot_y_mm;
bx = T.body_x_mm; by = T.body_y_mm;
hx = T.head_x_mm; hy = T.head_y_mm;
fx(~ok)=NaN; fy(~ok)=NaN; bx(~ok)=NaN; by(~ok)=NaN; hx(~ok)=NaN; hy(~ok)=NaN;

% ---- median smoothing of position, within valid runs only ------
fx = smoothValid(fx, ok, W); fy = smoothValid(fy, ok, W);
bx = smoothValid(bx, ok, W); by = smoothValid(by, ok, W);
hx = smoothValid(hx, ok, W); hy = smoothValid(hy, ok, W);

% ---- shape, rates of change and speeds ----
seg1 = hypot(bx-fx, by-fy);
seg2 = hypot(hx-bx, hy-by);
L    = seg1 + seg2;
span = hypot(hx-fx, hy-fy);
straightness = span ./ max(L, eps);

v1x = bx-fx; v1y = by-fy; v2x = hx-bx; v2y = hy-by;
cosb = (v1x.*v2x + v1y.*v2y) ./ max(hypot(v1x,v1y).*hypot(v2x,v2y), eps);
bend = acos(min(max(cosb,-1),1));

axisAng   = atan2(hy-fy, hx-fx);
headRel   = wrapToPiLocal(atan2(v2y,v2x) - atan2(v1y,v1x));

d = @(v) slope5(v);
dL      = d(L);
dseg1   = d(seg1);
dseg2   = d(seg2);
dbend   = d(bend);
dstr    = d(straightness);
daxis   = dAngle5(axisAng);
dheadRel= dAngle5(headRel);

v_foot = speed5(fx,fy);
v_body = speed5(bx,by);
v_head = speed5(hx,hy);

ux = cos(axisAng); uy = sin(axisAng);
relbx = bx - fx; relby = by - fy;
bodyPerp = relbx.*(-uy) + relby.*ux;
dbodyPerp = d(bodyPerp);

F = table(T.frame_idx, T.time_h, ok, ...
    fx, fy, bx, by, hx, hy, ...
    seg1, seg2, L, span, straightness, bend, axisAng, headRel, bodyPerp, ...
    dL, dseg1, dseg2, dbend, dstr, daxis, dheadRel, dbodyPerp, ...
    v_foot, v_body, v_head, ...
    'VariableNames', {'frame_idx','time_h','valid', ...
    'foot_x','foot_y','body_x','body_y','head_x','head_y', ...
    'seg1','seg2','L','span','straightness','bend','axisAng','headRel','bodyPerp', ...
    'dL','dseg1','dseg2','dbend','dstr','daxis','dheadRel','dbodyPerp', ...
    'v_foot','v_body','v_head'});
F.animal = repmat(string(stem), n, 1);

if ~exist(outDir,'dir'), mkdir(outDir); end
writetable(F, fullfile(outDir,[stem '_features1fps.csv']));

v = F.valid & ~isnan(F.dL);
fprintf('%-20s %6d frames, %6d usable (%.1f%%)  [smoothed, W=%d]\n', stem, n, sum(v), 100*mean(v), W);
end

% -------------------------------------------------------------------------
function y = smoothValid(x, ok, W)
y = x;
if W <= 1, return; end
d = diff([false; ok(:); false]); s0=find(d==1); e0=find(d==-1)-1;
for z = 1:numel(s0)
    idx = s0(z):e0(z);
    if numel(idx) < 3, continue; end
    y(idx) = movmedian(x(idx), W);
end
end

function s = slope5(v)
n = numel(v); s = nan(n,1);
for i = 3:n-2
    w = v(i-2:i+2);
    if any(isnan(w)), continue; end
    s(i) = ([-2 -1 0 1 2] * w) / 10;
end
end

function s = dAngle5(a)
n = numel(a); s = nan(n,1);
for i = 3:n-2
    w = a(i-2:i+2);
    if any(isnan(w)), continue; end
    w = w(1) + cumsum([0; wrapToPiLocal(diff(w))]);
    s(i) = ([-2 -1 0 1 2] * w) / 10;
end
end

function s = speed5(x,y)
n = numel(x); s = nan(n,1);
sx = slope5(x); sy = slope5(y);
ok = ~isnan(sx) & ~isnan(sy);
s(ok) = hypot(sx(ok), sy(ok));
end

function a = wrapToPiLocal(a)
a = mod(a + pi, 2*pi) - pi;
end
