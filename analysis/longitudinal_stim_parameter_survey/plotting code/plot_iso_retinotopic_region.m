%% plot_iso_retinotopic_region.m
% Click one point on a step-5_A dF/F figure and outline every pixel whose
% receptive field is close to that point's.
%
% Step 9 (receptive_field_lookup_9.m) reads the receptive field OF a clicked
% pixel. This script does the reverse lookup: it takes the clicked pixel's
% (azimuth, altitude) from the step-6 retinotopic alignment and outlines
% ALL pixels whose (azimuth, altitude) falls within a tolerance of it —
% typically one patch per visual area (V1, LM, AL, ...) representing the
% same part of visual space.
%
%   clicked pixel -> (azi0, alt0) from day_setup.retino_align
%   region        =  |azi - azi0| <= tol_azi  AND  |alt - alt0| <= tol_alt
%
% With the default 10 deg tolerance, clicking a pixel at (30, 20) outlines
% everywhere with azimuth in [20, 40] and altitude in [10, 30].
%
% The region updates live: click again to move the point, 'u' to clear,
% Enter when satisfied. The final figure is the same step-5_A dF/F frame
% you were viewing, with the region boundary drawn on top.
%
% Inputs (selected interactively):
%   - day_setup .mat from step 6 (retino_align.azi_stim / .alt_stim,
%     optionally .V1_mask_stim)
%   - one mean dF/F .mat from step 5_A (or 5_B), same H x W pixel grid
%
% The figure is shown on screen first; only afterwards are you asked where
% to save it (Cancel = keep the figure, save nothing).

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside = [0.15 0.15 0.15];
v1_outline_color   = [0.10 0.85 0.30];
region_color       = [1.00 0.00 1.00];   % magenta — absent from jet, so it
                                         % stays legible over red/orange
region_line_width  = 1.5;
pick_marker_color  = [1.00 1.00 1.00];

% Region clean-up. Both default to 0, so the outlined region is exactly the
% set of pixels meeting the angle criterion — nothing added, nothing
% dropped. Raise min_region_px to suppress isolated speckle at map edges;
% raise smooth_close_px to close pinholes (both alter what is shown).
min_region_px      = 0;    % drop connected components smaller than this
smooth_close_px    = 0;    % imclose radius, in pixels

restrict_to_brain_mask = true;   % ignore pixels outside the dF/F brain mask

%% -------------------------
% LOAD DAY_SETUP (STEP 6): azi_stim / alt_stim / V1_mask_stim
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
fprintf('Loaded retinotopic alignment from:\n  %s\n  Map size: %d x %d\n', day_setup_file, H, W);

%% -------------------------
% SELECT THE dF/F FILE (STEP 5_A / 5_B)
% -------------------------
[dff_fn, dff_fp] = uigetfile('*.mat', ...
    'Select a mean dF/F .mat from step 5_A (or 5_B) for this channel & current');
if isequal(dff_fn, 0), error('No dF/F file selected.'); end
dff_fpath = fullfile(dff_fp, dff_fn);

S = load(dff_fpath);
if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', dff_fpath); end
assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', dff_fpath);
t_s = double(S.t_s(:)');

[Hm, Wm, T] = size(movie);
assert(Hm == H && Wm == W, ...
    ['dF/F movie size (%dx%d) does not match the retinotopic map size (%dx%d).\n' ...
     'Both must come from the same stim-space pixel grid (step 6 day_setup + step 5_A/5_B).'], ...
    Hm, Wm, H, W);

always_nan_mask = all(isnan(movie), 3);
% Whole frame when the restriction is switched off
brain_mask      = ~always_nan_mask | ~restrict_to_brain_mask;

if ~isempty(V1_mask) && ~isequal(size(V1_mask), [H W])
    warning('V1_mask_stim size does not match the map size — dropping V1 overlay.');
    V1_mask = [];
end

%% -------------------------
% TOLERANCE (deg) — half-width of the accepted angle window in each dimension
% -------------------------
tol_ans = inputdlg( ...
    {'Azimuth tolerance (± deg):', 'Altitude tolerance (± deg):'}, ...
    'Receptive-field match tolerance', [1 60], {'10', '10'});
if isempty(tol_ans), error('Tolerance not specified. Cancelled.'); end
tol_azi = str2double(tol_ans{1});
tol_alt = str2double(tol_ans{2});
assert(isfinite(tol_azi) && tol_azi > 0 && isfinite(tol_alt) && tol_alt > 0, ...
    'Both tolerances must be positive numbers.');
fprintf('Tolerance: azimuth +/-%g deg, altitude +/-%g deg\n', tol_azi, tol_alt);

%% -------------------------
% REFERENCE FRAME TO OPEN ON (most active post-stim frame, same as step 9)
% -------------------------
post_idx = find(t_s >= 0);
if isempty(post_idx), post_idx = 1:numel(t_s); end
mean_abs_post  = squeeze(mean(mean(abs(movie(:,:,post_idx)), 1, 'omitnan'), 2, 'omitnan'));
[~, pk_loc]    = max(mean_abs_post);
start_frame_idx = post_idx(pk_loc);

clim_bg   = data_clim(movie, ~always_nan_mask);
cmap      = jet(256);
[~, dff_tag] = fileparts(dff_fn);
ref_title = sprintf('%s', dff_tag);

%% -------------------------
% CLICK A POINT — the matching region updates live
% -------------------------
sel = pick_point_with_region(movie, always_nan_mask, brain_mask, t_s, start_frame_idx, ...
    clim_bg, cmap, mask_color_outside, V1_mask, v1_outline_color, ...
    azi_stim, alt_stim, tol_azi, tol_alt, min_region_px, smooth_close_px, ...
    region_color, region_line_width, pick_marker_color, ref_title);

if isempty(sel)
    fprintf('No point selected. Nothing to plot.\n');
    return;
end

region_mask = sel.region_mask;
azi_win = [sel.azi0 - tol_azi, sel.azi0 + tol_azi];
alt_win = [sel.alt0 - tol_alt, sel.alt0 + tol_alt];

cc = bwconncomp(region_mask);
comp_px = cellfun(@numel, cc.PixelIdxList);
fprintf('\nClicked pixel (row=%d, col=%d)  ->  azimuth %+.1f deg, altitude %+.1f deg\n', ...
    sel.row, sel.col, sel.azi0, sel.alt0);
fprintf('Matching window: azimuth [%+.1f, %+.1f] deg, altitude [%+.1f, %+.1f] deg\n', ...
    azi_win(1), azi_win(2), alt_win(1), alt_win(2));
fprintf('Region: %d pixel(s) in %d separate patch(es)', sum(region_mask(:)), cc.NumObjects);
if ~isempty(comp_px)
    fprintf(' — sizes: %s px', mat2str(sort(comp_px, 'descend')));
end
fprintf('\n');
if ~isempty(V1_mask)
    fprintf('  %d of those pixel(s) fall inside V1.\n', sum(region_mask(:) & V1_mask(:)));
end

%% -------------------------
% FINAL FIGURE — the step-5_A frame you were viewing, region outlined
% -------------------------
frame_idx = sel.frame_idx;

fig = figure('Color', 'w', 'Position', [100 80 820 720], ...
    'Name', sprintf('Iso-retinotopic region — %s', dff_tag));
ax = axes(fig);
image(ax, dff_frame_to_rgb(movie(:,:,frame_idx), always_nan_mask, clim_bg, cmap, mask_color_outside));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask)
    visboundaries(ax, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
end
if any(region_mask(:))
    visboundaries(ax, region_mask, 'Color', region_color, 'LineWidth', region_line_width);
end
plot(ax, sel.col, sel.row, '+', 'Color', pick_marker_color, 'MarkerSize', 13, 'LineWidth', 1.8);
colormap(ax, cmap); clim(ax, clim_bg);
cb = colorbar(ax); cb.Label.String = '\DeltaF/F';

title(ax, sprintf('%s  |  t = %+.2f s', dff_tag, t_s(frame_idx)), ...
    'Interpreter', 'none', 'FontSize', 10);
subtitle(ax, sprintf(['clicked (azi %+.1f, alt %+.1f)  |  region: azi [%+.1f, %+.1f], ' ...
    'alt [%+.1f, %+.1f] deg  |  %d px in %d patch(es)'], ...
    sel.azi0, sel.alt0, azi_win(1), azi_win(2), alt_win(1), alt_win(2), ...
    sum(region_mask(:)), cc.NumObjects), 'Interpreter', 'none', 'FontSize', 9);

drawnow;

%% -------------------------
% OUTPUT — asked for only after the figure is on screen
% -------------------------
save_choice = questdlg('Save this plot?', 'Save output', 'Save', 'Do not save', 'Save');
if ~strcmp(save_choice, 'Save')
    fprintf('\nNot saved. Figure left open.\n');
    return;
end

save_dir = uigetdir(dff_fp, 'Select output folder for the plot (Cancel = do not save)');
if isequal(save_dir, 0)
    fprintf('\nNo output folder selected — not saved. Figure left open.\n');
    return;
end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

base_fname = sprintf('iso_retino_region_%s_azi%+.0f_alt%+.0f_tol%gx%g', ...
    matlab.lang.makeValidName(dff_tag), sel.azi0, sel.alt0, tol_azi, tol_alt);
base_fname = strrep(strrep(base_fname, '+', 'p'), '-', 'm');

exportgraphics(fig, fullfile(save_dir, [base_fname '.png']), 'Resolution', 150);
fprintf('\nSaved figure: %s\n', fullfile(save_dir, [base_fname '.png']));

clicked_row = sel.row;
clicked_col = sel.col;
azimuth_deg  = sel.azi0;
altitude_deg = sel.alt0;
frame_time_s = t_s(frame_idx);
n_region_px  = sum(region_mask(:));
n_patches    = cc.NumObjects;
save(fullfile(save_dir, [base_fname '.mat']), ...
    'region_mask', 'clicked_row', 'clicked_col', 'azimuth_deg', 'altitude_deg', ...
    'azi_win', 'alt_win', 'tol_azi', 'tol_alt', 'frame_idx', 'frame_time_s', ...
    'n_region_px', 'n_patches', 'min_region_px', 'smooth_close_px', ...
    'restrict_to_brain_mask', 'day_setup_file', 'dff_fpath');
fprintf('Saved data:   %s\n', fullfile(save_dir, [base_fname '.mat']));

%% =========================
% LOCAL FUNCTIONS
%% =========================

function [mask, n_comp] = compute_iso_region(azi, alt, azi0, alt0, tol_azi, tol_alt, ...
    brain_mask, min_px, close_px)
% Every pixel whose receptive field sits inside the (azi0 +/- tol_azi,
% alt0 +/- tol_alt) window. Pixels with no retinotopic value (NaN) never
% match, and matches are confined to the brain mask.
mask = abs(azi - azi0) <= tol_azi & abs(alt - alt0) <= tol_alt;
mask = mask & isfinite(azi) & isfinite(alt) & brain_mask;
if close_px > 0
    mask = imclose(mask, strel('disk', close_px)) & brain_mask;
end
if min_px > 0
    mask = bwareaopen(mask, min_px);
end
if nargout > 1
    cc = bwconncomp(mask);
    n_comp = cc.NumObjects;
end
end

function sel = pick_point_with_region(movie, always_nan_mask, brain_mask, t_s, start_idx, ...
    clim_range, cmap, mask_color, V1_mask, v1_color, azi, alt, tol_azi, tol_alt, ...
    min_px, close_px, region_color, region_lw, marker_color, title_str)
% Time-slider viewer over the dF/F movie. Clicking a pixel looks up its
% (azimuth, altitude) and outlines every pixel within tolerance of it,
% redrawing on each click:
%   left-click        -> move the point, recompute the region
%   right-click / 'u' -> clear the current point
%   Enter / Escape    -> accept and close
% Returns a struct with .row .col .azi0 .alt0 .region_mask .frame_idx, or []
% if nothing was selected / the figure was closed.
[H, W, T] = size(movie);
sel = [];

fig = figure('Color', 'w', 'Name', ['Click a point — ' title_str], ...
    'Position', [80 60 820 760]);
ax = axes(fig, 'Position', [0.08 0.13 0.80 0.78]);

img = image(ax, dff_frame_to_rgb(movie(:,:,start_idx), always_nan_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
colormap(ax, cmap); clim(ax, clim_range); colorbar(ax);
th = title(ax, '', 'Interpreter', 'none');
set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, start_idx);

sld = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.12 0.03 0.72 0.035], ...
    'Min', 1, 'Max', T, 'Value', start_idx, ...
    'SliderStep', [1 / max(1, T - 1), 5 / max(1, T - 1)], ...
    'Callback', @(src, ~) set_ref_frame(img, th, movie, always_nan_mask, t_s, ...
        clim_range, cmap, mask_color, title_str, get(src, 'Value')));

sgtitle(fig, ['Click a pixel to outline everywhere with a similar receptive field   |   ' ...
    'left-click: place   \cdot   right-click or ''u'': clear   \cdot   Enter: done']);

h_region = [];
h_mark   = [];

while true
    if ~isvalid(fig), sel = []; return; end
    [x, y, button] = ginput(1);
    if isempty(button)
        break;   % figure closed by the user
    end

    if button == 1                      % place / move the point
        r = round(y); c = round(x);
        if r < 1 || r > H || c < 1 || c > W
            continue;                   % click landed off the image (e.g. on the slider)
        end
        azi0 = azi(r, c);
        alt0 = alt(r, c);
        if ~isfinite(azi0) || ~isfinite(alt0)
            fprintf('  Pixel (%d, %d) has no retinotopic value (NaN) — pick another.\n', r, c);
            continue;
        end

        [mask, n_comp] = compute_iso_region(azi, alt, azi0, alt0, tol_azi, tol_alt, ...
            brain_mask, min_px, close_px);
        fprintf(['  Pixel (%d, %d): azi %+.1f, alt %+.1f  ->  azi [%+.1f, %+.1f], ' ...
            'alt [%+.1f, %+.1f]  ->  %d px in %d patch(es)\n'], ...
            r, c, azi0, alt0, azi0 - tol_azi, azi0 + tol_azi, ...
            alt0 - tol_alt, alt0 + tol_alt, sum(mask(:)), n_comp);

        if ~isempty(h_region) && isvalid(h_region), delete(h_region); end
        if ~isempty(h_mark)   && isvalid(h_mark),   delete(h_mark);   end
        h_region = [];
        if any(mask(:))
            h_region = visboundaries(ax, mask, 'Color', region_color, 'LineWidth', region_lw);
        end
        h_mark = plot(ax, c, r, '+', 'Color', marker_color, 'MarkerSize', 13, 'LineWidth', 1.8);
        drawnow;

        sel = struct('row', r, 'col', c, 'azi0', azi0, 'alt0', alt0, ...
            'region_mask', mask, 'frame_idx', start_idx);

    elseif button == 3 || button == double('u') || button == 8   % clear
        if ~isempty(h_region) && isvalid(h_region), delete(h_region); end
        if ~isempty(h_mark)   && isvalid(h_mark),   delete(h_mark);   end
        h_region = []; h_mark = [];
        sel = [];
        fprintf('  Cleared.\n');
        drawnow;

    elseif button == 13 || button == 27   % Enter / Escape -> done
        break;
    end
end

% Report the region on whichever frame was on screen when picking finished
if ~isempty(sel) && isvalid(sld)
    sel.frame_idx = max(1, min(T, round(get(sld, 'Value'))));
end
if isvalid(fig), close(fig); end
end

function ra = load_retino_align(fpath)
% Pull retino_align (azi_stim, alt_stim, V1_mask_stim) out of a step-6
% day_setup .mat, trying the known top-level struct names. Same search as
% get_v1_boundary / step 9, kept local so this script runs from the
% "plotting code" folder without the pipeline folder on the path.
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

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie. Same convention as steps 5_A/5_B/7_A/7_B/8/9.
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
