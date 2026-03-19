%% reference_mask_and_retino_alignment.m
% Day-level setup script for widefield stimulation experiments.
%
% This script:
%   1) Loads retinotopy output from compute_retino_maps
%   2) Builds a stimulation-day reference mask from TIFF frames
%   3) Aligns retinotopy to the stimulation-day reference image
%   4) Saves one unified day_setup struct
%
% Output:
%   analysis/{subject}_{date}_reference_mask_and_retino_alignment.mat
%
% day_setup contains:
%   day_setup.subject_id
%   day_setup.date_str
%   day_setup.img_dir
%   day_setup.reference_mask.*
%   day_setup.retino_align.*
%
% Notes:
%   - Uses manual cpselect affine by default
%   - Optionally supports auto affine + manual nudge
%   - Forces all retino-side objects into one consistent space:
%       azi/alt space
%   - Saves V1_mask_stim, azi_stim, alt_stim into the same setup file

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
RUN_OPTION_A = true;    % manual cpselect affine
RUN_OPTION_B = false;   % auto affine + manual nudge
USE_VFS_BOUNDARIES_IF_AVAILABLE = true;
NREF = 200;             % number of TIFF frames to average for stim reference
FORCE_REDRAW_V1 = true; % safest while establishing consistent geometry

%% -------------------------
% SELECT INPUTS
% -------------------------

% Retinotopy output from compute_retino_maps
[ret_name, ret_path] = uigetfile('*.mat', ...
    'Select retino_registration_ready.mat or retino_session_output.mat');
if isequal(ret_name,0), error('No retino file selected.'); end
retino_file = fullfile(ret_path, ret_name);

% Stimulation-day image folder
img_dir = uigetdir(pwd, 'Select folder containing stimulation-day TIFF frames');
if isequal(img_dir,0), error('No image folder selected.'); end

% Optional metadata
prompt = {'Subject ID (e.g. LGN11):', 'Date (YYYYMMDD):'};
dlg_title = 'Day setup metadata';
dims = [1 60];
definput = {'',''};
answ = inputdlg(prompt, dlg_title, dims, definput);
if isempty(answ), error('User cancelled metadata input.'); end
subject_id = strtrim(answ{1});
date_str   = strtrim(answ{2});

if isempty(subject_id)
    error('Subject ID is required.');
end
if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be YYYYMMDD.');
end

% Output folder
analysisFolder = fullfile(fileparts(img_dir), 'analysis');
if ~exist(analysisFolder,'dir'), mkdir(analysisFolder); end

%% -------------------------
% LOAD RETINOTOPY DATA
% Force everything into azi/alt space
% -------------------------
S = load(retino_file);

R = struct();
if isfield(S,'registration_ready')
    R = S.registration_ready;
elseif isfield(S,'out')
    R = S.out;
elseif isfield(S,'maps')
    R = S.maps;
else
    R = S;
end

% Load azi / alt first
azi = [];
alt = [];
if isfield(R,'azi'), azi = R.azi; end
if isfield(R,'alt'), alt = R.alt; end
if isempty(azi) && isfield(S,'azi'), azi = S.azi; end
if isempty(alt) && isfield(S,'alt'), alt = S.alt; end

assert(~isempty(azi) && ~isempty(alt), ...
    'Retino file must contain azi and alt.');

retino_target_size = size(azi);

% Load reference image and force into azi/alt space
if isfield(R,'ReferenceImage')
    retRef = R.ReferenceImage;
elseif isfield(S,'ReferenceImage')
    retRef = S.ReferenceImage;
else
    error('Retino file missing ReferenceImage.');
end

if size(retRef,1) ~= retino_target_size(1) || size(retRef,2) ~= retino_target_size(2)
    retRef = imresize(retRef, retino_target_size, 'bilinear');
end
retRefG = mat2gray(toGrayDouble(retRef));

% Overlay image
retOverlay = [];
if USE_VFS_BOUNDARIES_IF_AVAILABLE && isfield(R,'VFS_boundaries') && ~isempty(R.VFS_boundaries)
    retOverlay = R.VFS_boundaries;
elseif isfield(R,'VFS_processed') && ~isempty(R.VFS_processed)
    retOverlay = R.VFS_processed;
elseif isfield(R,'VFS_boundaries') && ~isempty(R.VFS_boundaries)
    retOverlay = R.VFS_boundaries;
elseif isfield(S,'VFS_processed')
    retOverlay = S.VFS_processed;
elseif isfield(S,'VFS_boundaries')
    retOverlay = S.VFS_boundaries;
end

if ~isempty(retOverlay)
    if size(retOverlay,1) ~= retino_target_size(1) || size(retOverlay,2) ~= retino_target_size(2)
        retOverlay = imresize(retOverlay, retino_target_size, 'nearest');
    end
end

% V1 mask in retino space
V1_mask_retino = [];
if ~FORCE_REDRAW_V1
    if isfield(R,'V1_mask_retino') && ~isempty(R.V1_mask_retino)
        V1_mask_retino = logical(R.V1_mask_retino);
        if size(V1_mask_retino,1) ~= retino_target_size(1) || size(V1_mask_retino,2) ~= retino_target_size(2)
            V1_mask_retino = imresize(V1_mask_retino, retino_target_size, 'nearest') > 0.5;
        end
    end
end

%% -------------------------
% BUILD STIM REFERENCE MASK
% -------------------------
[reference_mask_struct, final_mask, stimRef] = build_reference_mask_from_img_dir(img_dir, NREF);

stimRefG = mat2gray(toGrayDouble(stimRef));
Rfixed = imref2d(size(stimRefG));

%% -------------------------
% DEFINE / DRAW V1 MASK IN RETINO SPACE
% -------------------------
if isempty(V1_mask_retino)
    fprintf('Draw V1_mask_retino directly on retino reference used for registration.\n');

    figure('Name','Draw V1 on Retino Reference','Color','w');
    imshow(retRefG, []); hold on;

    if ~isempty(retOverlay)
        ovDisp = makeOverlayForDisplay(retOverlay);
        h = imshow(ovDisp);
        set(h, 'AlphaData', 0.35);
        title('Retino reference + overlay. Draw polygon around V1.');
    else
        title('Retino reference. Draw polygon around V1.');
    end

    axis image;
    hpoly = drawpolygon('Color','y','LineWidth',2);
    wait(hpoly);

    V1_mask_retino = poly2mask(hpoly.Position(:,1), hpoly.Position(:,2), ...
        size(retRefG,1), size(retRefG,2));

    figure('Name','Verify V1 mask in retino space','Color','w');
    imshow(retRefG, []); hold on;
    visboundaries(V1_mask_retino, 'Color','y', 'LineWidth', 1.5);
    title('Verify V1_mask_retino on retino reference');
    axis image;
end

assert(isequal(size(V1_mask_retino), size(retRefG)), ...
    'V1_mask_retino must match retino reference image size.');

%% -------------------------
% ALIGN RETINO TO STIM SPACE
% -------------------------
retRef_warp = [];
retOverlay_warp = [];
V1_mask_stim = [];
azi_stim = [];
alt_stim = [];
tform_used = [];
tform_type = '';

if RUN_OPTION_A
    fprintf('\n=== OPTION A: cpselect -> affine ===\n');

    [movingPts, fixedPts] = cpselect(retRefG, stimRefG, 'Wait', true);
    assert(size(movingPts,1) >= 3, 'Need >=3 points for affine.');

    tformA = fitgeotrans(movingPts, fixedPts, 'affine');

    retRef_warp = imwarp(retRefG, tformA, 'OutputView', Rfixed);

    if ~isempty(retOverlay)
        retOverlay_warp = warpAnyImage(retOverlay, tformA, Rfixed);
    end

    V1_mask_stim = imwarp(V1_mask_retino, tformA, ...
        'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;

    azi_stim = imwarp(double(azi), tformA, 'OutputView', Rfixed);
    alt_stim = imwarp(double(alt), tformA, 'OutputView', Rfixed);

    tform_used = tformA;
    tform_type = 'optionA_affine';
end

if RUN_OPTION_B
    fprintf('\n=== OPTION B: auto affine -> manual nudge ===\n');

    [optimizer, metric] = imregconfig('multimodal');
    optimizer.MaximumIterations = 300;

    moving = retRefG;
    fixed  = stimRefG;

    tformAuto = imregtform(moving, fixed, 'affine', optimizer, metric);
    tformManual = manualNudgeGUI(fixed, moving, tformAuto);
    tformB = affine2d(tformManual.T * tformAuto.T);

    retRef_warp = imwarp(retRefG, tformB, 'OutputView', Rfixed);

    if ~isempty(retOverlay)
        retOverlay_warp = warpAnyImage(retOverlay, tformB, Rfixed);
    end

    V1_mask_stim = imwarp(V1_mask_retino, tformB, ...
        'OutputView', Rfixed, 'Interp', 'nearest') > 0.5;

    azi_stim = imwarp(double(azi), tformB, 'OutputView', Rfixed);
    alt_stim = imwarp(double(alt), tformB, 'OutputView', Rfixed);

    tform_used = tformB;
    tform_type = 'optionB_affine';
end

%% -------------------------
% QC
% -------------------------
fig1 = figure('Name','Retino vs Stim QC','Color','w');
imshowpair(stimRefG, retRef_warp, 'falsecolor');
title('Stim reference vs warped retino reference');
saveas(fig1, fullfile(analysisFolder, sprintf('%s_%s_retino_stim_qc.png', subject_id, date_str)));

fig2 = figure('Name','Mask warp QC','Color','w');
subplot(1,2,1);
imshow(retRefG, []); hold on;
visboundaries(V1_mask_retino, 'Color','y', 'LineWidth', 1.5);
title('Retino-space V1 mask');
axis image;

subplot(1,2,2);
imshow(stimRefG, []); hold on;
visboundaries(V1_mask_stim, 'Color','y', 'LineWidth', 1.5);
title('Stim-space warped V1 mask');
axis image;
saveas(fig2, fullfile(analysisFolder, sprintf('%s_%s_V1_mask_stim_qc.png', subject_id, date_str)));

if ~isempty(retOverlay_warp)
    fig3 = figure('Name','Warped overlay on stim reference','Color','w');
    imshow(stimRefG, []); hold on;
    ovDisp = makeOverlayForDisplay(retOverlay_warp);
    h = imshow(ovDisp);
    set(h, 'AlphaData', 0.45);
    visboundaries(V1_mask_stim, 'Color','y', 'LineWidth', 1.5);
    title('Warped retino overlay + V1 boundary');
    saveas(fig3, fullfile(analysisFolder, sprintf('%s_%s_retino_overlay_stim_qc.png', subject_id, date_str)));
end

%% -------------------------
% BUILD DAY_SETUP STRUCT
% -------------------------
day_setup = struct();

day_setup.subject_id = subject_id;
day_setup.date_str   = date_str;
day_setup.img_dir    = img_dir;
day_setup.retino_source_file = retino_file;
day_setup.created_on = datestr(now);

day_setup.reference_mask = reference_mask_struct;

day_setup.retino_align = struct();
day_setup.retino_align.ReferenceImage_stim = retRef_warp;
day_setup.retino_align.stim_reference_image = stimRef;
day_setup.retino_align.retOverlay_stim = retOverlay_warp;
day_setup.retino_align.V1_mask_retino = V1_mask_retino;
day_setup.retino_align.V1_mask_stim = V1_mask_stim;
day_setup.retino_align.azi_stim = azi_stim;
day_setup.retino_align.alt_stim = alt_stim;
day_setup.retino_align.tform = tform_used;
day_setup.retino_align.tform_type = tform_type;

%% -------------------------
% SAVE
% -------------------------
saveName = sprintf('%s_%s_reference_mask_and_retino_alignment.mat', subject_id, date_str);
savePath = fullfile(analysisFolder, saveName);
save(savePath, 'day_setup', '-v7.3');

fprintf('\nSaved day setup file:\n  %s\n', savePath);

%% ===================== LOCAL FUNCTIONS =====================

function [reference_mask_struct, final_mask, ref_img] = build_reference_mask_from_img_dir(img_dir, Nref)
    image_files = dir(fullfile(img_dir, '*.tif'));
    if isempty(image_files)
        error('No .tif files found in %s', img_dir);
    end

    nFiles = numel(image_files);
    fileNumbers = zeros(nFiles, 1);
    for i = 1:nFiles
        tok = regexp(image_files(i).name, '(\d+)\.tif$', 'tokens');
        if ~isempty(tok)
            fileNumbers(i) = str2double(tok{1}{1});
        else
            error('Filename "%s" has no trailing numeric index.', image_files(i).name);
        end
    end
    [~, sortedIdx] = sort(fileNumbers);
    image_files = image_files(sortedIdx);

    Nref = min(Nref, numel(image_files));
    acc = 0;
    for i = 1:Nref
        img = imread(fullfile(img_dir, image_files(i).name));
        acc = acc + double(img);
    end
    ref_img = acc / Nref;

    figure('Name', 'Define Masks', 'Position', [100, 100, 800, 600]);
    imagesc(ref_img);
    colormap(gray);
    title('Define Circle and Rectangle Masks');
    axis image;

    disp('Draw a circular region of interest:');
    h_circle = drawcircle('Color', 'g', 'LineWidth', 2);
    wait(h_circle);
    circle_center = h_circle.Center;
    circle_radius = h_circle.Radius;

    [xx, yy] = meshgrid(1:size(ref_img, 2), 1:size(ref_img, 1));
    circle_mask = ((xx - circle_center(1)).^2 + (yy - circle_center(2)).^2) <= (circle_radius^2);

    disp('Draw rectangular exclusion regions inside the circle:');
    rectangle_masks = false(size(circle_mask));

    n_rectangles = input('Enter the shank number of the device: ');
    for i = 1:n_rectangles
        disp(['Draw rectangle ', num2str(i), ' of ', num2str(n_rectangles)]);
        h_rect = drawpolygon('Color', 'r', 'LineWidth', 2);
        wait(h_rect);

        vertices = h_rect.Position;
        current_mask = poly2mask(vertices(:,1), vertices(:,2), ...
            size(rectangle_masks,1), size(rectangle_masks,2));

        rectangle_masks = rectangle_masks | current_mask;
    end

    final_mask = circle_mask & ~rectangle_masks;

    figure('Name', 'Verification', 'Position', [100, 100, 800, 600]);
    imagesc(ref_img);
    colormap(gray);
    hold on;
    h_mask = imagesc(cat(3, ~final_mask, zeros(size(final_mask)), zeros(size(final_mask))));
    set(h_mask, 'AlphaData', 0.3);
    title('Verification: Red areas excluded from analysis');
    axis image;

    response = questdlg('Is the mask correct?', 'Mask Verification', 'Yes', 'No, redo', 'Yes');
    if strcmp(response, 'No, redo')
        error('Mask definition cancelled. Please run again.');
    end

    reference_mask_struct = struct();
    reference_mask_struct.final_mask = final_mask;
    reference_mask_struct.circle_mask = circle_mask;
    reference_mask_struct.rectangle_masks = rectangle_masks;
    reference_mask_struct.circle_center = circle_center;
    reference_mask_struct.circle_radius = circle_radius;
    reference_mask_struct.ref_img = ref_img;
    reference_mask_struct.img_dir = img_dir;
end

function G = toGrayDouble(I)
    if isa(I,'uint16') || isa(I,'uint8')
        I = im2double(I);
    elseif ~isa(I,'double')
        I = double(I);
    end

    if ndims(I)==3
        if size(I,3)==3
            G = rgb2graySafe(I);
        else
            G = I(:,:,1);
        end
    else
        G = I;
    end
end

function G = rgb2graySafe(I)
    I = mat2gray(I);
    G = 0.2989*I(:,:,1) + 0.5870*I(:,:,2) + 0.1140*I(:,:,3);
end

function warped = warpAnyImage(img, tform, Rfixed)
    if ndims(img)==2
        warped = imwarp(img, tform, 'OutputView', Rfixed);
    elseif ndims(img)==3 && size(img,3)==3
        warped = zeros([Rfixed.ImageSize 3], 'like', img);
        for c = 1:3
            warped(:,:,c) = imwarp(img(:,:,c), tform, 'OutputView', Rfixed);
        end
    else
        warped = imwarp(img(:,:,1), tform, 'OutputView', Rfixed);
    end
end

function ovDisp = makeOverlayForDisplay(ov)
    if isempty(ov)
        ovDisp = [];
        return;
    end
    if ndims(ov)==2
        ovDisp = repmat(mat2gray(ov), 1,1,3);
    elseif ndims(ov)==3 && size(ov,3)==3
        ovDisp = mat2gray(ov);
    else
        ovDisp = repmat(mat2gray(ov(:,:,1)), 1,1,3);
    end
end

function tformManual = manualNudgeGUI(fixed, moving, tformAuto)
    Rfixed = imref2d(size(fixed));

    params.dx = 0;
    params.dy = 0;
    params.rotDeg = 0;
    params.scale = 1.0;

    fig = figure('Name','Manual Nudge (Close when done)','Color','w', ...
                 'KeyPressFcn', @keyPress);
    updateDisplay();

    uicontrol(fig,'Style','text','String','dx (px)','Units','normalized','Position',[0.05 0.02 0.08 0.03]);
    sdx = uicontrol(fig,'Style','slider','Min',-200,'Max',200,'Value',0, ...
        'Units','normalized','Position',[0.13 0.02 0.22 0.03],'Callback',@sliderCB);

    uicontrol(fig,'Style','text','String','dy (px)','Units','normalized','Position',[0.36 0.02 0.08 0.03]);
    sdy = uicontrol(fig,'Style','slider','Min',-200,'Max',200,'Value',0, ...
        'Units','normalized','Position',[0.44 0.02 0.22 0.03],'Callback',@sliderCB);

    uicontrol(fig,'Style','text','String','rot (deg)','Units','normalized','Position',[0.67 0.02 0.08 0.03]);
    srot = uicontrol(fig,'Style','slider','Min',-30,'Max',30,'Value',0, ...
        'Units','normalized','Position',[0.75 0.02 0.20 0.03],'Callback',@sliderCB);

    uicontrol(fig,'Style','text','String','scale','Units','normalized','Position',[0.05 0.06 0.08 0.03]);
    ssc  = uicontrol(fig,'Style','slider','Min',0.7,'Max',1.3,'Value',1.0, ...
        'Units','normalized','Position',[0.13 0.06 0.22 0.03],'Callback',@sliderCB);

    uicontrol(fig,'Style','pushbutton','String','Reset','Units','normalized', ...
        'Position',[0.36 0.06 0.10 0.035],'Callback',@resetCB);

    uicontrol(fig,'Style','text','String','Tip: arrow keys nudge dx/dy, +/- rot', ...
        'Units','normalized','Position',[0.48 0.055 0.47 0.04], ...
        'HorizontalAlignment','left');

    uiwait(fig);

    tformManual = affine2d(similarityMatrix(params.dx, params.dy, params.rotDeg, params.scale));

    function sliderCB(~,~)
        params.dx = get(sdx,'Value');
        params.dy = get(sdy,'Value');
        params.rotDeg = get(srot,'Value');
        params.scale = get(ssc,'Value');
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

        params.dx = max(get(sdx,'Min'), min(get(sdx,'Max'), params.dx));
        params.dy = max(get(sdy,'Min'), min(get(sdy,'Max'), params.dy));
        params.rotDeg = max(get(srot,'Min'), min(get(srot,'Max'), params.rotDeg));

        set(sdx,'Value',params.dx);
        set(sdy,'Value',params.dy);
        set(srot,'Value',params.rotDeg);
        updateDisplay();
    end

    function updateDisplay()
        Tm = similarityMatrix(params.dx, params.dy, params.rotDeg, params.scale);
        tformM = affine2d(Tm);
        tformTotalPreview = affine2d(tformM.T * tformAuto.T);
        movingWarp = imwarp(moving, tformTotalPreview, 'OutputView', Rfixed);

        clf(fig);
        axes(fig);
        imshowpair(fixed, movingWarp, 'falsecolor');
        title(sprintf('dx=%.1f  dy=%.1f  rot=%.1f°  scale=%.3f (close when done)', ...
            params.dx, params.dy, params.rotDeg, params.scale));
        drawnow;
    end

    function T = similarityMatrix(dx, dy, rotDeg, sc)
        th = deg2rad(rotDeg);
        R = [cos(th) -sin(th) 0;
             sin(th)  cos(th) 0;
             0        0       1];
        S = [sc 0  0;
             0  sc 0;
             0  0  1];
        Tr = [1 0 0;
              0 1 0;
              dx dy 1];
        T = Tr * R * S;
    end
end