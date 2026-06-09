%% dff_pixelwise_significance_threshold_8.m
% Step 8: Per-pixel significance thresholding of a single dF/F movie.
%
% Generic post-processing utility — works on ANY single dF/F movie .mat
% produced by step 4 or step 7 (whole-brain or V1, single-trial or
% trial-averaged): dff_ch*_trial*.mat, mean_dff_ch*.mat,
% v1_dff_ch*_trial*.mat, v1_mean_dff_ch*.mat. It only needs the movie
% array (dff_movie / mean_dff_movie) and its time axis t_s.
%
% For every pixel (x,y):
%   1. Computes std(x,y) of its dF/F trace over the pre-stim baseline
%      (t_s < 0), ignoring NaNs. The baseline mean of dF/F is ~0, so
%      +/- std(x,y) defines a per-pixel "noise band" significance threshold.
%   2. Builds a thresholded movie that, at each t, shows a pixel's true
%      dF/F value only when |dF/F(x,y,t)| > std(x,y). All other pixels at
%      that frame are rendered with one of two solid colors:
%         - always-NaN pixels (outside the brain/V1 mask for the whole movie)
%         - in-mask pixels that are simply within the +/- std band right now
%      so the region outline stays visible even when nothing is active.
%   3. Saves the thresholded movie + per-pixel std map as .mat, optionally
%      also as an .mp4 video.
%   4. Opens an interactive viewer (time-slider over the thresholded movie,
%      plus a static "peak response" map at the post-stim timepoint with
%      the most suprathreshold pixels) and lets you click pixels to pick
%      them; for each picked pixel it plots dF/F(t) with its +/- std band.
%
% Requires: a dF/F movie .mat from step 4 or step 7 (contains the movie
% array and t_s).

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside  = [0.15 0.15 0.15];  % always-NaN (out-of-brain/V1) pixels
mask_color_inactive = [0.55 0.55 0.55];  % in-mask pixels currently within +/- std band

video_frame_rate_fps = 10;
video_quality        = 95;

% Frame-grid figure spacing (seconds) — same convention as steps 4/7.
display_step_s    = 0.1;
n_prestim_display = 9;

%% -------------------------
% SELECT INPUT MOVIE
% -------------------------
[mv_fn, mv_fp] = uigetfile('*.mat', ...
    'Select a dF/F movie (dff_ch*_trial*.mat, mean_dff_ch*.mat, v1_dff_ch*_trial*.mat, v1_mean_dff_ch*.mat)');
if isequal(mv_fn, 0), error('No file selected.'); end

S = load(fullfile(mv_fp, mv_fn));
if isfield(S, 'dff_movie')
    movie = S.dff_movie;
elseif isfield(S, 'mean_dff_movie')
    movie = S.mean_dff_movie;
else
    error('Selected file must contain "dff_movie" or "mean_dff_movie".');
end
assert(isfield(S, 't_s'), 'Selected file is missing "t_s" (time axis).');

t_s = double(S.t_s(:)');
[H, W, T] = size(movie);
assert(numel(t_s) == T, 't_s length (%d) does not match movie frame count (%d).', numel(t_s), T);

% Pull a clean condition label such as "ch86_7uA_trial618" or "ch86_7uA"
% out of the filename, regardless of its dff_/mean_dff_/v1_ prefix.
[~, base_name, ~] = fileparts(mv_fn);
tok = regexp(base_name, '(ch\d+_[\d.]+uA(?:_trial\d+)?)', 'tokens', 'once');
if isempty(tok)
    cond_label = base_name;
else
    cond_label = tok{1};
end

fprintf('Loaded movie: %s   (%d x %d x %d frames)\n', mv_fn, H, W, T);
fprintf('Condition label: %s\n', cond_label);

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(mv_fp, 'Select output folder for thresholded movie / figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% CHOOSE SIGNIFICANCE THRESHOLD MULTIPLIER (n_std)
% -------------------------
% Pixels are flagged where |dF/F(x,y,t)| > n_std * std(x,y). For ~Gaussian
% baseline noise, ~32% of samples cross +/-1*std; ~5% cross
% +/-2*std; ~0.3% cross +/-3*std. Pick a larger n_std for a band that
% baseline noise essentially never crosses.
default_n_std = 3;
sigma_char    = char(963);  % 'sigma' (kept ASCII-safe regardless of file encoding)
answer = inputdlg(...
    sprintf(['Significance threshold = n_std %s pixel baseline std\n\n' ...
             'Expected fraction of baseline samples crossing by chance:\n' ...
             '  n_std = 1  ->  ~32%%\n' ...
             '  n_std = 2  ->  ~5%%\n' ...
             '  n_std = 3  ->  ~0.3%%\n\n' ...
             'Enter n_std:'], sigma_char), ...
    'Step 8: significance threshold multiplier', [1 60], {num2str(default_n_std)});
if isempty(answer)
    error('No threshold multiplier entered.');
end
n_std = str2double(answer{1});
assert(isfinite(n_std) && n_std > 0, 'Threshold multiplier must be a positive number.');

if n_std == round(n_std)
    n_std_label = sprintf('%d%s', n_std, sigma_char);
else
    n_std_label = sprintf('%g%s', n_std, sigma_char);
end
out_tag = sprintf('%s_%s', base_name, n_std_label);
fprintf('Using significance threshold: |dF/F| > %g * std  (label: %s)\n', n_std, n_std_label);

%% -------------------------
% PER-PIXEL BASELINE STD AND SIGNIFICANCE THRESHOLD
% -------------------------
baseline_idx = t_s < 0;
assert(any(baseline_idx), 'No pre-stimulation frames (t_s < 0) found in this movie.');

always_nan_mask = all(isnan(movie), 3);                              % H x W
pixel_std       = std(movie(:, :, baseline_idx), 0, 3, 'omitnan');   % H x W
sig_threshold   = n_std * pixel_std;                                 % H x W

sig_mask = abs(movie) > sig_threshold;     % H x W x T (NaN comparisons -> false)

thresh_movie = movie;
thresh_movie(~sig_mask) = NaN;

fprintf('Baseline frames: %d  |  In-mask pixels: %d / %d\n', ...
    sum(baseline_idx), sum(~always_nan_mask(:)), H * W);

%% -------------------------
% SAVE THRESHOLDED MOVIE
% -------------------------
thresh_fname = sprintf('thresh_%s.mat', out_tag);
thresh_fpath = fullfile(save_dir, thresh_fname);
save(thresh_fpath, 'thresh_movie', 'sig_mask', 'pixel_std', 'sig_threshold', 'n_std', ...
    'always_nan_mask', 't_s', '-v7.3');
fprintf('Saved thresholded movie: %s\n', thresh_fname);

%% -------------------------
% COLOR LIMITS (symmetric, 1st/99th percentile — same convention as steps 4/7)
% -------------------------
finite_vals = movie(isfinite(movie));
if ~isempty(finite_vals)
    q           = quantile(finite_vals, [0.01 0.99]);
    clim_to_use = [-max(abs(q))  max(abs(q))];
else
    clim_to_use = [-0.02 0.02];
end
cmap = bwr_colormap();

%% -------------------------
% FRAME-GRID FIGURE
% Thresholded dF/F at selected pre-/post-stim timepoints, same display
% spacing convention as steps 4/7 (display_step_s, n_prestim_display),
% with pre_sec/post_sec read directly from this movie's time axis.
% -------------------------
pre_sec  = -t_s(1);
post_sec = t_s(end);

prestim_display_t  = -display_step_s * (n_prestim_display : -1 : 1);
poststim_display_t = 0 : display_step_s : post_sec;
display_t_all      = [prestim_display_t, poststim_display_t];

display_frame_idx = zeros(size(display_t_all));
for di = 1:numel(display_t_all)
    [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
end

n_display = numel(display_frame_idx);
n_cols    = min(7, n_display);
n_rows    = ceil(n_display / n_cols);

fig = figure('Color', 'w', ...
    'Name', sprintf('Thresholded dF/F %s', cond_label), ...
    'Position', [50 50  min(1800, 240 * n_cols)  240 * n_rows + 70]);
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');

last_ax = [];
for di = 1:n_display
    fi = display_frame_idx(di);
    if fi < 1 || fi > T, continue; end

    ax = nexttile(tl);
    image(ax, thresh_frame_to_rgb(movie(:, :, fi), sig_mask(:, :, fi), always_nan_mask, ...
        clim_to_use, cmap, mask_color_outside, mask_color_inactive));
    axis(ax, 'image'); axis(ax, 'off');
    set(ax, 'YDir', 'normal');
    hold(ax, 'on');
    visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.6);
    title(ax, sprintf('t = %+.1f s', t_s(fi)), 'FontSize', 8);
    last_ax = ax;
end

if ~isempty(last_ax)
    colormap(last_ax, cmap);
    clim(last_ax, clim_to_use);
    colorbar(last_ax);
end

title(tl, sprintf('Thresholded dF/F (|dF/F| > %g%s)  |  %s', n_std, sigma_char, cond_label), ...
    'Interpreter', 'none', 'FontSize', 11);

frame_grid_fname = sprintf('thresh_%s_frame_grid.png', out_tag);
exportgraphics(fig, fullfile(save_dir, frame_grid_fname), 'Resolution', 150);
close(fig);
fprintf('Saved figure: %s\n', frame_grid_fname);

%% -------------------------
% OPTIONAL VIDEO EXPORT
% -------------------------
export_choice = questdlg( ...
    sprintf('Export the thresholded movie for "%s" as an MP4 video?', cond_label), ...
    'Export thresholded video?', 'Export video', 'Skip', 'Skip');

if strcmp(export_choice, 'Export video')
    video_fpath = fullfile(save_dir, sprintf('thresh_%s.mp4', out_tag));
    write_thresh_video(video_fpath, movie, sig_mask, always_nan_mask, t_s, cond_label, ...
        clim_to_use, cmap, mask_color_outside, mask_color_inactive, ...
        video_frame_rate_fps, video_quality);
    fprintf('Saved thresholded video: %s\n', sprintf('thresh_%s.mp4', out_tag));
end

%% -------------------------
% PEAK-RESPONSE TIMEPOINT
% (post-stim frame with the most suprathreshold pixels)
% -------------------------
post_idx = find(t_s >= 0);
assert(~isempty(post_idx), 'No post-stimulation frames (t_s >= 0) found in this movie.');

sig_counts          = squeeze(sum(sum(sig_mask(:, :, post_idx), 1), 2));
[~, peak_local_idx] = max(sig_counts);
peak_idx            = post_idx(peak_local_idx);

fprintf('Peak response at t = %+.2f s  (%d suprathreshold pixels)\n', ...
    t_s(peak_idx), sig_counts(peak_local_idx));

%% -------------------------
% INTERACTIVE VIEWER + PIXEL PICKING
% -------------------------
picked = pick_pixels_interactively(movie, sig_mask, always_nan_mask, t_s, peak_idx, ...
    cond_label, clim_to_use, cmap, mask_color_outside, mask_color_inactive);

%% -------------------------
% PER-PIXEL dF/F(t) FIGURES FOR PICKED PIXELS
% -------------------------
if isempty(picked)
    fprintf('\nNo pixels picked.\n');
else
    fprintf('\nGenerating dF/F(t) figures for %d picked pixel(s)...\n', size(picked, 1));
    for pi = 1:size(picked, 1)
        row = picked(pi, 1);
        col = picked(pi, 2);
        plot_pixel_timecourse(squeeze(movie(row, col, :)), t_s, sig_threshold(row, col), n_std, sigma_char, ...
            row, col, cond_label, save_dir);
    end
end

fprintf('\nDone.\nAll outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function rgb = thresh_frame_to_rgb(frame, sig_frame, always_nan_mask, clim_range, cmap, ...
    color_outside, color_inactive)
% Maps a single thresholded dF/F frame to RGB:
%   - suprathreshold in-mask pixels (sig_frame true) -> true dF/F value through cmap/clim_range
%   - in-mask pixels currently within the +/- std band -> color_inactive (solid)
%   - pixels that are NaN for the entire movie (out of mask) -> color_outside (solid)
n = size(cmap, 1);
scaled = (frame - clim_range(1)) / (clim_range(2) - clim_range(1));
scaled(~isfinite(scaled)) = 0;
idx = uint8(min(max(round(scaled * (n - 1)), 0), n - 1));
rgb = ind2rgb(idx, cmap);

inactive_mask = ~always_nan_mask & ~sig_frame;

for c = 1:3
    chan = rgb(:, :, c);
    chan(inactive_mask)   = color_inactive(c);
    chan(always_nan_mask) = color_outside(c);
    rgb(:, :, c) = chan;
end
end

function write_thresh_video(video_file, movie_stack, sig_mask, always_nan_mask, time_axis_sec, ...
    title_prefix, clim_range, cmap, color_outside, color_inactive, frame_rate, quality)
% Writes an MP4 of the thresholded dF/F(x,y,t) movie using the same
% three-tier solid-color rendering as thresh_frame_to_rgb.

[~, ~, n_frames] = size(movie_stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax  = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);

writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate;
writer.Quality   = quality;
open(writer);

img_handle = image(ax, thresh_frame_to_rgb(movie_stack(:, :, 1), sig_mask(:, :, 1), ...
    always_nan_mask, clim_range, cmap, color_outside, color_inactive));
axis(ax, 'image'); axis(ax, 'off');
set(ax, 'YDir', 'normal');
hold(ax, 'on');
visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);

title_handle = title(ax, '', 'Interpreter', 'none');
colormap(ax, cmap);
clim(ax, clim_range);
cb = colorbar(ax, 'eastoutside');
cb.Label.String = '\DeltaF/F (suprathreshold only)';
drawnow;

target_frame_size = [];
for k = 1:n_frames
    set(img_handle, 'CData', thresh_frame_to_rgb(movie_stack(:, :, k), sig_mask(:, :, k), ...
        always_nan_mask, clim_range, cmap, color_outside, color_inactive));
    set(title_handle, 'String', sprintf('%s | t = %+.2f s | suprathreshold pixels: %d', ...
        title_prefix, time_axis_sec(k), sum(sum(sig_mask(:, :, k)))));

    drawnow;
    frame_rgb = capture_consistent_frame(fig, target_frame_size);
    if isempty(target_frame_size)
        target_frame_size = size(frame_rgb(:, :, 1));
    end
    writeVideo(writer, frame_rgb);
end

close(writer);
close(fig);
end

function frame_rgb = capture_consistent_frame(fig, target_frame_size)
frame_struct = getframe(fig);
frame_rgb = frame2im(frame_struct);

if isempty(target_frame_size)
    return;
end

if ~isequal(size(frame_rgb, 1), target_frame_size(1)) || ...
        ~isequal(size(frame_rgb, 2), target_frame_size(2))
    frame_rgb = imresize(frame_rgb, target_frame_size);
end
end

function set_threshold_frame(img_handle, title_handle, movie, sig_mask, always_nan_mask, t_s, ...
    cond_label, clim_range, cmap, color_outside, color_inactive, k)
[~, ~, T] = size(movie);
k = max(1, min(T, round(k)));
set(img_handle, 'CData', thresh_frame_to_rgb(movie(:, :, k), sig_mask(:, :, k), ...
    always_nan_mask, clim_range, cmap, color_outside, color_inactive));
set(title_handle, 'String', sprintf('%s | t = %+.2f s | suprathreshold pixels: %d', ...
    cond_label, t_s(k), sum(sum(sig_mask(:, :, k)))));
end

function picked = pick_pixels_interactively(movie, sig_mask, always_nan_mask, t_s, peak_idx, ...
    cond_label, clim_range, cmap, color_outside, color_inactive)
% Opens a time-slider viewer (left) over the thresholded movie and a
% static peak-response map (right). Click pixels on either axes to pick
% them for individual dF/F(t) plots:
%   left-click       -> add the clicked pixel
%   right-click / 'u' -> undo the most recent pick
%   Enter / Escape    -> finish picking and close the figure
% Returns an N x 2 matrix of [row, col] picked pixels (possibly empty).

[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', sprintf('Pick pixels — %s', cond_label), ...
    'Position', [60 60 1300 650]);

ax1 = subplot(1, 2, 1);
img1 = image(ax1, thresh_frame_to_rgb(movie(:, :, peak_idx), sig_mask(:, :, peak_idx), ...
    always_nan_mask, clim_range, cmap, color_outside, color_inactive));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
visboundaries(ax1, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
colormap(ax1, cmap); clim(ax1, clim_range);
title1 = title(ax1, '', 'Interpreter', 'none');
set_threshold_frame(img1, title1, movie, sig_mask, always_nan_mask, t_s, cond_label, ...
    clim_range, cmap, color_outside, color_inactive, peak_idx);

slider = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.10 0.02 0.34 0.04], ...
    'Min', 1, 'Max', T, 'Value', peak_idx, ...
    'SliderStep', [1 / (T - 1),  5 / (T - 1)], ...
    'Callback', @(src, ~) set_threshold_frame(img1, title1, movie, sig_mask, always_nan_mask, ...
        t_s, cond_label, clim_range, cmap, color_outside, color_inactive, get(src, 'Value')));

ax2 = subplot(1, 2, 2);
image(ax2, thresh_frame_to_rgb(movie(:, :, peak_idx), sig_mask(:, :, peak_idx), ...
    always_nan_mask, clim_range, cmap, color_outside, color_inactive));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
visboundaries(ax2, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
colormap(ax2, cmap); clim(ax2, clim_range);
title(ax2, sprintf('Peak response | %s | t = %+.2f s', cond_label, t_s(peak_idx)), ...
    'Interpreter', 'none');

sgtitle(fig, ['Click pixels to pick them for dF/F(t) plots   |   ' ...
    'left-click: add pixel   \cdot   right-click or ''u'': undo last   \cdot   Enter: done']);

picked  = zeros(0, 2);
markers = gobjects(0, 1);

while true
    [x, y, button] = ginput(1);
    if isempty(button)
        break;   % figure closed by the user
    end

    if button == 1   % left click -> add picked pixel
        ax  = gca;
        row = round(y);
        col = round(x);
        if row < 1 || row > H || col < 1 || col > W
            continue;
        end
        picked(end + 1, :) = [row, col];                                       %#ok<AGROW>
        markers(end + 1)   = plot(ax, col, row, 'w+', 'MarkerSize', 12, 'LineWidth', 1.6); %#ok<AGROW>
        fprintf('  Picked pixel (%d, %d)   [%d selected]\n', row, col, size(picked, 1));

    elseif button == 3 || button == double('u') || button == 8   % undo last pick
        if ~isempty(picked)
            delete(markers(end));
            markers(end, :) = [];
            picked(end, :)  = [];
            fprintf('  Undid last pick   [%d remaining]\n', size(picked, 1));
        end

    elseif button == 13 || button == 27   % Enter / Escape -> done
        break;
    end
end

if isvalid(fig), close(fig); end
end

function plot_pixel_timecourse(trace, t_s, px_thresh, n_std, sigma_char, row, col, cond_label, save_dir)
% Plots a single pixel's full dF/F(t) trace with its +/- (n_std*std)
% significance band, highlighting timepoints where the trace exceeds it.

fig = figure('Color', 'w', 'Position', [120 120 640 420]);
ax  = axes(fig);
hold(ax, 'on');

h_band = patch(ax, [t_s(1) t_s(end) t_s(end) t_s(1)], [-px_thresh -px_thresh px_thresh px_thresh], ...
    [0.85 0.85 0.85], 'FaceAlpha', 0.45, 'EdgeColor', 'none');
xline(ax, 0, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1);

h_trace = plot(ax, t_s, trace, '-', 'Color', [0.10 0.30 0.80], 'LineWidth', 1.3);

supra = abs(trace) > px_thresh;
h_supra = plot(ax, t_s(supra), trace(supra), 'o', 'MarkerSize', 4, ...
    'MarkerFaceColor', [0.85 0.20 0.10], 'MarkerEdgeColor', 'none');

xlabel(ax, 'Time relative to stimulation onset (s)');
ylabel(ax, '\DeltaF/F');
title(ax, sprintf('dF/F(t) for pixel (%d,%d) for %s', row, col, cond_label), 'Interpreter', 'none');
legend(ax, [h_band, h_trace, h_supra], ...
    {sprintf('baseline \\pm%g%s = \\pm%.4f', n_std, sigma_char, px_thresh), 'dF/F(t)', 'suprathreshold'}, ...
    'Location', 'best', 'Box', 'off');
grid(ax, 'on'); box(ax, 'on');

fig_fname = sprintf('dff_t_pixel_r%d_c%d_%s.png', row, col, cond_label);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('  Saved figure: %s\n', fig_fname);
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
