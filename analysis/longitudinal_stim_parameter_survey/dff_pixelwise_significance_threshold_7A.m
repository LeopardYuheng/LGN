%% dff_pixelwise_significance_threshold_7A.m
% Step 7_A: Per-pixel significance thresholding of Method-0 dF/F movies.
%
% Scans a step-5_A output folder for mean_dff_ch*.mat files, lets the user
% select which channel-current conditions to process (sorted by channel then
% current), then for each selected condition:
%   1. Computes per-pixel baseline std from pre-stim frames (t_s < 0).
%   2. Flags |dF/F(x,y,t)| > n_std * std(x,y) as suprathreshold.
%   3. Saves the thresholded movie + frame-grid figure.
%   4. If a single condition is selected: opens the interactive viewer and
%      pixel-picking tool. Multiple conditions: batch-processes all.
%
% Optional V1 boundary overlay (from step 6 day_setup) is drawn as a green
% contour on all figures.  Display time window is user-specified (default
% -0.2 to 1.2 s); all frames are always saved regardless.
%
% n_std may be set to 0, which disables thresholding entirely: every
% in-mask pixel is shown at its true dF/F value in the figures/video (no
% suprathreshold/inactive distinction), i.e. step 7_A degenerates into a
% plain figure/movie plotter for the step-5_A dF/F movie.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside  = [0.15 0.15 0.15];
mask_color_inactive = [0.55 0.55 0.55];
video_frame_rate_fps = 10;
video_quality        = 95;
display_step_s       = 0.1;   % frame-grid spacing (seconds); all frames saved regardless

%% -------------------------
% SELECT ROOT FOLDER + CONDITIONS
% -------------------------
root_dir = uigetdir(pwd, 'Select step-5_A output folder (contains ch{N}_{I}uA/ subfolders)');
if isequal(root_dir, 0), error('No folder selected.'); end

mat_files = dir(fullfile(root_dir, '**', 'mean_dff_ch*uA.mat'));
assert(~isempty(mat_files), 'No mean_dff_ch*.mat files found under:\n  %s', root_dir);

% Extract channel and current from each filename; sort by channel then current
chs  = nan(numel(mat_files), 1);
curs = nan(numel(mat_files), 1);
for i = 1:numel(mat_files)
    tok = regexp(mat_files(i).name, 'ch(\d+)_([\d.]+)uA', 'tokens', 'once');
    if ~isempty(tok)
        chs(i)  = str2double(tok{1});
        curs(i) = str2double(tok{2});
    end
end
valid = isfinite(chs) & isfinite(curs);
mat_files = mat_files(valid);
chs  = chs(valid);
curs = curs(valid);
[~, sord] = sortrows([chs curs]);
mat_files = mat_files(sord);
chs       = chs(sord);
curs      = curs(sord);

cond_strs = arrayfun(@(i) sprintf('Ch %d  |  %g uA', chs(i), curs(i)), ...
    (1:numel(mat_files))', 'UniformOutput', false);

[sel_idx, ok] = listdlg( ...
    'Name',          'Select conditions to threshold', ...
    'PromptString',  'Available conditions (Ctrl+click for multiple):', ...
    'ListString',    cond_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [320 260], ...
    'OKString',      'Analyze selected', ...
    'CancelString',  'Cancel');
if ~ok || isempty(sel_idx), error('No conditions selected.'); end

mat_files = mat_files(sel_idx);
chs       = chs(sel_idx);
curs      = curs(sel_idx);
n_sel     = numel(mat_files);
fprintf('Selected %d condition(s):\n', n_sel);
for i = 1:n_sel, fprintf('  Ch %d  |  %g uA\n', chs(i), curs(i)); end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(root_dir, 'Select output folder for thresholded movies / figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY
% -------------------------
v1_outline_color = [0.10 0.85 0.30];
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');

% Load one movie just to get H x W for V1 size check
S0 = load(fullfile(mat_files(1).folder, mat_files(1).name));
if isfield(S0, 'mean_dff_movie'), tmp = S0.mean_dff_movie;
else,                              tmp = S0.dff_movie; end
[H0, W0, ~] = size(tmp); clear tmp S0;

if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = get_v1_boundary(fullfile(v1_fp, v1_fn), [H0 W0]);
    if ~isempty(V1_mask), fprintf('V1 boundary loaded: %s\n', v1_fn); end
end

%% -------------------------
% DISPLAY TIME WINDOW (interactive)
% -------------------------
win_ans = inputdlg( ...
    {'Frame-grid start time (s):', 'Frame-grid end   time (s):'}, ...
    'Frame-grid display window', [1 50], {'-0.1', '0.7'});
if isempty(win_ans), error('Display window not specified. Cancelled.'); end
display_tmin = str2double(win_ans{1});
display_tmax = str2double(win_ans{2});
assert(isfinite(display_tmin) && isfinite(display_tmax) && display_tmin < display_tmax, ...
    'display_tmin must be less than display_tmax.');

%% -------------------------
% SIGNIFICANCE THRESHOLD MULTIPLIER (n_std)
% -------------------------
sigma_char    = char(963);
default_n_std = 3;
answer = inputdlg(...
    sprintf(['|dF/F| > n_std %s pixel baseline std\n\n' ...
             '  n_std = 0 -> no threshold (plots raw dF/F)\n' ...
             '  n_std = 1 -> ~32%% baseline crossing chance\n' ...
             '  n_std = 2 -> ~5%%\n' ...
             '  n_std = 3 -> ~0.3%%\n\nEnter n_std:'], sigma_char), ...
    'Step 7_A: significance threshold multiplier', [1 60], {num2str(default_n_std)});
if isempty(answer), error('No threshold multiplier entered.'); end
n_std = str2double(answer{1});
assert(isfinite(n_std) && n_std >= 0, 'n_std must be a non-negative number.');
no_threshold = (n_std == 0);
if no_threshold
    n_std_label = 'raw';
elseif n_std == round(n_std)
    n_std_label = sprintf('%d%s', n_std, sigma_char);
else
    n_std_label = sprintf('%g%s', n_std, sigma_char);
end
if no_threshold
    fprintf('No threshold (n_std = 0): plotting raw dF/F.\n');
else
    fprintf('Threshold: |dF/F| > %g * std\n', n_std);
end

%% -------------------------
% MAIN LOOP — one pass per selected condition
% -------------------------
last_condition = struct('movie', [], 'sig_mask', [], 'always_nan_mask', [], ...
    't_s', [], 'sig_threshold', [], 'cond_label', '', 'cond_save_dir', '');
cmap = jet(256);
skip_all_videos = false;

for ci = 1:n_sel
    mv_fpath   = fullfile(mat_files(ci).folder, mat_files(ci).name);
    [~, base_name] = fileparts(mat_files(ci).name);

    S = load(mv_fpath);
    if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
    elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
    else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', mv_fpath); end
    assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

    t_s = double(S.t_s(:)');
    [H, W, T] = size(movie);

    tok = regexp(base_name, '(ch\d+_[\d.]+uA(?:_trial\d+)?)', 'tokens', 'once');
    cond_label = tok{1};
    if isempty(cond_label), cond_label = base_name; end

    fprintf('\n[%d/%d] %s  (%d x %d x %d)\n', ci, n_sel, cond_label, H, W, T);

    % Per-condition output subfolder
    cond_save_dir = fullfile(save_dir, sprintf('ch%d_%guA', chs(ci), curs(ci)));
    if ~exist(cond_save_dir, 'dir'), mkdir(cond_save_dir); end

    out_tag = sprintf('%s_%s', base_name, n_std_label);

    % Threshold
    baseline_idx    = t_s < 0;
    always_nan_mask = all(isnan(movie), 3);
    pixel_std       = std(movie(:,:,baseline_idx), 0, 3, 'omitnan');
    sig_threshold   = n_std * pixel_std;
    if no_threshold
        sig_mask = repmat(~always_nan_mask, 1, 1, T);
    else
        sig_mask = abs(movie) > sig_threshold;
    end
    thresh_movie    = movie;
    thresh_movie(~sig_mask) = NaN;

    fprintf('  Baseline frames: %d  |  In-mask pixels: %d\n', ...
        sum(baseline_idx), sum(~always_nan_mask(:)));

    % Save .mat
    thresh_fname = sprintf('thresh_%s.mat', out_tag);
    save(fullfile(cond_save_dir, thresh_fname), ...
        'thresh_movie', 'sig_mask', 'pixel_std', 'sig_threshold', 'n_std', ...
        'always_nan_mask', 't_s', '-v7.3');
    fprintf('  Saved: %s\n', thresh_fname);

    % Color limits — autoscale to this condition's in-mask dF/F range (same as step 5_A)
    clim_to_use = data_clim(movie, ~always_nan_mask);

    % Frame-grid display indices
    display_t_all = display_tmin : display_step_s : display_tmax;
    display_frame_idx = zeros(size(display_t_all));
    for di = 1:numel(display_t_all)
        [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
    end
    display_frame_idx = unique(display_frame_idx, 'stable');
    n_display = numel(display_frame_idx);
    n_cols    = min(7, n_display);
    n_rows    = ceil(n_display / n_cols);

    % Frame-grid figure
    fig = figure('Color', 'w', 'Visible', 'off', ...
        'Name', sprintf('Thresholded dF/F %s', cond_label), ...
        'Position', [50 50 min(1800, 240*n_cols) 240*n_rows + 70]);
    tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');
    last_ax = [];
    for di = 1:n_display
        fi = display_frame_idx(di);
        if fi < 1 || fi > T, continue; end
        ax = nexttile(tl);
        image(ax, thresh_frame_to_rgb(movie(:,:,fi), sig_mask(:,:,fi), always_nan_mask, ...
            clim_to_use, cmap, mask_color_outside, mask_color_inactive));
        axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','normal'); hold(ax,'on');
        visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.6);
        if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
            visboundaries(ax, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
        end
        title(ax, sprintf('t = %+.1f s', t_s(fi)), 'FontSize', 8);
        last_ax = ax;
    end
    if ~isempty(last_ax)
        colormap(last_ax, cmap); clim(last_ax, clim_to_use); colorbar(last_ax);
    end
    if no_threshold
        title(tl, sprintf('Raw dF/F (no threshold)  |  %s', cond_label), ...
            'Interpreter', 'none', 'FontSize', 11);
    else
        title(tl, sprintf('Thresholded dF/F (|dF/F| > %g%s)  |  %s', ...
            n_std, sigma_char, cond_label), 'Interpreter', 'none', 'FontSize', 11);
    end

    frame_grid_fname = sprintf('thresh_%s_frame_grid.png', out_tag);
    exportgraphics(fig, fullfile(cond_save_dir, frame_grid_fname), 'Resolution', 150);
    close(fig);
    fprintf('  Saved: %s\n', frame_grid_fname);

    % Optional video
    if ~skip_all_videos
        export_choice = questdlg( ...
            sprintf('Export thresholded video for "%s"?', cond_label), ...
            'Export video?', 'Export', 'Skip', 'Skip All', 'Skip');
        if strcmp(export_choice, 'Skip All')
            skip_all_videos = true;
        end
    else
        export_choice = 'Skip';
    end
    if strcmp(export_choice, 'Export')
        video_fpath = fullfile(cond_save_dir, sprintf('thresh_%s.mp4', out_tag));
        write_thresh_video(video_fpath, movie, sig_mask, always_nan_mask, t_s, cond_label, ...
            clim_to_use, cmap, mask_color_outside, mask_color_inactive, ...
            video_frame_rate_fps, video_quality, V1_mask, v1_outline_color);
        fprintf('  Saved video: thresh_%s.mp4\n', out_tag);
    end

    % Store last condition for interactive viewer (single-condition case)
    last_condition.movie           = movie;
    last_condition.sig_mask        = sig_mask;
    last_condition.always_nan_mask = always_nan_mask;
    last_condition.t_s             = t_s;
    last_condition.sig_threshold   = sig_threshold;
    last_condition.clim_to_use     = clim_to_use;
    last_condition.cond_label      = cond_label;
    last_condition.cond_save_dir   = cond_save_dir;
end

fprintf('\nDone. All outputs in:\n  %s\n', save_dir);

%% -------------------------
% INTERACTIVE VIEWER + PIXEL PICKING
% Only shown when exactly one condition is selected.
% -------------------------
if n_sel == 1
    movie           = last_condition.movie;
    sig_mask        = last_condition.sig_mask;
    always_nan_mask = last_condition.always_nan_mask;
    t_s             = last_condition.t_s;
    sig_threshold   = last_condition.sig_threshold;
    clim_to_use     = last_condition.clim_to_use;
    cond_label      = last_condition.cond_label;
    cond_save_dir   = last_condition.cond_save_dir;

    post_idx = find(t_s >= 0);
    sig_counts = squeeze(sum(sum(sig_mask(:,:,post_idx), 1), 2));
    [~, pk_loc] = max(sig_counts);
    peak_idx    = post_idx(pk_loc);
    fprintf('\nPeak response at t = %+.2f s  (%d suprathreshold pixels)\n', ...
        t_s(peak_idx), sig_counts(pk_loc));

    picked = pick_pixels_interactively(movie, sig_mask, always_nan_mask, t_s, peak_idx, ...
        cond_label, clim_to_use, cmap, mask_color_outside, mask_color_inactive, ...
        V1_mask, v1_outline_color);

    if isempty(picked)
        fprintf('No pixels picked.\n');
    else
        fprintf('Generating dF/F(t) figures for %d picked pixel(s)...\n', size(picked,1));
        for pi = 1:size(picked, 1)
            row = picked(pi,1); col = picked(pi,2);
            plot_pixel_timecourse(squeeze(movie(row,col,:)), t_s, sig_threshold(row,col), ...
                n_std, sigma_char, row, col, cond_label, cond_save_dir);
        end
    end
else
    fprintf('\n(%d conditions processed — interactive viewer skipped for multi-condition runs.)\n', n_sel);
end

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
    title_prefix, clim_range, cmap, color_outside, color_inactive, frame_rate, quality, ...
    V1_mask, v1_color)
% Writes an MP4 of the thresholded dF/F(x,y,t) movie using the same
% three-tier solid-color rendering as thresh_frame_to_rgb.
if nargin < 13, V1_mask = []; end
if nargin < 14, v1_color = [0.10 0.85 0.30]; end

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
if ~isempty(V1_mask), visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0); end

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
    cond_label, clim_range, cmap, color_outside, color_inactive, V1_mask, v1_color)
% Opens a time-slider viewer (left) over the thresholded movie and a
% static peak-response map (right). Click pixels on either axes to pick
% them for individual dF/F(t) plots:
%   left-click       -> add the clicked pixel
%   right-click / 'u' -> undo the most recent pick
%   Enter / Escape    -> finish picking and close the figure
% Returns an N x 2 matrix of [row, col] picked pixels (possibly empty).
if nargin < 11, V1_mask = []; end
if nargin < 12, v1_color = [0.10 0.85 0.30]; end

[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', sprintf('Pick pixels — %s', cond_label), ...
    'Position', [60 60 1300 650]);

ax1 = subplot(1, 2, 1);
img1 = image(ax1, thresh_frame_to_rgb(movie(:, :, peak_idx), sig_mask(:, :, peak_idx), ...
    always_nan_mask, clim_range, cmap, color_outside, color_inactive));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
visboundaries(ax1, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask), visboundaries(ax1, V1_mask, 'Color', v1_color, 'LineWidth', 1.0); end
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
if ~isempty(V1_mask), visboundaries(ax2, V1_mask, 'Color', v1_color, 'LineWidth', 1.0); end
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

xline(ax, 0, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1);
h_trace = plot(ax, t_s, trace, '-', 'Color', [0.10 0.30 0.80], 'LineWidth', 1.3);

xlabel(ax, 'Time relative to stimulation onset (s)');
ylabel(ax, '\DeltaF/F');
title(ax, sprintf('dF/F(t) for pixel (%d,%d) for %s', row, col, cond_label), 'Interpreter', 'none');

if n_std > 0
    h_band = patch(ax, [t_s(1) t_s(end) t_s(end) t_s(1)], [-px_thresh -px_thresh px_thresh px_thresh], ...
        [0.85 0.85 0.85], 'FaceAlpha', 0.45, 'EdgeColor', 'none');
    uistack(h_band, 'bottom');

    supra = abs(trace) > px_thresh;
    h_supra = plot(ax, t_s(supra), trace(supra), 'o', 'MarkerSize', 4, ...
        'MarkerFaceColor', [0.85 0.20 0.10], 'MarkerEdgeColor', 'none');

    legend(ax, [h_band, h_trace, h_supra], ...
        {sprintf('baseline \\pm%g%s = \\pm%.4f', n_std, sigma_char, px_thresh), 'dF/F(t)', 'suprathreshold'}, ...
        'Location', 'best', 'Box', 'off');
else
    legend(ax, h_trace, {'dF/F(t) (no threshold)'}, 'Location', 'best', 'Box', 'off');
end
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

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie, so the colorbar spans the real data range with no clipping.
% Same convention as step 5_A/5_B.
if nargin >= 2 && ~isempty(mask)
    T = size(M, 3);
    v = M(repmat(logical(mask), [1 1 T]) & isfinite(M));
else
    v = M(isfinite(M));
end
if isempty(v)
    cl = [-0.02 0.02];
    return;
end
lo = min(v); hi = max(v);
if ~(hi > lo), cl = [-0.02 0.02]; else, cl = [lo hi]; end
end
