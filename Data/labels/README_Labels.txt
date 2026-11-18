LABELS
======

Hand-made ground truth for the Irvine starved Hydra: verified jump episodes,
and second-by-second behavior labels in sampled 1-min clips. These are the
files used to fit the behavior classifier (build_ethograms.m) and to score it
(score_labels.m). Animals are named by their file stem in Data\raw_tracking.

Nothing in this folder can be regenerated from anything else in the
repository.


FILES
-----
jump_ledger.csv                 339 hand-verified jump episodes, 33 animals.
                                run_classifier reads this to label jumping.
jump_ledger_animals.csv         One row per animal of the two analyzed
                                conditions (36): whether its ledger was
                                reviewed, whether it was flagged as excluded,
                                and its number of jumps.
jump_ledger_json\               The ledger as the labeling tool exported it,
                                one file per animal (35). Intervals there are
                                counted from 0, and "notjumps" are candidates
                                marked as not a jump. Provenance only; the
                                code reads jump_ledger.csv.

bouts_Irvine_light.csv          Behavior bouts in 31 clips of 16
label_KEY_Irvine_light.csv      Irvine_starved_light_startNearLight animals.
                                None of these seconds were used in the fit:
                                this is the held-out test set, scored by
                                score_labels.m (1,507 seconds).

bouts_Irvine_dark.csv           Behavior bouts in 73 clips of all 15
label_KEY_Irvine_dark.csv       Irvine_starved_dark_startNear animals. Part of
                                the training set, and the set scored
                                leave-one-animal-out for the Dark panel.

bouts_Irvine_startFar.csv       Behavior bouts in 77 clips of 15
label_KEY_Irvine_startFar.csv   Irvine_starved_light_startFarLight animals.
                                The rest of the training set. This condition
                                is not analyzed in the behavior figures; its
                                labels are here only so the fit can be
                                reproduced.

sealed_animals.csv              The 30 training animals, their condition
                                (noLight = dark startNear, startDark =
                                startFarLight) and the plate each came from.
                                build_ethograms reads it for the animal order
                                of the fit. The "sealed" flag marks five dark
                                animals held back during development; it is
                                not an exclusion in the paper, where all 15
                                appear in the Dark panel.

Training set: 150 clips, 692 bout rows (dark + startFarLight).
Test set:      31 clips, 141 bout rows (startNearLight).


READING A LABELED CLIP
-----------------------
A clip is 60 s long and starts at startRow of its label_KEY file. startRow is
a 1-based row of the 1-per-second trace, which is also the 1-based data row of
the raw SLEAP CSV (its header excluded), since the per-second trace keeps one
row per raw row. In the bouts file s_sec and e_sec are counted from 0 within
the clip, so a bout covers the seconds

   startRow + s_sec  to  startRow + e_sec

The startFrame column of bouts_Irvine_dark.csv and bouts_Irvine_startFar.csv
is the SLEAP frame_idx, which is NOT that number: SLEAP omits frames with no
detection, so by the end of a recording the frame index runs up to 18 ahead of
the row. Use startRow.


BEHAVIOR CODES
--------------
   beh_id  behavior        how it is used
   1       stillness       predicted by the classifier
   2       elongation      predicted by the classifier
   3       contraction     predicted by the classifier
   4       bend_sway       fitted, then excluded: its intra-rater agreement
                           was too low to use, so it is dropped before the
                           one-label step and never scored
   5       jumping         taken from jump_ledger.csv, not predicted
   6       tracking_noise  not a behavior: excluded from fitting and scoring


THREE RULES FOR SCORING
-----------------------
The same rules are applied by score_labels.m and build_ethograms.m:

  - tracking_noise seconds (beh_id 6) are left out.
  - bouts of different behaviors may overlap, so a second can carry two hand
    labels: 23% of the labeled seconds do. Such a second counts as the one
    the classifier scores higher.
  - a clip whose kind is "repeat" is a second labeling pass over a clip
    already labeled; where the same animal and startRow appear twice, the
    clip is used once. (These duplicates measure the labeler against
    themself.)


HOW THE CLIPS WERE PICKED
-------------------------
The kind column of each label_KEY file: "random" clips were sampled blind,
while "enriched_jumping" and "enriched_contraction" clips were chosen to
contain rare behaviors, using the clip's net body-length change (dL_net, mm)
and net foot displacement (foot_disp, mm). The labeled minutes are therefore
NOT a random sample of time: rare behaviors are over-represented on purpose,
which is why the confusion matrix holds 940 seconds of stillness against 86 of
contraction.


HOW THEY ARE USED
-----------------
  - fitting (build_ethograms.m): the dark and startFarLight clips.
  - the Dark panel: the dark clips, each animal scored by a classifier
    refitted without it (build_ethograms('loo')).
  - the Light panel: the startNearLight clips, scored against the shipped
    weights (score_labels.m). These animals were never in the fit.
  - jumping (run_classifier): jump_ledger.csv supplies the verified episodes
    for every animal.
