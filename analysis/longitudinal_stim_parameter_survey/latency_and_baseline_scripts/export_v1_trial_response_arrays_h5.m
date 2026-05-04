%% export_v1_trial_response_arrays_h5.m
% Export trial-wise V1 response maps in a compact HDF5 file.
%
% Trial maps are computed the same way as in
% compare_pixelwise_activation_across_sessions.m:
%   1. Use the full trial window from day_pointer.cfg
%   2. Baseline is all frames with t < 0
%   3. Response window is [0 1] sec
%   4. dF/F = (response - baseline) ./ baseline
%
% Output datasets:
%   /channel              [n_trials]
%   /current_uA           [n_trials]
%   /v1_response_values   [n_trials, n_v1_pixels]
%       Only the 4x-binned cropped V1 pixels, ordered left-to-right within each row.
%   /v1_response_grid     [n_trials, H, W]
%       Same trial map in 4x-binned cropped-grid form.
%   /v1_mask              [H, W]
%   /final_mask           [H, W]

close all; clc;

%% -------------------------
% USER OPTIONS
% -------------------------
day_pointer_file = "C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-03-29\analysis\LGN11_20260328_day_pointer.mat";

response_sec = [0 1.0];
display_pad_px = 10;
mask_outside_final_mask = true;
drop_out_of_bounds_trials = true;
max_trials_to_export = Inf;
bin_factor = 4;

%% -------------------------
% LOAD DAY POINTER
% -------------------------
if isempty(day_pointer_file)
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
binned_v1_mask = bin_2d_nanmean(single(v1_crop), bin_factor) > 0;
binned_final_mask = bin_2d_nanmean(single(final_crop), bin_factor) > 0;

fprintf('\nPixel counts in cropped V1 bbox\n');
fprintf('  cropped V1 pixels: %d\n', nnz(v1_crop));
fprintf('  cropped final-mask pixels: %d\n', nnz(final_crop));
fprintf('  4x-binned V1 pixels: %d\n', nnz(binned_v1_mask));
fprintf('  4x-binned final-mask pixels: %d\n', nnz(binned_final_mask));

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
pre_sec = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);
full_win = -pre_frames:post_frames;
t_s = full_win / Fs;

baseline_idx = t_s < 0;
response_idx = t_s > response_sec(1) & t_s <= response_sec(2);

assert(any(baseline_idx), 'Baseline window selected zero frames.');
assert(any(response_idx), 'Response window selected zero frames.');

fprintf('\nCamera rate: %.3f Hz\n', Fs);
fprintf('TIFF frame count: %d\n', nFrames);
fprintf('Response window: [%.3f %.3f] sec\n', response_sec(1), response_sec(2));

%% -------------------------
% UNPACK TRIAL ENTRIES
% -------------------------
[frame_idx, channels, currents] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents);
if drop_out_of_bounds_trials
    valid = valid & frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);
end

frame_idx = frame_idx(valid);
channels = channels(valid);
currents = currents(valid);

n_trials = numel(frame_idx);
assert(n_trials > 0, 'No valid trials remain after filtering.');

if isfinite(max_trials_to_export) && max_trials_to_export > 0 && n_trials > max_trials_to_export
    keep_idx = 1:max_trials_to_export;
    frame_idx = frame_idx(keep_idx);
    channels = channels(keep_idx);
    currents = currents(keep_idx);
    n_trials = numel(frame_idx);
end

fprintf('Valid trials to export: %d\n', n_trials);

%% -------------------------
% BUILD TRIAL MAPS
% -------------------------
[trial_maps, trial_values] = build_trial_exports( ...
    frame_idx, img_dir, image_files, full_win, baseline_idx, response_idx, ...
    bbox, v1_crop, final_crop, binned_v1_mask, binned_final_mask, ...
    mask_outside_final_mask, bin_factor);

%% -------------------------
% OUTPUT PATH
% -------------------------
[pointer_dir, pointer_base, ~] = fileparts(day_pointer_file);
out_dir = fullfile(pointer_dir, 'python_export_v1_trial_response_arrays');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

h5_file = fullfile(out_dir, sprintf('%s_v1_trial_response_arrays.h5', pointer_base));
delete_if_present(h5_file);

%% -------------------------
% WRITE HDF5 FILE
% -------------------------
write_h5_dataset(h5_file, '/channel', int32(channels(:)));
write_h5_dataset(h5_file, '/current_uA', single(currents(:)));
write_h5_dataset(h5_file, '/v1_response_values', single(trial_values));
write_h5_dataset(h5_file, '/v1_response_grid', single(trial_maps));
write_h5_dataset(h5_file, '/v1_mask', uint8(binned_v1_mask));
write_h5_dataset(h5_file, '/final_mask', uint8(binned_final_mask));

%% -------------------------
% SUMMARY
% -------------------------
fprintf('\nExport complete\n');
fprintf('  HDF5: %s\n', h5_file);

fprintf('\nSaved array shapes (Python order for grid: n_trials, rows, cols)\n');
fprintf('  channel: [%d]\n', numel(channels));
fprintf('  current_uA: [%d]\n', numel(currents));
fprintf('  v1_response_values: [%d, %d]\n', size(trial_values, 1), size(trial_values, 2));
fprintf('  v1_response_grid: [%d, %d, %d]\n', size(trial_maps, 1), size(trial_maps, 2), size(trial_maps, 3));
fprintf('  v1_mask: [%d, %d]\n', size(binned_v1_mask, 1), size(binned_v1_mask, 2));
fprintf('  final_mask: [%d, %d]\n', size(binned_final_mask, 1), size(binned_final_mask, 2));

fprintf('\nExample Python usage:\n');
fprintf('  import h5py\n');
fprintf('  f = h5py.File(r''%s'', ''r'')\n', h5_file);
fprintf('  channels = f[''/channel''][:]\n');
fprintf('  currents = f[''/current_uA''][:]\n');
fprintf('  v1_values = f[''/v1_response_values''][:]   # left-to-right within each row\n');
fprintf('  v1_grid = f[''/v1_response_grid''][:]       # cropped V1 grid\n');

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

function [frame_idx, channels, currents] = unpack_day_pointer_entries(entries)
frame_idx = [];
channels = [];
currents = [];

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

function [trial_maps, trial_values] = build_trial_exports(frame_idx, img_dir, image_files, ...
    full_win, baseline_idx, response_idx, bbox, v1_crop, final_crop, ...
    binned_v1_mask, binned_final_mask, mask_outside_final_mask, bin_factor)

n = numel(frame_idx);
h = size(binned_v1_mask, 1);
w = size(binned_v1_mask, 2);
n_v1_pixels = nnz(binned_v1_mask);

trial_maps = nan(n, h, w, 'single');
trial_values = nan(n, n_v1_pixels, 'single');

for i = 1:n
    stack = load_frame_stack(img_dir, image_files, frame_idx(i) + full_win, bbox);

    baseline = mean(stack(:, :, baseline_idx), 3, 'omitnan');
    response = mean(stack(:, :, response_idx), 3, 'omitnan');
    dff_map = (response - baseline) ./ baseline;

    grid_map = bin_2d_nanmean(dff_map, bin_factor);
    value_map = grid_map;

    value_map(~binned_v1_mask) = NaN;

    if mask_outside_final_mask
        value_map(~binned_final_mask) = NaN;
    end

    trial_maps(i, :, :) = single(grid_map);
    trial_values(i, :) = single(extract_masked_values_row_major(value_map, binned_v1_mask));


    if mod(i, 50) == 0 || i == n
        fprintf('Built trial map %d / %d\n', i, n);
    end
end

end

function binned = bin_2d_nanmean(img, factor)
[h, w] = size(img);
h2 = floor(h / factor);
w2 = floor(w / factor);
cropped = img(1:(h2 * factor), 1:(w2 * factor));
reshaped = reshape(cropped, factor, h2, factor, w2);
reshaped = permute(reshaped, [2 4 1 3]);
binned = mean(reshaped, [3 4], 'omitnan');
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

function values = extract_masked_values_row_major(map_2d, mask_2d)
map_row_major = reshape(map_2d.', 1, []);
mask_row_major = reshape(mask_2d.', 1, []);
values = map_row_major(mask_row_major);
end

function delete_if_present(file_path)
if exist(file_path, 'file') == 2
    delete(file_path);
end
end

function write_h5_dataset(h5_file, dataset_name, data)
dims = size(data);
if isscalar(data)
    dims = [1 1];
end

chunk = choose_chunk_size(data);

if isempty(chunk)
    h5create(h5_file, dataset_name, dims, 'Datatype', class(data));
else
    h5create(h5_file, dataset_name, dims, 'Datatype', class(data), ...
        'ChunkSize', chunk, 'Deflate', 4);
end
h5write(h5_file, dataset_name, data);
end

function chunk = choose_chunk_size(data)
dims = size(data);
if isscalar(data)
    chunk = [];
    return;
end

if ndims(data) == 2 && min(dims) == 1
    chunk = dims;
    return;
end

if ndims(data) == 2
    chunk = min(dims, [min(256, dims(1)), min(256, dims(2))]);
    return;
end

if ndims(data) == 3
    chunk = [1, min(64, dims(2)), min(64, dims(3))];
    return;
end

chunk = [];
end
