


%% plot_dff_frame_with_visual_areas.m
% Plotting-only tool: picks one or more channel & current combinations
% from a step-5_A output folder, picks ONE time point t (shared across all
% selected combinations), and plots each combination's dF/F frame at that
% t with the visual-area boundaries (V1 + all higher areas such as LM, AL,
% PM, ...) from a day_setup.mat overlaid on top -- one figure per
% combination.
%
% Requires a day_setup.mat produced by the UPDATED step 6
% (retino_alignment_with_brain_mask_6.m), which now saves
% day_setup.retino_align.retOverlay_stim -- the full set of visual-area
% boundaries warped onto the SAME stim/brain-mask pixel grid as the
% step-5_A dF/F movies (nearest-neighbor interpolation, no manual
% re-selection needed). V1_mask_stim is overlaid the same way it always
% has been.
%
% Orientation/convention: axis image / axis off / YDir normal, matching
% every other dF/F figure in this pipeline (step 5_A, 7_A, 8, ...) -- both
% the dF/F movies and the day_setup boundary fields already share that
% same pixel grid, so no additional warping happens here.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
mask_color_outside  = [0.15 0.15 0.15];
region_bound_color  = [1.00 0.55 0.00];
region_bound_dilate_px = 1;
v1_color            = [1.00 0.85 0.10];
font_size_title     = 13;

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
% SELECT TIME POINT t (shared across all selected combinations)
% -------------------------
t_ans = inputdlg('Time point t (s) to display for all selected combination(s):', ...
    'Select time point', [1 60], {'0.5'});
if isempty(t_ans), error('No time point specified. Cancelled.'); end
t_target = str2double(t_ans{1});
assert(isfinite(t_target), 't must be a number.');

%% -------------------------
% SELECT day_setup.mat (from the updated step 6) -- V1 + all-area boundaries
% -------------------------
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
    warning('day_setup has no retOverlay_stim -- visual-area boundaries will not be shown. Re-run the updated step 6.');
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(ds_fp, 'Select output folder for the figure(s)');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% MAIN LOOP -- one figure per selected channel/current combination
% -------------------------
cmap = jet(256);

for ci = 1:n_sel
    mv_fpath = fullfile(mat_files(ci).folder, mat_files(ci).name);
    sel_ch   = chs(ci);
    sel_cur  = curs(ci);

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
    fprintf('\n[%d/%d] %s  (Ch %d, %g uA, %d x %d x %d)\n', ...
        ci, n_sel, mat_files(ci).name, sel_ch, sel_cur, H, W, T);

    [~, fi] = min(abs(t_s - t_target));
    fprintf('  Nearest frame: t = %+.3f s (requested %+.3f s)\n', t_s(fi), t_target);
    frame = movie(:, :, fi);

    if ~isempty(V1_mask_stim)
        assert(isequal(size(V1_mask_stim), [H W]), ...
            'day_setup V1_mask_stim size (%dx%d) does not match this dF/F movie size (%dx%d).', ...
            size(V1_mask_stim,1), size(V1_mask_stim,2), H, W);
    end
    if ~isempty(region_bound_stim)
        assert(isequal(size(region_bound_stim), [H W]), ...
            'day_setup retOverlay_stim size (%dx%d) does not match this dF/F movie size (%dx%d).', ...
            size(region_bound_stim,1), size(region_bound_stim,2), H, W);
    end

    clim_to_use = data_clim(movie, valid_mask);
    rgb = scalar_frame_to_rgb(frame, ~valid_mask, clim_to_use, cmap, mask_color_outside);

    fig = figure('Color', 'w', 'Position', [100 100 800 700]);
    ax = axes(fig);
    image(ax, rgb);
    axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
    visboundaries(ax, valid_mask, 'Color', [0.9 0.9 0.9], 'LineWidth', 0.6);
    if ~isempty(region_bound_stim)
        visboundaries(ax, region_bound_stim, 'Color', region_bound_color, 'LineWidth', 1.0);
    end
    if ~isempty(V1_mask_stim)
        visboundaries(ax, V1_mask_stim, 'Color', v1_color, 'LineWidth', 1.5);
    end
    colormap(ax, cmap); clim(ax, clim_to_use);
    cb = colorbar(ax);
    cb.Label.String = '\DeltaF/F';
    title(ax, sprintf('Ch %d  |  %g uA  |  t = %+.2f s  |  visual areas overlaid', sel_ch, sel_cur, t_s(fi)), ...
        'Interpreter', 'none', 'FontSize', font_size_title);

    out_fname = sprintf('dff_ch%d_%guA_t%+.2fs_visual_areas.png', sel_ch, sel_cur, t_s(fi));
    out_fname = strrep(out_fname, '+', 'p');   % keep filenames shell/Windows-friendly
    exportgraphics(fig, fullfile(save_dir, out_fname), 'Resolution', 150);
    close(fig);
    fprintf('  Saved: %s\n', fullfile(save_dir, out_fname));
end

fprintf('\nDone. %d figure(s) saved in:\n  %s\n', n_sel, save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function v = get_field_or_empty(S, name)
if isfield(S, name) && ~isempty(S.(name))
    v = S.(name);
else
    v = [];
end
end

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values
% across the whole movie. Same convention as steps 5_A/5_B/7_A/7_B/8.
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

function rgb = scalar_frame_to_rgb(frame, mask, clim_range, cmap, mask_color)
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