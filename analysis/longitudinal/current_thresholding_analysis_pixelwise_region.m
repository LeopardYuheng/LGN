%% current_thresholding_analysis_pixelwise_region.m
% Pixelwise threshold analysis with cluster-defined activation regions.

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
response_sec = [0 1.0]; % Used when computing the mean evoked ΔF/F map
alpha = 0.05;  %A pixel is considered “active” if its response is unlikely under baseline noise (p < 0.05).
min_cluster_size = 100; % Removes noise / isolated pixels that pass threshold by chance
conn = 8;

use_analysis_mask_for_stats = true;
mask_outside_for_display = true;
use_shared_clim = true;
shared_clim = [];

%% -------------------------
% LOAD DAY POINTER
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer');
if isequal(fn, 0), error('No file selected.'); end

S = load(fullfile(fp, fn));
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

%% -------------------------
% RESOLVE INPUT PATHS
% -------------------------
dataset_root = day_pointer.meta.dataset_root;
day_setup_file = resolve_file_path(day_pointer.meta.day_setup_file_rel, dataset_root, 'file');
img_dir = resolve_file_path(day_pointer.meta.img_dir_rel, dataset_root, 'dir');

fprintf('Resolved day_setup_file:\n  %s\n', day_setup_file);
fprintf('Resolved img_dir:\n  %s\n', img_dir);

%% -------------------------
% LOAD DAY SETUP
% -------------------------
D = load(day_setup_file);
assert(isfield(D, 'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;

azi_stim = day_setup.retino_align.azi_stim;
alt_stim = day_setup.retino_align.alt_stim;

[H, W] = size(analysis_mask);

%% -------------------------
% LOAD TIFF FILES
% -------------------------
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

%% -------------------------
% TIMING FROM DAY POINTER
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

%% -------------------------
% RECONSTRUCT PER-TRIAL VECTORS
% -------------------------
[frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(day_pointer.entries);

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);

frame_idx = frame_idx(valid);
channels = channels(valid);
currents = currents(valid);
trial_index = trial_index(valid);

unique_channels = unique(channels);

%% -------------------------
% GLOBAL DISPLAY LIMITS
% -------------------------
pad_xy = 10;
[y_v1, x_v1] = find(V1_mask);
global_v1_xlim = [max(1, min(x_v1) - pad_xy), min(size(V1_mask,2), max(x_v1) + pad_xy)];
global_v1_ylim = [max(1, min(y_v1) - pad_xy), min(size(V1_mask,1), max(y_v1) + pad_xy)];

%% -------------------------
% MAIN ANALYSIS
% -------------------------
results = struct( ...
    'channel', {}, ...
    'threshold_uA', {}, ...
    'anchor_current_uA', {}, ...
    'peak_xy', {}, ...
    'azi', {}, ...
    'alt', {}, ...
    'current_summary', {}, ...
    'anchor_mean_map', {}, ...
    'threshold_cluster_mask', {}, ...
    'threshold_mean_map', {}, ...
    'threshold_peak_xy', {} );

all_anchor_vals = [];

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

    current_summary = struct( ...
        'current_uA', {}, 'n_trials', {}, 'mean_evoked_map', {}, 'p_map', {}, ...
        'sig_pixel_mask', {}, 'sig_cluster_mask', {}, 'largest_cluster_mask', {}, ...
        'largest_cluster_size', {}, 'fraction_activated', {}, ...
        'mean_cluster_effect', {}, 'has_cluster', {} );

    threshold_uA = NaN;
    anchor_current_uA = max(currents_ch(currents_ch > 0));
    if isempty(anchor_current_uA), anchor_current_uA = 0; end
    anchor_mean_map = [];
    peak_xy = [NaN NaN];
    azi_val = NaN;
    alt_val = NaN;
    threshold_cluster_mask = false(H, W);
    threshold_mean_map = [];
    threshold_peak_xy = [NaN NaN];

    for cur_i = 1:numel(currents_ch)
        cur = currents_ch(cur_i);
        if cur == 0, continue; end

        idx_cur = idx_ch & currents == cur;
        cur_maps = build_trial_response_map_stack(frame_idx(idx_cur), img_dir, image_files, ...
            full_win, baseline_idx, response_idx, H, W);
        if isempty(cur_maps), continue; end

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
        if ~has_cluster, mean_cluster_effect = NaN; end

        if cur == anchor_current_uA
            anchor_mean_map = mean_evoked_map;
            all_anchor_vals = [all_anchor_vals; mean_evoked_map(isfinite(mean_evoked_map))]; %#ok<AGROW>
        end

        if isnan(threshold_uA) && has_cluster
            threshold_uA = cur;
            threshold_cluster_mask = largest_cluster_mask;
            threshold_mean_map = mean_evoked_map;
            if mask_outside_for_display
                threshold_mean_map(~final_mask) = NaN;
            end
        end

        current_summary(end+1).current_uA = cur;
        current_summary(end).n_trials = size(cur_maps, 3);
        current_summary(end).mean_evoked_map = mean_evoked_map;
        current_summary(end).p_map = p_map;
        current_summary(end).sig_pixel_mask = sig_pixel_mask;
        current_summary(end).sig_cluster_mask = sig_cluster_mask;
        current_summary(end).largest_cluster_mask = largest_cluster_mask;
        current_summary(end).largest_cluster_size = largest_cluster_size;
        current_summary(end).fraction_activated = fraction_activated;
        current_summary(end).mean_cluster_effect = mean_cluster_effect;
        current_summary(end).has_cluster = has_cluster;
    end

    if isempty(anchor_mean_map)
        anchor_mean_map = mean(base_maps, 3, 'omitnan');
    end
    if mask_outside_for_display
        anchor_mean_map(~final_mask) = NaN;
    end

    if ~isempty(current_summary) && ~isnan(threshold_uA)
        idx_thr = find([current_summary.current_uA] == threshold_uA, 1);
        region_for_peak = current_summary(idx_thr).largest_cluster_mask;
        search_map = anchor_mean_map;
        search_map(~region_for_peak) = NaN;
        if any(isfinite(search_map(:)))
            [~, idx_max] = max(search_map(:));
            [y_peak, x_peak] = ind2sub(size(search_map), idx_max);
            peak_xy = [x_peak, y_peak];
            threshold_peak_xy = [x_peak, y_peak];
            azi_val = azi_stim(y_peak, x_peak);
            alt_val = alt_stim(y_peak, x_peak);
        end
    end

    results(end+1).channel = ch;
    results(end).threshold_uA = threshold_uA;
    results(end).anchor_current_uA = anchor_current_uA;
    results(end).peak_xy = peak_xy;
    results(end).azi = azi_val;
    results(end).alt = alt_val;
    results(end).current_summary = current_summary;
    results(end).anchor_mean_map = anchor_mean_map;
    results(end).threshold_cluster_mask = threshold_cluster_mask;
    results(end).threshold_mean_map = threshold_mean_map;
    results(end).threshold_peak_xy = threshold_peak_xy;
end

%% -------------------------
% OUTPUT DIRECTORY
% -------------------------
save_dir = fullfile(img_dir, '..', 'analysis', 'pixelwise_threshold_region_analysis');
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

%% -------------------------
% DISPLAY LIMITS
% -------------------------
if use_shared_clim && ~isempty(shared_clim)
    clim_to_use = shared_clim;
else
    q = quantile(all_anchor_vals, [0.02 0.98]);
    m = max(abs(q));
    if ~isfinite(m) || m == 0, m = 0.01; end
    clim_to_use = [-m m];
end

%% -------------------------
% PLOT PER-CHANNEL THRESHOLD SUMMARIES
% -------------------------
for res_idx = 1:numel(results)
    ch = results(res_idx).channel;

    fig_summary = figure('Color', 'w', 'Name', sprintf('Pixelwise threshold summary ch%d', ch), ...
        'Position', [80 80 1300 500]);

    subplot(1,3,1);
    imagesc(results(res_idx).anchor_mean_map); axis image off; set(gca,'YDir','normal');
    xlim(global_v1_xlim); ylim(global_v1_ylim); colormap(gca, parula); caxis(clim_to_use); hold on;
    visboundaries(V1_mask, 'Color', 'w', 'LineWidth', 1.0);
    visboundaries(final_mask, 'Color', 'y', 'LineWidth', 1.0);
    title(sprintf('Anchor mean map\nCh %d | %g uA', ch, results(res_idx).anchor_current_uA), 'Interpreter', 'none');
    colorbar;

    subplot(1,3,2);
    if ~isempty(results(res_idx).threshold_mean_map)
        M = results(res_idx).threshold_mean_map;
    else
        M = results(res_idx).anchor_mean_map;
    end
    imagesc(M); axis image off; set(gca,'YDir','normal');
    xlim(global_v1_xlim); ylim(global_v1_ylim); colormap(gca, parula); caxis(clim_to_use); hold on;
    visboundaries(V1_mask, 'Color', 'w', 'LineWidth', 1.0);
    visboundaries(final_mask, 'Color', 'y', 'LineWidth', 1.0);
    if any(results(res_idx).threshold_cluster_mask(:))
        visboundaries(results(res_idx).threshold_cluster_mask & final_mask, 'Color', 'r', 'LineWidth', 1.8);
    end
    title(sprintf('Threshold region\nCh %d | %g uA', ch, results(res_idx).threshold_uA), 'Interpreter', 'none');
    colorbar;

    subplot(1,3,3);
    cur_vals = [results(res_idx).current_summary.current_uA];
    has_cluster = double([results(res_idx).current_summary.has_cluster]);
    largest_cluster = [results(res_idx).current_summary.largest_cluster_size];
    yyaxis left; plot(cur_vals, has_cluster, '-o', 'LineWidth', 1.5); ylabel('Has significant region'); ylim([-0.05 1.05]);
    yyaxis right; plot(cur_vals, largest_cluster, '-s', 'LineWidth', 1.5); ylabel('Largest cluster size');
    xlabel('Current (uA)'); title(sprintf('Threshold = %g uA', results(res_idx).threshold_uA)); grid on;

    exportgraphics(fig_summary, fullfile(save_dir, sprintf('channel_%d_pixelwise_threshold_summary.png', ch)), 'Resolution', 200);

    activated_idx = find([results(res_idx).current_summary.has_cluster]);
    if ~isempty(activated_idx)
        fig_multi = figure('Color', 'w', 'Name', sprintf('Pixelwise activated currents ch%d', ch), ...
            'Position', [100 100 760 520]);
        ax_cur = axes(fig_multi);
        imagesc(ax_cur, results(res_idx).anchor_mean_map);
        axis(ax_cur, 'image');
        axis(ax_cur, 'off');
        set(ax_cur, 'YDir', 'normal');
        xlim(ax_cur, global_v1_xlim);
        ylim(ax_cur, global_v1_ylim);
        colormap(ax_cur, parula);
        caxis(ax_cur, clim_to_use);
        hold(ax_cur, 'on');
        visboundaries(ax_cur, V1_mask, 'Color', 'w', 'LineWidth', 1.0);
        visboundaries(ax_cur, final_mask, 'Color', 'y', 'LineWidth', 1.0);

        cmap_cur = lines(numel(activated_idx));
        legend_handles = gobjects(0);
        legend_labels = {};
        for a_i = 1:numel(activated_idx)
            cs = results(res_idx).current_summary(activated_idx(a_i));
            if any(cs.sig_cluster_mask(:))
                B = bwboundaries(cs.sig_cluster_mask & final_mask, conn, 'noholes');
                for b_i = 1:numel(B)
                    boundary = B{b_i};
                    plot(ax_cur, boundary(:,2), boundary(:,1), '-', ...
                        'Color', cmap_cur(a_i,:), 'LineWidth', 2);
                end
            end
            legend_handles(end+1) = plot(ax_cur, nan, nan, '-', ...
                'Color', cmap_cur(a_i,:), 'LineWidth', 2);
            legend_labels{end+1} = sprintf('%g uA', cs.current_uA); %#ok<AGROW>
        end
        title(ax_cur, sprintf('Ch %d | activated currents overlay', ch), 'Interpreter', 'none');
        if ~isempty(legend_handles)
            legend(ax_cur, legend_handles, legend_labels, 'Location', 'eastoutside', 'Box', 'off');
        end
        colorbar(ax_cur);
        exportgraphics(fig_multi, fullfile(save_dir, sprintf('channel_%d_pixelwise_activated_currents.png', ch)), 'Resolution', 200);
    end
end

%% -------------------------
% THRESHOLD BORDER SUMMARY
% -------------------------
valid_thr = arrayfun(@(r) isfinite(r.threshold_uA) && any(r.threshold_cluster_mask(:)), results);
if any(valid_thr)
    valid_results = results(valid_thr);
    threshold_levels = sort(unique([valid_results.threshold_uA]));
    n_levels = numel(threshold_levels);
    n_cols = min(3, n_levels);
    n_rows = ceil(n_levels / n_cols);
    fig_vf = figure('Color', 'w', 'Name', 'Pixelwise threshold borders by current');
    tiledlayout(n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');
    cmap = lines(max(numel(valid_results),1));

    for lvl_i = 1:n_levels
        thr = threshold_levels(lvl_i);
        ax = nexttile;
        imagesc(ax, double(final_mask)); axis(ax, 'image'); axis(ax, 'off'); set(ax, 'YDir', 'normal');
        xlim(ax, global_v1_xlim); ylim(ax, global_v1_ylim); colormap(ax, gray); caxis(ax, [0 1]); hold(ax, 'on');
        visboundaries(ax, V1_mask, 'Color', 'w', 'LineWidth', 1.2);
        visboundaries(ax, final_mask, 'Color', 'y', 'LineWidth', 1.2);

        idx_thr = find([valid_results.threshold_uA] == thr);
        legend_handles = gobjects(0);
        legend_labels = {};
        for j = 1:numel(idx_thr)
            r_idx = idx_thr(j);
            mask_i = valid_results(r_idx).threshold_cluster_mask & final_mask;
            B = bwboundaries(mask_i, conn, 'noholes');
            for b_i = 1:numel(B)
                boundary = B{b_i};
                patch(ax, boundary(:,2), boundary(:,1), cmap(r_idx,:), ...
                    'FaceAlpha', 0.12, 'EdgeColor', cmap(r_idx,:), 'LineWidth', 2);
            end
            legend_handles(end+1) = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cmap(r_idx,:), ...
                'MarkerEdgeColor', 'k', 'MarkerSize', 6, 'LineStyle', 'none');
            legend_labels{end+1} = sprintf('Ch %d', valid_results(r_idx).channel); %#ok<AGROW>
        end
        title(ax, sprintf('Threshold %g uA', thr), 'Interpreter', 'none');
        if ~isempty(legend_handles)
            legend(ax, legend_handles, legend_labels, 'Location', 'southoutside', 'Box', 'off');
        end
    end

    exportgraphics(fig_vf, fullfile(save_dir, 'pixelwise_threshold_border_summary.png'), 'Resolution', 200);
end

%% -------------------------
% ALL SIGNIFICANT ACTIVATIONS BY CURRENT
% -------------------------
all_sig_currents = [];
for r_i = 1:numel(results)
    if isempty(results(r_i).current_summary)
        continue;
    end
    active_idx = find([results(r_i).current_summary.has_cluster]);
    if ~isempty(active_idx)
        all_sig_currents = [all_sig_currents, [results(r_i).current_summary(active_idx).current_uA]]; %#ok<AGROW>
    end
end

all_sig_currents = sort(unique(all_sig_currents));
if ~isempty(all_sig_currents)
    n_levels = numel(all_sig_currents);
    n_cols = min(3, n_levels);
    n_rows = ceil(n_levels / n_cols);
    fig_all = figure('Color', 'w', 'Name', 'All significant activations by current');
    tiledlayout(n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for lvl_i = 1:n_levels
        cur = all_sig_currents(lvl_i);
        ax = nexttile;
        imagesc(ax, double(final_mask));
        axis(ax, 'image');
        axis(ax, 'off');
        set(ax, 'YDir', 'normal');
        xlim(ax, global_v1_xlim);
        ylim(ax, global_v1_ylim);
        colormap(ax, gray);
        caxis(ax, [0 1]);
        hold(ax, 'on');
        visboundaries(ax, V1_mask, 'Color', 'w', 'LineWidth', 1.2);
        visboundaries(ax, final_mask, 'Color', 'y', 'LineWidth', 1.2);

        active_channels = [];
        for r_i = 1:numel(results)
            if isempty(results(r_i).current_summary)
                continue;
            end
            idx_cur = find([results(r_i).current_summary.current_uA] == cur & [results(r_i).current_summary.has_cluster], 1);
            if ~isempty(idx_cur)
                active_channels(end+1) = r_i; %#ok<AGROW>
            end
        end

        cmap_all = lines(max(1, numel(active_channels)));
        legend_handles = gobjects(0);
        legend_labels = {};
        for a_i = 1:numel(active_channels)
            r_i = active_channels(a_i);
            idx_cur = find([results(r_i).current_summary.current_uA] == cur & [results(r_i).current_summary.has_cluster], 1);
            cs = results(r_i).current_summary(idx_cur);
            B = bwboundaries(cs.sig_cluster_mask & final_mask, conn, 'noholes');
            for b_i = 1:numel(B)
                boundary = B{b_i};
                plot(ax, boundary(:,2), boundary(:,1), '-', ...
                    'Color', cmap_all(a_i,:), 'LineWidth', 2);
            end
            legend_handles(end+1) = plot(ax, nan, nan, '-', ...
                'Color', cmap_all(a_i,:), 'LineWidth', 2);
            legend_labels{end+1} = sprintf('Ch %d', results(r_i).channel); %#ok<AGROW>
        end

        title(ax, sprintf('%g uA | all significant channels', cur), 'Interpreter', 'none');
        if ~isempty(legend_handles)
            legend(ax, legend_handles, legend_labels, 'Location', 'southoutside', 'Box', 'off');
        end
    end

    exportgraphics(fig_all, fullfile(save_dir, 'pixelwise_all_significant_activations_by_current.png'), 'Resolution', 200);
end

%% -------------------------
% SAVE RESULTS
% -------------------------
save_file = fullfile(save_dir, 'pixelwise_threshold_region_results.mat');
save(save_file, 'results', 'alpha', 'min_cluster_size', 'conn', ...
    'response_sec', 'pre_sec', 'post_sec', 'Fs', 'analysis_mask', 'final_mask', ...
    'V1_mask', 'global_v1_xlim', 'global_v1_ylim', '-v7.3');

fprintf('\nSaved results to:\n  %s\n', save_file);

%% =========================
% LOCAL FUNCTIONS
% =========================
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

function [frame_idx, channels, currents, trial_index] = unpack_day_pointer_entries(entries)
frame_idx = [];
channels = [];
currents = [];
trial_index = [];

for i = 1:numel(entries)
    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i = numel(onset_i);
    frame_idx = [frame_idx; onset_i]; %#ok<AGROW>
    channels = [channels; repmat(double(entries(i).stim_channel), n_i, 1)]; %#ok<AGROW>
    currents = [currents; repmat(double(entries(i).current_uA), n_i, 1)]; %#ok<AGROW>
    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_index = [trial_index; double(entries(i).trial_index(:))]; %#ok<AGROW>
    else
        trial_index = [trial_index; nan(n_i, 1)]; %#ok<AGROW>
    end
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
