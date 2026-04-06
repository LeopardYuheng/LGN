%% compare_pixelwise_activation_across_sessions.m
% Compare pixelwise activations across multiple sessions for matched
% channel-current conditions.

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
response_sec = [0 1.0];
alpha = 0.05;
min_cluster_size = 100;
conn = 8;

use_analysis_mask_for_stats = true;
mask_outside_for_display = true;
min_sessions_per_condition = 2;

use_shared_clim = true;
shared_clim = [];

%% -------------------------
% SELECT DAY POINTERS
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer files', 'MultiSelect', 'on');
if isequal(fn, 0)
    error('No files selected.');
end

if ischar(fn)
    fn = {fn};
end

day_pointer_files = fullfile(fp, fn);
n_sessions = numel(day_pointer_files);
assert(n_sessions >= 2, 'Select at least two day pointer files.');

%% -------------------------
% ANALYZE EACH SESSION
% -------------------------
session_results = struct( ...
    'session_label', {}, ...
    'subject_id', {}, ...
    'date_str', {}, ...
    'day_pointer_file', {}, ...
    'img_dir', {}, ...
    'save_dir', {}, ...
    'final_mask', {}, ...
    'V1_mask', {}, ...
    'analysis_mask', {}, ...
    'global_v1_xlim', {}, ...
    'global_v1_ylim', {}, ...
    'condition_results', {} );

all_map_vals = [];

for s = 1:n_sessions
    fprintf('\n==============================\n');
    fprintf('Analyzing session %d / %d\n', s, n_sessions);
    fprintf('  %s\n', day_pointer_files{s});

    session_results(s) = analyze_single_session( ...
        day_pointer_files{s}, response_sec, alpha, min_cluster_size, conn, ...
        use_analysis_mask_for_stats, mask_outside_for_display);

    all_map_vals = [all_map_vals; collect_map_values(session_results(s).condition_results)]; %#ok<AGROW>
end

%% -------------------------
% OUTPUT DIRECTORY
% -------------------------
base_output_dir = fileparts(day_pointer_files{1});
save_root = fullfile(base_output_dir, 'multi_session_pixelwise_activation_comparison');
if ~exist(save_root, 'dir')
    mkdir(save_root);
end

%% -------------------------
% DISPLAY LIMITS
% -------------------------
if use_shared_clim && ~isempty(shared_clim)
    clim_to_use = shared_clim;
elseif ~isempty(all_map_vals)
    q = quantile(all_map_vals, [0.02 0.98]);
    m = max(abs(q));
    if ~isfinite(m) || m == 0
        m = 0.01;
    end
    clim_to_use = [-m m];
else
    clim_to_use = [-0.01 0.01];
end

%% -------------------------
% BUILD SESSION-CONDITION TABLE
% -------------------------
session_condition_rows = struct( ...
    'session_index', {}, ...
    'session_label', {}, ...
    'subject_id', {}, ...
    'date_str', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'n_trials', {}, ...
    'has_cluster', {}, ...
    'largest_cluster_size', {}, ...
    'fraction_activated', {}, ...
    'mean_cluster_effect', {}, ...
    'centroid_x', {}, ...
    'centroid_y', {}, ...
    'peak_x', {}, ...
    'peak_y', {} );

for s = 1:numel(session_results)
    conds = session_results(s).condition_results;
    for c = 1:numel(conds)
        session_condition_rows(end+1) = make_session_condition_row(conds(c), session_results(s), s);
    end
end

session_condition_table = struct2table(session_condition_rows);

%% -------------------------
% MATCH CONDITIONS ACROSS SESSIONS
% -------------------------
condition_keys = {};
for s = 1:numel(session_results)
    conds = session_results(s).condition_results;
    for c = 1:numel(conds)
        condition_keys{end+1} = condition_key(conds(c).channel, conds(c).current_uA);
    end
end
condition_keys = unique(condition_keys);

comparison_summary = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'session_indices', {}, ...
    'session_labels', {}, ...
    'n_sessions', {}, ...
    'n_active_sessions', {}, ...
    'pairwise_metrics', {} );

pairwise_rows = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'session_a', {}, ...
    'session_b', {}, ...
    'has_cluster_a', {}, ...
    'has_cluster_b', {}, ...
    'same_image_size', {}, ...
    'active_pixels_a', {}, ...
    'active_pixels_b', {}, ...
    'intersection_pixels', {}, ...
    'union_pixels', {}, ...
    'dice', {}, ...
    'iou', {}, ...
    'centroid_distance_px', {}, ...
    'map_corr_common_mask', {}, ...
    'fraction_activated_diff', {}, ...
    'mean_cluster_effect_diff', {} );

for k = 1:numel(condition_keys)
    key = condition_keys{k};
    [channel_i, current_i] = parse_condition_key(key);
    matched = find_condition_across_sessions(session_results, channel_i, current_i);

    if numel(matched) < min_sessions_per_condition
        continue;
    end

    pairwise_metrics = struct([]);
    for i = 1:numel(matched)-1
        for j = i+1:numel(matched)
            pairwise_metrics(end+1) = compare_condition_pair( ... %#ok<AGROW>
                matched(i), matched(j), session_results);

            pairwise_rows(end+1) = pairwise_metric_to_row( ... %#ok<AGROW>
                pairwise_metrics(end), channel_i, current_i, key);
        end
    end

    comparison_summary(end+1).condition_key = key;
    comparison_summary(end).channel = channel_i;
    comparison_summary(end).current_uA = current_i;
    comparison_summary(end).session_indices = [matched.session_index];
    comparison_summary(end).session_labels = {matched.session_label};
    comparison_summary(end).n_sessions = numel(matched);
    comparison_summary(end).n_active_sessions = sum([matched.condition.has_cluster]);
    comparison_summary(end).pairwise_metrics = pairwise_metrics;

    fig = make_condition_comparison_figure(matched, session_results, clim_to_use);
    exportgraphics(fig, fullfile(save_root, sprintf('%s_comparison.png', sanitize_filename(key))), 'Resolution', 200);
    close(fig);
end

pairwise_table = struct2table(pairwise_rows);

%% -------------------------
% SAVE SUMMARY FILES
% -------------------------
save(fullfile(save_root, 'multi_session_activation_comparison.mat'), ...
    'session_results', 'session_condition_table', 'comparison_summary', ...
    'pairwise_table', 'response_sec', 'alpha', 'min_cluster_size', 'conn', ...
    'use_analysis_mask_for_stats', 'mask_outside_for_display', ...
    'clim_to_use', '-v7.3');

writetable(session_condition_table, fullfile(save_root, 'session_condition_summary.csv'));
writetable(pairwise_table, fullfile(save_root, 'pairwise_condition_comparison.csv'));

fprintf('\nSaved multi-session comparison outputs to:\n  %s\n', save_root);

%% =========================
% LOCAL FUNCTIONS
% =========================
function session_result = analyze_single_session(day_pointer_file, response_sec, alpha, min_cluster_size, conn, use_analysis_mask_for_stats, mask_outside_for_display)
S = load(day_pointer_file);
if isfield(S, 'day_pointer')
    day_pointer = S.day_pointer;
elseif isfield(S, 'C')
    day_pointer = S.C;
else
    error('Selected file must contain "day_pointer" or legacy variable "C".');
end

assert(isfield(day_pointer, 'meta'), 'day_pointer.meta missing.');
assert(isfield(day_pointer, 'cfg'), 'day_pointer.cfg missing.');
assert(isfield(day_pointer, 'entries') && ~isempty(day_pointer.entries), ...
    'day_pointer.entries missing or empty.');

dataset_root = day_pointer.meta.dataset_root;
day_setup_file = resolve_file_path(day_pointer.meta.day_setup_file_rel, dataset_root, 'file');
img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');

D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;

[H, W] = size(analysis_mask);

image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFFs found.');

nums = nan(numel(image_files), 1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord] = sort(nums);
image_files = image_files(ord);
nFrames = numel(image_files);

Fs = infer_camera_rate(day_pointer);
pre_sec = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);
full_win = -pre_frames:post_frames;
t_s = full_win / Fs;

baseline_idx = t_s < 0;
response_idx = t_s > response_sec(1) & t_s <= response_sec(2);

[frame_idx, channels, currents] = unpack_day_pointer_entries(day_pointer.entries);
valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);

frame_idx = frame_idx(valid);
channels = channels(valid);
currents = currents(valid);

unique_channels = unique(channels);

pad_xy = 10;
[y_v1, x_v1] = find(V1_mask);
global_v1_xlim = [max(1, min(x_v1) - pad_xy), min(size(V1_mask,2), max(x_v1) + pad_xy)];
global_v1_ylim = [max(1, min(y_v1) - pad_xy), min(size(V1_mask,1), max(y_v1) + pad_xy)];

condition_results = struct( ...
    'channel', {}, ...
    'current_uA', {}, ...
    'n_trials', {}, ...
    'mean_evoked_map', {}, ...
    'p_map', {}, ...
    'sig_pixel_mask', {}, ...
    'sig_cluster_mask', {}, ...
    'largest_cluster_mask', {}, ...
    'largest_cluster_size', {}, ...
    'fraction_activated', {}, ...
    'mean_cluster_effect', {}, ...
    'has_cluster', {}, ...
    'centroid_xy', {}, ...
    'peak_xy', {} );

for ch_i = 1:numel(unique_channels)
    ch = unique_channels(ch_i);
    idx_ch = channels == ch;
    currents_ch = sort(unique(currents(idx_ch)));

    if ~any(currents_ch == 0)
        continue;
    end

    idx_base = idx_ch & currents == 0;
    base_maps = build_trial_response_map_stack(frame_idx(idx_base), img_dir, image_files, ...
        full_win, baseline_idx, response_idx, H, W);
    if isempty(base_maps)
        continue;
    end

    for cur_i = 1:numel(currents_ch)
        cur = currents_ch(cur_i);
        if cur == 0
            continue;
        end

        idx_cur = idx_ch & currents == cur;
        cur_maps = build_trial_response_map_stack(frame_idx(idx_cur), img_dir, image_files, ...
            full_win, baseline_idx, response_idx, H, W);
        if isempty(cur_maps)
            continue;
        end

        mean_evoked_map = mean(cur_maps, 3, 'omitnan');
        p_map = compute_pixelwise_p_map(cur_maps, base_maps, analysis_mask, final_mask, use_analysis_mask_for_stats);
        if use_analysis_mask_for_stats
            stat_mask = analysis_mask;
        else
            stat_mask = final_mask;
        end

        sig_pixel_mask = (p_map < alpha) & (mean_evoked_map > 0) & stat_mask;
        [sig_cluster_mask, largest_cluster_mask, largest_cluster_size] = ...
            cluster_filter_mask(sig_pixel_mask, conn, min_cluster_size, H, W);

        has_cluster = any(sig_cluster_mask(:));
        fraction_activated = sum(sig_cluster_mask(:)) / sum(stat_mask(:));
        mean_cluster_effect = mean(mean_evoked_map(sig_cluster_mask), 'omitnan');
        if ~has_cluster
            mean_cluster_effect = NaN;
        end

        centroid_xy = [NaN NaN];
        peak_xy = [NaN NaN];
        if any(largest_cluster_mask(:))
            [yy, xx] = find(largest_cluster_mask);
            centroid_xy = [mean(xx, 'omitnan'), mean(yy, 'omitnan')];

            search_map = mean_evoked_map;
            search_map(~largest_cluster_mask) = NaN;
            if any(isfinite(search_map(:)))
                [~, idx_max] = max(search_map(:));
                [y_peak, x_peak] = ind2sub(size(search_map), idx_max);
                peak_xy = [x_peak, y_peak];
            end
        end

        if mask_outside_for_display
            mean_evoked_map(~final_mask) = NaN;
        end

        condition_results(end+1).channel = ch; %#ok<AGROW>
        condition_results(end).current_uA = cur;
        condition_results(end).n_trials = size(cur_maps, 3);
        condition_results(end).mean_evoked_map = mean_evoked_map;
        condition_results(end).p_map = p_map;
        condition_results(end).sig_pixel_mask = sig_pixel_mask;
        condition_results(end).sig_cluster_mask = sig_cluster_mask;
        condition_results(end).largest_cluster_mask = largest_cluster_mask;
        condition_results(end).largest_cluster_size = largest_cluster_size;
        condition_results(end).fraction_activated = fraction_activated;
        condition_results(end).mean_cluster_effect = mean_cluster_effect;
        condition_results(end).has_cluster = has_cluster;
        condition_results(end).centroid_xy = centroid_xy;
        condition_results(end).peak_xy = peak_xy;
    end
end

session_label = build_session_label(day_pointer, day_pointer_file);
subject_id = get_nested_field(day_pointer, {'meta', 'subject_id'}, '');
date_str = get_nested_field(day_pointer, {'meta', 'date_str'}, '');
save_dir = fullfile(img_dir, '..', 'analysis', 'pixelwise_threshold_region_analysis');

session_result = struct();
session_result.session_label = session_label;
session_result.subject_id = subject_id;
session_result.date_str = date_str;
session_result.day_pointer_file = day_pointer_file;
session_result.img_dir = img_dir;
session_result.save_dir = save_dir;
session_result.final_mask = final_mask;
session_result.V1_mask = V1_mask;
session_result.analysis_mask = analysis_mask;
session_result.global_v1_xlim = global_v1_xlim;
session_result.global_v1_ylim = global_v1_ylim;
session_result.condition_results = condition_results;
end

function vals = collect_map_values(condition_results)
vals = [];
for i = 1:numel(condition_results)
    map_i = condition_results(i).mean_evoked_map;
    vals = [vals; map_i(isfinite(map_i))]; %#ok<AGROW>
end
end

function row = make_session_condition_row(cond, session_result, session_index)
row = struct();
row.session_index = session_index;
row.session_label = string(session_result.session_label);
row.subject_id = string(session_result.subject_id);
row.date_str = string(session_result.date_str);
row.channel = cond.channel;
row.current_uA = cond.current_uA;
row.n_trials = cond.n_trials;
row.has_cluster = cond.has_cluster;
row.largest_cluster_size = cond.largest_cluster_size;
row.fraction_activated = cond.fraction_activated;
row.mean_cluster_effect = cond.mean_cluster_effect;
row.centroid_x = cond.centroid_xy(1);
row.centroid_y = cond.centroid_xy(2);
row.peak_x = cond.peak_xy(1);
row.peak_y = cond.peak_xy(2);
end

function matched = find_condition_across_sessions(session_results, channel_i, current_i)
matched = struct('session_index', {}, 'session_label', {}, 'condition', {});
for s = 1:numel(session_results)
    conds = session_results(s).condition_results;
    idx = find([conds.channel] == channel_i & [conds.current_uA] == current_i, 1);
    if isempty(idx)
        continue;
    end
    matched(end+1).session_index = s; %#ok<AGROW>
    matched(end).session_label = session_results(s).session_label;
    matched(end).condition = conds(idx);
end
end

function pairwise_metric = compare_condition_pair(match_a, match_b, session_results)
cond_a = match_a.condition;
cond_b = match_b.condition;

mask_a = logical(cond_a.largest_cluster_mask);
mask_b = logical(cond_b.largest_cluster_mask);

same_image_size = isequal(size(mask_a), size(mask_b));
if same_image_size
    intersection_pixels = sum(mask_a(:) & mask_b(:));
    union_pixels = sum(mask_a(:) | mask_b(:));
else
    intersection_pixels = NaN;
    union_pixels = NaN;
end

active_pixels_a = sum(mask_a(:));
active_pixels_b = sum(mask_b(:));

if same_image_size && (active_pixels_a + active_pixels_b) > 0
    dice = (2 * intersection_pixels) / (active_pixels_a + active_pixels_b);
else
    dice = NaN;
end

if same_image_size && union_pixels > 0
    iou = intersection_pixels / union_pixels;
else
    iou = NaN;
end

centroid_distance_px = norm(cond_a.centroid_xy - cond_b.centroid_xy);
if any(~isfinite([cond_a.centroid_xy, cond_b.centroid_xy]))
    centroid_distance_px = NaN;
end

map_corr_common_mask = compute_map_correlation( ...
    cond_a.mean_evoked_map, cond_b.mean_evoked_map, ...
    session_results(match_a.session_index), session_results(match_b.session_index));

pairwise_metric = struct();
pairwise_metric.session_index_a = match_a.session_index;
pairwise_metric.session_index_b = match_b.session_index;
pairwise_metric.session_label_a = match_a.session_label;
pairwise_metric.session_label_b = match_b.session_label;
pairwise_metric.has_cluster_a = cond_a.has_cluster;
pairwise_metric.has_cluster_b = cond_b.has_cluster;
pairwise_metric.same_image_size = same_image_size;
pairwise_metric.active_pixels_a = active_pixels_a;
pairwise_metric.active_pixels_b = active_pixels_b;
pairwise_metric.intersection_pixels = intersection_pixels;
pairwise_metric.union_pixels = union_pixels;
pairwise_metric.dice = dice;
pairwise_metric.iou = iou;
pairwise_metric.centroid_distance_px = centroid_distance_px;
pairwise_metric.map_corr_common_mask = map_corr_common_mask;
pairwise_metric.fraction_activated_diff = cond_b.fraction_activated - cond_a.fraction_activated;
pairwise_metric.mean_cluster_effect_diff = cond_b.mean_cluster_effect - cond_a.mean_cluster_effect;
end

function row = pairwise_metric_to_row(metric, channel_i, current_i, key)
row = struct();
row.condition_key = string(key);
row.channel = channel_i;
row.current_uA = current_i;
row.session_a = string(metric.session_label_a);
row.session_b = string(metric.session_label_b);
row.has_cluster_a = metric.has_cluster_a;
row.has_cluster_b = metric.has_cluster_b;
row.same_image_size = metric.same_image_size;
row.active_pixels_a = metric.active_pixels_a;
row.active_pixels_b = metric.active_pixels_b;
row.intersection_pixels = metric.intersection_pixels;
row.union_pixels = metric.union_pixels;
row.dice = metric.dice;
row.iou = metric.iou;
row.centroid_distance_px = metric.centroid_distance_px;
row.map_corr_common_mask = metric.map_corr_common_mask;
row.fraction_activated_diff = metric.fraction_activated_diff;
row.mean_cluster_effect_diff = metric.mean_cluster_effect_diff;
end

function fig = make_condition_comparison_figure(matched, session_results, clim_to_use)
n_sessions = numel(matched);
fig = figure('Color', 'w', 'Name', sprintf('Condition comparison %s', matched(1).session_label), ...
    'Position', [80 80 max(420 * n_sessions, 900) 680]);

t = tiledlayout(2, n_sessions, 'TileSpacing', 'compact', 'Padding', 'compact');
title(t, sprintf('Ch %d | %g uA across sessions', matched(1).condition.channel, matched(1).condition.current_uA), ...
    'Interpreter', 'none');

for i = 1:n_sessions
    sess = session_results(matched(i).session_index);
    cond = matched(i).condition;

    ax = nexttile;
    imagesc(ax, cond.mean_evoked_map);
    axis(ax, 'image');
    axis(ax, 'off');
    set(ax, 'YDir', 'normal');
    xlim(ax, sess.global_v1_xlim);
    ylim(ax, sess.global_v1_ylim);
    colormap(ax, parula);
    clim(ax, clim_to_use);
    hold(ax, 'on');
    visboundaries(ax, sess.V1_mask, 'Color', 'w', 'LineWidth', 1.0);
    visboundaries(ax, sess.final_mask, 'Color', 'y', 'LineWidth', 1.0);
    if any(cond.largest_cluster_mask(:))
        visboundaries(ax, cond.largest_cluster_mask & sess.final_mask, 'Color', 'r', 'LineWidth', 1.8);
    end
    if all(isfinite(cond.peak_xy))
        plot(ax, cond.peak_xy(1), cond.peak_xy(2), 'wo', 'MarkerFaceColor', 'm', 'MarkerSize', 6);
    end
    title(ax, sprintf('%s\nactive=%d | area=%d', matched(i).session_label, cond.has_cluster, cond.largest_cluster_size), ...
        'Interpreter', 'none');
    colorbar(ax);

    ax2 = nexttile;
    summary_text = {
        sprintf('Trials: %d', cond.n_trials)
        sprintf('Active frac: %.4f', cond.fraction_activated)
        sprintf('Mean effect: %.4f', cond.mean_cluster_effect)
        sprintf('Centroid x,y: %.1f, %.1f', cond.centroid_xy(1), cond.centroid_xy(2))
        sprintf('Peak x,y: %.1f, %.1f', cond.peak_xy(1), cond.peak_xy(2))
        };
    axis(ax2, 'off');
    text(ax2, 0, 0.9, summary_text, 'FontSize', 11, 'Interpreter', 'none', 'VerticalAlignment', 'top');
    xlim(ax2, [0 1]);
    ylim(ax2, [0 1]);
end
end

function r = compute_map_correlation(map_a, map_b, session_a, session_b)
if ~isequal(size(map_a), size(map_b))
    r = NaN;
    return;
end

common_mask = session_a.analysis_mask & session_b.analysis_mask;
x = map_a(common_mask);
y = map_b(common_mask);

valid = isfinite(x) & isfinite(y);
x = x(valid);
y = y(valid);

if numel(x) < 3 || numel(unique(x)) < 2 || numel(unique(y)) < 2
    r = NaN;
    return;
end

R = corrcoef(x, y);
r = R(1,2);
end

function key = condition_key(channel_i, current_i)
key = sprintf('ch%d_uA_%g', channel_i, current_i);
end

function [channel_i, current_i] = parse_condition_key(key)
tok = regexp(key, '^ch([-+]?\d+)_uA_([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)$', 'tokens', 'once');
assert(~isempty(tok), 'Could not parse condition key: %s', key);
channel_i = str2double(tok{1});
current_i = str2double(tok{2});
end

function label = build_session_label(day_pointer, day_pointer_file)
subject_id = get_nested_field(day_pointer, {'meta', 'subject_id'}, '');
date_str = get_nested_field(day_pointer, {'meta', 'date_str'}, '');

if ~isempty(subject_id) && ~isempty(date_str)
    label = sprintf('%s_%s', subject_id, date_str);
    return;
end

[~, base, ~] = fileparts(day_pointer_file);
label = base;
end

function value = get_nested_field(S, field_path, default_value)
value = default_value;
tmp = S;
for i = 1:numel(field_path)
    if ~isstruct(tmp) || ~isfield(tmp, field_path{i})
        return;
    end
    tmp = tmp.(field_path{i});
end
if ~isempty(tmp)
    value = tmp;
end
end

function path_out = resolve_file_path(rel_or_abs_path, dataset_root, kind)
if exist(rel_or_abs_path, kind_code(kind)) == kind_exists_value(kind)
    path_out = rel_or_abs_path;
else
    path_out = fullfile(dataset_root, rel_or_abs_path);
end

assert(exist(path_out, kind_code(kind)) == kind_exists_value(kind), ...
    'Resolved %s path does not exist: %s', kind, path_out);
end

function code = kind_code(kind)
switch kind
    case 'file'
        code = 'file';
    case 'dir'
        code = 'dir';
    otherwise
        error('Unsupported path kind: %s', kind);
end
end

function v = kind_exists_value(kind)
switch kind
    case 'file'
        v = 2;
    case 'dir'
        v = 7;
    otherwise
        error('Unsupported path kind: %s', kind);
end
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
    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i = numel(onset_i);
    frame_idx = [frame_idx; onset_i]; %#ok<AGROW>
    channels = [channels; repmat(double(entries(i).stim_channel), n_i, 1)]; %#ok<AGROW>
    currents = [currents; repmat(double(entries(i).current_uA), n_i, 1)]; %#ok<AGROW>
end
end

function dff_maps = build_trial_response_map_stack(frame_idx, img_dir, image_files, full_win, baseline_idx, response_idx, H, W)
n = numel(frame_idx);
if n == 0
    dff_maps = [];
    return;
end

dff_maps = nan(H, W, n);
for i = 1:n
    f = frame_idx(i);
    frames = f + full_win;
    stack = zeros(H, W, numel(frames));
    for k = 1:numel(frames)
        stack(:,:,k) = double(imread(fullfile(img_dir, image_files(frames(k)).name)));
    end
    baseline = mean(stack(:,:,baseline_idx), 3);
    response = mean(stack(:,:,response_idx), 3);
    dff_maps(:,:,i) = (response - baseline) ./ baseline;
end
end

function p_map = compute_pixelwise_p_map(cur_maps, base_maps, analysis_mask, final_mask, use_analysis_mask_for_stats)
[H, W, ~] = size(cur_maps);
p_map = nan(H, W);
if use_analysis_mask_for_stats
    pix_idx = find(analysis_mask);
else
    pix_idx = find(final_mask);
end
cur_2d = reshape(cur_maps, [], size(cur_maps, 3));
base_2d = reshape(base_maps, [], size(base_maps, 3));
for k = 1:numel(pix_idx)
    pix = pix_idx(k);
    x = cur_2d(pix, :);
    b = base_2d(pix, :);
    x = x(isfinite(x));
    b = b(isfinite(b));
    if numel(x) < 3 || numel(b) < 3
        continue;
    end
    [~, p] = ttest2(x, b);
    p_map(pix) = p;
end
end

function [sig_cluster_mask, largest_cluster_mask, largest_cluster_size] = cluster_filter_mask(sig_pixel_mask, conn, min_cluster_size, H, W)
CC = bwconncomp(sig_pixel_mask, conn);
sig_cluster_mask = false(H, W);
largest_cluster_mask = false(H, W);
largest_cluster_size = 0;
for i = 1:CC.NumObjects
    pix_list = CC.PixelIdxList{i};
    cluster_size = numel(pix_list);
    if cluster_size >= min_cluster_size
        sig_cluster_mask(pix_list) = true;
        if cluster_size > largest_cluster_size
            largest_cluster_size = cluster_size;
            largest_cluster_mask = false(H, W);
            largest_cluster_mask(pix_list) = true;
        end
    end
end
end

function name = sanitize_filename(str)
name = regexprep(str, '[^\w.-]', '_');
end
