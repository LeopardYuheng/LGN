%% make_v1_trial_response_videos.m
% Make per-trial V1 response videos from a day pointer.
%
% For each valid trial matching the requested stimulation currents, this script:
%   1. loads TIFF frames from -1 to +3 sec around stimulation
%   2. optionally computes per-frame dF/F using the 1 sec prestimulus baseline
%   3. crops to the V1 bounding box
%   4. overlays the V1 and final-mask boundaries
%   5. saves one MP4 video per trial

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
day_pointer_file = "";

target_channels = [96];      % [] = all channels, or e.g. 16
target_currents_uA = [4];   % [] = all currents, or e.g. 7
video_window_sec = [-1 3];
baseline_sec = [-1 0];
video_mode = 'dff';  % raw | dff

display_pad_px = 10;
mask_outside_display = false;
overlay_V1_boundary = true;
overlay_final_mask_boundary = true;

output_frame_rate_fps = 10;
video_quality = 95;
colormap_name = parula(256);
use_global_clim = false;
global_clim = [-0.06 0.06];
fixed_clim = [-0.08, 0.08];  % e.g. [-0.05 0.10]; applies to all videos when non-empty

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
assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
    'day_pointer.entries missing or empty.');

%% -------------------------
% RESOLVE INPUT PATHS
% -------------------------
dataset_root = day_pointer.meta.dataset_root;
day_setup_file = resolve_existing_path(day_pointer.meta.day_setup_file_rel, dataset_root, 'file');
img_dir = resolve_existing_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');

fprintf('Resolved day pointer:\n  %s\n', day_pointer_file);
fprintf('Resolved day setup:\n  %s\n', day_setup_file);
fprintf('Resolved image dir:\n  %s\n', img_dir);

%% -------------------------
% LOAD DAY SETUP / MASKS
% -------------------------
D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);

assert(any(V1_mask(:)), 'V1 mask is empty.');

bbox = bbox_from_mask(V1_mask, display_pad_px);
v1_crop = crop_to_bbox(V1_mask, bbox);
final_crop = crop_to_bbox(final_mask, bbox);

%% -------------------------
% LOAD TIFF FILE LIST
% -------------------------
image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFF files found in image dir.');

nums = nan(numel(image_files), 1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord] = sort(nums);
image_files = image_files(ord);
nFrames = numel(image_files);

%% -------------------------
% CAMERA RATE / WINDOWS
% -------------------------
Fs = infer_camera_rate(day_pointer);
video_offsets = seconds_to_frame_offsets(video_window_sec, Fs);
time_axis_sec = video_offsets / Fs;
baseline_idx = time_axis_sec >= baseline_sec(1) & time_axis_sec < baseline_sec(2);
assert(any(baseline_idx), 'Baseline window selected zero frames.');

max_backward = abs(min(video_offsets));
max_forward = max(video_offsets);

fprintf('\nCamera rate: %.3f Hz\n', Fs);
fprintf('TIFF frame count: %d\n', nFrames);
fprintf('Video window: [%.2f %.2f] sec\n', video_window_sec(1), video_window_sec(2));
fprintf('Baseline window: [%.2f %.2f] sec\n', baseline_sec(1), baseline_sec(2));

%% -------------------------
% UNPACK TRIAL ENTRIES
% -------------------------
[frame_idx, channels, currents, trial_ids] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
    frame_idx > max_backward & frame_idx <= (nFrames - max_forward);
if ~isempty(target_channels)
    valid = valid & ismember(channels, target_channels);
end
if ~isempty(target_currents_uA)
    valid = valid & ismember(currents, target_currents_uA);
end

frame_idx = frame_idx(valid);
channels = channels(valid);
currents = currents(valid);
trial_ids = trial_ids(valid);

n_trials = numel(frame_idx);
assert(n_trials > 0, 'No valid trials remain after filtering.');

fprintf('Trials selected for video export: %d\n', n_trials);
if ~isempty(target_channels)
    fprintf('Target channels: %s\n', mat2str(target_channels));
end
if ~isempty(target_currents_uA)
    fprintf('Target currents (uA): %s\n', mat2str(target_currents_uA));
end

%% -------------------------
% OUTPUT PATH
% -------------------------
[pointer_dir, pointer_base, ~] = fileparts(day_pointer_file);
out_dir = fullfile(pointer_dir, 'v1_trial_response_videos');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% -------------------------
% BUILD VIDEOS
% -------------------------
for i = 1:n_trials
    frame_indices = frame_idx(i) + video_offsets;
    movie_stack = load_frame_stack(img_dir, image_files, frame_indices, bbox);
    movie_stack = convert_movie_stack(movie_stack, baseline_idx, video_mode);
    movie_stack = apply_display_mask(movie_stack, final_crop, mask_outside_display);

    if ~isempty(fixed_clim)
        assert(isnumeric(fixed_clim) && numel(fixed_clim) == 2 && all(isfinite(fixed_clim)) && ...
            fixed_clim(1) < fixed_clim(2), ...
            'fixed_clim must be a finite numeric 1x2 vector [min max].');
        clim = double(fixed_clim(:))';
    elseif use_global_clim && strcmpi(video_mode, 'dff')
        clim = global_clim;
    else
        clim = compute_movie_clim(movie_stack, video_mode);
    end

    if isnan(trial_ids(i))
        trial_label = sprintf('row_%04d', i);
    else
        trial_label = sprintf('trial_%04d', round(trial_ids(i)));
    end

    video_file = fullfile(out_dir, sprintf('%s_ch_%d_current_%g_uA_%s.mp4', ...
        pointer_base, channels(i), currents(i), trial_label));

    write_trial_video(video_file, movie_stack, time_axis_sec, v1_crop, final_crop, ...
        channels(i), currents(i), trial_ids(i), overlay_V1_boundary, ...
        overlay_final_mask_boundary, clim, colormap_name, output_frame_rate_fps, ...
        video_quality, video_mode);

    fprintf('Saved video %d / %d\n  %s\n', i, n_trials, video_file);
end

fprintf('\nDone.\nSaved videos to:\n  %s\n', out_dir);

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

function Fs = infer_camera_rate(day_pointer)
if isfield(day_pointer.meta, 'camera_rate_hz') && ~isempty(day_pointer.meta.camera_rate_hz)
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq') && ~isempty(day_pointer.meta.Freq)
    Fs = double(day_pointer.meta.Freq);
else
    Fs = 10;
end
end

function offsets = seconds_to_frame_offsets(window_sec, Fs)
start_idx = ceil(window_sec(1) * Fs);
end_idx = floor(window_sec(2) * Fs);
offsets = start_idx:end_idx;
end

function [frame_idx, channels, currents, trial_ids] = unpack_day_pointer_entries(entries)
frame_idx = [];
channels = [];
currents = [];
trial_ids = [];

for i = 1:numel(entries)
    assert(isfield(entries(i), 'trial_onset_frame_idx'), ...
        'Entry %d missing trial_onset_frame_idx.', i);
    assert(isfield(entries(i), 'stim_channel'), ...
        'Entry %d missing stim_channel.', i);
    assert(isfield(entries(i), 'current_uA'), ...
        'Entry %d missing current_uA.', i);

    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i = numel(onset_i);
    stim_channel_i = scalarize_numeric(entries(i).stim_channel, 'stim_channel');
    current_uA_i = scalarize_numeric(entries(i).current_uA, 'current_uA');

    frame_idx = [frame_idx; onset_i]; %#ok<AGROW>
    channels = [channels; repmat(stim_channel_i, n_i, 1)]; %#ok<AGROW>
    currents = [currents; repmat(current_uA_i, n_i, 1)]; %#ok<AGROW>

    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_ids = [trial_ids; double(entries(i).trial_index(:))]; %#ok<AGROW>
    else
        trial_ids = [trial_ids; nan(n_i, 1)]; %#ok<AGROW>
    end
end
end

function x = scalarize_numeric(value, field_name)
if iscell(value)
    assert(numel(value) == 1, 'Field %s must be scalar-like.', field_name);
    value = value{1};
end

if isnumeric(value) || islogical(value)
    assert(numel(value) == 1, 'Field %s must be scalar-like.', field_name);
    x = double(value);
    return;
end

error('Field %s must be numeric/logical scalar-like data.', field_name);
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

function stack = load_frame_stack(img_dir, image_files, frame_indices, bbox)
for k = 1:numel(frame_indices)
    idx = frame_indices(k);
    assert(idx >= 1 && idx <= numel(image_files), 'Frame index out of bounds.');
    frame = im2single(imread(fullfile(img_dir, image_files(idx).name)));
    frame = crop_to_bbox(frame, bbox);
    if k == 1
        [h, w] = size(frame);
        stack = zeros(h, w, numel(frame_indices), 'single');
    end
    stack(:, :, k) = frame;
end
end

function movie_stack = convert_movie_stack(movie_stack, baseline_idx, video_mode)
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

function movie_stack = apply_display_mask(movie_stack, display_mask, mask_outside_display)
if ~mask_outside_display
    return;
end

for k = 1:size(movie_stack, 3)
    frame_k = movie_stack(:, :, k);
    frame_k(~display_mask) = NaN;
    movie_stack(:, :, k) = frame_k;
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

function write_trial_video(video_file, movie_stack, time_axis_sec, v1_mask, final_mask, ...
    channel_i, current_i, trial_id_i, overlay_V1_boundary, overlay_final_mask_boundary, ...
    clim, cmap, frame_rate, quality, video_mode)

[~, ~, n_frames] = size(movie_stack);
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 700 650]);
ax = axes(fig, 'Position', [0.08 0.08 0.72 0.84]);

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

if overlay_V1_boundary
    visboundaries(ax, v1_mask, 'Color', 'w', 'LineWidth', 1.0);
end
if overlay_final_mask_boundary
    visboundaries(ax, final_mask, 'Color', 'y', 'LineWidth', 0.9);
end

title_handle = title(ax, '', 'Interpreter', 'none');
cb = colorbar(ax, 'eastoutside');
cb.Label.String = colorbar_label_for_mode(video_mode);
drawnow;

target_frame_size = [];

for k = 1:n_frames
    if isnan(trial_id_i)
        trial_text = 'trial=NA';
    else
        trial_text = sprintf('trial=%d', round(trial_id_i));
    end

    set(img_handle, 'CData', movie_stack(:, :, k));
    set(title_handle, 'String', sprintf('%s | ch=%d | current=%g uA | t=%+.2f s', ...
        trial_text, channel_i, current_i, time_axis_sec(k)));

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
