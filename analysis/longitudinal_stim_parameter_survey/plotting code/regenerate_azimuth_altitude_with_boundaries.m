%% regenerate_azimuth_altitude_with_boundaries.m
% Regenerates the azimuth_map.png / altitude_map.png figures for an
% EXISTING day_setup.mat (produced by an OLDER version of step 6, before
% retino_alignment_with_brain_mask_6.m was updated to overlay ALL
% visual-area boundaries, not just V1) -- WITHOUT re-running step 6's
% cpselect alignment.
%
% How it avoids re-aligning:
%   day_setup.retino_align.tform is the affine transform step 6 already
%   fitted (via cpselect) from retino space to stim space. This script
%   reuses that exact transform. It re-derives a clean, properly
%   nearest-neighbor-warped visual-area boundary mask by re-reading the
%   ORIGINAL retino_registration_ready.mat (path saved in
%   day_setup.retino_source_file) and warping its VFS_boundaries (or an
%   edge-detection of VFS_processed if VFS_boundaries isn't available)
%   through that saved tform -- exactly what the updated step 6 does, just
%   without repeating the manual point-selection step.
%
% Output: {subject}_{date}_azimuth_map.png and {subject}_{date}_altitude_map.png,
% each with ALL visual-area boundaries (orange) + V1 (white) overlaid, in
% a folder you choose. Optionally also updates the day_setup.mat itself
% with the corrected retOverlay_stim field, if you confirm.

close all; clc; clear; fclose('all');

%% -------------------------
% SELECT day_setup.mat
% -------------------------
[ds_fn, ds_fp] = uigetfile('*day_setup*.mat', 'Select an existing day_setup.mat (from step 6)');
if isequal(ds_fn, 0), error('No file selected.'); end
ds_path = fullfile(ds_fp, ds_fn);

DS = load(ds_path);
assert(isfield(DS, 'day_setup') && isfield(DS.day_setup, 'retino_align'), ...
    'Selected file does not contain a day_setup.retino_align struct:\n  %s', ds_path);
day_setup = DS.day_setup;
RA = day_setup.retino_align;

assert(isfield(RA, 'tform') && ~isempty(RA.tform), ...
    'day_setup.retino_align.tform is missing -- cannot re-warp without re-running step 6.');
tform = RA.tform;

azi_stim = get_field_or_empty(RA, 'azi_stim');
alt_stim = get_field_or_empty(RA, 'alt_stim');
assert(~isempty(azi_stim) && ~isempty(alt_stim), 'day_setup.retino_align.azi_stim/alt_stim are missing.');
[H, W] = size(azi_stim);
Rfixed = imref2d([H W]);

V1_mask_stim = get_field_or_empty(RA, 'V1_mask_stim');
if ~isempty(V1_mask_stim), V1_mask_stim = logical(V1_mask_stim); end

subject_id = get_field_or_empty(day_setup, 'subject_id');
date_str   = get_field_or_empty(day_setup, 'date_str');
if isempty(subject_id), subject_id = 'subject'; end
if isempty(date_str),   date_str   = 'date';    end

fprintf('Loaded day_setup: %s\n', ds_fn);
fprintf('  %s %s  |  stim-space size %d x %d\n', subject_id, date_str, H, W);

%% -------------------------
% LOCATE THE ORIGINAL RETINO SOURCE FILE (for a clean boundary map)
% -------------------------
retino_file = get_field_or_empty(day_setup, 'retino_source_file');
if isempty(retino_file) || ~exist(retino_file, 'file')
    if ~isempty(retino_file)
        fprintf('Recorded retino source file not found:\n  %s\n', retino_file);
    end
    [ret_fn, ret_fp] = uigetfile('*.mat', ...
        'Locate the original retino_registration_ready.mat / retino_session_output.mat');
    if isequal(ret_fn, 0), error('No retino file selected -- cannot rebuild the boundary map.'); end
    retino_file = fullfile(ret_fp, ret_fn);
end
fprintf('Using retino source file:\n  %s\n', retino_file);

S = load(retino_file);
if isfield(S, 'registration_ready'), R = S.registration_ready;
elseif isfield(S, 'out'),            R = S.out;
elseif isfield(S, 'maps'),           R = S.maps;
else,                                R = S;
end

azi_native = get_field_or_empty(R, 'azi');
if isempty(azi_native), azi_native = get_field_or_empty(S, 'azi'); end
assert(~isempty(azi_native), 'Retino source file must contain azi (used only to fix native H x W).');
retino_target_size = size(azi_native);

VFS_boundaries_native = get_field_or_empty(R, 'VFS_boundaries');
if isempty(VFS_boundaries_native), VFS_boundaries_native = get_field_or_empty(S, 'VFS_boundaries'); end
VFS_processed_native = get_field_or_empty(R, 'VFS_processed');
if isempty(VFS_processed_native), VFS_processed_native = get_field_or_empty(S, 'VFS_processed'); end

if ~isempty(VFS_boundaries_native)
    if ~isequal(size(VFS_boundaries_native), retino_target_size)
        VFS_boundaries_native = imresize(VFS_boundaries_native, retino_target_size, 'nearest');
    end
    boundary_native = VFS_boundaries_native > 0.5;
elseif ~isempty(VFS_processed_native)
    if ~isequal(size(VFS_processed_native), retino_target_size)
        VFS_processed_native = imresize(VFS_processed_native, retino_target_size, 'nearest');
    end
    boundary_native = patch_edges(VFS_processed_native);
    fprintf('VFS_boundaries not available -- derived visual-area boundaries from VFS_processed instead.\n');
else
    error('Retino source file has neither VFS_boundaries nor VFS_processed -- cannot build a boundary map.');
end

%% -------------------------
% RE-WARP THE BOUNDARY MASK USING THE ALREADY-FITTED tform (no cpselect)
% -------------------------
retOverlay_stim = imwarp(double(boundary_native), tform, ...
    'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;
fprintf('Rebuilt retOverlay_stim (all visual-area boundaries), %d boundary pixel(s).\n', ...
    sum(retOverlay_stim(:)));

%% -------------------------
% OPTIONAL: UPDATE THE day_setup.mat WITH THE CORRECTED FIELD
% -------------------------
update_choice = questdlg( ...
    'Also update this day_setup.mat with the corrected retOverlay_stim field?', ...
    'Update day_setup.mat', 'Yes, update', 'No, just export figures', 'No, just export figures');
if strcmp(update_choice, 'Yes, update')
    day_setup.retino_align.retOverlay_stim = retOverlay_stim;
    save(ds_path, 'day_setup', '-v7.3');
    fprintf('Updated retOverlay_stim in:\n  %s\n', ds_path);
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(ds_fp, 'Select output folder for the regenerated figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% REBUILD FIGURES — same style as the updated step 6
% -------------------------
region_bound_disp = imdilate(retOverlay_stim, strel('disk', 1));
region_overlay_rgb = cat(3, ones(size(region_bound_disp)), ...
    0.55*ones(size(region_bound_disp)), zeros(size(region_bound_disp)));
region_overlay_alpha = double(region_bound_disp);

fig4 = figure('Name', 'Azimuth map', 'Color', 'w');
imagesc(azi_stim); axis image; set(gca, 'YDir', 'normal');
colormap(gca, parula); cb = colorbar; cb.Label.String = 'Azimuth (deg)';
hold on;
h_bound = image(region_overlay_rgb);
set(h_bound, 'AlphaData', region_overlay_alpha);
if ~isempty(V1_mask_stim)
    visboundaries(V1_mask_stim, 'Color', 'w', 'LineWidth', 2);
end
title('Azimuth map with visual-area boundaries (orange, all areas) + V1 (white)');
azi_png = fullfile(save_dir, sprintf('%s_%s_azimuth_map.png', subject_id, date_str));
saveas(fig4, azi_png);
close(fig4);
fprintf('Saved: %s\n', azi_png);

fig5 = figure('Name', 'Altitude map', 'Color', 'w');
imagesc(alt_stim); axis image; set(gca, 'YDir', 'normal');
colormap(gca, parula); cb = colorbar; cb.Label.String = 'Altitude (deg)';
hold on;
h_bound = image(region_overlay_rgb);
set(h_bound, 'AlphaData', region_overlay_alpha);
if ~isempty(V1_mask_stim)
    visboundaries(V1_mask_stim, 'Color', 'w', 'LineWidth', 2);
end
title('Altitude map with visual-area boundaries (orange, all areas) + V1 (white)');
alt_png = fullfile(save_dir, sprintf('%s_%s_altitude_map.png', subject_id, date_str));
saveas(fig5, alt_png);
close(fig5);
fprintf('Saved: %s\n', alt_png);

fprintf('\nDone.\n');

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

function bmask = patch_edges(labelMap)
% 1-pixel-wide boundary mask between differently-valued regions of a
% labeled/patch map (e.g. VFS_processed) -- used when a dedicated
% VFS_boundaries field isn't available.
se = ones(3);
bmask = (labelMap ~= imdilate(labelMap, se)) | (labelMap ~= imerode(labelMap, se));
end