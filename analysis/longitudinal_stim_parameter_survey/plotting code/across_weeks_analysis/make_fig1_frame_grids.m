%% make_fig1_frame_grids.m
% FIGURE 1 — one frame grid per effective channel, rows = weeks.
%
% For every channel in the longitudinal tree, renders a single figure whose
% ROWS are the recording weeks (pre W4 -> post W4 by default) and whose
% COLUMNS are time points after stimulation onset, all at ONE current
% (7 uA by default).
%
% The point of the figure is to compare weeks, so every row is drawn on the
% SAME color scale — computed once per channel across all of its weeks.
% Auto-scaling each week separately would paint a dead week as brightly as
% a live one and destroy the comparison, so that is deliberately not the
% default (set clim_mode below to change it).
%
% Columns are sampled at the SAME requested times in every row, picking each
% week's nearest frame, so a column means the same latency in every row even
% if the weekly time bases differ slightly.
%
% Note the high-current session (post W5 / W6) never tested 7 uA, so it is
% absent from this figure by construction — it appears in figures 4/5/6.
%
% Reads:  the longitudinal_data tree, via wf_scan_longitudinal.m
% Writes: <root>/figure1_frame_grids/fig1_frame_grid_<MOUSE>_ch<N>_<I>uA.png
%         <root>/figure1_frame_grids/fig1_frame_grid_index.csv  (clim used, etc.)
%
% The PNGs are then assembled into a deck by build_fig1_pptx.py.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
target_current_uA  = 7;          % the one current shown in this figure
week_index_range   = [-1 4];     % pre W4 (-1) through post W4 (+4)

% How the (always week-shared) color scale is chosen:
%   'channel'      min/max over the whole movie of every week — pipeline
%                  convention, but one hot pixel anywhere in the recording
%                  sets the top of the scale and dims the real response
%   'channel_pct'  percentiles of the DISPLAYED frames only, so the range is
%                  spent on what the figure actually shows; the brightest
%                  fraction saturates
%   'global'       the fixed range below, identical for every channel, which
%                  is the only mode that makes channels comparable to each
%                  other as well as across weeks
clim_mode          = 'channel_pct';
clim_percentiles   = [0.5 99.9];     % used only when clim_mode is 'channel_pct'
global_clim        = [-0.02 0.06];   % used only when clim_mode is 'global'

out_subfolder      = 'figure1_frame_grids';   % created under the tree root

font_size_tile_title = 11;   % per-column "t = ..." label (top row only)
font_size_row_label  = 12;   % per-row week label
font_size_main_title = 16;
font_size_colorbar   = 11;

tile_px            = 150;    % on-screen size of one frame, drives figure size
mask_color_outside = [0.15 0.15 0.15];
export_resolution  = 150;

%% -------------------------
% SCAN THE TREE
% -------------------------
root_dir = uigetdir('C:\Projects\LGN\weekly update\plots for presentation', ...
    'Select the longitudinal_data folder');
if isequal(root_dir, 0), error('No folder selected.'); end

S = wf_scan_longitudinal(root_dir);

% Keep only sessions that have the target current and sit in the week range
keep = false(size(S));
for i = 1:numel(S)
    keep(i) = any(abs(S(i).currents - target_current_uA) < 1e-9) ...
        && S(i).week_index >= week_index_range(1) ...
        && S(i).week_index <= week_index_range(2);
end
S = S(keep);
assert(~isempty(S), 'No session has %g uA inside weeks [%+d %+d].', ...
    target_current_uA, week_index_range(1), week_index_range(2));

chan_folders = unique(string({S.chan_folder}), 'stable');
fprintf('Figure 1: %g uA, weeks %+d..%+d -> %d session(s) across %d channel(s).\n', ...
    target_current_uA, week_index_range(1), week_index_range(2), ...
    numel(S), numel(chan_folders));

%% -------------------------
% TIME WINDOW + FRAME SPACING (asked once, applied to every channel)
% -------------------------
win_ans = inputdlg( ...
    {'Frame-grid start time (s):', 'Frame-grid end time (s):', 'Frame spacing (s):'}, ...
    'Figure 1 display window', [1 60], {'-0.1', '1.1', '0.1'});
if isempty(win_ans), error('Display window not specified. Cancelled.'); end
display_tmin   = str2double(win_ans{1});
display_tmax   = str2double(win_ans{2});
display_step_s = str2double(win_ans{3});
assert(isfinite(display_tmin) && isfinite(display_tmax) && display_tmin < display_tmax, ...
    'Start time must be less than end time.');
assert(isfinite(display_step_s) && display_step_s > 0, 'Frame spacing must be positive.');

target_times = display_tmin : display_step_s : display_tmax;
n_cols_frames = numel(target_times);
fprintf('Columns: %d time point(s) from %+.2f to %+.2f s\n', ...
    n_cols_frames, target_times(1), target_times(end));

%% -------------------------
% OUTPUT FOLDER
% -------------------------
out_dir = fullfile(root_dir, out_subfolder);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

cmap = jet(256);
idx_rows = table();

%% -------------------------
% ONE FIGURE PER CHANNEL
% -------------------------
for ci = 1:numel(chan_folders)
    cf  = chan_folders(ci);
    sel = S(strcmp({S.chan_folder}, cf));
    [~, ord] = sort([sel.week_index]);
    sel = sel(ord);
    n_weeks = numel(sel);

    mouse = sel(1).mouse;
    ch    = sel(1).channel;
    fprintf('\n[%d/%d] %s ch%d — %d week(s): %s\n', ci, numel(chan_folders), ...
        mouse, ch, n_weeks, strjoin({sel.week_label}, ', '));

    % --- Load this channel's movie for every week ---
    movies = cell(n_weeks, 1);
    masks  = cell(n_weeks, 1);
    tvecs  = cell(n_weeks, 1);
    for wi = 1:n_weeks
        fi_cur = find(abs(sel(wi).currents - target_current_uA) < 1e-9, 1);
        M = load(sel(wi).files{fi_cur});
        if isfield(M, 'mean_dff_movie'), mv = M.mean_dff_movie;
        elseif isfield(M, 'dff_movie'),  mv = M.dff_movie;
        else, error('No dF/F movie in:\n  %s', sel(wi).files{fi_cur}); end
        movies{wi} = mv;
        tvecs{wi}  = double(M.t_s(:)');
        if isfield(M, 'final_mask'), masks{wi} = logical(M.final_mask);
        else,                        masks{wi} = ~all(isnan(mv), 3); end
    end

    % --- Frame index per (week, requested time) ---
    % Same requested times in every row, each week contributing its nearest
    % frame, so a column means one latency across all rows.
    frame_idx = zeros(n_weeks, n_cols_frames);
    for wi = 1:n_weeks
        for tj = 1:n_cols_frames
            [~, frame_idx(wi, tj)] = min(abs(tvecs{wi} - target_times(tj)));
        end
    end

    % --- One color scale for the whole channel ---
    switch lower(clim_mode)
        case 'global'
            clim_used = global_clim;
        case 'channel_pct'
            clim_used = shared_clim(movies, masks, frame_idx, clim_percentiles);
        otherwise
            clim_used = shared_clim(movies, masks, [], []);
    end
    fprintf('  color scale (%s): [%.4f %.4f]\n', clim_mode, clim_used(1), clim_used(2));

    % --- Render: rows = weeks, columns = time (plus a label column) ---
    fig = figure('Color', 'w', 'Visible', 'off', ...
        'Name', sprintf('fig1 %s ch%d', mouse, ch), ...
        'Position', [40 40 tile_px*(n_cols_frames+1) + 160, tile_px*n_weeks + 150]);
    tl = tiledlayout(fig, n_weeks, n_cols_frames + 1, ...
        'TileSpacing', 'tight', 'Padding', 'compact');

    last_ax = [];
    for wi = 1:n_weeks
        % Label tile at the start of the row
        ax_lbl = nexttile(tl);
        axis(ax_lbl, 'off');
        text(ax_lbl, 0.95, 0.5, sel(wi).week_label, ...
            'Units', 'normalized', 'FontSize', font_size_row_label, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'middle', 'Interpreter', 'none');

        for tj = 1:n_cols_frames
            ax = nexttile(tl);
            imagesc(ax, movies{wi}(:,:,frame_idx(wi, tj)));
            axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal');
            colormap(ax, cmap);
            clim(ax, clim_used);
            hold(ax, 'on');
            visboundaries(ax, masks{wi}, 'Color', [0.45 0.45 0.45], 'LineWidth', 0.5);
            if wi == 1
                title(ax, sprintf('%+.2f s', target_times(tj)), ...
                    'FontSize', font_size_tile_title, 'FontWeight', 'normal');
            end
            last_ax = ax;
        end
    end

    if ~isempty(last_ax)
        cb = colorbar(last_ax);
        cb.Layout.Tile = 'east';               % one shared colorbar
        cb.FontSize = font_size_colorbar;
        cb.Label.String = '\DeltaF/F';
    end

    % Two-line title via cell array: tiledlayout subtitles are not available
    % in every release, a multi-line title is.
    title(tl, { sprintf('%s  ch%d  |  %g \\muA  |  %s to %s', ...
                    mouse, ch, target_current_uA, sel(1).week_label, sel(end).week_label), ...
                sprintf('same color scale for every week: %.3f to %.3f \\DeltaF/F', ...
                    clim_used(1), clim_used(2)) }, ...
        'FontSize', font_size_main_title, 'FontWeight', 'bold');

    png_name = sprintf('fig1_frame_grid_%s_ch%d_%guA.png', mouse, ch, target_current_uA);
    exportgraphics(fig, fullfile(out_dir, png_name), 'Resolution', export_resolution);
    close(fig);
    fprintf('  saved: %s\n', png_name);

    idx_rows = [idx_rows; table(string(mouse), ch, target_current_uA, n_weeks, ...
        string(strjoin({sel.week_label}, '|')), clim_used(1), clim_used(2), string(png_name), ...
        'VariableNames', {'mouse', 'channel', 'current_uA', 'n_weeks', ...
        'weeks', 'clim_lo', 'clim_hi', 'png'})]; %#ok<AGROW>
end

%% -------------------------
% INDEX
% -------------------------
idx_file = fullfile(out_dir, 'fig1_frame_grid_index.csv');
writetable(idx_rows, idx_file);
fprintf('\nDone. %d figure(s) in:\n  %s\nIndex: %s\n', ...
    height(idx_rows), out_dir, idx_file);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function cl = shared_clim(movies, masks, frame_idx, pcts)
% Color limits spanning EVERY week of one channel, so rows are comparable.
% Same in-mask / finite convention as steps 5_A/7_A/8.
%
% frame_idx empty -> whole movie, min/max ('channel' mode)
% frame_idx given -> only the displayed frames, trimmed at the percentiles
%                    in pcts ('channel_pct' mode)
vals = [];
lo = inf; hi = -inf;

for i = 1:numel(movies)
    M = movies{i};
    msk = logical(masks{i});
    if isempty(frame_idx)
        T = size(M, 3);
        v = M(repmat(msk, [1 1 T]) & isfinite(M));
        if isempty(v), continue; end
        lo = min(lo, min(v));
        hi = max(hi, max(v));
    else
        sub = M(:, :, frame_idx(i, :));
        n3  = size(sub, 3);
        v = sub(repmat(msk, [1 1 n3]) & isfinite(sub));
        vals = [vals; v]; %#ok<AGROW>
    end
end

if ~isempty(frame_idx)
    if isempty(vals), cl = [-0.02 0.02]; return; end
    lo = local_pct(vals, pcts(1));
    hi = local_pct(vals, pcts(2));
end

if ~isfinite(lo) || ~isfinite(hi) || ~(hi > lo)
    cl = [-0.02 0.02];
else
    cl = [lo hi];
end
end

function p = local_pct(v, q)
% Nearest-rank percentile. Implemented here rather than with prctile so the
% script does not require the Statistics Toolbox; huge vectors are
% subsampled first, which does not move a display percentile measurably.
v = v(isfinite(v));
if isempty(v), p = NaN; return; end
max_n = 2e6;
if numel(v) > max_n
    v = v(round(linspace(1, numel(v), max_n)));
end
v = sort(v);
idx = min(numel(v), max(1, round(q / 100 * numel(v))));
p = v(idx);
end
