%% plot_retino_maps_native_orientation.m
% Plotting-only tool: re-renders retinotopic-mapping results (SignMapper
% output) so the brain appears in the SAME ORIENTATION as the wide-field
% (WF) stim-day imaging experiment -- i.e. the actual rotation/mirroring
% difference between the retino camera and the WF camera is corrected, not
% just a YDir flip.
%
% Orientation is corrected by reusing the affine transform already fitted
% in step 6 (retino_alignment_with_brain_mask_6.m via cpselect control
% points): day_setup.retino_align.tform. Every retino-space field (azi,
% alt, VFS_raw, the visual-area boundary map, V1_mask_retino, and the
% retino reference image) is warped through that SAME transform with a
% shared, auto-sized ("loose") output canvas -- so nothing is cropped and
% the output is NOT forced onto the WF camera's exact pixel dimensions,
% only its ORIENTATION.
%
% Outputs 4 figures:
%   1. Azimuth map            (azi, warped)
%   2. Altitude map           (alt, warped)
%   3. Visual Field Sign map  (VFS_raw, warped) -- the RAW VFS signal, not
%      the processed/segmented patch map. VFS_raw is usually NOT saved
%      inside retino_registration_ready.mat (only VFS_processed and
%      VFS_boundaries are -- see retino_inputcombine.m); it lives in the
%      separate VFS_maps.mat that SignMapperModifR.saveSignMaps() writes.
%      This script prompts for that file if VFS_raw isn't already present.
%   4. ALL visual-area boundaries (not just V1): the full boundary map
%      from the automated sign-map segmentation (VFS_boundaries, falling
%      back to an edge-detection of VFS_processed if VFS_boundaries is
%      missing) overlaid on the retino reference image, warped into the
%      same orientation, with V1 (V1_mask_retino) outlined on top in a
%      contrasting color.
%
% Why day_setup.retino_align.*_stim looked wrong before (for reference):
%   day_setup's VFS_stim is NOT a warped copy of SignMapper's VFS_raw/
%   VFS_processed -- step 6 recomputes VFS from scratch via a plain
%   gradient() on azi/alt, which is much noisier. Warping VFS_raw directly
%   (this script) avoids that problem entirely.
%
% Inputs (selected interactively):
%   1. retino_registration_ready.mat / retino_session_output.mat
%      (SignMapper output: azi, alt, ReferenceImage, VFS_processed,
%      VFS_boundaries, and V1_mask_retino if step 6 has already appended it)
%   2. day_setup.mat (from step 6) -- REQUIRED, supplies retino_align.tform
%      and, if needed, a fallback V1_mask_retino
%   3. VFS_maps.mat -- only asked for if VFS_raw isn't already available

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
v1_color             = [1.00 0.85 0.10];   % V1 boundary
region_bound_color   = [0.20 0.95 0.95];   % all-area boundary overlay color (figure 4)
region_bound_dilate_px = 1;                % thicken the 1px boundary map for visibility
font_size_title      = 13;

%% -------------------------
% SELECT RETINO FILE (SignMapper output)
% -------------------------
[ret_name, ret_path] = uigetfile('*.mat', ...
    'Select retino_registration_ready.mat or retino_session_output.mat (SignMapper output)');
if isequal(ret_name, 0), error('No retino file selected.'); end
retino_file = fullfile(ret_path, ret_name);

S = load(retino_file);
if isfield(S, 'registration_ready'), R = S.registration_ready;
elseif isfield(S, 'out'),            R = S.out;
elseif isfield(S, 'maps'),           R = S.maps;
else,                                R = S;
end

azi = get_field_or_empty(R, 'azi');
alt = get_field_or_empty(R, 'alt');
if isempty(azi), azi = get_field_or_empty(S, 'azi'); end
if isempty(alt), alt = get_field_or_empty(S, 'alt'); end
assert(~isempty(azi) && ~isempty(alt), 'Retino file must contain azi and alt.');
[H, W] = size(azi);

refImg = get_field_or_empty(R, 'ReferenceImage');
if isempty(refImg), refImg = get_field_or_empty(S, 'ReferenceImage'); end
assert(~isempty(refImg), 'Retino file missing ReferenceImage.');
if size(refImg,1) ~= H || size(refImg,2) ~= W
    warning('ReferenceImage size (%dx%d) does not match azi/alt size (%dx%d) -- resizing ReferenceImage only.', ...
        size(refImg,1), size(refImg,2), H, W);
    refImg = imresize(refImg, [H W], 'bilinear');
end
refImgG = mat2gray(toGrayDouble(refImg));

VFS_processed = get_field_or_empty(R, 'VFS_processed');
if isempty(VFS_processed), VFS_processed = get_field_or_empty(S, 'VFS_processed'); end
VFS_boundaries = get_field_or_empty(R, 'VFS_boundaries');
if isempty(VFS_boundaries), VFS_boundaries = get_field_or_empty(S, 'VFS_boundaries'); end
% SignMapperModifR resizes its sign-map outputs to match whatever
% reference image (obj.ref_img) was active during THAT sign-mapping run --
% if that differs from the camera binning/resolution azi/alt were saved
% at (e.g. a different processing session), these end up a different size
% than azi/alt. Resize them to match rather than silently dropping them.
VFS_processed  = resize_to_match(VFS_processed,  [H W], 'nearest', 'VFS_processed');
VFS_boundaries = resize_to_match(VFS_boundaries, [H W], 'nearest', 'VFS_boundaries');

VFS_raw = get_field_or_empty(R, 'VFS_raw');
if isempty(VFS_raw), VFS_raw = get_field_or_empty(S, 'VFS_raw'); end
VFS_raw = resize_to_match(VFS_raw, [H W], 'bilinear', 'VFS_raw');

V1_mask_retino = get_field_or_empty(R, 'V1_mask_retino');
if isempty(V1_mask_retino), V1_mask_retino = get_field_or_empty(S, 'V1_mask_retino'); end

fprintf('Loaded retino file: %s  (native size %d x %d)\n', ret_name, H, W);

%% -------------------------
% SELECT day_setup.mat (REQUIRED -- supplies the retino->WF orientation tform)
% -------------------------
[ds_fn, ds_fp] = uigetfile('*day_setup*.mat', ...
    'Select day_setup.mat (from step 6) -- provides the retino -> WF orientation transform');
if isequal(ds_fn, 0), error('No day_setup.mat selected -- cannot determine orientation without it.'); end
DS = load(fullfile(ds_fp, ds_fn));
assert(isfield(DS, 'day_setup') && isfield(DS.day_setup, 'retino_align') && ...
    isfield(DS.day_setup.retino_align, 'tform') && ~isempty(DS.day_setup.retino_align.tform), ...
    ['Selected file has no day_setup.retino_align.tform. Run step 6 ' ...
     '(retino_alignment_with_brain_mask_6.m) first to fit the retino -> WF alignment.']);
tform = DS.day_setup.retino_align.tform;
fprintf('Loaded orientation transform from: %s\n', ds_fn);

if isempty(V1_mask_retino) && isfield(DS.day_setup.retino_align, 'V1_mask_retino')
    V1_mask_retino = DS.day_setup.retino_align.V1_mask_retino;
    fprintf('Loaded V1_mask_retino from day_setup (not present in retino file).\n');
end
if ~isempty(V1_mask_retino)
    V1_mask_retino = logical(V1_mask_retino);
    if ~isequal(size(V1_mask_retino), [H W])
        V1_mask_retino = imresize(V1_mask_retino, [H W], 'nearest') > 0.5;
    end
end

%% -------------------------
% VFS_raw: prompt for VFS_maps.mat if not already available
% (retino_registration_ready.mat normally only carries VFS_processed /
% VFS_boundaries -- VFS_raw lives in the separate VFS_maps.mat that
% SignMapperModifR.saveSignMaps() writes)
% -------------------------
if isempty(VFS_raw)
    [vfs_fn, vfs_fp] = uigetfile('*VFS_maps*.mat', ...
        'Select VFS_maps.mat (contains VFS_raw from the retinotopic mapping experiment)');
    if isequal(vfs_fn, 0)
        warning('No VFS_maps.mat selected -- figure 3 (VFS raw) will be skipped.');
    else
        VM = load(fullfile(vfs_fp, vfs_fn));
        VFS_raw = get_field_or_empty(VM, 'VFS_raw');
        assert(~isempty(VFS_raw), 'Selected file has no VFS_raw:\n  %s', fullfile(vfs_fp, vfs_fn));
        VFS_raw = resize_to_match(VFS_raw, [H W], 'bilinear', 'VFS_raw');
        fprintf('Loaded VFS_raw from: %s\n', vfs_fn);
    end
end

%% -------------------------
% VISUAL-AREA BOUNDARY MASK (native retino space, before warping)
% Prefer VFS_boundaries; otherwise derive edges from VFS_processed.
% -------------------------
if ~isempty(VFS_boundaries)
    region_bound_native = VFS_boundaries > 0.5;
elseif ~isempty(VFS_processed)
    region_bound_native = patch_edges(VFS_processed);
    fprintf('VFS_boundaries not available -- derived area boundaries from VFS_processed instead.\n');
else
    region_bound_native = [];
    warning('Neither VFS_boundaries nor VFS_processed available -- figure 4 will show V1 only.');
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(ret_path, 'Select output folder for the retino figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

[~, tag] = fileparts(ret_name);

%% -------------------------
% WARP EVERYTHING THROUGH THE SAME TRANSFORM, SAME (LOOSE) OUTPUT CANVAS
% -------------------------
[azi_w, Rout] = imwarp(azi, tform, 'FillValues', NaN);
alt_w         = imwarp(alt, tform, 'OutputView', Rout, 'FillValues', NaN);
refImg_w      = imwarp(refImgG, tform, 'OutputView', Rout, 'FillValues', 0.15);

VFS_raw_w = [];
if ~isempty(VFS_raw) && isequal(size(VFS_raw), [H W])
    VFS_raw_w = imwarp(VFS_raw, tform, 'OutputView', Rout, 'FillValues', NaN);
elseif ~isempty(VFS_raw)
    warning('VFS_raw size does not match azi/alt size -- skipping figure 3.');
end

V1_mask_w = [];
if ~isempty(V1_mask_retino)
    V1_mask_w = imwarp(double(V1_mask_retino), tform, 'OutputView', Rout, ...
        'Interp', 'nearest', 'FillValues', 0) > 0.5;
end

region_bound_w = [];
if ~isempty(region_bound_native)
    region_bound_w = imwarp(double(region_bound_native), tform, 'OutputView', Rout, ...
        'Interp', 'nearest', 'FillValues', 0) > 0.5;
    if region_bound_dilate_px > 0
        region_bound_w = imdilate(region_bound_w, strel('disk', region_bound_dilate_px));
    end
end

fprintf('Warped output canvas: %d x %d\n', Rout.ImageSize(1), Rout.ImageSize(2));

%% -------------------------
% FIGURE 1: AZIMUTH MAP
% -------------------------
plot_scalar_map(azi_w, V1_mask_w, v1_color, parula(256), data_clim2d(azi_w), ...
    'Azimuth (deg)', sprintf('Azimuth map (WF orientation)  |  %s', tag), ...
    fullfile(save_dir, sprintf('%s_azimuth_WForient.png', tag)), font_size_title);

%% -------------------------
% FIGURE 2: ALTITUDE MAP
% -------------------------
plot_scalar_map(alt_w, V1_mask_w, v1_color, parula(256), data_clim2d(alt_w), ...
    'Altitude (deg)', sprintf('Altitude map (WF orientation)  |  %s', tag), ...
    fullfile(save_dir, sprintf('%s_altitude_WForient.png', tag)), font_size_title);

%% -------------------------
% FIGURE 3: VISUAL FIELD SIGN (VFS) MAP -- raw signal
% -------------------------
if ~isempty(VFS_raw_w)
    plot_scalar_map(VFS_raw_w, V1_mask_w, v1_color, jet(256), [-1 1], ...
        'VFS (raw)', sprintf('Visual Field Sign, raw (WF orientation)  |  %s', tag), ...
        fullfile(save_dir, sprintf('%s_VFSraw_WForient.png', tag)), font_size_title);
end

%% -------------------------
% FIGURE 4: ALL VISUAL-AREA BOUNDARIES ON THE RETINO REFERENCE IMAGE
% -------------------------
plot_region_overlay(refImg_w, region_bound_w, V1_mask_w, region_bound_color, v1_color, ...
    sprintf('Visual areas (WF orientation)  |  %s', tag), ...
    fullfile(save_dir, sprintf('%s_visual_areas_WForient.png', tag)), font_size_title);

fprintf('\nDone. Outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function v = get_field_or_empty(S, name)
if isfield(S, name) && ~isempty(S.(name))
    v = S.(name);
else
    v = [];
end
end

function X = resize_to_match(X, targetSize, interp_method, field_name)
% Resizes X to targetSize [H W] if its size differs, with a warning
% explaining why: SignMapperModifR resizes its sign-map outputs
% (VFS_raw/VFS_processed/VFS_boundaries) to match whatever reference image
% was active during THAT sign-mapping run, which can be a different
% camera binning/resolution than azi/alt were saved at if they came from a
% different processing session.
if isempty(X) || isequal(size(X), targetSize)
    return;
end
warning(['%s size (%dx%d) does not match azi/alt size (%dx%d) -- resizing to match. ' ...
    'This happens when the sign-map outputs (SignMapperModifR) were computed at a ' ...
    'different camera binning/resolution than azi/alt were saved at.'], ...
    field_name, size(X,1), size(X,2), targetSize(1), targetSize(2));
X = imresize(X, targetSize, interp_method);
end

function G = toGrayDouble(I)
if ~isa(I, 'double'), I = im2double(I); end
if ndims(I) == 3 && size(I,3) == 3
    I = mat2gray(I);
    G = 0.2989*I(:,:,1) + 0.5870*I(:,:,2) + 0.1140*I(:,:,3);
elseif ndims(I) == 3
    G = I(:,:,1);
else
    G = I;
end
end

function bmask = patch_edges(labelMap)
% 1-pixel-wide boundary mask between differently-valued regions of a
% labeled/patch map (e.g. VFS_processed) -- used when a dedicated
% VFS_boundaries field isn't available.
se = ones(3);
bmask = (labelMap ~= imdilate(labelMap, se)) | (labelMap ~= imerode(labelMap, se));
end

function cl = data_clim2d(M)
% Autoscale color limits to the min/max of finite values of a 2D map.
v = M(isfinite(M));
if isempty(v)
    cl = [-1 1];
    return;
end
lo = min(v); hi = max(v);
if ~(hi > lo), cl = [-1 1]; else, cl = [lo hi]; end
end

function plot_scalar_map(data, V1_mask, v1_color, cmap, clim_range, cbar_label, ...
    fig_title, out_png, font_size_title)
% One figure: a 2D scalar retino field (azimuth / altitude / VFS), already
% warped into WF orientation, V1 boundary drawn on top if available --
% axis image / axis off / YDir normal (matches the brain-mask convention).
[H, W] = size(data);

fig = figure('Color', 'w', 'Position', [100 100 750 650]);
ax = axes(fig);
imagesc(ax, data);
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.5);
end
colormap(ax, cmap); clim(ax, clim_range);
cb = colorbar(ax);
cb.Label.String = cbar_label;
title(ax, fig_title, 'Interpreter', 'none', 'FontSize', font_size_title);

exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', out_png);
end

function plot_region_overlay(refImgG, region_bound, V1_mask, region_bound_color, v1_color, ...
    fig_title, out_png, font_size_title)
% One figure: the grayscale retino reference image (already warped into WF
% orientation), with every visual-area boundary from the automated
% sign-map segmentation painted on top (region_bound -- includes V1 AND
% higher areas such as LM, AL, ...), plus the manually confirmed V1
% boundary outlined in a contrasting color. axis image / axis off /
% YDir normal.
[H, W] = size(refImgG);
rgb = repmat(refImgG, 1, 1, 3);

if ~isempty(region_bound) && isequal(size(region_bound), [H W])
    for c = 1:3
        chan = rgb(:, :, c);
        chan(region_bound) = region_bound_color(c);
        rgb(:, :, c) = chan;
    end
end

fig = figure('Color', 'w', 'Position', [100 100 750 650]);
ax = axes(fig);
image(ax, rgb);
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 2.0);
end
title(ax, fig_title, 'Interpreter', 'none', 'FontSize', font_size_title);

exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', out_png);
end