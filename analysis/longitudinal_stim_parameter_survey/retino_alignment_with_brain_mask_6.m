%% retino_alignment_with_brain_mask.m
% Step 5 of the analysis pipeline: retinotopic alignment and V1 labeling.
%
% Loads the brain boundary mask saved by draw_brain_mask_0.m, then aligns
% the retinotopic map to the stimulation-day image and defines V1.
%
% Run this AFTER inspecting step 4 dF/F results. You do not need to commit
% to a V1 boundary before seeing the activation data.
%
% Inputs (selected interactively):
%   - brain_mask.mat        from draw_brain_mask_0.m
%   - retino .mat file      from compute_retino_maps or retino_inputcombine.m
%
% Output:
%   {analysis_folder}/{subject_id}_{date_str}_day_setup.mat
%
%   day_setup contains:
%     day_setup.subject_id
%     day_setup.date_str
%     day_setup.img_dir
%     day_setup.reference_mask.*        (loaded from brain_mask.mat)
%     day_setup.retino_align.*          (computed here)
%       .V1_mask_stim
%       .azi_stim, .alt_stim, .VFS_stim
%       .retOverlay_stim                 -- ALL visual-area boundaries (not
%                                            just V1: LM, AL, PM, ... too),
%                                            warped onto the stim/brain-mask
%                                            pixel grid with nearest-neighbor
%                                            interpolation (crisp lines, no
%                                            resampling blur). Prefers
%                                            VFS_boundaries; falls back to
%                                            an edge-detection of
%                                            VFS_processed if that field
%                                            isn't available. No manual
%                                            selection needed.
%       .tform, .tform_type
%       .stim_reference_image
%       ... (see full list below)

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
RUN_OPTION_A = true;   % manual cpselect affine (recommended)
RUN_OPTION_B = false;  % auto affine + manual nudge

FORCE_REDRAW_V1 = false;  % set true to redraw V1 even if a saved mask exists

%% -------------------------
% LOAD BRAIN MASK (from draw_brain_mask_0.m)
% -------------------------
[mask_fn, mask_fp] = uigetfile('*.mat', 'Select brain_mask.mat');
if isequal(mask_fn, 0), error('No brain mask file selected.'); end

M = load(fullfile(mask_fp, mask_fn));
assert(isfield(M, 'reference_mask_struct'), ...
    'Selected file does not contain reference_mask_struct. Did you run draw_brain_mask_0.m?');

reference_mask_struct = M.reference_mask_struct;
final_mask  = logical(reference_mask_struct.final_mask);
stimRef     = reference_mask_struct.ref_img;
img_dir     = reference_mask_struct.img_dir;

% Pre-fill subject/date from saved values if available
default_subject = '';
default_date    = '';
if isfield(M, 'subject_id'), default_subject = M.subject_id; end
if isfield(M, 'date_str'),   default_date    = M.date_str;   end

fprintf('Loaded brain mask from:\n  %s\n', fullfile(mask_fp, mask_fn));
fprintf('  Image size: %d x %d  |  Brain pixels: %d\n', ...
    size(final_mask,1), size(final_mask,2), sum(final_mask(:)));

%% -------------------------
% SESSION METADATA
% -------------------------
prompt    = {'Subject ID:', 'Date (YYYYMMDD):'};
dlg_title = 'Session metadata';
dims      = [1 60];
answ = inputdlg(prompt, dlg_title, dims, {default_subject, default_date});
if isempty(answ), error('User cancelled.'); end
subject_id = strtrim(answ{1});
date_str   = strtrim(answ{2});

if isempty(subject_id)
    error('Subject ID is required.');
end
if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be YYYYMMDD.');
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
analysis_folder = uigetdir(mask_fp, 'Select output folder to save day_setup.mat');
if isequal(analysis_folder, 0), error('No output folder selected.'); end
if ~exist(analysis_folder, 'dir'), mkdir(analysis_folder); end

% Master V1 mask path (reuse across sessions for same subject)
v1_mask_file = fullfile(analysis_folder, sprintf('%s_V1_mask_retino_master.mat', subject_id));

%% -------------------------
% LOAD RETINOTOPY DATA
% -------------------------
[ret_name, ret_path] = uigetfile('*.mat', ...
    'Select retino_registration_ready.mat or retino_session_output.mat');
if isequal(ret_name, 0), error('No retino file selected.'); end
retino_file = fullfile(ret_path, ret_name);

S = load(retino_file);

R = struct();
if isfield(S, 'registration_ready'), R = S.registration_ready;
elseif isfield(S, 'out'),            R = S.out;
elseif isfield(S, 'maps'),           R = S.maps;
else,                                R = S;
end

azi = [];
alt = [];
if isfield(R, 'azi'), azi = R.azi; end
if isfield(R, 'alt'), alt = R.alt; end
if isempty(azi) && isfield(S, 'azi'), azi = S.azi; end
if isempty(alt) && isfield(S, 'alt'), alt = S.alt; end
assert(~isempty(azi) && ~isempty(alt), 'Retino file must contain azi and alt.');

retino_target_size = size(azi);

% Reference image from retino space
if isfield(R, 'ReferenceImage'),     retRef = R.ReferenceImage;
elseif isfield(S, 'ReferenceImage'), retRef = S.ReferenceImage;
else, error('Retino file missing ReferenceImage.');
end

if size(retRef,1) ~= retino_target_size(1) || size(retRef,2) ~= retino_target_size(2)
    retRef = imresize(retRef, retino_target_size, 'bilinear');
end
retRefG = mat2gray(toGrayDouble(retRef));

% Visual-area boundary overlay from retino space -- ALL areas (not just
% V1). Prefer the dedicated boundary map; otherwise derive a 1px boundary
% mask from the patch/sign map via edge detection. No manual selection.
VFS_boundaries_native = [];
if isfield(R, 'VFS_boundaries') && ~isempty(R.VFS_boundaries)
    VFS_boundaries_native = R.VFS_boundaries;
elseif isfield(S, 'VFS_boundaries') && ~isempty(S.VFS_boundaries)
    VFS_boundaries_native = S.VFS_boundaries;
end

VFS_processed_native = [];
if isfield(R, 'VFS_processed') && ~isempty(R.VFS_processed)
    VFS_processed_native = R.VFS_processed;
elseif isfield(S, 'VFS_processed') && ~isempty(S.VFS_processed)
    VFS_processed_native = S.VFS_processed;
end

retOverlay = [];
if ~isempty(VFS_boundaries_native)
    if size(VFS_boundaries_native,1) ~= retino_target_size(1) || size(VFS_boundaries_native,2) ~= retino_target_size(2)
        VFS_boundaries_native = imresize(VFS_boundaries_native, retino_target_size, 'nearest');
    end
    retOverlay = VFS_boundaries_native > 0.5;
elseif ~isempty(VFS_processed_native)
    if size(VFS_processed_native,1) ~= retino_target_size(1) || size(VFS_processed_native,2) ~= retino_target_size(2)
        VFS_processed_native = imresize(VFS_processed_native, retino_target_size, 'nearest');
    end
    retOverlay = patch_edges(VFS_processed_native);
    fprintf('VFS_boundaries not available -- derived visual-area boundaries from VFS_processed instead.\n');
end

%% -------------------------
% LOAD OR DRAW V1 MASK IN RETINO SPACE
% -------------------------
V1_mask_retino   = [];
V1_vertices_retino = [];

if ~FORCE_REDRAW_V1
    % Try retino file first
    if isfield(R, 'V1_mask_retino') && ~isempty(R.V1_mask_retino)
        V1_mask_retino = logical(R.V1_mask_retino);
        if ~isequal(size(V1_mask_retino), retino_target_size)
            V1_mask_retino = imresize(V1_mask_retino, retino_target_size, 'nearest') > 0.5;
        end
        fprintf('Loaded V1_mask_retino from retino file.\n');
    end

    % Try master saved mask
    if isempty(V1_mask_retino) && exist(v1_mask_file, 'file')
        MV = load(v1_mask_file);
        if isfield(MV, 'V1_mask_retino') && ~isempty(MV.V1_mask_retino)
            V1_mask_retino = logical(MV.V1_mask_retino);
            if ~isequal(size(V1_mask_retino), retino_target_size)
                V1_mask_retino = imresize(V1_mask_retino, retino_target_size, 'nearest') > 0.5;
            end
        end
        if isfield(MV, 'V1_vertices_retino')
            V1_vertices_retino = MV.V1_vertices_retino;
        end
        fprintf('Loaded reusable V1 retino mask:\n  %s\n', v1_mask_file);
    end
end

if isempty(V1_mask_retino)
    fprintf('Drawing V1 mask on retino reference image...\n');

    figure('Name', 'Draw V1 on Retino Reference', 'Color', 'w');
    imshow(retRefG, []); hold on;
    if ~isempty(retOverlay)
        h_ov = imshow(makeOverlayForDisplay(retOverlay));
        set(h_ov, 'AlphaData', 0.35);
        title('Retino reference + VFS overlay. Draw polygon around V1.');
    else
        title('Retino reference. Draw polygon around V1.');
    end
    axis image;

    h_poly = drawpolygon('Color', 'y', 'LineWidth', 2);
    wait(h_poly);
    V1_vertices_retino = h_poly.Position;
    V1_mask_retino = poly2mask(V1_vertices_retino(:,1), V1_vertices_retino(:,2), ...
        size(retRefG,1), size(retRefG,2));

    % Verify
    figure('Name', 'Verify V1 mask in retino space', 'Color', 'w');
    imshow(retRefG, []); hold on;
    visboundaries(V1_mask_retino, 'Color', 'y', 'LineWidth', 1.5);
    title('V1 mask on retino reference — verify then close');
    axis image;

    % Save master V1 mask for reuse
    save(v1_mask_file, 'V1_mask_retino', 'V1_vertices_retino', 'retino_file');
    fprintf('Saved reusable V1 retino mask:\n  %s\n', v1_mask_file);

    try
        save(retino_file, 'V1_mask_retino', '-append');
        fprintf('Appended V1_mask_retino to retino file.\n');
    catch
        warning('Could not append V1_mask_retino to retino file.');
    end
end

assert(isequal(size(V1_mask_retino), size(retRefG)), ...
    'V1_mask_retino size does not match retino reference image.');

%% -------------------------
% PREPARE STIM REFERENCE IMAGE
% -------------------------
stimRefG = mat2gray(toGrayDouble(stimRef));
Rfixed   = imref2d(size(stimRefG));

%% -------------------------
% ALIGN RETINO TO STIM SPACE
% -------------------------
retRef_warp    = [];
retOverlay_warp = [];
V1_mask_stim   = [];
azi_stim       = [];
alt_stim       = [];
VFS_retino     = [];
VFS_stim       = [];
tform_used     = [];
tform_type     = '';

if RUN_OPTION_A
    fprintf('\n=== OPTION A: cpselect -> affine ===\n');

    [movingPts, fixedPts] = cpselect(retRefG, stimRefG, 'Wait', true);
    assert(size(movingPts,1) >= 3, 'Need at least 3 point pairs for affine.');

    tformA = fitgeotrans(movingPts, fixedPts, 'affine');

    retRef_warp = imwarp(retRefG, tformA, 'OutputView', Rfixed);

    if ~isempty(retOverlay)
        retOverlay_warp = imwarp(double(retOverlay), tformA, ...
            'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;
    end

    V1_mask_stim = imwarp(V1_mask_retino, tformA, ...
        'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;

    azi_stim = imwarp(double(azi), tformA, 'OutputView', Rfixed);
    alt_stim = imwarp(double(alt), tformA, 'OutputView', Rfixed);

    tform_used = tformA;
    tform_type = 'optionA_affine';
end

if RUN_OPTION_B
    fprintf('\n=== OPTION B: auto affine + manual nudge ===\n');

    [optimizer, metric] = imregconfig('multimodal');
    optimizer.MaximumIterations = 300;

    tformAuto   = imregtform(retRefG, stimRefG, 'affine', optimizer, metric);
    tformManual = manualNudgeGUI(stimRefG, retRefG, tformAuto);
    tformB      = affine2d(tformManual.T * tformAuto.T);

    retRef_warp = imwarp(retRefG, tformB, 'OutputView', Rfixed);

    if ~isempty(retOverlay)
        retOverlay_warp = imwarp(double(retOverlay), tformB, ...
            'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;
    end

    V1_mask_stim = imwarp(V1_mask_retino, tformB, ...
        'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;

    azi_stim = imwarp(double(azi), tformB, 'OutputView', Rfixed);
    alt_stim = imwarp(double(alt), tformB, 'OutputView', Rfixed);

    tform_used = tformB;
    tform_type = 'optionB_affine';
end

%% -------------------------
% VISUAL FIELD SIGN
% -------------------------
if ~isempty(azi_stim) && ~isempty(alt_stim)
    [dAzi_dx, dAzi_dy] = gradient(double(azi));
    [dAlt_dx, dAlt_dy] = gradient(double(alt));
    VFS_retino = dAzi_dx .* dAlt_dy - dAzi_dy .* dAlt_dx;
    mx = max(abs(VFS_retino(:)), [], 'omitnan');
    if mx > 0, VFS_retino = VFS_retino ./ mx; end
    VFS_stim = imwarp(VFS_retino, tform_used, 'OutputView', Rfixed);
end

%% -------------------------
% QC FIGURES
% -------------------------
fig1 = figure('Name', 'Retino vs Stim QC', 'Color', 'w');
imshowpair(stimRefG, retRef_warp, 'falsecolor');
title('Stim reference vs warped retino reference');
saveas(fig1, fullfile(analysis_folder, sprintf('%s_%s_retino_stim_qc.png', subject_id, date_str)));

fig2 = figure('Name', 'V1 mask warp QC', 'Color', 'w');
subplot(1,2,1);
imshow(retRefG, []); hold on;
visboundaries(V1_mask_retino, 'Color', 'y', 'LineWidth', 1.5);
title('Retino-space V1 mask'); axis image;
subplot(1,2,2);
imshow(stimRefG, []); hold on;
visboundaries(final_mask, 'Color', 'g', 'LineWidth', 1.5);
visboundaries(V1_mask_stim, 'Color', 'y', 'LineWidth', 1.5);
title('Stim-space: brain mask (green) + V1 (yellow)'); axis image;
saveas(fig2, fullfile(analysis_folder, sprintf('%s_%s_V1_mask_stim_qc.png', subject_id, date_str)));

if ~isempty(retOverlay_warp)
    % ALL visual-area boundaries (LM, AL, PM, ... -- not just V1) painted
    % directly on the stim reference image, same axis convention
    % (axis image / axis off / YDir normal) as every dF/F figure in this
    % pipeline (step 5_A, 7_A, 8, ...).
    region_bound_color = [0.20 0.95 0.95];
    v1_color           = [1.00 0.85 0.10];

    rgb = repmat(stimRefG, 1, 1, 3);
    bmask = imdilate(retOverlay_warp, strel('disk', 1));
    for c = 1:3
        chan = rgb(:, :, c);
        chan(bmask) = region_bound_color(c);
        rgb(:, :, c) = chan;
    end

    fig3 = figure('Name', 'Visual-area boundaries on stim reference', 'Color', 'w');
    ax3 = axes(fig3);
    image(ax3, rgb);
    axis(ax3, 'image'); axis(ax3, 'off'); set(ax3, 'YDir', 'normal'); hold(ax3, 'on');
    visboundaries(ax3, V1_mask_stim, 'Color', v1_color, 'LineWidth', 1.5);
    title(ax3, 'All visual-area boundaries (cyan) + V1 (yellow) on stim reference');
    exportgraphics(fig3, fullfile(analysis_folder, sprintf('%s_%s_retino_overlay_stim_qc.png', subject_id, date_str)), ...
        'Resolution', 150);
end

% Dilated all-area boundary mask (for visibility) + its orange RGB/alpha
% overlay, reused on both the azimuth and altitude figures below.
region_overlay_rgb = [];
region_overlay_alpha = [];
if ~isempty(retOverlay_warp)
    region_bound_disp = imdilate(retOverlay_warp, strel('disk', 1));
    region_overlay_rgb = cat(3, ones(size(region_bound_disp)), ...
        0.55*ones(size(region_bound_disp)), zeros(size(region_bound_disp)));
    region_overlay_alpha = double(region_bound_disp);
end

if ~isempty(azi_stim)
    fig4 = figure('Name', 'Azimuth map', 'Color', 'w');
    imagesc(azi_stim); axis image; set(gca, 'YDir', 'normal');
    colormap(gca, parula); cb = colorbar; cb.Label.String = 'Azimuth (deg)';
    hold on;
    if ~isempty(region_overlay_rgb)
        h_bound = image(region_overlay_rgb);
        set(h_bound, 'AlphaData', region_overlay_alpha);
    end
    visboundaries(V1_mask_stim, 'Color', 'w', 'LineWidth', 2);
    title('Azimuth map with visual-area boundaries (orange, all areas) + V1 (white)');
    saveas(fig4, fullfile(analysis_folder, sprintf('%s_%s_azimuth_map.png', subject_id, date_str)));

    fig5 = figure('Name', 'Altitude map', 'Color', 'w');
    imagesc(alt_stim); axis image; set(gca, 'YDir', 'normal');
    colormap(gca, parula); cb = colorbar; cb.Label.String = 'Altitude (deg)';
    hold on;
    if ~isempty(region_overlay_rgb)
        h_bound = image(region_overlay_rgb);
        set(h_bound, 'AlphaData', region_overlay_alpha);
    end
    visboundaries(V1_mask_stim, 'Color', 'w', 'LineWidth', 2);
    title('Altitude map with visual-area boundaries (orange, all areas) + V1 (white)');
    saveas(fig5, fullfile(analysis_folder, sprintf('%s_%s_altitude_map.png', subject_id, date_str)));

    fig6 = figure('Name', 'Visual Field Sign', 'Color', 'w');
    imagesc(VFS_stim); axis image; set(gca, 'YDir', 'normal');
    colormap(gca, jet); caxis([-1 1]); cb = colorbar; cb.Label.String = 'VFS';
    hold on; visboundaries(V1_mask_stim, 'Color', 'w', 'LineWidth', 2);
    title('Visual Field Sign (stim space) with V1 overlay');
    saveas(fig6, fullfile(analysis_folder, sprintf('%s_%s_VFS_stim.png', subject_id, date_str)));
end

%% -------------------------
% BUILD AND SAVE day_setup
% -------------------------
day_setup = struct();
day_setup.subject_id          = subject_id;
day_setup.date_str            = date_str;
day_setup.img_dir             = img_dir;
day_setup.retino_source_file  = retino_file;
day_setup.created_on          = datestr(now);

day_setup.reference_mask      = reference_mask_struct;

day_setup.retino_align.ReferenceImage_stim  = retRef_warp;
day_setup.retino_align.stim_reference_image = stimRef;
day_setup.retino_align.retOverlay_stim      = retOverlay_warp;
day_setup.retino_align.V1_mask_retino       = V1_mask_retino;
day_setup.retino_align.V1_vertices_retino   = V1_vertices_retino;
day_setup.retino_align.V1_mask_stim         = V1_mask_stim;
day_setup.retino_align.azi_stim             = azi_stim;
day_setup.retino_align.alt_stim             = alt_stim;
day_setup.retino_align.VFS_retino           = VFS_retino;
day_setup.retino_align.VFS_stim             = VFS_stim;
day_setup.retino_align.tform                = tform_used;
day_setup.retino_align.tform_type           = tform_type;
day_setup.retino_align.azi_stim_v1_only     = azi_stim .* double(V1_mask_stim);
day_setup.retino_align.alt_stim_v1_only     = alt_stim .* double(V1_mask_stim);

save_name = sprintf('%s_%s_day_setup.mat', subject_id, date_str);
save_path = fullfile(analysis_folder, save_name);
save(save_path, 'day_setup', '-v7.3');

fprintf('\nSaved day_setup to:\n  %s\n', save_path);

%% ===================== LOCAL FUNCTIONS =====================

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

function ovDisp = makeOverlayForDisplay(ov)
if isempty(ov), ovDisp = []; return; end
if ndims(ov) == 2
    ovDisp = repmat(mat2gray(ov), 1, 1, 3);
elseif ndims(ov) == 3 && size(ov,3) == 3
    ovDisp = mat2gray(ov);
else
    ovDisp = repmat(mat2gray(ov(:,:,1)), 1, 1, 3);
end
end

function tformManual = manualNudgeGUI(fixed, moving, tformAuto)
Rfixed = imref2d(size(fixed));
params.dx = 0; params.dy = 0; params.rotDeg = 0; params.scale = 1.0;

fig = figure('Name', 'Manual Nudge (close when done)', 'Color', 'w', ...
             'KeyPressFcn', @keyPress);
updateDisplay();

uicontrol(fig,'Style','text','String','dx (px)','Units','normalized','Position',[0.05 0.02 0.08 0.03]);
sdx = uicontrol(fig,'Style','slider','Min',-200,'Max',200,'Value',0,'Units','normalized', ...
    'Position',[0.13 0.02 0.22 0.03],'Callback',@sliderCB);

uicontrol(fig,'Style','text','String','dy (px)','Units','normalized','Position',[0.36 0.02 0.08 0.03]);
sdy = uicontrol(fig,'Style','slider','Min',-200,'Max',200,'Value',0,'Units','normalized', ...
    'Position',[0.44 0.02 0.22 0.03],'Callback',@sliderCB);

uicontrol(fig,'Style','text','String','rot (deg)','Units','normalized','Position',[0.67 0.02 0.08 0.03]);
srot = uicontrol(fig,'Style','slider','Min',-30,'Max',30,'Value',0,'Units','normalized', ...
    'Position',[0.75 0.02 0.20 0.03],'Callback',@sliderCB);

uicontrol(fig,'Style','text','String','scale','Units','normalized','Position',[0.05 0.06 0.08 0.03]);
ssc = uicontrol(fig,'Style','slider','Min',0.7,'Max',1.3,'Value',1.0,'Units','normalized', ...
    'Position',[0.13 0.06 0.22 0.03],'Callback',@sliderCB);

uicontrol(fig,'Style','pushbutton','String','Reset','Units','normalized', ...
    'Position',[0.36 0.06 0.10 0.035],'Callback',@resetCB);

uicontrol(fig,'Style','text','String','Arrow keys: nudge dx/dy  |  +/-: rotate', ...
    'Units','normalized','Position',[0.48 0.055 0.47 0.04],'HorizontalAlignment','left');

uiwait(fig);
tformManual = affine2d(similarityMatrix(params.dx, params.dy, params.rotDeg, params.scale));

    function sliderCB(~,~)
        params.dx = get(sdx,'Value'); params.dy = get(sdy,'Value');
        params.rotDeg = get(srot,'Value'); params.scale = get(ssc,'Value');
        updateDisplay();
    end

    function resetCB(~,~)
        set(sdx,'Value',0); set(sdy,'Value',0); set(srot,'Value',0); set(ssc,'Value',1.0);
        params.dx = 0; params.dy = 0; params.rotDeg = 0; params.scale = 1.0;
        updateDisplay();
    end

    function keyPress(~,evt)
        switch evt.Key
            case 'rightarrow', params.dx = params.dx + 2;
            case 'leftarrow',  params.dx = params.dx - 2;
            case 'uparrow',    params.dy = params.dy - 2;
            case 'downarrow',  params.dy = params.dy + 2;
            case 'equal',      params.rotDeg = params.rotDeg + 0.5;
            case 'hyphen',     params.rotDeg = params.rotDeg - 0.5;
            otherwise, return;
        end
        params.dx     = max(get(sdx,'Min'),  min(get(sdx,'Max'),  params.dx));
        params.dy     = max(get(sdy,'Min'),  min(get(sdy,'Max'),  params.dy));
        params.rotDeg = max(get(srot,'Min'), min(get(srot,'Max'), params.rotDeg));
        set(sdx,'Value',params.dx); set(sdy,'Value',params.dy); set(srot,'Value',params.rotDeg);
        updateDisplay();
    end

    function updateDisplay()
        Tm = similarityMatrix(params.dx, params.dy, params.rotDeg, params.scale);
        tformTotal = affine2d(affine2d(Tm).T * tformAuto.T);
        movingWarp = imwarp(moving, tformTotal, 'OutputView', Rfixed);
        clf(fig); axes(fig);
        imshowpair(fixed, movingWarp, 'falsecolor');
        title(sprintf('dx=%.1f  dy=%.1f  rot=%.1f deg  scale=%.3f  |  close when done', ...
            params.dx, params.dy, params.rotDeg, params.scale));
        drawnow;
    end

    function T = similarityMatrix(dx, dy, rotDeg, sc)
        th = deg2rad(rotDeg);
        T = [sc*cos(th)  -sc*sin(th)  0;
             sc*sin(th)   sc*cos(th)  0;
             dx           dy          1];
    end
end
