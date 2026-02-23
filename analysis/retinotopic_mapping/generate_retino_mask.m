%% register_retino_to_stim_cpselect_affine.m
% Manual registration of retinotopy reference -> stimulation-day reference
% using cpselect control points and an affine transform.
%
% Interactive steps:
%   1) (Optional) draw V1 polygon in retinotopy space (saved for reuse)
%   2) select matching control points with cpselect
%
% Outputs saved in outDir:
%   - tform_affine.mat
%   - V1_mask_retino.mat
%   - V1_mask_stim.mat
%   - stimRef_gray.png
%   - retRef_warp.png
%   - qc_falsecolor.png
%   - qc_v1_on_stim.png
%
% Notes:
%   - Need >= 3 control points for affine; 10–30 recommended.

close all; clear; clc;

%% -------------------- USER SETTINGS --------------------
retinoMatPath = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\retinotopic_mapping\LGN11_retinotopic_mapping\additional_maps.mat';
stimRefPath   = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\wf_stim_ephys\WF_StimSurvey_20260210\StimSurvey_images_20260210\img_actual\test61_00001.tif';
outDir        = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\wf_stim_ephys\WF_StimSurvey_20260210\StimSurvey_images_20260210\retinotopic_mapping';

USE_VFS_BOUNDARIES_IF_AVAILABLE = true;
OVERLAY_ALPHA = 0.45;

%% -------------------- BASIC CHECKS --------------------
assert(exist(retinoMatPath,'file')==2, 'Cannot find %s', retinoMatPath);
assert(exist(stimRefPath,'file')==2,   'Cannot find %s', stimRefPath);

if exist(outDir,'dir')~=7
    mkdir(outDir);
end

%% -------------------- LOAD RETINOTOPY DATA --------------------
S = load(retinoMatPath);

if isfield(S,'ReferenceImage')
    retRef = S.ReferenceImage;
elseif isfield(S,'maps') && isfield(S.maps,'ReferenceImage')
    retRef = S.maps.ReferenceImage;
else
    error('ReferenceImage not found in %s', retinoMatPath);
end

% Optional overlay
retOverlay = [];
if USE_VFS_BOUNDARIES_IF_AVAILABLE && isfield(S,'VFS_boundaries')
    retOverlay = S.VFS_boundaries;
elseif isfield(S,'VFS_processed')
    retOverlay = S.VFS_processed;
elseif isfield(S,'maps') && isfield(S.maps,'VFS_boundaries')
    retOverlay = S.maps.VFS_boundaries;
elseif isfield(S,'maps') && isfield(S.maps,'VFS_processed')
    retOverlay = S.maps.VFS_processed;
end

%% -------------------- LOAD STIM REFERENCE --------------------
stimRef = imread(stimRefPath);

retRefG  = mat2gray(toGrayDouble(retRef));
stimRefG = mat2gray(toGrayDouble(stimRef));

Rfixed = imref2d(size(stimRefG));

%% -------------------- LOAD / DRAW V1 MASK --------------------
v1MaskPath = fullfile(outDir, 'V1_mask_retino.mat');

if exist(v1MaskPath,'file')==2
    T = load(v1MaskPath);
    V1_mask_retino = T.V1_mask_retino;
    fprintf('Loaded V1 mask\n');
else
    fprintf('Draw V1 polygon...\n');

    figure('Name','Draw V1','Color','w');
    imshow(retRefG, []); hold on;

    if ~isempty(retOverlay)
        ovDisp = makeOverlayForDisplay(retOverlay);
        h = imshow(ovDisp);
        set(h,'AlphaData',OVERLAY_ALPHA);
    end

    hpoly = drawpolygon('Color','y','LineWidth',2);
    wait(hpoly);

    V1_mask_retino = poly2mask(hpoly.Position(:,1), hpoly.Position(:,2), ...
        size(retRefG,1), size(retRefG,2));

    save(v1MaskPath, 'V1_mask_retino');
    fprintf('Saved V1 mask\n');
end

%% -------------------- CPSELECT REGISTRATION --------------------
fprintf('\nSelect matching points (retino -> stim)\n');

[movingPts, fixedPts] = cpselect(retRefG, stimRefG, 'Wait', true);

assert(size(movingPts,1) >= 3, 'Need >=3 points');
assert(size(movingPts,1) == size(fixedPts,1), 'Point mismatch');

tform = fitgeotrans(movingPts, fixedPts, 'affine');

%% -------------------- WARP DATA --------------------
retRef_warp = imwarp(retRefG, tform, 'OutputView', Rfixed);

% Warp overlay
retOverlay_warp = [];
if ~isempty(retOverlay)
    retOverlay_warp = warpAnyImage(retOverlay, tform, Rfixed);
end

% Warp V1 mask
V1_mask_stim = imwarp(V1_mask_retino, tform, 'OutputView', Rfixed) > 0.5;

%% -------------------- QC FIGURES --------------------
figure;
imshowpair(stimRefG, retRef_warp, 'falsecolor');
title('Registration QC');

figure;
imshow(stimRefG, []); hold on;
visboundaries(V1_mask_stim, 'Color','y','LineWidth',1.5);
title('V1 on stim');

if ~isempty(retOverlay_warp)
    figure;
    imshow(stimRefG, []); hold on;
    ovDisp = makeOverlayForDisplay(retOverlay_warp);
    h = imshow(ovDisp);
    set(h,'AlphaData',OVERLAY_ALPHA);
    visboundaries(V1_mask_stim, 'Color','y','LineWidth',1.5);
end

%% -------------------- SAVE --------------------
save(fullfile(outDir,'tform_affine.mat'), 'tform');
save(fullfile(outDir,'V1_mask_stim.mat'), 'V1_mask_stim');

imwrite(im2uint8(stimRefG),    fullfile(outDir,'stimRef_gray.png'));
imwrite(im2uint8(retRef_warp), fullfile(outDir,'retRef_warp.png'));

fprintf('\nSaved outputs to %s\n', outDir);

%% -------------------- FUNCTIONS --------------------
function G = toGrayDouble(I)
    if isa(I,'uint16') || isa(I,'uint8')
        I = im2double(I);
    else
        I = double(I);
    end

    if ndims(I)==3
        if size(I,3)==3
            G = 0.2989*I(:,:,1) + 0.5870*I(:,:,2) + 0.1140*I(:,:,3);
        else
            G = I(:,:,1);
        end
    else
        G = I;
    end
end

function warped = warpAnyImage(img, tform, Rfixed)
    if ndims(img)==2
        warped = imwarp(img, tform, 'OutputView', Rfixed);
    else
        warped = zeros([Rfixed.ImageSize 3], 'like', img);
        for c = 1:3
            warped(:,:,c) = imwarp(img(:,:,c), tform, 'OutputView', Rfixed);
        end
    end
end

function ovDisp = makeOverlayForDisplay(ov)
    if ndims(ov)==2
        ovDisp = repmat(mat2gray(ov), 1,1,3);
    else
        ovDisp = mat2gray(ov);
    end
end