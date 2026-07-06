%% threshold_dff_method1_7B.m
% Step 7_B: Per-pixel significance thresholding of Method-1 dF/F movies.
%
% Scans a step-5_B output folder for mean_dff_m1_ch*.mat files, lets the
% user select which channel-current conditions to process (sorted by channel
% then current), then for each selected condition:
%
%   baseline_dff(x,y) = mean( dF/F(x,y, t<0) )   pre-stim mean
%   pixel_std(x,y)    = std(  dF/F(x,y, t<0) )   pre-stim std
%   suprathreshold    = |dF/F − baseline_dff| > n_std * pixel_std
%
% No external baseline file required. Same thresholding logic as step 7_C.
% Optional V1 boundary overlay; interactive display time window.
% Interactive pixel-picking viewer shown only for single-condition runs.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside  = [0.15 0.15 0.15];
mask_color_inactive = [0.55 0.55 0.55];
video_frame_rate_fps = 10;
video_quality        = 95;
display_step_s       = 0.1;

%% -------------------------
% SELECT ROOT FOLDER + CONDITIONS
% -------------------------
root_dir = uigetdir(pwd, 'Select step-5_B output folder (contains method1/ch{N}_{I}uA/ subfolders)');
if isequal(root_dir, 0), error('No folder selected.'); end

mat_files = dir(fullfile(root_dir, '**', 'mean_dff_m1_ch*uA.mat'));
assert(~isempty(mat_files), 'No mean_dff_m1_ch*.mat files found under:\n  %s', root_dir);

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

S0 = load(fullfile(mat_files(1).folder, mat_files(1).name));
if isfield(S0, 'mean_dff_movie'), tmp = S0.mean_dff_movie;
else,                              tmp = S0.dff_movie; end
[H0, W0, ~] = size(tmp); clear tmp S0;

[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');
if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = load_v1_mask(fullfile(v1_fp, v1_fn), [H0 W0]);
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
    sprintf(['|dF/F − baseline| > n_std %s pixel_std  (pre-stim std)\n\n' ...
             '  n_std = 1 -> ~32%% baseline crossing chance\n' ...
             '  n_std = 2 -> ~5%%\n' ...
             '  n_std = 3 -> ~0.3%%\n\nEnter n_std:'], sigma_char), ...
    'Step 7_B: significance threshold multiplier', [1 60], {num2str(default_n_std)});
if isempty(answer), error('No threshold multiplier entered.'); end
n_std = str2double(answer{1});
assert(isfinite(n_std) && n_std > 0, 'n_std must be a positive number.');
if n_std == round(n_std)
    n_std_label = sprintf('%d%s', n_std, sigma_char);
else
    n_std_label = sprintf('%g%s', n_std, sigma_char);
end
fprintf('Threshold: |dF/F − baseline| > %g * pixel_std\n', n_std);

%% -------------------------
% MAIN LOOP — one pass per selected condition
% -------------------------
cmap = jet(256);
skip_all_videos = false;

last_c = struct('movie', [], 'sig_mask', [], 'always_nan_mask', [], ...
    't_s', [], 'baseline_dff', [], 'sig_threshold', [], ...
    'clim_to_use', [], 'cond_label', '', 'cond_save_dir', '');

for ci = 1:n_sel
    mv_fpath   = fullfile(mat_files(ci).folder, mat_files(ci).name);
    [~, base_name] = fileparts(mat_files(ci).name);

    S = load(mv_fpath);
    if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
    elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
    else, error('File missing dff_movie/mean_dff_movie:\n  %s', mv_fpath); end
    assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

    t_s = double(S.t_s(:)');
    [H, W, T] = size(movie);
    tok = regexp(base_name, '(ch\d+_[\d.]+uA(?:_trial\d+)?)', 'tokens', 'once');
    cond_label = tok{1};
    if isempty(cond_label), cond_label = base_name; end

    fprintf('\n[%d/%d] %s  (%d x %d x %d)\n', ci, n_sel, cond_label, H, W, T);

    cond_save_dir = fullfile(save_dir, sprintf('ch%d_%guA', chs(ci), curs(ci)));
    if ~exist(cond_save_dir, 'dir'), mkdir(cond_save_dir); end

    out_tag = sprintf('%s_%s_m1', base_name, n_std_label);

    % Threshold
    prestim_idx   = find(t_s < 0);
    always_nan_mask = all(isnan(movie), 3);
    baseline_dff  = mean(movie(:,:,prestim_idx), 3, 'omitnan');
    pixel_std     = std( movie(:,:,prestim_idx), 0, 3, 'omitnan');
    sig_threshold = n_std * pixel_std;
    movie_centered = movie - baseline_dff;
    sig_mask       = abs(movie_centered) > sig_threshold;
    thresh_movie   = movie;
    thresh_movie(~sig_mask) = NaN;

    fprintf('  Pre-stim frames: %d  |  In-mask pixels: %d\n', ...
        numel(prestim_idx), sum(~always_nan_mask(:)));

    % Save .mat
    thresh_fname = sprintf('thresh_%s.mat', out_tag);
    save(fullfile(cond_save_dir, thresh_fname), ...
        'thresh_movie', 'sig_mask', 'baseline_dff', 'pixel_std', ...
        'sig_threshold', 'n_std', 'always_nan_mask', 't_s', '-v7.3');
    fprintf('  Saved: %s\n', thresh_fname);

    % Color limits
    clim_to_use = [-0.05 0.05];

    % Frame-grid display indices
    display_t_all = display_tmin : display_step_s : display_tmax;
    display_frame_idx = zeros(size(display_t_all));
    for di = 1:numel(display_t_all)
        [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
    end
    display_frame_idx = unique(display_frame_idx, 'stable');
    n_display = numel(display_frame_idx);
    n_cols    = 3;
    n_rows    = 3;

    % Frame-grid figure
    fig = figure('Color', 'w', 'Visible', 'off', ...
        'Name', sprintf('Thresholded dF/F (M1) %s', cond_label), ...
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
    title(tl, sprintf('Thresholded dF/F (|dF/F − baseline| > %g%s, M1)  |  %s', ...
        n_std, sigma_char, cond_label), 'Interpreter', 'none', 'FontSize', 11);

    frame_grid_fname = sprintf('thresh_%s_frame_grid.png', out_tag);
    exportgraphics(fig, fullfile(cond_save_dir, frame_grid_fname), 'Resolution', 150);
    close(fig);
    fprintf('  Saved: %s\n', frame_grid_fname);

    % Optional video
    if ~skip_all_videos
        export_choice = questdlg( ...
            sprintf('Export thresholded video for "%s" (M1)?', cond_label), ...
            'Export video?', 'Export', 'Skip', 'Skip All', 'Skip');
        if strcmp(export_choice, 'Skip All')
            skip_all_videos = true;
        end
    else
        export_choice = 'Skip';
    end
    if strcmp(export_choice, 'Export')
        video_fpath = fullfile(cond_save_dir, sprintf('thresh_%s.mp4', out_tag));
        write_thresh_video(video_fpath, movie, sig_mask, always_nan_mask, t_s, ...
            sprintf('%s | M1', cond_label), clim_to_use, cmap, ...
            mask_color_outside, mask_color_inactive, video_frame_rate_fps, video_quality, ...
            V1_mask, v1_outline_color);
        fprintf('  Saved video: thresh_%s.mp4\n', out_tag);
    end

    last_c.movie           = movie;
    last_c.sig_mask        = sig_mask;
    last_c.always_nan_mask = always_nan_mask;
    last_c.t_s             = t_s;
    last_c.baseline_dff    = baseline_dff;
    last_c.sig_threshold   = sig_threshold;
    last_c.clim_to_use     = clim_to_use;
    last_c.cond_label      = cond_label;
    last_c.cond_save_dir   = cond_save_dir;
end

fprintf('\nDone. All outputs in:\n  %s\n', save_dir);

%% -------------------------
% INTERACTIVE VIEWER + PIXEL PICKING (single-condition runs only)
% -------------------------
if n_sel == 1
    movie           = last_c.movie;
    sig_mask        = last_c.sig_mask;
    always_nan_mask = last_c.always_nan_mask;
    t_s             = last_c.t_s;
    baseline_dff    = last_c.baseline_dff;
    sig_threshold   = last_c.sig_threshold;
    clim_to_use     = last_c.clim_to_use;
    cond_label      = last_c.cond_label;
    cond_save_dir   = last_c.cond_save_dir;

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
            plot_pixel_timecourse(squeeze(movie(row,col,:)), t_s, baseline_dff(row,col), ...
                sig_threshold(row,col), n_std, sigma_char, row, col, cond_label, cond_save_dir);
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
if isempty(target_frame_size), return; end
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
set(title_handle, 'String', sprintf('%s | M1 | t = %+.2f s | suprathreshold pixels: %d', ...
    cond_label, t_s(k), sum(sum(sig_mask(:, :, k)))));
end

function picked = pick_pixels_interactively(movie, sig_mask, always_nan_mask, t_s, peak_idx, ...
    cond_label, clim_range, cmap, color_outside, color_inactive, V1_mask, v1_color)
if nargin < 11, V1_mask = []; end
if nargin < 12, v1_color = [0.10 0.85 0.30]; end
[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', sprintf('Pick pixels — %s (M1)', cond_label), ...
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

uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
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
title(ax2, sprintf('Peak response | %s | M1 | t = %+.2f s', cond_label, t_s(peak_idx)), ...
    'Interpreter', 'none');

sgtitle(fig, ['Click pixels to pick them for dF/F(t) plots   |   ' ...
    'left-click: add pixel   \cdot   right-click or ''u'': undo last   \cdot   Enter: done']);

picked  = zeros(0, 2);
markers = gobjects(0, 1);

while true
    [x, y, button] = ginput(1);
    if isempty(button), break; end

    if button == 1
        ax  = gca;
        row = round(y);
        col = round(x);
        if row < 1 || row > H || col < 1 || col > W, continue; end
        picked(end + 1, :) = [row, col];                                        %#ok<AGROW>
        markers(end + 1)   = plot(ax, col, row, 'w+', 'MarkerSize', 12, 'LineWidth', 1.6); %#ok<AGROW>
        fprintf('  Picked pixel (%d, %d)   [%d selected]\n', row, col, size(picked, 1));

    elseif button == 3 || button == double('u') || button == 8
        if ~isempty(picked)
            delete(markers(end));
            markers(end, :) = [];
            picked(end, :)  = [];
            fprintf('  Undid last pick   [%d remaining]\n', size(picked, 1));
        end

    elseif button == 13 || button == 27
        break;
    end
end

if isvalid(fig), close(fig); end
end

function plot_pixel_timecourse(trace, t_s, px_baseline, px_thresh, n_std, sigma_char, row, col, cond_label, save_dir)
fig = figure('Color', 'w', 'Position', [120 120 640 420]);
ax  = axes(fig);
hold(ax, 'on');

% Shaded band: baseline +/- threshold
lo = px_baseline - px_thresh;
hi = px_baseline + px_thresh;
h_band = patch(ax, [t_s(1) t_s(end) t_s(end) t_s(1)], [lo lo hi hi], ...
    [0.85 0.85 0.85], 'FaceAlpha', 0.45, 'EdgeColor', 'none');
yline(ax, px_baseline, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
xline(ax, 0, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1);

h_trace = plot(ax, t_s, trace, '-', 'Color', [0.10 0.30 0.80], 'LineWidth', 1.3);

supra   = abs(trace - px_baseline) > px_thresh;
h_supra = plot(ax, t_s(supra), trace(supra), 'o', 'MarkerSize', 4, ...
    'MarkerFaceColor', [0.85 0.20 0.10], 'MarkerEdgeColor', 'none');

xlabel(ax, 'Time relative to stimulation onset (s)');
ylabel(ax, '\DeltaF/F');
title(ax, sprintf('dF/F(t) for pixel (%d,%d) — %s (Method 1)', row, col, cond_label), ...
    'Interpreter', 'none');
legend(ax, [h_band, h_trace, h_supra], ...
    {sprintf('baseline \\pm%g%s', n_std, sigma_char), 'dF/F(t)', 'suprathreshold'}, ...
    'Location', 'best', 'Box', 'off');
grid(ax, 'on'); box(ax, 'on');

fig_fname = sprintf('dff_t_pixel_r%d_c%d_%s_m1.png', row, col, cond_label);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('  Saved figure: %s\n', fig_fname);
end

function V1_mask = load_v1_mask(fpath, expected_size)
V1_mask = [];
try
    D = load(fpath);
    if isfield(D, 'retino_align') && isfield(D.retino_align, 'V1_mask_stim')
        V1_mask = logical(D.retino_align.V1_mask_stim);
    elseif isfield(D, 'day_setup') && isfield(D.day_setup, 'retino_align')
        V1_mask = logical(D.day_setup.retino_align.V1_mask_stim);
    end
    if ~isempty(expected_size) && ~isempty(V1_mask) && ~isequal(size(V1_mask), expected_size)
        warning('V1_mask size mismatch — overlay skipped.');
        V1_mask = [];
    end
catch ME
    warning('Could not load V1 boundary: %s', ME.message);
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
