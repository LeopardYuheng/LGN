%% consensus_7C2.m
% Step 7_C2: Count-threshold filter on 7_C consensus output.
%
% Loads a consensus .mat file from step 7_C (or 7_D) and applies a stricter
% per-frame display threshold: at each timepoint t, only pixels where
%
%   count_activated(x,y,t)  >= min_count_display
%   OR
%   count_suppressed(x,y,t) >= min_count_display
%
% are rendered with their net-count color; all other in-brain pixels are
% shown as inactive (medium gray).  The stimulation-related region is
% recomputed from this tighter threshold (same direction-preference logic
% as 7_C: is_act when max_act >= threshold AND max_act >= max_sup, etc.).
%
% This is a fast post-processing step — no per-trial movie loading.
%
% Requires:
%   - A consensus .mat file from step 7_C or 7_D
%     (must contain count_activated_u16, count_suppressed_u16,
%      always_nan_mask, n_std, min_trials, n_used, t_s, cond_label, V1_mask)
%
% Outputs (appended tag _c<K> where K = min_count_display):
%   consensus_<original_tag>_c<K>_frame_grid.png
%   consensus_<original_tag>_c<K>_region.png
%   consensus_<original_tag>_c<K>.mat

close all; clc; clear; fclose('all');

%% -------------------------
% LOAD 7_C / 7_D .mat FILE
% -------------------------
[mat_fn, mat_fp] = uigetfile('*.mat', ...
    'Select 7_C / 7_D consensus .mat file (consensus_*_m1.mat)');
if isequal(mat_fn, 0), error('No file selected.'); end

S = load(fullfile(mat_fp, mat_fn));

required = {'count_activated_u16', 'count_suppressed_u16', ...
            'always_nan_mask', 'n_used', 't_s', 'cond_label'};
for i = 1:numel(required)
    assert(isfield(S, required{i}), ...
        'Missing field "%s". Did you select a 7_C/7_D consensus .mat file?', required{i});
end

count_act = double(S.count_activated_u16);   % H x W x T
count_sup = double(S.count_suppressed_u16);  % H x W x T
always_nan_mask = logical(S.always_nan_mask);
n_used     = double(S.n_used);
t_s        = double(S.t_s(:)');
cond_label = char(S.cond_label);
n_std      = S.n_std;
min_trials = S.min_trials;

[H, W, T] = size(count_act);
assert(numel(t_s) == T, 't_s length does not match count array frame count.');

V1_mask = [];
if isfield(S, 'V1_mask') && ~isempty(S.V1_mask)
    V1_mask = logical(S.V1_mask);
end

fprintf('Loaded: %s\n', mat_fn);
fprintf('Condition: %s | n_used = %d | original min_trials = %d\n', ...
    cond_label, n_used, min_trials);

%% -------------------------
% SELECT OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(mat_fp, 'Select output folder for 7_C2 results');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% CHOOSE NEW COUNT THRESHOLD
% -------------------------
sigma_char    = char(963);
default_thresh = 15;

answer = inputdlg( ...
    sprintf(['New display threshold (min_count_display):\n\n' ...
             'A pixel is shown at timepoint t only if\n' ...
             '  count_activated(x,y,t) >= threshold\n' ...
             '  OR count_suppressed(x,y,t) >= threshold\n\n' ...
             'Original 7_C min_trials was %d of %d.'], min_trials, n_used), ...
    'Step 7_C2: count threshold', [1 60], {num2str(default_thresh)});

if isempty(answer), error('Cancelled.'); end
min_count_display = round(str2double(answer{1}));
assert(isfinite(min_count_display) && min_count_display >= 1, ...
    'Threshold must be a positive integer.');

fprintf('Applying count threshold: %d\n', min_count_display);

%% -------------------------
% PER-FRAME THRESHOLD MASK
% -------------------------
% A pixel is shown at frame t only when its DOMINANT direction reaches the
% threshold (same direction-preference logic as the region computation):
%   activated  : count_act >= threshold  AND  count_act >= count_sup
%   suppressed : count_sup >= threshold  AND  count_sup >  count_act
% This prevents mixed pixels (e.g. 15 activated + 15 suppressed, net = 0)
% from appearing as spurious neutral signal.
act_dom = (count_act >= min_count_display) & (count_act >= count_sup);
sup_dom = (count_sup >= min_count_display) & (count_sup >  count_act);
thresh_mask = (act_dom | sup_dom) & ~always_nan_mask;

net_count = count_act - count_sup;   % H x W x T (signed)

%% -------------------------
% RECOMPUTE REGION (same direction-preference logic as 7_C)
% -------------------------
post_idx   = find(t_s >= 0);
max_act    = max(count_act(:,:,post_idx), [], 3);   % H x W
max_sup    = max(count_sup(:,:,post_idx), [], 3);   % H x W

new_is_act = (max_act >= min_count_display) & (max_act >= max_sup);
new_is_sup = (max_sup >= min_count_display) & (max_sup >  max_act);

new_is_act(always_nan_mask) = false;
new_is_sup(always_nan_mask) = false;

new_region_mask   = new_is_act | new_is_sup;
new_region_signed = zeros(H, W);
new_region_signed(new_is_act) =  max_act(new_is_act);
new_region_signed(new_is_sup) = -max_sup(new_is_sup);

thresh_post      = thresh_mask(:,:,post_idx);
post_counts      = squeeze(sum(sum(thresh_post, 1), 2));
[peak_n, pk_loc] = max(post_counts);
peak_idx         = post_idx(pk_loc);

n_region = sum(new_region_mask(:));
n_act    = sum(new_is_act(:));
n_sup    = sum(new_is_sup(:));

fprintf('New region: %d px (%d activated, %d suppressed)\n', n_region, n_act, n_sup);
fprintf('Peak at t = %+.2f s (%d px above threshold)\n', t_s(peak_idx), peak_n);

%% -------------------------
% OUTPUT TAG
% -------------------------
[~, base_name, ~] = fileparts(mat_fn);   % e.g. consensus_ch16_5uA_1sigma_min20of30_m1
out_tag = sprintf('%s_c%d', base_name, min_count_display);

%% -------------------------
% SAVE .mat
% -------------------------
thresh_mask_u8 = uint8(thresh_mask);
save(fullfile(save_dir, sprintf('%s.mat', out_tag)), ...
    'thresh_mask_u8', 'new_region_mask', 'new_region_signed', ...
    'new_is_act', 'new_is_sup', 'net_count', ...
    'min_count_display', 'n_std', 'min_trials', 'n_used', ...
    'cond_label', 't_s', 'always_nan_mask', 'V1_mask', '-v7.3');
fprintf('Saved: %s.mat\n', out_tag);

%% -------------------------
% COLORMAP AND STYLE
% -------------------------
cmap              = jet(256);
color_outside     = [0.15 0.15 0.15];
color_inactive    = [0.40 0.40 0.40];
brain_color       = [0.85 0.85 0.85];
v1_outline_color  = [0.10 0.85 0.30];
frame_grid_tmin   = -0.2;
frame_grid_tmax   =  1.2;

%% -------------------------
% FRAME-GRID FIGURE
% -------------------------
display_frame_idx = find(t_s >= frame_grid_tmin & t_s <= frame_grid_tmax);
if isempty(display_frame_idx)
    [~, display_frame_idx] = min(abs(t_s));
end

n_display = numel(display_frame_idx);
n_cols    = 5;
n_rows    = ceil(n_display / n_cols);

fig = figure('Color', 'w', 'Visible', 'off', ...
    'Position', [50 50  min(1800, 240*n_cols)  240*n_rows + 80]);
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');
last_ax = [];

for di = 1:n_display
    fi  = display_frame_idx(di);
    ax  = nexttile(tl);
    image(ax, net_count_rgb(net_count(:,:,fi), thresh_mask(:,:,fi), ...
        always_nan_mask, n_used, cmap, color_outside, color_inactive));
    axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
    draw_outlines(ax, always_nan_mask, V1_mask, brain_color, v1_outline_color);
    title(ax, sprintf('t = %+.2f s', t_s(fi)), 'FontSize', 8);
    last_ax = ax;
end

if ~isempty(last_ax)
    colormap(last_ax, cmap); clim(last_ax, [-n_used n_used]);
    cb = colorbar(last_ax);
    cb.Label.String = 'net count (activated \minus suppressed)';
end

title(tl, sprintf( ...
    'Consensus net-count (t in [%.1f, %.1f] s)  |  %s  |  count \geq %d of %d  |  %g%s', ...
    frame_grid_tmin, frame_grid_tmax, cond_label, ...
    min_count_display, n_used, n_std, sigma_char), ...
    'Interpreter', 'tex', 'FontSize', 10);

exportgraphics(fig, fullfile(save_dir, sprintf('%s_frame_grid.png', out_tag)), 'Resolution', 150);
close(fig);
fprintf('Saved: %s_frame_grid.png\n', out_tag);

%% -------------------------
% REGION FIGURE
% -------------------------
fig2 = figure('Color', 'w', 'Visible', 'off', 'Position', [60 60 1200 540]);
tl2  = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl2);
image(ax1, net_count_rgb(new_region_signed, new_region_mask, ...
    always_nan_mask, n_used, cmap, color_outside, color_inactive));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
draw_outlines(ax1, always_nan_mask, V1_mask, brain_color, v1_outline_color);
colormap(ax1, cmap); clim(ax1, [-n_used n_used]);
title(ax1, sprintf('Region  (%d px: %d activated, %d suppressed)', n_region, n_act, n_sup), ...
    'FontSize', 11);

ax2 = nexttile(tl2);
image(ax2, net_count_rgb(net_count(:,:,peak_idx), thresh_mask(:,:,peak_idx), ...
    always_nan_mask, n_used, cmap, color_outside, color_inactive));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
draw_outlines(ax2, always_nan_mask, V1_mask, brain_color, v1_outline_color);
colormap(ax2, cmap); clim(ax2, [-n_used n_used]);
cb2 = colorbar(ax2); cb2.Label.String = 'net count';
title(ax2, sprintf('Peak | t = %+.2f s | %d px', t_s(peak_idx), peak_n), 'FontSize', 11);

title(tl2, sprintf('%s  |  count \geq %d of %d  |  %g%s  (red = activated, blue = suppressed)', ...
    cond_label, min_count_display, n_used, n_std, sigma_char), ...
    'Interpreter', 'tex', 'FontSize', 12);

exportgraphics(fig2, fullfile(save_dir, sprintf('%s_region.png', out_tag)), 'Resolution', 150);
close(fig2);
fprintf('Saved: %s_region.png\n', out_tag);

fprintf('\nDone. Outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function rgb = net_count_rgb(net_frame, show_mask, always_nan_mask, n_max, ...
    cmap, color_outside, color_inactive)
% Render a net-count frame:
%   show_mask = true  -> colored by net count via jet
%   ~show_mask & ~always_nan_mask -> color_inactive (medium gray)
%   always_nan_mask -> color_outside (dark gray)
n = size(cmap, 1);
if n_max <= 0, n_max = 1; end
scaled = (double(net_frame) + n_max) / (2 * n_max);   % map [-n_max, n_max] to [0,1]
scaled(~isfinite(scaled)) = 0.5;
idx = uint16(min(max(round(scaled * (n-1)), 0), n-1)) + 1;
rgb = ind2rgb(idx, cmap);

inactive = ~show_mask & ~always_nan_mask;
for c = 1:3
    ch = rgb(:,:,c);
    ch(inactive)        = color_inactive(c);
    ch(always_nan_mask) = color_outside(c);
    rgb(:,:,c) = ch;
end
end


function draw_outlines(ax, always_nan_mask, V1_mask, brain_color, v1_color)
if any(~always_nan_mask(:))
    visboundaries(ax, ~always_nan_mask, 'Color', brain_color, 'LineWidth', 0.6);
end
if ~isempty(V1_mask) && any(V1_mask(:))
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
end