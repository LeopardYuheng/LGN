%% compute_global_baseline_v1_8B1.m
% Step 8_B1: Compute F_global and std_dff_m1 from all 0 uA trials,
%            restricted to the V1 region (Method 1, V1 path).
%
% V1-restricted counterpart of step 5_B1. Uses all 0 uA trials to compute
% two per-pixel maps via a single pass over every raw TIFF frame in every
% 0 uA trial window, cropped to the V1 bounding box:
%
%   F_global(x,y)   = mean raw F  across all frames of all 0 uA trials
%   std_dff_m1(x,y) = std( (F - F_global) / F_global )
%                   = std(F) / F_global
%
% Both maps are h x w (V1 bounding box + padding) with NaN outside V1_mask.
%
% F_global is used as the common normalisation denominator in step 8_B2.
% std_dff_m1 is used as the per-pixel significance threshold in step 9_B
% (V1 path).
%
% Requires:
%   - Day pointer .mat whose day_setup contains retino_align.V1_mask_stim
%     (run step 7 to relink if needed)
%
% Outputs
%   global_baseline_m1_v1.mat
%       F_global      h x w  [mean raw F, all 0 uA frames, V1 bbox]
%       std_dff_m1    h x w  [std of (F - F_global)/F_global, V1 bbox]
%       V1_mask       h x w  logical
%       final_mask    h x w  logical
%       bbox          [y0 y1 x0 x1]
%       n_frames_used scalar
%       n_trials_used scalar
%       Fs, pre_sec, post_sec
%
%   global_baseline_m1_v1_maps.png
%       Left:  F_global map (gray, V1 bbox)
%       Right: std_dff_m1 map (parula, in %, V1 bbox)

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
display_pad_px = 10;   % padding around V1 mask when cropping

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

assert(isfield(day_pointer, 'meta'),    'day_pointer.meta missing.');
assert(isfield(day_pointer, 'cfg'),     'day_pointer.cfg missing.');
assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
    'day_pointer.entries missing or empty.');

%% -------------------------
% LOAD DAY SETUP / V1 + BRAIN MASKS
% -------------------------
dataset_root = '';
if isfield(day_pointer.meta, 'dataset_root')
    dataset_root = day_pointer.meta.dataset_root;
end

day_setup_file = resolve_file_path(day_pointer.meta.day_setup_file_rel, dataset_root, 'file');
fprintf('Day setup file:\n  %s\n', day_setup_file);

D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

assert(isfield(day_setup, 'retino_align') && isfield(day_setup.retino_align, 'V1_mask_stim'), ...
    ['day_setup.retino_align.V1_mask_stim missing.\n' ...
     'Run step 6 (retino_alignment_with_brain_mask_6.m), then relink the day pointer ' ...
     'with step 7 (relink_day_pointer_to_day_setup_7.m).']);

final_mask_full = logical(day_setup.reference_mask.final_mask);
V1_mask_full    = logical(day_setup.retino_align.V1_mask_stim);
assert(any(V1_mask_full(:)), 'V1 mask is empty.');

bbox       = bbox_from_mask(V1_mask_full, display_pad_px);
V1_mask    = crop_to_bbox(V1_mask_full,    bbox);   % h x w
final_mask = crop_to_bbox(final_mask_full, bbox);   % h x w
[H, W]     = size(V1_mask);

fprintf('V1 mask: %d x %d (cropped from %d x %d)  |  %d V1 pixels\n', ...
    H, W, size(V1_mask_full,1), size(V1_mask_full,2), sum(V1_mask(:)));

%% -------------------------
% SELECT OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(fp, 'Select output folder');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% RESOLVE IMAGE DIRECTORY & SORT TIFF FILES
% -------------------------
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
full_win    = (-pre_frames : post_frames)';   % T x 1
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
% ONE-PASS ACCUMULATION — ALL FRAMES, V1 BBOX ONLY
%
%   S_F  = sum of F(x,y)    over all frames  (H x W, cropped)
%   S_F2 = sum of F(x,y)^2  over all frames  (H x W, cropped)
%   N    = total frame count
%
% Final:
%   F_global   = S_F / N
%   std_dff_m1 = sqrt(S_F2/N - F_global^2) / F_global
% -------------------------
S_F  = zeros(H, W);
S_F2 = zeros(H, W);
N    = 0;

skipped = 0;
fprintf('\nAccumulating %d trials x %d frames = %d total reads...\n', ...
    n_zero, T, n_zero * T);

for k = 1:n_zero

    f      = onsets_0(k);
    frames = f + full_win;

    if any(frames < 1) || any(frames > nFrames)
        fprintf('  Trial %d (ch%d onset=%d): window out of range — skipped.\n', ...
            k, chan_0(k), f);
        skipped = skipped + 1;
        continue;
    end

    for fi = 1:T
        frame_full = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
        frame_d    = crop_to_bbox(frame_full, bbox);   % h x w
        S_F        = S_F  + frame_d;
        S_F2       = S_F2 + frame_d .^ 2;
        N          = N + 1;
    end

    if mod(k, 20) == 1 || k == n_zero
        fprintf('  Trial %d / %d  (ch%d | onset frame %d | total frames so far: %d)\n', ...
            k, n_zero, chan_0(k), f, N);
    end
end

n_trials_used = n_zero - skipped;
n_frames_used = N;
fprintf('Done. Used %d trials (%d skipped) = %d frames total.\n', ...
    n_trials_used, skipped, n_frames_used);

%% -------------------------
% COMPUTE F_global AND std_dff_m1
% -------------------------
F_global   = S_F ./ N;
var_F      = max(S_F2 ./ N - F_global .^ 2, 0);
std_dff_m1 = sqrt(var_F) ./ F_global;

F_global(~V1_mask)   = NaN;
std_dff_m1(~V1_mask) = NaN;

fprintf('F_global   V1 range: [%.1f, %.1f]\n', ...
    min(F_global(V1_mask)), max(F_global(V1_mask)));
fprintf('std_dff_m1 V1 range: [%.4f, %.4f]  (%.2f%% – %.2f%%)\n', ...
    min(std_dff_m1(V1_mask)), max(std_dff_m1(V1_mask)), ...
    min(std_dff_m1(V1_mask))*100, max(std_dff_m1(V1_mask))*100);

%% -------------------------
% SAVE
% -------------------------
out_fname = 'global_baseline_m1_v1.mat';
save(fullfile(save_dir, out_fname), ...
    'F_global', 'std_dff_m1', 'V1_mask', 'final_mask', 'bbox', ...
    'n_frames_used', 'n_trials_used', 'Fs', 'pre_sec', 'post_sec', '-v7.3');
fprintf('Saved: %s\n', out_fname);

%% -------------------------
% FIGURE: F_global (left) + std_dff_m1 in % (right)
% -------------------------
q_F   = quantile(F_global(V1_mask),   [0.01 0.99]);
q_std = quantile(std_dff_m1(V1_mask), [0.01 0.99]);

fig = figure('Color', 'w', 'Name', 'V1 global baseline (Method 1)', ...
    'Position', [50 50 1200 520]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
imagesc(ax1, F_global, q_F);
hold(ax1, 'on');
visboundaries(ax1, V1_mask,    'Color', 'w',           'LineWidth', 1.0);
visboundaries(ax1, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);
colormap(ax1, gray(256));
cb1 = colorbar(ax1); cb1.Label.String = 'F  (counts)';
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
title(ax1, sprintf('F_{global}  (%d trials, %d frames)', n_trials_used, n_frames_used), ...
    'FontSize', 11);

ax2 = nexttile(tl);
imagesc(ax2, std_dff_m1 * 100, q_std * 100);
hold(ax2, 'on');
visboundaries(ax2, V1_mask,    'Color', 'w',           'LineWidth', 1.0);
visboundaries(ax2, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);
colormap(ax2, parula(256));
cb2 = colorbar(ax2); cb2.Label.String = 'std(dF/F)  (%)';
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
title(ax2, 'std_{dF/F}  (Method 1 V1 noise floor)', 'FontSize', 11);

title(tl, sprintf('Method 1 V1 global baseline  (0 uA, %d trials)', n_trials_used), ...
    'FontSize', 12, 'FontWeight', 'bold');

fig_fname = 'global_baseline_m1_v1_maps.png';
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

function bbox = bbox_from_mask(mask, pad)
[yy, xx] = find(mask);
assert(~isempty(yy), 'Mask is empty.');
y0 = max(1, min(yy) - pad);
y1 = min(size(mask, 1), max(yy) + pad);
x0 = max(1, min(xx) - pad);
x1 = min(size(mask, 2), max(xx) + pad);
bbox = [y0 y1 x0 x1];
end

function out = crop_to_bbox(arr, bbox)
out = arr(bbox(1):bbox(2), bbox(3):bbox(4));
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