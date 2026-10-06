%% plot_circle_max_dff_vs_current.m
% Circle-of-interest dose-response curves, one per selected channel plus a
% cross-channel average.
%
% Same front end as step 8_B (pixel_temporal_comparison_8B.m): pick a
% step-5_A (or 5_B) output folder, pick one or more channels, and draw ONE
% circle of interest per channel on that channel's reference dF/F map.
%
% What differs is the plot itself. Step 8/8_B plots dF/F(t) — time on x.
% Here the curve is a dose-response instead:
%   x axis : stimulation current (0, 2, 4, ... uA — every current level
%            found for that channel, including 0 uA if present)
%   y axis : the MAXIMUM of the circle's mean dF/F(t) trace for that
%            current, taken over a user-set response window
%
% So each current contributes exactly one point: first the mean dF/F across
% all in-brain pixels inside the circle is computed at every frame (same
% math as step 8/8_B), then the peak of that trace within the response
% window is read off.
%
% Outputs (all figures are shown first; you are asked where to save only
% afterwards, and Cancel saves nothing):
%   - one two-panel figure per channel — reference map with the circle on
%     the left, that channel's dose-response curve on the right
%   - one combined figure — the dose-response averaged across all selected
%     channels on the left, and every channel's reference map with its
%     circle tiled as a small array on the right
%
% The reference map is taken from each channel's highest-current condition
% at a FIXED display time (ref_time_s below, default +0.5 s), not at its
% most-active frame, so every channel is shown at the same latency.
%
% Optional V1 boundary overlay from a step-6 day_setup.mat, same convention
% as steps 5_A/5_B/7_A/7_B/8.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
ref_time_s          = 0.5;                % reference map display time (s)
mask_color_outside  = [0.15 0.15 0.15];
v1_outline_color    = [0.10 0.85 0.30];
circle_color        = [1.00 0.00 1.00];   % magenta — absent from jet, so it
                                          % stays legible over red/orange
curve_color         = [0.12 0.47 0.71];
show_sem_errorbars  = true;               % SEM across channels on the average

%% -------------------------
% SELECT METHOD (5_A vs 5_B output)
% -------------------------
method_choice = questdlg('Which dF/F movies should this plot read?', ...
    'Select source', ...
    'Method 0 (step 5_A)', 'Method 1 (step 5_B)', 'Method 0 (step 5_A)');
if isempty(method_choice), error('Cancelled.'); end
is_m1 = strcmp(method_choice, 'Method 1 (step 5_B)');
if is_m1
    file_glob   = 'mean_dff_m1_ch*uA.mat';
    prompt_text = 'Select step-5_B output folder (contains method1/ch{N}_{I}uA/ subfolders)';
else
    file_glob   = 'mean_dff_ch*uA.mat';
    prompt_text = 'Select step-5_A output folder (contains ch{N}_{I}uA/ subfolders)';
end

%% -------------------------
% SELECT ROOT FOLDER + CHANNELS (multiple)
% -------------------------
root_dir = uigetdir(pwd, prompt_text);
if isequal(root_dir, 0), error('No folder selected.'); end

mat_files = dir(fullfile(root_dir, '**', file_glob));
assert(~isempty(mat_files), 'No %s files found under:\n  %s', file_glob, root_dir);

chs  = nan(numel(mat_files), 1);
curs = nan(numel(mat_files), 1);
for i = 1:numel(mat_files)
    tok = regexp(mat_files(i).name, 'ch(\d+)_([\d.]+)uA', 'tokens', 'once');
    if ~isempty(tok)
        chs(i)  = str2double(tok{1});
        curs(i) = str2double(tok{2});
    end
end
valid     = isfinite(chs) & isfinite(curs);
mat_files = mat_files(valid);
chs       = chs(valid);
curs      = curs(valid);

unique_chs = unique(chs);
ch_strs    = arrayfun(@(c) sprintf('Ch %d', c), unique_chs, 'UniformOutput', false);
[ch_sel, ok] = listdlg( ...
    'Name',          'Select channels', ...
    'PromptString',  'Select one or more channels (Ctrl+click) — one figure each, plus an average:', ...
    'ListString',    ch_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [220 260], ...
    'OKString',      'Select', ...
    'CancelString',  'Cancel');
if ~ok || isempty(ch_sel), error('No channel(s) selected.'); end
sel_channels = unique_chs(ch_sel);
n_ch = numel(sel_channels);
fprintf('Selected %d channel(s): %s\n', n_ch, mat2str(sel_channels'));

%% -------------------------
% SESSION LABELS — used verbatim in the figure titles
% -------------------------
lbl_ans = inputdlg( ...
    {'Subject / preparation label (e.g. LGN 24):', 'Session date as it should appear (e.g. 08142026):'}, ...
    'Figure labels', [1 60], {'LGN 24', ''});
if isempty(lbl_ans), error('Figure labels not specified. Cancelled.'); end
subject_label = strtrim(lbl_ans{1});
date_label    = strtrim(lbl_ans{2});
assert(~isempty(date_label), 'A session date label is required (it goes in every figure title).');
if isempty(subject_label), subject_label = 'subject'; end
fprintf('Labels: %s  |  %s\n', subject_label, date_label);

%% -------------------------
% RESPONSE WINDOW — the max is taken over this window
% -------------------------
win_ans = inputdlg( ...
    {'Response window start (s):', 'Response window end (s):'}, ...
    'Window for the dF/F maximum', [1 60], {'0', '1.0'});
if isempty(win_ans), error('Response window not specified. Cancelled.'); end
resp_win_s = [str2double(win_ans{1}) str2double(win_ans{2})];
assert(all(isfinite(resp_win_s)) && resp_win_s(2) > resp_win_s(1), ...
    'Response window start must be finite and less than its end.');
fprintf('Response window: %+.3f s to %+.3f s\n', resp_win_s(1), resp_win_s(2));

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY (step-6 day_setup)
% -------------------------
peek_idx = find(chs == sel_channels(1), 1, 'first');
S0 = load(fullfile(mat_files(peek_idx).folder, mat_files(peek_idx).name));
if isfield(S0, 'mean_dff_movie'), tmp = S0.mean_dff_movie;
else,                             tmp = S0.dff_movie; end
[H, W, ~] = size(tmp); clear tmp S0;

[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');
if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = load_v1_mask(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary loaded: %s\n', v1_fn); end
end

%% -------------------------
% PER-CHANNEL: LOAD, DRAW CIRCLE, MEASURE MAX dF/F PER CURRENT
% -------------------------
channel_data = struct('channel', {}, 'currents_uA', {}, 'max_dff', {}, 't_at_max', {}, ...
    'n_frames_in_win', {}, 'circle', {}, 'ref_img', {}, 'ref_mask', {}, 'ref_clim', {}, ...
    'ref_current', {}, 'ref_t', {}, 'ref_title', {}, 'n_roi_px', {}, 'source_files', {});
ref_cmap = jet(256);

for ci = 1:n_ch
    ch = sel_channels(ci);
    keep         = (chs == ch);
    ch_mat_files = mat_files(keep);
    ch_curs      = curs(keep);
    [ch_curs, sord] = sort(ch_curs);
    ch_mat_files    = ch_mat_files(sord);
    n_cur           = numel(ch_curs);
    fprintf('\nChannel %d: %d current level(s) found: %s uA\n', ch, n_cur, mat2str(ch_curs'));

    conditions = struct('current_uA', {}, 'movie', {}, 't_s', {}, 'always_nan_mask', {});
    for i = 1:n_cur
        mv_fpath = fullfile(ch_mat_files(i).folder, ch_mat_files(i).name);
        S = load(mv_fpath);
        if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
        elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
        else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', mv_fpath); end
        assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

        conditions(i).current_uA      = ch_curs(i);
        conditions(i).movie           = movie;
        conditions(i).t_s             = double(S.t_s(:)');
        conditions(i).always_nan_mask = all(isnan(movie), 3);
        fprintf('  Loaded %g uA: %s\n', ch_curs(i), ch_mat_files(i).name);
    end

    for i = 1:n_cur
        [Hi, Wi, ~] = size(conditions(i).movie);
        assert(Hi == H && Wi == W, ...
            'Frame size mismatch for Ch %d at %g uA (%dx%d vs %dx%d).', ...
            ch, conditions(i).current_uA, Hi, Wi, H, W);
    end
    % Each current keeps its own t_s: the peak is read per trace, so the
    % time axes only have to cover the response window, not match each other.

    % --- Reference map: highest current, shown at the FIXED time ref_time_s ---
    [~, ref_i] = max(ch_curs);
    ref_movie           = conditions(ref_i).movie;
    ref_t_vec           = conditions(ref_i).t_s;
    ref_always_nan_mask = conditions(ref_i).always_nan_mask;

    [dt_ref, ref_frame_idx] = min(abs(ref_t_vec - ref_time_s));
    if dt_ref > 1e-6
        fprintf('  Note: no frame exactly at t = %+.2f s; using nearest at t = %+.3f s.\n', ...
            ref_time_s, ref_t_vec(ref_frame_idx));
    end
    ref_img  = ref_movie(:,:,ref_frame_idx);
    clim_bg  = data_clim(ref_movie, ~ref_always_nan_mask);

    ref_title = sprintf('Reference map  |  Ch %d  |  %g uA  |  t = %+.2f s', ...
        ch, ch_curs(ref_i), ref_t_vec(ref_frame_idx));
    fprintf('  Reference map: Ch %d | %g uA | t = %+.2f s\n', ...
        ch, ch_curs(ref_i), ref_t_vec(ref_frame_idx));

    % --- Draw the circle of interest for this channel ---
    circle = pick_single_circle_on_reference(ref_img, ref_always_nan_mask, ref_t_vec, ref_frame_idx, ...
        clim_bg, ref_cmap, mask_color_outside, V1_mask, v1_outline_color, circle_color, ...
        sprintf('Ch %d  |  reference: %g uA', ch, ch_curs(ref_i)), ref_movie);
    if isempty(circle)
        fprintf('  No circle drawn for Ch %d — channel excluded from all outputs.\n', ch);
        continue;
    end

    roi_mask = circle.mask;
    n_roi_px = sum(roi_mask(:) & ~ref_always_nan_mask(:));
    if n_roi_px == 0
        warning('  Ch %d: circle contains no in-brain pixels — channel excluded.', ch);
        continue;
    end

    % --- One point per current: max of the circle's mean dF/F(t) ---
    max_dff         = nan(n_cur, 1);
    t_at_max        = nan(n_cur, 1);
    n_frames_in_win = zeros(n_cur, 1);

    fprintf('  Current (uA)   max mean dF/F   at t (s)   frames in window\n');
    for i = 1:n_cur
        trace = roi_mean_trace(conditions(i).movie, roi_mask);
        t_i   = conditions(i).t_s;

        in_win = t_i >= resp_win_s(1) & t_i <= resp_win_s(2);
        n_frames_in_win(i) = nnz(in_win);
        if ~any(in_win)
            warning('    %g uA: no frame inside the response window — point left blank.', ...
                conditions(i).current_uA);
            continue;
        end

        win_trace = trace(:);
        win_trace(~in_win(:)) = NaN;
        [mx, mi] = max(win_trace, [], 'omitnan');
        if isempty(mx) || ~isfinite(mx)
            warning('    %g uA: no finite dF/F inside the response window — point left blank.', ...
                conditions(i).current_uA);
            continue;
        end
        max_dff(i)  = mx;
        t_at_max(i) = t_i(mi);
        fprintf('    %8g     %+12.5f   %+8.3f   %6d\n', ...
            conditions(i).current_uA, max_dff(i), t_at_max(i), n_frames_in_win(i));
    end

    if ~any(isfinite(max_dff))
        warning('  Ch %d: no current produced a finite maximum — channel excluded.', ch);
        continue;
    end

    channel_data(end+1) = struct( ...
        'channel',         ch, ...
        'currents_uA',     ch_curs(:), ...
        'max_dff',         max_dff, ...
        't_at_max',        t_at_max, ...
        'n_frames_in_win', n_frames_in_win, ...
        'circle',          circle, ...
        'ref_img',         ref_img, ...
        'ref_mask',        ref_always_nan_mask, ...
        'ref_clim',        clim_bg, ...
        'ref_current',     ch_curs(ref_i), ...
        'ref_t',           ref_t_vec(ref_frame_idx), ...
        'ref_title',       ref_title, ...
        'n_roi_px',        n_roi_px, ...
        'source_files',    {fullfile({ch_mat_files.folder}', {ch_mat_files.name}')}); %#ok<AGROW>

    % Free this channel's movies before loading the next one
    clear conditions;
end

n_used = numel(channel_data);
assert(n_used > 0, 'No channel produced a usable circle of interest — nothing to plot.');
if n_used < n_ch
    fprintf('\n%d of %d selected channel(s) contributed a curve.\n', n_used, n_ch);
end

%% -------------------------
% PER-CHANNEL FIGURES
% -------------------------
method_tag = '';
if is_m1, method_tag = ' (Method 1)'; end

figs      = gobjects(n_used, 1);
fig_names = cell(n_used, 1);

for k = 1:n_used
    cd_k = channel_data(k);
    cx = cd_k.circle.center(1); cy = cd_k.circle.center(2); cr = cd_k.circle.radius;

    fig = figure('Color', 'w', 'Position', [60 80 1220 480], ...
        'Name', sprintf('max dF/F | Ch %d | %s', cd_k.channel, date_label));

    % --- Left: reference map with the circle of interest outlined ---
    ax1 = subplot(1, 2, 1);
    image(ax1, dff_frame_to_rgb(cd_k.ref_img, cd_k.ref_mask, cd_k.ref_clim, ref_cmap, mask_color_outside));
    axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
    visboundaries(ax1, ~cd_k.ref_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
    if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
        visboundaries(ax1, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
    end
    colormap(ax1, ref_cmap); clim(ax1, cd_k.ref_clim);
    cb = colorbar(ax1); cb.Label.String = '\DeltaF/F';
    viscircles(ax1, [cx cy], cr, 'Color', circle_color, 'LineWidth', 1.6);
    title(ax1, cd_k.ref_title, 'Interpreter', 'none', 'FontSize', 10);

    % --- Right: max dF/F inside the circle vs stimulation current ---
    ax2 = subplot(1, 2, 2);
    hold(ax2, 'on');
    ok_pt = isfinite(cd_k.max_dff);
    plot(ax2, cd_k.currents_uA(ok_pt), cd_k.max_dff(ok_pt), '-', ...
        'Color', curve_color, 'LineWidth', 1.8);
    plot(ax2, cd_k.currents_uA(ok_pt), cd_k.max_dff(ok_pt), 'o', ...
        'MarkerSize', 7, 'MarkerFaceColor', curve_color, 'MarkerEdgeColor', 'w', 'LineWidth', 1.0);
    yline(ax2, 0, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
    apply_current_axis(ax2, cd_k.currents_uA);
    xlabel(ax2, 'Stimulation current (\muA)');
    ylabel(ax2, 'Max mean \DeltaF/F in circle of interest');
    title(ax2, sprintf('max dF/F  |  Ch %d  |  %s', cd_k.channel, date_label), ...
        'Interpreter', 'none');
    grid(ax2, 'on'); box(ax2, 'on');

    drawnow;
    figs(k)      = fig;
    fig_names{k} = sprintf('max_dff_vs_current_%s_ch%d_circle_x%.0f_y%.0f_r%.0f', ...
        sanitize(date_label), cd_k.channel, cx, cy, cr);
end

%% -------------------------
% CROSS-CHANNEL AVERAGE + REFERENCE-MAP ARRAY
% -------------------------
all_currents = unique(vertcat(channel_data.currents_uA));
n_all_cur    = numel(all_currents);
avg_max_dff  = nan(n_all_cur, 1);
sem_max_dff  = zeros(n_all_cur, 1);
n_ch_per_cur = zeros(n_all_cur, 1);

fprintf('\nCross-channel average (%d channel(s)):\n', n_used);
fprintf('  Current (uA)   mean max dF/F   SEM        n channels\n');
for i = 1:n_all_cur
    vals = nan(n_used, 1);
    for k = 1:n_used
        idx = find(channel_data(k).currents_uA == all_currents(i), 1);
        if isempty(idx), continue; end
        vals(k) = channel_data(k).max_dff(idx);
    end
    vals = vals(isfinite(vals));
    n_ch_per_cur(i) = numel(vals);
    if isempty(vals), continue; end
    avg_max_dff(i) = mean(vals);
    if numel(vals) > 1
        sem_max_dff(i) = std(vals) / sqrt(numel(vals));
    end
    fprintf('  %8g     %+12.5f   %9.5f  %6d\n', ...
        all_currents(i), avg_max_dff(i), sem_max_dff(i), n_ch_per_cur(i));
end

fig_avg = figure('Color', 'w', 'Position', [80 60 1320 560], ...
    'Name', sprintf('averaged max dF/F for %s | %s', subject_label, date_label));
tl = tiledlayout(fig_avg, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- Left: averaged dose-response curve ---
ax_avg = nexttile(tl, 1);
hold(ax_avg, 'on');
ok_pt = isfinite(avg_max_dff);
if show_sem_errorbars && any(n_ch_per_cur(ok_pt) > 1)
    errorbar(ax_avg, all_currents(ok_pt), avg_max_dff(ok_pt), sem_max_dff(ok_pt), ...
        '-o', 'Color', curve_color, 'LineWidth', 1.8, 'MarkerSize', 7, ...
        'MarkerFaceColor', curve_color, 'MarkerEdgeColor', 'w', 'CapSize', 6);
else
    plot(ax_avg, all_currents(ok_pt), avg_max_dff(ok_pt), '-o', ...
        'Color', curve_color, 'LineWidth', 1.8, 'MarkerSize', 7, ...
        'MarkerFaceColor', curve_color, 'MarkerEdgeColor', 'w');
end
yline(ax_avg, 0, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');
apply_current_axis(ax_avg, all_currents);
xlabel(ax_avg, 'Stimulation current (\muA)');
ylabel(ax_avg, 'Max mean \DeltaF/F in circle of interest');
title(ax_avg, sprintf('averaged max dF/F for %s  |  %s', subject_label, date_label), ...
    'Interpreter', 'none');
grid(ax_avg, 'on'); box(ax_avg, 'on');

% --- Right: every channel's reference map + circle, as a small array ---
n_map_cols = ceil(sqrt(n_used));
n_map_rows = ceil(n_used / n_map_cols);
tl_maps = tiledlayout(tl, n_map_rows, n_map_cols, 'TileSpacing', 'tight', 'Padding', 'tight');
tl_maps.Layout.Tile = 2;

for k = 1:n_used
    cd_k = channel_data(k);
    ax_m = nexttile(tl_maps);
    image(ax_m, dff_frame_to_rgb(cd_k.ref_img, cd_k.ref_mask, cd_k.ref_clim, ref_cmap, mask_color_outside));
    axis(ax_m, 'image'); axis(ax_m, 'off'); set(ax_m, 'YDir', 'normal'); hold(ax_m, 'on');
    visboundaries(ax_m, ~cd_k.ref_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5);
    if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
        visboundaries(ax_m, V1_mask, 'Color', v1_outline_color, 'LineWidth', 0.6);
    end
    viscircles(ax_m, cd_k.circle.center, cd_k.circle.radius, ...
        'Color', circle_color, 'LineWidth', 1.2);
    title(ax_m, sprintf('Ch %d  |  %g uA', cd_k.channel, cd_k.ref_current), ...
        'Interpreter', 'none', 'FontSize', 9);
end
title(tl_maps, sprintf('Reference maps at t = %+.2f s (each auto-scaled)', ref_time_s), ...
    'FontSize', 9);

drawnow;

%% -------------------------
% OUTPUT — asked for only after every figure is on screen
% -------------------------
save_choice = questdlg(sprintf('Save these %d figure(s)?', n_used + 1), 'Save output', ...
    'Save', 'Do not save', 'Save');
if ~strcmp(save_choice, 'Save')
    fprintf('\nNot saved. Figures left open.\n');
    return;
end

save_dir = uigetdir(root_dir, 'Select output folder for the figures (Cancel = do not save)');
if isequal(save_dir, 0)
    fprintf('\nNo output folder selected — not saved. Figures left open.\n');
    return;
end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

method_fname_tag = '';
if is_m1, method_fname_tag = '_m1'; end
win_tag = sprintf('win%+.2fs_to%+.2fs', resp_win_s(1), resp_win_s(2));
win_tag = strrep(strrep(win_tag, '+', 'p'), '.', 'p');

fprintf('\n');
for k = 1:n_used
    fname = sprintf('%s%s_%s.png', fig_names{k}, method_fname_tag, win_tag);
    exportgraphics(figs(k), fullfile(save_dir, fname), 'Resolution', 150);
    fprintf('Saved figure: %s\n', fname);
end

ch_tag = strjoin(string([channel_data.channel]), '-');
avg_base = sprintf('max_dff_vs_current_avg_%s_%s_ch%s%s_%s', ...
    sanitize(subject_label), sanitize(date_label), ch_tag, method_fname_tag, win_tag);
exportgraphics(fig_avg, fullfile(save_dir, [avg_base '.png']), 'Resolution', 150);
fprintf('Saved figure: %s\n', [avg_base '.png']);

% --- Data behind every figure ---
channels_used   = [channel_data.channel];
per_channel     = rmfield(channel_data, {'ref_img', 'ref_mask'});   % keep the .mat small
currents_uA     = all_currents;
save(fullfile(save_dir, [avg_base '.mat']), ...
    'channels_used', 'per_channel', 'currents_uA', 'avg_max_dff', 'sem_max_dff', ...
    'n_ch_per_cur', 'resp_win_s', 'ref_time_s', 'subject_label', 'date_label', 'is_m1');
fprintf('Saved data:   %s\n', [avg_base '.mat']);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function s = sanitize(str)
% Filename-safe version of a free-text label ('LGN 24' -> 'LGN_24').
s = regexprep(char(str), '[^A-Za-z0-9]+', '_');
s = regexprep(s, '^_+|_+$', '');
if isempty(s), s = 'x'; end
end

function apply_current_axis(ax, currents)
% Ticks on the actual current levels, with a little padding either side, so
% non-uniform sets (0, 2, 4, 5, 6, 7 uA) still space correctly.
c = unique(currents(:));
xticks(ax, c');
if numel(c) > 1
    pad = 0.06 * (max(c) - min(c));
    if pad > 0, xlim(ax, [min(c) - pad, max(c) + pad]); end
end
end

function V1_mask = load_v1_mask(fpath, expected_size)
% Pull a full-frame V1 mask out of a step-6 day_setup.mat. Kept local so
% this script runs from the "plotting code" folder without needing the
% pipeline folder on the MATLAB path (same field search as get_v1_boundary).
V1_mask = [];
S = load(fpath);
cand = [];
if isfield(S, 'day_setup'),                              cand = dig_v1(S.day_setup); end
if isempty(cand) && isfield(S, 'reference_mask_and_retino_alignment')
    cand = dig_v1(S.reference_mask_and_retino_alignment);
end
if isempty(cand),                                        cand = dig_v1(S); end
if isempty(cand)
    warning('No V1 mask field found in:\n  %s', fpath);
    return;
end
V1_mask = logical(cand);
if ~isequal(size(V1_mask), expected_size(:)')
    warning('V1 mask size (%dx%d) does not match the movie (%dx%d) — overlay skipped.', ...
        size(V1_mask,1), size(V1_mask,2), expected_size(1), expected_size(2));
    V1_mask = [];
    return;
end
if ~any(V1_mask(:))
    warning('Loaded V1 mask is empty — overlay skipped.');
    V1_mask = [];
end
end

function m = dig_v1(s)
m = [];
if ~isstruct(s), return; end
if isfield(s, 'retino_align') && isstruct(s.retino_align) && isfield(s.retino_align, 'V1_mask_stim')
    m = s.retino_align.V1_mask_stim; return;
end
if isfield(s, 'V1_mask_stim'), m = s.V1_mask_stim; return; end
if isfield(s, 'V1_mask'),      m = s.V1_mask;      return; end
end

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie. Same convention as steps 5_A/5_B/7_A/7_B/8.
if nargin >= 2 && ~isempty(mask)
    T = size(M, 3);
    v = M(repmat(logical(mask), [1 1 T]) & isfinite(M));
else
    v = M(isfinite(M));
end
if isempty(v)
    cl = [-0.02 0.02];
    return;
end
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

function trace = roi_mean_trace(movie, roi_mask)
% Mean dF/F within roi_mask at every frame, ignoring NaN (out-of-brain)
% pixels. NaN if the ROI contains no finite in-mask pixels for that frame.
% Same math as step 8/8_B.
[H, W, T] = size(movie);
flat  = reshape(movie, H * W, T);
sel   = flat(roi_mask(:), :);
trace = mean(sel, 1, 'omitnan')';
end

function set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, k)
[~, ~, T] = size(movie);
k = max(1, min(T, round(k)));
set(img, 'CData', dff_frame_to_rgb(movie(:,:,k), always_nan_mask, clim_range, cmap, mask_color));
set(th, 'String', sprintf('%s | t = %+.2f s', title_str, t_s(k)));
end

function circle = pick_single_circle_on_reference(ref_img, always_nan_mask, t_s, ref_idx, ...
    clim_range, cmap, mask_color, V1_mask, v1_color, circle_color, title_str, movie)
% Time-slider viewer over the reference dF/F movie, opened at the reference
% frame. Draws ONE circular ROI (with a redraw option). Same interaction as
% step 8_B.
%   - Drag out a circle, then double-click / Enter to confirm it.
%   - Accept it, redraw, or cancel this channel.
% Returns a struct with .center [x y], .radius, .mask (H x W logical), or []
% if cancelled / the figure was closed.
[H, W, T] = size(movie);

fig = figure('Color', 'w', 'Name', ['Draw circle of interest — ' title_str], ...
    'Position', [80 80 780 700]);
ax = axes(fig, 'Position', [0.10 0.12 0.78 0.80]);

img = image(ax, dff_frame_to_rgb(ref_img, always_nan_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
visboundaries(ax, ~always_nan_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.8);
if ~isempty(V1_mask) && isequal(size(V1_mask), [H W])
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end
colormap(ax, cmap); clim(ax, clim_range); colorbar(ax);
th = title(ax, '', 'Interpreter', 'none');
set_ref_frame(img, th, movie, always_nan_mask, t_s, clim_range, cmap, mask_color, title_str, ref_idx);

uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.12 0.03 0.72 0.035], ...
    'Min', 1, 'Max', T, 'Value', ref_idx, ...
    'SliderStep', [1 / (T - 1), 5 / (T - 1)], ...
    'Callback', @(src, ~) set_ref_frame(img, th, movie, always_nan_mask, t_s, ...
        clim_range, cmap, mask_color, title_str, get(src, 'Value')));

sgtitle(fig, 'Drag out the circle of interest, then double-click / Enter to confirm.');

[xx, yy] = meshgrid(1:W, 1:H);
circle = [];

while isvalid(fig)
    h_circ = drawcircle(ax, 'Color', circle_color, 'LineWidth', 1.6, 'FaceAlpha', 0.08);
    wait(h_circ);
    if ~isvalid(h_circ)
        break;   % figure closed while drawing
    end

    c = h_circ.Center;
    r = h_circ.Radius;
    m = ((xx - c(1)).^2 + (yy - c(2)).^2) <= r^2;
    n_px = sum(m(:) & ~always_nan_mask(:));
    fprintf('  Circle: center (%.1f, %.1f), radius %.1f px, %d in-mask pixel(s)\n', c(1), c(2), r, n_px);

    if ~isvalid(fig), break; end
    choice = questdlg('Accept this circle of interest?', 'Circle of interest', ...
        'Accept', 'Redraw', 'Cancel channel', 'Accept');
    if strcmp(choice, 'Accept')
        circle = struct('center', c, 'radius', r, 'mask', m);
        break;
    elseif isempty(choice) || strcmp(choice, 'Cancel channel')
        delete(h_circ);
        circle = [];
        break;
    else   % 'Redraw'
        delete(h_circ);
    end
end

if isvalid(fig), close(fig); end
end
