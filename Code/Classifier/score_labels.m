function [M, S] = score_labels(clfDir, boutsFile, keyFile)
%SCORE_LABELS Compare the classifier's labels with the hand labels.
%
%   score_labels()                       scores <repo>\Results\classifier
%                                        against <repo>\Data\labels\
%                                        bouts_Irvine_light.csv and
%                                        label_KEY_Irvine_light.csv
%   score_labels(clfDir)                 clfDir = the folder of
%                                        <stem>_behavior.csv written by
%                                        run_classifier
%   score_labels(clfDir, boutsFile, keyFile)
%                                        another pair of label files, for
%                                        example the dark ones
%
% Every default path is resolved from this file's location, so it can be run
% from the repository root or from Code\Classifier.
%
% Reproduces the confusion matrix and the agreement of the paper's supplemental
% figure for the startNearLight animals. These animals were never used to fit
% the classifier, so the shipped weights are the right ones for them and no
% refitting is involved.
%
% HOW A LABELED SECOND IS SCORED (the paper's rules)
%   - a labeled window is 60 s and starts at startRow of label_KEY: second
%     startRow + s_sec of the 1-per-second trace, with s_sec counted from 0
%   - windows whose kind is "repeat" and that are listed twice are used once
%   - a second counts only if it is inside at least one hand bout, was tracked,
%     and the classifier gave it a label
%   - tracking_noise seconds (beh_id 6) are left out
%   - bend / sway is not in the classifier's label set, so seconds labeled
%     only bend / sway are left out, and in a second with two hand labels
%     bend / sway is ignored
%   - a second with two hand labels counts as the one the classifier scores
%     higher, the score its own one-label step compares
%
% OUTPUT
%   M  the confusion matrix in seconds, rows = hand label, columns =
%      classifier label, in the order stillness, elongation, contraction,
%      jumping
%   S  one row per animal: labeled seconds and agreement
%   and label_agreement.csv in clfDir.
%
% Run:  matlab -batch "addpath('Code/Classifier'); score_labels"

% every default path is built from this file's own location, so the working
% directory does not matter: the repository root is two folders up
HERE = fileparts(mfilename('fullpath'));                 % <repo>\Code\Classifier
REPO = fileparts(fileparts(HERE));                       % <repo>
LAB  = fullfile(REPO,'Data','labels');
if nargin < 1 || isempty(clfDir),    clfDir    = fullfile(REPO,'Results','classifier'); end
if nargin < 2 || isempty(boutsFile), boutsFile = fullfile(LAB,'bouts_Irvine_light.csv'); end
if nargin < 3 || isempty(keyFile),   keyFile   = fullfile(LAB,'label_KEY_Irvine_light.csv'); end
assert(isfile(boutsFile) && isfile(keyFile), ['score_labels: label files not found:\n  %s\n  %s\n' ...
    'Expected them in <repo>\\Data\\labels; pass boutsFile and keyFile to use another pair.'], boutsFile, keyFile);
W = 60;

D = load(fullfile(HERE,'detector_weights_smoothed3.mat'));
BEH = cellstr(D.BEH);
SHOW = [1 2 3 5];                                  % the four labeled behaviors
NAME = BEH(SHOW);
K = readtable(keyFile,'TextType','string');
B = readtable(boutsFile,'TextType','string');

if ismember('kind', K.Properties.VariableNames)    % a window listed twice is used once
    dup = false(height(K),1);
    for i = 1:height(K)
        dup(i) = K.kind(i) == "repeat" && any(K.animal == K.animal(i) & ...
            K.startRow == K.startRow(i) & K.id ~= K.id(i));
    end
    K = K(~dup,:);
end

tr = []; pr = []; an = strings(0,1); nTwo = 0; nWin = 0;
for a = unique(K.animal)'
    f = fullfile(clfDir, a + "_behavior.csv");
    if ~isfile(f)
        fprintf('no classifier output for %s, skipped\n', a); continue;
    end
    T = readtable(f,'TextType','string');
    % the per-behavior scores the one-label step compares; bend / sway is
    % excluded, so it has no column in the file and stays at -inf here
    L = -inf(height(T), numel(BEH));
    for b = SHOW
        p = min(max(T.("p_"+BEH{b}), 1e-6), 1-1e-6);
        L(:,b) = log(p./(1-p)) - log(D.PRIOR(b)/(1-D.PRIOR(b))) - D.COFF(b);
    end
    jc = find(strcmp(BEH,'jumping'));              % jumping is the Jump Ledger
    L(:,jc) = -inf; L(T.("on_"+BEH{jc})==1, jc) = 1e6;

    for i = find(K.animal == a)'
        r = K.startRow(i) + (0:W-1)';
        if r(end) > height(T), continue; end
        nWin = nWin + 1;
        bb = B(B.id == K.id(i), :);
        y = false(W, numel(BEH)); nz = false(W,1);
        for z = 1:height(bb)
            sl = bb.s_sec(z)+1 : min(bb.e_sec(z)+1, W);
            if bb.beh_id(z) == 6, nz(sl) = true; else, y(sl, bb.beh_id(z)) = true; end
        end
        for t = 1:W
            lab = find(y(t,:));
            lab = intersect(lab, SHOW);            % bend / sway is not scored
            if isempty(lab) || nz(t) || T.valid(r(t)) ~= 1 || T.label(r(t)) == "", continue; end
            if numel(lab) > 1
                nTwo = nTwo + 1;
                [~, ix] = max(L(r(t), lab)); lab = lab(ix);
            end
            tr(end+1,1) = find(SHOW == lab);                       %#ok<AGROW>
            pr(end+1,1) = find(strcmp(NAME, T.label(r(t))));       %#ok<AGROW>
            an(end+1,1) = a;                                       %#ok<AGROW>
        end
    end
end
assert(~isempty(tr), 'score_labels: no labeled second could be scored. Has run_classifier been run on these animals?');

M = accumarray([tr pr], 1, [numel(SHOW) numel(SHOW)]);
S = table();
for a = unique(an)'
    s = an == a;
    S = [S; table(a, sum(s), 100*mean(tr(s)==pr(s)), ...
        'VariableNames', {'animal','labeled_seconds','agreement_pct'})]; %#ok<AGROW>
end
writetable(S, fullfile(clfDir,'label_agreement.csv'));

Rw = 100 * M ./ max(sum(M,2),1);
fprintf('\n%d animals, %d labeled windows, %d labeled seconds (%d with two hand labels)\n', ...
    numel(unique(an)), nWin, numel(tr), nTwo);
fprintf('agreement %.0f%% pooled, %.0f%% median over animals\n\n', ...
    100*mean(tr==pr), median(S.agreement_pct));
fprintf('%-14s %s   hand s\n', 'hand \ clf', sprintf('%12s', NAME{:}));
for i = 1:numel(SHOW)
    fprintf('%-14s %s   %6d\n', NAME{i}, sprintf('%11.0f%%', Rw(i,:)), sum(M(i,:)));
end
fprintf('\nper animal: %s\n', fullfile(clfDir,'label_agreement.csv'));
end
