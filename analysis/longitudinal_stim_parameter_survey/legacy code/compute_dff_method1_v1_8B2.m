%% compute_dff_method1_v1_8B2.m
% Step 8_B2: V1-restricted pixelwise dF/F(x,y,t) movies using Method 1
%            (global baseline normalisation).
%
% V1-restricted counterpart of step 5_B2. For each channel-current
% stimulation condition this script:
%   1. Crops to the V1 bounding box and computes
%      dF/F(x,y,t) = [F(x,y,t) - F_global(x,y)] / F_global(x,y)
%      for every trial, using F_global from step 8_B1.
%   2. Saves each individual trial movie as  v1_dff_m1_ch{N}_{I}uA_trial{K}.mat
%      (contains dff_movie h x w x T, t_s, V1_mask, final_mask)
%   3. Averages across trials to produce    v1_mean_dff_m1_ch{N}_{I}uA.mat
%      (same format: mean_dff_movie, t_s, V1_mask, final_mask)
%   4. Saves a frame-grid figure with V1 (white) and brain (gray) boundaries.
%
% All outputs are written into
%   save_dir/method1_v1/ch{N}_{I}uA/
%
% Requires:
%   - Day pointer .mat whose day_setup contains retino_align.V1_mask_stim
%     (run step 7 to relink if needed)
%   - global_baseline_m1_v1.mat  (from step 8_B1)

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
display_pad_px    = 10;    % padding around V1 mask when cropping
display_step_s    = 0.1;
n_prestim_display = 9;

use_auto_clim = true;
manual_clim   = [-0.02  0.02];

video_export_options = {'Per-trial dF/F videos (.mp4)', 'Trial-averaged (mean) dF/F videos (.mp4)'};
video_sel = listdlg( ...
    'Name',          'Export dF/F movies as video?', ...
    'PromptString',  'Select which V1 Method 1 dF/F movies to also export as MP4 (Cancel = none):', ...
    'ListString',    video_export_options, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [360 90], ...
    'OKString',      'Export selected', ...
    'CancelString',  'Skip videos');

make_trial_videos    = ismember(1, video_sel);
make_mean_videos     = ismember(2, video_sel);
video_frame_rate_fps = 10;
video_quality        = 95;

%% -------------------------
% SELECT OUTPUT ROOT FOLDER
% -------------------------
save_dir = uigetdir(pwd, 'Select output root folder (method1_v1/ subfolder created automatically)');
if isequal(save_dir, 0), error('No output folder selected.'); end

method1_v1_dir = fullfile(save_dir, 'method1_v1');
if ~exist(method1_v1_dir, 'dir'), mkdir(method1_v1_dir); end

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
V1_mask    = crop_to_bbox(V1_mask_full,    bbox);
final_mask = crop_to_bbox(final_mask_full, bbox);
[H, W]     = size(V1_mask);

fprintf('V1 mask: %d x %d (cropped)  |  %d V1 pixels\n', H, W, sum(V1_mask(:)));

%% -------------------------
% LOAD GLOBAL BASELINE (from step 8_B1)
% -------------------------
[gb_fn, gb_fp] = uigetfile('*.mat', 'Select global_baseline_m1_v1.mat (from step 8_B1)');
if isequal(gb_fn, 0), error('No global baseline file selected.'); end

GB = load(fullfile(gb_fp, gb_fn), 'F_global', 'std_dff_m1', 'n_frames_used', 'n_trials_used');
assert(isfield(GB, 'F_global'), ...
    'global_baseline_m1_v1.mat does not contain F_global. Did you run compute_global_baseline_v1_8B1.m?');

F_global = GB.F_global;   % h x w
assert(isequal(size(F_global), [H W]), ...
    'F_global size (%dx%d) does not match V1 bbox size (%dx%d).', ...
    size(F_global,1), size(F_global,2), H, W);

fprintf('V1 global baseline loaded: %d trials, %d frames.\n', ...
    GB.n_trials_used, GB.n_frames_used);

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
% FRAME DISPLAY SELECTION
% -------------------------
prestim_display_t  = -display_step_s * (n_prestim_display : -1 : 1);
poststim_display_t = 0 : display_step_s : post_sec;
display_t_all      = [prestim_display_t, poststim_display_t];

display_frame_idx = zeros(size(display_t_all));
for di = 1:numel(display_t_all)
    [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
end

%% -------------------------
% INTERACTIVE CONDITION SELECTION
% -------------------------
unique_pairs = unique([channels, currents], 'rows', 'stable');

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
                 'mean_dff_file', {}, 'trial_dff_files', {}, 'cond_dir', {});

%% -------------------------
% MAIN LOOP — one pass per (channel, current) condition
% -------------------------
for p = 1:size(unique_pairs, 1)

    ch  = unique_pairs(p, 1);
    cur = unique_pairs(p, 2);

    cond_dir = fullfile(method1_v1_dir, sprintf('ch%d_%guA', ch, cur));
    if ~exist(cond_dir, 'dir'), mkdir(cond_dir); end

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

        % Load and crop to V1 bounding box
        stack = zeros(H, W, T);
        for fi = 1:T
            frame_full    = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
            stack(:,:,fi) = crop_to_bbox(frame_full, bbox);
        end

        % dF/F(x,y,t) = [F(x,y,t) - F_global(x,y)] / F_global(x,y)
        % F_global is h x w; broadcasts across T automatically.
        dff_movie = (stack - F_global) ./ F_global;   % h x w x T

        % Restrict to V1
        for fi = 1:T
            frame_i = dff_movie(:,:,fi);
            frame_i(~V1_mask) = NaN;
            dff_movie(:,:,fi) = frame_i;
        end

        % Save individual trial movie
        trial_fname = sprintf('v1_dff_m1_ch%d_%guA_trial%d.mat', ch, cur, trials_cond(k));
        trial_fpath = fullfile(cond_dir, trial_fname);
        save(trial_fpath, 'dff_movie', 't_s', 'V1_mask', 'final_mask', '-v7.3');
        trial_dff_files{end+1} = trial_fpath; %#ok<AGROW>

        mean_movie = mean_movie + dff_movie;
        count      = count + 1;

    end

    if count == 0
        fprintf('  No valid trials — condition skipped.\n');
        continue;
    end

    % Trial-averaged dF/F (NaNs outside V1 propagate through the mean)
    mean_movie = mean_movie / count;

    mean_fname     = sprintf('v1_mean_dff_m1_ch%d_%guA.mat', ch, cur);
    mean_fpath     = fullfile(cond_dir, mean_fname);
    mean_dff_movie = mean_movie;
    save(mean_fpath, 'mean_dff_movie', 't_s', 'V1_mask', 'final_mask', '-v7.3');
    fprintf('  Saved mean: %s\n', mean_fname);

    results(end+1).channel        = ch;       %#ok<AGROW>
    results(end).current_uA      = cur;
    results(end).n_trials        = count;
    results(end).mean_dff_movie  = mean_movie;
    results(end).t_s             = t_s;
    results(end).mean_dff_file   = mean_fpath;
    results(end).trial_dff_files = trial_dff_files;
    results(end).cond_dir        = cond_dir;

end

%% -------------------------
% COLOR LIMITS
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
cmap = bwr_colormap();

%% -------------------------
% PER-TRIAL DF/F VIDEOS (optional)
% -------------------------
if make_trial_videos
    fprintf('\nWriting per-trial V1 Method 1 dF/F videos...\n');
    for r = 1:numel(results)
        ch  = results(r).channel;
        cur = results(r).current_uA;

        for ti = 1:numel(results(r).trial_dff_files)
            trial_fpath = results(r).trial_dff_files{ti};
            Strial = load(trial_fpath, 'dff_movie');

            [~, trial_base, ~] = fileparts(trial_fpath);
            video_fpath = fullfile(results(r).cond_dir, [trial_base '.mp4']);

            tok = regexp(trial_base, 'trial(\d+)$', 'tokens', 'once');
            trial_label = sprintf('trial %s', tok{1});

            write_v1_dff_video(video_fpath, Strial.dff_movie, t_s, V1_mask, final_mask, ...
                sprintf('Ch %d | %g uA | %s | M1', ch, cur, trial_label), ...
                clim_to_use, cmap, video_frame_rate_fps, video_quality);

            fprintf('  Saved trial video: %s.mp4\n', trial_base);
        end
    end
end

%% -------------------------
% FRAME-GRID FIGURES
% -------------------------
n_display = numel(display_frame_idx);
n_cols    = min(7, n_display);
n_rows    = ceil(n_display / n_cols);

for r = 1:numel(results)

    ch  = results(r).channel;
    cur = results(r).current_uA;
    Mv  = results(r).mean_dff_movie;

    fig = figure('Color', 'w', ...
        'Name', sprintf('Mean V1 dF/F (M1) Ch%d %guA', ch, cur), ...
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
        visboundaries(ax, V1_mask,    'Color', 'w',           'LineWidth', 1.0);
        visboundaries(ax, final_mask, 'Color', [0.4 0.4 0.4], 'LineWidth', 0.6);
        title(ax, sprintf('t = %.1f s', display_t_all(di)), 'FontSize', 8);
        last_ax = ax;
    end

    if ~isempty(last_ax)
        colorbar(last_ax);
    end

    title(tl, sprintf('Mean V1 dF/F (Method 1)  |  Ch %d  |  %g uA  |  n = %d trials', ...
        ch, cur, results(r).n_trials), 'Interpreter', 'none', 'FontSize', 11);

    fig_fname = sprintf('v1_mean_dff_m1_ch%d_%guA_frame_grid.png', ch, cur);
    exportgraphics(fig, fullfile(results(r).cond_dir, fig_fname), 'Resolution', 150);
    close(fig);
    fprintf('Saved figure: %s\n', fig_fname);

    if make_mean_videos
        mean_video_fname = sprintf('v1_mean_dff_m1_ch%d_%guA.mp4', ch, cur);
        write_v1_dff_video(fullfile(results(r).cond_dir, mean_video_fname), Mv, results(r).t_s, ...
            V1_mask, final_mask, ...
            sprintf('Ch %d | %g uA | mean (n=%d) | M1', ch, cur, results(r).n_trials), ...
            clim_to_use, cmap, video_frame_rate_fps, video_quality);
        fprintf('Saved mean video: %s\n', mean_video_fname);
    end

end

%% -------------------------
% SAVE SUMMARY
% -------------------------
summary_file = fullfile(method1_v1_dir, 'v1_dff_m1_results_summary.mat');
save(summary_file, 'results', 'V1_mask', 'final_mask', 'bbox', 't_s', ...
     'Fs', 'pre_sec', 'post_sec', 'F_global', '-v7.3');

fprintf('\nDone.\nAll outputs in:\n  %s\n', method1_v1_dir);
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

function write_v1_dff_video(video_file, movie_stack, time_axis_sec, V1_mask, final_mask, ...
    title_prefix, clim_range, cmap, frame_rate, quality)
mask_color = [0.15 0.15 0.15];

[~, ~, n_frames] = size(movie_stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax  = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);

writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate;
writer.Quality   = quality;
open(writer);

img_handle = image(ax, dff_frame_to_rgb(movie_stack(:,:,1), V1_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off');
set(ax, 'YDir', 'normal');
hold(ax, 'on');
visboundaries(ax, V1_mask,    'Color', 'w',           'LineWidth', 1.0);
visboundaries(ax, final_mask, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6);

title_handle = title(ax, '', 'Interpreter', 'none');
colormap(ax, cmap);
clim(ax, clim_range);
cb = colorbar(ax, 'eastoutside');
cb.Label.String = '\DeltaF/F';
drawnow;

target_frame_size = [];
for k = 1:n_frames
    set(img_handle, 'CData', dff_frame_to_rgb(movie_stack(:,:,k), V1_mask, clim_range, cmap, mask_color));
    set(title_handle, 'String', sprintf('%s | t = %+.2f s', title_prefix, time_axis_sec(k)));
    drawnow;
    frame_rgb = capture_consistent_frame(fig, target_frame_size);
    if isempty(target_frame_size)
        target_frame_size = size(frame_rgb(:,:,1));
    end
    writeVideo(writer, frame_rgb);
end

close(writer);
close(fig);
end

function rgb = dff_frame_to_rgb(frame, mask, clim_range, cmap, mask_color)
n      = size(cmap, 1);
scaled = (frame - clim_range(1)) / (clim_range(2) - clim_range(1));
scaled(~isfinite(scaled)) = 0;
idx    = uint8(min(max(round(scaled * (n - 1)), 0), n - 1));
rgb    = ind2rgb(idx, cmap);
for c = 1:3
    chan        = rgb(:,:,c);
    chan(~mask) = mask_color(c);
    rgb(:,:,c)  = chan;
end
end

function frame_rgb = capture_consistent_frame(fig, target_frame_size)
frame_struct = getframe(fig);
frame_rgb    = frame2im(frame_struct);
if isempty(target_frame_size), return; end
if ~isequal(size(frame_rgb,1), target_frame_size(1)) || ...
        ~isequal(size(frame_rgb,2), target_frame_size(2))
    frame_rgb = imresize(frame_rgb, target_frame_size);
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