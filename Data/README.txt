DATA
====

Tracking data of Hydra moving along a 35 mm lane, with or without a light at
one end.


DOWNLOADING THE TRACKING DATA (GITHUB VS. ZENODO)
-------------------------------------------------
In the GitHub repository, only labels\ and this README.txt are committed.
Because the trajectory archives are large, the three tracking folders
(raw_tracking\, processed_tracking\, and hourly_tracking\) are archived on
Zenodo:

   https://doi.org/10.5281/zenodo.24329561

To run the MATLAB analysis and classifier scripts:
  1. Download the tracking archives (raw_tracking, processed_tracking, and
     hourly_tracking) from the Zenodo deposit above.
  2. Unpack them directly into this Data\ folder so the directory layout is:

        Data\
        ├── labels\               (included in GitHub)
        ├── raw_tracking\         (unpacked from Zenodo)
        ├── processed_tracking\   (unpacked from Zenodo)
        └── hourly_tracking\      (unpacked from Zenodo)

  Extract the folders directly into Data\ (avoid creating a nested
  Data\Data\raw_tracking\ folder). Every MATLAB script resolves paths
  automatically relative to its own location.


FOLDERS
-------

raw_tracking             Tracker output in pixels, one file per animal.
processed_tracking       Positions in mm, one row per 20 s, first 8 h of each
                         recording.
hourly_tracking          Positions in mm, one row per hour, 0 to 48 h.
labels                   Hand labels: verified jumps and labeled behavior.

Each tracking folder has one subfolder per condition.


CONDITIONS
----------

Subfolder names are strain_feeding_light_start.

strain    Kiel, Irvine
feeding   fed, starved
light     light  = light on at one end of the lane for the whole recording
          dark   = no light
start     startFarLight   = animal placed at the end far from the light
          startNearLight  = animal placed at the lit end
          startNear       = dark; animal placed at the same end as in
                            startNearLight

Number of animals in each folder:

Condition                              raw   processed   hourly
Irvine_starved_dark_startNear           15       15        15
Irvine_starved_light_startFarLight      21       21        21
Irvine_starved_light_startNearLight     21       21        21
Kiel_starved_light_startFarLight        24       24        24
Kiel_fed_light_startFarLight            29        -        29
Irvine_fed_light_startFarLight           -        -         6


COORDINATES
-----------

x   Position along the lane in mm. The light is at x = 0, and the lane is
    35 mm long.
y   Position across the lane in mm. The lane is about 7 mm wide.

Three points are tracked on each animal: foot (basal disc), body (mid body
column) and hypostome (head).

Pixels are converted to mm with the two lane ends:
mm per pixel = 35 / distance between the lane ends.


RAW_TRACKING
------------

Irvine (SLEAP export, about 1 frame per second, about 8 h)

  - One header row, then one row per frame in which the animal was detected.
    frame_idx is the frame number; frames with no detection are absent, so
    files of the same recording can differ in length.
  - Columns: track, frame_idx, instance.score, then x, y, score for each of
    foot, body, hypostome (named hypo in some files), L and R. L and R are
    the two ends of the lane; L is the lit end.
  - Units are pixels. Image y increases downward.
  - The interval between frames is slightly longer than 1 s (1.03-1.09 s),
    so recordings of the same duration have 26,500 to 28,000 frames.

Kiel (DeepLabCut format, one labeled image every 20 s)

  - Three header rows (scorer, bodyparts, coords), then one row per labeled
    image. The image name gives the frame number.
  - Body parts: foot, body, hypostome, left_end, right_end (the lane ends),
    each with x and y in pixels.


PROCESSED_TRACKING
------------------

  - One header row, six columns, in mm:
    foot x, foot y, body x, body y, hypostome x, hypostome y.
  - One row per 20 s (Kiel: each labeled image; Irvine: every 20th frame),
    starting at the first frame.
  - Files differ in length (Irvine: 1,325 to 1,398 rows; Kiel: 1,438 rows,
    or 558 rows for the 3.1 h recordings).


HOURLY_TRACKING
---------------

  - One header row, six columns, in mm:
    foot x, foot y, body x, body y, hypostome x, hypostome y.
  - One row per hour, hours 0 to 48 (49 rows).
  - Irvine starved and Irvine fed: one header row (foot_x_mm, foot_y_mm, body_x_mm, body_y_mm,
    hypo_x_mm, hypo_y_mm), then 49 rows.
  - Irvine_fed_JumpCounts.csv gives the number of jumps counted for each of the six animals.
  - Kiel starved and Kiel fed: foot x in mm.


LABELS
------

  - Ground-truth behavioral annotations and verified jump episodes (see
    labels/README.txt for full column definitions).
  - bouts_Irvine_dark.csv and label_KEY_Irvine_dark.csv: second-by-second
    (0 to 59 s) bout labels and clip metadata for 73 1-min training clips
    across 15 Irvine_starved_dark_startNear animals (also scored
    leave-one-animal-out for the Dark panel).
  - bouts_Irvine_startFar.csv and label_KEY_Irvine_startFar.csv:
    second-by-second (0 to 59 s) bout labels and clip metadata for 77 1-min
    training clips across 15 Irvine_starved_light_startFarLight animals.
  - bouts_Irvine_light.csv and label_KEY_Irvine_light.csv: second-by-second
    (0 to 59 s) bout labels and clip metadata for 31 out-of-sample 1-min
    test clips across 16 Irvine_starved_light_startNearLight animals.
  - Behavior codes (beh_id): 1 = stillness, 2 = elongation, 3 = contraction,
    4 = bend_sway, 5 = jumping, 6 = tracking_noise. Classifier evaluation
    scores behaviors 1-3 (plus 5 when jump_ledger.csv is supplied) and
    excludes bend_sway and tracking_noise seconds.
  - jump_ledger.csv: hand-verified jump intervals (columns: stem, s_sec,
    e_sec; 1-based seconds from recording start) used to assign jumping
    labels.