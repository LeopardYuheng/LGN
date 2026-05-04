%% export_v1_trial_latency_table_csv.m
% Export a per-trial V1 response summary table to CSV.
%
% For each valid trial, this script:
%   1. computes the V1-averaged dF/F trace
%   2. measures peak amplitude and peak latency
%   3. compares early and late response windows
%   4. flags late-response trials
%   5. writes one CSV row per trial

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
day_pointer_file = "";

Fs_default = 10;
target_channels = [];        % [] = all channels
target_currents_uA = [];     % [] = all currents

pre_sec_override = [];
post_sec_override = [];

early_window_sec = [0 1];
late_window_sec = [1 3];
peak_search_sec = [0 3];
late_peak_cutoff_sec = 1;
late_mean_margin = 0;

% ROI options
roi_radius = 5; % pixels

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
% LOAD DAY SETUP / MASK
% -------------------------
D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;
assert(any(analysis_mask(:)), 'analysis_mask is empty.');
pix_idx = find(analysis_mask);

fprintf('analysis_mask pixels: %d\n', nnz(analysis_mask));

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
Fs = infer_camera_rate(day_pointer, Fs_default);
if isempty(pre_sec_override)
    pre_sec = double(day_pointer.cfg.pre_sec);
else
    pre_sec = double(pre_sec_override);
end
if isempty(post_sec_override)
    post_sec = double(day_pointer.cfg.post_sec);
else
    post_sec = double(post_sec_override);
end

pre_frames = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);
full_win = -pre_frames:post_frames;
t_s = full_win(:) / Fs;

baseline_idx = full_win < 0;
peak_idx = t_s >= peak_search_sec(1) & t_s <= peak_search_sec(2);
early_idx = t_s >= early_window_sec(1) & t_s <= early_window_sec(2);
late_idx = t_s >= late_window_sec(1) & t_s <= late_window_sec(2);

assert(any(baseline_idx), 'Baseline window selected zero frames.');
assert(any(peak_idx), 'Peak-search window selected zero frames.');
assert(any(early_idx), 'Early window selected zero frames.');
assert(any(late_idx), 'Late window selected zero frames.');

fprintf('\nCamera rate: %.3f Hz\n', Fs);
fprintf('TIFF frame count: %d\n', nFrames);
fprintf('Peak search window: [%.2f %.2f] sec\n', peak_search_sec(1), peak_search_sec(2));
fprintf('Early window: [%.2f %.2f] sec\n', early_window_sec(1), early_window_sec(2));
fprintf('Late window: [%.2f %.2f] sec\n', late_window_sec(1), late_window_sec(2));

%% -------------------------
% UNPACK TRIAL ENTRIES
% -------------------------
[frame_idx, channels, currents, trial_ids] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
    frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);
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

fprintf('Trials selected for CSV export: %d\n', n_trials);

%% -------------------------
% BUILD TRIAL TABLE
% -------------------------
trial_table = table('Size', [n_trials 18], ...
    'VariableTypes', {'double','double','double','double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double','logical','string'}, ...
    'VariableNames', {'trial_id','stim_channel','current_uA','onset_frame_idx', ...
    'peak_dff','peak_latency_s', ...
    'early_peak_dff','early_peak_latency_s','late_peak_dff','late_peak_latency_s', ...
    'early_mean_dff','late_mean_dff','late_minus_early_dff', ...
    'baseline_mean_raw','baseline_std_raw','roi_mean_dff', ...
    'late_flag','video_label'});

trial_traces = nan(n_trials, numel(t_s), 'single');

for i = 1:n_trials
    frame_indices = frame_idx(i) + full_win;
    [trace_i, roi_pix_idx] = build_trial_trace(frame_indices, img_dir, image_files, pix_idx, baseline_idx, peak_idx, roi_radius);
    trial_traces(i, :) = single(trace_i);
    % ROI mean dF/F in peak search window
    if any(peak_idx)
        roi_mean_dff = mean(trace_i(peak_idx), 'omitnan');
    else
        roi_mean_dff = NaN;
    end

    peak_trace = trace_i(peak_idx);
    peak_time = t_s(peak_idx);

    if all(~isfinite(peak_trace))
        peak_dff = NaN;
        peak_latency_s = NaN;
    else
        [peak_dff, imax] = max(peak_trace, [], 'omitnan');
        peak_latency_s = peak_time(imax);
    end

    early_trace = trace_i(early_idx);
    early_time = t_s(early_idx);
    if all(~isfinite(early_trace))
        early_peak_dff = NaN;
        early_peak_latency_s = NaN;
    else
        [early_peak_dff, imax_early] = max(early_trace, [], 'omitnan');
        early_peak_latency_s = early_time(imax_early);
    end

    late_trace = trace_i(late_idx);
    late_time = t_s(late_idx);
    if all(~isfinite(late_trace))
        late_peak_dff = NaN;
        late_peak_latency_s = NaN;
    else
        [late_peak_dff, imax_late] = max(late_trace, [], 'omitnan');
        late_peak_latency_s = late_time(imax_late);
    end

    early_mean_dff = mean(trace_i(early_idx), 'omitnan');
    late_mean_dff = mean(trace_i(late_idx), 'omitnan');
    late_minus_early_dff = late_mean_dff - early_mean_dff;

    % compute baseline stats over ROI (if available) otherwise use whole mask
    if exist('roi_pix_idx','var') && ~isempty(roi_pix_idx)
        raw_stats = compute_raw_baseline_stats(frame_indices, img_dir, image_files, roi_pix_idx, baseline_idx);
    else
        raw_stats = compute_raw_baseline_stats(frame_indices, img_dir, image_files, pix_idx, baseline_idx);
    end
    late_flag = isfinite(peak_latency_s) && peak_latency_s > late_peak_cutoff_sec;
    late_flag = late_flag || (isfinite(late_minus_early_dff) && late_minus_early_dff > late_mean_margin);

    if isnan(trial_ids(i))
        trial_label = sprintf('row_%04d', i);
        trial_id_value = NaN;
    else
        trial_label = sprintf('trial_%04d', round(trial_ids(i)));
        trial_id_value = trial_ids(i);
    end

    trial_table.trial_id(i) = trial_id_value;
    trial_table.stim_channel(i) = channels(i);
    trial_table.current_uA(i) = currents(i);
    trial_table.onset_frame_idx(i) = frame_idx(i);
    trial_table.peak_dff(i) = peak_dff;
    trial_table.peak_latency_s(i) = peak_latency_s;
    trial_table.early_peak_dff(i) = early_peak_dff;
    trial_table.early_peak_latency_s(i) = early_peak_latency_s;
    trial_table.late_peak_dff(i) = late_peak_dff;
    trial_table.late_peak_latency_s(i) = late_peak_latency_s;
    trial_table.early_mean_dff(i) = early_mean_dff;
    trial_table.late_mean_dff(i) = late_mean_dff;
    trial_table.late_minus_early_dff(i) = late_minus_early_dff;
    trial_table.baseline_mean_raw(i) = raw_stats.mean_baseline;
    trial_table.baseline_std_raw(i) = raw_stats.std_baseline;
    trial_table.roi_mean_dff(i) = roi_mean_dff;
    trial_table.late_flag(i) = late_flag;
    trial_table.video_label(i) = string(sprintf('ch_%d_current_%g_uA_%s', ...
        channels(i), currents(i), trial_label));
end

%% -------------------------
% OUTPUT PATHS
% -------------------------
[pointer_dir, pointer_base, ~] = fileparts(day_pointer_file);
out_dir = fullfile(pointer_dir, 'v1_trial_latency_table');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

csv_file = fullfile(out_dir, sprintf('%s_v1_trial_latency_table.csv', pointer_base));
writetable(trial_table, csv_file);

fprintf('\nCSV export complete\n');
fprintf('  CSV: %s\n', csv_file);
fprintf('  Late-flagged trials: %d / %d\n', nnz(trial_table.late_flag), height(trial_table));

if save_mat
    save(fullfile(out_dir, sprintf('%s_v1_trial_latency_table.mat', pointer_base)), ...
        'trial_table', 'trial_traces', 't_s', 'Fs', 'analysis_mask', ...
        'early_window_sec', 'late_window_sec', 'peak_search_sec', ...
        'late_peak_cutoff_sec', 'late_mean_margin', '-v7.3');
end

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

function [trace_i, roi_pix_idx] = build_trial_trace(frame_indices, img_dir, image_files, pix_idx, baseline_idx, peak_idx, roi_radius)
n_t = numel(frame_indices);
% Read image pixels for mask indices into stack
stack = nan(numel(pix_idx), n_t);
H = [];
W = [];
for k = 1:n_t
    img = double(imread(fullfile(img_dir, image_files(frame_indices(k)).name)));
    if isempty(H)
        [H, W] = size(img);
    end
    stack(:, k) = img(pix_idx);
end

baseline = mean(stack(:, baseline_idx), 2, 'omitnan');
valid_baseline = isfinite(baseline) & baseline ~= 0;
dff_stack = nan(size(stack));
dff_stack(valid_baseline, :) = (stack(valid_baseline, :) - baseline(valid_baseline)) ./ baseline(valid_baseline);

% find peak pixel within peak_idx window (use mean over peak window)
if nargin >= 6 && ~isempty(peak_idx) && any(peak_idx)
    resp_per_pixel = mean(dff_stack(:, peak_idx), 2, 'omitnan');
    % find pixel index (within pix_idx) of maximum response
    [~, imax] = max(resp_per_pixel);
    peak_pix_linear = pix_idx(imax); % linear index in full image
    % convert to subscripts
    [y0, x0] = ind2sub([H, W], peak_pix_linear);
    % build circular ROI mask (in full image coords)
    [X, Y] = meshgrid(1:W, 1:H);
    roi_mask_full = ( (X - x0).^2 + (Y - y0).^2 ) <= (roi_radius.^2);
    % restrict ROI to provided pix_idx (analysis_mask)
    roi_pix_idx = intersect(find(roi_mask_full), pix_idx);
    if isempty(roi_pix_idx)
        % fallback: use original pix_idx
        roi_pix_idx = pix_idx;
    end
    % build ROI-stack (rows correspond to roi_pix_idx)
    roi_mask_logical = ismember(pix_idx, roi_pix_idx);
    roi_stack = stack(roi_mask_logical, :);
    % compute dF/F for roi_stack using baseline of those pixels
    baseline_roi = mean(roi_stack(:, baseline_idx), 2, 'omitnan');
    valid_baseline_roi = isfinite(baseline_roi) & baseline_roi ~= 0;
    dff_roi = nan(size(roi_stack));
    dff_roi(valid_baseline_roi, :) = (roi_stack(valid_baseline_roi, :) - baseline_roi(valid_baseline_roi)) ./ baseline_roi(valid_baseline_roi);
    trace_i = mean(dff_roi, 1, 'omitnan');
else
    % if no peak window provided, fall back to whole-mask average
    trace_i = mean(dff_stack, 1, 'omitnan');
    roi_pix_idx = pix_idx;
end
end

function stats = compute_raw_baseline_stats(frame_indices, img_dir, image_files, pix_idx, baseline_idx)
baseline_frames = frame_indices(baseline_idx);
vals = nan(numel(baseline_frames), 1);

for k = 1:numel(baseline_frames)
    img = double(imread(fullfile(img_dir, image_files(baseline_frames(k)).name)));
    vals(k) = mean(img(pix_idx), 'omitnan');
end

stats = struct();
stats.mean_baseline = mean(vals, 'omitnan');
stats.std_baseline = std(vals, 0, 'omitnan');
end
