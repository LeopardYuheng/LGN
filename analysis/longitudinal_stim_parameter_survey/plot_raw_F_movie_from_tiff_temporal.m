%% plot_raw_F_movie_from_tiff_temporal.m
% Sanity check by ACQUISITION TIME: plot the RAW fluorescence F(x,y,t) movie for
% trials chosen by their position in the experiment (e.g. the first 50 trials of
% the session, out of ~1980), straight from the original TIFFs via the day
% pointer built in step 3. Use it to verify that focus and illumination are
% stable as the session progresses (the dF/F pipeline divides F_global out, so
% illumination / focus drift is only visible in the raw images).
%
% Same as plot_raw_F_movie_from_tiff_per_condition.m, except trials are selected
% by acquisition order instead of by channel/current.
%
% Three things are chosen interactively when you run it:
%   OPTION 1 — Colorbar: grayscale (linear) or rainbow (jet). The rainbow scale
%              makes small F changes easier to see.
%   OPTION 2 — A range of trials in EXPERIMENT TIME ORDER: all valid trials are
%              sorted by onset time (trial #1 = first acquired ... #N = last),
%              and you enter a first/last trial number (e.g. 1 and 50).
%   OPTION 3 — Color-scale range: from the BRAIN MASK (min/max F inside the
%              mask drawn in earlier steps, carried by the day pointer) or from
%              the whole frame. Using the brain mask makes the in-brain F
%              variation fill the colormap instead of being squashed by bright
%              or dark pixels outside the brain. If the day pointer has no mask,
%              you can point at a brain_mask.mat / day_setup when prompted.
%
% For each selected trial this script:
%   1. Uses the day pointer to find the trial's TIFF frames
%      (onset frame index + the fixed pre/post window).
%   2. Loads the raw TIFF stack for the trial window — the true original
%      images, full frame, no masking or normalisation.
%   3. Writes an MP4 movie of the raw F(x,y,t) over the trial window — one per
%      trial, named with its acquisition order — plus a MEAN movie over the
%      selected window. (A static frame-grid PNG/PDF is available too but off by
%      default; the movie is the point.)
%
% All movies use ONE shared intensity scale, so a dim, saturated, or defocused
% trial stands out immediately. Output goes into a trials_{i0}to{i1} subfolder
% (ch{N}_{I}uA/) of the chosen output folder.
%
% Requires: the day pointer .mat from make_container_ripple_3.m (step 3),
% with the original TIFF folder still in its recorded location.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
% --- MP4 video (the primary output) ---
video_frame_rate_fps = 10;    % playback rate; camera is ~10 Hz, so ~real time
video_quality        = 95;
% --- shared intensity scale ---
grayscale_clim_pct   = [1 99];% percentiles for the shared intensity scale
overlay_brain        = true;  % draw the brain-mask boundary if available
% --- optional static frame-grid PNG / PDF (off by default; the MP4 is the point) ---
make_frame_grid      = false; % also save a static frame-grid PNG per trial/average
n_cols               = 5;     % columns in that optional frame-grid
display_step_s       = 0.2;   % displayed-frame spacing (s) in that optional frame-grid
make_pdf             = false; % append the optional frame-grids to one multipage PDF

%% -------------------------
% LOAD DAY POINTER
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer (from step 3)');
if isequal(fn, 0), error('No file selected.'); end
S = load(fullfile(fp, fn));
if     isfield(S, 'day_pointer'), day_pointer = S.day_pointer;
elseif isfield(S, 'C'),           day_pointer = S.C;
else,  error('Expected "day_pointer" or legacy "C" in selected file.');
end
assert(isfield(day_pointer, 'meta') && isfield(day_pointer, 'cfg') && ...
       isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
       'day_pointer is missing meta / cfg / entries.');

%% -------------------------
% OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(fp, 'Select output folder for raw-F sanity-check figures');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
pdf_path = fullfile(save_dir, 'rawF_0uA_sanitycheck.pdf');
if make_pdf && exist(pdf_path, 'file'), delete(pdf_path); end

%% -------------------------
% BRAIN MASK (from the day pointer / day_setup)
% Used for the color-scale range option and the boundary overlay. Validated
% against the frame size and finalised after the TIFFs are resolved (below).
% -------------------------
final_mask = get_brain_mask(day_pointer, []);

%% -------------------------
% RESOLVE TIFF DIRECTORY & SORT FRAMES
% -------------------------
dataset_root = '';
if isfield(day_pointer.meta, 'dataset_root')
    dataset_root = day_pointer.meta.dataset_root;
end
img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');
fprintf('TIFF directory:\n  %s\n', img_dir);

image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFF files found in:\n  %s', img_dir);
nums = nan(numel(image_files), 1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord]    = sort(nums);
image_files = image_files(ord);
nFrames     = numel(image_files);

probe = imread(fullfile(img_dir, image_files(1).name));
[H, W] = size(probe);
fprintf('Frame size: %d x %d   |   total frames: %d\n', H, W, nFrames);

%% -------------------------
% TIMING / TRIAL WINDOW
% -------------------------
Fs          = infer_camera_rate(day_pointer);
pre_sec     = double(day_pointer.cfg.pre_sec);
post_sec    = double(day_pointer.cfg.post_sec);
pre_frames  = round(pre_sec  * Fs);
post_frames = round(post_sec * Fs);
full_win    = (-pre_frames : post_frames);
t_s         = full_win / Fs;
T           = numel(full_win);
fprintf('Camera %.2f Hz | window -%.1fs..+%.1fs (%d frames/trial)\n', Fs, pre_sec, post_sec, T);

%% -------------------------
% OPTION 1 — COLORBAR CHOICE
% -------------------------
cmap_choice = questdlg('Color scale for the raw F display?', 'Colorbar', ...
    'Grayscale (linear)', 'Rainbow (jet)', 'Grayscale (linear)');
if isempty(cmap_choice), error('Cancelled.'); end
if strcmp(cmap_choice, 'Rainbow (jet)')
    disp_cmap = jet(256);   cmap_tag = 'rainbow';
else
    disp_cmap = gray(256);  cmap_tag = 'grayscale';
end
fprintf('Colorbar: %s\n', cmap_tag);

%% -------------------------
% OPTION 2 — SELECT TRIALS BY EXPERIMENT TIME ORDER
% -------------------------
[frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(day_pointer.entries);
valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);
frame_idx   = frame_idx(valid);
channels    = channels(valid);
currents    = currents(valid);
trial_index = trial_index(valid);
assert(~isempty(frame_idx), 'No valid trials found in the day pointer.');

% Order all trials by their onset frame index = the order they ran in the
% session (trial #1 = first acquired, ... trial #N = last acquired).
[~, ord]    = sort(frame_idx, 'ascend');
frame_idx   = frame_idx(ord);
channels    = channels(ord);
currents    = currents(ord);
trial_index = trial_index(ord);
nTrials     = numel(frame_idx);
fprintf('Total valid trials in session: %d (ordered by acquisition time).\n', nTrials);

% Ask for a temporal range, e.g. the first 50 trials of the experiment.
resp = inputdlg( ...
    {sprintf('First trial # in experiment order (1-%d):', nTrials), ...
     sprintf('Last  trial # in experiment order (1-%d):', nTrials)}, ...
    'Select trials by acquisition time', [1 50; 1 50], ...
    {'1', num2str(min(50, nTrials))});
if isempty(resp), error('Cancelled.'); end
i0 = max(1, round(str2double(resp{1})));
i1 = min(nTrials, round(str2double(resp{2})));
assert(isfinite(i0) && isfinite(i1) && i1 >= i0, 'Need 1 <= first <= last <= N.');
sel         = i0 : i1;             % positions in acquisition order
sel_order   = sel;
sel_onset   = frame_idx(sel);
sel_chan    = channels(sel);
sel_cur     = currents(sel);
sel_trialid = trial_index(sel);
fprintf('Selected trials %d..%d  (%d trials) in acquisition order.\n', i0, i1, numel(sel));

%% -------------------------
% OPTION 3 — COLOR-SCALE RANGE (whole frame vs inside the brain mask)
% -------------------------
% Validate any mask found in the day pointer against the frame size.
if ~isempty(final_mask) && ~isequal(size(final_mask), [H W])
    warning('Brain mask is %s but frames are %dx%d — ignoring it.', ...
        mat2str(size(final_mask)), H, W);
    final_mask = [];
end
% If the day pointer did not carry a mask, let the user select one.
if isempty(final_mask)
    [mfn, mfp] = uigetfile('*.mat', ...
        'Optional: select brain_mask.mat / day_setup for masking (Cancel = whole frame)');
    if ~isequal(mfn, 0)
        final_mask = get_brain_mask(load(fullfile(mfp, mfn)), [H W]);
    end
end
% Choose where the color-scale (CLim) range comes from.
if ~isempty(final_mask)
    rc = questdlg('Color-scale range computed from?', 'Color scale range', ...
        'Brain mask (min/max in mask)', 'Whole frame (1-99%)', 'Brain mask (min/max in mask)');
    if isempty(rc), error('Cancelled.'); end
    use_mask_clim = strcmp(rc, 'Brain mask (min/max in mask)');
    fprintf('Brain mask: %d in-mask pixels.\n', sum(final_mask(:)));
else
    use_mask_clim = false;
    fprintf('No brain mask available — color scale will use the whole frame.\n');
end
% The boundary outline is only drawn if overlay_brain is on and a mask exists.
if overlay_brain, outline_mask = final_mask; else, outline_mask = []; end

%% -------------------------
% DISPLAYED FRAME INDICES (subsample the window)
% -------------------------
display_t = t_s(1) : display_step_s : t_s(end);
display_frame_idx = zeros(size(display_t));
for di = 1:numel(display_t)
    [~, display_frame_idx(di)] = min(abs(t_s - display_t(di)));
end
display_frame_idx = unique(display_frame_idx, 'stable');
n_disp = numel(display_frame_idx);
n_rows = ceil(n_disp / n_cols);

%% -------------------------
% PASS 1 — SHARED INTENSITY CLIM (one representative frame per selected trial)
% -------------------------
fprintf('\nPass 1/2: estimating shared intensity scale...\n');
onsets_sel = sel_onset;
samp = [];
for k = 1:numel(onsets_sel)
    f = onsets_sel(k);                        % onset frame is representative
    if f < 1 || f > nFrames, continue; end
    im = double(imread(fullfile(img_dir, image_files(f).name)));
    if use_mask_clim
        samp = [samp; im(final_mask)]; %#ok<AGROW>   % only pixels inside the brain mask
    else
        samp = [samp; im(1:7:end)];    %#ok<AGROW>   % subsample of the whole frame
    end
end
if use_mask_clim
    clim_shared = [min(samp) max(samp)];                 % min/max F inside the brain mask
    src_lbl = 'brain mask min/max';
else
    q = quantile(samp(:), grayscale_clim_pct / 100);
    clim_shared = [q(1) q(2)];
    src_lbl = sprintf('whole frame %g-%g%%', grayscale_clim_pct(1), grayscale_clim_pct(2));
end
if ~(clim_shared(2) > clim_shared(1)), clim_shared = [min(samp(:)) max(samp(:))]; end
fprintf('Shared CLim (%s): [%.0f  %.0f]\n', src_lbl, clim_shared(1), clim_shared(2));

%% -------------------------
% PASS 2 — ONE MOVIE PER SELECTED TRIAL (in acquisition order) + MEAN
% -------------------------
out_dir = fullfile(save_dir, sprintf('trials_%dto%d', i0, i1));
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

avg_stack = zeros(H, W, T);
n_avg     = 0;
for k = 1:numel(sel)
    f      = sel_onset(k);
    frames = f + full_win;
    if any(frames < 1) || any(frames > nFrames)
        fprintf('  #%d (ch%d %guA trial %d): window out of range — skipped.\n', ...
            sel_order(k), sel_chan(k), sel_cur(k), sel_trialid(k));
        continue;
    end
    % Onset diagnostic: the t=0 frame of this window is the trial's onset frame
    % (frames(pre_frames+1) == f), i.e. the frame steps 1-2 aligned to stim onset.
    fprintf('  #%d ch%d %guA trial %d | onset(=t0) frame %d = TIFF "%s" | session t0 = %.2f s | window frames %d..%d\n', ...
        sel_order(k), sel_chan(k), sel_cur(k), sel_trialid(k), f, ...
        image_files(f).name, (f - 1) / Fs, frames(1), frames(end));

    stack = zeros(H, W, T);
    for fi = 1:T
        stack(:, :, fi) = double(imread(fullfile(img_dir, image_files(frames(fi)).name)));
    end

    ttl = sprintf('Raw F  |  #%d in session  |  ch%d %guA  |  trial %d', ...
        sel_order(k), sel_chan(k), sel_cur(k), sel_trialid(k));
    mp4 = fullfile(out_dir, sprintf('rawF_order%03d_ch%d_%guA_trial%d.mp4', ...
        sel_order(k), sel_chan(k), sel_cur(k), sel_trialid(k)));
    write_raw_video(stack, t_s, clim_shared, disp_cmap, outline_mask, ttl, mp4, ...
        video_frame_rate_fps, video_quality);
    if make_frame_grid
        render_raw_grid(stack, t_s, display_frame_idx, n_cols, n_rows, ...
            clim_shared, disp_cmap, outline_mask, ttl, strrep(mp4, '.mp4', '.png'), make_pdf, pdf_path);
    end

    avg_stack = avg_stack + stack;
    n_avg     = n_avg + 1;
    if mod(k, 5) == 0 || k == numel(sel)
        fprintf('  rendered %d / %d trials\n', k, numel(sel));
    end
end

if n_avg > 0
    avg_stack = avg_stack / n_avg;
    ttl = sprintf('Raw F MEAN of trials #%d..#%d  (n = %d)', i0, i1, n_avg);
    mp4 = fullfile(out_dir, sprintf('rawF_MEAN_trials_%dto%d.mp4', i0, i1));
    write_raw_video(avg_stack, t_s, clim_shared, disp_cmap, outline_mask, ttl, mp4, ...
        video_frame_rate_fps, video_quality);
    if make_frame_grid
        render_raw_grid(avg_stack, t_s, display_frame_idx, n_cols, n_rows, ...
            clim_shared, disp_cmap, outline_mask, ttl, strrep(mp4, '.mp4', '.png'), make_pdf, pdf_path);
    end
    fprintf('  saved mean movie of the selected window.\n');
end

fprintf('\nDone.\nMP4 movies (per trial, in acquisition order) + mean are in:\n  %s\n', out_dir);
if make_pdf, fprintf('Optional frame-grid PDF: %s\n', pdf_path); end

%% =========================
% LOCAL FUNCTIONS
%% =========================

function write_raw_video(stack, t_s, clim_shared, disp_cmap, final_mask, ttl, mp4_path, fps, quality)
% Write a raw F movie to MP4: each frame is stack(:,:,k) on the fixed shared
% intensity scale, with the chosen colormap, a colorbar, and a t-stamped title.
[~, ~, T] = size(stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 640 620]);
ax  = axes(fig, 'Position', [0.08 0.08 0.78 0.84]);

writer = VideoWriter(mp4_path, 'MPEG-4');
writer.FrameRate = fps;
writer.Quality   = quality;
open(writer);

img = imagesc(ax, stack(:, :, 1), clim_shared);
colormap(ax, disp_cmap);
set(ax, 'CLim', clim_shared);
axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal'); hold(ax, 'on');
if ~isempty(final_mask)
    visboundaries(ax, final_mask, 'Color', [1 0 1], 'LineWidth', 0.5);
end
cb = colorbar(ax); cb.Label.String = 'raw F (counts)';
th = title(ax, '', 'Interpreter', 'none');
% Static reminder that t = 0 is the stim-onset frame, plus a red marker that
% lights up on the t = 0 frame so you can confirm the window is centred on it.
text(ax, 0.02, 0.98, 'stim onset \rightarrow t = 0 s', 'Units', 'normalized', ...
    'Color', [0.85 0.1 0.1], 'FontWeight', 'bold', 'FontSize', 9, 'VerticalAlignment', 'top');
[~, izero] = min(abs(t_s));   % frame nearest t = 0
drawnow;

target = [];
for k = 1:T
    set(img, 'CData', stack(:, :, k));
    if k == izero
        set(th, 'String', sprintf('%s | t = %+.2f s   <-- STIM ONSET', ttl, t_s(k)), ...
            'Color', [0.85 0.1 0.1]);
    else
        set(th, 'String', sprintf('%s | t = %+.2f s', ttl, t_s(k)), 'Color', 'k');
    end
    drawnow;
    fr = frame2im(getframe(fig));
    if isempty(target)
        target = [size(fr, 1) size(fr, 2)];
    elseif size(fr, 1) ~= target(1) || size(fr, 2) ~= target(2)
        fr = imresize(fr, target);
    end
    writeVideo(writer, fr);
end
close(writer);
close(fig);
end

function render_raw_grid(stack, t_s, display_frame_idx, n_cols, n_rows, ...
    clim_shared, disp_cmap, final_mask, ttl, png_path, make_pdf, pdf_path)
% Frame-grid of a raw F movie on a fixed intensity scale, using disp_cmap
% (grayscale or rainbow/jet).
fig = figure('Color', 'w', 'Visible', 'off', ...
    'Position', [50 50  min(1800, 230 * n_cols)  230 * n_rows + 80]);
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');
last_ax = [];
for di = 1:numel(display_frame_idx)
    fi = display_frame_idx(di);
    ax = nexttile(tl);
    imagesc(ax, stack(:, :, fi), clim_shared);
    colormap(ax, disp_cmap);
    axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal');
    if ~isempty(final_mask)
        hold(ax, 'on');
        visboundaries(ax, final_mask, 'Color', [1 0 1], 'LineWidth', 0.5);
    end
    title(ax, sprintf('t = %+.1f s', t_s(fi)), 'FontSize', 8);
    last_ax = ax;
end
if ~isempty(last_ax)
    cb = colorbar(last_ax); cb.Label.String = 'raw F (counts)';
end
title(tl, ttl, 'Interpreter', 'none', 'FontSize', 12);
exportgraphics(fig, png_path, 'Resolution', 130);
if make_pdf
    exportgraphics(fig, pdf_path, 'Append', true, 'Resolution', 130);
end
close(fig);
end

function path_out = resolve_file_path(rel_or_abs, dataset_root, kind)
want = 7; if strcmp(kind, 'file'), want = 2; end
if exist(rel_or_abs, kind) == want
    path_out = rel_or_abs;
else
    path_out = fullfile(dataset_root, rel_or_abs);
end
assert(exist(path_out, kind) == want, 'Path does not exist:\n  %s', path_out);
end

function Fs = infer_camera_rate(day_pointer)
if isfield(day_pointer.meta, 'camera_rate_hz') && ~isempty(day_pointer.meta.camera_rate_hz)
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq') && ~isempty(day_pointer.meta.Freq)
    Fs = double(day_pointer.meta.Freq);
else
    Fs = 10;
    warning('Camera rate not found in day_pointer.meta — defaulting to 10 Hz.');
end
end

function [frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(entries)
frame_idx = []; channels = []; currents = []; trial_index = [];
for i = 1:numel(entries)
    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i     = numel(onset_i);
    frame_idx = [frame_idx; onset_i]; %#ok<AGROW>
    channels  = [channels;  repmat(double(entries(i).stim_channel), n_i, 1)]; %#ok<AGROW>
    currents  = [currents;  repmat(double(entries(i).current_uA),   n_i, 1)]; %#ok<AGROW>
    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_index = [trial_index; double(entries(i).trial_index(:))]; %#ok<AGROW>
    else
        trial_index = [trial_index; (1:n_i)']; %#ok<AGROW>
    end
end
end

function m = get_brain_mask(src, expected_size)
% Pull the brain mask (final_mask) out of a day pointer / day_setup /
% brain_mask.mat struct. Tries the common field nestings used across the
% pipeline. Returns a logical H x W mask, or [] if none is found.
m = [];
cand = try_fields(src);
if isempty(cand) && isstruct(src)
    ds = resolve_day_setup(src);     % follow a referenced day_setup file
    cand = try_fields(ds);
end
if isempty(cand), return; end
m = logical(cand);
if nargin >= 2 && ~isempty(expected_size) && ~isequal(size(m), expected_size)
    warning('get_brain_mask:size', 'Mask %s != expected %s; ignoring.', ...
        mat2str(size(m)), mat2str(expected_size));
    m = [];
end
end

function c = try_fields(s)
% Search a struct for a brain mask under the field names used by
% draw_brain_mask_0.m (reference_mask_struct.final_mask), the day_setup
% (reference_mask.final_mask), or a plain final_mask / brain_mask.
c = [];
if isempty(s) || ~isstruct(s), return; end
if isfield(s, 'reference_mask') && isstruct(s.reference_mask) && ...
        isfield(s.reference_mask, 'final_mask')
    c = s.reference_mask.final_mask; return;
end
if isfield(s, 'reference_mask_struct') && isstruct(s.reference_mask_struct) && ...
        isfield(s.reference_mask_struct, 'final_mask')
    c = s.reference_mask_struct.final_mask; return;
end
if isfield(s, 'final_mask'), c = s.final_mask; return; end
if isfield(s, 'brain_mask'), c = 