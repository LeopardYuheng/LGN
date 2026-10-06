





%% draw_brain_mask_0.m
% Draws the brain boundary mask from stimulation-day TIFF frames.
%
% This is the first step in the analysis pipeline. It defines which pixels
% in the widefield image are inside the brain (vs. scalp, skull edge, or
% electrode shank shadows). The saved mask is used by:
%   - Step 4 (dF/F movie computation) to restrict analysis to brain pixels
%   - Step 5 (retino_alignment_with_brain_mask.m) to skip redrawing the mask
%
% Procedure:
%   1. Averages NREF TIFF frames into a clean reference image
%   2. User draws a circle around the brain
%   3. User draws polygon(s) over any exclusion regions (e.g. shank shadows)
%   4. Verify and save
%
% Output:
%   {output_folder}/{subject_id}_{date_str}_brain_mask.mat
%
%   Saved variables:
%     reference_mask_struct.final_mask       - logical H x W brain mask
%     reference_mask_struct.circle_mask      - the drawn circle
%     reference_mask_struct.rectangle_masks  - drawn exclusion polygons combined
%     reference_mask_struct.circle_center
%     reference_mask_struct.circle_radius
%     reference_mask_struct.ref_img          - averaged reference image
%     reference_mask_struct.img_dir
%     subject_id, date_str

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
NREF = 200;  % number of TIFF frames to average for the reference image

%% -------------------------
% SELECT INPUTS
% -------------------------
img_dir = uigetdir(pwd, 'Select folder containing stimulation-day TIFF frames');
if isequal(img_dir, 0), error('No image folder selected.'); end

prompt    = {'Subject ID (e.g. LGN11):', 'Date (YYYYMMDD):'};
dlg_title = 'Session metadata';
dims      = [1 60];
definput  = {'', ''};
answ = inputdlg(prompt, dlg_title, dims, definput);
if isempty(answ), error('User cancelled.'); end
subject_id = strtrim(answ{1});
date_str   = strtrim(answ{2});

if isempty(subject_id)
    error('Subject ID is required.');
end
if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be YYYYMMDD.');
end

output_folder = uigetdir(pwd, 'Select output folder to save brain_mask.mat');
if isequal(output_folder, 0), error('No output folder selected.'); end

%% -------------------------
% LOAD AND AVERAGE TIFF FRAMES
% -------------------------
image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    image_files = dir(fullfile(img_dir, '*.tiff'));
end
assert(~isempty(image_files), 'No TIFF files found in:\n  %s', img_dir);

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
fprintf('Averaging %d frames for reference image...\n', Nref);
acc = 0;
for i = 1:Nref
    acc = acc + double(imread(fullfile(img_dir, image_files(i).name)));
end
ref_img = acc / Nref;

%% -------------------------
% INTERACTIVE MASK DRAWING (with redo loop)
% -------------------------
done = false;
while ~done

    close all;

    % --- Step 1: draw brain circle ---
    figure('Name', 'Step 1: Draw circle around brain', ...
           'Position', [100 100 800 650]);
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
        'How many exclusion regions to draw? (e.g. electrode shank shadows; 0 = none)', ...
        'Exclusion regions', [1 65], {'0'});
    if isempty(n_rect_ans), error('User cancelled.'); end
    n_rect = max(0, round(str2double(n_rect_ans{1})));

    rectangle_masks = false(size(circle_mask));

    for i = 1:n_rect
        figure('Name', sprintf('Step 2: Draw exclusion region %d of %d', i, n_rect), ...
               'Position', [100 100 800 650]);
        imagesc(ref_img); colormap(gray); axis image; hold on;
        h_ov = imagesc(cat(3, zeros(size(circle_mask)), ...
                              double(circle_mask) * 0.5, ...
                              zeros(size(circle_mask))));
        set(h_ov, 'AlphaData', 0.3);
        title(sprintf('Draw exclusion polygon %d of %d', i, n_rect), 'FontSize', 11);

        h_poly = drawpolygon('Color', 'r', 'LineWidth', 2);
        wait(h_poly);
        verts = h_poly.Position;
        cur_mask = poly2mask(verts(:,1), verts(:,2), ...
                             size(rectangle_masks,1), size(rectangle_masks,2));
        rectangle_masks = rectangle_masks | cur_mask;
    end

    final_mask = circle_mask & ~rectangle_masks;

    % --- Verification ---
    close all;
    figure('Name', 'Verify brain mask', 'Position', [100 100 800 650]);
    imagesc(ref_img); colormap(gray); axis image; hold on;
    h_red = imagesc(cat(3, double(~final_mask & circle_mask), ...
                           zeros(size(final_mask)), ...
                           zeros(size(final_mask))));
    set(h_red, 'AlphaData', 0.35);
    visboundaries(final_mask, 'Color', 'g', 'LineWidth', 2);
    title({'Green boundary = brain mask.  Red = excluded regions.', ...
           'Inspect the mask, then answer the dialog.'}, 'FontSize', 11);

    resp = questdlg('Accept this mask?', 'Mask verification', ...
                    'Yes, save', 'No, redo', 'Yes, save');
    if isempty(resp) || strcmp(resp, 'No, redo')
        fprintf('Redrawing mask...\n');
    else
        done = true;
    end

end

%% -------------------------
% SAVE
% -------------------------
reference_mask_struct = struct();
reference_mask_struct.final_mask      = final_mask;
reference_mask_struct.circle_mask     = circle_mask;
reference_mask_struct.rectangle_masks = rectangle_masks;
reference_mask_struct.circle_center   = circle_center;
reference_mask_struct.circle_radius   = circle_radius;
reference_mask_struct.ref_img         = ref_img;
reference_mask_struct.img_dir         = img_dir;

save_name = sprintf('%s_%s_brain_mask.mat', subject_id, date_str);
save_path = fullfile(output_folder, save_name);
save(save_path, 'reference_mask_struct', 'subject_id', 'date_str', 'img_dir', '-v7.3');

fprintf('\nBrain mask saved:\n  %s\n', save_path);
fprintf('Image size: %d x %d  |  Brain pixels: %d  |  Excluded within circle: %d\n', ...
    size(final_mask,1), size(final_mask,2), sum(final_mask(:)), ...
    sum(circle_mask(:)) - sum(final_mask(:)));

close all;
