%% extract_features_kinematics.m
% Kinematic features of tracked hydra used to parameterise the biased correlated
% random walk (BCRW) simulation of phototaxis.
%
% Input   one CSV per animal, one header row, 6 columns in mm, one row per 20 s:
%         foot x, foot y, body x, body y, hypostome x, hypostome y
%         (x = distance from the light; the light is at x = 0)
% Output  a .mat file read by the simulation:
%   phototaxis.jumpDistancePooled  size of every detected jump [mm], all animals
%   jump_rates                     jumps per 20-s step, one value per animal
%   num_jumps_all                  detected jumps, one value per animal
%   pooled_ang_raw                 head angle of every sample [deg, 0-360]
%   deltaTheta_total               turning angles [deg, -180..180]
%   deltaTheta_light / _dark       turning angles split by the heading before the
%                                  turn (facing the light = 90-270 deg)

% Requires: Mapping Toolbox (wrapTo2Pi, wrapTo360) or MATLAB's shared maputils.
% ------------------------------------------------------------------------
clear; clc;

%% ====== Settings ======
% folder_path = 'PathToFile\Hydra-phototax-repo\Data\processed_tracking\Irvine_starved_light_startFarLight';
% out_file    = 'OutputPath\Irvine_extracted_features_starved_startFar.mat';

script_dir  = fileparts(mfilename('fullpath'));
folder_path = fullfile(script_dir, '..', '..', 'Data', 'processed_tracking', 'Irvine_starved_light_startFarLight');
out_file    = fullfile(script_dir, 'Irvine_extracted_features_starved_startFar.mat');


x_threshold    = 7;     % [mm] arrival at the light: analysis stops here
jump_threshold = 1.0;   % [mm] minimum foot displacement per 20-s step for a jump
min_jump_dist  = 3;     % [samples] detections closer than this belong to one jump
dt_s           = 20;    % [s] time between samples

%% ====== Load ======
csvfiles  = dir(fullfile(folder_path, '*.csv'));
[~, order] = sort({csvfiles.name});
csvfiles  = csvfiles(order);
num_files = numel(csvfiles);
assert(num_files > 0, 'No CSV files in %s', folder_path);
fprintf('%d animals in %s\n', num_files, folder_path);

%% ====== Per-animal features ======
num_jumps_all   = zeros(num_files, 1);
jump_rates      = zeros(num_files, 1);
all_jump_size   = cell(num_files, 1);
angleRad_pooled = [];

for f = 1:num_files
    C = readCoordinates(fullfile(csvfiles(f).folder, csvfiles(f).name));

    % analyze until the foot first comes within x_threshold of the light
    endIdx = find(C.X_foot <= x_threshold, 1);
    if isempty(endIdx), endIdx = numel(C.X_foot); end
    C = structfun(@(v) v(1:endIdx), C, 'UniformOutput', false);
    n_frames = endIdx;

    % head angle [rad, 0-2pi]
    head_angle = wrapTo2Pi(atan2(C.Y_head - C.Y_body, C.X_head - C.X_body));
    angleRad_pooled = [angleRad_pooled; head_angle(:)]; %#ok<AGROW>

    % jumps
    [jump_size, num_jumps] = detectJumps(C.X_foot, C.Y_foot, jump_threshold, min_jump_dist);
    num_jumps_all(f) = num_jumps;
    all_jump_size{f} = jump_size;
    jump_rates(f)    = num_jumps / n_frames;            % jumps per 20-s step
end

%% ====== Pooled features ======
jump_sizes_pooled = vertcat(all_jump_size{:});

theta  = rad2deg(angleRad_pooled);                         % head angle [deg]
dTheta = rad2deg(angle(exp(1i * deg2rad(diff(theta)))));   % turns, wrapped to (-180, 180]

current_heading  = wrapTo360(theta(1:end-1));              % heading before each turn
is_facing_light  = (current_heading >= 90) & (current_heading <= 270);
deltaTheta_light = dTheta(is_facing_light);
deltaTheta_dark  = dTheta(~is_facing_light);
deltaTheta_total = dTheta;

phototaxis = struct('jumpDistancePooled', jump_sizes_pooled);
pooled_ang_raw = theta;

%% ====== Summary ======
fprintf('Jumps: %d in total (%.1f per animal); mean jump rate %.4f per 20-s step\n', ...
    sum(num_jumps_all), mean(num_jumps_all), mean(jump_rates));
fprintf('Jump size: median %.2f mm (n = %d)\n', median(jump_sizes_pooled), numel(jump_sizes_pooled));
fprintf('Head-angle samples: %d; turns: %d (%d facing light, %d facing dark)\n', ...
    numel(theta), numel(deltaTheta_total), numel(deltaTheta_light), numel(deltaTheta_dark));

%% ====== Save ======
file_names = {csvfiles.name}';
settings = struct('folder_path', folder_path, 'x_threshold_mm', x_threshold, ...
    'jump_threshold_mm', jump_threshold, 'min_jump_dist_samples', min_jump_dist, ...
    'dt_s', dt_s, 'created', char(datetime('now')));
save(out_file, 'phototaxis', 'jump_rates', 'num_jumps_all', 'pooled_ang_raw', ...
    'deltaTheta_total', 'deltaTheta_light', 'deltaTheta_dark', 'file_names');
fprintf('Saved %s\n', out_file);

%% ====== Functions ======

function C = readCoordinates(csv_file)
% Six coordinate columns (mm) of one animal as column vectors.
    M = readmatrix(csv_file);
    names = {'X_foot', 'Y_foot', 'X_body', 'Y_body', 'X_head', 'Y_head'};
    for k = 1:numel(names)
        C.(names{k}) = M(:, k);
    end
end

function [jump_size, num_jumps] = detectJumps(x_foot, y_foot, jump_threshold, min_distance)
% Jumps: foot displacement > jump_threshold between consecutive samples; a
% detection within min_distance samples of the previous detection is dropped.
    dz  = hypot(diff(x_foot(:)), diff(y_foot(:)));
    idx = find(dz > jump_threshold);
    if isempty(idx)
        jump_size = zeros(0, 1);
    else
        idx = idx([true; diff(idx) > min_distance]);
        jump_size = dz(idx);
    end
    num_jumps = numel(jump_size);
end
