%% compare_pixelwise_activation_across_sessions.m
% Compare pixelwise activations across multiple sessions for matched
% channel-current conditions.

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
response_sec = [0.4 0.6];
alpha = 0.05;
min_cluster_size = 200;
conn = 8;
consistency_k = 1.0;
consistency_thresh = 0.38;
analysis_region_mode = 'v1';   % v1 | v1_bounding_box
registration_mode = 'final_mask_centroid_translation';   % none | final_mask_centroid_translation

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
    'channel_results', {}, ...
    'condition_results', {} );

all_map_vals = [];

for s = 1:n_sessions
    fprintf('\n==============================\n');
    fprintf('Analyzing session %d / %d\n', s, n_sessions);
    fprintf('  %s\n', day_pointer_files{s});

    session_results(s) = analyze_single_session( ...
        day_pointer_files{s}, response_sec, alpha, min_cluster_size, conn, ...
        use_analysis_mask_for_stats, mask_outside_for_display, ...
        consistency_k, consistency_thresh, analysis_region_mode);

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
    'mean_activation_fraction', {}, ...
    'pass_consistency', {}, ...
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

session_significance_rows = struct( ...
    'session_index', {}, ...
    'session_label', {}, ...
    'n_significant_conditions', {}, ...
    'n_total_conditions', {} );

for s = 1:numel(session_results)
    conds = session_results(s).condition_results;
    session_significance_rows(end+1).session_index = s; %#ok<AGROW>
    session_significance_rows(end).session_label = string(session_results(s).session_label);
    session_significance_rows(end).n_significant_conditions = sum([conds.has_cluster]);
    session_significance_rows(end).n_total_conditions = numel(conds);
end

session_significance_table = struct2table(session_significance_rows);
significant_session_condition_table = session_condition_table(session_condition_table.has_cluster, :);

%% -------------------------
% CHANNEL THRESHOLD TABLE
% -------------------------
channel_threshold_rows = struct( ...
    'session_index', {}, ...
    'session_label', {}, ...
    'subject_id', {}, ...
    'date_str', {}, ...
    'channel', {}, ...
    'threshold_uA', {}, ...
    'anchor_current_uA', {}, ...
    'threshold_peak_x', {}, ...
    'threshold_peak_y', {}, ...
    'threshold_centroid_x', {}, ...
    'threshold_centroid_y', {}, ...
    'threshold_area_px', {} );

for s = 1:numel(session_results)
    chans = session_results(s).channel_results;
    for c = 1:numel(chans)
        channel_threshold_rows(end+1) = make_channel_threshold_row(chans(c), session_results(s), s);
    end
end

channel_threshold_table = struct2table(channel_threshold_rows);

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

pairwise_rows = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'session_a', {}, ...
    'session_b', {}, ...
    'has_cluster_a', {}, ...
    'has_cluster_b', {}, ...
    'same_image_size', {}, ...
    'same_common_mask_size', {}, ...
    'active_pixels_a', {}, ...
    'active_pixels_b', {}, ...
    'intersection_pixels', {}, ...
    'union_pixels', {}, ...
    'dice', {}, ...
    'iou', {}, ...
    'centroid_distance_px', {}, ...
    'peak_distance_px', {}, ...
    'pixel_corr_r', {}, ...
    'pixel_corr_p', {}, ...
    'n_common_pixels', {}, ...
    'mean_abs_diff', {}, ...
    'rmse', {}, ...
    'fraction_activated_diff', {}, ...
    'mean_activation_fraction_diff', {}, ...
    'mean_cluster_effect_diff', {} );

all_days_rows = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'n_sessions_present', {}, ...
    'n_sessions_significant', {}, ...
    'session_labels', {}, ...
    'same_image_size', {}, ...
    'same_common_mask_size', {}, ...
    'active_pixels_intersection_all', {}, ...
    'active_pixels_union_all', {}, ...
    'active_pixels_mean_per_session', {}, ...
    'active_pixels_min_per_session', {}, ...
    'active_pixels_max_per_session', {}, ...
    'fraction_intersection_over_union', {}, ...
    'fraction_intersection_over_mean_active', {}, ...
    'mean_centroid_distance_to_group_px', {}, ...
    'max_centroid_distance_to_group_px', {} );

condition_significance_rows = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'n_sessions_present', {}, ...
    'n_sessions_significant', {}, ...
    'is_significant_across_days', {}, ...
    'significant_session_labels', {}, ...
    'all_session_labels', {} );

for k = 1:numel(condition_keys)
    key = condition_keys{k};
    [channel_i, current_i] = parse_condition_key(key);
    matched = find_condition_across_sessions(session_results, channel_i, current_i);

    if numel(matched) < min_sessions_per_condition
        continue;
    end

    active_mask = [matched.condition];
    active_mask = [active_mask.has_cluster];

    condition_significance_rows(end+1).condition_key = string(key); %#ok<AGROW>
    condition_significance_rows(end).channel = channel_i;
    condition_significance_rows(end).current_uA = current_i;
    condition_significance_rows(end).n_sessions_present = numel(matched);
    condition_significance_rows(end).n_sessions_significant = sum(active_mask);
    condition_significance_rows(end).is_significant_across_days = sum(active_mask) >= 2;
    condition_significance_rows(end).significant_session_labels = strjoin({matched(active_mask).session_label}, '; ');
    condition_significance_rows(end).all_session_labels = strjoin({matched.session_label}, '; ');

    if sum(active_mask) < 2
        continue;
    end

    matched_active = matched(active_mask);

    pairwise_metrics = struct( ...
        'session_index_a', {}, ...
        'session_index_b', {}, ...
        'session_label_a', {}, ...
        'session_label_b', {}, ...
        'has_cluster_a', {}, ...
        'has_cluster_b', {}, ...
        'same_image_size', {}, ...
        'same_common_mask_size', {}, ...
        'active_pixels_a', {}, ...
        'active_pixels_b', {}, ...
        'intersection_pixels', {}, ...
        'union_pixels', {}, ...
        'dice', {}, ...
        'iou', {}, ...
        'centroid_distance_px', {}, ...
        'peak_distance_px', {}, ...
        'pixel_similarity', {}, ...
        'fraction_activated_diff', {}, ...
        'mean_activation_fraction_diff', {}, ...
        'mean_cluster_effect_diff', {} );
    for i = 1:numel(matched_active)-1
        for j = i+1:numel(matched_active)
            pairwise_metrics(end+1) = compare_condition_pair( ... %#ok<AGROW>
                matched_active(i), matched_active(j), session_results, registration_mode);

            pairwise_rows(end+1) = pairwise_metric_to_row( ... %#ok<AGROW>
                pairwise_metrics(end), channel_i, current_i, key);
        end
    end

    all_days_rows(end+1) = all_days_metric_to_row( ... %#ok<AGROW>
        compare_condition_group(matched_active, session_results, registration_mode), channel_i, current_i, key);

    pair_figs = make_pairwise_overlap_figures(matched_active, session_results, clim_to_use, registration_mode);
    for pf_i = 1:numel(pair_figs)
        exportgraphics(pair_figs(pf_i).fig, ...
            fullfile(save_root, sprintf('%s_pair_%s_vs_%s_overlap.png', ...
            sanitize_filename(key), ...
            sanitize_filename(pair_figs(pf_i).session_label_a), ...
            sanitize_filename(pair_figs(pf_i).session_label_b))), ...
            'Resolution', 200);
        close(pair_figs(pf_i).fig);
    end

    all_days_fig = make_all_days_overlap_figure(matched_active, session_results, clim_to_use, registration_mode);
    exportgraphics(all_days_fig, ...
        fullfile(save_root, sprintf('%s_all_days_overlap.png', sanitize_filename(key))), ...
        'Resolution', 200);
    close(all_days_fig);
end

pairwise_table = struct2table(pairwise_rows);
condition_significance_table = struct2table(condition_significance_rows);
all_days_overlap_table = struct2table(all_days_rows);

%% -------------------------
% OVERVIEW FIGURES
% -------------------------
make_significance_presence_figure( ...
    condition_significance_table, session_results, save_root);
make_all_days_iou_heatmap( ...
    all_days_overlap_table, condition_significance_table, n_sessions, save_root);

%% -------------------------
% SAVE SUMMARY FILES
% -------------------------
save(fullfile(save_root, 'multi_session_activation_comparison.mat'), ...
    'session_results', 'session_condition_table', 'session_significance_table', ...
    'significant_session_condition_table', 'condition_significance_table', 'pairwise_table', ...
    'all_days_overlap_table', ...
    'response_sec', 'alpha', 'min_cluster_size', 'conn', ...
    'consistency_k', 'consistency_thresh', ...
    'analysis_region_mode', ...
    'registration_mode', ...
    'use_analysis_mask_for_stats', 'mask_outside_for_display', ...
    'clim_to_use', '-v7.3');

writetable(session_condition_table, fullfile(save_root, 'session_condition_summary.csv'));
writetable(significant_session_condition_table, fullfile(save_root, 'significant_session_conditions.csv'));
writetable(session_significance_table, fullfile(save_root, 'session_significant_condition_counts.csv'));
writetable(condition_significance_table, fullfile(save_root, 'conditions_significant_across_days.csv'));
writetable(pairwise_table, fullfile(save_root, 'pairwise_condition_comparison.csv'));
writetable(all_days_overlap_table, fullfile(save_root, 'all_days_condition_overlap_summary.csv'));

fprintf('\nSaved multi-session comparison outputs to:\n  %s\n', save_root);

%% =========================
% LOCAL FUNCTIONS
% =========================
function session_result = analyze_single_session(day_pointer_file, response_sec, alpha, min_cluster_size, conn, use_analysis_mask_for_stats, mask_outside_for_display, consistency_k, consistency_thresh, analysis_region_mode)
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
        analysis_mask = build_analysis_region_mask(final_mask, V1_mask, analysis_region_mode);

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
    'activation_fraction', {}, ...
    'mean_activation_fraction', {}, ...
    'pass_consistency', {}, ...
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

        base_mean_map = mean(base_maps, 3, 'omitnan');
        base_std_map = std(base_maps, 0, 3, 'omitnan');
        n_cur = size(cur_maps, 3);
        active_trials = false(H, W, n_cur);
        for ti = 1:n_cur
            active_trials(:,:,ti) = cur_maps(:,:,ti) > (base_mean_map + consistency_k .* base_std_map);
        end
        activation_fraction = mean(active_trials, 3, 'omitnan');
        if has_cluster
            mean_activation_fraction = mean(activation_fraction(sig_cluster_mask), 'omitnan');
        else
            mean_activation_fraction = 0;
        end
        pass_consistency = mean_activation_fraction >= consistency_thresh;
        has_cluster = has_cluster && pass_consistency;

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
        condition_results(end).activation_fraction = activation_fraction;
        condition_results(end).mean_activation_fraction = mean_activation_fraction;
        condition_results(end).pass_consistency = pass_consistency;
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
session_result.channel_results = build_channel_threshold_results(condition_results, analysis_mask);
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
row.mean_activation_fraction = cond.mean_activation_fraction;
row.pass_consistency = cond.pass_consistency;
row.centroid_x = cond.centroid_xy(1);
row.centroid_y = cond.centroid_xy(2);
row.peak_x = cond.peak_xy(1);
row.peak_y = cond.peak_xy(2);
end

function row = make_channel_threshold_row(ch_res, session_result, session_index)
row = struct();
row.session_index = session_index;
row.session_label = string(session_result.session_label);
row.subject_id = string(session_result.subject_id);
row.date_str = string(session_result.date_str);
row.channel = ch_res.channel;
row.threshold_uA = ch_res.threshold_uA;
row.anchor_current_uA = ch_res.anchor_current_uA;
row.threshold_peak_x = ch_res.threshold_peak_xy(1);
row.threshold_peak_y = ch_res.threshold_peak_xy(2);
row.threshold_centroid_x = ch_res.threshold_centroid_xy(1);
row.threshold_centroid_y = ch_res.threshold_centroid_xy(2);
row.threshold_area_px = ch_res.threshold_area_px;
end

function channel_results = build_channel_threshold_results(condition_results, analysis_mask)
channel_results = struct( ...
    'channel', {}, ...
    'threshold_uA', {}, ...
    'anchor_current_uA', {}, ...
    'threshold_peak_xy', {}, ...
    'threshold_centroid_xy', {}, ...
    'threshold_area_px', {}, ...
    'threshold_cluster_mask', {} );

if isempty(condition_results)
    return;
end

channels = unique([condition_results.channel]);
for ch_i = 1:numel(channels)
    ch = channels(ch_i);
    conds_ch = condition_results([condition_results.channel] == ch);
    [~, ord] = sort([conds_ch.current_uA]);
    conds_ch = conds_ch(ord);

    positive_currents = [conds_ch.current_uA];
    anchor_current_uA = max(positive_currents);

    threshold_uA = NaN;
    threshold_peak_xy = [NaN NaN];
    threshold_centroid_xy = [NaN NaN];
    threshold_area_px = 0;
    threshold_cluster_mask = false(size(analysis_mask));

    idx_thr = find([conds_ch.has_cluster], 1, 'first');
    if ~isempty(idx_thr)
        thr_cond = conds_ch(idx_thr);
        threshold_uA = thr_cond.current_uA;
        threshold_peak_xy = thr_cond.peak_xy;
        threshold_cluster_mask = logical(thr_cond.largest_cluster_mask);
        threshold_area_px = sum(threshold_cluster_mask(:));
        if threshold_area_px > 0
            [yy, xx] = find(threshold_cluster_mask);
            threshold_centroid_xy = [mean(xx, 'omitnan'), mean(yy, 'omitnan')];
        end
    end

    channel_results(end+1).channel = ch; %#ok<AGROW>
    channel_results(end).threshold_uA = threshold_uA;
    channel_results(end).anchor_current_uA = anchor_current_uA;
    channel_results(end).threshold_peak_xy = threshold_peak_xy;
    channel_results(end).threshold_centroid_xy = threshold_centroid_xy;
    channel_results(end).threshold_area_px = threshold_area_px;
    channel_results(end).threshold_cluster_mask = threshold_cluster_mask;
end
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

function matched = find_threshold_across_sessions(session_results, channel_i)
matched = struct('session_index', {}, 'session_label', {}, 'channel_result', {});
for s = 1:numel(session_results)
    chans = session_results(s).channel_results;
    idx = find([chans.channel] == channel_i, 1);
    if isempty(idx)
        continue;
    end
    matched(end+1).session_index = s; %#ok<AGROW>
    matched(end).session_label = session_results(s).session_label;
    matched(end).channel_result = chans(idx);
end
end

function pairwise_metric = compare_condition_pair(match_a, match_b, session_results, registration_mode)
cond_a = match_a.condition;
cond_b = match_b.condition;

overlap = compute_overlap_metrics( ...
    logical(cond_a.largest_cluster_mask), logical(cond_b.largest_cluster_mask), ...
    session_results(match_a.session_index), session_results(match_b.session_index), registration_mode);

centroid_distance_px = norm(cond_a.centroid_xy - cond_b.centroid_xy);
if any(~isfinite([cond_a.centroid_xy, cond_b.centroid_xy]))
    centroid_distance_px = NaN;
end

peak_distance_px = norm(cond_a.peak_xy - cond_b.peak_xy);
if any(~isfinite([cond_a.peak_xy, cond_b.peak_xy]))
    peak_distance_px = NaN;
end

pixel_similarity = compute_pixel_similarity( ...
    cond_a.mean_evoked_map, cond_b.mean_evoked_map, ...
    session_results(match_a.session_index), session_results(match_b.session_index), registration_mode);

pairwise_metric = struct();
pairwise_metric.session_index_a = match_a.session_index;
pairwise_metric.session_index_b = match_b.session_index;
pairwise_metric.session_label_a = match_a.session_label;
pairwise_metric.session_label_b = match_b.session_label;
pairwise_metric.has_cluster_a = cond_a.has_cluster;
pairwise_metric.has_cluster_b = cond_b.has_cluster;
pairwise_metric.same_image_size = overlap.same_image_size;
pairwise_metric.same_common_mask_size = overlap.same_common_mask_size;
pairwise_metric.active_pixels_a = overlap.active_pixels_a;
pairwise_metric.active_pixels_b = overlap.active_pixels_b;
pairwise_metric.intersection_pixels = overlap.intersection_pixels;
pairwise_metric.union_pixels = overlap.union_pixels;
pairwise_metric.dice = overlap.dice;
pairwise_metric.iou = overlap.iou;
pairwise_metric.centroid_distance_px = centroid_distance_px;
pairwise_metric.peak_distance_px = peak_distance_px;
pairwise_metric.pixel_similarity = pixel_similarity;
pairwise_metric.fraction_activated_diff = cond_b.fraction_activated - cond_a.fraction_activated;
pairwise_metric.mean_activation_fraction_diff = cond_b.mean_activation_fraction - cond_a.mean_activation_fraction;
pairwise_metric.mean_cluster_effect_diff = cond_b.mean_cluster_effect - cond_a.mean_cluster_effect;
end

function analysis_mask = build_analysis_region_mask(final_mask, V1_mask, analysis_region_mode)
switch lower(analysis_region_mode)
    case 'v1'
        analysis_mask = final_mask & V1_mask;
    case 'v1_bounding_box'
        pad_xy = 10;
        [yy, xx] = find(V1_mask);
        assert(~isempty(yy), 'V1_mask is empty.');
        xmin = max(1, min(xx) - pad_xy);
        xmax = min(size(V1_mask, 2), max(xx) + pad_xy);
        ymin = max(1, min(yy) - pad_xy);
        ymax = min(size(V1_mask, 1), max(yy) + pad_xy);
        analysis_mask = false(size(final_mask));
        analysis_mask(ymin:ymax, xmin:xmax) = true;
    otherwise
        error('Unsupported analysis_region_mode: %s', analysis_region_mode);
end

assert(any(analysis_mask(:)), 'analysis_mask is empty after applying analysis_region_mode.');
end

function metric = compare_threshold_pair(match_a, match_b, session_results, registration_mode)
ch_a = match_a.channel_result;
ch_b = match_b.channel_result;

overlap = compute_overlap_metrics( ...
    logical(ch_a.threshold_cluster_mask), logical(ch_b.threshold_cluster_mask), ...
    session_results(match_a.session_index), session_results(match_b.session_index), registration_mode);

threshold_centroid_distance_px = norm(ch_a.threshold_centroid_xy - ch_b.threshold_centroid_xy);
if any(~isfinite([ch_a.threshold_centroid_xy, ch_b.threshold_centroid_xy]))
    threshold_centroid_distance_px = NaN;
end

threshold_peak_distance_px = norm(ch_a.threshold_peak_xy - ch_b.threshold_peak_xy);
if any(~isfinite([ch_a.threshold_peak_xy, ch_b.threshold_peak_xy]))
    threshold_peak_distance_px = NaN;
end

metric = struct();
metric.channel = ch_a.channel;
metric.session_label_a = match_a.session_label;
metric.session_label_b = match_b.session_label;
metric.threshold_uA_a = ch_a.threshold_uA;
metric.threshold_uA_b = ch_b.threshold_uA;
metric.threshold_uA_diff = ch_b.threshold_uA - ch_a.threshold_uA;
metric.has_threshold_a = isfinite(ch_a.threshold_uA);
metric.has_threshold_b = isfinite(ch_b.threshold_uA);
metric.threshold_dice = overlap.dice;
metric.threshold_iou = overlap.iou;
metric.threshold_centroid_distance_px = threshold_centroid_distance_px;
metric.threshold_peak_distance_px = threshold_peak_distance_px;
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
row.same_common_mask_size = metric.same_common_mask_size;
row.active_pixels_a = metric.active_pixels_a;
row.active_pixels_b = metric.active_pixels_b;
row.intersection_pixels = metric.intersection_pixels;
row.union_pixels = metric.union_pixels;
row.dice = metric.dice;
row.iou = metric.iou;
row.centroid_distance_px = metric.centroid_distance_px;
row.peak_distance_px = metric.peak_distance_px;
row.pixel_corr_r = metric.pixel_similarity.r;
row.pixel_corr_p = metric.pixel_similarity.p;
row.n_common_pixels = metric.pixel_similarity.n;
row.mean_abs_diff = metric.pixel_similarity.mean_abs_diff;
row.rmse = metric.pixel_similarity.rmse;
row.fraction_activated_diff = metric.fraction_activated_diff;
row.mean_activation_fraction_diff = metric.mean_activation_fraction_diff;
row.mean_cluster_effect_diff = metric.mean_cluster_effect_diff;
end

function metric = compare_condition_group(matched_active, session_results, registration_mode)
metric = struct();
metric.session_labels = strjoin({matched_active.session_label}, '; ');
metric.n_sessions_present = numel(matched_active);
metric.n_sessions_significant = numel(matched_active);
metric.same_image_size = true;
metric.same_common_mask_size = true;
metric.active_pixels_intersection_all = NaN;
metric.active_pixels_union_all = NaN;
metric.active_pixels_mean_per_session = NaN;
metric.active_pixels_min_per_session = NaN;
metric.active_pixels_max_per_session = NaN;
metric.fraction_intersection_over_union = NaN;
metric.fraction_intersection_over_mean_active = NaN;
metric.mean_centroid_distance_to_group_px = NaN;
metric.max_centroid_distance_to_group_px = NaN;

if isempty(matched_active)
    return;
end

sess_ref = session_results(matched_active(1).session_index);
mask_list = cell(1, numel(matched_active));
active_counts = nan(1, numel(matched_active));
centroids = nan(numel(matched_active), 2);
for i = 1:numel(matched_active)
    cond_i = matched_active(i).condition;
    sess_i = session_results(matched_active(i).session_index);
    mask_i = logical(cond_i.largest_cluster_mask);
    if i == 1
        ref_mask_size = size(mask_i);
        ref_analysis_size = size(sess_i.analysis_mask);
        common_mask = sess_i.analysis_mask;
        mask_list{i} = mask_i;
        centroids(i, :) = cond_i.centroid_xy;
    else
        metric.same_image_size = metric.same_image_size && isequal(size(mask_i), ref_mask_size);
        metric.same_common_mask_size = metric.same_common_mask_size && isequal(size(sess_i.analysis_mask), ref_analysis_size);
        if metric.same_common_mask_size
            common_mask = common_mask & warp_binary_to_reference(sess_i.analysis_mask, sess_ref, sess_i, registration_mode);
        end
        mask_list{i} = warp_binary_to_reference(mask_i, sess_ref, sess_i, registration_mode);
        [dx, dy] = estimate_final_mask_translation(sess_ref.final_mask, sess_i.final_mask, registration_mode);
        centroids(i, :) = cond_i.centroid_xy + [dx, dy];
    end
    active_counts(i) = sum(mask_list{i}(:));
end

if ~metric.same_image_size || ~metric.same_common_mask_size
    return;
end

intersection_mask = common_mask;
union_mask = false(ref_mask_size);
for i = 1:numel(mask_list)
    mask_common_i = mask_list{i} & common_mask;
    intersection_mask = intersection_mask & mask_common_i;
    union_mask = union_mask | mask_common_i;
end

metric.active_pixels_intersection_all = sum(intersection_mask(:));
metric.active_pixels_union_all = sum(union_mask(:));
metric.active_pixels_mean_per_session = mean(active_counts, 'omitnan');
metric.active_pixels_min_per_session = min(active_counts);
metric.active_pixels_max_per_session = max(active_counts);
if metric.active_pixels_union_all > 0
    metric.fraction_intersection_over_union = metric.active_pixels_intersection_all / metric.active_pixels_union_all;
end
if metric.active_pixels_mean_per_session > 0
    metric.fraction_intersection_over_mean_active = metric.active_pixels_intersection_all / metric.active_pixels_mean_per_session;
end

valid_centroids = all(isfinite(centroids), 2);
if any(valid_centroids)
    centroid_mean = mean(centroids(valid_centroids, :), 1, 'omitnan');
    centroid_dist = vecnorm(centroids(valid_centroids, :) - centroid_mean, 2, 2);
    metric.mean_centroid_distance_to_group_px = mean(centroid_dist, 'omitnan');
    metric.max_centroid_distance_to_group_px = max(centroid_dist);
end
end

function row = all_days_metric_to_row(metric, channel_i, current_i, key)
row = struct();
row.condition_key = string(key);
row.channel = channel_i;
row.current_uA = current_i;
row.n_sessions_present = metric.n_sessions_present;
row.n_sessions_significant = metric.n_sessions_significant;
row.session_labels = string(metric.session_labels);
row.same_image_size = metric.same_image_size;
row.same_common_mask_size = metric.same_common_mask_size;
row.active_pixels_intersection_all = metric.active_pixels_intersection_all;
row.active_pixels_union_all = metric.active_pixels_union_all;
row.active_pixels_mean_per_session = metric.active_pixels_mean_per_session;
row.active_pixels_min_per_session = metric.active_pixels_min_per_session;
row.active_pixels_max_per_session = metric.active_pixels_max_per_session;
row.fraction_intersection_over_union = metric.fraction_intersection_over_union;
row.fraction_intersection_over_mean_active = metric.fraction_intersection_over_mean_active;
row.mean_centroid_distance_to_group_px = metric.mean_centroid_distance_to_group_px;
row.max_centroid_distance_to_group_px = metric.max_centroid_distance_to_group_px;
end

function make_significance_presence_figure(condition_significance_table, session_results, save_root)
if isempty(condition_significance_table)
    return;
end

session_labels = string({session_results.session_label});
partial_idx = condition_significance_table.n_sessions_significant > 0 & ...
    condition_significance_table.n_sessions_significant < numel(session_results);
partial_table = condition_significance_table(partial_idx, :);
if isempty(partial_table)
    return;
end

condition_labels = strings(height(partial_table), 1);
presence_mat = false(height(partial_table), numel(session_results));
for i = 1:height(partial_table)
    condition_labels(i) = sprintf('Ch %d | %g uA', ...
        partial_table.channel(i), partial_table.current_uA(i));
    sig_labels_i = split(string(partial_table.significant_session_labels(i)), ';');
    sig_labels_i = strtrim(sig_labels_i);
    for s = 1:numel(session_labels)
        presence_mat(i, s) = any(sig_labels_i == session_labels(s));
    end
end

[~, ord] = sort(partial_table.n_sessions_significant, 'descend');
presence_mat = presence_mat(ord, :);
condition_labels = condition_labels(ord);

fig = figure('Color', 'w', 'Name', 'Condition significance across days', ...
    'Position', [80 80 1200 900]);
ax = axes(fig);
imagesc(ax, double(presence_mat));
axis(ax, 'tight');
colormap(ax, [1 1 1; 0.1 0.65 0.2]);
caxis(ax, [0 1]);
xlabel(ax, 'Session');
ylabel(ax, 'Channel | Current');
title(ax, 'Conditions significant on only some days');
set(ax, 'XTick', 1:numel(session_labels), 'XTickLabel', session_labels, ...
    'YTick', 1:numel(condition_labels), 'YTickLabel', condition_labels, ...
    'YDir', 'normal', 'XTickLabelRotation', 45);
grid(ax, 'on');

exportgraphics(fig, fullfile(save_root, 'condition_significance_presence_matrix.png'), ...
    'Resolution', 200);
close(fig);
end

function make_all_days_iou_heatmap(all_days_overlap_table, condition_significance_table, n_sessions, save_root)
if isempty(all_days_overlap_table)
    return;
end

channels = unique(all_days_overlap_table.channel);
currents = unique(all_days_overlap_table.current_uA);
heat_iou = nan(numel(channels), numel(currents));
heat_nsig = nan(numel(channels), numel(currents));

for i = 1:height(all_days_overlap_table)
    r = find(channels == all_days_overlap_table.channel(i), 1);
    c = find(currents == all_days_overlap_table.current_uA(i), 1);
    heat_iou(r, c) = all_days_overlap_table.fraction_intersection_over_union(i);

    idx_sig = condition_significance_table.channel == all_days_overlap_table.channel(i) & ...
        condition_significance_table.current_uA == all_days_overlap_table.current_uA(i);
    if any(idx_sig)
        heat_nsig(r, c) = condition_significance_table.n_sessions_significant(find(idx_sig, 1));
    end
end

fig = figure('Color', 'w', 'Name', 'All-days IoU heatmap', ...
    'Position', [100 100 1200 520]);
t = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(t);
h1 = imagesc(ax1, heat_iou, [0 1]);
set(h1, 'AlphaData', ~isnan(heat_iou));
axis(ax1, 'image');
colorbar(ax1);
xlabel(ax1, 'Current (uA)');
ylabel(ax1, 'Channel');
title(ax1, sprintf('All-days IoU across conditions | %d sessions', n_sessions));
set(ax1, 'XTick', 1:numel(currents), 'XTickLabel', string(currents), ...
    'YTick', 1:numel(channels), 'YTickLabel', string(channels), 'YDir', 'normal');

ax2 = nexttile(t);
h2 = imagesc(ax2, heat_nsig, [0 n_sessions]);
set(h2, 'AlphaData', ~isnan(heat_nsig));
axis(ax2, 'image');
colorbar(ax2);
xlabel(ax2, 'Current (uA)');
ylabel(ax2, 'Channel');
title(ax2, 'Number of significant sessions per condition');
set(ax2, 'XTick', 1:numel(currents), 'XTickLabel', string(currents), ...
    'YTick', 1:numel(channels), 'YTickLabel', string(channels), 'YDir', 'normal');

exportgraphics(fig, fullfile(save_root, 'all_days_iou_heatmap.png'), 'Resolution', 200);
close(fig);
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

function pair_figs = make_pairwise_overlap_figures(matched, session_results, clim_to_use, registration_mode)
pair_figs = struct('fig', {}, 'session_label_a', {}, 'session_label_b', {});
if numel(matched) < 2
    return;
end

for i = 1:numel(matched)-1
    for j = i+1:numel(matched)
        pair_figs(end+1) = make_single_pairwise_overlap_figure( ... %#ok<AGROW>
            matched(i), matched(j), session_results, clim_to_use, registration_mode);
    end
end
end

function pair_fig = make_single_pairwise_overlap_figure(match_a, match_b, session_results, clim_to_use, registration_mode)
sess_a = session_results(match_a.session_index);
sess_b = session_results(match_b.session_index);
cond_a = match_a.condition;
cond_b = match_b.condition;

overlap = compute_overlap_metrics( ...
    logical(cond_a.largest_cluster_mask), logical(cond_b.largest_cluster_mask), ...
    sess_a, sess_b, registration_mode);
pixel_similarity = compute_pixel_similarity( ...
    cond_a.mean_evoked_map, cond_b.mean_evoked_map, sess_a, sess_b, registration_mode);

fig = figure('Color', 'w', 'Name', sprintf('Overlap %s vs %s', match_a.session_label, match_b.session_label), ...
    'Position', [100 80 1580 760]);
t = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(t, sprintf('Ch %d | %g uA | %s vs %s', cond_a.channel, cond_a.current_uA, ...
    match_a.session_label, match_b.session_label), 'Interpreter', 'none', 'FontSize', 18, 'FontWeight', 'bold');

ax1 = nexttile(t);
plot_condition_panel(ax1, cond_a, sess_a, clim_to_use, match_a.session_label);

ax2 = nexttile(t);
plot_condition_panel(ax2, cond_b, sess_b, clim_to_use, match_b.session_label);

ax3 = nexttile(t);
plot_pairwise_overlap_panel(ax3, overlap, sess_a, sess_b, registration_mode);
title(ax3, sprintf('Overlap Map | Dice %.3f | IoU %.3f | Pixel r %.3f', ...
    overlap.dice, overlap.iou, pixel_similarity.r), 'Interpreter', 'none', 'FontSize', 14);

ax4 = nexttile(t);
plot_pairwise_summary_panel(ax4, overlap, pixel_similarity, sess_a, sess_b);

pair_fig = struct();
pair_fig.fig = fig;
pair_fig.session_label_a = match_a.session_label;
pair_fig.session_label_b = match_b.session_label;
end

function fig = make_all_days_overlap_figure(matched_active, session_results, clim_to_use, registration_mode)
group_metric = compare_condition_group(matched_active, session_results, registration_mode);
sess_ref = session_results(matched_active(1).session_index);
cond_ref = matched_active(1).condition;

[count_map, intersection_mask, union_mask, common_mask] = build_all_days_overlap_maps(matched_active, session_results, registration_mode);

fig = figure('Color', 'w', 'Name', sprintf('All-days overlap %s', matched_active(1).session_label), ...
    'Position', [100 80 1700 820]);
n_tiles = 4 + numel(matched_active);
n_cols = 3;
n_rows = ceil(n_tiles / n_cols);
t = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');
title(t, sprintf('Ch %d | %g uA | all significant sessions overlap', ...
    cond_ref.channel, cond_ref.current_uA), 'Interpreter', 'none', 'FontSize', 18, 'FontWeight', 'bold');

ax1 = nexttile(t);
plot_condition_panel(ax1, matched_active(1).condition, sess_ref, clim_to_use, matched_active(1).session_label);

ax2 = nexttile(t);
imagesc(ax2, count_map);
axis(ax2, 'image');
axis(ax2, 'off');
set(ax2, 'YDir', 'normal');
xlim(ax2, sess_ref.global_v1_xlim);
ylim(ax2, sess_ref.global_v1_ylim);
colormap(ax2, turbo(max(2, numel(matched_active) + 1)));
caxis(ax2, [0 numel(matched_active)]);
hold(ax2, 'on');
visboundaries(ax2, common_mask, 'Color', 'w', 'LineWidth', 1.0);
visboundaries(ax2, intersection_mask, 'Color', 'm', 'LineWidth', 1.6);
title(ax2, sprintf('Count map | max=%d sessions', numel(matched_active)), 'Interpreter', 'none');
colorbar(ax2);

ax3 = nexttile(t);
rgb = zeros([size(count_map), 3]);
rgb(:,:,1) = union_mask & ~intersection_mask;
rgb(:,:,2) = intersection_mask;
imagesc(ax3, rgb);
axis(ax3, 'image');
axis(ax3, 'off');
set(ax3, 'YDir', 'normal');
xlim(ax3, sess_ref.global_v1_xlim);
ylim(ax3, sess_ref.global_v1_ylim);
hold(ax3, 'on');
visboundaries(ax3, common_mask, 'Color', 'w', 'LineWidth', 1.0);
title(ax3, sprintf('Union / intersection | IoU(all)=%.3f', ...
    group_metric.fraction_intersection_over_union), 'Interpreter', 'none');

for i = 1:numel(matched_active)
    ax = nexttile(t);
    plot_condition_panel(ax, matched_active(i).condition, ...
        session_results(matched_active(i).session_index), clim_to_use, matched_active(i).session_label);
end

ax_summary = nexttile(t);
axis(ax_summary, 'off');
summary_text = {
    sprintf('Significant sessions: %d', numel(matched_active))
    sprintf('Session labels: %s', group_metric.session_labels)
    sprintf('Intersection (all): %d px', group_metric.active_pixels_intersection_all)
    sprintf('Union (all): %d px', group_metric.active_pixels_union_all)
    sprintf('IoU (all sessions): %.3f', group_metric.fraction_intersection_over_union)
    sprintf('Intersection / mean active area: %.3f', group_metric.fraction_intersection_over_mean_active)
    sprintf('Mean active pixels per session: %.1f', group_metric.active_pixels_mean_per_session)
    sprintf('Centroid mean distance: %.2f px', group_metric.mean_centroid_distance_to_group_px)
    sprintf('Centroid max distance: %.2f px', group_metric.max_centroid_distance_to_group_px)
    };
text(ax_summary, 0.02, 0.98, summary_text, 'Units', 'normalized', ...
    'FontSize', 13, 'Interpreter', 'none', 'VerticalAlignment', 'top');
xlim(ax_summary, [0 1]);
ylim(ax_summary, [0 1]);
end

function plot_condition_panel(ax, cond, sess, clim_to_use, label_text)
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
title(ax, sprintf('%s | active=%d | area=%d', label_text, cond.has_cluster, cond.largest_cluster_size), ...
    'Interpreter', 'none', 'FontSize', 14);
colorbar(ax);
end

function plot_pairwise_overlap_panel(ax, overlap, sess_a, sess_b, registration_mode)
if ~overlap.same_common_mask_size
    axis(ax, 'off');
    text(ax, 0, 1, 'Cannot plot overlap: image sizes differ.', ...
        'Interpreter', 'none', 'VerticalAlignment', 'top');
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
    return;
end

rgb = zeros([size(overlap.mask_a_common), 3]);
rgb(:,:,1) = overlap.a_only_mask;
rgb(:,:,2) = overlap.both_mask;
rgb(:,:,3) = overlap.b_only_mask;

imagesc(ax, rgb);
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'normal');

common_window = overlap.common_analysis_mask;
if any(common_window(:))
    [yy, xx] = find(common_window);
    xlim(ax, [max(1, min(xx) - 10), min(size(common_window,2), max(xx) + 10)]);
    ylim(ax, [max(1, min(yy) - 10), min(size(common_window,1), max(yy) + 10)]);
end

hold(ax, 'on');
v1_b_aligned = warp_binary_to_reference(sess_b.V1_mask, sess_a, sess_b, registration_mode);
final_b_aligned = warp_binary_to_reference(sess_b.final_mask, sess_a, sess_b, registration_mode);
visboundaries(ax, sess_a.V1_mask & v1_b_aligned, 'Color', 'w', 'LineWidth', 1.0);
visboundaries(ax, sess_a.final_mask & final_b_aligned, 'Color', 'y', 'LineWidth', 1.0);
end

function plot_pairwise_summary_panel(ax, overlap, pixel_similarity, sess_a, sess_b)
axis(ax, 'off');

summary_text = {
    sprintf('Active pixels: %d vs %d', overlap.active_pixels_a, overlap.active_pixels_b)
    sprintf('%s only: %d px', sess_a.session_label, sum(overlap.a_only_mask(:)))
    sprintf('%s only: %d px', sess_b.session_label, sum(overlap.b_only_mask(:)))
    sprintf('Intersection: %d px', overlap.intersection_pixels)
    sprintf('Union: %d px', overlap.union_pixels)
    sprintf('Dice: %.3f', overlap.dice)
    sprintf('IoU: %.3f', overlap.iou)
    sprintf('Pixel correlation r: %.3f', pixel_similarity.r)
    sprintf('Pixel correlation p: %.3g', pixel_similarity.p)
    sprintf('Common pixels: %d', pixel_similarity.n)
    sprintf('Mean absolute diff: %.4f', pixel_similarity.mean_abs_diff)
    sprintf('RMSE: %.4f', pixel_similarity.rmse)
    sprintf('Centroid distance: %.2f px', overlap.centroid_distance_px)
    };

text(ax, 0.02, 0.98, summary_text, 'Units', 'normalized', ...
    'FontSize', 14, 'Interpreter', 'none', 'VerticalAlignment', 'top');
xlim(ax, [0 1]);
ylim(ax, [0 1]);
end

function [count_map, intersection_mask, union_mask, common_mask] = build_all_days_overlap_maps(matched_active, session_results, registration_mode)
sess_ref = session_results(matched_active(1).session_index);
common_mask = sess_ref.analysis_mask;
mask_common_list = cell(1, numel(matched_active));

for i = 2:numel(matched_active)
    sess_i = session_results(matched_active(i).session_index);
    common_mask = common_mask & warp_binary_to_reference(sess_i.analysis_mask, sess_ref, sess_i, registration_mode);
end

count_map = zeros(size(common_mask));
intersection_mask = common_mask;
union_mask = false(size(common_mask));

for i = 1:numel(matched_active)
    sess_i = session_results(matched_active(i).session_index);
    mask_i = logical(matched_active(i).condition.largest_cluster_mask);
    mask_i = warp_binary_to_reference(mask_i, sess_ref, sess_i, registration_mode) & common_mask;
    mask_common_list{i} = mask_i;
    count_map = count_map + double(mask_i);
    intersection_mask = intersection_mask & mask_i;
    union_mask = union_mask | mask_i;
end
end

function similarity = compute_pixel_similarity(map_a, map_b, session_a, session_b, registration_mode)
similarity = struct('r', NaN, 'p', NaN, 'n', 0, 'mean_abs_diff', NaN, 'rmse', NaN);
if ~isequal(size(map_a), size(map_b)) || ~isequal(size(session_a.analysis_mask), size(session_b.analysis_mask))
    return;
end

map_b = warp_numeric_to_reference(map_b, session_a, session_b, registration_mode);
analysis_mask_b = warp_binary_to_reference(session_b.analysis_mask, session_a, session_b, registration_mode);
common_mask = session_a.analysis_mask & analysis_mask_b;
x = map_a(common_mask);
y = map_b(common_mask);

valid = isfinite(x) & isfinite(y);
x = x(valid);
y = y(valid);
similarity.n = numel(x);

if similarity.n == 0
    return;
end

diff_xy = x - y;
similarity.mean_abs_diff = mean(abs(diff_xy), 'omitnan');
similarity.rmse = sqrt(mean(diff_xy.^2, 'omitnan'));

if similarity.n < 3 || numel(unique(x)) < 2 || numel(unique(y)) < 2
    return;
end

[R, P] = corrcoef(x, y);
similarity.r = R(1,2);
similarity.p = P(1,2);
end

function overlap = compute_overlap_metrics(mask_a, mask_b, session_a, session_b, registration_mode)
overlap = struct();
overlap.same_image_size = isequal(size(mask_a), size(mask_b));
overlap.same_common_mask_size = false;
overlap.common_analysis_mask = [];
overlap.mask_a_common = [];
overlap.mask_b_common = [];
overlap.mask_b_aligned = [];
overlap.analysis_mask_b_aligned = [];
overlap.a_only_mask = [];
overlap.b_only_mask = [];
overlap.both_mask = [];
overlap.active_pixels_a = NaN;
overlap.active_pixels_b = NaN;
overlap.intersection_pixels = NaN;
overlap.union_pixels = NaN;
overlap.dice = NaN;
overlap.iou = NaN;
overlap.centroid_distance_px = NaN;

if ~overlap.same_image_size || ~isequal(size(session_a.analysis_mask), size(session_b.analysis_mask))
    return;
end

overlap.same_common_mask_size = true;
overlap.analysis_mask_b_aligned = warp_binary_to_reference(session_b.analysis_mask, session_a, session_b, registration_mode);
overlap.common_analysis_mask = session_a.analysis_mask & overlap.analysis_mask_b_aligned;
overlap.mask_a_common = logical(mask_a) & overlap.common_analysis_mask;
overlap.mask_b_aligned = warp_binary_to_reference(mask_b, session_a, session_b, registration_mode);
overlap.mask_b_common = overlap.mask_b_aligned & overlap.common_analysis_mask;
overlap.a_only_mask = overlap.mask_a_common & ~overlap.mask_b_common;
overlap.b_only_mask = overlap.mask_b_common & ~overlap.mask_a_common;
overlap.both_mask = overlap.mask_a_common & overlap.mask_b_common;
overlap.active_pixels_a = sum(overlap.mask_a_common(:));
overlap.active_pixels_b = sum(overlap.mask_b_common(:));
overlap.intersection_pixels = sum(overlap.both_mask(:));
union_mask = overlap.mask_a_common | overlap.mask_b_common;
overlap.union_pixels = sum(union_mask(:));

if (overlap.active_pixels_a + overlap.active_pixels_b) > 0
    overlap.dice = (2 * overlap.intersection_pixels) / (overlap.active_pixels_a + overlap.active_pixels_b);
end

if overlap.union_pixels > 0
    overlap.iou = overlap.intersection_pixels / overlap.union_pixels;
end

[centroid_a, centroid_b] = overlap_centroids(overlap.mask_a_common, overlap.mask_b_common);
if all(isfinite([centroid_a, centroid_b]))
    overlap.centroid_distance_px = norm(centroid_a - centroid_b);
end
end

function [centroid_a, centroid_b] = overlap_centroids(mask_a, mask_b)
centroid_a = [NaN NaN];
centroid_b = [NaN NaN];

if any(mask_a(:))
    [yy, xx] = find(mask_a);
    centroid_a = [mean(xx, 'omitnan'), mean(yy, 'omitnan')];
end

if any(mask_b(:))
    [yy, xx] = find(mask_b);
    centroid_b = [mean(xx, 'omitnan'), mean(yy, 'omitnan')];
end
end

function mask_out = warp_binary_to_reference(mask_in, session_ref, session_mov, registration_mode)
if strcmpi(registration_mode, 'none')
    mask_out = logical(mask_in);
    return;
end

[dx, dy] = estimate_final_mask_translation(session_ref.final_mask, session_mov.final_mask, registration_mode);
mask_out = imtranslate(single(mask_in), [dx dy], 'OutputView', 'same', 'FillValues', 0) > 0.5;
end

function map_out = warp_numeric_to_reference(map_in, session_ref, session_mov, registration_mode)
if strcmpi(registration_mode, 'none')
    map_out = map_in;
    return;
end

[dx, dy] = estimate_final_mask_translation(session_ref.final_mask, session_mov.final_mask, registration_mode);
valid_in = isfinite(map_in);
map_filled = map_in;
map_filled(~valid_in) = 0;

map_shifted = imtranslate(map_filled, [dx dy], 'OutputView', 'same', 'FillValues', 0);
valid_shifted = imtranslate(single(valid_in), [dx dy], 'OutputView', 'same', 'FillValues', 0) > 0.5;

map_out = map_shifted;
map_out(~valid_shifted) = NaN;
end

function [dx, dy] = estimate_final_mask_translation(final_mask_ref, final_mask_mov, registration_mode)
switch lower(registration_mode)
    case 'none'
        dx = 0;
        dy = 0;
    case 'final_mask_centroid_translation'
        c_ref = binary_mask_centroid(final_mask_ref);
        c_mov = binary_mask_centroid(final_mask_mov);
        dx = c_ref(1) - c_mov(1);
        dy = c_ref(2) - c_mov(2);
    otherwise
        error('Unsupported registration_mode: %s', registration_mode);
end
end

function centroid_xy = binary_mask_centroid(mask_in)
centroid_xy = [NaN NaN];
if any(mask_in(:))
    [yy, xx] = find(mask_in);
    centroid_xy = [mean(xx, 'omitnan'), mean(yy, 'omitnan')];
end
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
