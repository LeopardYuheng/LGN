function maskFile = wf_step0_auto_mask(imgDir, subjectId, dateStr, outFolder, cfg)
%WF_STEP0_AUTO_MASK  Pre-step B, automatic: find the brain boundary, you verify.
%
%   maskFile = WF_STEP0_AUTO_MASK(imgDir, subjectId, dateStr, outFolder, cfg)
%
% Averages the first cfg.mask.n_ref_frames TIFFs into a reference image,
% segments the brain with Otsu thresholding plus morphological cleanup, and
% shows you the result for approval. You can accept it, grow or shrink the
% boundary a few pixels at a time, or fall back to drawing it by hand with
% the original draw_brain_mask_0.m.
%
% The output file is byte-for-byte compatible with the manual step 0: same
% name, same reference_mask_struct fields, so every downstream step reads it
% without knowing the difference.
%
%   final_mask = circle_mask & ~rectangle_masks   still holds exactly, with
%   circle_mask the smallest circle enclosing the detected brain and
%   rectangle_masks everything inside that circle the segmentation rejected.

if nargin < 5 || isempty(cfg), cfg = wf_config(); end

maskFile = fullfile(outFolder, sprintf('%s_%s_brain_mask.mat', subjectId, dateStr));

if cfg.mask.reuse_existing && exist(maskFile, 'file') == 2
    wf_log('  step 0: reusing existing brain mask (%s)', wf_short(maskFile));
    return;
end

if exist(outFolder, 'dir') ~= 7, mkdir(outFolder); end

%% ---- reference image ---------------------------------------------------
ref_img = wf_reference_image(imgDir, cfg.mask.n_ref_frames);
wf_log('  step 0: reference image %dx%d from %d frames', ...
    size(ref_img,1), size(ref_img,2), cfg.mask.n_ref_frames);

%% ---- automatic segmentation -------------------------------------------
[final_mask, score] = wf_auto_brain_mask(ref_img, cfg.mask);

if isempty(final_mask)
    wf_log('  step 0: automatic segmentation found no plausible brain region');
    maskFile = wf_manual_fallback(imgDir, subjectId, dateStr, outFolder, maskFile);
    return;
end

wf_log('  step 0: auto mask covers %.1f%% of the frame (confidence %.2f)', ...
    100 * sum(final_mask(:)) / numel(final_mask), score);

%% ---- verification -----------------------------------------------------
if cfg.mask.verify
    [final_mask, action] = wf_verify_mask(ref_img, final_mask, subjectId, dateStr);
    switch action
        case 'manual'
            maskFile = wf_manual_fallback(imgDir, subjectId, dateStr, outFolder, maskFile);
            return;
        case 'cancel'
            % Treated as a stop rather than a failure, so the driver reports
            % it cleanly and does not offer to retry something the user
            % deliberately abandoned.
            wf_stop('request', 'cancelled at the brain mask');
            error('wf:stopped', 'Cancelled at the brain mask for %s %s.', ...
                subjectId, dateStr);
    end
end

%% ---- save in the manual step's format ---------------------------------
[circle_center, circle_radius] = wf_enclosing_circle(final_mask);
[xx, yy]        = meshgrid(1:size(ref_img,2), 1:size(ref_img,1));
circle_mask     = ((xx - circle_center(1)).^2 + (yy - circle_center(2)).^2) <= circle_radius^2;
rectangle_masks = circle_mask & ~final_mask;

reference_mask_struct                 = struct();
reference_mask_struct.final_mask      = logical(final_mask);
reference_mask_struct.circle_mask     = circle_mask;
reference_mask_struct.rectangle_masks = rectangle_masks;
reference_mask_struct.circle_center   = circle_center;
reference_mask_struct.circle_radius   = circle_radius;
reference_mask_struct.ref_img         = ref_img;
reference_mask_struct.img_dir         = imgDir;
reference_mask_struct.auto_generated  = true;
reference_mask_struct.auto_score      = score;
reference_mask_struct.auto_settings   = cfg.mask;

subject_id = subjectId;   %#ok<NASGU>
date_str   = dateStr;     %#ok<NASGU>
img_dir    = imgDir;      %#ok<NASGU>

save(maskFile, 'reference_mask_struct', 'subject_id', 'date_str', 'img_dir', '-v7.3');
wf_log('  step 0: saved %s', wf_short(maskFile));

end

% =====================================================================
function ref_img = wf_reference_image(imgDir, nRef)

files = [dir(fullfile(imgDir, '*.tif')); dir(fullfile(imgDir, '*.tiff'))];
assert(~isempty(files), 'wf_step0:noTiffs', 'No TIFF files found in:\n  %s', imgDir);

nums = nan(numel(files), 1);
for i = 1:numel(files)
    tok = regexp(files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'wf_step0:badName', ...
        'TIFF filename has no trailing numeric index: %s', files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord] = sort(nums);
files    = files(ord);

n   = min(nRef, numel(files));
acc = 0;
for i = 1:n
    acc = acc + double(imread(fullfile(imgDir, files(i).name)));
end
ref_img = acc / n;

end

% =====================================================================
function [best_mask, best_score] = wf_auto_brain_mask(ref_img, m)
%WF_AUTO_BRAIN_MASK  Otsu + morphology, evaluated against a plausibility score.
%
% The cranial window is normally the brighter part of the frame, but that
% flips with illumination and with a very dark window, so both polarities are
% segmented and the more brain-like result is kept. "Brain-like" means: area
% within the expected band, roughly convex, and centred rather than hugging
% an edge.

I = mat2gray(double(ref_img));
if m.smooth_sigma > 0
    I = imgaussfilt(I, m.smooth_sigma);
end

level = graythresh(I);
polarities = {I > level, I < level};

best_mask  = [];
best_score = -Inf;

for p = 1:2
    bw = polarities{p};

    bw = imfill(bw, 'holes');
    if m.close_radius > 0, bw = imclose(bw, strel('disk', m.close_radius)); end
    if m.open_radius  > 0, bw = imopen(bw,  strel('disk', m.open_radius));  end
    bw = imfill(bw, 'holes');

    if ~any(bw(:)), continue; end
    bw = bwareafilt(bw, 1);                      % largest connected region
    if m.erode_radius > 0, bw = imerode(bw, strel('disk', m.erode_radius)); end
    if ~any(bw(:)), continue; end

    s = wf_mask_score(bw, m);
    if s > best_score
        best_score = s;
        best_mask  = bw;
    end
end

if best_score <= 0
    best_mask  = [];
    best_score = 0;
end

end

% =====================================================================
function s = wf_mask_score(bw, m)
%WF_MASK_SCORE  How much does this region look like a cranial window?

[H, W] = size(bw);
area   = sum(bw(:));
frac   = area / (H * W);

if frac < m.min_area_frac || frac > m.max_area_frac
    s = 0;
    return;
end

st = regionprops(bw, 'Solidity', 'Centroid', 'BoundingBox');
if isempty(st), s = 0; return; end

% Convexity: a window is close to convex; scalp/edge artefacts are ragged.
solidity = st(1).Solidity;

% Centrality: distance of the centroid from the frame centre, normalised.
c        = st(1).Centroid;
dcent    = hypot(c(1) - W/2, c(2) - H/2) / hypot(W/2, H/2);
central  = 1 - min(dcent, 1);

% Touching the frame border is a strong sign of a runaway threshold.
border   = any(bw(1,:)) + any(bw(end,:)) + any(bw(:,1)) + any(bw(:,end));
borderOK = 1 - min(border, 4) / 4;

s = 0.45 * solidity + 0.35 * central + 0.20 * borderOK;

end

% =====================================================================
function [center, radius] = wf_enclosing_circle(bw)
%WF_ENCLOSING_CIRCLE  Smallest circle (centroid-based) containing the mask.

st = regionprops(bw, 'Centroid');
if isempty(st)
    [H, W] = size(bw);
    center = [W/2, H/2];
    radius = max(H, W) / 2;
    return;
end

center = st(1).Centroid;

B = bwboundaries(bw, 'noholes');
maxr = 0;
for k = 1:numel(B)
    p = B{k};                       % [row col]
    d = hypot(p(:,2) - center(1), p(:,1) - center(2));
    maxr = max(maxr, max(d));
end

radius = ceil(maxr) + 1;            % +1 px so the mask is strictly inside

end

% =====================================================================
function [mask_out, action] = wf_verify_mask(ref_img, mask_in, subjectId, dateStr)
%WF_VERIFY_MASK  Show the proposed mask and let the user accept or adjust it.

mask_out = logical(mask_in);
action   = 'accept';

fig = figure('Name', sprintf('Verify brain mask - %s %s', subjectId, dateStr), ...
             'NumberTitle', 'off', 'Color', 'w', ...
             'Position', [120 90 900 720], ...
             'CloseRequestFcn', @(s,e) uiresume(s));

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.06 0.16 0.88 0.78]);

state = struct('mask', mask_out, 'action', 'accept');
guidata(fig, state);

redraw();

btn = @(x, w, label, cb) uicontrol(fig, 'Style', 'pushbutton', 'String', label, ...
    'Units', 'normalized', 'Position', [x 0.04 w 0.07], ...
    'FontSize', 10, 'Callback', cb);

btn(0.06, 0.16, 'Accept',          @(s,e) finish(fig, 'accept'));
btn(0.24, 0.11, 'Grow 4 px',       @(s,e) adjust(fig,  4));
btn(0.36, 0.11, 'Shrink 4 px',     @(s,e) adjust(fig, -4));
btn(0.49, 0.22, 'Draw it myself',   @(s,e) finish(fig, 'manual'));
btn(0.73, 0.21, 'Stop the pipeline', @(s,e) finish(fig, 'cancel'));

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.115 0.88 0.035], 'BackgroundColor', 'w', ...
    'FontSize', 9, 'HorizontalAlignment', 'left', ...
    'String', ['Green outline = brain mask that every later step will use. ' ...
               'Grow/shrink nudges the boundary; "Draw it myself" opens the ' ...
               'original manual tool.']);

uiwait(fig);

if ishandle(fig)
    state = guidata(fig);
    mask_out = state.mask;
    action   = state.action;
    delete(fig);
end

    function redraw()
        st = guidata(fig);
        if isempty(st), st = state; end
        cla(ax);
        imagesc(ax, ref_img); colormap(ax, gray); axis(ax, 'image'); hold(ax, 'on');
        ov = imagesc(ax, cat(3, double(~st.mask), zeros(size(st.mask)), zeros(size(st.mask))));
        set(ov, 'AlphaData', 0.18);
        visboundaries(ax, st.mask, 'Color', [0.1 0.9 0.3], 'LineWidth', 2);
        title(ax, sprintf('%s  %s     %d brain pixels (%.1f%% of frame)', ...
            subjectId, dateStr, sum(st.mask(:)), ...
            100 * sum(st.mask(:)) / numel(st.mask)), 'FontSize', 11);
        hold(ax, 'off');
    end

    function adjust(h, px)
        st = guidata(h);
        if px > 0
            st.mask = imdilate(st.mask, strel('disk', px));
        else
            st.mask = imerode(st.mask, strel('disk', -px));
        end
        guidata(h, st);
        redraw();
    end

    function finish(h, act)
        st = guidata(h);
        st.action = act;
        guidata(h, st);
        uiresume(h);
    end

end

% =====================================================================
function maskFile = wf_manual_fallback(imgDir, subjectId, dateStr, outFolder, maskFile)
%WF_MANUAL_FALLBACK  Hand over to the original interactive draw_brain_mask_0.
%
% Its folder and metadata prompts are filled in automatically; the drawing
% itself and the exclusion-region count are left to the user, which is the
% whole point of this path. Strict mode is off so any prompt we did not
% anticipate simply appears.

P = wf_paths();
wf_log('  step 0: handing over to manual draw_brain_mask_0.m');

answers = wf_ans( ...
    'uigetdir',  'stimulation-day TIFF frames',   imgDir, ...
    'inputdlg',  'Session metadata',              {subjectId, dateStr}, ...
    'uigetdir',  'save brain_mask',               outFolder);

wf_run_script(P.single.step0, answers, struct('strict', false));

assert(exist(maskFile, 'file') == 2, 'wf_step0:manualFailed', ...
    ['The manual mask tool did not produce the expected file:\n  %s\n' ...
     'Check that the subject ID and date entered there match %s / %s.'], ...
    maskFile, subjectId, dateStr);

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
