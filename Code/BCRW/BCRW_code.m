% Synthetic phototaxis (biased correlated random walk)
% ---- Gabriela Franco
% Requires: Statistics and Machine Learning, Mapping (wrapTo180/wrapTo360/wrapTo2Pi),
%           Symbolic Math (syms/solve in redirect and compare_ang)
% ------------------------------------------------------------------------
clear all; clc; close all
rng(1, 'twister');                       % fixed seed: identical simulation every run

% --- Time ---------------------------------------------------------------
iter = 8 * 60*60 / 20;                   % 1440 steps of 20 s = 8 h
dt = 1;
dt_s = 20;                               % seconds per step
total_run = floor(iter/dt);
GREY    = [0.55 0.55 0.55];              % experimental

% --- Import data --------------------------------------------------------
script_dir = fileparts(mfilename('fullpath'));
starved_data = load(fullfile(script_dir, 'Irvine_extracted_features_starved_startFar.mat'));

% --- Model parameters from the data -------------------------------------
global params target_theta deltaTheta_total_kernel x_high x_low y_high y_low
params = estimate_BCRW_params(starved_data.pooled_ang_raw);
w = params.w;

% turning noise: kernel fit to the measured turning angles
deltaTheta_total_kernel = fitdist(starved_data.deltaTheta_total, 'Kernel', 'BandWidth', 2);

% jump distance: kernel fit to the measured jump distances
pooled_dist_raw = starved_data.phototaxis.jumpDistancePooled;
pooled_dist_raw(isnan(pooled_dist_raw)) = [];
pooled_dist_kernel = fitdist(pooled_dist_raw, 'Kernel');

% jump probability per step
lambda = mean(starved_data.jump_rates);
p = lambda * exp(-lambda);

% --- Number of simulated hydra ------------------------------------------
num_hydra = 21;

% --- Bias direction and chamber -----------------------------------------
target_theta = 180;                      % light direction [deg]
x_low = 0; x_high = 35;                  % chamber [mm]
y_low = 0; y_high = 7.5;
thresh = 7;                              % [mm] arrival at the light

%% --- Simulate --------------------------------------------------------------
numIter_actualRun = zeros(1, num_hydra);
numJumps    = zeros(1, num_hydra);
x_coord     = cell(1, num_hydra);
y_coord     = cell(1, num_hydra);
x_first     = zeros(1, num_hydra);
x_last      = zeros(1, num_hydra);
angle_record = cell(1, num_hydra);
Reach_Light = repmat('?', num_hydra, 1);

for jj = 1:num_hydra
    x = NaN(1, total_run);
    y = NaN(1, total_run);
    x(1) = unifrnd(23, 35);
    y(1) = 3.5;
    ang = zeros(1, total_run);

    for ii = 1:total_run-1
        % stop when the hydra reaches the light
        if x(ii) < thresh
            numIter_actualRun(jj) = ii;
            x(ii+1:end) = [];
            y(ii+1:end) = [];
            ang(ii:end) = [];
            Reach_Light(jj) = 'Y';
            break;
        elseif ii == total_run - 1           % 8-h limit
            numIter_actualRun(jj) = total_run;
            Reach_Light(jj) = 'N';
        end

        % heading: random at the start, then BCRW (redrawn at a wall)
        if ii == 1
            ang(ii) = 360*rand;
        else
            ang(ii) = isAtEdge(x(ii), y(ii), ii, ang);
        end

        % jump with probability p
        if rand(1) < p
            numJumps(jj) = numJumps(jj) + 1;
            step_d = pooled_dist_kernel.random(1);
            xtemp = x(ii) + step_d * cosd(ang(ii));
            ytemp = y(ii) + step_d * sind(ang(ii));
            [x(ii+1), y(ii+1)] = redirect(x(ii), y(ii), xtemp, ytemp);   % stop at the wall
        else
            x(ii+1) = x(ii);
            y(ii+1) = y(ii);
        end
    end

    % a hydra that never arrived has one unset final heading (0 deg): drop it
    if Reach_Light(jj) == 'N'
        ang(end) = [];
    end

    angle_record{jj} = ang;
    x_coord{jj} = x;
    y_coord{jj} = y;
    x_first(jj) = x(1);
    x_last(jj)  = x(numIter_actualRun(jj));
    fprintf('Hydra #%d: %d steps\n', jj, numIter_actualRun(jj));
end
fprintf('---- SIMULATION COMPLETE FOR %d HYDRA ----\n', num_hydra);

% pooled simulated headings and within-animal turning angles
all_sim_angles = [];
dth_sim = [];
for jj = 1:num_hydra
    a = angle_record{jj}(:);
    all_sim_angles = [all_sim_angles; a];                 %#ok<AGROW>
    dth_sim        = [dth_sim; wrapTo180(diff(a))];       %#ok<AGROW>
end

% --- Validation and summary (command window) --------------------------------
params_sim = estimate_BCRW_params(all_sim_angles);
fprintf('\n--- VALIDATION ---\n');
fprintf('Target w      : %.4f | Simulated w      : %.4f\n', w, params_sim.w);
fprintf('Target R_bias : %.4f | Simulated R_bias : %.4f\n', params.R_bias, params_sim.R_bias);
fprintf('Target R_turn : %.4f | Simulated R_turn : %.4f\n', params.R_turn, params_sim.R_turn);

summary = table((1:num_hydra)', numIter_actualRun', numJumps', Reach_Light, ...
    'VariableNames', {'Hydra_Num','Runtime','Num_Jumps','Reached_Light'})

%% Simulated foot traces (hydra 1-3)
dt_s  = 20; t_max = 8;
c0 = [1.0 0.9 0.2];                 % yellow (0 h)
c1 = [0.1 0.4 0.7];                 % dark blue (8 h)   (Kiel: [0.6 0.1 0.1])
time_cmap = [linspace(c0(1), c1(1), 256)', linspace(c0(2), c1(2), 256)', linspace(c0(3), c1(3), 256)'];
show_gradient = true;               % white at the light (x = 0) -> grey at the far end
grey_far = [0.65 0.65 0.65];

fig1 = figure();                    % default size, as in the original
trace_ids = 1:3;
for k = 1:numel(trace_ids)
    jj  = trace_ids(k);
    x_pos = x_coord{jj}(:); y_pos = y_coord{jj}(:);
    t_h = (0:numel(x_pos)-1)' * dt_s / 3600;      % real time of each step (h)

    ax = subplot(numel(trace_ids), 1, k); hold(ax, 'on');
    if show_gradient
        patch(ax, [0 35 35 0], [0 0 8 8], 'k', 'FaceColor', 'interp', 'EdgeColor', 'none', ...
              'FaceVertexCData', [1 1 1; grey_far; grey_far; 1 1 1]);
    end
    plot(ax, x_pos, y_pos, '-k', 'LineWidth', 1.5);
    s = scatter(ax, x_pos, y_pos, 80, t_h, 'filled');
    s.MarkerFaceAlpha = 0.7;
    s.MarkerEdgeColor = 'none';
    colormap(ax, time_cmap); clim(ax, [0 t_max]);

    cb = colorbar(ax);
    cb.Location = 'northoutside';
    cb.Ticks = [0 t_max]; cb.TickLabels = {'0 h', sprintf('%g h', t_max)};
    cb.FontSize = 10; cb.Box = 'off';

    xlim(ax, [0 35]); ylim(ax, [0 8]); xticks(ax, 0:5:35);
    set(ax, 'YTickLabel', [], 'XTickLabel', [], 'Layer', 'top');
    box(ax, 'on');
    hold(ax, 'off');
end

%% Start vs end position 
x_first_last = [x_first; x_last]';
marker_blue = [0.12 0.56 0.95];
fig2 = figure('Color', 'w', 'Position', [100 100 300 450]);
hold on;
plot([1 2], x_first_last', '-', 'Color', [0.25 0.25 0.25], 'LineWidth', 1);        % lines first
plot([1 2], x_first_last', 'o', 'MarkerSize', 8, ...
    'MarkerFaceColor', marker_blue, 'MarkerEdgeColor', 'none');                 % dots on top
xlim([0.8 2.2]);
ylim([0 35]);
xticks([1 2]);
xticklabels({'Start', 'End'});
yticks(0:10:40);
ylabel('X position (mm)', 'Color', 'k');
box off;
set(gca, 'FontName', 'Arial', 'FontSize', 24, 'LineWidth', 0.8, 'TickDir', 'in', ...
    'XColor', [0.2 0.2 0.2], 'YColor', [0.2 0.2 0.2]);

%% Turning angle: real vs synthetic 
fig3 = figure;
histogram(starved_data.deltaTheta_total, 'BinWidth', 5, 'FaceAlpha', 0.5, ...
    'EdgeColor', 'none', 'Normalization', 'probability'); hold on;
histogram(dth_sim, 'BinWidth', 5, 'FaceAlpha', 0.5, ...
    'EdgeColor', 'none', 'Normalization', 'probability');                       % within-hydra turns, all hydra
legend({'Real', 'Synthetic'});
xlabel('\Delta\theta (deg)');
ylabel('Probability');

%% Head angle: real vs synthetic 
fig4 = figure;
subplot(1, 2, 1);
polarhistogram(deg2rad(starved_data.pooled_ang_raw), 10, 'Normalization', 'probability', ...
    'FaceAlpha', 0.5, 'EdgeColor', 'none');
title('Real');
rlim([0 0.4]);
subplot(1, 2, 2);
polarhistogram(deg2rad(all_sim_angles), 10, 'Normalization', 'probability', ...
    'FaceAlpha', 0.5, 'EdgeColor', 'none');                                    % all simulated hydra pooled
title('Synthetic');
rlim([0 0.4]);



%% ========================= functions =====================================

function styleAxes(ax, fs)
    set(ax, 'FontName', 'Arial', 'FontSize', fs, 'LineWidth', 0.75, 'TickDir', 'out', ...
        'Box', 'off', 'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15]);
end

function stylePolar(pax, rmax, ttl, fs, fsTitle)
    lab = repmat({''}, 1, 12); lab([1 4 7 10]) = {'0°','90°','180°','270°'};
    set(pax, 'ThetaTick', 0:30:330, 'ThetaTickLabel', lab, 'RLim', [0 rmax], ...
        'RTick', 0:0.05:rmax, 'RAxisLocation', 80, 'FontName', 'Arial', 'FontSize', fs, ...
        'LineWidth', 1, 'GridColor', [0.6 0.6 0.6], 'GridAlpha', 0.45, ...
        'RColor', [0.15 0.15 0.15], 'ThetaColor', [0.15 0.15 0.15]);
    title(pax, ttl, 'FontName', 'Arial', 'FontSize', fsTitle, 'FontWeight', 'bold');
end

function num_frames = plotFootTrace(foot, ax, color_mode, time_vector, t_max, show_cbar, FS)
% Foot trace of one animal: black line, dots colored by real time (0..t_max h).
    x_pos = foot(:,1); y_pos = foot(:,2);
    num_frames = numel(x_pos);
    hold(ax, 'on');
    plot(ax, x_pos, y_pos, '-k', 'LineWidth', 0.75);
    s = scatter(ax, x_pos, y_pos, 12, time_vector, 'filled');
    s.MarkerFaceAlpha = 0.7; s.MarkerEdgeColor = 'none';
    color_yellow = [1.0 0.9 0.2];                                  % 0 h
    if strcmpi(color_mode, 'blue'), color_end = [0.1 0.4 0.7];      % 8 h
    else,                           color_end = [0.6 0.1 0.1]; end
    nColors = 256;
    colormap(ax, [linspace(color_yellow(1), color_end(1), nColors)', ...
                  linspace(color_yellow(2), color_end(2), nColors)', ...
                  linspace(color_yellow(3), color_end(3), nColors)']);
    clim(ax, [0 t_max]);
    if show_cbar
        pos0 = ax.Position;
        cb = colorbar(ax);
        cb.Location = 'northoutside';
        cb.Ticks = [0 t_max];
        cb.TickLabels = {'0 h', sprintf('%g h', t_max)};
        cb.FontSize = FS - 1; cb.FontName = 'Arial'; cb.Box = 'off';
        ax.Position = pos0;
        cb.Position = [pos0(1) + 0.6*pos0(3), pos0(2) + pos0(4) + 0.035, 0.4*pos0(3), 0.008];
    end
    xlim(ax, [0 35]); ylim(ax, [min([0; y_pos]) 8]);
    set(ax, 'XTick', 0:5:35, 'XTickLabel', [], 'YTickLabel', [], 'Box', 'on', 'LineWidth', 0.5);
    hold(ax, 'off');
end

function [xtemp_update, ytemp_update, direction] = redirect(prev_x, prev_y, xtemp, ytemp)
% If a jump would leave the chamber, stop it where it meets the wall.
    global x_high x_low y_high y_low
    n1 = (xtemp <= x_high && xtemp >= x_low);
    n2 = (ytemp <= y_high && ytemp >= y_low);
    normal = n1 & n2;
    up    = (xtemp <= x_high && xtemp >= x_low) && (ytemp > y_high);
    down  = (xtemp <= x_high && xtemp >= x_low) && (ytemp < y_low);
    left  = (xtemp < x_low)  && (ytemp <= y_high && ytemp >= y_low);
    right = (xtemp > x_high) && (ytemp <= y_high && ytemp >= y_low);
    upperLeft  = (xtemp < x_low)  && (ytemp > y_high);
    upperRight = (xtemp > x_high) && (ytemp > y_high);
    lowerLeft  = (xtemp < x_low)  && (ytemp < y_low);
    lowerRight = (xtemp > x_high) && (ytemp < y_low);
    if normal
        xtemp_update = xtemp; ytemp_update = ytemp; direction = 'normal';
        return
    end
    syms xx yy
    eqn = yy == ((ytemp-prev_y)/(xtemp-prev_x))*(xx-prev_x) + prev_y;
    if up,    S = subs(eqn,yy,y_high); xtemp_update = double(solve(S,xx)); ytemp_update = y_high; direction = 'up';    end
    if down,  S = subs(eqn,yy,y_low);  xtemp_update = double(solve(S,xx)); ytemp_update = y_low;  direction = 'down';  end
    if right, S = subs(eqn,xx,x_high); xtemp_update = x_high; ytemp_update = double(solve(S,yy)); direction = 'right'; end
    if left,  S = subs(eqn,xx,x_low);  xtemp_update = x_low;  ytemp_update = double(solve(S,yy)); direction = 'left';  end
    if upperLeft,  [xtemp_update, ytemp_update] = compare_ang([x_low,  y_high], prev_x, prev_y, xtemp, ytemp); direction = 'upperLeft';  end
    if lowerLeft,  [xtemp_update, ytemp_update] = compare_ang([x_low,  y_low],  prev_x, prev_y, xtemp, ytemp); direction = 'lowerLeft';  end
    if upperRight, [xtemp_update, ytemp_update] = compare_ang([x_high, y_high], prev_x, prev_y, xtemp, ytemp); direction = 'upperRight'; end
    if lowerRight, [xtemp_update, ytemp_update] = compare_ang([x_high, y_low],  prev_x, prev_y, xtemp, ytemp); direction = 'lowerRight'; end
end

function [new_angle] = isAtEdge(prev_x, prev_y, current_idx, ang_array)
% At a wall, redraw the heading until it points back into the chamber.
    global x_low x_high y_low y_high
    xlowbound  = (prev_x <= x_low);
    xhighbound = (prev_x >= x_high);
    ylowbound  = (prev_y <= y_low);
    yhighbound = (prev_y >= y_high);
    if ~(xlowbound | xhighbound | ylowbound | yhighbound)
        new_angle = compute_BCRW(ang_array(current_idx-1));
    else
        while true
            new_angle = compute_BCRW(ang_array(current_idx-1));
            if (xlowbound  && (new_angle <= 90 || new_angle >= 270)), break; end
            if (xhighbound && (new_angle >= 90 && new_angle <= 270)), break; end
            if (ylowbound  && (new_angle >= 0  && new_angle <= 180)), break; end
            if (yhighbound && (new_angle >= 180 && new_angle <= 360)), break; end
        end
    end
end

function [x_adjust, y_adjust] = compare_ang(ref, currx, curry, nextx, nexty)
% Corner case of redirect: which wall the jump meets first.
    syms xx yy
    eqn = yy == ((nexty-curry)/(nextx-currx))*(xx-currx) + curry;
    refx = ref(1); refy = ref(2);
    slope_ref = abs((refy-curry)/(refx-currx));
    slope_vec = abs((nexty-curry)/(nextx-currx));
    if slope_vec > slope_ref
        y_adjust = refy; x_adjust = double(solve(subs(eqn,yy,y_adjust),xx));
    elseif slope_vec < slope_ref
        x_adjust = refx; y_adjust = double(solve(subs(eqn,xx,x_adjust),yy));
    else                                    % exactly through the corner
        x_adjust = refx; y_adjust = refy;
    end
end

function newAngle = compute_BCRW(currAngle)
% With probability w steer toward the light (vector average of the light
% direction and the current heading); otherwise keep the heading. Then add
% turning noise drawn from the measured turning angles.
    global target_theta deltaTheta_total_kernel params
    w = params.w;
    if rand < w
        next_x = w * cosd(target_theta) + (1 - w) * cosd(currAngle);
        next_y = w * sind(target_theta) + (1 - w) * sind(currAngle);
        center_angle = wrapTo360(atan2d(next_y, next_x));
    else
        center_angle = currAngle;
    end
    newAngle = wrapTo360(center_angle + deltaTheta_total_kernel.random(1));
end

function params = estimate_BCRW_params(head_angle_deg)
theta = head_angle_deg(:);
theta = theta(~isnan(theta));
% 1) bias from absolute angle
theta_rad = deg2rad(theta);
C = mean(cos(theta_rad)); S = mean(sin(theta_rad));
mu_rad = atan2(S,C);
mu_deg = mod(rad2deg(mu_rad),360);
R_bias = sqrt(C^2 + S^2);
% 2) persistence from turning angle
deltaTheta = wrapTo180(diff(theta));
delta_rad = deg2rad(deltaTheta);
C_turn = mean(cos(delta_rad)); S_turn = mean(sin(delta_rad));
R_turn = sqrt(C_turn^2 + S_turn^2);
theta_prev = theta(1:end-1);
X = sind(mu_deg - theta_prev);
alpha = (X' * deltaTheta) / (X' * X);
if R_turn < 1e-6
    kappa_turn = 0;
elseif R_turn < 0.53
    kappa_turn = 2*R_turn + R_turn^3 + (5*R_turn^5)/6;
elseif R_turn < 0.85
    kappa_turn = -0.4 + 1.39*R_turn + 0.43/(1-R_turn);
else
    kappa_turn = 1/(R_turn^3 - 4*R_turn^2 + 3*R_turn);
end
% 3) relative weight
w = R_bias / (R_bias + R_turn);
params.mu_deg = mu_deg; params.mu_rad = mu_rad;
params.R_bias = R_bias; params.R_turn = R_turn;
params.kappa_turn = kappa_turn; params.w = w; params.alpha = alpha;
end