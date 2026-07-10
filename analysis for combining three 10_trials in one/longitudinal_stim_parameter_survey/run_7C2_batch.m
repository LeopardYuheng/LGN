function run_7C2_batch(consensus_mat_file, save_dir, min_count_display)
% run_7C2_batch  Headless batch version of consensus_7C2.
%
% Applies a directional count threshold to one 7_C or 7_D consensus .mat
% file and saves a frame-grid figure, a region figure, and a .mat.
%
% A pixel is shown at timepoint t only when its DOMINANT direction reaches
% the threshold:
%   activated  : count_act(x,y,t) >= min_count_display  AND  count_act >= count_sup
%   suppressed : count_sup(x,y,t) >= min_count_display  AND  count_sup >  count_act
%
% Usage:
%   run_7C2_batch(consensus_mat_file, save_dir, min_count_display)
%
% Arguments:
%   consensus_mat_file  path to a consensus_*_m1.mat from step 7_C or 7_D
%   save_dir            output folder (created if absent)
%   min_count_display   directional count threshold (e.g. 15)

assert(isfile(consensus_mat_file), 'File not found:\n  %s', consensus_mat_file);
assert(min_count_display >= 1, 'min_count_display must be >= 1.');

sigma_char       = char(963);
color_outside    = [0.15 0.15 0.15];
color_inactive   = [0.40 0.40 0.40];
brain_color      = [0.85 0.85 0.85];
v1_outline_color = [0.10 0.85 0.30];
frame_grid_tmin  = -0.2;
frame_grid_tmax  =  1.2;

%% -------------------------
% LOAD 7_C / 7_D .mat
% -------------------------
S = load(consensus_mat_file);
required = {'count_activated_u16', 'count_suppressed_u16', ...
            'always_nan_mask', 'n_used', 't_s', 'cond_label'};
for i = 1:numel(required)
    assert(isfield(S, required{i}), 'Missing field "%s" in:\n  %s', ...
        required{i}, consensus_mat_file);
end

count_act       = double(S.count_activated_u16);
count_sup       = double(S.count_suppressed_u16);
always_nan_mask = logical(S.always_nan_mask);
n_used          = double(S.n_used);
t_s             = double(S.t_s(:)');
cond_label      = char(S.cond_label);
n_std           = S.n_std;
min_trials      = S.min_trials;

[H, W, T] = size(count_act);
assert(numel(t_s) == T, 't_s length mismatch.');

V1_mask = [];
if isfield(S, 'V1_mask') && ~isempty(S.V1_mask)
    V1_mask = logical(S.V1_mask);
end

if ~exist(save_dir, 'dir'), mkdir(save_dir); end

fprintf('Processing: %s  |  min_count_display = %d\n', cond_label, min_count_display);

%% -------------------------
% PER-FRAME THRESHOLD MASK (directional)
% -------------------------
act_dom     = (count_act >= min_count_display) & (count_act >= count_sup);
sup_dom     = (count_sup >= min_count_display) & (count_sup >  count_act);
thresh_mask = (act_dom | sup_dom) & ~always_nan_mask;

net_count = count_act - count_sup;   % H x W x T

%% -------------------------
% RECOMPUTE REGION
% -------------------------
post_idx = find(t_s >= 0);
max_act  = max(count_act(:,:,post_idx), [], 3);
max_sup  = max(count_sup(:,:,post_idx), [], 3);

new_is_act = (max_act >= min_count_display) & (max_act >= max_sup) & ~always_nan_mask;
new_is_sup = (max_sup >= min_count_display) & (max_sup >  max_act) & ~always_nan_mask;

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
fprintf('  Region: %d px (%d act, %d sup) | peak t=%+.2f s (%d px)\n', ...
    n_region, n_act, n_sup, t_s(peak_idx), peak_n);

%% -------------------------
% OUTPUT TAG
% -------------------------
[~, base_name] = fileparts(consensus_mat_file);
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

%% -------------------------
% FRAME-GRID FIGURE
% -------------------------
cmap = jet(256);
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
    fi = display_frame_idx(di);
    ax = nexttile(tl);
    image(ax, net_count_rgb(net_count(:,:,fi), thresh_mask(:,:,fi), ...
        always_nan_mask, n_used, cmap, color_outside, color_inactive));
    axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','normal'); hold(ax,'on');
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
    'Consensus (t in [%.1f, %.1f] s)  |  %s  |  count \geq %d of %d  |  %g%s', ...
    frame_grid_tmin, frame_grid_tmax, cond_label, ...
    min_count_display, n_used, n_std, sigma_char), ...
    'Interpreter', 'tex', 'FontSize', 10);

exportgraphics(fig, fullfile(save_dir, sprintf('%s_frame_grid.png', out_tag)), 'Resolution', 150);
close(fig);

%% -------------------------
% REGION FIGURE
% -------------------------
fig2 = figure('Color', 'w', 'Visible', 'off', 'Position', [60 60 1200 540]);
tl2  = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl2);
image(ax1, net_count_rgb(new_region_signed, new_region_mask, ...
    always_nan_mask, n_used, cmap, color_outside, color_inactive));
axis(ax1,'image'); axis(ax1,'off'); set(ax1,'YDir','normal'); hold(ax1,'on');
draw_outlines(ax1, always_nan_mask, V1_mask, brain_color, v1_outline_color);
colormap(ax1, cmap); clim(ax1, [-n_used n_used]);
title(ax1, sprintf('Region  (%d px: %d activated, %d suppressed)', n_region, n_act, n_sup), 'FontSize', 11);

ax2 = nexttile(tl2);
image(ax2, net_count_rgb(net_count(:,:,peak_idx), thresh_mask(:,:,peak_idx), ...
    always_nan_mask, n_used, cmap, color_outside, color_inactive));
axis(ax2,'image'); axis(ax2,'off'); set(ax2,'YDir','normal'); hold(ax2,'on');
draw_outlines(ax2, always_nan_mask, V1_mask, brain_color, v1_outline_color);
colormap(ax2, cmap); clim(ax2, [-n_used n_used]);
cb2 = colorbar(ax2); cb2.Label.String = 'net count';
title(ax2, sprintf('Peak | t = %+.2f s | %d px', t_s(peak_idx), peak_n), 'FontSize', 11);

title(tl2, sprintf('%s  |  count \geq %d of %d  |  %g%s  (red = activated, blue = suppressed)', ...
    cond_label, min_count_display, n_used, n_std, sigma_char), ...
    'Interpreter', 'tex', 'FontSize', 12);

exportgraphics(fig2, fullfile(save_dir, sprintf('%s_region.png', out_tag)), 'Resolution', 150);
close(fig2);

fprintf('  Saved: %s_frame_grid.png + _region.png + .mat\n', out_tag);
end

%% =========================
% LOCAL FUNCTIONS
%% =========================

function rgb = net_count_rgb(net_frame, show_mask, always_nan_mask, n_max, ...
    cmap, color_outside, color_inactive)
n = size(cmap, 1);
if n_max <= 0, n_max = 1; end
scaled = (double(net_frame) + n_max) / (2 * n_max);
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