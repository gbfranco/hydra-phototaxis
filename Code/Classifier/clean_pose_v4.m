function out = clean_pose_v4(csvPath, outDir, stem)
%CLEAN_POSE_V4 Mask + interpolate one SLEAP file, calibrated from that file.
%
%   out = clean_pose_v4(csvPath, outDir, stem)
%   csvPath  SLEAP CSV export (1 frame/s)
%   outDir   output folder (required); writes <outDir>\<stem>_clean.csv
%   stem     name of the output (optional; default = the file name). Hand
%            labels are keyed by this stem (manifest legacy_names).
%   out      struct: summary table per node, the cleaned table, scale, ...
%
% Design notes:
%   * tolerates the node-naming differences between exports (Exp68 calls the
%     head 'hypo', the others 'hypostome')
%   * EXC_BASE = 15 frames of baseline before and after a candidate excursion.
%   * a CHATTER flag instead of deleting chatter: where the tracked position
%     alternates between levels there is no clean baseline, so the
%     return-to-baseline rule cannot fix it. The flag (any_chatter) excludes
%     nothing here (see "CHATTER IS A FLAG" below).
%
% Calibration is per file, from that file's own L/R chamber annotations:
%   scale = 35 mm / median(R.x - L.x), ONE isotropic scale (pixels are square)
%   x_mm  = (px - median(L.x)) * scale     0 at the left edge, 35 at the right
%   y_mm  = (py - yCentre)     * scale     signed from the lane centerline
% The 7 mm lane height is used only as a CHECK, never fitted: it should come
% back within a few percent, and a failure means the L/R annotation is wrong.

assert(nargin >= 2 && ~isempty(outDir), 'clean_pose_v4: outDir is required');
if ~exist(outDir,'dir'), mkdir(outDir); end

CHAMBER_MM = 35.0;
LANE_MM    = 7.0;
LOWSCORE   = struct('foot',0.30,'body',0.20,'head',0.30);
% MAXGAP = 20: gaps of up to 20 frames are interpolated (pchip), longer gaps
% are left empty. Across a 20-frame gap the median error against hand-placed
% positions is 0.24 mm, below the tracking jitter; the longest missing run in
% these exports is 19 frames.
MAXGAP     = 20;
EXC_D_MM   = 1.9;
EXC_W      = 60;
EXC_BASE   = 15;
EXC_TOL    = 0.5;
CH_WIN     = 61;      % frames, window for the local median and chatter count
CH_MIN     = 6;       % this many bad frames in a window makes it chatter

if nargin < 3 || isempty(stem)
    [~, stem] = fileparts(csvPath);
    stem = erase(stem, '.analysis');
end
T = readtable(csvPath, 'VariableNamingRule','preserve');
nF = height(T);
vn = T.Properties.VariableNames;

% node -> whichever prefix this export used
prefixes = struct('foot',{{'foot'}}, 'body',{{'body'}}, 'head',{{'hypostome','hypo','head'}});
nodes = {'foot','body','head'};
pfx = struct();
for i = 1:numel(nodes)
    cand = prefixes.(nodes{i}); hit = '';
    for c = 1:numel(cand)
        if ismember([cand{c} '.x'], vn), hit = cand{c}; break; end
    end
    assert(~isempty(hit), '%s: no column found for the %s node (tried %s)', ...
        stem, nodes{i}, strjoin(cand,'/'));
    pfx.(nodes{i}) = hit;
end

% ---- per-file calibration -----------------------------------------------
Lx = median(T.('L.x'),'omitnan'); Rx = median(T.('R.x'),'omitnan');
Ly = median(T.('L.y'),'omitnan'); Ry = median(T.('R.y'),'omitnan');
span = Rx - Lx;
assert(span > 100, '%s: L/R span is %.1f px, annotation looks wrong', stem, span);
scale   = CHAMBER_MM / span;
yCentre = mean([Ly Ry]);
EXC_D   = EXC_D_MM / scale;
X2mm = @(px) (px - Lx)*scale;
Y2mm = @(py) (py - yCentre)*scale;

ally = [];
for i = 1:numel(nodes), ally = [ally; T.([pfx.(nodes{i}) '.y'])]; end %#ok<AGROW>
laneObs = (max(ally,[],'omitnan') - min(ally,[],'omitnan'))*scale;

fprintf('%-22s %6d frames  %5.2f h  |  %.3f px/mm  |  lane %.2f mm (stated %.1f)\n', ...
    stem, nF, nF/3600, 1/scale, laneObs, LANE_MM);
if abs(laneObs - LANE_MM) > 0.7
    warning('%s: observed lane height %.2f mm differs from %.1f mm by >0.7 mm', stem, laneObs, LANE_MM);
end

O = table(T.frame_idx,'VariableNames',{'frame_idx'});
O.time_h = (0:nF-1)'/3600;
rows = cell(0,11);

for i = 1:numel(nodes)
    nd = nodes{i}; p = pfx.(nd);
    x = T.([p '.x']); y = T.([p '.y']); s = T.([p '.score']);

    missing = isnan(x) | isnan(y);
    manual  = ~missing & isnan(s);
    bad     = ~missing & ~manual & s < LOWSCORE.(nd);

    exc = detectExcursions(x, y, missing | bad, EXC_D, EXC_W, EXC_BASE, EXC_TOL);
    exc(manual) = false;
    suspect = missing | bad | exc;
    suspect(manual) = false;

    [xi, yi, interpMask, blankMask] = fillOrBlank(x, y, suspect, MAXGAP);
    xm = X2mm(xi); ym = Y2mm(yi);

    % residual contamination and chatter, both from the cleaned series
    mx = movmedian(xm, CH_WIN, 'omitnan', 'Endpoints','shrink');
    my = movmedian(ym, CH_WIN, 'omitnan', 'Endpoints','shrink');
    dev = hypot(xm-mx, ym-my);
    devBad = dev > EXC_D_MM;                       % NaN compares false
    chatter = movsum(devBad, CH_WIN, 'Endpoints','shrink') >= CH_MIN;

    O.([nd '_x_mm'])    = xm;
    O.([nd '_y_mm'])    = ym;
    O.([nd '_interp'])  = interpMask;
    O.([nd '_blank'])   = blankMask;
    O.([nd '_manual'])  = manual;
    O.([nd '_exc'])     = exc;
    O.([nd '_chatter']) = chatter;

    rows(end+1,:) = {stem, nd, p, sum(missing), sum(manual), sum(bad), sum(exc), ...
        sum(interpMask), 100*sum(~isnan(xm))/nF, 100*sum(devBad)/nF, ...
        100*sum(chatter)/nF}; %#ok<AGROW>
end

O.all3_valid  = ~isnan(O.foot_x_mm) & ~isnan(O.body_x_mm) & ~isnan(O.head_x_mm);
O.any_chatter = O.foot_chatter | O.body_chatter | O.head_chatter;
% CHATTER IS A FLAG, NOT AN EXCLUSION: chatter (position far from its local
% median) is about 4x more common around real jumps, so excluding it would
% remove jumps.
O.locomotion_ok = O.all3_valid;
O.posture_ok    = O.all3_valid;

S = cell2table(rows,'VariableNames',{'file','node','column','missing','manual', ...
    'lowScore','excursions','interpolated','pct_usable','pct_residual','pct_chatter'});

writetable(O, fullfile(outDir,[stem '_clean.csv']));
out = struct('summary',S,'data',O,'scale',scale,'laneObs',laneObs,'stem',stem, ...
             'Lx',Lx,'yCentre',yCentre,'pfx',pfx);

fprintf('   all3 %.1f%%  locomotion-usable %.1f%%  chatter(any) %.1f%%\n', ...
    100*mean(O.all3_valid), 100*mean(O.locomotion_ok), 100*mean(O.any_chatter));
end

% =========================================================================
function exc = detectExcursions(x, y, alreadyBad, D, W, B, TOL)
n = numel(x); exc = false(n,1);
valid = ~alreadyBad & ~isnan(x) & ~isnan(y);
if sum(valid) < 2*B + 2, return; end
for L = 1:W
    usable = valid & ~exc;
    ui = find(usable);
    if numel(ui) < 2*B + L + 2, break; end

    % nBefore(a) = how many usable frames have index < a. Precomputing this
    % turns the "which frames form my baseline" lookup from an O(n) scan into
    % an O(1) index. Without it the loop is O(n^2 * W) and takes minutes per
    % file instead of seconds.
    nBefore = [0; cumsum(usable(:))];        % nBefore(a) counts indices < a
    cumValid = [0; cumsum(valid(:))];
    cumExc   = [0; cumsum(exc(:))];

    for a = 1:n-L+1
        b = a + L - 1;
        % whole segment valid and not already flagged, without forming seg
        if (cumValid(b+1)-cumValid(a)) ~= L, continue; end
        if (cumExc(b+1)-cumExc(a)) > 0, continue; end

        kPre = nBefore(a);                    % usable frames strictly before a
        if kPre < B, continue; end
        kPost = numel(ui) - nBefore(b+1);     % usable frames strictly after b
        if kPost < B, continue; end

        preIdx  = ui(kPre-B+1:kPre);
        postIdx = ui(nBefore(b+1)+1 : nBefore(b+1)+B);
        if (a - preIdx(end)) > 2 || (postIdx(1) - b) > 2, continue; end

        pbx = median(x(preIdx));  pby = median(y(preIdx));
        qbx = median(x(postIdx)); qby = median(y(postIdx));
        if hypot(qbx-pbx, qby-pby) > TOL*D, continue; end

        seg = a:b;
        if all(hypot(x(seg)-pbx, y(seg)-pby) > D), exc(seg) = true; end
    end
end
end

% =========================================================================
function [xi, yi, interpMask, blankMask] = fillOrBlank(x, y, suspect, MAXGAP)
n = numel(x); xi = x; yi = y;
interpMask = false(n,1); blankMask = false(n,1);
gi = find(~suspect & ~isnan(x));
d = diff([false; suspect; false]);
starts = find(d==1); stops = find(d==-1)-1;
for r = 1:numel(starts)
    a = starts(r); b = stops(r);
    if (b-a+1) <= MAXGAP && any(gi<a) && any(gi>b)
        interpMask(a:b) = true;
    else
        blankMask(a:b) = true;
    end
end
if any(interpMask)
    xi(interpMask) = interp1(gi, x(gi), find(interpMask), 'pchip');
    yi(interpMask) = interp1(gi, y(gi), find(interpMask), 'pchip');
end
xi(blankMask) = NaN; yi(blankMask) = NaN;
end
