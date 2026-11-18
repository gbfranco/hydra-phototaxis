function S = run_classifier(rawDir, outDir, jumpsFile)
%RUN_CLASSIFIER One behavior label per second for raw SLEAP tracking files.
%
%   run_classifier()                     the two conditions of the paper's
%                                        behavior analysis in
%                                        <repo>\Data\raw_tracking, with jumping
%                                        from <repo>\Data\labels\
%                                        jump_ledger.csv, results to
%                                        <repo>\Results\classifier
%   run_classifier(rawDir, outDir)       rawDir = a folder of SLEAP CSVs, or a
%                                        folder of such folders. The Jump
%                                        Ledger is still used.
%   run_classifier(rawDir, outDir, jumpsFile)
%                                        jumpsFile = CSV with columns
%                                        stem, s_sec, e_sec: hand-verified jump
%                                        episodes (see JUMPING below).
%                                        Pass '' for no jumping label at all.
%
% Every default path is resolved from this file's location, so it can be run
% from the repository root or from Code\Classifier.
%
% Runs the paper's classifier on new animals with the weights it was fitted
% with; nothing is refitted here (build_ethograms.m does the fitting). The
% chain of steps, in order:
%
%   1 clean_pose_v4                 mask and interpolate the SLEAP file,
%                                   calibrated from that file's own lane ends
%   2 build_features_1fps_smoothed  3-frame median filter, then the 8 movement
%                                   measures per second
%   3 window_features               those 8 as mean and SD over +-3, +-10 and
%                                   +-30 s, plus net length change: 51 inputs
%   4 detector_weights_smoothed3    lasso logistic regression, one per
%                                   behavior -> a probability per second
%   5 smooth_bouts                  temporal smoothing: probabilities become
%                                   bouts, with the settings fitted in the paper
%   6 one label per second          among the behaviors on after smoothing,
%                                   the strongest wins; if none is on, the
%                                   strongest overall is still assigned
%
% JUMPING. In the paper, jumping is NOT predicted: it is the hand-verified Jump
% Ledger, and the classifier's own jumping fit is computed but never used. The
% same holds here. Without jumpsFile the label is chosen among stillness,
% elongation and contraction, and the model's jumping probability is written to
% the output for information only. With jumpsFile, those seconds are forced to
% jumping exactly as the paper does, and jumping joins the label set.
% Bend / sway is dropped before the labeling step, as in the paper (its
% intra-rater agreement was too low to use).
%
% OUTPUT, in outDir:
%   <stem>_behavior.csv    one row per second: second, valid, label, and for
%                          each of the four behaviors (bend / sway excluded)
%                          p_<behavior> (the classifier's probability) and
%                          on_<behavior> (1 after temporal smoothing)
%   classifier_summary.csv one row per animal: seconds, % valid and the share
%                          of valid seconds spent in each label
%   work\                  the cleaned trace and the per-second features of
%                          every animal (can be deleted)
%
% Run:  matlab -batch "addpath('Code/Classifier'); run_classifier"

% every default path is built from this file's own location, so the working
% directory does not matter: the repository root is two folders up
HERE = fileparts(mfilename('fullpath'));                 % <repo>\Code\Classifier
REPO = fileparts(fileparts(HERE));                       % <repo>
% the two conditions the behavior analysis uses; with no rawDir, only these
% are labeled, not the other folders of Data\raw_tracking
CONDS = ["Irvine_starved_light_startNearLight", "Irvine_starved_dark_startNear"];
if nargin < 1 || isempty(rawDir),  rawDir = fullfile(REPO,'Data','raw_tracking'); onlyConds = true;
else,                                                    onlyConds = false; end
if nargin < 2 || isempty(outDir),  outDir = fullfile(REPO,'Results','classifier'); end
if nargin < 3, jumpsFile = fullfile(REPO,'Data','labels','jump_ledger.csv'); end
assert(isfolder(rawDir), ['run_classifier: %s not found.\n' ...
    'Unpack the Zenodo raw_tracking folders into <repo>\\Data, or pass rawDir.'], rawDir);
SMOOTH_W = 3;                                            % the paper's median filter

D = load(fullfile(HERE,'detector_weights_smoothed3.mat'));
BEH = cellstr(D.BEH); nB = numel(BEH);
jumpCol = find(strcmp(BEH,'jumping'));
drop = find(strcmp(BEH,'bend_sway'));                    % fitted, never labeled

JUMPS = table();
if ~isempty(jumpsFile)
    assert(isfile(jumpsFile), ['run_classifier: jump file %s not found.\n' ...
        'The Jump Ledger ships in <repo>\\Data\\labels; pass '''' for no jumping label.'], jumpsFile);
    JUMPS = readtable(jumpsFile,'TextType','string');
    assert(all(ismember({'stem','s_sec','e_sec'}, JUMPS.Properties.VariableNames)), ...
        'run_classifier: %s needs the columns stem, s_sec, e_sec', jumpsFile);
end
useBeh = setdiff(1:nB, drop);                            % label set
if isempty(JUMPS), useBeh = setdiff(useBeh, jumpCol); end

% raw files: a folder of CSVs, or a folder of condition folders
if onlyConds
    F = struct([]);
    for i = 1:numel(CONDS), F = [F; dir(fullfile(rawDir,CONDS(i),'*.csv'))]; end %#ok<AGROW>
else
    F = dir(fullfile(rawDir,'*.csv'));
    if isempty(F)
        sub = dir(rawDir); sub = sub([sub.isdir] & ~startsWith({sub.name},'.'));
        for i = 1:numel(sub), F = [F; dir(fullfile(sub(i).folder,sub(i).name,'*.csv'))]; end %#ok<AGROW>
    end
end
assert(~isempty(F), 'run_classifier: no CSV found under %s', rawDir);
[~, iS] = sort({F.name}); F = F(iS);

WORK = fullfile(outDir,'work');
if ~exist(WORK,'dir'), mkdir(WORK); end
S = table();
fprintf('%d files\n  raw  %s\n  out  %s\n', numel(F), rawDir, outDir);
t0 = tic;
for i = 1:numel(F)
    [~, stem] = fileparts(F(i).name); stem = erase(stem,'.analysis');
    fprintf('[%2d/%2d] %-45s', i, numel(F), stem);

    % 1-2. clean, then per-second features from the smoothed positions
    clean_pose_v4(fullfile(F(i).folder, F(i).name), WORK, stem);
    build_features_1fps_smoothed(stem, WORK, WORK, SMOOTH_W);
    T = readtable(fullfile(WORK,[stem '_features1fps.csv']));

    % 3-4. the 51 inputs, then the fitted classifier
    [G, v] = window_features(T);
    v = v & all(isfinite(G),2);
    n = height(T);
    P = nan(n, nB);
    P(v,:) = 1./(1+exp(-(D.COEF(1,:) + ((G(v,:)-D.mu)./D.sd)*D.COEF(2:end,:))));

    % 5. temporal smoothing, behavior by behavior, within each run of valid
    %    seconds (a run shorter than 3 s is left off, as in the paper)
    ON  = false(n, nB);
    LLR = -inf(n, nB);
    q = diff([false; v; false]); s0 = find(q==1); e0 = find(q==-1)-1;
    for b = 1:nB
        p = min(max(P(:,b),1e-6),1-1e-6);
        llr = log(p./(1-p)) - log(D.PRIOR(b)/(1-D.PRIOR(b))) - D.COFF(b);
        llr(~v) = -inf;
        LLR(:,b) = llr;
        for z = 1:numel(s0)
            sl = s0(z):e0(z);
            if numel(sl) < 3, continue; end
            ON(sl,b) = smooth_bouts(llr(sl), D.AT(:,:,b), D.PRIOR(b)) > 0.5;
        end
    end

    % the hand-verified jumps win the vote wherever they are marked
    if ~isempty(JUMPS)
        je = false(n,1);
        jj = JUMPS(JUMPS.stem == string(stem), :);
        for z = 1:height(jj)
            sl = max(jj.s_sec(z),1) : min(jj.e_sec(z), n);
            je(sl) = true;
        end
        ON(:,jumpCol) = je & v;
        LLR(:,jumpCol) = -inf;
        LLR(je & v, jumpCol) = 1e6;
    end

    % 6. one label per second, over the label set only
    lab = strings(n,1);
    L = LLR(:,useBeh); O = ON(:,useBeh);
    Lon = L; Lon(~O) = -inf;
    [~, ix]  = max(Lon, [], 2);
    [~, ix2] = max(L,   [], 2);
    any_on = any(O,2);
    pick = ix; pick(~any_on) = ix2(~any_on);
    names = string(BEH(useBeh));
    lab(v) = names(pick(v));

    % ---- write this animal ----
    % bend / sway is fitted but excluded everywhere, so it is not written out
    Out = table((1:n)', double(v), lab, 'VariableNames', {'second','valid','label'});
    for b = setdiff(1:nB, drop)
        Out.("p_"  + BEH{b}) = P(:,b);
        Out.("on_" + BEH{b}) = double(ON(:,b));
    end
    writetable(Out, fullfile(outDir,[stem '_behavior.csv']));

    r = table(string(stem), n, 100*mean(v), 'VariableNames', {'stem','seconds','pct_valid'});
    for k = 1:numel(useBeh)
        r.("pct_" + BEH{useBeh(k)}) = 100*mean(lab(v) == names(k));
    end
    S = [S; r]; %#ok<AGROW>
    fprintf('  %6d s, %4.1f%% valid\n', n, 100*mean(v));
end
writetable(S, fullfile(outDir,'classifier_summary.csv'));
fprintf('\ndone in %.0f s\nwritten: %s\n', toc(t0), fullfile(outDir,'classifier_summary.csv'));
if isempty(JUMPS)
    fprintf(['NOTE: no jump file given, so the label is one of %s.\n' ...
             '      The jumping column is the model''s own fit, which the paper does not use.\n'], ...
             strjoin(cellstr(names), ', '));
end
disp(S);
end
