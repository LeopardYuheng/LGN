%% baseline_drift_analysis_9.m
% Step 9: Pixelwise fluorescence drift analysis using 0 uA (no-stim) trials.
%
% Collects every 0 uA trial from the day pointer and fits a linear model
%   F(x,y,t) = slope(x,y) * t_global + intercept(x,y)
% for every in-mask pixel, where t_global is seconds from the very first
% TIFF frame of the session (frame 1 = t = 0 s).
%
% All frames in the trial window (-pre_sec to +post_sec) are used as
% individual data points — raw fluorescence F, not dF/F.  The whole
% frame set is never held in memory at once: sufficient statistics
% (ΣF, Σt·F, Σt, Σt², ΣF², N) are accumulated one trial at a time.
%
% Outputs
%   baseline_drift_9.mat
%       slope_map      H x W  [raw F units / second]
%       intercept_map  H x W  [raw F at t = 0 s]
%       r2_map         H x W  [R² of per-pixel linear fit]
%       n_trials_used  scalar
%       N_frames       scalar (total frames accumulated)
%       Fs, pre_sec, post_sec
%
%   baseline_drift_slope_r2.png
%       Left:  slope map (bwr, centred at 0)
%       Right: R² map (parula, [0 1])
%
%   baseline_drift_summary_scatter.png
%       Left:  mean in-mask F vs global time + fitted line
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
full_win    = (-pre_frames : post_frames)';  % T x 1 relative frame offsets
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

% Sort chronologically so the summary scatter reads left-to-right
[onsets_0, sord] = sort(onsets_0);
chan_0   = chan_0(sord);
trials_0 = trials_0(sord);

%% -------------------------
% ONE-PASS SUFFICIENT STATISTICS ACCUMULATION
%
% Sufficient statistics for linear regression y = a*t + b:
%   S_x   Σ t_global          (scalar — identical for all pixels)
%   S_xx  Σ t_global²         (scalar)
%   S_y   Σ F(x,y)            (H x W)
%   S_xy  Σ t_global·F(x,y)   (H x W)
%   S_yy  Σ F(x,y)²           (H x W, used for R²)
%   N     total frame count    (scalar)
%
% Loading one full trial stack (H x W x T) at a time; no more than that
% is kept in memory simultaneously.
% -------------------------
S_x  = 0;
S_xx = 0;
S_y  = zeros(H, W);
S_xy = zeros(H, W);
S_yy = zeros(H, W);
N    = 0;

max_frames      = n_zero * T;
t_global_all    = zeros(1, max_frames);
mean_F_all      = zeros(1, max_frames);
frame_count     = 0;

fprintf('\nLoading 0 uA trials (%d trials x %d frames = up to %d frames)...\n', ...
    n_zero, T, max_frames);

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

    if mod(k, 20) == 1
        fprintf('  Trial %d / %d  (ch%d | onset frame %d)\n', ...
            k, n_zero, chan_0(k), f);
    end

    % --- Load full trial stack (H x W x T) ---
    stack = zeros(H, W, T);
    for fi = 1:T
        stack(:,:,fi) = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
    end

    % --- Global time for each frame in this trial (t=0 at session start) ---
    t_global_trial = (frames - 1) ./ Fs;   % T x 1, seconds

    % --- Vectorised sufficient statistics update ---
    % Reshape t into 1 x 1 x T for broadcasting against H x W x T stack
    t_3d = reshape(t_global_trial, 1, 1, T);

    S_x  = S_x  + sum(t_global_trial);         % scalar + scalar
    S_xx = S_xx + sum(t_global_trial .^ 2);
    S_y  = S_y  + sum(stack, 3);               % H x W
    S_xy = S_xy + sum(stack .* t_3d, 3);       % H x W
    S_yy = S_yy + sum(stack .^ 2, 3);          % H x W
    N    = N    + T;

    % --- Mean in-mask F per frame for the summary scatter ---
    for fi = 1:T
        frame_count = frame_count + 1;
        t_global_all(frame_count) = t_global_trial(fi);
        fr = stack(:,:,fi);
        mean_F_all(frame_count)   = mean(fr(final_mask));
    end
end

n_trials_used = n_zero - skipped;
t_global_all  = t_global_all(1:frame_count);
mean_F_all    = mean_F_all(1:frame_count);
fprintf('Done. Accumulated %d frames from %d trials (%d skipped).\n', ...
    N, n_trials_used, skipped);

%% -------------------------
% PER-PIXEL LINEAR FIT FROM SUFFICIENT STATISTICS
%
%   slope     = Sxy_c / Sxx_c
%   intercept = (S_y - slope * S_x) / N
%   R²        = 1 - SS_res / SS_tot
%              = (Sxy_c)² / (Sxx_c · Syy_c)   [equivalent form]
%
% where:
%   Sxx_c = S_xx - S_x²/N       (scalar)
%   Sxy_c = S_xy - S_x·S_y/N    (H x W)
%   Syy_c = S_yy - S_y²/N       (H x W) = SS_tot per pixel
% -------------------------
Sxx_c = S_xx  - S_x ^ 2  / N;            % scalar
Sxy_c = S_xy  - (S_x / N) .* S_y;        % H x W
Syy_c = S_yy  - S_y .^ 2  / N;           % H x W

slope_map     = Sxy_c ./ Sxx_c;                      % H x W, raw-F units / s
intercept_map = (S_y - slope_map .* S_x) ./ N;       % H x W
r2_map        = (Sxy_c .^ 2) ./ (Sxx_c .* Syy_c);   % H x W, [0,1]

% Zero out non-brain pixels
slope_map(~final_mask)     = NaN;
intercept_map(~final_mask) = NaN;
r2_map(~final_mask)        = NaN;

%% -------------------------
% SAVE
% -------------------------
out_fname = 'baseline_drift_9.mat';
save(fullfile(save_dir, out_fname), ...
    'slope_map', 'intercept_map', 'r2_map', ...
    'n_trials_used', 'N', 'Fs', 'pre_sec', 'post_sec', '-v7.3');
fprintf('Saved: %s\n', out_fname);

%% -------------------------
% FIGURE 1: slope map (left) + R² map (right)
% -------------------------
slope_vals = slope_map(final_mask & isfinite(slope_map));
q          = quantile(slope_vals, [0.01 0.99]);
clim_slope = [-max(abs(q)) max(abs(q))];

fig1 = figure('Color', 'w', 'Name', 'Baseline drift — slope & R²', ...
    'Position', [50 50 1200 520]);
tl1 = tiledlayout(fig1, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl1);
imagesc(ax1, slope_map, clim_slope);
hold(ax1, 'on');
visboundaries(ax1, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax1, bwr_colormap());
cb1 = colorbar(ax1, 'eastoutside');
cb1.Label.String = '\DeltaF / s';
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
title(ax1, sprintf('Drift slope  (\\DeltaF / s)  |  %d trials, %d frames', ...
    n_trials_used, N), 'FontSize', 11);

ax2 = nexttile(tl1);
imagesc(ax2, r2_map, [0 1]);
hold(ax2, 'on');
visboundaries(ax2, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax2, parula(256));
cb2 = colorbar(ax2, 'eastoutside');
cb2.Label.String = 'R²';
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
title(ax2, 'R² of linear fit  (residual diagnostic)', 'FontSize', 11);

title(tl1, 'Baseline fluorescence drift  (0 uA trials)', ...
    'FontSize', 12, 'FontWeight', 'bold');

fig1_fname = 'baseline_drift_slope_r2.png';
exportgraphics(fig1, fullfile(save_dir, fig1_fname), 'Resolution', 150);
fprintf('Saved: %s\n', fig1_fname);

%% -------------------------
% FIGURE 2: mean in-mask F vs global time, with fit + residuals
% -------------------------
[t_sort, sorder] = sort(t_global_all);
F_sort           = mean_F_all(sorder);

p_mean   = polyfit(t_sort, F_sort, 1);
t_fit    = linspace(t_sort(1), t_sort(end), 1000);
F_fit    = polyval(p_mean, t_fit);
resid    = F_sort - polyval(p_mean, t_sort);

fig2 = figure('Color', 'w', 'Name', 'Baseline drift — mean F summary', ...
    'Position', [100 100 1000 420]);
tl2 = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax3 = nexttile(tl2);
hold(ax3, 'on');
scatter(ax3, t_sort, F_sort, 3, [0.65 0.65 0.85], 'filled', 'MarkerFaceAlpha', 0.25);
plot(ax3, t_fit, F_fit, '-', 'Color', [0.85 0.20 0.10], 'LineWidth', 2);
xlabel(ax3, 'Global time  (s  from session start)');
ylabel(ax3, 'Mean F  (in-mask pixels)');
title(ax3, sprintf('Mean brain F vs global time\nslope = %.4g  F/s', p_mean(1)), ...
    'FontSize', 10);
legend(ax3, {'F(t)  each frame', 'linear fit'}, 'Location', 'best', 'Box', 'off');
grid(ax3, 'on'); box(ax3, 'on');

ax4 = nexttile(tl2);
hold(ax4, 'on');
scatter(ax4, t_sort, resid, 3, [0.55 0.55 0.55], 'filled', 'MarkerFaceAlpha', 0.25);
yline(ax4, 0, '-k', 'LineWidth', 1);
xlabel(ax4, 'Global time  (s  from session start)');
ylabel(ax4, 'Residual F');
title(ax4, sprintf('Residuals  (mean F  −  linear fit)\nRMS = %.4g', rms(resid)), ...
    'FontSize', 10);
grid(ax4, 'on'); box(ax4, 'on');

title(tl2, 'Mean in-mask fluorescence  (0 uA trials)', ...
    'FontSize', 12, 'FontWeight', 'bold');

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
