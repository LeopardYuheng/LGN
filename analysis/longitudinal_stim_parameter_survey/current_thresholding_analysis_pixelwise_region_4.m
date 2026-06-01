%% current_thresholding_analysis_pixelwise_region_4.m
% Step 4: Pixelwise dF/F(x,y,t) movie computation.
%
% For each channel-current stimulation condition this script:
%   1. Computes dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)
%      for every trial, where F_baseline = mean(F, pre-stim frames of that trial).
%   2. Saves each individual trial movie as  dff_ch{N}_{I}uA_trial{K}.mat
%      (contains dff_movie H x W x T  and  t_s; use t_s < 0 for pre-stim frames)
%   3. Averages across trials to produce    mean_dff_ch{N}_{I}uA.mat
%      (same format: mean_dff_movie, t_s, final_mask)
%   4. Saves a frame-grid figure of the mean dF/F at selected post-stim timepoints.
%      (pre-stim dF/F is saved but not shown in the figure)
%
% Requires:
%   - Day pointer .mat  (from make_container_ripple_3.m)
%   - brain_mask.mat    (from draw_brain_mask_0.m)
%
% display_step_s controls the figure grid spacing only; all frames are always
% saved in the .mat files. At 10 Hz with display_step_s = 0.3, the figure
% shows frames at t = 0, 0.3, 0.6, ... s post-stim.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------

% Output folder for all saved .mat files and figures
save_dir = 'C:\Projects\LGN_project\wide field analysis result\LGN11_20260326_experiment\analysis\dff_movies';

% Spacing between displayed frames in the frame-grid figure (seconds).
% Does NOT affect what is saved — all frames are always saved.
display_step_s = 0.3;

% Color limits for the dF/F figures.
% use_auto_clim = true  : symmetric scale set from the 1st/99th percentile
%                          of the data, so it always matches the signal range.
% use_auto_clim = false : use the fixed range in manual_clim below.
use_auto_clim = true;
manual_clim   = [-0.02  0.02];

%% -------------------------
% LOAD DAY POINTER
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer');
if isequal(fn, 0), error('No file selected.'); end

S = load(fullfile(fp, fn));
if isfield(S, 'day_pointer')
    day_pointer = S.day_pointer;
elseif isfield(S, 'C')
    day_pointer = S.C;
else
    error('Selected file must contain "day_pointer" or legacy variable "C".');
end

assert(isfield(day_pointer, 'meta'),    'day_pointer.meta missing.');
assert(isfield(day_pointer, 'cfg'),     'day_pointer.cfg missing.');
assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
    'day_pointer.entries missing or empty.');

%% -------------------------
% LOAD BRAIN MASK
% -------------------------
[mask_fn, mask_fp] = uigetfile('*.mat', 'Select brain_mask.mat');
if isequal(mask_fn, 0), error('No brain mask selected.'); end

M = load(fullfile(mask_fp, mask_fn));
assert(isfield(M, 'reference_mask_struct') && isfield(M.reference_mask_struct, 'final_mask'), ...
    'Selected file does not contain reference_mask_struct.final_mask. Did you run draw_brain_mask_0.m?');

final_mask = logical(M.reference_mask_struct.final_mask);
[H, W]     = size(final_mask);
fprintf('Brain mask loaded: %d x %d  |  %d brain pixels\n', H, W, sum(final_mask(:)));

%% -------------------------
% RESOLVE IMAGE DIRECTORY
% img_dir_rel stores the absolute path when data and analysis are on
% separate drives; resolve_file_path uses it directly in that case.
% -------------------------
dataset_root = '';
if isfield(day_pointer.meta, 'dataset_root')
    dataset_root = day_pointer.meta.dataset_root;
end
img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');
fprintf('Image directory:\n  %s\n', img_dir);

%% -------------------------
% LOAD AND SORT TIFF FILES
% -------------------------
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
fprintf('Total TIFF frames: %d\n', nFrames);

%% -------------------------
% TIMING
% -------------------------
Fs       = infer_camera_rate(day_pointer);
pre_sec  = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames  = round(pre_sec  * Fs);
post_frames = round(post_sec * Fs);
full_win    = -pre_frames : post_frames;
t_s         = full_win / Fs;
T           = numel(full_win);

baseline_idx = t_s < 0;  % logical index into t_s for pre-stim frames

fprintf('Camera rate: %.2f Hz  |  Pre: %.1f s  |  Post: %.1f s  |  %d frames/trial\n', ...
    Fs, pre_sec, post_sec, T);

%% -------------------------
% UNPACK TRIAL INFORMATION
% -------------------------
[frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);

frame_idx   = frame_idx(valid);
channels    = channels(valid);
currents    = currents(valid);
trial_index = trial_index(valid);

fprintf('Valid trials: %d\n', sum(valid));

%% -------------------------
% CREATE OUTPUT DIRECTORY
% -------------------------
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
fprintf('Output directory:\n  %s\n', save_dir);

%% -------------------------
% FRAME DISPLAY SELECTION
% Frames shown in the figure at t = 0, display_step_s, 2*display_step_s, ...
% -------------------------
display_t_post    = 0 : display_step_s : post_sec;
display_frame_idx = zeros(size(display_t_post));
for di = 1:numel(display_t_post)
    [~, display_frame_idx(di)] = min(abs(t_s - display_t_post(di)));
end

%% -------------------------
% MAIN LOOP — one pass per (channel, current) condition
% -------------------------
unique_pairs = unique([channels, currents], 'rows', 'stable');

%% -------------------------
% INTERACTIVE CONDITION SELECTION
% -------------------------
condition_strs = arrayfun( ...
    @(r) sprintf('Ch %d  |  %g uA', unique_pairs(r,1), unique_pairs(r,2)), ...
    (1:size(unique_pairs,1))', 'UniformOutput', false);

[sel_idx, ok] = listdlg( ...
    'Name',          'Select conditions to analyze', ...
    'PromptString',  'Available channel-current conditions (Ctrl+click for multiple):', ...
    'ListString',    condition_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [320 220], ...
    'OKString',      'Analyze selected', ...
    'CancelString',  'Cancel');

if ~ok || isempty(sel_idx)
    error('No conditions selected. Analysis cancelled.');
end

unique_pairs = unique_pairs(sel_idx, :);
fprintf('Selected %d condition(s):\n', size(unique_pairs,1));
for r = 1:size(unique_pairs,1)
    fprintf('  Ch %d  |  %g uA\n', unique_pairs(r,1), unique_pairs(r,2));
end

results = struct('channel', {}, 'current_uA', {}, 'n_trials', {}, ...
                 'mean_dff_movie', {}, 't_s', {}, ...
                 'mean_dff_file', {}, 'trial_dff_files', {});

for p = 1:size(unique_pairs, 1)

    ch  = unique_pairs(p, 1);
    cur = unique_pairs(p, 2);

    idx_cond    = (channels == ch) & (currents == cur);
    onsets_cond = frame_idx(idx_cond);
    trials_cond = trial_index(idx_cond);
    n_cond      = numel(onsets_cond);

    fprintf('\nChannel %d | %g uA | %d trials\n', ch, cur, n_cond);

    mean_movie      = zeros(H, W, T);
    count           = 0;
    trial_dff_files = {};

    for k = 1:n_cond

        f      = onsets_cond(k);
        frames = f + full_win;

        if any(frames < 1) || any(frames > nFrames)
            fprintf('  Trial %d: frame window out of bounds — skipped.\n', trials_cond(k));
            continue;
        end

        % Load frame stack for this trial
        stack = zeros(H, W, T);
        for fi = 1:T
            stack(:,:,fi) = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
        end

        % dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)
        F_baseline  = mean(stack(:,:,baseline_idx), 3);    % H x W
        dff_movie   = (stack - F_baseline) ./ F_baseline;  % H x W x T

        % Save individual trial movie (t_s < 0 are pre-stim frames)
        trial_fname = sprintf('dff_ch%d_%guA_trial%d.mat', ch, cur, trials_cond(k));
        trial_fpath = fullfile(save_dir, trial_fname);
        save(trial_fpath, 'dff_movie', 't_s', '-v7.3');
        trial_dff_files{end+1} = trial_fpath; %#ok<AGROW>

        % Accumulate for trial-average
        mean_movie = mean_movie + dff_movie;
        count        = count + 1;

    end

    if count == 0
        fprintf('  No valid trials — condition skipped.\n');
        continue;
    end

    % Trial-averaged dF/F; set outside-brain pixels to NaN
    mean_movie = mean_movie / count;
    for fi = 1:T
        frame_i = mean_movie(:,:,fi);
        frame_i(~final_mask) = NaN;
        mean_movie(:,:,fi) = frame_i;
    end

    % Save mean movie (t_s < 0 are pre-stim frames)
    mean_fname     = sprintf('mean_dff_ch%d_%guA.mat', ch, cur);
    mean_fpath     = fullfile(save_dir, mean_fname);
    mean_dff_movie = mean_movie;
    save(mean_fpath, 'mean_dff_movie', 't_s', 'final_mask', '-v7.3');
    fprintf('  Saved mean: %s\n', mean_fname);

    results(end+1).channel        = ch;        %#ok<AGROW>
    results(end).current_uA      = cur;
    results(end).n_trials        = count;
    results(end).mean_dff_movie  = mean_movie;
    results(end).t_s             = t_s;
    results(end).mean_dff_file   = mean_fpath;
    results(end).trial_dff_files = trial_dff_files;

end

%% -------------------------
% COLOR LIMITS
% Auto: symmetric around 0, scaled to 1st/99th percentile across all conditions.
% -------------------------
if use_auto_clim
    all_vals = [];
    for r = 1:numel(results)
        m = results(r).mean_dff_movie;
        all_vals = [all_vals; m(isfinite(m))]; %#ok<AGROW>
    end
    if ~isempty(all_vals)
        q           = quantile(all_vals, [0.01 0.99]);
        clim_to_use = [-max(abs(q))  max(abs(q))];
    else
        clim_to_use = manual_clim;
    end
else
    clim_to_use = manual_clim;
end

fprintf('\nColor limits: [%.4f  %.4f]\n', clim_to_use(1), clim_to_use(2));

%% -------------------------
% FRAME-GRID FIGURES — one figure per (channel, current) condition
% Shows post-stim frames only; pre-stim dF/F is saved in .mat but not plotted.
% -------------------------
n_display = numel(display_frame_idx);
n_cols    = min(7, n_display);
n_rows    = ceil(n_display / n_cols);
cmap      = bwr_colormap();

for r = 1:numel(results)

    ch  = results(r).channel;
    cur = results(r).current_uA;
    Mv  = results(r).mean_dff_movie;

    fig = figure('Color', 'w', ...
        'Name', sprintf('Mean dF/F Ch%d %guA', ch, cur), ...
        'Position', [50 50  min(1800, 240*n_cols)  240*n_rows + 70]);
    tl = tiledlayout(n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');

    last_ax = [];
    for di = 1:n_display
        fi = display_frame_idx(di);
        if fi < 1 || fi > T, continue; end

        ax = nexttile(tl);
        imagesc(ax, Mv(:,:,fi));
        axis(ax, 'image'); axis(ax, 'off');
        set(ax, 'YDir', 'normal');
        colormap(ax, cmap);
        clim(ax, clim_to_use);
        hold(ax, 'on');
        visboundaries(ax, final_mask, 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8);
        title(ax, sprintf('t = %.1f s', display_t_post(di)), 'FontSize', 8);
        last_ax = ax;
    end

    if ~isempty(last_ax)
        colorbar(last_ax);
    end

    title(tl, sprintf('Mean dF/F  |  Ch %d  |  %g uA  |  n = %d trials', ...
        ch, cur, results(r).n_trials), 'Interpreter', 'none', 'FontSize', 11);

    fig_fname = sprintf('mean_dff_ch%d_%guA_frame_grid.png', ch, cur);
    exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
    close(fig);
    fprintf('Saved figure: %s\n', fig_fname);

end

%% -------------------------
% SAVE SUMMARY
% -------------------------
summary_file = fullfile(save_dir, 'dff_results_summary.mat');
save(summary_file, 'results', 'final_mask', 't_s', 'baseline_idx', ...
     'Fs', 'pre_sec', 'post_sec', '-v7.3');

fprintf('\nDone.\nAll outputs in:\n  %s\n', save_dir);
fprintf('Conditions processed: %d\n', numel(results));

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
% Blue-white-red diverging colormap, symmetric around zero.
if nargin < 1, n = 256; end
half = floor(n / 2);
rest = n - half;
r    = [linspace(0, 1, half)';  ones(rest, 1)         ];
g    = [linspace(0, 1, half)';  linspace(1, 0, rest)' ];
b    = [ones(half, 1);          linspace(1, 0, rest)'  ];
cmap = [r, g, b];
end
