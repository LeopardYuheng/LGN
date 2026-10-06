function action = wf_verify_retino_map(readyFile, subject, dateStr, sourceNote)
%WF_VERIFY_RETINO_MAP  Show a retinotopy file and ask if it is the right one.
%
%   action = WF_VERIFY_RETINO_MAP(readyFile, subject, dateStr, sourceNote)
%
% readyFile is a retino_registration_ready.mat holding azi, alt,
% ReferenceImage and, usually, VFS_boundaries or VFS_processed.
%
% Returns
%   'accept'  use this map for this experiment
%   'choose'  pick a different retinotopy folder and rebuild
%   'skip'    no V1 overlay for this experiment
%
% WHY THIS EXISTS
%   Retinotopy files get reused across sessions of the same animal, and the
%   pipeline may reuse one it found from an earlier experiment. A map from
%   the wrong animal, or from a session where the field of view had moved,
%   produces a V1 boundary that is wrong everywhere while looking completely
%   ordinary on the figures. Showing the maps costs a few seconds and makes
%   that mistake impossible to make silently.

if nargin < 4, sourceNote = ''; end

action = 'accept';

S = load(readyFile);

azi = wf_field(S, 'azi');
alt = wf_field(S, 'alt');
ref = wf_field(S, 'ReferenceImage');
bnd = wf_field(S, 'VFS_boundaries');
if isempty(bnd), bnd = wf_field(S, 'VFS_processed'); end

if isempty(ref) && ~isempty(azi)
    ref = zeros(size(azi));
end
if isempty(ref)
    warning('wf_verify_retino:noMaps', ...
        'Could not read maps from %s - accepting it unchecked.', readyFile);
    return;
end

fig = figure('Name', sprintf('Is this the right retinotopy for %s %s?', subject, dateStr), ...
             'NumberTitle', 'off', 'Color', 'w', ...
             'Position', [80 90 1280 620], ...
             'CloseRequestFcn', @(s,e) finish('accept'));

% ---- panel 1: reference image with visual-area boundaries --------------
ax1 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.03 0.26 0.29 0.62]);
imagesc(ax1, wf_gray(ref)); colormap(ax1, gray); axis(ax1, 'image'); hold(ax1, 'on');
if ~isempty(bnd)
    b = wf_boundary_mask(bnd, size(ref));
    if any(b(:))
        ov = imagesc(ax1, cat(3, ones(size(b)), 0.55 * ones(size(b)), zeros(size(b))));
        set(ov, 'AlphaData', double(imdilate(b, strel('disk', 1))));
    end
end
title(ax1, 'Retinotopy reference + visual areas', 'FontSize', 10);
set(ax1, 'XTick', [], 'YTick', []); hold(ax1, 'off');

% ---- panel 2: azimuth ---------------------------------------------------
ax2 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.36 0.26 0.29 0.62]);
if ~isempty(azi)
    imagesc(ax2, azi); axis(ax2, 'image'); colormap(ax2, parula);
    c = colorbar(ax2); c.Label.String = 'Azimuth (deg)';
end
title(ax2, 'Azimuth', 'FontSize', 10);
set(ax2, 'XTick', [], 'YTick', []);

% ---- panel 3: altitude --------------------------------------------------
ax3 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.69 0.26 0.29 0.62]);
if ~isempty(alt)
    imagesc(ax3, alt); axis(ax3, 'image'); colormap(ax3, parula);
    c = colorbar(ax3); c.Label.String = 'Altitude (deg)';
end
title(ax3, 'Altitude', 'FontSize', 10);
set(ax3, 'XTick', [], 'YTick', []);

% ---- header and provenance ---------------------------------------------
uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.03 0.90 0.94 0.06], 'BackgroundColor', 'w', ...
    'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'String', sprintf('%s   %s   -   is this the correct retinotopic map?', ...
                      subject, wf_pretty_date(dateStr)));

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.03 0.155 0.94 0.09], 'BackgroundColor', 'w', ...
    'FontSize', 9, 'ForegroundColor', [0.3 0.3 0.35], ...
    'HorizontalAlignment', 'left', ...
    'String', sprintf('File: %s\n%s', readyFile, sourceNote));

% ---- buttons ------------------------------------------------------------
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Yes, use this map', ...
    'Units', 'normalized', 'Position', [0.03 0.04 0.22 0.085], ...
    'FontSize', 11, 'FontWeight', 'bold', 'Callback', @(s,e) finish('accept'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'No, pick a different folder', ...
    'Units', 'normalized', 'Position', [0.27 0.04 0.26 0.085], ...
    'FontSize', 11, 'Callback', @(s,e) finish('choose'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip step 6 for this experiment', ...
    'Units', 'normalized', 'Position', [0.71 0.04 0.26 0.085], ...
    'FontSize', 10, 'Callback', @(s,e) finish('skip'));

guidata(fig, struct('action', 'accept'));
uiwait(fig);

if ishandle(fig)
    st     = guidata(fig);
    action = st.action;
    delete(fig);
end

    function finish(act)
        if ~ishandle(fig), return; end
        guidata(fig, struct('action', act));
        uiresume(fig);
    end

end

% =====================================================================
function v = wf_field(S, name)
%WF_FIELD  Read a map whether it sits at the top level or inside a struct.

v = [];
if isfield(S, name)
    v = S.(name);
    return;
end

for holder = {'registration_ready', 'out', 'maps'}
    h = holder{1};
    if isfield(S, h) && isstruct(S.(h)) && isfield(S.(h), name)
        v = S.(h).(name);
        return;
    end
end

end

% =====================================================================
function b = wf_boundary_mask(raw, targetSize)
%WF_BOUNDARY_MASK  Boundary map as a logical mask on the reference grid.

raw = double(raw);
if size(raw,1) ~= targetSize(1) || size(raw,2) ~= targetSize(2)
    raw = imresize(raw, targetSize(1:2), 'nearest');
end

u = unique(raw(isfinite(raw)));
if numel(u) <= 2
    b = raw > 0.5;                 % already a boundary mask
else
    b = imgradient(raw) > 0;       % a patch/sign map: take its edges
end

end

% =====================================================================
function G = wf_gray(I)

I = double(I);
if ndims(I) == 3, I = mean(I, 3); end
lo = min(I(:));
hi = max(I(:));
if hi > lo, G = (I - lo) / (hi - lo); else, G = zeros(size(I)); end

end

% =====================================================================
function s = wf_pretty_date(d)

if numel(d) == 8
    s = sprintf('%s-%s-%s', d(1:4), d(5:6), d(7:8));
else
    s = d;
end

end
