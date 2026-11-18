BEHAVIOR CLASSIFIER: ONE LABEL PER SECOND
==========================================

Labels every second of a raw tracking file as stillness, elongation,
contraction or jumping, reproducing Figures 4F–H in the paper. run_classifier
applies the weights fitted in the paper, which are shipped in this folder.
build_ethograms regrows those weights from the hand labels and reproduces the
leave-one-animal-out Dark panel.


FILES
-----
run_classifier.m                Script to run. Cleaning, features,
                                classifier, temporal smoothing, one label per
                                second, and the output CSVs.

clean_pose_v4.m                 Masks bad tracking, interpolates gaps
                                of up to 20 s, converts pixels to mm using that
                                file's own lane ends.

build_features_1fps_smoothed.m  3-frame median filter on the positions,
                                then 8 movement measures per second.

window_features.m               Those 8 as mean and SD over +-3, +-10
                                and +-30 s, plus the net length change at each
                                scale: the 51 inputs the classifier takes.

smooth_bouts.m                  Temporal smoothing: turns per-second
                                probabilities into bouts.

score_labels.m                  Scores the labels against the hand labels of
                                Data\labels and prints the confusion matrix
                                and the agreement: the Light panel. Run it
                                after run_classifier.

build_ethograms.m               Fits the classifier from the hand labels
                                instead of using the shipped weights, and with
                                'loo' reproduces the Dark panel. Needs the
                                Statistics and Machine Learning Toolbox.

detector_weights_smoothed3.mat  The fitted classifier: COEF (51 weights plus an
                                intercept per behavior), the standardization
                                mu and sd, and the smoothing settings AT, PRIOR
                                and COFF. The weights of the paper, written by
                                build_ethograms.m.


HOW TO RUN
----------
From the repository folder, or from this folder: every default path is resolved
from the script's own location, so the working directory does not matter.

   matlab -batch "addpath('Code/Classifier'); run_classifier; score_labels;"

run_classifier labels the two conditions of the behavior analysis,
Data\raw_tracking\Irvine_starved_light_startNearLight (21 animals) and
Data\raw_tracking\Irvine_starved_dark_startNear (15 animals), taking jumping
from Data\labels\jump_ledger.csv, and writes to Results\classifier. No other
folder of Data\raw_tracking is touched. To point it somewhere else:

   run_classifier(rawDir, outDir)
   run_classifier(rawDir, outDir, jumpsFile)   % '' for no jumping label

About 50 s per 7.5 h animal, 26 min for all 36. No toolbox is required: the
only non-core functions used are interp1/pchip, movmean, movstd and movmedian.

score_labels then prints the Light panel, reading
Data\labels\bouts_Irvine_light.csv and label_KEY_Irvine_light.csv.


INPUT
-----
One SLEAP CSV per animal, as in Data\raw_tracking (Irvine format): one header
row, one row per detected frame, about 1 frame per second, columns

   track, frame_idx, instance.score, then x, y, score for each of
   foot, body, hypostome (or hypo), L and R

L and R are the two ends of the lane. The file is calibrated from them, so no
scale has to be given. The Kiel DeepLabCut files are NOT a valid input: they
are one labeled image every 20 s, and the classifier needs 1 frame per second.


ANIMALS USED IN THE PAPER
-------------------------
The behavior analysis uses two conditions, 21 startNearLight animals and 15
dark startNear animals. Of those 36, the paper analyzes 19 and 14:

   Irvine_starved_light_startNearLight_09    excluded because of poor
   Irvine_starved_light_startNearLight_11    tracking; both carry reviewed = 0
                                             in Data\labels\jump_ledger_animals.csv.
   Irvine_starved_dark_startNear_15          assigned to the classifier's
                                             training set only, and so left out
                                             of the time budget. Not a data
                                             problem: its jump ledger was
                                             reviewed (5 jumps) and nothing is
                                             wrong with its tracking.

All 15 dark animals contributed labeled clips to the fit, so being in the fit
is not what sets this one apart. The other 14 carry a second role as well, as
the comparison set of the time budget, while this animal carries only the
training role; that is the whole of the distinction, and no further reason was
recorded for it. All 15 are in the Dark panel, which is leave-one-animal-out.

run_classifier labels all 36 files, including these three.


OUTPUT
------
In outDir:

   <stem>_behavior.csv   One row per second:
                            second        1..n
                            valid         1 if all three points were tracked
                            label         the behavior of that second
                            p_<behavior>  the classifier's probability (4)
                            on_<behavior> 1 if on after temporal smoothing (4)

                         The four are stillness, elongation, contraction and
                         jumping. Bend / sway is fitted but excluded from this
                         analysis, so it is not written: no p_bend_sway or
                         on_bend_sway column. The column names keep the
                         behavior names of the label files (beh_id order).
   classifier_summary.csv  One row per animal: seconds, % valid, and the share
                           of valid seconds in each label.
   work\                   The cleaned trace and the per-second features of
                           every animal. Only intermediate files: deletable.

The two evaluation scripts write into the same folder:

   label_agreement.csv     score_labels.m. One row per scored animal:
                              animal           file stem
                              labeled_seconds  seconds that could be scored
                              agreement_pct    agreement on those seconds
                           The 16 startNearLight animals of the out-of-sample
                           Light panel. Most have only one or two labeled
                           clips, so a single animal's percentage can rest on
                           60 seconds; the panel quotes the pooled and the
                           median figure instead.
   dark_panel_leave_one_out.csv
                           build_ethograms('loo'). The Dark panel confusion
                           matrix, one row per cell:
                              hand_label        the hand behavior
                              classifier_label  what the classifier said
                              seconds           seconds in that cell
                              row_pct           percent of that hand label's
                                                seconds
                           Every dark animal is labeled by a classifier
                           refitted without it, so these are the
                           leave-one-animal-out numbers, not the shipped
                           classifier scoring its own training seconds.
   detector_weights_refit.mat
                           build_ethograms. The refitted weights, kept for
                           comparison with the shipped ones; see WHAT THE
                           REFIT REPRODUCES below.


JUMPING
-------
In the paper jumping is not predicted. It comes from the hand-verified Jump
Ledger, and the classifier's own jumping fit is computed but never used, so the
figures never present jumping as a model output.

The same holds here, and the Jump Ledger is the default:

   run_classifier              reads Data\labels\jump_ledger.csv without being
                               asked, so the labels are the paper's four:
                               stillness, elongation, contraction, jumping.
                               This is also what run_classifier(rawDir, outDir)
                               does.
   run_classifier(rawDir, outDir, jumpsFile)
                               another jump file: a CSV with the columns stem,
                               s_sec, e_sec, one row per verified jump episode,
                               seconds counted from 1. Those seconds are forced
                               to jumping, as in the paper.
   run_classifier(rawDir, outDir, '')
                               no jump file at all: the label is then one of
                               three, stillness, elongation or contraction.
                               p_jumping and on_jumping are still written, but
                               they are the model's own fit, which the paper
                               does not use.

The ledger is keyed by the file names of Data\raw_tracking. With it, the time
shares in classifier_summary.csv are the paper's four-behavior time budget;
with '' they are shares of three behaviors and are not comparable with it.

Data\labels\jump_ledger_animals.csv lists which animals were reviewed. An
animal with no reviewed ledger gets no jumping label: that is why
Irvine_starved_light_startNearLight_09 and _11 show 0% jumping.


THE TWO PANELS OF THE PAPER
---------------------------
Both are reproducible from this repository, by different routes, because the
two conditions stand in different relations to the fit.

LIGHT PANEL, out of sample

   matlab -batch "addpath('Code/Classifier'); run_classifier; score_labels"

The 16 hand-labeled startNearLight animals, scored against
Data\labels\bouts_Irvine_light.csv and label_KEY_Irvine_light.csv by the rules
in Data\labels\README.txt. None of their seconds were used in the fit, so the
shipped weights are the right ones for them, and this is a fair test.

It reproduces the published matrix exactly: 16 animals, 1,507 labeled
seconds, 72% agreement pooled (78% median over animals), every cell equal.

DARK PANEL, leave one animal out

   matlab -batch "addpath('Code/Classifier'); build_ethograms('loo')"

The dark animals were part of the fit, so scoring them with the shipped
weights would flatter the classifier. Instead each one is labeled by a
classifier refitted without its own labeled seconds, and only then scored.
build_ethograms does the 15 refits and prints the matrix, after first checking
its full fit against the shipped weights. Expect an hour or so, and the
Statistics and Machine Learning Toolbox.

Pointing score_labels at the dark label files instead
(Data\labels\bouts_Irvine_dark.csv) gives an optimistic number, not the one in
the paper.


HOW THE WEIGHTS WERE FITTED
---------------------------
build_ethograms.m, from the hand labels: lasso logistic regression, one model
per behavior, on the labeled 1-min clips of the 15 dark startNear animals
together with those of 15 Irvine_starved_light_startFarLight animals, with the
penalty chosen by 5-fold cross-validation. The temporal-smoothing settings come
from the lengths of the hand-marked bouts and gaps, and one offset per behavior
makes the share of labeled seconds called "on" match the hand labels. The seed
is fixed and the labeled seconds are assembled in a fixed order, so the fit
repeats run to run.

startFarLight is a third condition, which the behavior figures do not analyze:
its labels (Data\labels\bouts_Irvine_startFar.csv) and its recordings are in
the repository so that the fit can be reproduced, and run_classifier never
labels them. The startNearLight animals were never in the fit, which is what
makes the Light panel an out-of-sample test.

build_ethograms writes Results\classifier\detector_weights_refit.mat and
compares it with the shipped weights; it never overwrites them.

WHAT THE REFIT REPRODUCES, AND WHAT IT DOES NOT
It reproduces the training set exactly: the same 6,731 usable labeled seconds
out of 8,400, the same positives per behavior (2,897 stillness, 1,485
elongation, 514 contraction, 931 bend / sway, 1,186 jumping) and the same base
rates as the shipped weights record. The per-second features of all 30
training animals are identical to those of the original build.

The fitted coefficients come back close but not identical. The
cross-validation that picks the penalty lands on a neighboring value for two
of the five behaviors (contraction and bend / sway), which shifts those
models' weights; the standardization mu and sd differ in the third decimal.
The leave-one-animal-out Dark panel therefore comes out at 81% pooled
agreement against the 81.3% of the paper, on exactly the right set of scored
seconds (15 animals, 2,897 seconds, 53 of them with two hand labels), with
every cell of the matrix within about two percentage points.

The Light panel reproduces cell for cell, and the Dark panel reproduces to
rounding. Treat the shipped detector_weights_smoothed3.mat as the weights of
record.


