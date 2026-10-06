  %% plot_dff_frame_grid_custom.m
% Plotting-only tool for step-5_A mean dF/F output files.
%
% Lets the user pick a step-5_A output FOLDER, then pick one or more
% channel/current combinations (mean_dff_ch{N}_{I}uA.mat files) found
% under it. For all selected combinations (sharing one time window / frame
% spacing / row count), it:
%   1. Re-sets the frame-grid time window and frame spacing (e.g. only
%      -0.1 s to 1.1 s), independent of whatever step 5_A originally used.
%   2. Chooses the number of rows for the output frame-grid figure(s) — the
%      number of columns is derived to fit all selected frames.
%   3. Chooses the dF/F color scale: either autoscaled per combination (the
%      pipeline default, min/max of in-mask finite values) or one fixed
%      [min max] range applied to every selected combination, so figures can
%      be compared side by side.
%   4. Optionally overlays the visual-area boundaries (V1 + all higher
%      areas: LM, AL, PM, ...) from a step-6 day_setup.mat on every frame.
%   5. Renders the frame-grid figure with larger fonts than the pipeline
%      default and exports it as a PNG, saved directly into that
%      combination's own step-5_A subfolder (next to its source .mat file).
%      The filename records the display time window (e.g. "-0.20s_to_1.20s")
%      and the color scale used.
%
% No thresholding, masking, or video export — this script only re-plots
% existing step-5_A mean dF/F movies with different display settings.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS — font sizes (larger than the pipeline default)
% -------------------------
font_size_tile_title = 14;   % per-frame "t = ..." label (pipeline default: 8)
font_size_main_title = 18;   % figure super-title (pipeline default: 11)
font_size_colorbar   = 13;   % colorbar tick labels

% Visual-area overlay appearance (only used if the overlay is enabled below).
% Kept deliberately thin and semi-transparent so the boundaries read as a
% reference grid without hiding the dF/F underneath. Raise the *_alpha
% values toward 1 for more prominent lines.
region_bound_color     = [0.85 0.45 0.05];   % all higher visual areas (muted orange)
region_bound_alpha     = 0.40;               % 0 = invisible, 1 = opaque
region_bound_dilate_px = 0;                  % 0 keeps step 6's crisp 1-px lines
v1_color               = [0.90 0.75 0.10];   % V1 outline (muted yellow)
v1_line_width          = 0.75;
v1_alpha               = 0.55;

%% -------------------------
% SELECT STEP-5_A OUTPUT FOLDER + CHANNEL/CURRENT COMBINATION(S)
% -------------------------
root_dir = uigetdir(pwd, 'Select step-5_A output folder (contains ch{N}_{I}uA/ subfolders)');
if isequal(root_dir, 0), error('No folder selected.'); end

mat_files = dir(fullfile(root_dir, '**', 'mean_dff_ch*uA.mat'));
assert(~isempty(mat_files), 'No mean_dff_ch*.mat files found under:\n  %s', root_dir);

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
[~, sord] = sortrows([chs curs]);
mat_files = mat_files(sord);
chs       = chs(sord);
curs      = curs(sord);

combo_strs = arrayfun(@(i) sprintf('Ch %d  |  %g uA', chs(i), curs(i)), ...
    (1:numel(mat_files))', 'UniformOutput', false);
[sel_idx, ok] = listdlg( ...
    'Name',          'Select channel(s) & current(s)', ...
    'PromptString',  'Select one or more channel/current combinations (Ctrl+click for multiple):', ...
    'ListString',    combo_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [300 400], ...
    'OKString',      'Select', ...
    'CancelString',  'Cancel');
if ~ok || isempty(sel_idx), error('No combination(s) selected.'); end

mat_files = mat_files(sel_idx);
chs       = chs(sel_idx);
curs      = curs(sel_idx);
n_sel     = numel(mat_files);
fprintf('Selected %d combination(s):\n', n_sel);
for i = 1:n_sel, fprintf('  Ch %d  |  %g uA\n', chs(i), curs(i)); end

%% -------------------------
% TIME WINDOW + FRAME SPACING (interactive, shared across all selected combinations)
% -------------------------
win_ans = inputdlg( ...
    {'Frame-grid start time (s):', 'Frame-grid end time (s):', 'Frame spacing (s):'}, ...
    'Frame-grid display window', [1 60], {'-0.1', '1.1', '0.1'});
if isempty(win_ans), error('Display window not specified. Cancelled.'); end
display_tmin   = str2double(win_ans{1});
display_tmax   = str2double(win_ans{2});
display_step_s = str2double(win_ans{3});
assert(isfinite(display_tmin) && isfinite(display_tmax) && display_tmin < display_tmax, ...
    'display_tmin must be less than display_tmax.');
assert(isfinite(display_step_s) && display_step_s > 0, 'Frame spacing must be a positive number.');

%% -------------------------
% NUMBER OF ROWS (interactive, shared across all selected combinations)
% -------------------------
row_ans = inputdlg( ...
    'Number of rows for the frame-grid figure(s):', ...
    'Frame-grid rows', [1 60], {'2'});
if isempty(row_ans), error('Number of rows not specified. Cancelled.'); end
n_rows_setting = round(str2double(row_ans{1}));
assert(isfinite(n_rows_setting) && n_rows_setting >= 1, 'Number of rows must be a positive integer.');

%% -------------------------
% COLOR SCALE (interactive) — autoscale per combination, or one fixed
% [min max] dF/F range shared by every selected combination
% -------------------------
clim_choice = questdlg( ...
    'How should the dF/F color scale be set?', ...
    'dF/F color scale', ...
    'Auto (per combination)', 'Custom (fixed for all)', 'Auto (per combination)');
switch clim_choice
    case 'Auto (per combination)'
        use_custom_clim = false;
        custom_clim     = [];
    case 'Custom (fixed for all)'
        use_custom_clim = true;
        clim_ans = inputdlg( ...
            {'dF/F color-scale minimum:', 'dF/F color-scale maximum:'}, ...
            'Custom dF/F color scale', [1 60], {'-0.02', '0.05'});
        if isempty(clim_ans), error('Color scale not specified. Cancelled.'); end
        custom_clim = [str2double(clim_ans{1}) str2double(clim_ans{2})];
        assert(all(isfinite(custom_clim)) && custom_clim(2) > custom_clim(1), ...
            'Color-scale minimum must be finite and less than the maximum.');
    otherwise
        error('Color scale not specified. Cancelled.');
end
if use_custom_clim
    fprintf('Color scale: fixed [%g %g] for all combinations.\n', custom_clim(1), custom_clim(2));
else
    fprintf('Color scale: autoscaled per combination.\n');
end

%% -------------------------
% VISUAL-AREA BOUNDARIES (interactive, optional) — V1 + all higher areas
% from a step-6 day_setup.mat, drawn on every frame of every figure
% -------------------------
area_choice = questdlg( ...
    'Overlay visual-area boundaries (V1 + LM, AL, PM, ...) from a step-6 day_setup.mat?', ...
    'Visual-area boundaries', ...
    'Yes', 'No', 'No');
show_areas        = strcmp(area_choice, 'Yes');
V1_mask_stim      = [];
region_bound_stim = [];

if show_areas
    [ds_fn, ds_fp] = uigetfile('*day_setup*.mat', ...
        'Select day_setup.mat (from step 6) -- provides V1 + visual-area boundaries');
    if isequal(ds_fn, 0), error('No day_setup.mat selected.'); end
    DS = load(fullfile(ds_fp, ds_fn));
    assert(isfield(DS, 'day_setup') && isfield(DS.day_setup, 'retino_align'), ...
        'Selected file does not contain a day_setup.retino_align struct:\n  %s', fullfile(ds_fp, ds_fn));
    RA = DS.day_setup.retino_align;

    V1_mask_stim = get_field_or_empty(RA, 'V1_mask_stim');
    if ~isempty(V1_mask_stim), V1_mask_stim = logical(V1_mask_stim); end

    region_bound_stim = get_field_or_empty(RA, 'retOverlay_stim');
    if ~isempty(region_bound_stim)
        region_bound_stim = logical(region_bound_stim);
        if region_bound_dilate_px > 0
            region_bound_stim = imdilate(region_bound_stim, strel('disk', region_bound_dilate_px));
        end
    else
        warning('day_setup has no retOverlay_stim -- higher visual-area boundaries will not be shown. Re-run the updated step 6.');
    end

    if isempty(V1_mask_stim) && isempty(region_bound_stim)
        warning('day_setup contains neither V1_mask_stim nor retOverlay_stim -- no boundaries will be drawn.');
        show_areas = false;
    else
        fprintf('Visual-area overlay: on (%s)\n', fullfile(ds_fp, ds_fn));
    end
else
    fprintf('Visual-area overlay: off\n');
end

%% -------------------------
% MAIN LOOP — one figure per selected channel/current combination, saved
% into that combination's own step-5_A subfolder
% -------------------------
cmap = jet(256);

for ci = 1:n_sel
    mv_fpath = fullfile(mat_files(ci).folder, mat_files(ci).name);
    [~, base_name] = fileparts(mat_files(ci).name);

    S = load(mv_fpath);
    if isfield(S, 'mean_dff_movie'),  movie = S.mean_dff_movie;
    elseif isfield(S, 'dff_movie'),   movie = S.dff_movie;
    else, error('File does not contain dff_movie or mean_dff_movie:\n  %s', mv_fpath); end
    assert(isfield(S, 't_s'), 'Missing t_s in:\n  %s', mv_fpath);

    t_s = double(S.t_s(:)');
    [H, W, T] = size(movie);
    if isfield(S, 'final_mask')
        valid_mask = logical(S.final_mask);
    else
        valid_mask = ~all(isnan(movie), 3);
    end
    fprintf('\n[%d/%d] %s  (%d x %d x %d)\n', ci, n_sel, mat_files(ci).name, H, W, T);

    display_t_all      = display_tmin : display_step_s : display_tmax;
    display_frame_idx  = zeros(size(display_t_all));
    for di = 1:numel(display_t_all)
        [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
    end
    display_frame_idx = unique(display_frame_idx, 'stable');
    display_frame_idx(display_frame_idx < 1 | display_frame_idx > T) = [];
    n_display = numel(display_frame_idx);
    if n_display == 0
        warning('  No frames fall inside the requested time window for %s -- skipped.', mat_files(ci).name);
        continue;
    end

    n_rows = min(n_rows_setting, n_display);
    n_cols = ceil(n_display / n_rows);
    fprintf('  Frame grid: %d frame(s) -> %d rows x %d cols\n', n_display, n_rows, n_cols);

    % Visual-area boundaries only apply if they share this movie's pixel
    % grid; a mismatch means the day_setup came from a different session, so
    % skip the overlay for this combination instead of aborting the batch.
    V1_this     = V1_mask_stim;
    region_this = region_bound_stim;
    if show_areas
        if ~isempty(V1_this) && ~isequal(size(V1_this), [H W])
            warning('  day_setup V1_mask_stim is %dx%d but this movie is %dx%d -- V1 overlay skipped.', ...
                size(V1_this,1), size(V1_this,2), H, W);
            V1_this = [];
        end
        if ~isempty(region_this) && ~isequal(size(region_this), [H W])
            warning('  day_setup retOverlay_stim is %dx%d but this movie is %dx%d -- area overlay skipped.', ...
                size(region_this,1), size(region_this,2), H, W);
            region_this = [];
        end
    end

    % The area boundary map is a 1-px line mask, so paint those pixels
    % directly with a constant alpha rather than tracing an outline around
    % them (tracing would draw each line twice, once per side).
    region_rgb   = [];
    region_alpha = [];
    if ~isempty(region_this)
        region_rgb = cat(3, region_bound_color(1) * ones(H, W), ...
                            region_bound_color(2) * ones(H, W), ...
                            region_bound_color(3) * ones(H, W));
        region_alpha = region_bound_alpha * double(region_this);
    end

    %% Plot
    if use_custom_clim
        clim_to_use = custom_clim;
        fprintf('  Color scale: custom [%g %g]\n', clim_to_use(1), clim_to_use(2));
    else
        clim_to_use = data_clim(movie, valid_mask);
        fprintf('  Color scale: auto [%g %g]\n', clim_to_use(1), clim_to_use(2));
    end

    fig = figure('Color', 'w', ...
        'Name', sprintf('dF/F frame grid - %s', base_name), ...
        'Position', [50 50 min(1900, 260*n_cols) 260*n_rows + 90]);
    tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

    last_ax = [];
    for di = 1:n_display
        fi = display_frame_idx(di);
        ax = nexttile(tl);
        imagesc(ax, movie(:,:,fi));
        axis(ax, 'image'); axis(ax, 'off');
        set(ax, 'YDir', 'normal');
        colormap(ax, cmap);
        clim(ax, clim_to_use);
        hold(ax, 'on');
        visboundaries(ax, valid_mask, 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8);
        if ~isempty(region_rgb)
            h_reg = image(ax, region_rgb);
            set(h_reg, 'AlphaData', region_alpha);
        end
        if ~isempty(V1_this)
            draw_mask_outline(ax, V1_this, v1_color, v1_line_width, v1_alpha);
        end
        title(ax, sprintf('t = %+.2f s', t_s(fi)), 'FontSize', font_size_tile_title);
        last_ax = ax;
    end

    if ~isempty(last_ax)
        cb = colorbar(last_ax);
        cb.FontSize = font_size_colorbar;
    end

    title_str = sprintf('dF/F frame grid  |  %s', base_name);
    if ~isempty(region_this) && ~isempty(V1_this)
        title_str = [title_str '  |  visual areas (orange) + V1 (yellow)'];
    elseif ~isempty(region_this)
        title_str = [title_str '  |  visual areas (orange)'];
    elseif ~isempty(V1_this)
        title_str = [title_str '  |  V1 (yellow)'];
    end
    title(tl, title_str, 'Interpreter', 'none', 'FontSize', font_size_main_title);

    if use_custom_clim
        clim_tag = sprintf('clim_%g_to_%g', custom_clim(1), custom_clim(2));
        clim_tag = strrep(clim_tag, '.', 'p');
    else
        clim_tag = 'clim_auto';
    end
    if ~isempty(region_this) || ~isempty(V1_this)
        area_tag = '_visual_areas';
    else
        area_tag = '';
    end
    fig_fname = sprintf('%s_custom_frame_grid_%.2fs_to_%.2fs_%s%s.png', ...
        base_name, display_tmin, display_tmax, clim_tag, area_tag);
    exportgraphics(fig, fullfile(mat_files(ci).folder, fig_fname), 'Resolution', 150);
    close(fig);
    fprintf('  Saved: %s\n', fullfile(mat_files(ci).folder, fig_fname));
end

fprintf('\nDone. %d combination(s) processed.\n', n_sel);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function draw_mask_outline(ax, mask, color, lw, alpha_val)
% Thin, semi-transparent outline of a filled binary region. Used instead of
% visboundaries, which draws an extra thick contrast halo under every line
% and would obscure the dF/F map underneath.
B = bwboundaries(logical(mask));
rgba = [color(:)' alpha_val];
for k = 1:numel(B)
    b = B{k};
    try
        plot(ax, b(:,2), b(:,1), '-', 'Color', rgba, 'LineWidth', lw);
    catch
        % Older graphics backends reject RGBA line colors -- fall back to an
        % opaque line in the same hue.
        plot(ax, b(:,2), b(:,1), '-', 'Color', color, 'LineWidth', lw);
    end
end
end

function v = get_field_or_empty(S, name)
if isfield(S, name) && ~isempty(S.(name))
    v = S.(name);
else
    v = [];
end
end

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values
% across the whole movie. Same convention as the rest of the pipeline.
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