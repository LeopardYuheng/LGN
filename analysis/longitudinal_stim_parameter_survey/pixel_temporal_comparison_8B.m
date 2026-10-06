%% pixel_temporal_comparison_8B.m
% Step 8_B: Multi-channel circle-of-interest dF/F(t) comparison across
% stimulation currents.
%
% Extension of step 8 (pixel_temporal_comparison_8.m): instead of a single
% channel, lets the user pick MULTIPLE channels. For each picked channel:
%   1. A reference dF/F map is built from that channel's highest-current
%      condition (same convention as step 8).
%   2. The user draws ONE circle of interest on that map.
%   3. The mean dF/F(t) inside that circle is computed for every current
%      level available for that channel (same math as step 8).
%   4. A per-channel QC figure (reference map + circle, dF/F(t) across
%      currents for that channel alone) is saved, in the same format as
%      step 8's output.
%
% These per-channel, per-current traces are then averaged ACROSS the
% picked channels for each shared current level (e.g. the 7 uA trace is
% the mean of the 7 uA circle-of-interest traces from channels 30, 35, 43),
% producing one dF/F(t) function per current — plotted together in a
% single combined figure, in the same style as step 8's dF/F(t) panel.
%
% All selected channels/currents must share an identical time axis (t_s);
% this is required so per-channel traces can be averaged directly with no
% interpolation.
%
% Optional V1 boundary overlay (from step 6 day_setup), same convention as
% steps 5_A/5_B/7_A/7_B/8.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside = [0.15 0.15 0.15];
stim_win_s         = [0 0.5];   % stimulation time window shaded on dF/F(t) plots

%% -------------------------
% SELECT METHOD (5_A vs 5_B output)
% -------------------------
method_choice = questdlg('Which dF/F movies should step 8_B read?', ...
    'Step 8_B: select source', ...
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
% SELECT ROOT FOLDER + CHANNELS (multiple)
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
    'Name',          'Select channels', ...
    'PromptString',  'Select one or more channels (Ctrl+click) for the cross-channel average:', ...
    'ListString',    ch_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [220 260], ...
    'OKString',      'Select', ...
    'CancelString',  'Cancel');
if ~ok || isempty(ch_sel), error('No channel(s) selected.'); end
sel_channels = unique_chs(ch_sel);
n_ch = numel(sel_channels);
fprintf('Selected %d channel(s): %s\n', n_ch, mat2str(sel_channels'));

%% -------------------------
% GLOBAL CURRENT -> COLOR MAP (shared by every plot, so e.g. 7 uA is
% always the same color whether in a per-channel figure or the combined one)
% -------------------------
keep_sel            = ismember(chs, sel_channels);
all_currents_global  = unique(curs(keep_sel));
n_cur_global         = numel(all_currents_global);
global_cur_colors    = assign_current_colors(n_cur_global);
current_color_map    = containers.Map(num2cell(all_currents_global), num2cell(global_cur_colors, 2));
fprintf('Current levels found across selected channels: %s uA\n', mat2str(all_currents_global'));

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(root_dir, 'Select output folder for temporal comparison figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
combo_save_dir = fullfile(save_dir, sprintf('multichannel_%s_temporal', strjoin(string(sel_channels(:))', '-')));
if ~exist(combo_save_dir, 'dir'), mkdir(combo_save_dir); end

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY
% -------------------------
v1_outline_color = [0.10 0.85 0.30];
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');

% Peek at one file to get H x W before loading V1 (same convention as steps 5_A/7_A/8)
peek_idx = find(chs == sel_channels(1), 1, 'first');
S0 = load(fullfile(mat_files(peek_idx).folder, mat_files(peek_idx).name));
if isfield(S0, 'mean_dff_movie'), tmp = S0.mean_dff_movie;
else,                              tmp = S0.dff_movie; end
[H, W, ~] = size(tmp); clear tmp S0;

if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = get_v1_boundary(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary loaded: %s\n', v1_fn); end
end

%% -------------------------
% PER-CHANNEL LOADING + CIRCLE PICKING
% -------------------------
channel_data = struct('channel', {}, 'conditions', {}, 'circle', {}, 'ref_title', {});
global_t_s   = [];

for ci = 1:n_ch
    ch = sel_channels(ci);
    keep         = (chs == ch);
    ch_mat_files = mat_files(keep);
    ch_curs      = curs(keep);
    [ch_curs, sord] = sort(ch_curs);
    ch_mat_files    = ch_mat_files(sord);
    n_cur_ch        = numel(ch_mat_files);
    fprintf('\nChannel %d: %d current level(s) found: %s uA\n', ch, n_cur_ch, mat2str(ch_curs'));

    conditions = struct('current_uA', {}, 'movie', {}, 't_s', {}, 'always_nan_mask', {});
    for i = 1:n_cur_ch
        mv_fpath = fullfile(ch_mat_files(i).folder, ch_mat_files(i).name);
        S = load(mv_fpath);
        if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
        elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
        else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', mv_fpath); end
        assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

        conditions(i).current_uA      = ch_curs(i);
        conditions(i).movie           = movie;
        conditions(i).t_s             = double(S.t_s(:)');
        conditions(i).always_nan_mask = all(isnan(movie), 3);
        fprintf('  Loaded %g uA: %s\n', ch_curs(i), ch_mat_files(i).name);
    end

    for i = 1:numel(conditions)
        [Hi, Wi, ~] = size(conditions(i).movie);
        assert(Hi == H && Wi == W, ...
            'Frame size mismatch for Ch %d (%dx%d vs %dx%d) — cannot compare across channels.', ...
            ch, Hi, Wi, H, W);
        if isempty(global_t_s)
            global_t_s = conditions(i).t_s;
        else
            assert(isequal(conditions(i).t_s, global_t_s), ...
                ['Time axis (t_s) mismatch for Ch %d, %g uA — all selected channels/currents must ' ...
                 'share the same time axis to be averaged together.'], ch, conditions(i).current_uA);
        end
    end

    % --- Reference map: highest-current condition's most active post-stim frame ---
    [~, ref_i] = max(ch_curs);
    ref_movie           = conditions(ref_i).movie;
    ref_t               = conditions(ref_i).t_s;
    ref_always_nan_mask = conditions(ref_i).always_nan_mask;

    post_idx = find(ref_t >= 0);
    if isempty(post_idx), post_idx = 1:numel(ref_t); end
    mean_abs_post  = squeeze(mean(mean(abs(ref_movie(:,:,post_idx)), 1, 'omitnan'), 2, 'omitnan'));
    [~, pk_loc]    = max(mean_abs_post);
    peak_frame_idx = post_idx(pk_loc);
    peak_img       = ref_movie(:,:,peak_frame_idx);

    clim_bg  = data_clim(ref_movie, ~ref_always_nan_mask);
    ref_cmap = jet(256);
    ref_title = sprintf('Reference map  |  Ch %d  |  %g uA  |  t = %+.2f s', ...
        ch, ch_curs(ref_i), ref_t(peak_frame_idx));
    fprintf('  Reference map: Ch %d | %g uA | peak frame t = %+.2f s\n', ...
        ch, ch_curs(ref_i), ref_t(peak_frame_idx));

    % --- Draw the circle of interest for this channel ---
    circle = pick_single_circle_on_reference(peak_img, ref_always_nan_mask, ref_t, peak_frame_idx, ...
        clim_bg, ref_cmap, mask_color_outside, V1_mask, v1_outline_color, ...
        sprintf('Ch %d  |  reference: %g uA', ch, ch_curs(ref_i)), ref_movie);

    if isempty(circle)
        fprintf('  No circle drawn for Ch %d — this channel is excluded from all outputs.\n', ch);
        continue;
    end

    channel_data(end+1) = struct('channel', ch, 'conditions', conditions, ...
        'circle', circle, 'ref_title', ref_title); %#ok<AGROW>

    % --- Per-channel QC figure: reference map + circle, dF/F(t) across currents ---
    plot_circle_across_currents(conditions, current_color_map, circle, ch, combo_save_dir, is_m1, ...
        peak_img, ref_always_nan_mask, clim_bg, ref_cmap, mask_color_outside, ...
        V1_mask, v1_outline_color, ref_title, stim_win_s);
end

n_used = numel(channel_data);
assert(n_used > 0, 'No channel had a circle of interest drawn — nothing to average.');
if n_used < n_ch
    fprintf('\n%d of %d selected channel(s) contributed a circle of interest.\n', n_used, n_ch);
end

%% -------------------------
% CROSS-CHANNEL AVERAGE PER CURRENT + COMBINED PLOT
% -------------------------
plot_multichannel_current_average(channel_data, current_color_map, all_currents_global, ...
    global_t_s, stim_win_s, combo_save_dir, is_m1);

fprintf('\nDone. Outputs in:\n  %s\n', combo_save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie. Same convention as steps 5_A/5_B/7_A/7_B/8.
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

function circle = pick_single_circle_on_reference(peak_img, always_nan_mask, t_s, peak_idx, ...
    clim_range, cmap, mask_color, V1_mask, v1_color, title_str, movie)
% Time-slider viewer over one reference dF/F movie. Draws ONE circular ROI
% (with a redraw option) defining this channel's circle of interest.
%   - Drag out a circle, then double-click / Enter to confirm it.
%   - Accept it, redraw, or cancel this channel entirely.
% Returns a struct with .center [x y], .radius, .mask (H x W logical), or
% [] if the channel was cancelled / the figure was closed.
[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', ['Draw circle of interest — ' title_str], ...
    'Position', [80 80 780 700]);
ax = axes(fig, 'Position', [0.10 0.12 0.78 0.80]);

img = image(ax, dff_frame_to_rgb(peak_img, always_nan_mask, clim_range, cmap, mask_color));
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

sgtitle(fig, 'Drag out the circle of interest, then double-click / Enter to confirm.');

[xx, yy] = meshgrid(1:W, 1:H);
circle = [];

while isvalid(fig)
    h_circ = drawcircle(ax, 'Color', [1 1 0], 'LineWidth', 1.6, 'FaceAlpha', 0.08);
    wait(h_circ);
    if ~isvalid(h_circ)
        break;   % figure closed while drawing
    end

    c = h_circ.Center;
    r = h_circ.Radius;
    m = ((xx - c(1)).^2 + (yy - c(2)).^2) <= r^2;
    n_px = sum(m(:) & ~always_nan_mask(:));
    fprintf('  Circle: center (%.1f, %.1f), radius %.1f px, %d in-mask pixel(s)\n', c(1), c(2), r, n_px);

    if ~isvalid(fig), break; end
    choice = questdlg('Accept this circle of interest?', 'Circle of interest', ...
        'Accept', 'Redraw', 'Cancel channel', 'Accept');
    if strcmp(choice, 'Accept')
        circle = struct('center', c, 'radius', r, 'mask', m);
        break;
    elseif isempty(choice) || strcmp(choice, 'Cancel channel')
        delete(h_circ);
        circle = [];
        break;
    else   % 'Redraw'
        delete(h_circ);
    end
end

if isvalid(fig), close(fig); end
end

function plot_circle_across_currents(conditions, current_color_map, circle, sel_channel, save_dir, is_m1, ...
    ref_img, ref_mask, ref_clim, ref_cmap, mask_color, V1_mask, v1_color, ref_title, stim_win_s)
% Two-panel QC figure for ONE channel: left = reference dF/F map with the
% circle of interest outlined, right = mean dF/F(t) within that circle
% overlaid for every current level available for this channel. Colors come
% from current_color_map so they match the combined cross-channel plot.
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
    col   = current_color_map(conditions(i).current_uA);
    handles(i) = plot(ax2, conditions(i).t_s, trace, '-', 'Color', col, 'LineWidth', 1.5);
    labels{i}  = sprintf('%g uA', conditions(i).current_uA);
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
currents_uA   = arrayfun(@(c) c.current_uA, conditions)'; %#ok<NASGU>
traces        = arrayfun(@(c) roi_mean_trace(c.movie, roi_mask), conditions, 'UniformOutput', false); %#ok<NASGU>
t_s_all       = arrayfun(@(c) c.t_s, conditions, 'UniformOutput', false); %#ok<NASGU>
circle_center = circle.center; %#ok<NASGU>
circle_radius = circle.radius; %#ok<NASGU>
save(fullfile(save_dir, mat_fname), 'currents_uA', 'traces', 't_s_all', ...
    'roi_mask', 'circle_center', 'circle_radius', 'sel_channel');
fprintf('  Saved data:   %s\n', mat_fname);
end

function plot_multichannel_current_average(channel_data, current_color_map, all_currents_global, ...
    t_s, stim_win_s, save_dir, is_m1)
% One combined figure: for every current level found across the picked
% channels, average that current's circle-of-interest dF/F(t) trace across
% all channels that had that current available, then plot all currents
% together — same layout/style as step 8's dF/F(t) panel.
method_tag = '';
if is_m1, method_tag = ' (Method 1)'; end

n_ch_used   = numel(channel_data);
ch_list_str = mat2str([channel_data.channel]);
n_cur       = numel(all_currents_global);

fig = figure('Color', 'w', 'Position', [100 100 760 560]);
ax  = axes(fig);
hold(ax, 'on');

handles       = gobjects(0, 1);
labels        = {};
combined_traces = cell(n_cur, 1);
n_contrib_list  = zeros(n_cur, 1);

for k = 1:n_cur
    cur = all_currents_global(k);
    per_channel_traces = [];
    contributing_chs = [];
    for cd = 1:n_ch_used
        idx = find([channel_data(cd).conditions.current_uA] == cur, 1);
        if isempty(idx), continue; end
        trace = roi_mean_trace(channel_data(cd).conditions(idx).movie, channel_data(cd).circle.mask);
        per_channel_traces = [per_channel_traces, trace]; %#ok<AGROW>
        contributing_chs   = [contributing_chs, channel_data(cd).channel]; %#ok<AGROW>
    end
    if isempty(per_channel_traces)
        fprintf('  Note: no selected channel has %g uA — skipped in combined plot.\n', cur);
        continue;
    end
    combined_trace = mean(per_channel_traces, 2, 'omitnan');
    combined_traces{k}  = combined_trace;
    n_contrib_list(k)   = numel(contributing_chs);

    col = current_color_map(cur);
    h = plot(ax, t_s, combined_trace, '-', 'Color', col, 'LineWidth', 1.8);
    handles(end+1, 1) = h; %#ok<AGROW>
    if numel(contributing_chs) < n_ch_used
        labels{end+1} = sprintf('%g uA (n=%d/%d ch)', cur, numel(contributing_chs), n_ch_used); %#ok<AGROW>
    else
        labels{end+1} = sprintf('%g uA (n=%d ch)', cur, numel(contributing_chs)); %#ok<AGROW>
    end
end

% Shade the stimulation window and mark its edges with dashed lines
yl = ylim(ax);
h_stim = patch(ax, stim_win_s([1 2 2 1]), yl([1 1 2 2]), [1.00 0.80 0.40], ...
    'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
uistack(h_stim, 'bottom');
xline(ax, stim_win_s(1), '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
xline(ax, stim_win_s(2), '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
ylim(ax, yl);

xlabel(ax, 'Time relative to stimulation onset (s)');
ylabel(ax, 'Mean \DeltaF/F (averaged across channels'' circles of interest)');
title(ax, sprintf('Cross-channel average dF/F(t)  |  Ch %s%s', ch_list_str, method_tag), ...
    'Interpreter', 'none');
legend(ax, handles, labels, 'Location', 'best', 'Box', 'off');
grid(ax, 'on'); box(ax, 'on');

fname_tag = 'dff_t_multichannel_avg';
if is_m1, fname_tag = [fname_tag '_m1']; end
ch_vec = [channel_data.channel];
ch_tag = strjoin(string(ch_vec(:))', '-');
fig_fname = sprintf('%s_ch%s.png', fname_tag, ch_tag);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('\nSaved combined figure: %s\n', fig_fname);

mat_fname = sprintf('%s_ch%s.mat', fname_tag, ch_tag);
channels_used  = [channel_data.channel]; %#ok<NASGU>
circle_centers = arrayfun(@(c) c.circle.center, channel_data, 'UniformOutput', false); %#ok<NASGU>
circle_radii   = arrayfun(@(c) c.circle.radius, channel_data); %#ok<NASGU>
currents_uA    = all_currents_global; %#ok<NASGU>
n_channels_per_current = n_contrib_list; %#ok<NASGU>
save(fullfile(save_dir, mat_fname), 'channels_used', 'circle_centers', 'circle_radii', ...
    'currents_uA', 'combined_traces', 'n_channels_per_current', 't_s');
fprintf('Saved combined data:   %s\n', mat_fname);
end