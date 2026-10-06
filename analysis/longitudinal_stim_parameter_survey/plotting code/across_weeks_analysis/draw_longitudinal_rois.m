
%% draw_longitudinal_rois.m
% Draw ONE circular ROI per (channel, week) across the whole longitudinal
% tree, and save them all to one file for the extraction step.
%
% Hand-drawn per session, as agreed — but never from scratch on a week
% where there may be no response to aim at. Each session opens with the
% PREVIOUS week's circle already in place; you drag/resize it to match this
% week's anatomy and press Accept, or redraw it from scratch if the FOV
% moved. The first session of each channel is drawn fresh, and sessions are
% walked in time order starting from pre-blindness, so the circle is always
% inherited from a week where the response was visible.
%
% This matters for more than convenience: drawing a fresh circle on a dead
% week means hunting for the best-looking noise, which inflates post-blind
% dF/F and shrinks the very effect these figures are meant to show.
%
% Progress is saved after every session, so you can quit and resume; a
% session that already has an ROI is skipped unless REDO_EXISTING is true.
%
% Output:
%   <root>/rois_longitudinal.mat   struct array (what extraction reads)
%   <root>/rois_longitudinal.csv   same thing, human-readable
%
% Controls per session:
%   drag / resize the magenta circle   position it
%   Accept (or Enter)                  save and go to the next session
%   Redraw                             discard and draw a fresh circle
%   Skip                               no ROI for this session
%   Quit & save                        stop, keeping everything so far

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
ref_time_s         = 0.5;                % frame the viewer opens on (s)
default_radius_px  = 35;                 % first circle of a channel
circle_color       = [1.00 0.00 1.00];   % magenta: absent from jet
mask_color_outside = [0.15 0.15 0.15];
REDO_EXISTING      = false;              % true = revisit sessions already drawn

% Restrict this pass to certain channel folders (empty = every channel), so
% you can finish the channels one figure needs before doing the rest.
% Figures 2 and 3 use only the six full-history channels:
%   {'LGN24_CH49-','LGN24_CH97-','LGN24_CH101-','LGN24_CH105-', ...
%    'LGN26_CH101-','LGN26_CH106-'}
% Everything already drawn is kept, so narrowing here never loses work.
%only_chan_folders  = {};
only_chan_folders = {'LGN24_CH97-'};

%% -------------------------
% SCAN THE TREE
% -------------------------
root_dir = uigetdir('C:\Projects\LGN\weekly update\plots for presentation', ...
    'Select the longitudinal_data folder');
if isequal(root_dir, 0), error('No folder selected.'); end

S = wf_scan_longitudinal(root_dir);
fprintf('Indexed %d session(s) across %d channel(s).\n', ...
    numel(S), numel(unique(string({S.chan_folder}))));

if ~isempty(only_chan_folders)
    keep = ismember(string({S.chan_folder}), string(only_chan_folders));
    missing = setdiff(string(only_chan_folders), string({S.chan_folder}));
    if ~isempty(missing)
        warning('No such channel folder(s) in the tree: %s', strjoin(missing, ', '));
    end
    S = S(keep);
    assert(~isempty(S), 'only_chan_folders matched nothing.');
    fprintf('Restricted to %d session(s) across %d channel(s).\n', ...
        numel(S), numel(unique(string({S.chan_folder}))));
end
n_sess = numel(S);

roi_file = fullfile(root_dir, 'rois_longitudinal.mat');
rois = empty_roi_struct();
if isfile(roi_file)
    L = load(roi_file);
    if isfield(L, 'rois'), rois = L.rois; end
    fprintf('Loaded %d existing ROI(s) from %s\n', numel(rois), roi_file);
end

cmap = jet(256);
n_done = 0; n_skipped = 0;

%% -------------------------
% WALK SESSIONS IN TIME ORDER, CHANNEL BY CHANNEL
% -------------------------
for si = 1:n_sess
    s = S(si);
    key_idx = find_roi(rois, s.chan_folder, s.week_folder);
    if ~isempty(key_idx) && ~REDO_EXISTING
        continue;   % already drawn in an earlier sitting
    end

    % Reference movie: the strongest current available that week, so the
    % blob (when there is one) is as visible as possible while placing the
    % circle. The ROI itself is then applied to every current.
    [ref_cur, ci_ref] = max(s.currents);
    M = load(s.files{ci_ref});
    if isfield(M, 'mean_dff_movie'), movie = M.mean_dff_movie;
    elseif isfield(M, 'dff_movie'),  movie = M.dff_movie;
    else, warning('No dF/F movie in %s -- skipped.', s.files{ci_ref}); continue; end
    t_s = double(M.t_s(:)');
    if isfield(M, 'final_mask'), valid_mask = logical(M.final_mask);
    else,                        valid_mask = ~all(isnan(movie), 3); end

    % Seed circle: this channel's most recent earlier week, else frame centre
    seed = last_roi_for_channel(rois, s.chan_folder, s.week_index);
    if isempty(seed)
        seed = struct('center', [size(movie, 2) size(movie, 1)] / 2, ...
            'radius', default_radius_px);
        seed_txt = 'fresh (first week of this channel)';
    else
        seed_txt = sprintf('inherited from %s', seed.week_label);
    end

    [~, f0] = min(abs(t_s - ref_time_s));
    hdr = sprintf('[%d/%d]  %s  ch%d  |  %s  |  %g uA  |  %s', ...
        si, n_sess, s.mouse, s.channel, s.week_label, ref_cur, seed_txt);
    fprintf('%s\n', hdr);

    out = place_circle(movie, valid_mask, t_s, f0, seed, cmap, ...
        mask_color_outside, circle_color, hdr);

    if strcmp(out.action, 'quit'), fprintf('Quitting at your request.\n'); break; end
    if strcmp(out.action, 'skip')
        fprintf('  skipped\n'); n_skipped = n_skipped + 1; continue;
    end

    rec = struct('chan_folder', s.chan_folder, 'week_folder', s.week_folder, ...
        'mouse', s.mouse, 'channel', s.channel, 'week_index', s.week_index, ...
        'week_label', s.week_label, 'center', out.center, 'radius', out.radius, ...
        'drawn_on_current', ref_cur, 'drawn_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    if isempty(key_idx), rois(end+1) = rec; else, rois(key_idx) = rec; end %#ok<SAGROW>

    save(roi_file, 'rois');            % checkpoint after every session
    n_done = n_done + 1;
    fprintf('  saved: center (%.1f, %.1f), r = %.1f px\n', ...
        out.center(1), out.center(2), out.radius);
end

%% -------------------------
% SUMMARY + CSV
% -------------------------
fprintf('\n%d ROI(s) drawn this sitting, %d skipped, %d total on file.\n', ...
    n_done, n_skipped, numel(rois));

if ~isempty(rois)
    T = struct2table(rmfield(rois, 'center'));
    C = vertcat(rois.center);
    T.center_x = C(:,1);
    T.center_y = C(:,2);
    % The ROIs themselves are already safe in the .mat, checkpointed after
    % every session. This CSV is only a readable copy, so a lock on it
    % (open in Excel, typically) must not end the run with an error that
    % looks like the drawing session was lost.
    csv_file = fullfile(root_dir, 'rois_longitudinal.csv');
    try
        writetable(T, csv_file);
        fprintf('Wrote %s\n', csv_file);
    catch ME
        warning(['Could not write %s (%s).\n' ...
            'The ROIs are saved in rois_longitudinal.mat regardless — close the ' ...
            'file and re-run to refresh the CSV.'], csv_file, ME.message);
    end

    remaining = n_sess - numel(rois);
    if remaining > 0
        fprintf('%d session(s) still without an ROI -- re-run to continue.\n', remaining);
    else
        fprintf('Every indexed session has an ROI. Ready for extraction.\n');
    end
end

%% =========================
% LOCAL FUNCTIONS
%% =========================

function r = empty_roi_struct()
r = struct('chan_folder', {}, 'week_folder', {}, 'mouse', {}, 'channel', {}, ...
    'week_index', {}, 'week_label', {}, 'center', {}, 'radius', {}, ...
    'drawn_on_current', {}, 'drawn_on', {});
end

function idx = find_roi(rois, chan_folder, week_folder)
idx = [];
for i = 1:numel(rois)
    if strcmp(rois(i).chan_folder, chan_folder) && strcmp(rois(i).week_folder, week_folder)
        idx = i;
        return;
    end
end
end

function seed = last_roi_for_channel(rois, chan_folder, week_index)
% Most recent ROI of this channel from a strictly earlier week.
seed = [];
best = -inf;
for i = 1:numel(rois)
    if strcmp(rois(i).chan_folder, chan_folder) && rois(i).week_index < week_index ...
            && rois(i).week_index > best
        best = rois(i).week_index;
        seed = rois(i);
    end
end
end

function out = place_circle(movie, valid_mask, t_s, f0, seed, cmap, mask_color, circ_color, hdr)
% Slider viewer with a draggable circle pre-placed at the seed position.
[~, ~, T] = size(movie);
clim_range = data_clim(movie, valid_mask);
out = struct('action', 'skip', 'center', [NaN NaN], 'radius', NaN);

fig = figure('Color', 'w', 'Name', hdr, 'Position', [80 60 820 780], ...
    'CloseRequestFcn', @(~, ~) finish('quit'));
ax = axes(fig, 'Position', [0.08 0.14 0.80 0.78]);

img = image(ax, dff_frame_to_rgb(movie(:,:,f0), ~valid_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, valid_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
colormap(ax, cmap); clim(ax, clim_range); colorbar(ax);
th = title(ax, '', 'Interpreter', 'none');
show_frame(f0);

uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.12 0.075 0.72 0.03], 'Min', 1, 'Max', T, 'Value', f0, ...
    'SliderStep', [1/max(1,T-1), 5/max(1,T-1)], ...
    'Callback', @(src, ~) show_frame(get(src, 'Value')));

h = drawcircle(ax, 'Center', seed.center, 'Radius', seed.radius, ...
    'Color', circ_color, 'LineWidth', 1.6, 'FaceAlpha', 0.06);

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Accept', 'Units', 'normalized', ...
    'Position', [0.10 0.015 0.18 0.05], 'FontWeight', 'bold', ...
    'Callback', @(~, ~) finish('accept'));
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Redraw', 'Units', 'normalized', ...
    'Position', [0.31 0.015 0.18 0.05], 'Callback', @(~, ~) redraw());
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip', 'Units', 'normalized', ...
    'Position', [0.52 0.015 0.18 0.05], 'Callback', @(~, ~) finish('skip'));
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Quit & save', 'Units', 'normalized', ...
    'Position', [0.73 0.015 0.18 0.05], 'Callback', @(~, ~) finish('quit'));
set(fig, 'KeyPressFcn', @(~, e) keypress(e));

sgtitle(fig, 'Drag / resize the circle, then Accept', 'FontSize', 10);
uiwait(fig);

    function show_frame(k)
        k = max(1, min(T, round(k)));
        set(img, 'CData', dff_frame_to_rgb(movie(:,:,k), ~valid_mask, clim_range, cmap, mask_color));
        set(th, 'String', sprintf('t = %+.2f s', t_s(k)));
    end

    function redraw()
        if isvalid(h), delete(h); end
        h = drawcircle(ax, 'Color', circ_color, 'LineWidth', 1.6, 'FaceAlpha', 0.06);
    end

    function keypress(e)
        if any(strcmp(e.Key, {'return', 'space'})), finish('accept'); end
    end

    function finish(action)
        if strcmp(action, 'accept') && isvalid(h)
            out.center = h.Center;
            out.radius = h.Radius;
            out.action = 'accept';
        else
            out.action = action;
        end
        if isvalid(fig), delete(fig); end
    end
end

function cl = data_clim(M, mask)
% Same autoscale convention as steps 5_A/7_A/8.
T = size(M, 3);
v = M(repmat(logical(mask), [1 1 T]) & isfinite(M));
if isempty(v), cl = [-0.02 0.02]; return; end
lo = min(v); hi = max(v);
if ~(hi > lo), cl = [-0.02 0.02]; else, cl = [lo hi]; end
end

function rgb = dff_frame_to_rgb(frame, mask, clim_range, cmap, mask_color)
n = size(cmap, 1);
scaled = (frame - clim_range(1)) / (clim_range(2) - clim_range(1));
scaled(~isfinite(scaled)) = 0;
idx = uint8(min(max(round(scaled * (n - 1)), 0), n - 1));
rgb = ind2rgb(idx, cmap);
for c = 1:3
    chan = rgb(:, :, c);
    chan(mask) = mask_color(c);
    rgb(:, :, c) = chan;
end
end
