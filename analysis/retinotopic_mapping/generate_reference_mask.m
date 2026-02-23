% Makes a reference mask to identify where the window is and where the
% probes are located. Should be ran first
close all;
clc; clear;
% ------------------------------------------------------------
% USER: select the IMAGE folder directly (no naming assumptions)
% ------------------------------------------------------------
img_dir = uigetdir(pwd, 'Select folder containing image frames');
if isequal(img_dir, 0)
    error('No folder selected.');
end

% Verify images exist
image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    error('No .tif files found in %s', img_dir);
end

% Define chan_dir as parent (for saving outputs)
chan_dir = fileparts(img_dir);

% Put analysis folder next to image folder
analysisFolder = fullfile(chan_dir, 'analysis');
if ~exist(analysisFolder, 'dir')
    mkdir(analysisFolder);
end


% ------------------------------------------------------------
% Load images and build a reference image (average of first N frames)
% ------------------------------------------------------------
image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    error('No .tif files found in %s', img_dir);
end

% Sort by trailing digits (works for test1_00001.tif, etc.)
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

% Average first N frames to make a stable reference image
Nref = min(200, numel(image_files));
acc = 0;
for i = 1:Nref
    img = imread(fullfile(img_dir, image_files(i).name));
    acc = acc + double(img);
end
ref_img = acc / Nref;

% ------------------------------------------------------------
% COPY of your interactive mask drawing block (circle + rectangles)
% ------------------------------------------------------------

figure('Name', 'Define Masks', 'Position', [100, 100, 800, 600]);
imagesc(ref_img);
colormap(gray);
title('Define Circle and Rectangle Masks');
axis image;

% Let user draw a circular ROI
disp('Draw a circular region of interest:');
h_circle = drawcircle('Color', 'g', 'LineWidth', 2);
wait(h_circle);
circle_center = h_circle.Center;
circle_radius = h_circle.Radius;

% Create circle mask
[xx, yy] = meshgrid(1:size(ref_img, 2), 1:size(ref_img, 1));
circle_mask = ((xx - circle_center(1)).^2 + (yy - circle_center(2)).^2) <= (circle_radius^2);

% Let user draw rectangular exclusion regions inside the circle
disp('Draw rectangular exclusion regions inside the circle (double-click to finish each polygon):');

rectangle_masks = false(size(circle_mask));
rectangle_handles = [];

n_rectangles = input('Enter the shank number of the device: ');

for i = 1:n_rectangles
    disp(['Draw rectangle ', num2str(i), ' of ', num2str(n_rectangles)]);
    h_rect = drawpolygon('Color', 'r', 'LineWidth', 2);
    wait(h_rect);

    vertices = h_rect.Position;
    current_mask = poly2mask(vertices(:,1), vertices(:,2), size(rectangle_masks, 1), size(rectangle_masks, 2));

    rectangle_masks = rectangle_masks | current_mask;
    rectangle_handles = [rectangle_handles, h_rect]; %#ok<AGROW>
end

final_mask = circle_mask & ~rectangle_masks;

% Display the mask for verification
figure('Name', 'Verification', 'Position', [100, 100, 800, 600]);
imagesc(ref_img);
colormap(gray);
hold on;
h_mask = imagesc(cat(3, ~final_mask, zeros(size(final_mask)), zeros(size(final_mask))));
set(h_mask, 'AlphaData', 0.3);
title('Verification: Red areas will be excluded from analysis');
axis image;

response = questdlg('Is the mask correct?', 'Mask Verification', 'Yes', 'No, redo', 'Yes');
if strcmp(response, 'No, redo')
    error('Mask definition canceled. Please run the script again.');
end

saveas(gcf, fullfile(analysisFolder, 'reference_mask_confirmation.png'));

% ------------------------------------------------------------
% SAVE REFERENCE MASK FILE (this is what batch analysis loads)
% ------------------------------------------------------------
reference_mask_file = fullfile(chan_dir, 'reference_mask.mat');

save(reference_mask_file, ...
    'final_mask', ...
    'circle_mask', ...
    'rectangle_masks', ...
    'circle_center', ...
    'circle_radius', ...
    'ref_img', ...
    'chan_dir', ...
    'img_dir', ...
    '-v7.3');

disp(['Saved reference mask to: ', reference_mask_file]);
