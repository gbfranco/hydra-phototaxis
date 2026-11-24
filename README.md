# Hydra phototaxis: code and hand labels

Analysis code for _Hydra_ moving along a 35 mm lane, BCRW, and the behavior classifier. The
tracking data itself comes from the Zenodo archive (see **Getting the data**).

## Structure

```
Code/
  Classifier/   one behavior label per second: apply, fit, score
  BCRW/         the biased correlated random-walk simulation
Data/
  labels/       hand labels: verified jumps and labeled 1-min clips
  README.txt    conditions, file formats, coordinates
```

Running the code creates a `Results/` folder. Everything in it is derived and
can be deleted; it rebuilds from `Code` and `Data`.

### Code/Classifier

Labels every second of a recording as stillness, elongation, contraction or
jumping, for the two conditions of the behavior analysis:
`Irvine_starved_light_startNearLight` and `Irvine_starved_dark_startNear`.

| File                             | Role                                                                                                        |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `run_classifier.m`               | the script to run: cleaning, features, classifier, temporal smoothing, one label per second                 |
| `score_labels.m`                 | scores those labels against the hand labels: the out-of-sample Light panel                                  |
| `build_ethograms.m`              | refits the classifier from the hand labels, and with `'loo'` reproduces the leave-one-animal-out Dark panel |
| `clean_pose_v4.m`                | masks bad tracking, interpolates short gaps, converts pixels to mm                                          |
| `build_features_1fps_smoothed.m` | eight movement measures per second                                                                          |
| `window_features.m`              | those eight over ±3, ±10 and ±30 s: the 51 inputs                                                           |
| `smooth_bouts.m`                 | temporal smoothing                                                                                          |
| `detector_weights_smoothed3.mat` | the fitted classifier of the paper                                                                          |

`README_Classifier.txt` in that folder documents the inputs, the outputs, how
jumping is handled and how to reproduce each panel.

### Code/BCRW

Simulates movement toward the light with every parameter measured from tracked
animals. `extract_features_kinematics.m` measures them, `BCRW_code.m` runs the
simulation and draws the figures, and the two `.mat` files are those
measurements precomputed, so the simulation runs without the tracking data.
See `README_BCRW.txt`.

### Data/labels

Hand-made ground truth, and the only data here that no code can regenerate:
the Jump Ledger (339 verified jump episodes) and behavior bouts in 1-min clips
of three conditions. The `light` clips are the held-out test set; the `dark`
and `startFar` clips are together the training set. `Data/labels/README.txt`
explains the clip format, the behavior codes and the scoring rules.

## Running it

From this folder, in MATLAB R2024b:

```matlab
addpath('Code/Classifier')
run_classifier     % labels the 36 animals of the two conditions
score_labels       % prints the confusion matrix of the Light panel
```

`run_classifier` and `score_labels` need base MATLAB only.
`build_ethograms` needs the Statistics and Machine Learning Toolbox, and the
BCRW scripts additionally need the Mapping and Symbolic Math Toolboxes.

## Getting the data

The tracking folders are distributed through Zenodo: https://doi.org/10.5281/zenodo.24329561. Unpack the archive into `Data` so that the condition folders sit directly inside `Data/raw_tracking`, `Data/processed_tracking` and `Data/hourly_tracking`.

## Licensing

Code: MIT. Data, including the Zenodo archive and the hand labels here:
CC BY 4.0. Please cite the paper and the dataset.
