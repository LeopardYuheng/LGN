%% v1_compression_demo_matlab.m
% Count pixels inside the V1 mask and visualize simple spatial compression
% on one evoked map using 2x and 4x binning.

close all; clc;

%% -------------------------
% USER OPTIONS
% -------------------------
day_pointer_file = ''; % leave empty to choose with uigetfile

% Set these after reviewing the printed summary table below.
TARGET_CHANNEL = [114];
TARGET_CURRENT_UA = [ 7];
TARGET_TRIAL_INDEX_WITHIN_CONDITION = 1; % 1-based index within condition

BASELINE_SEC = [-1.0 0.0];
RESPONSE_SEC = [0.0 1.0];

DISPLAY_PAD_PX = 10;
MASK_OCCUPANCY_THRESHOLD = 0.0; % 0 = keep any bin touched by the mask

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
% LOAD DAY SETUP
% -------------------------
D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;

assert(any(V1_mask(:)), 'V1 mask is empty.');

[H, W] = size(V1_mask);
bbox = bbox_from_mask(V1_mask, DISPLAY_PAD_PX);

fprintf('\nPixel counts\n');
fprintf('  V1_mask_stim pixels: %d\n', nnz(V1_mask));
fprintf('  final_mask pixels: %d\n', nnz(final_mask));
fprintf('  analysis_mask = final_mask & V1_mask pixels: %d\n', nnz(analysis_mask));

%% -------------------------
% SHOW MASKS
% -------------------------
figure('Color', 'w', 'Name', 'V1 and analysis masks');
tiledlayout(1,3, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imagesc(crop_to_bbox(V1_mask, bbox)); axis image off;
title('V1 mask');
colormap(gca, gray);

nexttile;
imagesc(crop_to_bbox(final_mask, bbox)); axis image off;
title('Final mask');
colormap(gca, gray);

nexttile;
imagesc(crop_to_bbox(analysis_mask, bbox)); axis image off;
title('Analysis mask');
colormap(gca, gray);

%% -------------------------
% LOAD TIFF FILES
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
% CAMERA RATE / OFFSETS
% -------------------------
% Fs = infer_camera_rate(day_pointer);
Fs = 10;
baseline_offsets = frame_window_to_offsets(BASELINE_SEC, Fs);
response_offsets = frame_window_to_offsets(RESPONSE_SEC, Fs);

assert(~isempty(baseline_offsets), 'Baseline window selected zero frames.');
assert(~isempty(response_offsets), 'Response window selected zero frames.');

max_backward = abs(min([baseline_offsets(:); response_offsets(:)]));
max_forward = max([baseline_offsets(:); response_offsets(:)]);

fprintf('\nCamera rate: %.3f Hz\n', Fs);
fprintf('TIFF frame count: %d\n', nFrames);

%% -------------------------
% UNPACK ENTRIES
% -------------------------
[frame_idx, channels, currents, trial_ids] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > max_backward & frame_idx <= (nFrames - max_forward);

frame_idx = frame_idx(valid);
channels = channels(valid);
currents = currents(valid);
trial_ids = trial_ids(valid);

assert(~isempty(frame_idx), 'No valid trials remain after frame-window filtering.');

%% -------------------------
% LIST AVAILABLE CONDITIONS
% -------------------------
[G, channel_vals, current_vals] = findgroups(channels, currents);
trial_counts = splitapply(@numel, frame_idx, G);

summary_table = table(channel_vals, current_vals, trial_counts, ...
    'VariableNames', {'channel', 'current_uA', 'n_trials'});
summary_table = sortrows(summary_table, {'channel', 'current_uA'});

fprintf('\nAvailable channel/current conditions:\n');
disp(summary_table);

if isempty(TARGET_CHANNEL) || isempty(TARGET_CURRENT_UA)
    fprintf(['\nSet TARGET_CHANNEL and TARGET_CURRENT_UA near the top of this script,\n' ...
             'then run it again to generate the compression comparison.\n']);
    return;
end

%% -------------------------
% SELECT CONDITION / TRIAL
% -------------------------
selected = channels == TARGET_CHANNEL & currents == TARGET_CURRENT_UA;
selected_frame_idx = frame_idx(selected);
selected_trial_ids = trial_ids(selected);

assert(~isempty(selected_frame_idx), ...
    'No valid trials found for TARGET_CHANNEL=%g and TARGET_CURRENT_UA=%g.', ...
    TARGET_CHANNEL, TARGET_CURRENT_UA);

assert(TARGET_TRIAL_INDEX_WITHIN_CONDITION >= 1 && ...
       TARGET_TRIAL_INDEX_WITHIN_CONDITION <= numel(selected_frame_idx), ...
    'TARGET_TRIAL_INDEX_WITHIN_CONDITION must be between 1 and %d.', numel(selected_frame_idx));

onset_frame = selected_frame_idx(TARGET_TRIAL_INDEX_WITHIN_CONDITION);
selected_trial_id = selected_trial_ids(TARGET_TRIAL_INDEX_WITHIN_CONDITION);

fprintf('\nSelected condition\n');
fprintf('  channel: %g\n', TARGET_CHANNEL);
fprintf('  current_uA: %g\n', TARGET_CURRENT_UA);
fprintf('  condition trial index: %d of %d\n', ...
    TARGET_TRIAL_INDEX_WITHIN_CONDITION, numel(selected_frame_idx));
fprintf('  onset frame: %d\n', onset_frame);
fprintf('  trial id: %g\n', selected_trial_id);

%% -------------------------
% BUILD EVOKED MAP
% -------------------------
evoked_map = build_evoked_map(img_dir, image_files, onset_frame, baseline_offsets, response_offsets);
display_map = evoked_map;
display_map(~final_mask) = NaN;

display_crop = crop_to_bbox(display_map, bbox);
analysis_crop = crop_to_bbox(analysis_mask, bbox);

finite_vals = display_crop(isfinite(display_crop));
assert(~isempty(finite_vals), 'Selected map has no finite values in the cropped display region.');

q = quantile(finite_vals, [0.02 0.98]);
m = max(abs(q));
if ~isfinite(m) || m == 0
    m = max(abs(finite_vals));
end
if ~isfinite(m) || m == 0
    m = 1;
end
clim = [-m m];

%% -------------------------
% BINNING COUNTS AND ERRORS
% -------------------------
fprintf('\nCompression summary\n');
fprintf('  Original V1 samples: %d\n', nnz(V1_mask));
fprintf('  Original analysis-mask samples: %d\n', nnz(analysis_mask));

[~, ~, ~, recon_2x] = compress_map(display_crop, 2);
[~, ~, ~, recon_4x] = compress_map(display_crop, 4);

for factor = [2 4]
    [~, occupied_v1, count_v1] = mask_coverage_counts(V1_mask, factor, MASK_OCCUPANCY_THRESHOLD);
    [~, occupied_analysis, count_analysis] = mask_coverage_counts(analysis_mask, factor, MASK_OCCUPANCY_THRESHOLD);
    [~, ~, ~, recon_map] = compress_map(display_crop, factor);
    [rmse_val, mae_val] = masked_error_metrics(display_crop, recon_map, analysis_crop);

    fprintf('\n  %dx binning\n', factor);
    fprintf('    Effective V1 bins: %d\n', count_v1);
    fprintf('    Effective analysis-mask bins: %d\n', count_analysis);
    fprintf('    Compression vs original V1: %.3fx\n', nnz(V1_mask) / max(count_v1, 1));
    fprintf('    Compression vs original analysis mask: %.3fx\n', nnz(analysis_mask) / max(count_analysis, 1));
    fprintf('    RMSE inside analysis mask: %.6f\n', rmse_val);
    fprintf('    MAE inside analysis mask: %.6f\n', mae_val);

    if factor == 2
        occupied_analysis_2x = occupied_analysis; %#ok<NASGU>
    else
        occupied_analysis_4x = occupied_analysis; %#ok<NASGU>
    end
end

%% -------------------------
% VISUAL COMPARISON
% -------------------------
figure('Color', 'w', 'Name', 'Compression comparison');
tiledlayout(2,3, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imagesc(display_crop, clim); axis image off;
hold on; contour(double(analysis_crop), [0.5 0.5], 'k', 'LineWidth', 1); hold off;
title('Original');
colormap(gca, parula);

nexttile;
imagesc(recon_2x, clim); axis image off;
hold on; contour(double(analysis_crop), [0.5 0.5], 'k', 'LineWidth', 1); hold off;
title('2x binned, expanded');
colormap(gca, parula);

nexttile;
imagesc(recon_4x, clim); axis image off;
hold on; contour(double(analysis_crop), [0.5 0.5], 'k', 'LineWidth', 1); hold off;
title('4x binned, expanded');
colormap(gca, parula);
cb = colorbar;
cb.Layout.Tile = 'east';
cb.Label.String = 'response - baseline';

nexttile;
imagesc(analysis_crop); axis image off;
title('Original analysis mask');
colormap(gca, gray);

nexttile;
[~, occupied_analysis_2x, ~] = mask_coverage_counts(analysis_crop, 2, MASK_OCCUPANCY_THRESHOLD);
imagesc(occupied_analysis_2x); axis image off;
title('2x occupied bins');
colormap(gca, gray);

nexttile;
[~, occupied_analysis_4x, ~] = mask_coverage_counts(analysis_crop, 4, MASK_OCCUPANCY_THRESHOLD);
imagesc(occupied_analysis_4x); axis image off;
title('4x occupied bins');
colormap(gca, gray);

sgtitle(sprintf('Channel %g | Current %g uA | Trial %d', ...
    TARGET_CHANNEL, TARGET_CURRENT_UA, TARGET_TRIAL_INDEX_WITHIN_CONDITION));

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
    error('Could not infer camera rate from day_pointer.meta.camera_rate_hz or day_pointer.meta.Freq.');
end
end

function offsets = frame_window_to_offsets(window_sec, Fs)
start_idx = ceil(window_sec(1) * Fs);
end_idx = floor(window_sec(2) * Fs) - 1;
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
y1 = min(size(mask,1), max(yy) + pad);
x0 = max(1, min(xx) - pad);
x1 = min(size(mask,2), max(xx) + pad);
bbox = [y0 y1 x0 x1];
end

function out = crop_to_bbox(arr, bbox)
out = arr(bbox(1):bbox(2), bbox(3):bbox(4));
end

function evoked_map = build_evoked_map(img_dir, image_files, onset_frame, baseline_offsets, response_offsets)
baseline_stack = load_frame_stack(img_dir, image_files, onset_frame + baseline_offsets);
response_stack = load_frame_stack(img_dir, image_files, onset_frame + response_offsets);

baseline_mean = mean(baseline_stack, 3, 'omitnan');
response_mean = mean(response_stack, 3, 'omitnan');
evoked_map = response_mean - baseline_mean;
end

function stack = load_frame_stack(img_dir, image_files, frame_indices)
for k = 1:numel(frame_indices)
    idx = frame_indices(k);
    assert(idx >= 1 && idx <= numel(image_files), 'Frame index out of bounds.');
    frame = im2single(imread(fullfile(img_dir, image_files(idx).name)));
    if k == 1
        [h, w] = size(frame);
        stack = zeros(h, w, numel(frame_indices), 'single');
    end
    stack(:,:,k) = frame;
end
end

function reduced = block_reduce_mean(arr, factor)
[h, w] = size(arr);
h_trim = floor(h / factor) * factor;
w_trim = floor(w / factor) * factor;
arr_trim = arr(1:h_trim, 1:w_trim);

if islogical(arr_trim)
    arr_trim = single(arr_trim);
end

arr_reshaped = reshape(arr_trim, factor, h_trim / factor, factor, w_trim / factor);
arr_reshaped = permute(arr_reshaped, [2 4 1 3]);
reduced = mean(arr_reshaped, [3 4], 'omitnan');
end

function expanded = upsample_repeat(arr, factor)
expanded = repelem(arr, factor, factor);
end

function [reduced, expanded, recon_cropped, recon_full] = compress_map(arr, factor)
reduced = block_reduce_mean(arr, factor);
expanded = upsample_repeat(reduced, factor);
recon_cropped = expanded;
recon_full = expanded;
end

function [reduced, occupied, count] = mask_coverage_counts(mask, factor, threshold)
reduced = block_reduce_mean(mask, factor);
occupied = reduced > threshold;
count = nnz(occupied);
end

function [rmse_val, mae_val] = masked_error_metrics(original, reconstructed, mask)
h = min([size(original,1), size(reconstructed,1), size(mask,1)]);
w = min([size(original,2), size(reconstructed,2), size(mask,2)]);

diff_map = original(1:h, 1:w) - reconstructed(1:h, 1:w);
valid = logical(mask(1:h, 1:w)) & isfinite(diff_map);
vals = diff_map(valid);

if isempty(vals)
    rmse_val = NaN;
    mae_val = NaN;
    return;
end

rmse_val = sqrt(mean(vals.^2, 'omitnan'));
mae_val = mean(abs(vals), 'omitnan');
end
