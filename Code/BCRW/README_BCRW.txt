SYNTHETIC PHOTOTAXIS: BIASED CORRELATED RANDOM WALK (BCRW)
==========================================================

Simulates hydra moving toward a light in the 35 x 7.5 mm chamber, reproducing 
Figures 3B, 3D, and 3E in the paper. Every model parameter is measured from tracked 
hydra; nothing is tuned to make the simulated animals reach the light.

FILES
-----
extract_features_kinematics.m   Reads the tracked hydra (one CSV per animal) and
                                saves the measured features to a .mat file.
BCRW_code.m                     Loads that .mat file, runs the simulation and
                                draws foot trajectories, initial/final positions,
				head angle changes, and head angles.

HOW TO RUN
----------
1. Extract data (optional — skip if using the precomputed .mat files).
2. Simulate. In BCRW_code.m, directly load one of the provided .mat files in
   this folder and set num_hydra (line 37) to the number of animals to
   simulate, then run it.


REQUIREMENTS
------------
MATLAB with:
   - Statistics and Machine Learning Toolbox (fitdist, unifrnd)
   - Mapping Toolbox (wrapTo180, wrapTo360, wrapTo2Pi)
   - Symbolic Math Toolbox (syms, solve; used to stop a jump at the chamber wall)


INPUT DATA
----------
Precomputed .mat feature files for both strains are included in this folder
if you run Step 2 directly. To regenerate them from scratch (Step 1), use
the downsampled trajectory CSVs in processed_tracking/ (available in the
Zenodo dataset):

Each file is one CSV per animal, 6 columns in mm, and one row every 20 s 
(downsampled every 20 frames from raw_tracking/):

   foot x | foot y | body x | body y | hypostome x | hypostome y

Coordinates are in mm within the 35 mm x 7.5 mm chamber, where x is the
distance from the light (the light is at x = 0).


STEP 1: FEATURES MEASURED FROM THE DATA (extract_features_kinematics.m)
-----------------------------------------------------------------------
Each track is used from the start until the foot first comes within 7 mm of the
light (or to its end if it never does).

   Head angle (theta)    Direction from body to hypostome,
                         atan2(y_head - y_body, x_head - x_body), 0-360 deg.
   Turning angle         Change in head angle between consecutive samples,
   (delta theta)         wrapped to -180..180 deg.
   Jump                  Foot moves > 1 mm between consecutive 20-s samples;
                         detections within 3 samples of the previous one count
                         as the same jump.
   Jump distance (d)     Foot displacement of each jump,
                         sqrt((x_t - x_t-1)^2 + (y_t - y_t-1)^2).
   Jump rate             Jumps / number of 20-s samples, one value per animal.

Saved in the .mat file:

   pooled_ang_raw                  head angle of every sample, all animals (deg)
   deltaTheta_total                turning angles, all animals (deg)
   deltaTheta_light / _dark        turning angles split by heading before the
                                   turn (facing the light = 90-270 deg)
   phototaxis.jumpDistancePooled   every jump distance, all animals (mm)
   jump_rates, num_jumps_all       jump rate and jump count per animal
   file_names, settings            which CSVs were used and the thresholds


STEP 2: MODEL PARAMETERS (BCRW_code.m)
--------------------------------------
   Jump rate                lambda = mean of jump_rates across animals
   Jump probability         p = lambda * exp(-lambda), per 20-s step
   Bias strength            R_bias = |mean(exp(i*theta))| over all head angles
   Persistence              R_turn = |mean(exp(i*delta theta))| over all
                            turning angles
   Bias weight              w = R_bias / (R_bias + R_turn)
   Turning noise            kernel density fit to the measured turning angles
                            (bandwidth 2 deg)
   Jump distance            kernel density fit to the measured jump distances


STEP 3: SIMULATION
------------------
For each simulated hydra:
1. Start at x drawn uniformly from 23-35 mm, y = 3.5 mm, with a random heading.
2. Every 20-s step:
   - Heading. With probability w, the heading turns toward the light: the new
     heading is the average of the light direction (180 deg) and the current
     heading, weighted w and 1 - w. Otherwise the heading is kept. A turning
     angle drawn from the turning-noise fit is then added. If the hydra is at a
     wall, the heading is redrawn until it points back into the chamber.
   - Jump. With probability p, the hydra jumps a distance drawn from the
     jump-distance fit along its heading. A jump that would leave the chamber
     stops where it meets the wall. Otherwise the hydra stays where it is.
3. Stop when x < 7 mm (reached the light) or after 1440 steps (8 h).

The random seed is fixed (rng(1, 'twister')), so every run gives identical
results.


OUTPUTS
-------
Command window:
   - Check that the simulation reproduces its inputs: target vs simulated w,
     R_bias and R_turn (computed from the simulated head angles).
   - Table with, per simulated hydra, the number of steps, number of jumps, and
     whether it reached the light (Y/N).

Figures:
   1. Foot traces of simulated hydra 1-3, dots colored by time (0-8 h).
   2. Start vs end x position of every simulated hydra.
   3. Turning angle, real vs simulated.
   4. Head angle, real vs simulated.
