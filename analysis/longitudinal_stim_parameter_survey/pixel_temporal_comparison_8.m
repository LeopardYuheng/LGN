%% pixel_temporal_comparison_8.m
% Step 8: Circle-of-interest dF/F(t) comparison across stimulation currents, same channel.
%
% Reads the trial-averaged dF/F movies produced by step 5_A (Method 0,
% mean_dff_ch{N}_{I}uA.mat) or step 5_B (Method 1, mean_dff_m1_ch{N}_{I}uA.mat),
% lets the user pick ONE channel, auto-discovers every current level available
% for that channel, then lets the user draw one or more circular regions of
% interest (ROIs) on a reference dF/F map.
%
% For each drawn circle, one figure is produced with dF/F(t) traces for every
% current of the selected channel overlaid — one line color per current
% (e.g. 0 uA green, 2 uA red, 3 uA blue, ... 7 uA — colors are assigned
% automatically, in ascending current order, from a fixed qualitative
% palette). Each trace is the mean dF/F, at every time point, averaged over
% all in-mask (non-NaN) pixels inside that circle.
%
% Optional V1 boundary overlay (from step 6 day_setup), same convention as
% steps 5_A/5_B/7_A/7_B.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside = [0.15 0.15 0.15];
stim_win_s         = [0 0.5];   % stimulation time window shaded on dF/F(t) plots

%% -------------------------
% SELECT METHOD (5_A vs 5_B output)
% -------------------------
method_choice = questdlg('Which dF/F movies should step 8 read?', ...
    'Step 8: select source', ...
    'Method 0 (step 5_A)', 'Method 1 (step 5_B)', 'Method 0 (step 5_A)');
if isempty(method_choice), error('Cancelled.'); end
is_m1 = strcmp(method_choice, 'Method 1 (step 5_B)');
if is_m1
    file_glob   = 'mean_dff_m1_ch*uA.mat';
    prompt_text = 'Select step-5_B output folder (contains method1/ch{N}_{I}uA/ subfolders)';
else
    file_glob   = 'mean_dff_ch*uA.mat';
    prompt_text = 'Select step-5_A output folder (contains ch{N}_{I}uA/ subfolders)';
end

%% -------------------------
% SELECT ROOT FOLDER + CHANNEL
% -------------------------
root_dir = uigetdir(pwd, prompt_text);
if isequal(root_dir, 0), error('No folder selected.'); end

mat_files = dir(fullfile(root_dir, '**', file_glob));
assert(~isempty(mat_files), 'No %s files found under:\n  %s', file_glob, root_dir);

chs  = nan(numel(mat_files), 1);
curs = nan(numel(mat_files), 1);
for i = 1:numel(mat_files)
    tok = regexp(mat_files(i).name, 'ch(\d+)_([\d.]+)uA', 'tokens', 'once');
    if ~isempty(tok)
        chs(i)  = str2double(tok{1});
        curs(i) = str2double(tok{2});
    end
end
valid     = isfinite(chs) & isfinite(curs);
mat_files = mat_files(valid);
chs       = chs(valid);
curs      = curs(valid);

unique_chs = unique(chs);
ch_strs    = arrayfun(@(c) sprintf('Ch %d', c), unique_chs, 'UniformOutput', false);
[ch_sel, ok] = listdlg( ...
    'Name',          'Select channel', ...
    'PromptString',  'Select ONE channel (all its current levels will be compared):', ...
    'ListString',    ch_strs, ...
    'SelectionMode', 'single', ...
    'ListSize',      [220 220], ...
    'OKString',      'Select', ...
    'CancelString',  'Cancel');
if ~ok || isempty(ch_sel), error('No channel selected.'); end
sel_channel = unique_chs(ch_sel);

keep      = (chs == sel_channel);
mat_files = mat_files(keep);
curs      = curs(keep);
[curs, sord] = sort(curs);
mat_files    = mat_files(sord);
n_cur        = numel(mat_files);
fprintf('Channel %d: %d current level(s) found: %s uA\n', sel_channel, n_cur, mat2str(curs'));

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(root_dir, 'Select output folder for temporal comparison figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
ch_save_dir = fullfile(save_dir, sprintf('ch%d_temporal', sel_channel));
if ~exist(ch_save_dir, 'dir'), mkdir(ch_save_dir); end

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY
% -------------------------
v1_outline_color = [0.10 0.85 0.30];
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');

%% -------------------------
% LOAD ALL CURRENT-LEVEL CONDITIONS FOR THIS CHANNEL
% -------------------------
conditions = struct('current_uA', {}, 'movie', {}, 't_s', {}, 'always_nan_mask', {});
for i = 1:n_cur
    mv_fpath = fullfile(mat_files(i).folder, mat_files(i).name);
    S = load(mv_fpath);
    if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
    elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
    else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', mv_fpath); end
    assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

    conditions(i).current_uA     = curs(i);
    conditions(i).movie          = movie;
    conditions(i).t_s            = double(S.t_s(:)');
    conditions(i).always_nan_mask = all(isnan(movie), 3);

    fprintf('  Loaded %g uA: %s\n', curs(i), mat_files(i).name);
end

[H, W, ~] = size(conditions(1).movie);
for i = 2:n_cur
    [Hi, Wi, ~] = size(conditions(i).movie);
    assert(Hi == H && Wi == W, ...
        'Frame size mismatch between current levels (%dx%d vs %dx%d) — cannot compare pixels.', ...
        Hi, Wi, H, W);
end

if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = get_v1_boundary(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary loaded: %s\n', v1_fn); end
end

%% -------------------------
% COLOR ASSIGNMENT PER CURRENT (ascending order)
% -------------------------
cur_colors = assign_current_colors(n_cur);

%% -------------------------
% REFERENCE MAP FOR ROI PICKING
% Uses the highest-current condition's most active post-stim frame.
% -------------------------
[~, ref_i] = max(curs);
ref_movie          = conditions(ref_i).movie;
ref_t              = conditions(ref_i).t_s;
ref_always_nan_mask = conditions(ref_i).always_nan_mask;

post_idx = find(ref_t >= 0);
if isempty(post_idx), post_idx = 1:numel(ref_t); end
mean_abs_post = squeeze(mean(mean(abs(ref_movie(:,:,post_idx)), 1, 'omitnan'), 2, 'omitnan'));
[~, pk_loc]   = max(mean_abs_post);
peak_frame_idx = post_idx(pk_loc);
peak_img       = ref_movie(:,:,peak_frame_idx);

clim_bg  = data_clim(ref_movie, ~ref_always_nan_mask);
ref_cmap = jet(256);
ref_title = sprintf('Reference map  |  Ch %d  |  %g uA  |  t = %+.2f s', ...
    sel_channel, curs(ref_i), ref_t(peak_frame_idx));
fprintf('\nReference map: Ch %d | %g uA | peak frame t = %+.2f s\n', ...
    sel_channel, curs(ref_i), ref_t(peak_frame_idx));

%% -------------------------
% INTERACTIVE CIRCLE-OF-INTEREST PICKING (with time slider on the reference condition)
% -------------------------
circles = pick_circles_on_reference(ref_movie, ref_always_nan_mask, ref_t, peak_frame_idx, ...
    clim_bg, ref_cmap, mask_color_outside, V1_mask, v1_outline_color, ...
    sprintf('Ch %d  |  reference: %g uA', sel_channel, curs(ref_i)));

if isempty(circles)
    fprintf('No circle(s) drawn. Nothing to plot.\n');
else
    fprintf('Generating dF/F(t) across-current comparison for %d circle(s) of interest...\n', numel(circles));
    for ci = 1:numel(circles)
        plot_circle_across_currents(conditions, cur_colors, circles(ci), sel_channel, ch_save_dir, is_m1, ...
            peak_img, ref_always_nan_mask, clim_bg, ref_cmap, mask_color_outside, ...
            V1_mask, v1_outline_color, ref_title, stim_win_s);
    end
end

fprintf('\nDone. Outputs in:\n  %s\n', ch_save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie. Same convention as steps 5_A/5_B/7_A/7_B.
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

function colors = assign_current_colors(n)
% Fixed qualitative palette, one distinct color per current level in
% ascending order (cycles if there are more currents than palette entries).
palette = [ ...
    0.20 0.63 0.17;   % green
    0.84 0.15 0.16;   % red
    0.12 0.47 0.71;   % blue
    1.00 0.50 0.05;   % orange
    0.58 0.40 0.74;   % purple
    0.55 0.34 0.29;   % brown
    0.89 0.47 0.76;   % pink
    0.50 0.50 0.50;   % gray
    0.74 0.74 0.13;   % olive
    0.09 0.75 0.81];  % cyan
idx    = mod((0:n-1)', size(palette, 1)) + 1;
colors = palette(idx, :);
end

function rgb = dff_frame_to_rgb(frame, mask, clim_range, cmap, mask_color)
n = size(cmap, 1);
scaled = (frame - clim_range(1)) / (clim_range(2) - clim_range(1));
scaled(~isfinite(scaled)) = 0;
idx = uint8(min(max(round(scaled * (n - 1)), 0), n - 1));
rgb = ind2rgb(idx, cmap);
for c = 1:3
    chan = rgb(:, :, c);
    chan(mask) = mask_color(c);
    rgb(:, :, c) = chan;
end
end

function circles = pick_circles_on_reference(movie, always_nan_mask, t_s, peak_idx, ...
    clim_range, cmap, mask_color, V1_mask, v1_color, title_str)
% Time-slider viewer over one reference dF/F movie. Draw circular ROIs to
% define one or more "circle of interest" regions for the across-current
% dF/F(t) comparison:
%   - Drag out a circle, then double-click or press Enter to confirm it.
%   - After each circle, choose to add another, undo the last one, or finish.
% Returns a struct array circles(k).center [x y], .radius, .mask (H x W
% logical, in-image-coordinate circular mask — NOT yet intersected with
% always_nan_mask; that is handled per-condition when averaging traces).
[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', ['Draw circle(s) of interest — ' title_str], ...
    'Position', [80 80 780 700]);
ax = axes(fig, 'Position', [0.10 0.12 0.78 0.80]);

img = image(ax, dff_frame_to_rgb(movie(:,:,peak_idx), always_nan_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
colormap(ax, cmap); clim(ax, clim_range); colorbar(ax);
th = title(ax, '', 'Interpreter', 'none');
set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, peak_idx);

uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.12 0.03 0.72 0.035], ...
    'Min', 1, 'Max', T, 'Value', peak_idx, ...
    'SliderStep', [1 / (T - 1), 5 / (T - 1)], ...
    'Callback', @(src, ~) set_ref_frame(img, th, movie, always_nan_mask, t_s, ...
        clim_range, cmap, mask_color, title_str, get(src, 'Value')));

sgtitle(fig, ['Drag out a circle of interest, then double-click / Enter to confirm.']);

[xx, yy] = meshgrid(1:W, 1:H);
circles = struct('center', {}, 'radius', {}, 'mask', {}, 'roi', {});

while isvalid(fig)
    h_circ = drawcircle(ax, 'Color', [1 1 0], 'LineWidth', 1.6, 'FaceAlpha', 0.08);
    wait(h_circ);
    if ~isvalid(h_circ)
        break;   % figure closed while drawing
    end

    c = h_circ.Center;
    r = h_circ.Radius;
    m = ((xx - c(1)).^2 + (yy - c(2)).^2) <= r^2;

    circles(end + 1) = struct('center', c, 'radius', r, 'mask', m, 'roi', h_circ); %#ok<AGROW>
    n_px = sum(m(:) & ~always_nan_mask(:));
    fprintf('  Circle %d: center (%.1f, %.1f), radius %.1f px, %d in-mask pixel(s)\n', ...
        numel(circles), c(1), c(2), r, n_px);

    if ~isvalid(fig), break; end
    choice = questdlg('Circle of interest added.', 'Circle of interest', ...
        'Add another', 'Undo last', 'Done', 'Done');
    if isempty(choice) || strcmp(choice, 'Done')
        break;
    elseif strcmp(choice, 'Undo last')
        if isvalid(circles(end).roi), delete(circles(end).roi); end
        circles(end) = [];
        fprintf('  Undid last circle   [%d remaining]\n', numel(circles));
    end
end

if isvalid(fig), close(fig); end
end

function set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, k)
[~, ~, T] = size(movie);
k = max(1, min(T, round(k)));
set(img, 'CData', dff_frame_to_rgb(movie(:,:,k), always_nan_mask, clim_range, cmap, mask_color));
set(th, 'String', sprintf('%s | t = %+.2f s', title_str, t_s(k)));
end

function trace = roi_mean_trace(movie, roi_mask)
% Mean dF/F within roi_mask at every frame, ignoring NaN (out-of-brain)
% pixels. NaN if the ROI contains no finite in-mask pixels for that frame.
[H, W, T] = size(movie);
flat  = reshape(movie, H * W, T);
sel   = flat(roi_mask(:), :);
trace = mean(sel, 1, 'omitnan')';
end

function plot_circle_across_currents(conditions, cur_colors, circle, sel_channel, save_dir, is_m1, ...
    ref_img, ref_mask, ref_clim, ref_cmap, mask_color, V1_mask, v1_color, ref_title, stim_win_s)
% Two-panel figure: left = reference dF/F map with the circle of interest
% outlined, right = mean dF/F(t) within that circle overlaid for every
% current level. The stimulation window (stim_win_s) is shaded with a
% light patch and bounded by dashed vertical lines.
[H, W] = size(ref_img);
method_tag = '';
if is_m1, method_tag = ' (Method 1)'; end

cx = circle.center(1); cy = circle.center(2); cr = circle.radius;
roi_mask = circle.mask;

fig = figure('Color', 'w', 'Position', [60 80 1220 480]);

% --- Left: reference map with the circle of interest outlined ---
ax1 = subplot(1, 2, 1);
image(ax1, dff_frame_to_rgb(ref_img, ref_mask, ref_clim, ref_cmap, mask_color));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
visboundaries(ax1, ~ref_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax1, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
colormap(ax1, ref_cmap); clim(ax1, ref_clim); colorbar(ax1);
viscircles(ax1, [cx cy], cr, 'Color', [1 1 0], 'LineWidth', 1.6);
title(ax1, ref_title, 'Interpreter', 'none', 'FontSize', 10);

% --- Right: mean dF/F(t) within the circle, overlaid across currents ---
ax2 = subplot(1, 2, 2);
hold(ax2, 'on');

n_cur   = numel(conditions);
handles = gobjects(n_cur, 1);
labels  = cell(n_cur, 1);
for i = 1:n_cur
    trace = roi_mean_trace(conditions(i).movie, roi_mask);
    handles(i) = plot(ax2, conditions(i).t_s, trace, '-', ...
        'Color', cur_colors(i, :), 'LineWidth', 1.5);
    labels{i} = sprintf('%g uA', conditions(i).current_uA);
end

% Shade the stimulation window and mark its edges with dashed lines
yl = ylim(ax2);
h_stim = patch(ax2, stim_win_s([1 2 2 1]), yl([1 1 2 2]), [1.00 0.80 0.40], ...
    'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
uistack(h_stim, 'bottom');
xline(ax2, stim_win_s(1), '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
xline(ax2, stim_win_s(2), '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
ylim(ax2, yl);

xlabel(ax2, 'Time relative to stimulation onset (s)');
ylabel(ax2, 'Mean \DeltaF/F (circle of interest)');
title(ax2, sprintf('Mean dF/F(t)  |  circle at (%.0f,%.0f), r=%.0f px  |  Ch %d%s', ...
    cx, cy, cr, sel_channel, method_tag), 'Interpreter', 'none');
legend(ax2, handles, labels, 'Location', 'best', 'Box', 'off');
grid(ax2, 'on'); box(ax2, 'on');

sgtitle(fig, sprintf('circle of interest at (%.0f,%.0f), r=%.0f px  |  Ch %d%s', ...
    cx, cy, cr, sel_channel, method_tag), 'Interpreter', 'none');

fname_tag = 'dff_t';
if is_m1, fname_tag = [fname_tag '_m1']; end
fig_fname = sprintf('%s_circle_x%.0f_y%.0f_r%.0f_ch%d_all_currents.png', ...
    fname_tag, cx, cy, cr, sel_channel);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('  Saved figure: %s\n', fig_fname);

mat_fname = sprintf('%s_circle_x%.0f_y%.0f_r%.0f_ch%d_all_currents.mat', ...
    fname_tag, cx, cy, cr, sel_channel);
currents_uA  = arrayfun(@(c) c.current_uA, conditions)'; %#ok<NASGU>
traces       = arrayfun(@(c) roi_mean_trace(c.movie, roi_mask), conditions, 'UniformOutput', false); %#ok<NASGU>
t_s_all      = arrayfun(@(c) c.t_s, conditions, 'UniformOutput', false); %#ok<NASGU>
circle_center = circle.center; %#ok<NASGU>
circle_radius = circle.radius; %#ok<NASGU>
save(fullfile(save_dir, mat_fname), 'currents_uA', 'traces', 't_s_all', ...
    'roi_mask', 'circle_center', 'circle_radius', 'sel_channel');
fprintf('  Saved data:   %s\n', mat_fname);
end