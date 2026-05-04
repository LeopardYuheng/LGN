%% analyze_v1_baseline_fluctuations.m
% Analyze spontaneous V1 fluorescence fluctuations during a no-stim block.
%
% This script:
%   1. loads a day pointer to recover the day setup and V1 mask
%   2. lets you choose a TIFF directory containing the recording
%   3. restricts analysis to a selected time window (default: first 5 min)
%   3. computes the mean fluorescence inside analysis_mask = final_mask & V1_mask
%   4. plots raw fluorescence and dF/F over time
%   5. optionally chops the recording into pseudo-trials for comparison with real trials

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
day_pointer_file = "C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-04-17\analysis\LGN11_20260417_day_pointer.mat";
baseline_img_dir = "C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-04-17\img";
analysis_time_sec = [0 280];   % analyze only this time range from the TIFF stream

Fs_default = 10;
dff_mode = 'moving_percentile';   % moving_percentile | moving_mean | fixed_percentile
baseline_window_sec = 30;
baseline_percentile = 20;

make_pseudotrials = true;
pseudotrial_window_sec = [-1 3];
pseudotrial_step_sec = [];

make_baseline_video = true;
baseline_video_start_sec = 60;      % relative to analysis_time_sec start
baseline_video_duration_sec = 30;
baseline_video_mode = 'dff';       % raw | dff
baseline_video_frame_rate_fps = 10;
baseline_video_quality = 95;
baseline_video_fixed_clim = [-0.08, 0.08];    % e.g. [-0.02 0.08] for dF/F, [] = auto
baseline_video_colormap = parula(256);
baseline_video_mask_outside = true;
baseline_video_display_pad_px = 10;

save_png = true;
save_mat = true;

%% -------------------------
% LOAD DAY POINTER
% -------------------------
if strlength(day_pointer_file) == 0
    [fn, fp] = uigetfile('*.mat', 'Select day pointer');
    if isequal(fn, 0)
        error('No day pointer selected.');
    end
    day_pointer_file = fullfile(fp, fn);
end

S = load(day_pointer_file);
if isfield(S, 'day_pointer')
    day_pointer = S.day_pointer;
elseif isfield(S, 'C')
    day_pointer = S.C;
else
    error('Selected file must contain "day_pointer" or legacy "C".');
end

assert(isfield(day_pointer, 'meta'), 'day_pointer.meta missing.');
assert(isfield(day_pointer, 'cfg'), 'day_pointer.cfg missing.');

%% -------------------------
% RESOLVE DAY SETUP / BASELINE TIFF DIR
% -------------------------
dataset_root = char(day_pointer.meta.dataset_root);
day_setup_file = resolve_existing_path(day_pointer.meta.day_setup_file_rel, dataset_root, 'file');

if strlength(baseline_img_dir) == 0
    baseline_img_dir = uigetdir(dataset_root, 'Select baseline / no-stim TIFF directory');
    if isequal(baseline_img_dir, 0)
        error('No baseline TIFF directory selected.');
    end
end
baseline_img_dir = char(baseline_img_dir);
assert(exist(baseline_img_dir, 'dir') == 7, 'Selected baseline TIFF directory does not exist.');

fprintf('Resolved day pointer:\n  %s\n', day_pointer_file);
fprintf('Resolved day setup:\n  %s\n', day_setup_file);
fprintf('Resolved baseline TIFF dir:\n  %s\n', baseline_img_dir);

%% -------------------------
% LOAD MASKS
% -------------------------
D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;
video_bbox = bbox_from_mask(V1_mask, baseline_video_display_pad_px);
analysis_mask_crop = crop_to_bbox(analysis_mask, video_bbox);

assert(any(analysis_mask(:)), 'analysis_mask is empty.');
pix_idx = find(analysis_mask);

fprintf('analysis_mask pixels: %d\n', nnz(analysis_mask));

%% -------------------------
% LOAD TIFF FILES
% -------------------------
image_files = [dir(fullfile(baseline_img_dir, '*.tif')); dir(fullfile(baseline_img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFF files found in baseline directory.');

nums = nan(numel(image_files), 1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord] = sort(nums);
image_files = image_files(ord);
nFrames = numel(image_files);

Fs = infer_camera_rate(day_pointer, Fs_default);
t_sec = (0:nFrames-1)' / Fs;

fprintf('Camera rate: %.3f Hz\n', Fs);
fprintf('Baseline frame count: %d\n', nFrames);
fprintf('Baseline duration: %.2f min\n', nFrames / Fs / 60);

frame_keep = true(nFrames, 1);
if ~isempty(analysis_time_sec)
    assert(isnumeric(analysis_time_sec) && numel(analysis_time_sec) == 2 && ...
        all(isfinite(analysis_time_sec)) && analysis_time_sec(1) >= 0 && ...
        analysis_time_sec(2) > analysis_time_sec(1), ...
        'analysis_time_sec must be a finite numeric 1x2 vector [start end] in seconds.');

    full_t_sec = (0:nFrames-1)' / Fs;
    frame_keep = full_t_sec >= analysis_time_sec(1) & full_t_sec < analysis_time_sec(2);
    assert(any(frame_keep), 'No frames fall within analysis_time_sec.');

    image_files = image_files(frame_keep);
    nFrames = numel(image_files);
    t_sec = (0:nFrames-1)' / Fs;

    fprintf('Analyzing only time window: [%.2f %.2f] sec (%.2f min)\n', ...
        analysis_time_sec(1), analysis_time_sec(2), diff(analysis_time_sec) / 60);
    fprintf('Frames kept for analysis: %d\n', nFrames);
end

%% -------------------------
% EXTRACT ROI MEAN TRACE
% -------------------------
raw_trace = nan(nFrames, 1);

for i = 1:nFrames
    img = double(imread(fullfile(baseline_img_dir, image_files(i).name)));
    raw_trace(i) = mean(img(pix_idx), 'omitnan');
end

[dff_trace, F0_trace] = compute_dff_trace(raw_trace, Fs, dff_mode, baseline_window_sec, baseline_percentile);

%% -------------------------
% PSEUDO-TRIAL SETTINGS
% -------------------------
if isempty(pseudotrial_step_sec)
    pseudotrial_step_sec = pseudotrial_window_sec(2) - pseudotrial_window_sec(1);
end

trial_offsets = seconds_to_frame_offsets(pseudotrial_window_sec, Fs);
trial_time_sec = trial_offsets(:) / Fs;
step_frames = max(1, round(pseudotrial_step_sec * Fs));

pseudotrial_onsets = [];
raw_pseudotrials = [];
dff_pseudotrials = [];

if make_pseudotrials
    first_center = 1 - min(trial_offsets);
    last_center = nFrames - max(trial_offsets);
    if first_center <= last_center
        pseudotrial_onsets = first_center:step_frames:last_center;
        [raw_pseudotrials, dff_pseudotrials] = build_pseudotrials(raw_trace, dff_trace, pseudotrial_onsets, trial_offsets);
    end
end

%% -------------------------
% SUMMARY STATS
% -------------------------
dff_valid = dff_trace(isfinite(dff_trace));
summary = struct();
summary.raw_mean = mean(raw_trace, 'omitnan');
summary.raw_std = std(raw_trace, 0, 'omitnan');
summary.dff_mean = mean(dff_valid, 'omitnan');
summary.dff_std = std(dff_valid, 0, 'omitnan');
if isempty(dff_valid)
    summary.dff_prctile_95 = NaN;
    summary.dff_prctile_99 = NaN;
else
    summary.dff_prctile_95 = prctile(dff_valid, 95);
    summary.dff_prctile_99 = prctile(dff_valid, 99);
end

fprintf('\nSpontaneous trace summary:\n');
fprintf('  raw mean                   : %.3f\n', summary.raw_mean);
fprintf('  raw std                    : %.3f\n', summary.raw_std);
fprintf('  dF/F mean                  : %.5f\n', summary.dff_mean);
fprintf('  dF/F std                   : %.5f\n', summary.dff_std);
fprintf('  dF/F 95th percentile       : %.5f\n', summary.dff_prctile_95);
fprintf('  dF/F 99th percentile       : %.5f\n', summary.dff_prctile_99);

if make_pseudotrials
    fprintf('  pseudo-trials exported     : %d\n', size(dff_pseudotrials, 1));
    fprintf('  pseudo-trial window (sec)  : [%.2f %.2f]\n', pseudotrial_window_sec(1), pseudotrial_window_sec(2));
    fprintf('  pseudo-trial step (sec)    : %.2f\n', pseudotrial_step_sec);
end

%% -------------------------
% OUTPUT FOLDER
% -------------------------
[pointer_dir, ~, ~] = fileparts(day_pointer_file);
out_dir = fullfile(pointer_dir, 'baseline_v1_fluctuation_analysis');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% -------------------------
% OPTIONAL VIDEO EXPORT
% -------------------------
if make_baseline_video
    video_start_frame = max(1, 1 + round(baseline_video_start_sec * Fs));
    video_num_frames = max(1, round(baseline_video_duration_sec * Fs));
    video_end_frame = min(nFrames, video_start_frame + video_num_frames - 1);
    video_frame_idx = video_start_frame:video_end_frame;

    assert(~isempty(video_frame_idx), 'No frames selected for baseline video.');

    video_stack = load_masked_frame_stack( ...
        baseline_img_dir, image_files, video_frame_idx, pix_idx, size(analysis_mask));
    video_stack = crop_movie_stack(video_stack, video_bbox);

    switch lower(baseline_video_mode)
        case 'raw'
            video_stack_to_write = video_stack;
        case 'dff'
            video_stack_to_write = convert_movie_stack_full(video_stack, baseline_idx_for_video(video_stack, Fs), 'dff');
        otherwise
            error('Unknown baseline_video_mode "%s". Use "raw" or "dff".', baseline_video_mode);
    end

    if baseline_video_mask_outside
        for k = 1:size(video_stack_to_write, 3)
            frame_k = video_stack_to_write(:, :, k);
            frame_k(~analysis_mask_crop) = NaN;
            video_stack_to_write(:, :, k) = frame_k;
        end
    end

    if isempty(baseline_video_fixed_clim)
        video_clim = compute_movie_clim(video_stack_to_write, baseline_video_mode);
    else
        assert(isnumeric(baseline_video_fixed_clim) && numel(baseline_video_fixed_clim) == 2 && ...
            all(isfinite(baseline_video_fixed_clim)) && ...
            baseline_video_fixed_clim(1) < baseline_video_fixed_clim(2), ...
            'baseline_video_fixed_clim must be [min max].');
        video_clim = double(baseline_video_fixed_clim(:))';
    end

    video_time_sec = ((video_frame_idx - video_frame_idx(1))' / Fs) + baseline_video_start_sec;
    video_file = fullfile(out_dir, sprintf('baseline_fluctuation_%s_%ds_to_%ds.mp4', ...
        lower(baseline_video_mode), round(video_time_sec(1)), round(video_time_sec(end))));

    write_baseline_video(video_file, video_stack_to_write, video_time_sec, analysis_mask_crop, ...
        video_clim, baseline_video_colormap, baseline_video_frame_rate_fps, ...
        baseline_video_quality, baseline_video_mode);

    fprintf('  baseline video exported    : %s\n', video_file);
end

%% -------------------------
% PLOT 1: FULL TRACE
% -------------------------
fig1 = figure('Color', 'w', 'Name', 'Baseline V1 traces');
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plot(ax1, t_sec, raw_trace, 'k', 'LineWidth', 1);
ylabel(ax1, 'Raw F');
title(ax1, 'Masked V1 mean fluorescence over time');
grid(ax1, 'on');

ax2 = nexttile;
plot(ax2, t_sec, F0_trace, 'b', 'LineWidth', 1);
ylabel(ax2, 'F0');
title(ax2, sprintf('Baseline estimate | mode=%s | window=%.1f s', dff_mode, baseline_window_sec));
grid(ax2, 'on');

ax3 = nexttile;
plot(ax3, t_sec, dff_trace, 'm', 'LineWidth', 1);
yline(ax3, summary.dff_prctile_95, '--', '95th pct', 'Color', [0.2 0.5 0.2], 'LabelHorizontalAlignment', 'left');
yline(ax3, summary.dff_prctile_99, '--', '99th pct', 'Color', [0.7 0.2 0.2], 'LabelHorizontalAlignment', 'left');
xlabel(ax3, 'Time (s)');
ylabel(ax3, 'dF/F');
title(ax3, 'Spontaneous dF/F over time');
grid(ax3, 'on');

linkaxes([ax1 ax2 ax3], 'x');

if save_png
    saveas(fig1, fullfile(out_dir, 'baseline_v1_trace_over_time.png'));
end

%% -------------------------
% PLOT 2: DFF HISTOGRAM
% -------------------------
fig2 = figure('Color', 'w', 'Name', 'Baseline V1 dF/F histogram');
histogram(dff_valid, 100, 'FaceColor', [0.7 0.2 0.7], 'EdgeColor', 'none');
xlabel('dF/F');
ylabel('Count');
title('Distribution of spontaneous V1 dF/F');
grid on;

if save_png
    saveas(fig2, fullfile(out_dir, 'baseline_v1_dff_histogram.png'));
end

%% -------------------------
% PLOT 3: PSEUDO-TRIALS
% -------------------------
if make_pseudotrials && ~isempty(dff_pseudotrials)
    fig3 = figure('Color', 'w', 'Name', 'Baseline pseudo-trials');
    tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    axp1 = nexttile;
    plot(axp1, trial_time_sec, raw_pseudotrials', 'Color', [0.7 0.7 0.7]);
    hold(axp1, 'on');
    plot(axp1, trial_time_sec, mean(raw_pseudotrials, 1, 'omitnan'), 'k', 'LineWidth', 2);
    xline(axp1, 0, 'k--');
    ylabel(axp1, 'Raw F');
    title(axp1, sprintf('Pseudo-trial raw traces | n=%d', size(raw_pseudotrials, 1)));
    grid(axp1, 'on');

    axp2 = nexttile;
    plot(axp2, trial_time_sec, dff_pseudotrials', 'Color', [0.85 0.7 0.85]);
    hold(axp2, 'on');
    plot(axp2, trial_time_sec, mean(dff_pseudotrials, 1, 'omitnan'), 'm', 'LineWidth', 2);
    xline(axp2, 0, 'k--');
    xlabel(axp2, 'Pseudo-trial time (s)');
    ylabel(axp2, 'dF/F');
    title(axp2, 'Pseudo-trial spontaneous dF/F traces');
    grid(axp2, 'on');

    if save_png
        saveas(fig3, fullfile(out_dir, 'baseline_v1_pseudotrials.png'));
    end
end

%% -------------------------
% SAVE OUTPUT
% -------------------------
if save_mat
    save(fullfile(out_dir, 'baseline_v1_fluctuation_summary.mat'), ...
        'raw_trace', 'dff_trace', 'F0_trace', 't_sec', 'Fs', ...
        'analysis_mask', 'final_mask', 'V1_mask', 'pix_idx', ...
        'analysis_time_sec', 'frame_keep', ...
        'make_pseudotrials', 'pseudotrial_window_sec', 'pseudotrial_step_sec', ...
        'trial_time_sec', 'pseudotrial_onsets', 'raw_pseudotrials', 'dff_pseudotrials', ...
        'dff_mode', 'baseline_window_sec', 'baseline_percentile', 'summary', '-v7.3');
end

fprintf('\nSaved baseline fluctuation outputs to:\n  %s\n', out_dir);

%% -------------------------
% LOCAL FUNCTIONS
% -------------------------
function p = resolve_existing_path(path_like, dataset_root, kind)
path_like = char(path_like);
dataset_root = char(dataset_root);

if strcmpi(kind, 'file')
    exists_here = exist(path_like, 'file') == 2;
else
    exists_here = exist(path_like, 'dir') == 7;
end
if exists_here
    p = path_like;
    return;
end

candidate = fullfile(dataset_root, path_like);
if strcmpi(kind, 'file')
    exists_there = exist(candidate, 'file') == 2;
else
    exists_there = exist(candidate, 'dir') == 7;
end
if exists_there
    p = candidate;
    return;
end

error('Could not resolve %s path:\n  %s', kind, path_like);
end

function Fs = infer_camera_rate(day_pointer, Fs_default)
if isfield(day_pointer.meta, 'camera_rate_hz') && ~isempty(day_pointer.meta.camera_rate_hz)
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq') && ~isempty(day_pointer.meta.Freq)
    Fs = double(day_pointer.meta.Freq);
else
    Fs = Fs_default;
end
end

function offsets = seconds_to_frame_offsets(window_sec, Fs)
start_idx = ceil(window_sec(1) * Fs);
end_idx = floor(window_sec(2) * Fs);
offsets = start_idx:end_idx;
end

function [dff_trace, F0_trace] = compute_dff_trace(raw_trace, Fs, dff_mode, baseline_window_sec, baseline_percentile)
window_frames = max(3, round(baseline_window_sec * Fs));

switch lower(dff_mode)
    case 'moving_percentile'
        F0_trace = mov_prctile_1d(raw_trace, baseline_percentile, window_frames);
    case 'moving_mean'
        F0_trace = movmean(raw_trace, window_frames, 'omitnan');
    case 'fixed_percentile'
        F0_trace = repmat(prctile(raw_trace(isfinite(raw_trace)), baseline_percentile), size(raw_trace));
    otherwise
        error('Unknown dff_mode "%s".', dff_mode);
end

valid = isfinite(raw_trace) & isfinite(F0_trace) & F0_trace ~= 0;
dff_trace = nan(size(raw_trace));
dff_trace(valid) = (raw_trace(valid) - F0_trace(valid)) ./ F0_trace(valid);
end

function y = mov_prctile_1d(x, p, window_frames)
n = numel(x);
y = nan(size(x));
half_window = floor(window_frames / 2);

for i = 1:n
    i0 = max(1, i - half_window);
    i1 = min(n, i + half_window);
    xi = x(i0:i1);
    xi = xi(isfinite(xi));
    if ~isempty(xi)
        y(i) = prctile(xi, p);
    end
end
end

function [raw_trials, dff_trials] = build_pseudotrials(raw_trace, dff_trace, onset_frames, offsets)
n_trials = numel(onset_frames);
n_t = numel(offsets);
raw_trials = nan(n_trials, n_t);
dff_trials = nan(n_trials, n_t);

for i = 1:n_trials
    idx = onset_frames(i) + offsets;
    raw_trials(i, :) = raw_trace(idx);
    dff_trials(i, :) = dff_trace(idx);
end
end

function bbox = bbox_from_mask(mask, pad)
[yy, xx] = find(mask);
assert(~isempty(yy), 'Mask is empty.');
y0 = max(1, min(yy) - pad);
y1 = min(size(mask, 1), max(yy) + pad);
x0 = max(1, min(xx) - pad);
x1 = min(size(mask, 2), max(xx) + pad);
bbox = [y0 y1 x0 x1];
end

function out = crop_to_bbox(arr, bbox)
out = arr(bbox(1):bbox(2), bbox(3):bbox(4));
end

function stack = crop_movie_stack(stack, bbox)
stack = stack(bbox(1):bbox(2), bbox(3):bbox(4), :);
end

function stack = load_masked_frame_stack(img_dir, image_files, frame_indices, pix_idx, frame_size)
stack = nan(frame_size(1), frame_size(2), numel(frame_indices), 'single');

for k = 1:numel(frame_indices)
    img = im2single(imread(fullfile(img_dir, image_files(frame_indices(k)).name)));
    frame = nan(frame_size, 'single');
    frame(pix_idx) = img(pix_idx);
    stack(:, :, k) = frame;
end
end

function baseline_idx = baseline_idx_for_video(movie_stack, Fs)
n_frames = size(movie_stack, 3);
baseline_frames = max(1, round(min(1, n_frames / Fs) * Fs));
baseline_idx = false(1, n_frames);
baseline_idx(1:baseline_frames) = true;
end

function movie_stack = convert_movie_stack_full(movie_stack, baseline_idx, video_mode)
switch lower(video_mode)
    case 'raw'
        return;
    case 'dff'
        baseline_img = mean(movie_stack(:, :, baseline_idx), 3, 'omitnan');
        movie_stack = (movie_stack - baseline_img) ./ baseline_img;
    otherwise
        error('Unknown video_mode "%s". Use "raw" or "dff".', video_mode);
end
end

function clim = compute_movie_clim(movie_stack, video_mode)
vals = movie_stack(isfinite(movie_stack));
if isempty(vals)
    clim = [-1 1];
    return;
end

switch lower(video_mode)
    case 'raw'
        q = quantile(vals, [0.02 0.98]);
        if ~all(isfinite(q)) || q(1) == q(2)
            clim = [min(vals) max(vals)];
        else
            clim = q;
        end
    case 'dff'
        q = quantile(vals, [0.02 0.98]);
        m = max(abs(q));
        if ~isfinite(m) || m == 0
            m = 1;
        end
        clim = [-m m];
    otherwise
        error('Unknown video_mode "%s". Use "raw" or "dff".', video_mode);
end

if ~all(isfinite(clim)) || clim(1) == clim(2)
    clim = [0 1];
end
end

function write_baseline_video(video_file, movie_stack, time_axis_sec, analysis_mask, ...
    clim, cmap, frame_rate, quality, video_mode)
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 720 680]);
ax = axes(fig, 'Position', [0.06 0.08 0.78 0.84]);

writer = VideoWriter(video_file, 'MPEG-4');
writer.FrameRate = frame_rate;
writer.Quality = quality;
open(writer);

img_handle = imagesc(ax, movie_stack(:, :, 1));
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'normal');
colormap(ax, cmap);
caxis(ax, clim);
hold(ax, 'on');
visboundaries(ax, analysis_mask, 'Color', 'w', 'LineWidth', 0.8);
title_handle = title(ax, '', 'Interpreter', 'none');
cb = colorbar(ax, 'eastoutside');
cb.Label.String = colorbar_label_for_mode(video_mode);
drawnow;

target_frame_size = [];
for k = 1:size(movie_stack, 3)
    set(img_handle, 'CData', movie_stack(:, :, k));
    set(title_handle, 'String', sprintf('Baseline %s | t=%0.2f s', upper(video_mode), time_axis_sec(k)));
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

function label = colorbar_label_for_mode(video_mode)
switch lower(video_mode)
    case 'raw'
        label = 'Raw fluorescence';
    case 'dff'
        label = '\DeltaF/F';
    otherwise
        label = 'Signal';
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
