%% baseline_drift_analysis_9.m
% Step 9: Pixelwise fluorescence drift analysis using 0 uA (no-stim) trials.
%
% For each 0 uA trial, computes the mean raw fluorescence over the full
% trial window and uses that as a single representative F(x,y) value for
% that trial.  Fits a linear model
%   F(x,y) = slope(x,y) * t_onset + intercept(x,y)
% per pixel across all 0 uA trials, where t_onset is the onset time of
% each trial in seconds from the start of the session (frame 1 = t = 0 s).
%
% One mean image per trial (H x W) is kept at a time — no more.
%
% Outputs
%   baseline_drift_4.mat
%       slope_map      H x W  [raw F units / second]
%       intercept_map  H x W  [raw F at t = 0 s]
%       r2_map         H x W  [R² of per-pixel linear fit]
%       n_trials_used  scalar
%       t_onset_vec    n_trials_used x 1  [trial onset times used]
%       Fs, pre_sec, post_sec
%
%   baseline_drift_slope_r2.png
%       Left:  slope map (bwr, centred at 0)
%       Right: R² map (parula, [0 1])
%
%   baseline_drift_summary_scatter.png
%       Left:  mean in-mask F per trial vs onset time + fitted line
%       Right: residuals of that mean-F fit

close all; clc; clear; fclose('all');

%% -------------------------
% LOAD DAY POINTER
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer');
if isequal(fn, 0), error('No file selected.'); end

S = load(fullfile(fp, fn));
if     isfield(S, 'day_pointer'), day_pointer = S.day_pointer;
elseif isfield(S, 'C'),           day_pointer = S.C;
else,  error('Expected "day_pointer" or legacy "C" in selected file.');
end

assert(isfield(day_pointer, 'meta')    , 'day_pointer.meta missing.');
assert(isfield(day_pointer, 'cfg')     , 'day_pointer.cfg missing.');
assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
    'day_pointer.entries missing or empty.');

%% -------------------------
% LOAD BRAIN MASK
% -------------------------
[mask_fn, mask_fp] = uigetfile('*.mat', 'Select brain_mask.mat');
if isequal(mask_fn, 0), error('No brain mask selected.'); end

M = load(fullfile(mask_fp, mask_fn));
assert(isfield(M, 'reference_mask_struct') && isfield(M.reference_mask_struct, 'final_mask'), ...
    'File does not contain reference_mask_struct.final_mask. Did you run draw_brain_mask_0.m?');

final_mask = logical(M.reference_mask_struct.final_mask);
[H, W]     = size(final_mask);
fprintf('Brain mask: %d x %d  |  %d in-mask pixels\n', H, W, sum(final_mask(:)));

%% -------------------------
% SELECT OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(fp, 'Select output folder');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% RESOLVE IMAGE DIRECTORY & SORT TIFF FILES
% -------------------------
dataset_root = '';
if isfield(day_pointer.meta, 'dataset_root')
    dataset_root = day_pointer.meta.dataset_root;
end
img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');
fprintf('Image directory:\n  %s\n', img_dir);

image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFF files found in:\n  %s', img_dir);

nums = nan(numel(image_files), 1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord]    = sort(nums);
image_files = image_files(ord);
nFrames     = numel(image_files);
fprintf('Total TIFF frames in session: %d\n', nFrames);

%% -------------------------
% TIMING
% -------------------------
Fs        = infer_camera_rate(day_pointer);
pre_sec   = double(day_pointer.cfg.pre_sec);
post_sec  = double(day_pointer.cfg.post_sec);

pre_frames  = round(pre_sec  * Fs);
post_frames = round(post_sec * Fs);
full_win    = (-pre_frames : post_frames)';   % T x 1 relative frame offsets
T           = numel(full_win);

fprintf('Camera rate: %.2f Hz  |  Trial window: -%.1fs to +%.1fs  (%d frames/trial)\n', ...
    Fs, pre_sec, post_sec, T);

%% -------------------------
% FIND ALL 0 uA TRIALS
% -------------------------
[frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);

frame_idx   = frame_idx(valid);
channels    = channels(valid);
currents    = currents(valid);
trial_index = trial_index(valid);

zero_mask = (currents == 0);
onsets_0  = frame_idx(zero_mask);
chan_0    = channels(zero_mask);
trials_0  = trial_index(zero_mask);
n_zero    = numel(onsets_0);

fprintf('Total valid trials: %d  |  0 uA trials: %d\n', sum(valid), n_zero);
if n_zero == 0
    error('No 0 uA trials found in the day pointer.');
end

% Sort chronologically
[onsets_0, sord] = sort(onsets_0);
chan_0   = chan_0(sord);
trials_0 = trials_0(sord);

%% -------------------------
% ACCUMULATE MEAN F PER TRIAL — ONE PASS, ONE TRIAL AT A TIME
%
% Each trial contributes one data point per pixel:
%   t_k = (onset_frame - 1) / Fs   (seconds from session start)
%   y_k = mean(F(x,y) over all trial frames)
%
% Sufficient statistics for linear regression across n_zero trials:
%   S_x   Σ t_k              (scalar)
%   S_xx  Σ t_k²             (scalar)
%   S_y   Σ mean_F_k(x,y)   (H x W)
%   S_xy  Σ t_k·mean_F_k    (H x W)
%   S_yy  Σ mean_F_k²       (H x W, for R²)
%   N     trial count        (scalar)
% -------------------------
S_x  = 0;
S_xx = 0;
S_y  = zeros(H, W);
S_xy = zeros(H, W);
S_yy = zeros(H, W);
N    = 0;

t_onset_vec = zeros(n_zero, 1);
mean_F_vec  = zeros(n_zero, 1);

fprintf('\nProcessing %d zero-current trials...\n', n_zero);

skipped = 0;
for k = 1:n_zero

    f      = onsets_0(k);
    frames = f + full_win;   % T x 1 absolute frame indices

    if any(frames < 1) || any(frames > nFrames)
        fprintf('  Trial %d (ch%d onset=%d): window out of range — skipped.\n', ...
            trials_0(k), chan_0(k), f);
        skipped = skipped + 1;
        continue;
    end

    % Load trial stack and compute per-pixel mean over the window
    stack = zeros(H, W, T);
    for fi = 1:T
        stack(:,:,fi) = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
    end
    F_mean_trial = mean(stack, 3);   % H x W — one value per pixel for this trial

    % Global onset time for this trial
    t_k = (f - 1) / Fs;

    % Update sufficient statistics
    S_x  = S_x  + t_k;
    S_xx = S_xx + t_k ^ 2;
    S_y  = S_y  + F_mean_trial;
    S_xy = S_xy + t_k .* F_mean_trial;
    S_yy = S_yy + F_mean_trial .^ 2;
    N    = N + 1;

    % Store for summary scatter
    idx = N;
    t_onset_vec(idx) = t_k;
    mean_F_vec(idx)  = mean(F_mean_trial(final_mask));

    if mod(k, 20) == 1 || k == n_zero
        fprintf('  Trial %d / %d  (ch%d | onset %.1f s)\n', k, n_zero, chan_0(k), t_k);
    end
end

t_onset_vec = t_onset_vec(1:N);
mean_F_vec  = mean_F_vec(1:N);
n_trials_used = N;

fprintf('Done. Used %d trials (%d skipped).\n', n_trials_used, skipped);

%% -------------------------
% PER-PIXEL LINEAR FIT
%   slope     = Sxy_c / Sxx_c
%   intercept = (S_y - slope * S_x) / N
%   R²        = (Sxy_c)² / (Sxx_c · Syy_c)
% -------------------------
Sxx_c = S_xx - S_x ^ 2  / N;
Sxy_c = S_xy - (S_x / N) .* S_y;
Syy_c = S_yy - S_y .^ 2  / N;

slope_map     = Sxy_c ./ Sxx_c;
intercept_map = (S_y - slope_map .* S_x) ./ N;
r2_map        = (Sxy_c .^ 2) ./ (Sxx_c .* Syy_c);

slope_map(~final_mask)     = NaN;
intercept_map(~final_mask) = NaN;
r2_map(~final_mask)        = NaN;

%% -------------------------
% SAVE
% -------------------------
out_fname = 'baseline_drift_4.mat';
save(fullfile(save_dir, out_fname), ...
    'slope_map', 'intercept_map', 'r2_map', ...
    'n_trials_used', 't_onset_vec', 'Fs', 'pre_sec', 'post_sec', '-v7.3');
fprintf('Saved: %s\n', out_fname);

%% -------------------------
% FIGURE 1: slope map + R² map
% -------------------------
slope_vals = slope_map(final_mask & isfinite(slope_map));
q          = quantile(slope_vals, [0.01 0.99]);
clim_slope = [-max(abs(q))  max(abs(q))];

fig1 = figure('Color', 'w', 'Name', 'Baseline drift — slope & R²', ...
    'Position', [50 50 1200 520]);
tl1 = tiledlayout(fig1, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl1);
imagesc(ax1, slope_map, clim_slope);
hold(ax1, 'on');
visboundaries(ax1, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax1, bwr_colormap());
cb1 = colorbar(ax1); cb1.Label.String = '\DeltaF / s';
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
title(ax1, sprintf('Drift slope  (\\DeltaF / s)  |  %d trials', n_trials_used), 'FontSize', 11);

ax2 = nexttile(tl1);
imagesc(ax2, r2_map, [0 1]);
hold(ax2, 'on');
visboundaries(ax2, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax2, parula(256));
cb2 = colorbar(ax2); cb2.Label.String = 'R²';
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
title(ax2, 'R² of linear fit', 'FontSize', 11);

title(tl1, sprintf('Baseline fluorescence drift  (0 uA, %d trials)', n_trials_used), ...
    'FontSize', 12, 'FontWeight', 'bold');

fig1_fname = 'baseline_drift_slope_r2.png';
exportgraphics(fig1, fullfile(save_dir, fig1_fname), 'Resolution', 150);
fprintf('Saved: %s\n', fig1_fname);

%% -------------------------
% FIGURE 2: mean in-mask F per trial vs onset time + residuals
% -------------------------
p_mean  = polyfit(t_onset_vec, mean_F_vec, 1);
t_fit   = linspace(t_onset_vec(1), t_onset_vec(end), 500);
F_fit   = polyval(p_mean, t_fit);
resid   = mean_F_vec - polyval(p_mean, t_onset_vec);

fig2 = figure('Color', 'w', 'Name', 'Baseline drift — mean F per trial', ...
    'Position', [100 100 1000 420]);
tl2 = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax3 = nexttile(tl2);
hold(ax3, 'on');
scatter(ax3, t_onset_vec, mean_F_vec, 30, [0.25 0.45 0.75], 'filled');
plot(ax3, t_fit, F_fit, '-', 'Color', [0.85 0.20 0.10], 'LineWidth', 2);
xlabel(ax3, 'Trial onset  (s  from session start)');
ylabel(ax3, 'Mean F  (in-mask)');
title(ax3, sprintf('Mean brain F per trial  (n = %d)\nslope = %.4g  F/s', ...
    n_trials_used, p_mean(1)), 'FontSize', 10);
legend(ax3, {'trial mean F', 'linear fit'}, 'Location', 'best', 'Box', 'off');
grid(ax3, 'on'); box(ax3, 'on');

ax4 = nexttile(tl2);
hold(ax4, 'on');
scatter(ax4, t_onset_vec, resid, 30, [0.55 0.55 0.55], 'filled');
yline(ax4, 0, '-k', 'LineWidth', 1);
xlabel(ax4, 'Trial onset  (s  from session start)');
ylabel(ax4, 'Residual F');
title(ax4, sprintf('Residuals  (mean F  −  linear fit)\nRMS = %.4g', rms(resid)), ...
    'FontSize', 10);
grid(ax4, 'on'); box(ax4, 'on');

title(tl2, 'Mean in-mask F per 0 uA trial', 'FontSize', 12, 'FontWeight', 'bold');

fig2_fname = 'baseline_drift_summary_scatter.png';
exportgraphics(fig2, fullfile(save_dir, fig2_fname), 'Resolution', 150);
fprintf('Saved: %s\n', fig2_fname);

fprintf('\nDone. All outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function path_out = resolve_file_path(rel_or_abs, dataset_root, kind)
if exist(rel_or_abs, kind_code(kind)) == kind_val(kind)
    path_out = rel_or_abs;
else
    path_out = fullfile(dataset_root, rel_or_abs);
end
assert(exist(path_out, kind_code(kind)) == kind_val(kind), ...
    'Path does not exist:\n  %s', path_out);
end

function c = kind_code(kind)
switch kind
    case 'file', c = 'file';
    case 'dir',  c = 'dir';
    otherwise,   error('Unknown kind: %s', kind);
end
end

function v = kind_val(kind)
switch kind
    case 'file', v = 2;
    case 'dir',  v = 7;
    otherwise,   error('Unknown kind: %s', kind);
end
end

function Fs = infer_camera_rate(day_pointer)
if isfield(day_pointer.meta, 'camera_rate_hz') && ~isempty(day_pointer.meta.camera_rate_hz)
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq') && ~isempty(day_pointer.meta.Freq)
    Fs = double(day_pointer.meta.Freq);
else
    Fs = 10;
    warning('Camera rate not found in day_pointer.meta — defaulting to 10 Hz.');
end
end

function [frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(entries)
frame_idx   = [];
channels    = [];
currents    = [];
trial_index = [];
for i = 1:numel(entries)
    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i     = numel(onset_i);
    frame_idx   = [frame_idx;   onset_i]; %#ok<AGROW>
    channels    = [channels;    repmat(double(entries(i).stim_channel), n_i, 1)]; %#ok<AGROW>
    currents    = [currents;    repmat(double(entries(i).current_uA),   n_i, 1)]; %#ok<AGROW>
    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_index = [trial_index; double(entries(i).trial_index(:))]; %#ok<AGROW>
    else
        trial_index = [trial_index; nan(n_i, 1)]; %#ok<AGROW>
    end
end
end

function cmap = bwr_colormap(n)
if nargin < 1, n = 256; end
half = floor(n / 2);
rest = n - half;
r    = [linspace(0, 1, half)';  ones(rest, 1)         ];
g    = [linspace(0, 1, half)';  linspace(1, 0, rest)' ];
b    = [ones(half, 1);          linspace(1, 0, rest)'  ];
cmap = [r, g, b];
end