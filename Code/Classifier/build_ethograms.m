function W = build_ethograms(mode, workDir)
%BUILD_ETHOGRAMS Fit the behavior classifier from the hand labels.
%
%   build_ethograms()          fit on every labeled second and check the
%                              result against the shipped weights
%   build_ethograms('loo')     the same, then leave one animal out: each dark
%                              animal is labeled by a classifier refitted
%                              without its own labeled seconds, and its
%                              labeled seconds are scored. Prints the
%                              confusion matrix of the paper's Dark panel.
%   build_ethograms(mode, workDir)   put the per-second features somewhere
%                              other than <repo>\Results\classifier\work
%
% Nothing here is needed to label animals: run_classifier applies the weights
% that ship in this folder, and this script reproduces them. It is here so a
% reviewer can regenerate detector_weights_smoothed3.mat from the labels, and
% so the Dark panel, which is a leave-one-animal-out result, can be redone.
%
% WHAT IT READS, all resolved from this file's location
%   <repo>\Data\raw_tracking\Irvine_starved_dark_startNear        15 animals
%   <repo>\Data\raw_tracking\Irvine_starved_light_startFarLight   15 animals
%   <repo>\Data\labels\bouts_Irvine_dark.csv     + label_KEY_Irvine_dark.csv
%   <repo>\Data\labels\bouts_Irvine_startFar.csv + label_KEY_Irvine_startFar.csv
%   <repo>\Data\labels\sealed_animals.csv        the 30 animals and their order
%   <repo>\Data\labels\jump_ledger.csv           jumping, for the 'loo' panel
%
% The 30 animals above are the training set. The startFarLight animals appear
% here and nowhere else in the behavior analysis: the paper's two conditions
% are startNearLight and dark startNear, and run_classifier labels only those.
%
% WHAT IT WRITES, in <repo>\Results\classifier
%   detector_weights_refit.mat   the refitted weights. The shipped
%                                detector_weights_smoothed3.mat is never
%                                overwritten; the two are compared instead.
%
% WHAT IS FITTED, per behavior (five, bend / sway included)
%   lasso logistic regression on the 51 inputs of the labeled seconds, the
%   penalty chosen by 5-fold cross-validation (the largest within one standard
%   error of the smallest error); then the temporal-smoothing settings from the
%   lengths of the hand-marked bouts and gaps, and one offset per behavior so
%   that the share of labeled seconds called "on" matches the hand labels.
%   The seed is fixed (rng(3,'twister')) and the labeled seconds are
%   assembled in a fixed order (dark animals by name, then startFarLight by
%   name), so the fit is reproducible run to run.
%
% REQUIREMENTS Statistics and Machine Learning Toolbox, for lassoglm.
%   run_classifier needs no toolbox; this script does.
%
% TIME About 25 min to build the features of the 30 animals (skipped if they
%   are already in workDir), a few minutes for the fit, and about 15 refits
%   more for 'loo'.
%
% Run:  matlab -batch "addpath('Code/Classifier'); build_ethograms('loo')"

HERE = fileparts(mfilename('fullpath'));                 % <repo>\Code\Classifier
REPO = fileparts(fileparts(HERE));                       % <repo>
LAB  = fullfile(REPO,'Data','labels');
RAW  = fullfile(REPO,'Data','raw_tracking');
if nargin < 1, mode = ''; end
if nargin < 2 || isempty(workDir), workDir = fullfile(REPO,'Results','classifier','work'); end
if ~isfolder(workDir), mkdir(workDir); end
assert(~isempty(ver('stats')), 'build_ethograms: lassoglm needs the Statistics and Machine Learning Toolbox');

BEH = {'stillness','elongation','contraction','bend_sway','jumping'};
nB = 5; WIN = 60; kb = [1 2 3 5];                        % kb: the label set, bend / sway dropped
SMOOTH_W = 3;                                            % the median filter of the paper

% ---- the labels ---------------------------------------------------------
F = {fullfile(LAB,'bouts_Irvine_dark.csv'),     fullfile(LAB,'label_KEY_Irvine_dark.csv'); ...
     fullfile(LAB,'bouts_Irvine_startFar.csv'), fullfile(LAB,'label_KEY_Irvine_startFar.csv')};
for i = 1:numel(F)
    assert(isfile(F{i}), ['build_ethograms: %s not found.\n' ...
        'The training labels of both conditions ship in <repo>\\Data\\labels.'], F{i});
end
Bt  = [readtable(F{1,1},'TextType','string'); readtable(F{2,1},'TextType','string')];
Key = [readtable(F{1,2},'TextType','string'); readtable(F{2,2},'TextType','string')];
dup = false(height(Key),1);                              % a clip labeled twice is used once
for i = 1:height(Key)
    dup(i) = Key.kind(i) == "repeat" && any(Key.animal == Key.animal(i) & ...
        Key.startRow == Key.startRow(i) & Key.id ~= Key.id(i));
end
Bt = Bt(~ismember(Bt.id, Key.id(dup)), :);

% ---- the 30 training animals, in the order the paper assembled them -----
Sld = readtable(fullfile(LAB,'sealed_animals.csv'),'TextType','string');
stems  = [sort(Sld.animal(Sld.cond=="noLight")); sort(Sld.animal(Sld.cond=="startDark"))];
isDark = [true(sum(Sld.cond=="noLight"),1); false(sum(Sld.cond=="startDark"),1)];
assert(numel(stems) == 30, 'build_ethograms: expected 30 training animals in sealed_animals.csv, found %d', numel(stems));

FEAT = cell(numel(stems),1); VALID = FEAT; JEP = FEAT;
fprintf('features for %d training animals (reused where already built)\n', numel(stems));
for a = 1:numel(stems)
    featFile = fullfile(workDir, stems(a) + "_features1fps.csv");
    if ~isfile(featFile)
        src = fullfile(RAW, extractBefore(stems(a), strlength(stems(a))-2), stems(a) + ".csv");
        assert(isfile(src), ['build_ethograms: %s not found.\n' ...
            'Unpack the Zenodo raw_tracking folders into <repo>\\Data.'], src);
        clean_pose_v4(char(src), workDir, char(stems(a)));
        build_features_1fps_smoothed(char(stems(a)), workDir, workDir, SMOOTH_W);
    end
    T = readtable(featFile);
    [G, v] = window_features(T);
    FEAT{a} = G; VALID{a} = v & all(isfinite(G),2);
    JEP{a} = hand_jumps(fullfile(LAB,'jump_ledger.csv'), stems(a), height(T));
end

% ---- the labeled seconds ----------------------------------------------
Xl = []; yl = false(0,nB); nz = false(0,1); al = [];
for a = 1:numel(stems)
    for id = Key.id(Key.animal == stems(a))'
        s0 = Key.startRow(Key.id == id); g = s0:s0+WIN-1;
        if g(end) > size(FEAT{a},1), continue; end
        r = Bt(Bt.id == id, :);
        if isempty(r), continue; end
        yw = false(WIN,nB); nw = false(WIN,1);
        for z = 1:height(r)
            sl = r.s_sec(z)+1 : min(r.e_sec(z)+1, WIN);
            if r.beh_id(z) == 6, nw(sl) = true; else, yw(sl, r.beh_id(z)) = true; end
        end
        Xl = [Xl; FEAT{a}(g,:)]; yl = [yl; yw]; nz = [nz; nw]; al = [al; repmat(a,WIN,1)]; %#ok<AGROW>
    end
end
keep0 = all(isfinite(Xl),2) & ~nz;
fprintf('%d animals, %d clips, %d labeled seconds usable of %d\n', ...
    numel(unique(al)), numel(unique(Key.id(~dup))), sum(keep0), numel(keep0));

% ---- the full fit, checked against the shipped weights ------------------
t0 = tic;
W = fitModel(Xl, yl, keep0, al, Bt, nB, WIN, BEH);
fprintf('fitted in %.0f s\n\n%-16s %8s %8s %10s\n', toc(t0), 'behavior','pos s','lambda','offset');
for b = 1:nB
    fprintf('%-16s %8d %8.4f %10.2f\n', BEH{b}, sum(yl(keep0,b)), W.LAM(b), W.COFF(b));
end
outFile = fullfile(fileparts(workDir),'detector_weights_refit.mat');
save(outFile, '-struct', 'W');
fprintf('\nwritten: %s\n', outFile);

Fz = load(fullfile(HERE,'detector_weights_smoothed3.mat'));
same = true;
for nm = ["COEF","COFF","AT","PRIOR","mu","sd"]
    if ~isequal(W.(nm), Fz.(nm))
        same = false;
        d = max(abs(double(W.(nm)(:)) - double(Fz.(nm)(:))));
        fprintf('%s differs from the shipped weights, largest difference %.3g\n', nm, d);
    end
end
if same
    fprintf('the refit equals the shipped detector_weights_smoothed3.mat exactly\n');
end

if ~strcmpi(mode,'loo'), return; end

% ---- leave one animal out: the paper's Dark panel -----------------------
fprintf('\nleave one animal out, %d dark animals\n', sum(isDark));
tr = []; pr = []; an = strings(0,1); nTwo = 0;
for h = find(isDark)'
    if ~any(al == h), continue; end                      % no labeled clips
    tf = tic;
    Bh = Bt(~ismember(Bt.id, Key.id(Key.animal == stems(h))), :);
    Mh = fitModel(Xl, yl, keep0 & al ~= h, al, Bh, nB, WIN, BEH);
    [seq, L] = labelAnimal(Mh, FEAT{h}, VALID{h}, JEP{h}, kb);
    [t1, p1, n1] = scoreAnimal(Key, Bt, stems(h), seq, L, VALID{h}, kb);
    tr = [tr; t1]; pr = [pr; p1]; nTwo = nTwo + n1; %#ok<AGROW>
    an = [an; repmat(stems(h), numel(t1), 1)]; %#ok<AGROW>
    fprintf('  %-34s %4d labeled s, %3.0f%% agreement (%.0f s)\n', ...
        stems(h), numel(t1), 100*mean(t1==p1), toc(tf));
end
M = accumarray([tr pr], 1, [numel(kb) numel(kb)]);
Rw = 100 * M ./ max(sum(M,2),1);
NAME = BEH(kb);
agr = splitapply(@(x) 100*mean(x), tr==pr, findgroups(an));
fprintf('\n%d animals, %d labeled seconds (%d with two hand labels)\n', numel(unique(an)), numel(tr), nTwo);
fprintf('agreement %.0f%% pooled, %.0f%% median over animals\n\n', 100*mean(tr==pr), median(agr));
fprintf('%-14s %s   hand s\n', 'hand / clf', sprintf('%12s', NAME{:}));
for i = 1:numel(kb)
    fprintf('%-14s %s   %6d\n', NAME{i}, sprintf('%11.0f%%', Rw(i,:)), sum(M(i,:)));
end
T = table(repelem(string(NAME)',numel(kb),1), repmat(string(NAME)',numel(kb),1), M(:), Rw(:), ...
    'VariableNames', {'hand_label','classifier_label','seconds','row_pct'});
csv = fullfile(fileparts(workDir),'dark_panel_leave_one_out.csv');
writetable(T, csv);
fprintf('\nwritten: %s\n', csv);
end

% ------------------------------------------------------------------------------
function M = fitModel(Xl, yl, keep, al, Bt, nB, WIN, BEH)
rng(3,'twister');
mu = mean(Xl(keep,:),1); sd = std(Xl(keep,:),0,1); sd(sd<eps) = 1;
COEF = nan(size(Xl,2)+1, nB); LAM = nan(1,nB); COFF = nan(1,nB);
AT = nan(2,2,nB); PRIOR = nan(1,nB);
for b = 1:nB
    Z = (Xl(keep,:)-mu)./sd; yb = yl(keep,b);
    ws = warning('off','all');
    [Bc,Fit] = lassoglm(Z, double(yb), 'binomial', 'CV', 5, 'NumLambda', 20);
    warning(ws);
    j = Fit.Index1SE; coef = [Fit.Intercept(j); Bc(:,j)];
    % smoothing settings from the hand-marked bouts: switch probabilities from
    % the mean bout and gap lengths, base rate = share of labeled time on
    d = Bt.dur_sec(Bt.behavior == BEH{b});
    nWin = numel(unique(Bt.id));
    onS = sum(d); tot = WIN*nWin; offS = max(tot-onS,1);
    muOn = max(mean(d),1.5); muOff = max(offS/numel(d),1.5);
    A = [1-1/muOff, 1/muOff; 1/muOn, 1-1/muOn];
    prior = onS/tot;
    % offset: the share of labeled seconds called "on" matches the hand labels
    pl = min(max(logistic(coef, Z), 1e-6), 1-1e-6);
    ll = log(pl./(1-pl)) - log(prior/(1-prior));
    wl = findgroups(al(keep));
    lo = -8; hi = 8;
    for it = 1:16
        c = (lo+hi)/2; vv = false(numel(ll),1);
        for g = unique(wl)'
            sel = wl==g; vv(sel) = smooth_bouts(ll(sel)-c, A, prior) > 0.5;
        end
        if mean(vv) > mean(yb), lo = c; else, hi = c; end
    end
    COEF(:,b) = coef; LAM(b) = Fit.Lambda(j); COFF(b) = (lo+hi)/2;
    AT(:,:,b) = A; PRIOR(b) = prior;
end
M = struct('COEF',COEF,'LAM',LAM,'COFF',COFF,'AT',AT,'PRIOR',PRIOR,'mu',mu,'sd',sd, ...
    'BEH',{BEH},'SCALES',[7 21 61]);
end

function [seq, LLR] = labelAnimal(M, F, v, je, kb)
% one animal's whole recording: scores, temporal smoothing, jumping from the
% Jump Ledger, one label per second over kb (the steps of run_classifier)
nB = size(M.COEF,2); T = size(F,1);
ON = false(T,nB); LLR = -inf(T,nB);
for b = 1:nB
    p = nan(T,1); p(v) = logistic(M.COEF(:,b), (F(v,:)-M.mu)./M.sd);
    p = min(max(p,1e-6),1-1e-6);
    llr = log(p./(1-p)) - log(M.PRIOR(b)/(1-M.PRIOR(b))) - M.COFF(b);
    llr(~v) = -inf; LLR(:,b) = llr;
    q = diff([false; v; false]); s0 = find(q==1); e0 = find(q==-1)-1;
    for z = 1:numel(s0)
        sl = s0(z):e0(z);
        if numel(sl) < 3, continue; end
        ON(sl,b) = smooth_bouts(llr(sl), M.AT(:,:,b), M.PRIOR(b)) > 0.5;
    end
end
ON(:,5) = je & v; LLR(:,5) = -inf; LLR(je & v, 5) = 1e6;   % jumping = the Jump Ledger
L = LLR(:,kb); O = ON(:,kb);
Lon = L; Lon(~O) = -inf;
[~, ix] = max(Lon, [], 2); [~, ix2] = max(L, [], 2);
seq = nan(T,1);
idle = v & ~any(O,2);
seq(v) = ix(v); seq(idle) = ix2(idle);                     % indices into kb
end

function [tr, pr, nTwo] = scoreAnimal(Key, Bt, stem, seq, LLR, v, kb)
% the labeled seconds of one animal, by the rules of score_labels.m
WIN = 60; tr = []; pr = []; nTwo = 0;
for i = find(Key.animal == stem)'
    r = Key.startRow(i) + (0:WIN-1)';
    if r(end) > numel(seq), continue; end
    bb = Bt(Bt.id == Key.id(i), :);
    if isempty(bb), continue; end
    y = false(WIN,5); nz = false(WIN,1);
    for z = 1:height(bb)
        sl = bb.s_sec(z)+1 : min(bb.e_sec(z)+1, WIN);
        if bb.beh_id(z) == 6, nz(sl) = true; else, y(sl, bb.beh_id(z)) = true; end
    end
    for t = 1:WIN
        lab = intersect(find(y(t,:)), kb);                % bend / sway is not scored
        if isempty(lab) || nz(t) || ~v(r(t)) || isnan(seq(r(t))), continue; end
        if numel(lab) > 1
            nTwo = nTwo + 1;
            [~, ix] = max(LLR(r(t), lab)); lab = lab(ix);
        end
        tr(end+1,1) = find(kb == lab); pr(end+1,1) = seq(r(t)); %#ok<AGROW>
    end
end
end

function je = hand_jumps(ledger, stem, n)
% the hand-verified jump episodes of one animal, as a per-second mask
je = false(n,1);
if ~isfile(ledger), return; end
L = readtable(ledger,'TextType','string');
L = L(L.stem == stem, :);
for z = 1:height(L)
    je(max(L.s_sec(z),1) : min(L.e_sec(z), n)) = true;
end
end

function p = logistic(coef, Z)
eta = [ones(size(Z,1),1) Z] * coef;
lim = log(eps); eta = min(max(eta, lim), -lim);
p = 1 ./ (1 + exp(-eta));
end
