function run_consensus_window_m1_batch(cond_dir, save_dir, n_std_list, min_trials_list, ...
    v1_source_file, export_video, window_s)
% run_consensus_window_m1_batch  Headless batch version of step 9_D
% (consensus_region_window_method1_9D): the TIME-WINDOW variant of 9_C.
%
% Per-trial baseline-corrected, per-timepoint cross-trial SIGNED consensus for
% one channel-current condition, for every (n_std x min_trials) combination,
% with no UI dialogs or interactive viewer.
%
% Activation is directional AND time-windowed:
%   activated  at t  <=>  corrected >  n_std*sigma_pre  somewhere in [t-w, t+w]
%   suppressed at t  <=>  corrected < -n_std*sigma_pre  somewhere in [t-w, t+w]
% where w = window_s (default 0.1 s). This absorbs small trial-to-trial latency
% offsets. A pixel is consensus-active at t iff it is activated in >= min_trials
% trials OR suppressed in >= min_trials trials (one direction only). Display
% uses the signed net count (activated - suppressed) on a blue-white-red scale.
%
% Usage:
%   run_consensus_window_m1_batch(cond_dir, save_dir, n_std_list, min_trials_list)
%   run_consensus_window_m1_batch(..., v1_source_file)
%   run_consensus_window_m1_batch(..., v1_source_file, export_video)
%   run_consensus_window_m1_batch(..., v1_source_file, export_video, window_s)
%
% Arguments:
%   cond_dir         folder of per-trial Method 1 movies from step 5_B2
%   save_dir         output folder (created if absent)
%   n_std_list       row vector of significance multipliers, e.g. [1 2 3]
%   min_trials_list  row vector of consensus counts, e.g. [25 27 30]
%   v1_source_file   optional path to a day_setup .mat whose V1 boundary is
%                    overlaid (whole-brain result; V1 not cropped). '' = none.
%   export_video     optional logical, default false
%   window_s         optional time-window half-width in seconds, default 0.1
%
% The per-trial pass is run once per n_std and reused across all min_trials.

if nargin < 5, v1_source_file = ''; end
if nargin < 6, export_video    = false; end
if nargin < 7 || isempty(window_s), window_s = 0.1; end

mask_color_outside  = [0.15 0.15 0.15];
brain_outline_color = [0.85 0.85 0.85];
v1_outline_color    = [0.10 0.85 0.30];
frame_grid_tmin     = -0.2;     % frame-grid display window (s)
frame_grid_tmax     =  1.2;
video_frame_rate_fps = 10;
video_quality        = 95;
sigma_char           = char(963);

%% -------------------------
% COLLECT PER-TRIAL FILES
% -------------------------
assert(isfolder(cond_dir), 'Condition folder not found:\n  %s', cond_dir);
files = [dir(fullfile(cond_dir, 'dff_m1_*_trial*.mat')); ...
         dir(fullfile(cond_dir, 'v1_dff_m1_*_trial*.mat'))];
assert(~isempty(files), 'No per-trial movies found in:\n  %s', cond_dir);

nums = nan(numel(files), 1);
for i = 1:numel(files)
    tok = regexp(files(i).name, 'trial(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok), nums(i) = str2double(tok{1}); end
end
[~, ord] = sort(nums);
files    = files(ord);
n_files  = numel(files);

[~, folder_name] = fileparts(cond_dir);
tok = regexp(files(1).name, '(ch\d+_[\d.]+uA)', 'tokens', 'once');
if ~isempty(tok), cond_label = tok{1}; else, cond_label = folder_name; end
fprintf('Condition %s : %d per-trial movies\n', cond_label, n_files);

if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% GEOMETRY / TIME AXIS FROM FIRST TRIAL
% -------------------------
S0 = load(fullfile(cond_dir, files(1).name), 'dff_movie', 't_s');
t_s        = double(S0.t_s(:)');
[H, W, T]  = size(S0.dff_movie);
assert(numel(t_s) == T, 't_s length (%d) ~= frame count (%d).', numel(t_s), T);

prestim_idx = t_s < 0;
post_idx    = t_s >= 0;
assert(any(prestim_idx) && any(post_idx), 'Movie needs both pre- and post-stim frames.');
always_nan_mask = all(isnan(S0.dff_movie), 3);

%% -------------------------
% OPTIONAL V1 OVERLAY
% -------------------------
V1_mask = [];
if ~isempty(v1_source_file)
    V1_mask = get_v1_boundary(v1_source_file, [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary overlay: %s\n', v1_source_file); end
end

%% -------------------------
% FRAME-GRID DISPLAY INDICES (shared)
% -------------------------
display_frame_idx = find(t_s >= frame_grid_tmin & t_s <= frame_grid_tmax);
if isempty(display_frame_idx)
    [~, display_frame_idx] = min(abs(t_s - 0));
end
cmap = rainbow_colormap(256);   % jet over signed net count: blue=suppressed, green=neutral, red=activated
post_frames = find(post_idx);

% Time-window half-width in frames.
dt            = median(diff(t_s));
window_frames = max(1, round(window_s / dt));

fprintf('n_std levels: %s | min_trials levels: %s | window +/-%gs (+/-%d frame)\n', ...
    num2str(n_std_list), num2str(min_trials_list), window_s, window_frames);

%% -------------------------
% LOOP OVER n_std  (per-trial pass once per n_std)
% -------------------------
for ni = 1:numel(n_std_list)
    n_std = n_std_list(ni);
    fprintf('\n=== n_std = %g : per-trial pass ===\n', n_std);

    count_activated  = zeros(H, W, T);
    count_suppressed = zeros(H, W, T);
    n_used = 0;
    for k = 1:n_files
        Sk  = load(fullfile(cond_dir, files(k).name), 'dff_movie');
        dff = Sk.dff_movie;
        if ~isequal(size(dff), [H W T])
            warning('  %s wrong size — skipped.', files(k).name);
            continue;
        end
        base = mean(dff(:, :, prestim_idx), 3, 'omitnan');
        spre = std( dff(:, :, prestim_idx), 0, 3, 'omitnan');
        thr  = n_std * spre;
        corrected = dff - base;
        act = corrected >  thr;     % NaN -> false
        sup = corrected < -thr;
        % Temporal window: activated/suppressed at t if threshold crossed
        % anywhere in [t-window_frames, t+window_frames].
        act = movmax(uint8(act), [window_frames window_frames], 3) > 0;
        sup = movmax(uint8(sup), [window_frames window_frames], 3) > 0;
        count_activated  = count_activated  + act;
        count_suppressed = count_suppressed + sup;
        n_used = n_used + 1;
    end
    assert(n_used > 0, 'No usable trials for n_std=%g.', n_std);

    net_count = count_activated - count_suppressed;

    if n_std == round(n_std)
        n_std_label = sprintf('%d%s', n_std, sigma_char);
    else
        n_std_label = sprintf('%g%s', n_std, sigma_char);
    end

    % --- sweep min_trials (cheap: re-threshold the counts) -------------
    for mi = 1:numel(min_trials_list)
        min_trials = round(min_trials_list(mi));
        if min_trials < 1,      min_trials = 1;      end
        if min_trials > n_used, min_trials = n_used; end

        consensus = (count_activated >= min_trials) | (count_suppressed >= min_trials);

        max_act = max(count_activated(:,  :, post_frames), [], 3);
        max_sup = max(count_suppressed(:, :, post_frames), [], 3);
        is_act  = (max_act >= min_trials) & (max_act >= max_sup);
        is_sup  = (max_sup >= min_trials) & (max_sup >  max_act);

        region_mask = is_act | is_sup;
        region_mask(always_nan_mask) = false;
        region_signed = zeros(H, W);
        region_signed(is_act) =  max_act(is_act);
        region_signed(is_sup) = -max_sup(is_sup);
        region_signed(always_nan_mask) = 0;

        cons_counts        = squeeze(sum(sum(consensus(:, :, post_frames), 1), 2));
        [peak_n, pk_local] = max(cons_counts);
        peak_idx           = post_frames(pk_local);

        n_region = sum(region_mask(:));
        n_act    = sum(is_act(:) & ~always_nan_mask(:));
        n_sup    = sum(is_sup(:) & ~always_nan_mask(:));

        out_tag = sprintf('%s_%s_min%dof%d_win%gs_m1', cond_label, n_std_label, min_trials, n_used, window_s);
        fprintf('  min_trials=%d -> region %d px (up %d, down %d), peak %d px @ t=%+.2f s\n', ...
            min_trials, n_region, n_act, n_sup, peak_n, t_s(peak_idx));

        % --- save mat ---
        count_activated_u16  = uint16(count_activated);
        count_suppressed_u16 = uint16(count_suppressed);
        save(fullfile(save_dir, sprintf('consensus_%s.mat', out_tag)), ...
            'count_activated_u16', 'count_suppressed_u16', 'consensus', ...
            'region_mask', 'region_signed', 'always_nan_mask', ...
            'n_std', 'min_trials', 'n_used', 't_s', 'cond_label', 'peak_idx', ...
            'V1_mask', '-v7.3');

        % --- frame grid (windowed, signed) ---
        save_frame_grid(fullfile(save_dir, sprintf('consensus_%s_frame_grid.png', out_tag)), ...
            net_count, consensus, always_nan_mask, V1_mask, t_s, display_frame_idx, ...
            n_used, min_trials, n_std, sigma_char, cond_label, cmap, mask_color_outside, ...
            brain_outline_color, v1_outline_color, frame_grid_tmin, frame_grid_tmax);

        % --- region + peak figure (signed) ---
        save_region_fig(fullfile(save_dir, sprintf('consensus_%s_region.png', out_tag)), ...
            net_count, consensus, region_signed, region_mask, always_nan_mask, V1_mask, t_s, peak_idx, ...
            peak_n, n_region, n_act, n_sup, n_used, min_trials, n_std, sigma_char, cond_label, ...
            cmap, mask_color_outside, brain_outline_color, v1_outline_color);

        % --- text summary ---
        fid = fopen(fullfile(save_dir, sprintf('consensus_%s_summary.txt', out_tag)), 'w');
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

        % --- optional video ---
        if export_video
            write_signed_video(fullfile(save_dir, sprintf('consensus_%s.mp4', out_tag)), ...
                net_count, consensus, always_nan_mask, V1_mask, t_s, n_used, min_trials, ...
                cond_label, cmap, mask_color_outside, brain_outline_color, v1_outline_color, ...
                video_frame_rate_fps, video_quality);
        end
    end
end

fprintf('\nDone. All outputs in:\n  %s\n', save_dir);
end

%% =========================
% LOCAL FUNCTIONS
%% =========================

function save_frame_grid(out_png, net_count, consensus, always_nan_mask, V1_mask, t_s, ...
    display_frame_idx, n_used, min_trials, n_std, sigma_char, cond_label, cmap, ...
    color_outside, brain_color, v1_color, tmin, tmax)
n_display = numel(display_frame_idx);
n_cols = 5; n_rows = ceil(n_display / n_cols);   % requested 3 x 5 layout (15 frames)

fig = figure('Color', 'w', 'Visible', 'off', ...
    'Position', [50 50  min(1800, 240 * n_cols)  240 * n_rows + 80]);
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');
last_ax = [];
for di = 1:n_display
    fi = display_frame_idx(di);
    ax = nexttile(tl);
    image(ax, net_count_to_rgb(net_count(:, :, fi), always_nan_mask, n_used, cmap, color_outside));
    axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
    overlay_outlines(ax, always_nan_mask, consensus(:, :, fi), V1_mask, brain_color, v1_color);
    title(ax, sprintf('t = %+.2f s', t_s(fi)), 'FontSize', 8);
    last_ax = ax;
end
if ~isempty(last_ax)
    colormap(last_ax, cmap); clim(last_ax, [-n_used n_used]);
    cb = colorbar(last_ax); cb.Label.String = 'net consensus (activated - suppressed)';
end
title(tl, sprintf(['Signed consensus net-count (t in [%.2f, %.2f] s)  |  %s  |  >= %d of %d  |  %g%s' ...
    '   (red = activated, blue = suppressed)'], ...
    tmin, tmax, cond_label, min_trials, n_used, n_std, sigma_char), 'Interpreter', 'none', 'FontSize', 11);
exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
end

function save_region_fig(out_png, net_count, consensus, region_signed, region_mask, always_nan_mask, V1_mask, ...
    t_s, peak_idx, peak_n, n_region, n_act, n_sup, n_used, min_trials, n_std, sigma_char, ...
    cond_label, cmap, color_outside, brain_color, v1_color)
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [60 60 1200 540]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
image(ax1, net_count_to_rgb(region_signed, always_nan_mask, n_used, cmap, color_outside));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
overlay_outlines(ax1, always_nan_mask, region_mask, V1_mask, brain_color, v1_color);
colormap(ax1, cmap); clim(ax1, [-n_used n_used]);
title(ax1, sprintf('Stimulation-related region (%d px: %d up, %d down)', n_region, n_act, n_sup), ...
    'FontSize', 11);

ax2 = nexttile(tl);
image(ax2, net_count_to_rgb(net_count(:, :, peak_idx), always_nan_mask, n_used, cmap, color_outside));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
overlay_outlines(ax2, always_nan_mask, consensus(:, :, peak_idx), V1_mask, brain_color, v1_color);
colormap(ax2, cmap); clim(ax2, [-n_used n_used]);
cb = colorbar(ax2); cb.Label.String = 'net consensus';
title(ax2, sprintf('Peak consensus | t = %+.2f s | %d px', t_s(peak_idx), peak_n), 'FontSize', 11);

title(tl, sprintf('%s  |  consensus >= %d of %d trials  |  %g%s  (red = activated, blue = suppressed)', ...
    cond_label, min_trials, n_used, n_std, sigma_char), 'Interpreter', 'none', 'FontSize', 12);
exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
end

function rgb = net_count_to_rgb(net_frame, always_nan_mask, n_max, cmap, color_outside)
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
target_fra