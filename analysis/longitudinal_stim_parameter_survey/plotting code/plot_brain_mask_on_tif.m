%% plot_brain_mask_on_tif.m
% Plotting-only tool: draws the brain mask (from draw_brain_mask_0.m /
% day_setup) as a green boundary on top of the wide-field TIFF reference
% image.
%
% Orientation note:
%   draw_brain_mask_0.m and retino_alignment_with_brain_mask_6.m display
%   the reference image with MATLAB's default image orientation (row 1 at
%   the top, i.e. default/reverse YDir). Every dF/F analysis figure in
%   this pipeline (step 5_A, 7_A, ...) instead explicitly sets
%   'YDir','normal' (row 1 at the bottom). Both display the SAME
%   underlying pixel array — only the axis convention differs — so this
%   script sets 'YDir','normal' to make the brain mask figure match the
%   orientation of the step-5_A output figures exactly, not the
%   orientation used when the mask was originally drawn.
%
% Background image source (user choice):
%   1. The averaged reference image already stored in the mask file
%      (reference_mask_struct.ref_img) — fastest, guaranteed pixel-aligned
%      with the mask.
%   2. A fresh average of N TIFF frames from a folder (defaults to the
%      img_dir recorded in the mask file, but a different folder can be
%      selected).

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color   = [0.10 0.85 0.30];   % green brain-mask boundary
mask_lw      = 1.8;
font_size_title = 14;
default_nref = 200;

%% -------------------------
% SELECT BRAIN MASK FILE
% -------------------------
[mask_fn, mask_fp] = uigetfile('*brain_mask.mat', ...
    'Select a brain_mask.mat file (from draw_brain_mask_0.m)');
if isequal(mask_fn, 0), error('No brain mask file selected.'); end
mask_fpath = fullfile(mask_fp, mask_fn);

M = load(mask_fpath);
assert(isfield(M, 'reference_mask_struct'), ...
    'Selected file does not contain reference_mask_struct:\n  %s', mask_fpath);
reference_mask_struct = M.reference_mask_struct;
final_mask = logical(reference_mask_struct.final_mask);
[H, W] = size(final_mask);
fprintf('Loaded brain mask: %s  (%d x %d, %d brain pixels)\n', ...
    mask_fn, H, W, sum(final_mask(:)));

%% -------------------------
% CHOOSE BACKGROUND IMAGE SOURCE
% -------------------------
has_ref_img = isfield(reference_mask_struct, 'ref_img') && ...
    ~isempty(reference_mask_struct.ref_img);

src_opts = {};
if has_ref_img, src_opts{end+1} = 'Use saved reference image'; end
src_opts{end+1} = 'Average TIFF frames from a folder';

if numel(src_opts) > 1
    src_choice = questdlg('Background wide-field image source:', ...
        'Background image', src_opts{:}, src_opts{1});
    if isempty(src_choice), error('No background image source selected.'); end
else
    src_choice = src_opts{1};
end

if strcmp(src_choice, 'Use saved reference image')
    ref_img = double(reference_mask_struct.ref_img);
    fprintf('Using saved reference image from mask file.\n');
else
    % Default to the img_dir recorded when the mask was drawn, if it
    % still exists; otherwise let the user browse for one.
    default_img_dir = pwd;
    if isfield(reference_mask_struct, 'img_dir') && ...
            exist(reference_mask_struct.img_dir, 'dir')
        default_img_dir = reference_mask_struct.img_dir;
    end
    img_dir = uigetdir(default_img_dir, 'Select folder containing wide-field TIFF frames');
    if isequal(img_dir, 0), error('No TIFF folder selected.'); end

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

    nref_ans = inputdlg('Number of TIFF frames to average:', ...
        'Reference frame averaging', [1 50], {num2str(default_nref)});
    if isempty(nref_ans), error('User cancelled.'); end
    n_ref = max(1, round(str2double(nref_ans{1})));
    n_ref = min(n_ref, nFiles);

    fprintf('Averaging %d frame(s) from:\n  %s\n', n_ref, img_dir);
    acc = 0;
    for i = 1:n_ref
        acc = acc + double(imread(fullfile(img_dir, image_files(i).name)));
    end
    ref_img = acc / n_ref;
end

assert(isequal(size(ref_img), [H W]), ...
    'Background image size (%d x %d) does not match brain mask size (%d x %d).', ...
    size(ref_img,1), size(ref_img,2), H, W);

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(mask_fp, 'Select output folder for the figure');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% PLOT — same axis orientation convention as step 5_A ('YDir','normal')
% -------------------------
[~, mask_base, ~] = fileparts(mask_fn);

fig = figure('Color', 'w', 'Name', sprintf('Brain mask on TIFF - %s', mask_base), ...
    'Position', [100 100 800 700]);
ax = axes(fig);
imagesc(ax, ref_img);
colormap(ax, gray);
axis(ax, 'image'); axis(ax, 'off');
set(ax, 'YDir', 'normal');   % matches step 5_A / 7_A output orientation
hold(ax, 'on');
visboundaries(ax, final_mask, 'Color', mask_color, 'LineWidth', mask_lw);
title(ax, sprintf('Brain mask  |  %s', mask_base), ...
    'Interpreter', 'none', 'FontSize', font_size_title);

fig_fname = sprintf('%s_on_tif.png', mask_base);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', fullfile(save_dir, fig_fname));