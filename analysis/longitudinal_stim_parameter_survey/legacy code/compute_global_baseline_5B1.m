%% compute_global_baseline_5B1.m
% Step 5_B1: Compute drift-corrected noise floor (std_dff_m1) for Method 1.
%
% When step 4 reveals an obvious linear drift in raw fluorescence, a single
% constant F_global is a poor baseline: it over-subtracts early trials and
% under-subtracts late ones.  This script replaces the constant baseline with
% a per-pixel time-varying expected value derived from the step-4 linear model:
%
%   F_expected(x,y, trial_k) = intercept_map(x,y) + slope_map(x,y) * t_k
%
% where t_k = (onset_frame_k - 1) / Fs  (seconds from session start).
%
% For every frame of every 0 uA trial the drift-corrected dF/F residual is:
%   dff_res(x,y) = [ F(x,y) - F_expected(x,y) ] / F_expected(x,y)
%
% std_dff_m1(x,y) = std(dff_res) across all ~12 000 null frames per pixel.
%
% slope_map and intercept_map are stored in the output so that step 5_B2
% can load this single file and compute per-trial baselines.
%
% Requires
%   - Day pointer .mat        (from step 3)
%   - brain_mask.mat          (from pre-step B)
%   - baseline_drift_4.mat    (from step 4)
%
% Outputs
%   global_baseline_m1.mat
%       slope_map      H x W  [F units / second — copied from step 4]
%       intercept_map  H x W  [F at t = 0 — copied from step 4]
%       std_dff_m1     H x W  [std of drift-corrected dF/F, null trials]
%       n_frames_used  scalar
%       n_trials_used  scalar
%       Fs, pre_sec, post_sec
%
%   global_baseline_m1_maps.png
%       Left:  intercept_map (gray) — estimated F at session start
%       Right: std_dff_m1 map (parula, in %) — drift-corrected noise floor

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
% LOAD DRIFT MODEL (from step 4)
% -------------------------
[drift_fn, drift_fp] = uigetfile('*.mat', 'Select baseline_drift_4.mat (from step 4)');
if isequal(drift_fn, 0), error('No drift file selected.'); end

D = load(fullfile(drift_fp, drift_fn), 'slope_map', 'intercept_map');
assert(isfield(D, 'slope_map') && isfield(D, 'intercept_map'), ...
    'baseline_drift_4.mat must contain slope_map and intercept_map. Did you run baseline_drift_analysis_4.m?');

slope_map     = D.slope_map;      % H x W  (F units / second)
intercept_map = D.intercept_map;  % H x W  (F at session t = 0)

assert(isequal(size(slope_map), [H W]), ...
    'slope_map size (%dx%d) does not match brain mask (%dx%d).', ...
    size(slope_map,1), size(slope_map,2), H, W);

fprintf('Drift model loaded: slope_map and intercept_map (%d x %d).\n', H, W);

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
trial_index = trial_index(valid); %#ok<NASGU>

zero_mask = (currents == 0);
onsets_0  = frame_idx(zero_mask);
chan_0    = channels(zero_mask);
n_zero    = numel(onsets_0);

fprintf('Total valid trials: %d  |  0 uA trials: %d\n', sum(valid), n_zero);
if n_zero == 0
    error('No 0 uA trials found in the day pointer.');
end

[onsets_0, sord] = sort(onsets_0);
chan_0 = chan_0(sord);

%% -------------------------
% ONE-PASS ACCUMULATION — drift-corrected dF/F residuals
%
% For each 0 uA trial with onset at session time t_k:
%   F_expected(x,y) = intercept_map(x,y) + slope_map(x,y) * t_k
%
% For each frame in the trial window, accumulate:
%   S_dff  = sum of  [F - F_expected] / F_expected   (H x W)
%   S_dff2 = sum of ([F - F_expected] / F_expected)^2 (H x W)
%   N      = total frame count                        (scalar)
%
% Final:
%   std_dff_m1 = sqrt( S_dff2/N - (S_dff/N)^2 )
% -------------------------
S_dff  = zeros(H, W);
S_dff2 = zeros(H, W);
N      = 0;

skipped = 0;
fprintf('\nAccumulating drift-corrected residuals: %d trials x %d frames = %d reads...\n', ...
    n_zero, T, n_zero * T);

for k = 1:n_zero

    f      = onsets_0(k);
    frames = f + full_win;   % T x 1 absolute frame indices

    if any(frames < 1) || any(frames > nFrames)
        fprintf('  Trial %d (ch%d onset=%d): window out of range — skipped.\n', ...
            k, chan_0(k), f);
        skipped = skipped + 1;
        continue;
    end

    % Session-clock time of this trial's onset (matches step 4 convention)
    t_k = (f - 1) / Fs;

    % Drift-predicted baseline for this trial
    F_expected = intercept_map + slope_map * t_k;   % H x W

    for fi = 1:T
        frame_d  = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
        dff_res  = (frame_d - F_expected) ./ F_expected;
        S_dff    = S_dff  + dff_res;
        S_dff2   = S_dff2 + dff_res .^ 2;
        N        = N + 1;
    end

    if mod(k, 20) == 1 || k == n_zero
        fprintf('  Trial %d / %d  (ch%d | t = %.1f s | total frames so far: %d)\n', ...
            k, n_zero, chan_0(k), t_k, N);
    end
end

n_trials_used = n_zero - skipped;
n_frames_used = N;
fprintf('Done. Used %d trials (%d skipped) = %d frames total.\n', ...
    n_trials_used, skipped, n_frames_used);

%% -------------------------
% COMPUTE std_dff_m1
% -------------------------
mean_dff_m1 = S_dff  ./ N;
var_dff_m1  = max(S_dff2 ./ N - mean_dff_m1 .^ 2, 0);
std_dff_m1  = sqrt(var_dff_m1);

std_dff_m1(~final_mask) = NaN;

fprintf('std_dff_m1 in-mask range: [%.4f, %.4f]  (%.2f%% – %.2f%%)\n', ...
    min(std_dff_m1(final_mask)), max(std_dff_m1(final_mask)), ...
    min(std_dff_m1(final_mask))*100, max(std_dff_m1(final_mask))*100);

%% -------------------------
% SAVE
% -------------------------
out_fname = 'global_baseline_m1.mat';
save(fullfile(save_dir, out_fname), ...
    'slope_map', 'intercept_map', 'std_dff_m1', ...
    'n_frames_used', 'n_trials_used', ...
    'Fs', 'pre_sec', 'post_sec', '-v7.3');
fprintf('Saved: %s\n', out_fname);

%% -------------------------
% FIGURE: intercept_map (left) + std_dff_m1 in % (right)
% -------------------------
fmask   = final_mask;
q_int   = quantile(intercept_map(fmask & isfinite(intercept_map)), [0.01 0.99]);
q_std   = quantile(std_dff_m1(fmask),                              [0.01 0.99]);

fig = figure('Color', 'w', 'Name', 'Global baseline (Method 1 — drift-corrected)', ...
    'Position', [50 50 1200 520]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- intercept_map (estimated F at session start) ---
ax1 = nexttile(tl);
imagesc(ax1, intercept_map, q_int);
hold(ax1, 'on');
visboundaries(ax1, fmask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
colormap(ax1, gray(256));
cb1 = colorbar(ax1); cb1.Label.String = 'F at t=0  (counts)';
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
title(ax1, sprintf('intercept\\_map  (%d trials, drift-corrected)', n_trials_used), ...
    'FontSize', 11);

% --- std_dff_m1 in % ---
ax2 = nexttile(tl);
imagesc(ax2, std_dff_m1 * 100, q_std * 100);
hold(ax2, 'on');
visboundaries(ax2, fmask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax2, parula(256));
cb2 = colorbar(ax2); cb2.Label.String = 'std(dF/F)  (%)';
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
title(ax2, 'std_{dF/F}  (drift-corrected noise floor)', 'FontSize', 11);

title(tl, sprintf('Method 1 drift-corrected baseline  (0 uA, %d trials)', n_trials_used), ...
    'FontSize', 12, 'FontWeight', 'bold');

fig_fname = 'global_baseline_m1_maps.png';
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
fprintf('Saved: %s\n', fig_fname);

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
