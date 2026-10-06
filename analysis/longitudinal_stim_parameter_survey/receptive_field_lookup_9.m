%% receptive_field_lookup_9.m
% Step 9: Look up the receptive field (altitude, azimuth) for clicked pixels.
%
% Uses the retinotopic alignment from step 6 (day_setup.retino_align:
% azi_stim, alt_stim, optional V1_mask_stim) together with a dF/F reference
% map from step 5_A or step 5_B. The user clicks pixel(s) on the dF/F
% reference map; for each picked pixel this script reads off the retinotopic
% map value at that pixel and reports it as the pixel's receptive field
% center: azi_stim(row,col) = azimuth (deg), alt_stim(row,col) = altitude
% (deg). This is a direct lookup, not a new computation -- step 6 already
% assigns a (altitude, azimuth) to every stim-space pixel.
%
% Inputs (selected interactively):
%   - day_setup .mat from step 6 (must contain retino_align.azi_stim /
%     .alt_stim, both H x W, and optionally .V1_mask_stim)
%   - a single dF/F .mat from step 5_A (dff_movie / mean_dff_movie) or
%     step 5_B (dff_movie / mean_dff_movie), same H x W as the retino maps
%
% Outputs (in a user-selected folder):
%   - receptive_field_lookup_<tag>.png   3-panel figure: dF/F reference map,
%     azimuth map, altitude map, all with the picked pixels numbered
%     (V1 boundary overlaid on the retino panels if available)
%   - receptive_field_lookup_<tag>.csv   pixel#, row, col, azimuth_deg,
%     altitude_deg, inside_V1
%   - receptive_field_lookup_<tag>.mat   same data, plus source file paths

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside = [0.15 0.15 0.15];
v1_outline_color    = [0.10 0.85 0.30];
pick_marker_color   = [1.00 1.00 1.00];

%% -------------------------
% LOAD DAY_SETUP (STEP 6 OUTPUT): azi_stim / alt_stim / V1_mask_stim
% -------------------------
[ds_fn, ds_fp] = uigetfile('*.mat', 'Select day_setup.mat from step 6 (retinotopic alignment)');
if isequal(ds_fn, 0), error('No day_setup file selected.'); end
day_setup_file = fullfile(ds_fp, ds_fn);
retino_align = load_retino_align(day_setup_file);
assert(~isempty(retino_align.azi_stim) && ~isempty(retino_align.alt_stim), ...
    'Selected file does not contain retino_align.azi_stim / alt_stim. Did you run step 6?');

azi_stim = retino_align.azi_stim;
alt_stim = retino_align.alt_stim;
V1_mask  = retino_align.V1_mask_stim;
[H, W]   = size(azi_stim);
assert(isequal(size(alt_stim), [H W]), 'azi_stim and alt_stim size mismatch.');

fprintf('Loaded retinotopic alignment from:\n  %s\n', day_setup_file);
fprintf('  Map size: %d x %d\n', H, W);

%% -------------------------
% SELECT DF/F SOURCE (STEP 5_A OR 5_B OUTPUT)
% -------------------------
method_choice = questdlg('Which dF/F result should step 9 use for pixel picking?', ...
    'Step 9: select source', ...
    'Method 0 (step 5_A)', 'Method 1 (step 5_B)', 'Method 0 (step 5_A)');
if isempty(method_choice), error('Cancelled.'); end
is_m1 = strcmp(method_choice, 'Method 1 (step 5_B)');

[dff_fn, dff_fp] = uigetfile('*.mat', ...
    'Select a dF/F .mat from step 5_A / 5_B (per-trial or trial-averaged)');
if isequal(dff_fn, 0), error('No dF/F file selected.'); end
dff_fpath = fullfile(dff_fp, dff_fn);

S = load(dff_fpath);
if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', dff_fpath); end
assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', dff_fpath);
t_s = double(S.t_s(:)');

[Hm, Wm, ~] = size(movie);
assert(Hm == H && Wm == W, ...
    ['dF/F movie size (%dx%d) does not match the retinotopic map size (%dx%d).\n' ...
     'Both must come from the same stim-space pixel grid (step 6 day_setup + step 5_A/5_B).'], ...
    Hm, Wm, H, W);

always_nan_mask = all(isnan(movie), 3);

if ~isempty(V1_mask) && ~isequal(size(V1_mask), [H W])
    warning('V1_mask_stim size does not match the map size -- dropping V1 overlay.');
    V1_mask = [];
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(dff_fp, 'Select output folder for receptive-field lookup results');
if isequal(save_dir, 0), error('No output folder selected.'); end

%% -------------------------
% REFERENCE FRAME FOR PIXEL PICKING (most active post-stim frame)
% -------------------------
post_idx = find(t_s >= 0);
if isempty(post_idx), post_idx = 1:numel(t_s); end
mean_abs_post = squeeze(mean(mean(abs(movie(:,:,post_idx)), 1, 'omitnan'), 2, 'omitnan'));
[~, pk_loc]    = max(mean_abs_post);
peak_frame_idx = post_idx(pk_loc);
peak_img       = movie(:,:,peak_frame_idx);

clim_bg = data_clim(movie, ~always_nan_mask);
cmap    = jet(256);
ref_title = sprintf('dF/F reference  |  %s  |  t = %+.2f s', dff_fn, t_s(peak_frame_idx));

%% -------------------------
% INTERACTIVE PIXEL PICKING (time slider over the dF/F reference movie)
% -------------------------
picked = pick_pixels_on_reference(movie, always_nan_mask, t_s, peak_frame_idx, ...
    clim_bg, cmap, mask_color_outside, V1_mask, v1_outline_color, ref_title);

if isempty(picked)
    fprintf('No pixels picked. Nothing to look up.\n');
    return;
end
n_pick = size(picked, 1);

%% -------------------------
% LOOK UP RECEPTIVE FIELD AT EACH PICKED PIXEL
% -------------------------
row = picked(:,1);
col = picked(:,2);
azimuth_deg  = nan(n_pick, 1);
altitude_deg = nan(n_pick, 1);
inside_V1    = false(n_pick, 1);

fprintf('\nReceptive field lookup (from step 6 retinotopic alignment):\n');
for i = 1:n_pick
    azimuth_deg(i)  = azi_stim(row(i), col(i));
    altitude_deg(i) = alt_stim(row(i), col(i));
    if ~isempty(V1_mask), inside_V1(i) = V1_mask(row(i), col(i)); end

    if isnan(azimuth_deg(i)) || isnan(altitude_deg(i))
        fprintf('  #%d  pixel (row=%d, col=%d)  ->  outside retinotopic map coverage (NaN)\n', ...
            i, row(i), col(i));
    else
        v1_str = '';
        if ~isempty(V1_mask)
            if inside_V1(i), v1_str = '  [inside V1]'; else, v1_str = '  [outside V1]'; end
        end
        fprintf('  #%d  pixel (row=%d, col=%d)  ->  azimuth = %+.1f deg, altitude = %+.1f deg%s\n', ...
            i, row(i), col(i), azimuth_deg(i), altitude_deg(i), v1_str);
    end
end

%% -------------------------
% SAVE SUMMARY FIGURE, TABLE, AND .MAT
% -------------------------
[~, dff_tag] = fileparts(dff_fn);
tag = matlab.lang.makeValidName(dff_tag);

fig = plot_lookup_summary(peak_img, always_nan_mask, clim_bg, cmap, mask_color_outside, ...
    azi_stim, alt_stim, V1_mask, v1_outline_color, pick_marker_color, ...
    row, col, ref_title, is_m1);
fig_fname = sprintf('receptive_field_lookup_%s.png', tag);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('\nSaved figure: %s\n', fig_fname);

pixel_index = (1:n_pick)';
result_table = table(pixel_index, row, col, azimuth_deg, altitude_deg, inside_V1);
csv_fname = sprintf('receptive_field_lookup_%s.csv', tag);
writetable(result_table, fullfile(save_dir, csv_fname));
fprintf('Saved table:  %s\n', csv_fname);

mat_fname = sprintf('receptive_field_lookup_%s.mat', tag);
save(fullfile(save_dir, mat_fname), 'result_table', 'day_setup_file', 'dff_fpath');
fprintf('Saved data:   %s\n', mat_fname);

fprintf('\nDone. Outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function ra = load_retino_align(fpath)
% Pull retino_align (azi_stim, alt_stim, V1_mask_stim) out of a step-6
% day_setup .mat, trying the known top-level struct names.
ra = struct('azi_stim', [], 'alt_stim', [], 'V1_mask_stim', []);
S = load(fpath);

if isfield(S, 'day_setup') && isstruct(S.day_setup)
    cand = S.day_setup;
elseif isfield(S, 'reference_mask_and_retino_alignment') && isstruct(S.reference_mask_and_retino_alignment)
    cand = S.reference_mask_and_retino_alignment;
else
    cand = S;
end

if isfield(cand, 'retino_align') && isstruct(cand.retino_align)
    ra_s = cand.retino_align;
elseif isfield(cand, 'azi_stim')
    ra_s = cand;
else
    return;
end

if isfield(ra_s, 'azi_stim'), ra.azi_stim = double(ra_s.azi_stim); end
if isfield(ra_s, 'alt_stim'), ra.alt_stim = double(ra_s.alt_stim); end
if isfield(ra_s, 'V1_mask_stim'), ra.V1_mask_stim = logical(ra_s.V1_mask_stim); end
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

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite values. Same
% convention as steps 5_A/5_B/7_A/7_B/8.
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

function picked = pick_pixels_on_reference(movie, always_nan_mask, t_s, peak_idx, ...
    clim_range, cmap, mask_color, V1_mask, v1_color, title_str)
% Time-slider viewer over the dF/F reference movie. Click pixels to pick
% them for the receptive-field lookup:
%   left-click         -> add the clicked pixel
%   right-click / 'u'   -> undo the most recent pick
%   Enter / Escape      -> finish picking and close the figure
% Returns an N x 2 matrix of [row, col] picked pixels (possibly empty).
[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', ['Pick pixels — ' title_str], ...
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

sgtitle(fig, ['Click pixels to pick them for RF lookup   |   ' ...
    'left-click: add pixel   \cdot   right-click or ''u'': undo last   \cdot   Enter: done']);

picked  = zeros(0, 2);
markers = gobjects(0, 1);

while true
    [x, y, button] = ginput(1);
    if isempty(button)
        break;   % figure closed by the user
    end

    if button == 1   % left click -> add picked pixel
        r = round(y);
        c = round(x);
        if r < 1 || r > H || c < 1 || c > W
            continue;
        end
        picked(end + 1, :) = [r, c];                                          %#ok<AGROW>
        markers(end + 1)   = plot(ax, c, r, 'w+', 'MarkerSize', 12, 'LineWidth', 1.6); %#ok<AGROW>
        fprintf('  Picked pixel (%d, %d)   [%d selected]\n', r, c, size(picked, 1));

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

function set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, k)
[~, ~, T] = size(movie);
k = max(1, min(T, round(k)));
set(img, 'CData', dff_frame_to_rgb(movie(:,:,k), always_nan_mask, clim_range, cmap, mask_color));
set(th, 'String', sprintf('%s | t = %+.2f s', title_str, t_s(k)));
end

function fig = plot_lookup_summary(peak_img, always_nan_mask, dff_clim, dff_cmap, mask_color, ...
    azi_stim, alt_stim, V1_mask, v1_color, marker_color, row, col, dff_title, is_m1)
% Three-panel figure: dF/F reference map, azimuth map, altitude map, all with
% the picked pixels numbered. V1 boundary overlaid on the retino panels.
n_pick = numel(row);
method_tag = '';
if is_m1, method_tag = ' (Method 1)'; end

fig = figure('Color', 'w', 'Position', [40 80 1560 480]);

% --- Panel 1: dF/F reference map ---
ax1 = subplot(1, 3, 1);
image(ax1, dff_frame_to_rgb(peak_img, always_nan_mask, dff_clim, dff_cmap, mask_color));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
visboundaries(ax1, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask), visboundaries(ax1, V1_mask, 'Color', v1_color, 'LineWidth', 1.0); end
colormap(ax1, dff_cmap); clim(ax1, dff_clim); colorbar(ax1);
mark_picks(ax1, row, col, marker_color);
title(ax1, dff_title, 'Interpreter', 'none', 'FontSize', 9);

% --- Panel 2: azimuth map ---
ax2 = subplot(1, 3, 2);
imagesc(ax2, azi_stim); axis(ax2, 'image'); set(ax2, 'YDir', 'normal');
colormap(ax2, parula); cb2 = colorbar(ax2); cb2.Label.String = 'Azimuth (deg)';
hold(ax2, 'on');
if ~isempty(V1_mask), visboundaries(ax2, V1_mask, 'Color', [1 1 1], 'LineWidth', 1.2); end
mark_picks(ax2, row, col, [0 0 0]);
title(ax2, 'Azimuth map');

% --- Panel 3: altitude map ---
ax3 = subplot(1, 3, 3);
imagesc(ax3, alt_stim); axis(ax3, 'image'); set(ax3, 'YDir', 'normal');
colormap(ax3, parula); cb3 = colorbar(ax3); cb3.Label.String = 'Altitude (deg)';
hold(ax3, 'on');
if ~isempty(V1_mask), visboundaries(ax3, V1_mask, 'Color', [1 1 1], 'LineWidth', 1.2); end
mark_picks(ax3, row, col, [0 0 0]);
title(ax3, 'Altitude map');

sgtitle(fig, sprintf('Receptive field lookup for %d picked pixel(s)%s', n_pick, method_tag), ...
    'Interpreter', 'none');
end

function mark_picks(ax, row, col, txt_color)
for i = 1:numel(row)
    plot(ax, col(i), row(i), 'ko', 'MarkerSize', 14, 'LineWidth', 1.2, ...
        'MarkerFaceColor', 'none');
    plot(ax, col(i), row(i), 'w+', 'MarkerSize', 11, 'LineWidth', 1.6);
    text(ax, col(i) + 4, row(i) - 4, sprintf('%d', i), ...
        'Color', txt_color, 'FontWeight', 'bold', 'FontSize', 9, ...
        'BackgroundColor', [1 1 1 0.6], 'Margin', 0.5);
end
end