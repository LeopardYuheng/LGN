%% compute_global_baseline_5B1.m
% Step 5_B1: Compute F_global and std_dff_m1 from all 0 uA trials (Method 1).
%
% Uses all 0 uA (no-stimulation) trials to compute two per-pixel maps via
% a single pass over every raw TIFF frame in every 0 uA trial window:
%
%   F_global(x,y)   = mean raw F  across all frames of all 0 uA trials
%   std_dff_m1(x,y) = std( (F - F_global) / F_global )
%                   = std(F) / F_global
%
% F_global is used as the common normalisation denominator in step 5_B2
% and step 8_B2.  std_dff_m1 is used as the per-pixel significance
% threshold in step 9_B, derived from ~12 000 null-condition frames per
% pixel rather than the ~10 pre-stim frames used in step 9_A.
%
% One frame at a time is held in memory during accumulation.
%
% Outputs
%   global_baseline_m1.mat
%       F_global      H x W  [mean raw F across all 0 uA frames]
%       std_dff_m1    H x W  [std of (F - F_global)/F_global]
%       n_frames_used scalar [total frames accumulated]
%       n_trials_used scalar [number of 0 uA trials used]
%       Fs, pre_sec, post_sec
%
%   global_baseline_m1_maps.png
%       Left:  F_global map (gray, in-mask only)
%       Right: std_dff_m1 map (parula, in %, in-mask only)

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

[onsets_0, sord] = sort(onsets_0);
chan_0   = chan_0(sord);
trials_0 = trials_0(sord); %#ok<NASGU>

%% -------------------------
% ONE-PASS ACCUMULATION OVER ALL FRAMES OF ALL 0 uA TRIALS
%
% For each trial, iterate over every frame in the window and accumulate:
%   S_F  = sum of F(x,y)    over all frames  (H x W)
%   S_F2 = sum of F(x,y)^2  over all frames  (H x W)
%   N    = total frame count                  (scalar)
%
% Final estimates:
%   F_global   = S_F / N
%   std_dff_m1 = sqrt(S_F2/N - F_global^2) / F_global
%              = std(F) / F_global
%              = std((F - F_global) / F_global)
% -------------------------
S_F  = zeros(H, W);
S_F2 = zeros(H, W);
N    = 0;

skipped = 0;
fprintf('\nAccumulating %d trials x %d frames = %d total reads...\n', ...
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

    for fi = 1:T
        frame_d = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
        S_F     = S_F  + frame_d;
        S_F2    = S_F2 + frame_d .^ 2;
        N       = N + 1;
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
F_global   = S_F ./ N;                                   % H x W
var_F      = max(S_F2 ./ N - F_global .^ 2, 0);         % H x W, clamp negative rounding errors
std_dff_m1 = sqrt(var_F) ./ F_global;                   % H x W

F_global(~final_mask)   = NaN;
std_dff_m1(~final_mask) = NaN;

fprintf('F_global  in-mask range: [%.1f, %.1f]\n', ...
    min(F_global(final_mask)), max(F_global(final_mask)));
fprintf('std_dff_m1 in-mask range: [%.4f, %.4f]  (%.2f%% – %.2f%%)\n', ...
    min(std_dff_m1(final_mask)), max(std_dff_m1(final_mask)), ...
    min(std_dff_m1(final_mask))*100, max(std_dff_m1(final_mask))*100);

%% -------------------------
% SAVE
% -------------------------
out_fname = 'global_baseline_m1.mat';
save(fullfile(save_dir, out_fname), ...
    'F_global', 'std_dff_m1', 'n_frames_used', 'n_trials_used', ...
    'Fs', 'pre_sec', 'post_sec', '-v7.3');
fprintf('Saved: %s\n', out_fname);

%% -------------------------
% FIGURE: F_global (left) + std_dff_m1 in % (right)
% -------------------------
fmask   = final_mask;
q_F     = quantile(F_global(fmask),   [0.01 0.99]);
q_std   = quantile(std_dff_m1(fmask), [0.01 0.99]);

fig = figure('Color', 'w', 'Name', 'Global baseline (Method 1)', ...
    'Position', [50 50 1200 520]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- F_global ---
ax1 = nexttile(tl);
imagesc(ax1, F_global, q_F);
hold(ax1, 'on');
visboundaries(ax1, fmask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
colormap(ax1, gray(256));
cb1 = colorbar(ax1); cb1.Label.String = 'F  (counts)';
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
title(ax1, sprintf('F_{global}  (%d trials, %d frames)', n_trials_used, n_frames_used), ...
    'FontSize', 11);

% --- std_dff_m1 in % ---
ax2 = nexttile(tl);
imagesc(ax2, std_dff_m1 * 100, q_std * 100);
hold(ax2, 'on');
visboundaries(ax2, fmask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
colormap(ax2, parula(256));
cb2 = colorbar(ax2); cb2.Label.String = 'std(dF/F)  (%)';
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
title(ax2, 'std_{dF/F}  (Method 1 noise floor)', 'FontSize', 11);

title(tl, sprintf('Method 1 global baseline  (0 uA, %d trials)', n_trials_used), ...
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
