%% consensus_region_method1_9C.m
% Step 9_C: Per-trial baseline-corrected, cross-trial CONSENSUS thresholding
%           of Method 1 dF/F (whole-brain), producing a per-timepoint
%           SIGNED consensus map and a stimulation-related region for one
%           channel-current condition.
%
% This is the per-trial counterpart of steps 9_A / 9_B. Those steps threshold
% a single (often trial-averaged) movie. Step 9_C instead analyses every
% trial of a condition individually and asks, at each timepoint, how many
% trials agree that a pixel is driven UP (activated) or DOWN (suppressed).
%
% Definitions (Method 1 — F_global normalisation, from steps 5_B1/5_B2):
%
%   dF/F(x,y,t)        = [F(x,y,t) - F_global(x,y)] / F_global(x,y)
%   baseline_dF/F(x,y) = mean over the trial's own pre-stim frames (t_s < 0)
%   sigma_pre(x,y)     = std of that trial's pre-stim dF/F(x,y,t)
%   corrected(x,y,t)   = dF/F(x,y,t) - baseline_dF/F(x,y)
%
%   A pixel is ACTIVATED in a trial at time t  <=>  corrected >  n_std*sigma_pre
%   A pixel is SUPPRESSED in a trial at time t  <=>  corrected < -n_std*sigma_pre
%
% These are treated as DIFFERENT events: a pixel that is activated in some
% trials and suppressed in others is unreliable noise, not a real response.
%
% Consensus (per timepoint):
%   count_activated(x,y,t)  = # trials with the pixel activated  at t
%   count_suppressed(x,y,t) = # trials with the pixel suppressed at t
%   A pixel is CONSENSUS-ACTIVE at t iff
%        count_activated(x,y,t)  >= min_trials   (consensus-activated)   OR
%        count_suppressed(x,y,t) >= min_trials   (consensus-suppressed)
%   i.e. it must agree in ONE direction in at least min_trials of the N trials
%   (e.g. 25 of 30). A 15-up / 15-down split is NOT consensus.
%
%   net_count(x,y,t) = count_activated - count_suppressed   (signed, -N..+N)
%   is used for display: deep red = strongly/consistently activated,
%   light red = weakly activated, white/grey = balanced or no signal,
%   light blue = weakly suppressed, deep blue = strongly suppressed.
%
%   stimulation-related region = pixels reaching consensus (in either single
%   direction) at one or more POST-stim timepoints (t_s >= 0).
%
% Input: a condition folder of per-trial Method 1 movies from step 5_B2,
%        i.e. dff_m1_ch{N}_{I}uA_trial{K}.mat (each contains dff_movie and t_s).
%
% Outputs (written into the chosen output folder):
%   consensus_<cond>_<n>sigma_min<M>of<N>_m1.mat
%       count_activated_u16, count_suppressed_u16  H x W x T  uint16
%       consensus      H x W x T  logical   (activated OR suppressed consensus)
%       region_mask    H x W      logical   any post-stim consensus
%       region_signed  H x W      double    signed peak consensus (red/blue)
%       n_std, min_trials, n_used, t_s, always_nan_mask, V1_mask, peak_idx
%   consensus_<cond>_..._frame_grid.png   signed net-count map, t in [-0.2, 0.12] s
%   consensus_<cond>_..._region.png       region + peak signed map
%   consensus_<cond>_..._summary.txt
%   consensus_<cond>_..._m1.mp4           (optional)

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside  = [0.15 0.15 0.15];  % out-of-brain (always-NaN) pixels
brain_outline_color = [0.85 0.85 0.85];
v1_outline_color    = [0.10 0.85 0.30];  % V1 boundary overlay (green)

% Frame-grid display window (seconds) — only frames in [tmin, tmax] are shown.
frame_grid_tmin = -0.2;
frame_grid_tmax =  1.2;

video_frame_rate_fps = 10;
video_quality        = 95;

%% -------------------------
% SELECT CONDITION FOLDER (per-trial movies from step 5_B2)
% -------------------------
cond_dir = uigetdir(pwd, ...
    'Select a condition folder of per-trial Method 1 movies (e.g. method1/ch16_7uA)');
if isequal(cond_dir, 0), error('No folder selected.'); end

trial_files = list_trial_files(cond_dir);
assert(~isempty(trial_files), ...
    'No per-trial movies (dff_m1_*_trial*.mat / v1_dff_m1_*_trial*.mat) found in:\n  %s', cond_dir);

n_files = numel(trial_files);
fprintf('Found %d per-trial movie(s) in:\n  %s\n', n_files, cond_dir);

[~, folder_name] = fileparts(cond_dir);
tok = regexp(trial_files(1).name, '(ch\d+_[\d.]+uA)', 'tokens', 'once');
if ~isempty(tok), cond_label = tok{1}; else, cond_label = folder_name; end

%% -------------------------
% LOAD FIRST TRIAL FOR GEOMETRY / TIME AXIS
% -------------------------
S0 = load(fullfile(cond_dir, trial_files(1).name), 'dff_movie', 't_s');
assert(isfield(S0, 'dff_movie') && isfield(S0, 't_s'), ...
    'Trial file must contain dff_movie and t_s: %s', trial_files(1).name);

t_s        = double(S0.t_s(:)');
[H, W, T]  = size(S0.dff_movie);
assert(numel(t_s) == T, 't_s length (%d) ~= frame count (%d).', numel(t_s), T);

prestim_idx = t_s < 0;
post_idx    = t_s >= 0;
assert(any(prestim_idx), 'No pre-stim frames (t_s < 0) in these movies.');
assert(any(post_idx),    'No post-stim frames (t_s >= 0) in these movies.');

always_nan_mask = all(isnan(S0.dff_movie), 3);   % H x W (out-of-brain)
fprintf('Geometry: %d x %d x %d frames | t = %+.2f .. %+.2f s | in-brain pixels: %d\n', ...
    H, W, T, t_s(1), t_s(end), sum(~always_nan_mask(:)));

%% -------------------------
% PROMPT: n_std AND min_trials
% -------------------------
default_n_std     = 3;
default_min_trial = min(25, n_files);
sigma_char        = char(963);

answer = inputdlg( ...
    {sprintf(['Significance multiplier n_std\n' ...
              '(threshold = n_std %s pre-stim std of each trial):'], sigma_char), ...
     sprintf(['Minimum number of trials that must agree IN ONE DIRECTION\n' ...
              '(consensus count). A pixel is consensus-active at time t if it\n' ...
              'is activated in >= this many trials, OR suppressed in >= this\n' ...
              'many of the %d trials (e.g. 25 of 30):'], n_files)}, ...
    'Step 9_C: consensus settings', [1 64; 1 64], ...
    {num2str(default_n_std), num2str(default_min_trial)});
if isempty(answer), error('Cancelled.'); end

n_std      = str2double(answer{1});
min_trials = round(str2double(answer{2}));
assert(isfinite(n_std) && n_std > 0,           'n_std must be a positive number.');
assert(isfinite(min_trials) && min_trials >= 1, 'min_trials must be >= 1.');
if min_trials > n_files
    warning('min_trials (%d) > number of trials (%d); clamping to %d.', ...
        min_trials, n_files, n_files);
    min_trials = n_files;
end

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY
% (whole-brain result; V1 drawn only as a contour, never used to crop)
% -------------------------
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select a day_setup with a V1 boundary to overlay (Cancel = none)');
if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = get_v1_boundary(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary overlay loaded from: %s\n', v1_fn); end
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(cond_dir, 'Select output folder for consensus results');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

if n_std == round(n_std)
    n_std_label = sprintf('%d%s', n_std, sigma_char);
else
    n_std_label = sprintf('%g%s', n_std, sigma_char);
end
out_tag = sprintf('%s_%s_min%dof%d_m1', cond_label, n_std_label, min_trials, n_files);

%% -------------------------
% PER-TRIAL PASS -> count_activated / count_suppressed
% -------------------------
count_activated  = zeros(H, W, T);   % # trials with pixel driven UP at (x,y,t)
count_suppressed = zeros(H, W, T);   % # trials with pixel driven DOWN at (x,y,t)
n_used = 0;
fprintf('\nAnalysing %d trials one by one...\n', n_files);

for k = 1:n_files
    Sk  = load(fullfile(cond_dir, trial_files(k).name), 'dff_movie');
    dff = Sk.dff_movie;
    if ~isequal(size(dff), [H W T])
        warning('Trial %s has size %s, expected %dx%dx%d — skipped.', ...
            trial_files(k).name, mat2str(size(dff)), H, W, T);
        continue;
    end

    base = mean(dff(:, :, prestim_idx), 3, 'omitnan');   % H x W baseline dF/F
    spre = std( dff(:, :, prestim_idx), 0, 3, 'omitnan'); % H x W pre-stim std
    thr  = n_std * spre;                                  % H x W

    corrected = dff - base;                 % implicit expansion over T
    act = corrected >  thr;                 % activated  (NaN -> false)
    sup = corrected < -thr;                 % suppressed (NaN -> false)

    count_activated  = count_activated  + act;
    count_suppressed = count_suppressed + sup;
    n_used = n_used + 1;

    if mod(k, 5) == 0 || k == n_files
        fprintf('  %d / %d trials processed\n', k, n_files);
    end
end
assert(n_used > 0, 'No usable trials.');

if min_trials > n_used
    warning('min_trials (%d) > usable trials (%d); clamping.', min_trials, n_used);
    min_trials = n_used;
end

% Signed display value and single-direction consensus.
net_count       = count_activated - count_suppressed;            % H x W x T, signed
consensus_act   = count_activated  >= min_trials;                % logical
consensus_sup   = count_suppressed >= min_trials;                % logical
consensus       = consensus_act | consensus_sup;                 % either direction

%% -------------------------
% STIMULATION-RELATED REGION + DIRECTION + PEAK TIMEPOINT (post-stim)
% -------------------------
post_frames = find(post_idx);
max_act = max(count_activated(:,  :, post_frames), [], 3);   % H x W
max_sup = max(count_suppressed(:, :, post_frames), [], 3);   % H x W

is_act_region = (max_act >= min_trials) & (max_act >= max_sup);
is_sup_region = (max_sup >= min_trials) & (max_sup >  max_act);

region_mask = is_act_region | is_sup_region;
region_mask(always_nan_mask) = false;

region_signed = zeros(H, W);                  % signed peak consensus for display
region_signed(is_act_region) =  max_act(is_act_region);
region_signed(is_sup_region) = -max_sup(is_sup_region);
region_signed(always_nan_mask) = 0;

cons_counts        = squeeze(sum(sum(consensus(:, :, post_frames), 1), 2));
[peak_n, pk_local] = max(cons_counts);
peak_idx           = post_frames(pk_local);

n_region = sum(region_mask(:));
n_act    = sum(is_act_region(:) & ~always_nan_mask(:));
n_sup    = sum(is_sup_region(:) & ~always_nan_mask(:));
fprintf('\nConsensus (>= %d of %d trials, single direction):\n', min_trials, n_used);
fprintf('  Region: %d px  (activated %d, suppressed %d)\n', n_region, n_act, n_sup);
fprintf('  Peak consensus at t = %+.2f s  (%d consensus pixels)\n', t_s(peak_idx), peak_n);

%% -------------------------
% SAVE .MAT
% -------------------------
count_activated_u16  = uint16(count_activated);
count_suppressed_u16 = uint16(count_suppressed);
mat_fname = sprintf('consensus_%s.mat', out_tag);
save(fullfile(save_dir, mat_fname), ...
    'count_activated_u16', 'count_suppressed_u16', 'consensus', ...
    'region_mask', 'region_signed', 'always_nan_mask', ...
    'n_std', 'min_trials', 'n_used', 't_s', 'cond_label', 'peak_idx', ...
    'V1_mask', '-v7.3');
fprintf('Saved: %s\n', mat_fname);

%% -------------------------
% COLORMAP (rainbow/jet over signed net count):
%   blue = suppressed, green = none/balanced, red = activated.
% -------------------------
cmap = rainbow_colormap(256);

%% -------------------------
% FRAME-GRID FIGURE (signed net-count, frames in [tmin, tmax])
% -------------------------
display_frame_idx = find(t_s >= frame_grid_tmin & t_s <= frame_grid_tmax);
if isempty(display_frame_idx)
    [~, nearest] = min(abs(t_s - 0));
    display_frame_idx = nearest;
    warning('No frames in [%.2f, %.2f] s; showing nearest frame to 0.', ...
        frame_grid_tmin, frame_grid_tmax);
end

n_display = numel(display_frame_idx);
n_cols    = 5;                              % requested 3 x 5 layout (15 frames)
n_rows    = ceil(n_display / n_cols);

fig = figure('Color', 'w', 'Name', sprintf('Signed consensus %s', cond_label), ...
    'Position', [50 50  min(1800, 240 * n_cols)  240 * n_rows + 80]);
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');

last_ax = [];
for di = 1:n_display
    fi = display_frame_idx(di);
    ax = nexttile(tl);
    image(ax, net_count_to_rgb(net_count(:, :, fi), always_nan_mask, n_used, cmap, mask_color_outside));
    axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
    overlay_outlines(ax, always_nan_mask, consensus(:, :, fi), V1_mask, brain_outline_color, v1_outline_color);
    title(ax, sprintf('t = %+.2f s', t_s(fi)), 'FontSize', 8);
    last_ax = ax;
end
if ~isempty(last_ax)
    colormap(last_ax, cmap); clim(last_ax, [-n_used n_used]);
    cb = colorbar(last_ax); cb.Label.String = 'net consensus (activated - suppressed)';
end
title(tl, sprintf(['Signed consensus net-count  |  %s  |  >= %d of %d trials  |  %g%s' ...
    '   (red = activated, blue = suppressed)'], ...
    cond_label, min_trials, n_used, n_std, sigma_char), 'Interpreter', 'none', 'FontSize', 11);

frame_grid_fname = sprintf('consensus_%s_frame_grid.png', out_tag);
exportgraphics(fig, fullfile(save_dir, frame_grid_fname), 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', frame_grid_fname);

%% -------------------------
% REGION + PEAK FIGURE (both signed red/blue)
% -------------------------
fig = figure('Color', 'w', 'Name', sprintf('Region %s', cond_label), ...
    'Position', [60 60 1200 540]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
image(ax1, net_count_to_rgb(region_signed, always_nan_mask, n_used, cmap, mask_color_outside));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
overlay_outlines(ax1, always_nan_mask, region_mask, V1_mask, brain_outline_color, v1_outline_color);
colormap(ax1, cmap); clim(ax1, [-n_used n_used]);
title(ax1, sprintf('Stimulation-related region (%d px: %d up, %d down)', n_region, n_act, n_sup), ...
    'FontSize', 11);

ax2 = nexttile(tl);
image(ax2, net_count_to_rgb(net_count(:, :, peak_idx), always_nan_mask, n_used, cmap, mask_color_outside));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
overlay_outlines(ax2, always_nan_mask, consensus(:, :, peak_idx), V1_mask, brain_outline_color, v1_outline_color);
colormap(ax2, cmap); clim(ax2, [-n_used n_used]);
cb = colorbar(ax2); cb.Label.String = 'net consensus';
title(ax2, sprintf('Peak consensus | t = %+.2f s | %d px', t_s(peak_idx), peak_n), 'FontSize', 11);

title(tl, sprintf('%s  |  consensus >= %d of %d trials  |  %g%s  (red = activated, blue = suppressed)', ...
    cond_label, min_trials, n_used, n_std, sigma_char), 'Interpreter', 'none', 'FontSize', 12);

region_fname = sprintf('consensus_%s_region.png', out_tag);
exportgraphics(fig, fullfile(save_dir, region_fname), 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', region_fname);

%% -------------------------
% TEXT SUMMARY
% -------------------------
summary_fname = sprintf('consensus_%s_summary.txt', out_tag);
fid = fopen(fullfile(save_dir, summary_fname), 'w');
fprintf(fid, 'Step 9_C consensus summary (signed: activated vs suppressed)\n');
fprintf(fid, 'Condition          : %s\n', cond_label);
fprintf(fid, 'Trials used        : %d\n', n_used);
fprintf(fid, 'n_std              : %g\n', n_std);
fprintf(fid, 'min_trials (cons.) : %d (single direction)\n', min_trials);
fprintf(fid, 'Time window        : %+.2f to %+.2f s (%d frames)\n', t_s(1), t_s(end), T);
fprintf(fid, 'Frame-grid window  : %+.2f to %+.2f s\n', frame_grid_tmin, frame_grid_tmax);
fprintf(fid, 'Region pixels      : %d (activated %d, suppressed %d)\n', n_region, n_act, n_sup);
fprintf(fid, 'Peak consensus time: %+.2f s\n', t_s(peak_idx));
fprintf(fid, 'Peak consensus px  : %d\n', peak_n);
if isempty(V1_mask), v1s = 'no'; else, v1s = 'yes'; end
fprintf(fid, 'V1 overlay         : %s\n', v1s);
fclose(fid);
fprintf('Saved: %s\n', summary_fname);

%% -------------------------
% OPTIONAL VIDEO OF THE SIGNED CONSENSUS MOVIE
% -------------------------
export_choice = questdlg( ...
    sprintf('Export the signed consensus movie for "%s" as an MP4 video?', cond_label), ...
    'Export consensus video?', 'Export video', 'Skip', 'Skip');
if strcmp(export_choice, 'Export video')
    video_fpath = fullfile(save_dir, sprintf('consensus_%s.mp4', out_tag));
    write_signed_video(video_fpath, net_count, consensus, always_nan_mask, V1_mask, ...
        t_s, n_used, min_trials, cond_label, cmap, mask_color_outside, ...
        brain_outline_color, v1_outline_color, video_frame_rate_fps, video_quality);
    fprintf('Saved video: consensus_%s.mp4\n', out_tag);
end

%% -------------------------
% INTERACTIVE VIEWER + PIXEL PICKING
% -------------------------
picked = pick_pixels_interactively(net_count, consensus, always_nan_mask, V1_mask, ...
    t_s, peak_idx, n_used, min_trials, cond_label, cmap, mask_color_outside, ...
    brain_outline_color, v1_outline_color);

if isempty(picked)
    fprintf('\nNo pixels picked.\n');
else
    fprintf('\nGenerating activated/suppressed timecourse figures for %d pixel(s)...\n', size(picked,1));
    for pi = 1:size(picked, 1)
        r = picked(pi, 1); c = picked(pi, 2);
        plot_pixel_timecourse(squeeze(count_activated(r, c, :)), squeeze(count_suppressed(r, c, :)), ...
            t_s, min_trials, n_used, r, c, cond_label, save_dir);
    end
end

fprintf('\nDone.\nAll outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function files = list_trial_files(cond_dir)
files = [dir(fullfile(cond_dir, 'dff_m1_*_trial*.mat')); ...
         dir(fullfile(cond_dir, 'v1_dff_m1_*_trial*.mat'))];
if isempty(files), return; end
nums = nan(numel(files), 1);
for i = 1:numel(files)
    tok = regexp(files(i).name, 'trial(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok), nums(i) = str2double(tok{1}); end
end
[~, ord] = sort(nums);
files = files(ord);
end

function rgb = net_count_to_rgb(net_frame, always_nan_mask, n_max, cmap, color_outside)
% Map a signed net-count frame in [-n_max, n_max] to a blue-white-red RGB.
% 0 -> white (no/balanced consensus), +n_max -> deep red (activated),
% -n_max -> deep blue (suppressed). Out-of-brain -> solid color_outside.
n = size(cmap, 1);
if n_max <= 0, n_max = 1; end
scaled = (double(net_frame) + n_max) / (2 * n_max);   % [-n_max,n_max] -> [0,1]
scaled(~isfinite(scaled)) = 0.5;
idx = uint16(min(max(round(scaled * (n - 1)), 0), n - 1)) + 1;
rgb = ind2rgb(idx, cmap);
for c = 1:3
    chan = rgb(:, :, c);
    chan(always_nan_mask) = color_outside(c);
    rgb(:, :, c) = chan;
end
end

function overlay_outlines(ax, always_nan_mask, consensus_frame, V1_mask, brain_color, v1_color)
% Brain boundary (always) + magenta consensus contour (if consensus_frame
% given and non-empty) + optional V1 boundary.
consensus_color = [1.00 0.10 0.80];   % magenta consensus contour
if any(~always_nan_mask(:))
    visboundaries(ax, ~always_nan_mask, 'Color', brain_color, 'LineWidth', 0.6);
end
if ~isempty(consensus_frame) && any(consensus_frame(:))
    visboundaries(ax, consensus_frame, 'Color', consensus_color, 'LineWidth', 0.8);
end
if ~isempty(V1_mask) && any(V1_mask(:))
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
end

function write_signed_video(video_file, net_count, consensus, always_nan_mask, V1_mask, ...
    t_s, n_used, min_trials, cond_label, cmap, color_outside, brain_color, v1_color, frame_rate, quality)
[~, ~, n_frames] = size(net_count);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax  = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);
writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate; writer.Quality = quality;
open(writer);
img_handle = image(ax, net_count_to_rgb(net_count(:, :, 1), always_nan_mask, n_used, cmap, color_outside));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
title_handle = title(ax, '', 'Interpreter', 'none');
colormap(ax, cmap); clim(ax, [-n_used n_used]);
cb = colorbar(ax, 'eastoutside'); cb.Label.String = 'net consensus (act - sup)';
drawnow;
target_frame_size = [];
for k = 1:n_frames
    set(img_handle, 'CData', net_count_to_rgb(net_count(:, :, k), always_nan_mask, n_used, cmap, color_outside));
    delete(findobj(ax, 'Type', 'line'));
    overlay_outlines(ax, always_nan_mask, consensus(:, :, k), V1_mask, brain_color, v1_color);
    set(title_handle, 'String', sprintf('%s | t = %+.2f s | consensus(>=%d): %d px', ...
        cond_label, t_s(k), min_trials, sum(sum(consensus(:, :, k)))));
    drawnow;
    frame_rgb = frame2im(getframe(fig));
    if isempty(target_frame_size)
        target_frame_size = size(frame_rgb(:, :, 1));
    elseif ~isequal(size(frame_rgb, 1), target_frame_size(1)) || ...
            ~isequal(size(frame_rgb, 2), target_frame_size(2))
        frame_rgb = imresize(frame_rgb, target_frame_size);
    end
    writeVideo(writer, frame_rgb);
end
close(writer); close(fig);
end

function picked = pick_pixels_interactively(net_count, consensus, always_nan_mask, V1_mask, ...
    t_s, peak_idx, n_used, min_trials, cond_label, cmap, color_outside, brain_color, v1_color)
[H, W, T] = size(net_count);

fig = figure('Color', 'w', 'Name', sprintf('Pick pixels — %s (9_C)', cond_label), ...
    'Position', [60 60 1300 650]);

ax1 = subplot(1, 2, 1);
img1 = image(ax1, net_count_to_rgb(net_count(:, :, peak_idx), always_nan_mask, n_used, cmap, color_outside));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
colormap(ax1, cmap); clim(ax1, [-n_used n_used]);
title1 = title(ax1, '', 'Interpreter', 'none');
draw_signed_frame(img1, title1, ax1, net_count, consensus, always_nan_mask, V1_mask, t_s, ...
    n_used, min_trials, cond_label, cmap, color_outside, brain_color, v1_color, peak_idx);

uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.10 0.02 0.34 0.04], 'Min', 1, 'Max', T, 'Value', peak_idx, ...
    'SliderStep', [1 / (T - 1), 5 / (T - 1)], ...
    'Callback', @(src, ~) draw_signed_frame(img1, title1, ax1, net_count, consensus, ...
        always_nan_mask, V1_mask, t_s, n_used, min_trials, cond_label, cmap, color_outside, ...
        brain_color, v1_color, get(src, 'Value')));

ax2 = subplot(1, 2, 2);
image(ax2, net_count_to_rgb(net_count(:, :, peak_idx), always_nan_mask, n_used, cmap, color_outside));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
overlay_outlines(ax2, always_nan_mask, consensus(:, :, peak_idx), V1_mask, brain_color, v1_color);
colormap(ax2, cmap); clim(ax2, [-n_used n_used]);
title(ax2, sprintf('Peak consensus | %s | t = %+.2f s', cond_label, t_s(peak_idx)), ...
    'Interpreter', 'none');

sgtitle(fig, ['Click pixels to plot their activated/suppressed trial counts   |   ' ...
    'left-click: add   \cdot   right-click / ''u'': undo   \cdot   Enter: done']);

picked  = zeros(0, 2);
markers = gobjects(0, 1);
while true
    [x, y, button] = ginput(1);
    if isempty(button), break; end
    if button == 1
        ax = gca; r = round(y); c = round(x);
        if r < 1 || r > H || c < 1 || c > W, continue; end
        picked(end + 1, :) = [r, c];                                            %#ok<AGROW>
        markers(end + 1)   = plot(ax, c, r, 'k+', 'MarkerSize', 12, 'LineWidth', 1.6); %#ok<AGROW>
        fprintf('  Picked pixel (%d, %d)   [%d selected]\n', r, c, size(picked, 1));
    elseif button == 3 || button == double('u') || button == 8
        if ~isempty(picked)
            delete(markers(end)); markers(end, :) = []; picked(end, :) = [];
            fprintf('  Undid last pick   [%d remaining]\n', size(picked, 1));
        end
    elseif button == 13 || button == 27
        break;
    end
end
if isvalid(fig), close(fig); end
end

function draw_signed_frame(img_handle, title_handle, ax, net_count, consensus, ...
    always_nan_mask, V1_mask, t_s, n_used, min_trials, cond_label, cmap, color_outside, ...
    brain_color, v1_color, k)
[~, ~, T] = size(net_count);
k = max(1, min(T, round(k)));
set(img_handle, 'CData', net_count_to_rgb(net_count(:, :, k), always_nan_mask, n_used, cmap, color_outside));
delete(findobj(ax, 'Type', 'line'));
overlay_outlines(ax, always_nan_mask, consensus(:, :, k), V1_mask, brain_color, v1_color);
set(title_handle, 'String', sprintf('%s | t = %+.2f s | consensus(>=%d): %d px', ...
    cond_label, t_s(k), min_trials, sum(sum(consensus(:, :, k)))));
end

function plot_pixel_timecourse(act_trace, sup_trace, t_s, min_trials, n_used, row, col, cond_label, save_dir)
% Plot a pixel's activated count (up, red) and suppressed count (down, blue)
% over time, with +/- min_trials consensus lines.
fig = figure('Color', 'w', 'Position', [120 120 680 440]);
ax  = axes(fig); hold(ax, 'on');

area(ax, t_s,  act_trace, 'FaceColor', [0.85 0.20 0.15], 'EdgeColor', [0.6 0.1 0.1], ...
    'FaceAlpha', 0.55, 'LineWidth', 1.0);
area(ax, t_s, -sup_trace, 'FaceColor', [0.15 0.35 0.85], 'EdgeColor', [0.1 0.2 0.6], ...
    'FaceAlpha', 0.55, 'LineWidth', 1.0);
yline(ax,  min_trials, '--', sprintf('activated consensus = %d', min_trials), ...
    'Color', [0.6 0.1 0.1], 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
yline(ax, -min_trials, '--', sprintf('suppressed consensus = %d', min_trials), ...
    'Color', [0.1 0.2 0.6], 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
xline(ax, 0, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1);

ylim(ax, [-(n_used + 0.5)  (n_used + 0.5)]);
xlabel(ax, 'Time relative to stimulation onset (s)');
ylabel(ax, 'trials   (up = activated, down = suppressed)');
title(ax, sprintf('Activated/suppressed trial counts | pixel (%d,%d) | %s (9_C)', ...
    row, col, cond_label), 'Interpreter', 'none');
grid(ax, 'on'); box(ax, 'on');

fig_fname = sprintf('consensus_pixel_r%d_c%d_%s.png', row, col, cond_label);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('  Saved figure: %s\n', fig_fname);
end

function cmap = rainbow_colormap(n)
% Common rainbow (jet) colormap. Mapped over the signed net count [-N, N]:
% blue = suppressed, green = no/balanced consensus, red = activated. The
% rainbow sweep makes magnitude differences much easier to read than a
% single-hue (light-to-dark red) ramp.
if nargin < 1, n = 256; end
cmap = jet(n);
end
