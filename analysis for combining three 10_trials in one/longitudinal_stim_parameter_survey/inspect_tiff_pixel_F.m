%% inspect_tiff_pixel_F.m
% Import a TIFF and inspect its pixelwise raw F values interactively.
%
% Prompts you to pick a TIFF, displays it as a grayscale F map with a
% colorbar, and lets you hover/click any pixel to read its (x, y) and raw F
% value via a data tip. Also prints basic stats to the command window.
%
% If the TIFF has multiple frames you are asked which frame to inspect.

close all; clc;

%% -------------------------
% SELECT A TIFF
% -------------------------
[fn, fp] = uigetfile({'*.tif;*.tiff', 'TIFF images (*.tif, *.tiff)'; ...
                      '*.*', 'All files (*.*)'}, 'Select a TIFF image');
if isequal(fn, 0), error('No file selected.'); end
fpath = fullfile(fp, fn);

%% -------------------------
% PICK A FRAME (if multi-page)
% -------------------------
info    = imfinfo(fpath);
nFrames = numel(info);
frame   = 1;
if nFrames > 1
    resp = inputdlg(sprintf('This TIFF has %d frames. Which frame? (1-%d)', nFrames, nFrames), ...
        'Select frame', [1 40], {'1'});
    if isempty(resp), error('Cancelled.'); end
    frame = max(1, min(nFrames, round(str2double(resp{1}))));
end

%% -------------------------
% READ AND REPORT
% -------------------------
F = double(imread(fpath, frame));
[H, W] = size(F);
fprintf('Loaded: %s  (frame %d/%d)\n', fn, frame, nFrames);
fprintf('Size: %d x %d  |  F min %.4g, max %.4g, mean %.4g, median %.4g\n', ...
    H, W, min(F(:)), max(F(:)), mean(F(:)), median(F(:)));

%% -------------------------
% DISPLAY + INTERACTIVE PIXEL READOUT
% -------------------------
fig = figure('Color', 'w', 'Name', sprintf('Pixelwise F — %s', fn), 'NumberTitle', 'off');
imagesc(F);
colormap(gray(256));
axis image;
cb = colorbar; cb.Label.String = 'F (counts)';
xlabel('x (column)'); ylabel('y (row)');
title(sprintf('%s | frame %d/%d | %d x %d   (hover/click a pixel to read F)', ...
    fn, frame, nFrames, H, W), 'Interpreter', 'none');

dcm = datacursormode(fig);
set(dcm, 'Enable', 'on', 'SnapToDataVertex', 'off', ...
    'UpdateFcn', @(~, evt) cursor_text(evt, F));

fprintf('Tip: click a pixel to drop a data tip showing its x, y and F value.\n');

%% =========================
% LOCAL FUNCTION
%% =========================
function txt = cursor_text(evt, F)
pos = get(evt, 'Position');          % [x(col)  y(row)]
[H, W] = size(F);
c = max(1, min(W, round(pos(1))));
r = max(1, min(H, round(pos(2))));
val = F(r, c);
txt = {sprintf('x (col): %d', c), ...
       sprintf('y (row): %d', r), ...
       sprintf('F: %g', val)};
end
