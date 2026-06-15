function run_threshold_m0_batch(movie_file, save_dir, n_std_list, export_video)
% run_threshold_m0_batch  Headless batch version of dff_pixelwise_significance_threshold_9A.
%
% Threshold is derived from each movie's own pre-stim baseline (t_s < 0) --
% no external baseline file is required.  All file dialogs, the n_std
% inputdlg, and the interactive pixel-picker are removed.
%
% Usage:
%   run_threshold_m0_batch(movie_file, save_dir, n_std_list)
%   run_threshold_m0_batch(movie_file, save_dir, n_std_list, export_video)
%
% Arguments:
%   movie_file   path to dF/F movie .mat  (from step 5_A or its V1 counterpart)
%   save_dir     output folder (created if absent)
%   n_std_list   row vector of threshold multipliers, e.g. [1 2 3]
%   export_video logical, default false

if nargin < 4
    export_video = false;
end

video_frame_rate_fps = 10;
video_quality        = 95;
display_step_s       = 0.1;
n_prestim_display    = 9;
mask_color_outside   = [0.15 0.15 0.15];
mask_color_inactive  = [0.55 0.55 0.55];
sigma_char           = char(963);

%% -------------------------
% LOAD MOVIE (once)
% -------------------------
fprintf('Loading movie:\n  %s\n', movie_file);
assert(isfile(movie_file), 'Movie file not found:\n  %s', movie_file);

S = load(movie_file);
if isfield(S, 'dff_movie')
    movie = S.dff_movie;
elseif isfield(S, 'mean_dff_movie')
    movie = S.mean_dff_movie;
else
    error('Movie file must contain "dff_movie" or "mean_dff_movie".');
end
assert(isfield(S, 't_s'), 'Movie file is missing "t_s".');

t_s = double(S.t_s(:)');
[H, W, T] = size(movie);
assert(numel(t_s) == T, 't_s length (%d) does not match frame count (%d).', numel(t_s), T);

[~, base_name, ~] = fileparts(movie_file);
tok = regexp(base_name, '(ch\d+_[\d.]+uA(?:_trial\d+)?)', 'tokens', 'once');
if isempty(tok)
    cond_label = base_name;
else
    cond_label = tok{1};
end

fprintf('Condition: %s   (%d x %d x %d frames)\n', cond_label, H, W, T);

%% -------------------------
% PER-PIXEL BASELINE STD (computed once, reused for every n_std)
% -------------------------
baseline_idx = t_s < 0;
assert(any(baseline_idx), 'No pre-stim frames (t_s < 0) in this movie.');

always_nan_mask = all(isnan(movie), 3);
pixel_std       = std(movie(:, :, baseline_idx), 0, 3, 'omitnan');   % H x W

fprintf('Baseline frames: %d  |  In-mask pixels: %d / %d\n', ...
    sum(baseline_idx), sum(~always_nan_mask(:)), H * W);

%% -------------------------
% SHARED STATE
% -------------------------
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

finite_vals = movie(isfinite(movie));
if ~isempty(finite_vals)
    q           = quantile(finite_vals, [0.01 0.99]);
    clim_to_use = [-max(abs(q))  max(abs(q))];
else
    clim_to_use = [-0.02 0.02];
end
cmap = bwr_colormap();

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

post_idx = find(t_s >= 0);
assert(~isempty(post_idx), 'No post-stim frames (t_s >= 0) in this movie.');

%% -------------------------
% LOOP OVER n_std VALUES
% -------------------------
fprintf('\nRunning %d threshold level(s): %s\n', numel(n_std_list), ...
    strjoin(arrayfun(@num2str, n_std_list, 'UniformOutput', false), ', '));

for ni = 1:numel(n_std_list)

    n_std = n_std_list(ni);
    fprintf('\n=== n_std = %g ===\n', n_std);

    if n_std == round(n_std)
        n_std_label = sprintf('%d%s', n_std, sigma_char);
    else
        n_std_label = sprintf('%g%s', n_std, sigma_char);
    end
    out_tag = sprintf('%s_%s', base_name, n_std_label);

    % Threshold
    sig_threshold = n_std * pixel_std;               % H x W
    sig_mask      = abs(movie) > sig_threshold;       % H x W x T
    thresh_movie  = movie;
    thresh_movie(~sig_mask) = NaN;

    % Peak response timepoint
    sig_counts          = squeeze(sum(sum(sig_mask(:, :, post_idx), 1), 2));
    [~, peak_local_idx] = max(sig_counts);
    peak_idx            = post_idx(peak_local_idx);
    fprintf('  Peak at t = %+.2f s  (%d suprathreshold pixels)\n', ...
        t_s(peak_idx), sig_counts(peak_local_idx));

    % Save .mat
    thresh_fname = sprintf('thresh_%s.mat', out_tag);
    thresh_fpath = fullfile(save_dir, thresh_fname);
    save(thresh_fpath, 'thresh_movie', 'sig_mask', 'pixel_std', 'sig_threshold', 'n_std', ...
        'always_nan_mask', 't_s', '-v7.3');
    fprintf('  Saved: %s\n', thresh_fname);

    % Frame-grid figure
    fig = figure('Color', 'w', 'Visible', 'off', ...
        'Position', [50 50  min(1800, 240*n_cols)  240*n_rows + 70]);
    tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');

    last_ax = [];
    for di = 1:n_display
        fi = display_frame_idx(di);
        if fi < 1 || fi > T, continue; end
        ax = nexttile(tl);
        image(ax, thresh_frame_to_rgb(movie(:,:,fi), sig_mask(:,:,fi), always_nan_mask, ...
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

    title(tl, sprintf('Thresholded dF/F (|dF/F| > %g%s, Method 0)  |  %s', ...
        n_std, sigma_char, cond_label), 'Interpreter', 'none', 'FontSize', 11);

    frame_grid_fname = sprintf('thresh_%s_frame_grid.png', out_tag);
    exportgraphics(fig, fullfile(save_dir, frame_grid_fname), 'Resolution', 150);
    close(fig);
    fprintf('  Saved: %s\n', frame_grid_fname);

    % Optional video
    if export_video
        video_fpath = fullfile(save_dir, sprintf('thresh_%s.mp4', out_tag));
        write_thresh_video(video_fpath, movie, sig_mask, always_nan_mask, t_s, ...
            sprintf('%s | M0', cond_label), clim_to_use, cmap, ...
            mask_color_outside, mask_color_inactive, video_frame_rate_fps, video_quality);
        fprintf('  Saved video: thresh_%s.mp4\n', out_tag);
    end

end

fprintf('\nDone. All outputs in:\n  %s\n', save_dir);
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
    chan = rgb(:,:,c);
    chan(inactive_mask)   = color_inactive(c);
    chan(always_nan_mask) = color_outside(c);
    rgb(:,:,c) = chan;
end
end

function write_thresh_video(video_file, movie_stack, sig_mask, always_nan_mask, time_axis_sec, ...
    title_prefix, clim_range, cmap, color_outside, color_inactive, frame_rate, quality)
[~, ~, n_frames] = size(movie_stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax  = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);

writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate;
writer.Quality   = quality;
open(writer);

img_handle = image(ax, thresh_frame_to_rgb(movie_stack(:,:,1), sig_mask(:,:,1), ...
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
    set(img_handle, 'CData', thresh_frame_to_rgb(movie_stack(:,:,k), sig_mask(:,:,k), ...
        always_nan_mask, clim_range, cmap, color_outside, color_inactive));
    set(title_handle, 'String', sprintf('%s | t = %+.2f s | suprathreshold: %d', ...
        title_prefix, time_axis_sec(k), sum(sum(sig_mask(:,:,k)))));
    drawnow;
    frame_struct = getframe(fig);
    frame_rgb    = frame2im(frame_struct);
    if isempty(target_frame_size)
        target_frame_size = size(frame_rgb(:,:,1));
    elseif ~isequal(size(frame_rgb,1), target_frame_size(1)) || ...
            ~isequal(size(frame_rgb,2), target_frame_size(2))
        frame_rgb = imresize(frame_rgb, target_frame_size);
    end
    writeVideo(writer, frame_rgb);
end

close(writer);
close(fig);
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