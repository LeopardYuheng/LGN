%% current_thresholding_analysis_pixelwise_region_5A.m  (multi-session combined)
% Step 5_A: Pixelwise dF/F(x,y,t) movie computation (Method 0, per-trial baseline).
%
% COMBINED-SESSION VARIANT: use this when the same channel/current design was
% run across multiple independent acquisition SESSIONS (its own TIFF folder,
% .nev file, and day pointer from step 3 per session) instead of one big
% session — e.g. 3 sessions of 10 trials/condition instead of 1 session of
% 30 trials/condition. You will be prompted for the number of sessions, then
% asked to select each session's day pointer in turn. Trials from ALL
% sessions are pooled per (channel, current) condition before averaging, so
% the output is equivalent to having run the full trial count in one session.
%
% Requirements for combining sessions:
%   - Same channel/current design, same camera rate, same pre/post window
%     (cfg.pre_sec / cfg.post_sec) in every session's day pointer — checked.
%   - Same field of view / camera position across sessions, since dF/F is
%     combined pixel-by-pixel with a single shared brain mask (no per-session
%     registration is performed).
%
% For each channel-current stimulation condition this script:
%   1. Computes dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)
%      for every trial (pooled across sessions), where F_baseline is the
%      mean over that trial's own pre-stim frames — no cross-session
%      baseline model is needed for Method 0.
%   2. Saves each individual trial movie as  dff_ch{N}_{I}uA_s{S}_trial{K}.mat
%      (S = session index, K = that trial's index within its own session;
%      contains dff_movie H x W x T  and  t_s; use t_s < 0 for pre-stim frames)
%   3. Averages across ALL pooled trials to produce  mean_dff_ch{N}_{I}uA.mat
%      (same format as the single-session script: mean_dff_movie, t_s,
%      final_mask — so steps 6/7/8 need no changes to consume it)
%   4. Saves a frame-grid figure of the mean dF/F over a user-specified
%      display window (default -0.2 to 1.2 s). All frames are always saved.
%
% All outputs for a given channel-current condition are written into their
% own subfolder  save_dir/ch{N}_{I}uA/.
%
% Conditions are listed sorted by channel number then current level
% (same order as step 7_C / 7_D batch runners).
%
% Requires:
%   - One day pointer .mat per session (from make_container_ripple_3.m)
%   - brain_mask.mat    (from draw_brain_mask_0.m), shared across sessions
% Optional:
%   - day_setup .mat with V1 boundary (from step 6) for figure overlay
%
% display_step_s controls figure grid spacing only; all frames always saved.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------

% Output folder for all saved .mat files and figures
save_dir = uigetdir(pwd, 'Select output folder for dF/F movies and figures');
if isequal(save_dir, 0), error('No output folder selected.'); end

% Spacing between displayed frames in the frame-grid figure (seconds).
% Does NOT affect what is saved — all frames are always saved.
display_step_s = 0.1;

% Color limits for the dF/F figures.
% use_auto_clim = true  : symmetric scale set from the 1st/99th percentile
%                          of the data, so it always matches the signal range.
% use_auto_clim = false : use the fixed range in manual_clim below.
use_auto_clim = true;
manual_clim   = [-0.02  0.02];

% Also export per-trial and/or trial-averaged dF/F movies as MP4 videos
% (in addition to the .mat files saved below). Videos use the same color
% limits as the frame-grid figures (clim_to_use) and overlay the brain
% mask boundary. Slower and produces many files for large trial counts.
% Choice is made interactively via the dialog below.
video_export_options = {'Per-trial dF/F videos (.mp4)', 'Trial-averaged (mean) dF/F videos (.mp4)'};
video_sel = listdlg( ...
    'Name',          'Export dF/F movies as video?', ...
    'PromptString',  'Select which dF/F movies to also export as MP4 (Cancel = none):', ...
    'ListString',    video_export_options, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [340 90], ...
    'OKString',      'Export selected', ...
    'CancelString',  'Skip videos');

make_trial_videos    = ismember(1, video_sel);
make_mean_videos     = ismember(2, video_sel);
video_frame_rate_fps = 10;
video_quality        = 95;

%% -------------------------
% SESSIONS TO COMBINE
% Each session is an independent acquisition run (its own TIFF folder,
% .nev file, and day pointer from step 3) that used the SAME channel/current
% design and pre/post trial window. Trials from all sessions are pooled per
% (channel, current) condition further below.
% -------------------------
n_ans = inputdlg('How many sessions to combine?', ...
    'Step 5_A (combined): number of sessions', [1 60], {'3'});
if isempty(n_ans), error('Cancelled.'); end
n_sessions = round(str2double(n_ans{1}));
assert(isfinite(n_sessions) && n_sessions >= 1, 'Number of sessions must be a positive integer.');

sessions = struct('day_pointer', {}, 'img_dir', {}, 'image_files', {}, 'nFrames', {}, ...
    'Fs', {}, 'pre_sec', {}, 'post_sec', {}, 'label', {}, 'source_file', {});

for s = 1:n_sessions
    [fn, fp] = uigetfile('*.mat', sprintf('Session %d of %d: select day pointer', s, n_sessions));
    if isequal(fn, 0), error('No day pointer selected for session %d.', s); end

    S = load(fullfile(fp, fn));
    if isfield(S, 'day_pointer')
        day_pointer = S.day_pointer;
    elseif isfield(S, 'C')
        day_pointer = S.C;
    else
        error('Session %d: selected file must contain "day_pointer" or legacy variable "C".', s);
    end
    assert(isfield(day_pointer, 'meta'),    'Session %d: day_pointer.meta missing.', s);
    assert(isfield(day_pointer, 'cfg'),     'Session %d: day_pointer.cfg missing.', s);
    assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
        'Session %d: day_pointer.entries missing or empty.', s);

    % img_dir_rel stores the absolute path when data and analysis are on
    % separate drives; resolve_file_path uses it directly in that case.
    dataset_root = '';
    if isfield(day_pointer.meta, 'dataset_root')
        dataset_root = day_pointer.meta.dataset_root;
    end
    img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');

    image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
    assert(~isempty(image_files), 'Session %d: no TIFF files found in:\n  %s', s, img_dir);
    nums = nan(numel(image_files), 1);
    for i = 1:numel(image_files)
        tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
        assert(~isempty(tok), 'Session %d: filename missing trailing numeric index: %s', s, image_files(i).name);
        nums(i) = str2double(tok{1});
    end
    [~, ord]    = sort(nums);
    image_files = image_files(ord);

    sessions(s).day_pointer = day_pointer;
    sessions(s).img_dir     = img_dir;
    sessions(s).image_files = image_files;
    sessions(s).nFrames     = numel(image_files);
    sessions(s).Fs          = infer_camera_rate(day_pointer);
    sessions(s).pre_sec     = double(day_pointer.cfg.pre_sec);
    sessions(s).post_sec    = double(day_pointer.cfg.post_sec);
    sessions(s).label       = sprintf('s%d', s);
    sessions(s).source_file = fullfile(fp, fn);

    fprintf('Session %d: %s\n  img_dir: %s\n  Camera %.2f Hz | pre %.1fs | post %.1fs | %d TIFF frames\n', ...
        s, fn, img_dir, sessions(s).Fs, sessions(s).pre_sec, sessions(s).post_sec, sessions(s).nFrames);
end

% Combining trials elementwise across sessions requires every session to
% share the same camera rate and pre/post window (same trial length T).
Fs       = sessions(1).Fs;
pre_sec  = sessions(1).pre_sec;
post_sec = sessions(1).post_sec;
for s = 2:n_sessions
    assert(abs(sessions(s).Fs - Fs) < 1e-6, ...
        'Session %d camera rate (%.4f Hz) differs from session 1 (%.4f Hz). Cannot combine.', ...
        s, sessions(s).Fs, Fs);
    assert(sessions(s).pre_sec == pre_sec && sessions(s).post_sec == post_sec, ...
        'Session %d pre/post window (%.2f/%.2f s) differs from session 1 (%.2f/%.2f s). Cannot combine.', ...
        s, sessions(s).pre_sec, sessions(s).post_sec, pre_sec, post_sec);
end

%% -------------------------
% LOAD BRAIN MASK  (single mask shared across all sessions — same FOV)
% -------------------------
[mask_fn, mask_fp] = uigetfile('*.mat', 'Select brain_mask.mat (shared across all sessions)');
if isequal(mask_fn, 0), error('No brain mask selected.'); end

M = load(fullfile(mask_fp, mask_fn));
assert(isfield(M, 'reference_mask_struct') && isfield(M.reference_mask_struct, 'final_mask'), ...
    'Selected file does not contain reference_mask_struct.final_mask. Did you run draw_brain_mask_0.m?');

final_mask = logical(M.reference_mask_struct.final_mask);
[H, W]     = size(final_mask);
fprintf('Brain mask loaded: %d x %d  |  %d brain pixels\n', H, W, sum(final_mask(:)));

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY  (shared across all sessions)
% -------------------------
v1_outline_color = [0.10 0.85 0.30];   % green V1 contour
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary from step 6 (Cancel = none)');
if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 boundary overlay selected.\n');
else
    V1_mask = load_v1_mask(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask)
        fprintf('V1 boundary loaded: %s\n', v1_fn);
    else
        fprintf('V1 boundary not found or size mismatch — overlay skipped.\n');
    end
end

%% -------------------------
% TIMING (shared across sessions, validated above)
% -------------------------
pre_frames  = round(pre_sec  * Fs);
post_frames = round(post_sec * Fs);
full_win    = -pre_frames : post_frames;
t_s         = full_win / Fs;
T           = numel(full_win);

baseline_idx = t_s < 0;  % logical index into t_s for pre-stim frames

fprintf('Camera rate: %.2f Hz  |  Pre: %.1f s  |  Post: %.1f s  |  %d frames/trial\n', ...
    Fs, pre_sec, post_sec, T);

%% -------------------------
% DISPLAY TIME WINDOW (interactive)
% Controls which frames appear in the frame-grid figure.
% All frames are always saved regardless of this setting.
% -------------------------
win_ans = inputdlg( ...
    {sprintf('Frame-grid start time (s)  [recording covers %.1f to +%.1f s]:', -pre_sec, post_sec), ...
     'Frame-grid end   time (s):'}, ...
    'Frame-grid display window', [1 60], {'-0.2', '1.2'});
if isempty(win_ans), error('Display window not specified. Cancelled.'); end
display_tmin = str2double(win_ans{1});
display_tmax = str2double(win_ans{2});
assert(isfinite(display_tmin) && isfinite(display_tmax) && display_tmin < display_tmax, ...
    'display_tmin must be less than display_tmax.');

%% -------------------------
% UNPACK + POOL TRIAL INFORMATION ACROSS SESSIONS
% session_of(k) records which session trial k came from, so the main loop
% below can load frames from the right TIFF folder and tag the saved
% per-trial filename to avoid collisions with the same trial number in
% another session.
% -------------------------
frame_idx   = [];
channels    = [];
currents    = [];
trial_index = [];
session_of  = [];
for s = 1:n_sessions
    [fi_s, ch_s, cur_s, ti_s] = unpack_day_pointer_entries(sessions(s).day_pointer.entries);

    valid_s = isfinite(fi_s) & isfinite(ch_s) & isfinite(cur_s) & ...
              fi_s > pre_frames & fi_s <= (sessions(s).nFrames - post_frames);

    fi_s  = fi_s(valid_s);  ch_s = ch_s(valid_s);
    cur_s = cur_s(valid_s); ti_s = ti_s(valid_s);

    frame_idx   = [frame_idx;   fi_s];                     %#ok<AGROW>
    channels    = [channels;    ch_s];                     %#ok<AGROW>
    currents    = [currents;    cur_s];                    %#ok<AGROW>
    trial_index = [trial_index; ti_s];                     %#ok<AGROW>
    session_of  = [session_of;  repmat(s, numel(fi_s), 1)]; %#ok<AGROW>

    fprintf('Session %d: %d valid trials\n', s, numel(fi_s));
end
fprintf('Total pooled valid trials across %d session(s): %d\n', n_sessions, numel(frame_idx));

%% -------------------------
% CREATE OUTPUT DIRECTORY
% -------------------------
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
fprintf('Output directory:\n  %s\n', save_dir);

%% -------------------------
% FRAME DISPLAY SELECTION
% Frames at display_tmin : display_step_s : display_tmax are shown in the
% frame-grid figure. Nearest available frame used for each target time.
% -------------------------
display_t_all = display_tmin : display_step_s : display_tmax;

display_frame_idx = zeros(size(display_t_all));
for di = 1:numel(display_t_all)
    [~, display_frame_idx(di)] = min(abs(t_s - display_t_all(di)));
end
% Remove duplicates caused by coarser camera rate than display_step_s
display_frame_idx = unique(display_frame_idx, 'stable');
display_t_all     = t_s(display_frame_idx);

%% -------------------------
% MAIN LOOP — one pass per (channel, current) condition
% Conditions sorted by channel number then current level (same order as 7_C/7_D).
% -------------------------
unique_pairs = unique([channels, currents], 'rows');   % sorted: channel first, then current

%% -------------------------
% INTERACTIVE CONDITION SELECTION
% -------------------------
condition_strs = arrayfun( ...
    @(r) sprintf('Ch %d  |  %g uA', unique_pairs(r,1), unique_pairs(r,2)), ...
    (1:size(unique_pairs,1))', 'UniformOutput', false);

[sel_idx, ok] = listdlg( ...
    'Name',          'Select conditions to analyze', ...
    'PromptString',  'Available channel-current conditions (Ctrl+click for multiple):', ...
    'ListString',    condition_strs, ...
    'SelectionMode', 'multiple', ...
    'ListSize',      [320 220], ...
    'OKString',      'Analyze selected', ...
    'CancelString',  'Cancel');

if ~ok || isempty(sel_idx)
    error('No conditions selected. Analysis cancelled.');
end

unique_pairs = unique_pairs(sel_idx, :);
fprintf('Selected %d condition(s):\n', size(unique_pairs,1));
for r = 1:size(unique_pairs,1)
    fprintf('  Ch %d  |  %g uA\n', unique_pairs(r,1), unique_pairs(r,2));
end

results = struct('channel', {}, 'current_uA', {}, 'n_trials', {}, ...
                 'mean_dff_movie', {}, 't_s', {}, ...
                 'mean_dff_file', {}, 'trial_dff_files', {}, 'cond_dir', {});

for p = 1:size(unique_pairs, 1)

    ch  = unique_pairs(p, 1);
    cur = unique_pairs(p, 2);

    % All outputs for this channel-current condition go in their own
    % subfolder, so trial movies, the mean movie, the frame-grid figure,
    % and any videos for a condition stay grouped together.
    cond_dir = fullfile(save_dir, sprintf('ch%d_%guA', ch, cur));
    if ~exist(cond_dir, 'dir'), mkdir(cond_dir); end

    idx_cond    = (channels == ch) & (currents == cur);
    onsets_cond = frame_idx(idx_cond);
    trials_cond = trial_index(idx_cond);
    sess_cond   = session_of(idx_cond);
    n_cond      = numel(onsets_cond);

    fprintf('\nChannel %d | %g uA | %d trials pooled across %d session(s)\n', ...
        ch, cur, n_cond, n_sessions);

    mean_movie           = zeros(H, W, T);
    count                = 0;
    trial_dff_files      = {};
    n_trials_per_session = zeros(1, n_sessions);

    for k = 1:n_cond

        s      = sess_cond(k);
        f      = onsets_cond(k);
        frames = f + full_win;

        if any(frames < 1) || any(frames > sessions(s).nFrames)
            fprintf('  Session %d trial %d: frame window out of bounds — skipped.\n', ...
                s, trials_cond(k));
            continue;
        end

        % Load frame stack for this trial, from its own session's TIFF folder
        stack = zeros(H, W, T);
        for fi = 1:T
            stack(:,:,fi) = double(imread(fullfile(sessions(s).img_dir, ...
                sessions(s).image_files(frames(fi)).name)));
        end

        % dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)
        % Per-trial baseline needs no cross-session model — same computation
        % regardless of which session the trial came from.
        F_baseline  = mean(stack(:,:,baseline_idx), 3);    % H x W
        dff_movie   = (stack - F_baseline) ./ F_baseline;  % H x W x T

        % Save individual trial movie, tagged with its session (t_s < 0 are
        % pre-stim frames). The session tag keeps e.g. session 1's trial 3
        % and session 2's trial 3 from overwriting each other.
        trial_fname = sprintf('dff_ch%d_%guA_s%d_trial%d.mat', ch, cur, s, trials_cond(k));
        trial_fpath = fullfile(cond_dir, trial_fname);
        save(trial_fpath, 'dff_movie', 't_s', '-v7.3');
        trial_dff_files{end+1} = trial_fpath; %#ok<AGROW>

        % Accumulate for trial-average
        mean_movie = mean_movie + dff_movie;
        count      = count + 1;
        n_trials_per_session(s) = n_trials_per_session(s) + 1;

    end

    if count == 0
        fprintf('  No valid trials — condition skipped.\n');
        continue;
    end

    % Trial-averaged dF/F; set outside-brain pixels to NaN
    mean_movie = mean_movie / count;
    for fi = 1:T
        frame_i = mean_movie(:,:,fi);
        frame_i(~final_mask) = NaN;
        mean_movie(:,:,fi) = frame_i;
    end

    % Save mean movie (t_s < 0 are pre-stim frames). Field names match the
    % single-session script exactly, so steps 6/7/8 need no changes.
    mean_fname     = sprintf('mean_dff_ch%d_%guA.mat', ch, cur);
    mean_fpath     = fullfile(cond_dir, mean_fname);
    mean_dff_movie = mean_movie;
    save(mean_fpath, 'mean_dff_movie', 't_s', 'final_mask', ...
        'n_trials_per_session', '-v7.3');
    fprintf('  Saved mean (n=%d, per-session %s): %s\n', ...
        count, mat2str(n_trials_per_session), mean_fname);

    results(end+1).channel        = ch;        %#ok<AGROW>
    results(end).current_uA      = cur;
    results(end).n_trials        = count;
    results(end).mean_dff_movie  = mean_movie;
    results(end).t_s             = t_s;
    results(end).mean_dff_file   = mean_fpath;
    results(end).trial_dff_files = trial_dff_files;
    results(end).cond_dir        = cond_dir;

end

%% -------------------------
% COLOR MAP
% Each dF/F figure / movie is AUTOSCALED to the min/max of its own in-mask
% dF/F values (no fixed clipping, so strong responses no longer saturate),
% and rendered with a jet colormap.
% -------------------------
cmap = jet(256);
fprintf('\nColor limits: per-figure autoscale to in-mask dF/F min/max  |  colormap: jet\n');

%% -------------------------
% PER-TRIAL DF/F VIDEOS (optional)
% Re-loads each saved trial movie and writes an MP4, autoscaled to that
% trial's own in-mask dF/F min/max (jet colormap).
% -------------------------
if make_trial_videos
    fprintf('\nWriting per-trial dF/F videos...\n');
    for r = 1:numel(results)
        ch  = results(r).channel;
        cur = results(r).current_uA;

        for ti = 1:numel(results(r).trial_dff_files)
            trial_fpath = results(r).trial_dff_files{ti};
            Strial = load(trial_fpath, 'dff_movie');

            [~, trial_base, ~] = fileparts(trial_fpath);
            video_fpath = fullfile(results(r).cond_dir, [trial_base '.mp4']);

            tok = regexp(trial_base, 'trial(\d+)$', 'tokens', 'once');
            if isempty(tok)
                trial_label = trial_base;
            else
                trial_label = sprintf('trial %s', tok{1});
            end

            write_dff_video(video_fpath, Strial.dff_movie, t_s, final_mask, ...
                sprintf('Ch %d | %g uA | %s', ch, cur, trial_label), ...
                data_clim(Strial.dff_movie, final_mask), cmap, video_frame_rate_fps, video_quality, ...
                V1_mask, v1_outline_color);

            fprintf('  Saved trial video: %s.mp4\n', trial_base);
        end
    end
end

%% -------------------------
% FRAME-GRID FIGURES — one figure per (channel, current) condition
% Pre-stim frames shown first, then post-stim.
% -------------------------
n_display = numel(display_frame_idx);
n_cols    = min(7, n_display);
n_rows    = ceil(n_display / n_cols);

for r = 1:numel(results)

    ch  = results(r).channel;
    cur = results(r).current_uA;
    Mv  = results(r).mean_dff_movie;
    cond_clim = data_clim(Mv, final_mask);   % autoscale to this condition's in-mask range

    fig = figure('Color', 'w', ...
        'Name', sprintf('Mean dF/F Ch%d %guA', ch, cur), ...
        'Position', [50 50  min(1800, 240*n_cols)  240*n_rows + 70]);
    tl = tiledlayout(n_rows, n_cols, 'TileSpacing', 'tight', 'Padding', 'compact');

    last_ax = [];
    for di = 1:n_display
        fi = display_frame_idx(di);
        if fi < 1 || fi > T, continue; end

        t_label = display_t_all(di);

        ax = nexttile(tl);
        imagesc(ax, Mv(:,:,fi));
        axis(ax, 'image'); axis(ax, 'off');
        set(ax, 'YDir', 'normal');
        colormap(ax, cmap);
        clim(ax, cond_clim);
        hold(ax, 'on');
        visboundaries(ax, final_mask, 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8);
        if ~isempty(V1_mask)
            visboundaries(ax, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
        end
        title(ax, sprintf('t = %.1f s', t_label), 'FontSize', 8);
        last_ax = ax;
    end

    if ~isempty(last_ax)
        colorbar(last_ax);
    end

    title(tl, sprintf('Mean dF/F  |  Ch %d  |  %g uA  |  n = %d trials', ...
        ch, cur, results(r).n_trials), 'Interpreter', 'none', 'FontSize', 11);

    fig_fname = sprintf('mean_dff_ch%d_%guA_frame_grid.png', ch, cur);
    exportgraphics(fig, fullfile(results(r).cond_dir, fig_fname), 'Resolution', 150);
    close(fig);
    fprintf('Saved figure: %s\n', fig_fname);

    if make_mean_videos
        mean_video_fname = sprintf('mean_dff_ch%d_%guA.mp4', ch, cur);
        write_dff_video(fullfile(results(r).cond_dir, mean_video_fname), Mv, results(r).t_s, final_mask, ...
            sprintf('Ch %d | %g uA | mean (n=%d)', ch, cur, results(r).n_trials), ...
            cond_clim, cmap, video_frame_rate_fps, video_quality, V1_mask, v1_outline_color);
        fprintf('Saved mean video: %s\n', mean_video_fname);
    end

end

%% -------------------------
% SAVE SUMMARY
% -------------------------
session_source_files = {sessions.source_file}; %#ok<NASGU>
summary_file = fullfile(save_dir, 'dff_results_summary.mat');
save(summary_file, 'results', 'final_mask', 't_s', 'baseline_idx', ...
     'Fs', 'pre_sec', 'post_sec', 'n_sessions', 'session_source_files', '-v7.3');

fprintf('\nDone.\nAll outputs in:\n  %s\n', save_dir);
fprintf('Conditions processed: %d\n', numel(results));
fprintf('Sessions combined: %d\n', n_sessions);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function path_out = resolve_file_path(rel_or_abs, dataset_root, kind)
if exist(rel_or_abs, kind_code(kind)) == kind_val(kind)
    path_out = rel_or_abs;
else
    path_out = fullfile(dataset_root, rel_or_abs);
end
assert(exist(path_out, kind_code(kind)) == kind_val(kind), ...
    'Path does not exist:\n  %s', path_out);
end

function c = kind_code(kind)
switch kind
    case 'file', c = 'file';
    case 'dir',  c = 'dir';
    otherwise,   error('Unknown kind: %s', kind);
end
end

function v = kind_val(kind)
switch kind
    case 'file', v = 2;
    case 'dir',  v = 7;
    otherwise,   error('Unknown kind: %s', kind);
end
end

function cl = data_clim(M, mask)
% Autoscale color limits to the min/max of in-mask, finite dF/F values across
% the whole movie, so the colorbar spans the real data range with no clipping.
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

function write_dff_video(video_file, movie_stack, time_axis_sec, final_mask, ...
    title_prefix, clim_range, cmap, frame_rate, quality, V1_mask, v1_color)
if nargin < 10, V1_mask  = []; end
if nargin < 11, v1_color = [0.10 0.85 0.30]; end

mask_color = [0.15 0.15 0.15];

[~, ~, n_frames] = size(movie_stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax  = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);

writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate;
writer.Quality   = quality;
open(writer);

img_handle = image(ax, dff_frame_to_rgb(movie_stack(:, :, 1), final_mask, clim_range, cmap, mask_color));
axis(ax, 'image'); axis(ax, 'off');
set(ax, 'YDir', 'normal');
hold(ax, 'on');
visboundaries(ax, final_mask, 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8);
if ~isempty(V1_mask)
    visboundaries(ax, V1_mask, 'Color', v1_color, 'LineWidth', 1.0);
end

title_handle = title(ax, '', 'Interpreter', 'none');
colormap(ax, cmap);
clim(ax, clim_range);
cb = colorbar(ax, 'eastoutside');
cb.Label.String = '\DeltaF/F';
drawnow;

target_frame_size = [];
for k = 1:n_frames
    set(img_handle, 'CData', dff_frame_to_rgb(movie_stack(:, :, k), final_mask, clim_range, cmap, mask_color));
    set(title_handle, 'String', sprintf('%s | t = %+.2f s', title_prefix, time_axis_sec(k)));

    drawnow;
    frame_rgb = capture_consistent_frame(fig, target_frame_size);
    if isempty(target_frame_size)
        target_frame_size = size(frame_rgb(:, :, 1));
    end
    writeVideo(writer, frame_rgb);
end

close(writer);
close(fig);
end

function rgb = dff_frame_to_rgb(frame, mask, clim_range, cmap, mask_color)
% Maps a single dF/F frame to RGB through cmap/clim_range, then overwrites
% every pixel outside mask with a fixed solid color (regardless of whether
% its underlying value is NaN or just noisy out-of-brain signal).
n = size(cmap, 1);
scaled = (frame - clim_range(1)) / (clim_range(2) - clim_range(1));
scaled(~isfinite(scaled)) = 0;
idx = uint8(min(max(round(scaled * (n - 1)), 0), n - 1));
rgb = ind2rgb(idx, cmap);

for c = 1:3
    chan = rgb(:, :, c);
    chan(~mask) = mask_color(c);
    rgb(:, :, c) = chan;
end
end

function frame_rgb = capture_consistent_frame(fig, target_frame_size)
frame_struct = getframe(fig);
frame_rgb = frame2im(frame_struct);

if isempty(target_frame_size)
    return;
end

if ~isequal(size(frame_rgb, 1), target_frame_size(1)) || ...
        ~isequal(size(frame_rgb, 2), target_frame_size(2))
    frame_rgb = imresize(frame_rgb, target_frame_size);
end
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
frame_idx   = [];
channels    = [];
currents    = [];
trial_index = [];
for i = 1:numel(entries)
    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i     = numel(onset_i);
    frame_idx   = [frame_idx;   onset_i]; %#ok<AGROW>
    channels    = [channels;    repmat(double(entries(i).stim_channel), n_i, 1)]; %#ok<AGROW>
    currents    = [currents;    repmat(double(entries(i).current_uA),   n_i, 1)]; %#ok<AGROW>
    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_index = [trial_index; double(entries(i).trial_index(:))]; %#ok<AGROW>
    else
        trial_index = [trial_index; nan(n_i, 1)]; %#ok<AGROW>
    end
end
end

function V1_mask = load_v1_mask(fpath, expected_size)
V1_mask = [];
try
    D = load(fpath);
    if isfield(D, 'retino_align') && isfield(D.retino_align, 'V1_mask_stim')
        V1_mask = logical(D.retino_align.V1_mask_stim);
    elseif isfield(D, 'day_setup') && isfield(D.day_setup, 'retino_align')
        V1_mask = logical(D.day_setup.retino_align.V1_mask_stim);
    end
    if ~isempty(expected_size) && ~isempty(V1_mask) && ~isequal(size(V1_mask), expected_size)
        warning('V1_mask size does not match brain mask — overlay skipped.');
        V1_mask = [];
    end
catch ME
    warning('Could not load V1 boundary: %s', ME.message);
end
end

function cmap = bwr_colormap(n)
% Blue-white-red diverging colormap, symmetric around zero.
if nargin < 1, n = 256; end
half = floor(n / 2);
rest = n - half;
r    = [linspace(0, 1, half)';  ones(rest, 1)         ];
g    = [linspace(0, 1, half)';  linspace(1, 0, rest)' ];
b    = [ones(half, 1);          linspace(1, 0, rest)'  ];
cmap = [r, g, b];
end
