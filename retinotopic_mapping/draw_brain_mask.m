%% draw_brain_mask.m
% Standalone script to draw a brain-area mask for the retinotopic mapping pipeline.
%
% Run this ONCE per session, before (or after) running the retinotopic mapping
% script. It produces brain_mask.mat, which the retinotopic mapping scripts
% (both the output-only and input+output masking versions) load and apply so
% that azi/alt/VFS are restricted to the true brain area instead of cement/skull.
%
% Procedure:
%   1. Select the folder containing the widefield .tif frames.
%   2. NREF frames are averaged into a clean reference image.
%   3. Draw a circle around the brain.
%   4. Optionally draw polygon(s) over regions to exclude (e.g. shank shadows,
%      bright cement, blood vessels).
%   5. Verify, then save.
%
% Output (saved where you choose):
%   brain_mask.mat containing:
%     brain_mask     - logical H x W mask, TRUE = keep (brain), in RAW image space
%     ref_img        - averaged reference image (H x W), for verification/overlay
%     circle_center  - [x y] of the drawn circle
%     circle_radius  - radius of the drawn circle
%     img_dir        - source image folder
%
% NOTE on coordinate space:
%   brain_mask is saved in RAW image space (same H x W as the .tif frames, i.e.
%   the same space as first_img in the retinotopic script). The retinotopic
%   script rotates it (rot90) to align with the azi/alt maps, because
%   getRetinotopicMap internally rot90's the phase maps. A verification overlay
%   is produced there so you can confirm alignment.

close all; clc; clear; fclose('all');

%% USER SETTINGS
NREF = 200;   % number of frames to average for the reference image

%% SELECT INPUTS
img_dir = uigetdir(pwd, 'Select folder containing the widefield .tif frames');
if isequal(img_dir, 0), error('No image folder selected.'); end

output_folder = uigetdir(img_dir, 'Select folder to save brain_mask.mat');
if isequal(output_folder, 0), error('No output folder selected.'); end

%% LOAD AND AVERAGE FRAMES
image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    image_files = dir(fullfile(img_dir, '*.tiff'));
end
assert(~isempty(image_files), 'No TIFF files found in:\n  %s', img_dir);

% Sort by the trailing numeric index in the filename
nFiles = numel(image_files);
file_numbers = zeros(nFiles, 1);
for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    if isempty(tok)
        error('Filename "%s" has no trailing numeric index.', image_files(i).name);
    end
    file_numbers(i) = str2double(tok{1});
end
[~, sort_idx] = sort(file_numbers);
image_files = image_files(sort_idx);

Nref = min(NREF, nFiles);
fprintf('Averaging %d frames for the reference image...\n', Nref);
acc = 0;
for i = 1:Nref
    acc = acc + double(imread(fullfile(img_dir, image_files(i).name)));
end
ref_img = acc / Nref;

%% INTERACTIVE MASK DRAWING (with redo loop)
done = false;
while ~done
    close all;

    % --- Step 1: draw brain circle ---
    figure('Name', 'Step 1: Draw circle around brain', 'Position', [100 100 800 650]);
    imagesc(ref_img); colormap(gray); axis image;
    title({'Draw a circle around the brain region.', ...
           'Double-click or press Enter when done.'}, 'FontSize', 11);

    h_circle = drawcircle('Color', 'g', 'LineWidth', 2);
    wait(h_circle);
    circle_center = h_circle.Center;
    circle_radius = h_circle.Radius;

    [xx, yy] = meshgrid(1:size(ref_img,2), 1:size(ref_img,1));
    circle_mask = ((xx - circle_center(1)).^2 + (yy - circle_center(2)).^2) <= circle_radius^2;

    % --- Step 2: exclusion regions ---
    n_rect_ans = inputdlg( ...
        'How many exclusion regions to draw? (e.g. shank shadows / cement; 0 = none)', ...
        'Exclusion regions', [1 65], {'0'});
    if isempty(n_rect_ans), error('User cancelled.'); end
    n_rect = max(0, round(str2double(n_rect_ans{1})));

    exclusion_masks = false(size(circle_mask));
    for i = 1:n_rect
        figure('Name', sprintf('Step 2: Draw exclusion region %d of %d', i, n_rect), ...
               'Position', [100 100 800 650]);
        imagesc(ref_img); colormap(gray); axis image; hold on;
        h_ov = imagesc(cat(3, zeros(size(circle_mask)), double(circle_mask)*0.5, zeros(size(circle_mask))));
        set(h_ov, 'AlphaData', 0.3);
        title(sprintf('Draw exclusion polygon %d of %d', i, n_rect), 'FontSize', 11);

        h_poly = drawpolygon('Color', 'r', 'LineWidth', 2);
        wait(h_poly);
        verts = h_poly.Position;
        cur_mask = poly2mask(verts(:,1), verts(:,2), size(exclusion_masks,1), size(exclusion_masks,2));
        exclusion_masks = exclusion_masks | cur_mask;
    end

    brain_mask = circle_mask & ~exclusion_masks;

    % --- Verification ---
    close all;
    figure('Name', 'Verify brain mask', 'Position', [100 100 800 650]);
    imagesc(ref_img); colormap(gray); axis image; hold on;
    h_red = imagesc(cat(3, double(~brain_mask & circle_mask), ...
                           zeros(size(brain_mask)), zeros(size(brain_mask))));
    set(h_red, 'AlphaData', 0.35);
    visboundaries(brain_mask, 'Color', 'g', 'LineWidth', 2);
    title({'Green boundary = brain mask.  Red = excluded regions.', ...
           'Inspect the mask, then answer the dialog.'}, 'FontSize', 11);

    resp = questdlg('Accept this mask?', 'Mask verification', 'Yes, save', 'No, redo', 'Yes, save');
    if isempty(resp) || strcmp(resp, 'No, redo')
        fprintf('Redrawing mask...\n');
    else
        done = true;
    end
end

%% SAVE
save_path = fullfile(output_folder, 'brain_mask.mat');
save(save_path, 'brain_mask', 'ref_img', 'circle_center', 'circle_radius', 'img_dir', '-v7.3');

fprintf('\nBrain mask saved:\n  %s\n', save_path);
fprintf('Image size: %d x %d  |  Brain pixels: %d  |  Excluded within circle: %d\n', ...
    size(brain_mask,1), size(brain_mask,2), sum(brain_mask(:)), ...
    sum(circle_mask(:)) - sum(brain_mask(:)));

close all;
