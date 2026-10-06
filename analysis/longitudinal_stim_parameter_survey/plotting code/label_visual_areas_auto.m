%% label_visual_areas_auto.m
% Automatically LABELS higher visual areas (LM, AL, RL, AM, PM, ...) on
% top of the visual-area boundary figure produced conceptually by
% plot_retino_maps_native_orientation.m (this script is self-contained and
% does NOT call or modify that one).
%
% *** THIS IS A HEURISTIC, NOT A VALIDATED AREA CLASSIFIER. ***
% Each detected patch is labeled by:
%   1. Its position relative to V1, expressed as an angle around V1
%      (0 deg = anterior, 90 deg = lateral, 180 deg = posterior,
%      270 deg = medial) -- computed from two points YOU click to define
%      the anterior and medial directions (the script cannot infer brain
%      orientation from pixels alone).
%   2. Its visual-field-sign (VFS) RELATIVE TO V1 (same sign = "sign_rel_V1
%      = +1", opposite/mirrored sign = "-1").
% These are matched against AREA_TEMPLATES below (angle + required sign),
% which encodes the general topological layout described in Garrett et al.
% 2014 (J Neurosci) and Zhuang et al. 2017 (eLife). Those reference angles
% are APPROXIMATE and were not re-derived from either paper's figures in
% this session -- verify every label by eye against your own reference
% figure, and edit AREA_TEMPLATES (or max_angle_err_deg) if a label looks
% wrong or your recollection of the literature differs. Unassigned/
% low-confidence patches are outlined but left unlabeled rather than
% guessed.
%
% Inputs (selected interactively, same files as plot_retino_maps_native_
% orientation.m):
%   1. retino_registration_ready.mat / retino_session_output.mat
%      (SignMapper output: VFS_processed, VFS_boundaries, ReferenceImage)
%   2. day_setup.mat (from step 6) -- supplies retino_align.tform (for WF
%      orientation) and V1_mask_retino

close all; clc; clear; fclose('all');

%% -------------------------
% USER-EDITABLE: reference area layout around V1 (see header disclaimer)
% angle_deg   : clockwise angle from ANTERIOR (0), through LATERAL (90),
%               POSTERIOR (180), MEDIAL (270)
% sign_rel_V1 : +1 = same VFS sign as V1 ("non-mirror"), -1 = opposite
%               ("mirror")
% -------------------------
AREA_TEMPLATES = struct( ...
    'name',        {'LM',  'AL',  'RL',  'A',   'AM',  'PM',  'LI',  'POR'}, ...
    'angle_deg',   {95,    60,    35,    15,    330,   280,   140,   170}, ...
    'sign_rel_V1', {-1,    -1,    +1,    -1,    +1,    -1,    +1,    -1});

min_patch_px       = 40;    % ignore tiny/noise patches below this pixel count
max_angle_err_deg   = 60;   % leave a patch unlabeled if its best angular match exceeds this
v1_color            = [1.00 0.85 0.10];
region_bound_color  = [0.20 0.95 0.95];
region_bound_dilate_px = 1;
label_font_size     = 11;
title_font_size     = 13;

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
if isempty(azi), azi = get_field_or_empty(S, 'azi'); end
assert(~isempty(azi), 'Retino file must contain azi (used only to fix the native H x W).');
[H, W] = size(azi);

refImg = get_field_or_empty(R, 'ReferenceImage');
if isempty(refImg), refImg = get_field_or_empty(S, 'ReferenceImage'); end
assert(~isempty(refImg), 'Retino file missing ReferenceImage.');
if size(refImg,1) ~= H || size(refImg,2) ~= W
    refImg = imresize(refImg, [H W], 'bilinear');
end
refImgG = mat2gray(toGrayDouble(refImg));

VFS_processed = get_field_or_empty(R, 'VFS_processed');
if isempty(VFS_processed), VFS_processed = get_field_or_empty(S, 'VFS_processed'); end
assert(~isempty(VFS_processed), 'Retino file missing VFS_processed -- needed to identify patches/signs.');
VFS_processed = resize_to_match(VFS_processed, [H W], 'nearest', 'VFS_processed');

VFS_boundaries = get_field_or_empty(R, 'VFS_boundaries');
if isempty(VFS_boundaries), VFS_boundaries = get_field_or_empty(S, 'VFS_boundaries'); end
VFS_boundaries = resize_to_match(VFS_boundaries, [H W], 'nearest', 'VFS_boundaries');

V1_mask_retino = get_field_or_empty(R, 'V1_mask_retino');
if isempty(V1_mask_retino), V1_mask_retino = get_field_or_empty(S, 'V1_mask_retino'); end

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

if isempty(V1_mask_retino) && isfield(DS.day_setup.retino_align, 'V1_mask_retino')
    V1_mask_retino = DS.day_setup.retino_align.V1_mask_retino;
end
assert(~isempty(V1_mask_retino), 'V1_mask_retino not found in the retino file or day_setup.mat.');
V1_mask_retino = logical(V1_mask_retino);
if ~isequal(size(V1_mask_retino), [H W])
    V1_mask_retino = imresize(V1_mask_retino, [H W], 'nearest') > 0.5;
end

if isempty(VFS_boundaries)
    region_bound_native = patch_edges(VFS_processed);
    fprintf('VFS_boundaries not available -- derived area boundaries from VFS_processed instead.\n');
else
    region_bound_native = VFS_boundaries > 0.5;
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(ret_path, 'Select output folder for the labeled visual-areas figure');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
[~, tag] = fileparts(ret_name);

%% -------------------------
% WARP EVERYTHING INTO WF ORIENTATION (same tform, shared loose canvas)
% -------------------------
[refImg_w, Rout] = imwarp(refImgG, tform, 'FillValues', 0.15);
VFS_processed_w = imwarp(VFS_processed, tform, 'OutputView', Rout, 'Interp', 'nearest', 'FillValues', 0);
region_bound_w  = imwarp(double(region_bound_native), tform, 'OutputView', Rout, ...
    'Interp', 'nearest', 'FillValues', 0) > 0.5;
V1_mask_w = imwarp(double(V1_mask_retino), tform, 'OutputView', Rout, ...
    'Interp', 'nearest', 'FillValues', 0) > 0.5;
if region_bound_dilate_px > 0
    region_bound_w_disp = imdilate(region_bound_w, strel('disk', region_bound_dilate_px));
else
    region_bound_w_disp = region_bound_w;
end

%% -------------------------
% USER CLICKS: anterior direction, medial direction (relative to V1)
% -------------------------
V1_props = regionprops(V1_mask_w, 'Centroid');
assert(~isempty(V1_props), 'V1_mask_w is empty after warping -- check inputs.');
V1_centroid = V1_props(1).Centroid;   % [x y]

fig0 = figure('Color', 'w', 'Name', 'Click anterior then medial direction', 'Position', [80 80 780 700]);
ax0 = axes(fig0);
image(ax0, repmat(refImg_w, 1, 1, 3));
axis(ax0, 'image'); axis(ax0, 'off'); set(ax0, 'YDir', 'normal'); hold(ax0, 'on');
visboundaries(ax0, V1_mask_w, 'Color', v1_color, 'LineWidth', 1.5);
visboundaries(ax0, region_bound_w_disp, 'Color', [0.5 0.5 0.5], 'LineWidth', 0.6);
plot(ax0, V1_centroid(1), V1_centroid(2), 'w+', 'MarkerSize', 14, 'LineWidth', 2);
title(ax0, {'Click a point ANTERIOR to V1 (e.g. toward the front of the brain), then Enter', ...
    'the direction from V1 to your click defines "anterior" for area labeling'}, 'FontSize', 11);
[ax_x, ay_y] = ginput(1);
anterior_pt = [ax_x, ay_y];

title(ax0, {'Now click a point MEDIAL to V1 (toward the midline), then Enter'}, 'FontSize', 11);
[mx_x, my_y] = ginput(1);
medial_pt = [mx_x, my_y];
close(fig0);

ant_vec = anterior_pt - V1_centroid;
ant_vec = ant_vec / norm(ant_vec);
med_vec = medial_pt - V1_centroid;
med_vec = med_vec - dot(med_vec, ant_vec) * ant_vec;   % orthogonalize vs anterior
assert(norm(med_vec) > 1e-6, 'Medial click was collinear with the anterior direction -- pick a clearer point.');
med_vec = med_vec / norm(med_vec);
lat_vec = -med_vec;

fprintf('Anterior direction: [%.2f %.2f]  |  Medial direction: [%.2f %.2f]\n', ant_vec, med_vec);

%% -------------------------
% IDENTIFY CANDIDATE PATCHES (connected components between boundaries,
% excluding V1 and anything too small to be a real area)
% -------------------------
enclosed = ~region_bound_w;
lbl = bwlabel(enclosed, 4);
n_lbl = max(lbl(:));

V1_sign_ref = sign(mean(VFS_processed_w(V1_mask_w), 'omitnan'));

candidates = struct('label', {}, 'centroid', {}, 'mask', {}, 'n_px', {}, 'sign_rel_V1', {}, 'angle_deg', {});
for L = 1:n_lbl
    patch_mask = (lbl == L);
    n_px = sum(patch_mask(:));
    if n_px < min_patch_px, continue; end

    v1_overlap = sum(patch_mask(:) & V1_mask_w(:)) / n_px;
    if v1_overlap > 0.5, continue; end   % this connected component IS V1 -- skip

    props = regionprops(patch_mask, 'Centroid');
    if isempty(props), continue; end
    centroid = props(1).Centroid;

    patch_sign = sign(mean(VFS_processed_w(patch_mask), 'omitnan'));
    if patch_sign == 0 || isnan(patch_sign), continue; end
    sign_rel_V1 = patch_sign * V1_sign_ref;   % +1 if same sign as V1, -1 if opposite

    v = centroid - V1_centroid;
    comp_ant = dot(v, ant_vec);
    comp_lat = dot(v, lat_vec);
    angle_deg = mod(atan2d(comp_lat, comp_ant), 360);

    candidates(end+1) = struct('label', L, 'centroid', centroid, 'mask', patch_mask, ...
        'n_px', n_px, 'sign_rel_V1', sign_rel_V1, 'angle_deg', angle_deg); %#ok<AGROW>
end
fprintf('Found %d candidate patch(es) (excluding V1) after size filtering.\n', numel(candidates));

%% -------------------------
% GREEDY LABEL ASSIGNMENT (angle + matching sign, closest first)
% -------------------------
n_cand = numel(candidates);
n_tmpl = numel(AREA_TEMPLATES);
pair_cost = inf(n_cand, n_tmpl);
for ci = 1:n_cand
    for ti = 1:n_tmpl
        if candidates(ci).sign_rel_V1 ~= AREA_TEMPLATES(ti).sign_rel_V1, continue; end
        d = abs(candidates(ci).angle_deg - AREA_TEMPLATES(ti).angle_deg);
        d = min(d, 360 - d);
        if d <= max_angle_err_deg
            pair_cost(ci, ti) = d;
        end
    end
end

assigned_name = cell(n_cand, 1);
cand_used = false(n_cand, 1);
tmpl_used = false(n_tmpl, 1);
pairs = [];
for ci = 1:n_cand
    for ti = 1:n_tmpl
        if isfinite(pair_cost(ci, ti))
            pairs = [pairs; ci, ti, pair_cost(ci, ti)]; %#ok<AGROW>
        end
    end
end
if ~isempty(pairs)
    pairs = sortrows(pairs, 3);
    for k = 1:size(pairs, 1)
        ci = pairs(k, 1); ti = pairs(k, 2);
        if cand_used(ci) || tmpl_used(ti), continue; end
        assigned_name{ci} = AREA_TEMPLATES(ti).name;
        cand_used(ci) = true;
        tmpl_used(ti) = true;
    end
end

fprintf('\n%-12s %10s %10s %8s\n', 'Area', 'AngleDeg', 'SignRelV1', 'nPx');
for ci = 1:n_cand
    name_str = assigned_name{ci};
    if isempty(name_str), name_str = '(unlabeled)'; end
    fprintf('%-12s %10.1f %10d %8d\n', name_str, candidates(ci).angle_deg, ...
        candidates(ci).sign_rel_V1, candidates(ci).n_px);
end

%% -------------------------
% PLOT LABELED FIGURE
% -------------------------
fig = figure('Color', 'w', 'Position', [100 100 800 700]);
ax = axes(fig);
rgb = repmat(refImg_w, 1, 1, 3);
for c = 1:3
    chan = rgb(:, :, c);
    chan(region_bound_w_disp) = region_bound_color(c);
    rgb(:, :, c) = chan;
end
image(ax, rgb);
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, V1_mask_w, 'Color', v1_color, 'LineWidth', 2.0);
text(ax, V1_centroid(1), V1_centroid(2), 'V1', 'Color', v1_color, 'FontWeight', 'bold', ...
    'FontSize', label_font_size, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

for ci = 1:n_cand
    label_color = region_bound_color;
    if isempty(assigned_name{ci})
        text_str = '?';
        label_color = [0.7 0.7 0.7];
    else
        text_str = assigned_name{ci};
    end
    text(ax, candidates(ci).centroid(1), candidates(ci).centroid(2), text_str, ...
        'Color', label_color, 'FontWeight', 'bold', 'FontSize', label_font_size, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

title(ax, {sprintf('Visual areas, auto-labeled (heuristic)  |  %s', tag), ...
    'Verify labels by eye -- see script header for method/caveats'}, ...
    'Interpreter', 'none', 'FontSize', title_font_size);

out_png = fullfile(save_dir, sprintf('%s_visual_areas_WForient_labeled.png', tag));
exportgraphics(fig, out_png, 'Resolution', 150);
close(fig);
fprintf('\nSaved: %s\n', out_png);

out_mat = fullfile(save_dir, sprintf('%s_visual_areas_WForient_labeled.mat', tag));
area_names   = assigned_name; %#ok<NASGU>
area_angles  = [candidates.angle_deg]'; %#ok<NASGU>
area_signs   = [candidates.sign_rel_V1]'; %#ok<NASGU>
area_npix    = [candidates.n_px]'; %#ok<NASGU>
area_centroids = cat(1, candidates.centroid); %#ok<NASGU>
area_masks   = {candidates.mask}'; %#ok<NASGU>
save(out_mat, 'area_names', 'area_angles', 'area_signs', 'area_npix', ...
    'area_centroids', 'area_masks', 'V1_centroid', 'AREA_TEMPLATES');
fprintf('Saved: %s\n', out_mat);

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
if isempty(X) || isequal(size(X), targetSize)
    return;
end
warning('%s size (%dx%d) does not match azi/alt size (%dx%d) -- resizing to match.', ...
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
se = ones(3);
bmask = (labelMap ~= imdilate(labelMap, se)) | (labelMap ~= imerode(labelMap, se));
end