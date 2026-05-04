%% summarize_v1_response_centroids_from_h5.m
% Summarize spatial consistency of trial-wise V1 response centroids.
%
% Uses the HDF5 exported by export_v1_trial_response_arrays_h5.m and:
%   1. computes one response centroid per trial from the binned V1 response map
%   2. filters weak trials by peak dF/F threshold
%   3. groups trials by (stim_channel, current_uA)
%   4. summarizes centroid spread and distance to the group centroid
%   5. writes a per-trial CSV and a per-condition summary CSV

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
h5_file = "";

peak_dff_threshold = 0.03;
min_trials_per_group = 3;
centroid_weight_mode = 'positive_only';   % positive_only | all_finite
save_png = true;
save_mat = true;

%% -------------------------
% LOAD HDF5
% -------------------------
if strlength(h5_file) == 0
    [fn, fp] = uigetfile('*.h5', 'Select V1 trial response HDF5');
    if isequal(fn, 0)
        error('No HDF5 file selected.');
    end
    h5_file = fullfile(fp, fn);
end

channels = double(h5read(h5_file, '/channel'));
currents = double(h5read(h5_file, '/current_uA'));
trial_maps = double(h5read(h5_file, '/v1_response_grid'));   % [n_trials, H, W]
v1_mask = logical(h5read(h5_file, '/v1_mask'));

assert(ndims(trial_maps) == 3, 'Expected /v1_response_grid to be [n_trials, H, W].');
n_trials = size(trial_maps, 1);
assert(numel(channels) == n_trials && numel(currents) == n_trials, ...
    'HDF5 datasets have inconsistent trial counts.');

fprintf('Loaded HDF5:\n  %s\n', h5_file);
fprintf('Trials: %d\n', n_trials);
fprintf('Grid size: [%d %d]\n', size(trial_maps, 2), size(trial_maps, 3));

%% -------------------------
% PER-TRIAL CENTROIDS
% -------------------------
[yy, xx] = ndgrid(1:size(v1_mask, 1), 1:size(v1_mask, 2));

trial_table = table('Size', [n_trials 10], ...
    'VariableTypes', {'double','double','double','double','double','double','double','double','logical','string'}, ...
    'VariableNames', {'trial_index','stim_channel','current_uA','peak_dff', ...
    'centroid_x','centroid_y','centroid_valid','centroid_weight_sum', ...
    'pass_peak_threshold','condition_label'});

for i = 1:n_trials
    map_i = squeeze(trial_maps(i, :, :));
    map_i(~v1_mask) = NaN;

    peak_dff = max(map_i(:), [], 'omitnan');
    [cx, cy, valid_centroid, weight_sum] = compute_weighted_centroid(map_i, xx, yy, centroid_weight_mode);

    trial_table.trial_index(i) = i;
    trial_table.stim_channel(i) = channels(i);
    trial_table.current_uA(i) = currents(i);
    trial_table.peak_dff(i) = peak_dff;
    trial_table.centroid_x(i) = cx;
    trial_table.centroid_y(i) = cy;
    trial_table.centroid_valid(i) = double(valid_centroid);
    trial_table.centroid_weight_sum(i) = weight_sum;
    trial_table.pass_peak_threshold(i) = isfinite(peak_dff) && peak_dff > peak_dff_threshold && valid_centroid;
    trial_table.condition_label(i) = string(sprintf('Ch %d | %g uA', channels(i), currents(i)));
end

Tf = trial_table(trial_table.pass_peak_threshold, :);
assert(~isempty(Tf), 'No trials remain after centroid validity and peak dF/F threshold filtering.');

fprintf('Trials after peak_dff > %.3f and valid centroid filter: %d\n', ...
    peak_dff_threshold, height(Tf));

%% -------------------------
% GROUP BY CHANNEL / CURRENT
% -------------------------
group_keys = [double(Tf.stim_channel), double(Tf.current_uA)];
[uniq_groups, ~, grp] = unique(group_keys, 'rows', 'stable');
n_groups = size(uniq_groups, 1);

summary_table = table('Size', [n_groups 13], ...
    'VariableTypes', {'double','double','double','double','double','double','double', ...
    'double','double','double','double','double','double'}, ...
    'VariableNames', {'stim_channel','current_uA','n_trials', ...
    'mean_centroid_x','mean_centroid_y', ...
    'std_centroid_x','std_centroid_y', ...
    'mean_distance_to_group_centroid_px','median_distance_to_group_centroid_px', ...
    'std_distance_to_group_centroid_px', ...
    'mean_peak_dff','std_peak_dff','peak_dff_threshold'});

Tf.distance_to_group_centroid_px = nan(height(Tf), 1);

for g = 1:n_groups
    idx = grp == g;
    cx = double(Tf.centroid_x(idx));
    cy = double(Tf.centroid_y(idx));
    pk = double(Tf.peak_dff(idx));

    mean_cx = mean(cx, 'omitnan');
    mean_cy = mean(cy, 'omitnan');
    dist = hypot(cx - mean_cx, cy - mean_cy);
    Tf.distance_to_group_centroid_px(idx) = dist;

    summary_table.stim_channel(g) = uniq_groups(g, 1);
    summary_table.current_uA(g) = uniq_groups(g, 2);
    summary_table.n_trials(g) = sum(idx);
    summary_table.mean_centroid_x(g) = mean_cx;
    summary_table.mean_centroid_y(g) = mean_cy;
    summary_table.std_centroid_x(g) = std(cx, 0, 'omitnan');
    summary_table.std_centroid_y(g) = std(cy, 0, 'omitnan');
    summary_table.mean_distance_to_group_centroid_px(g) = mean(dist, 'omitnan');
    summary_table.median_distance_to_group_centroid_px(g) = median(dist, 'omitnan');
    summary_table.std_distance_to_group_centroid_px(g) = std(dist, 0, 'omitnan');
    summary_table.mean_peak_dff(g) = mean(pk, 'omitnan');
    summary_table.std_peak_dff(g) = std(pk, 0, 'omitnan');
    summary_table.peak_dff_threshold(g) = peak_dff_threshold;
end

summary_table = sortrows(summary_table, {'stim_channel','current_uA'});
summary_table_filtered = summary_table(summary_table.n_trials >= min_trials_per_group, :);

fprintf('Groups total: %d\n', height(summary_table));
fprintf('Groups with n >= %d: %d\n', min_trials_per_group, height(summary_table_filtered));

%% -------------------------
% OUTPUT
% -------------------------
[h5_dir, h5_base, ~] = fileparts(h5_file);
out_dir = fullfile(h5_dir, 'v1_centroid_consistency_summary');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

trial_csv = fullfile(out_dir, sprintf('%s_trial_centroids.csv', h5_base));
summary_csv = fullfile(out_dir, sprintf('%s_centroid_consistency_summary.csv', h5_base));
writetable(Tf, trial_csv);
writetable(summary_table_filtered, summary_csv);

fprintf('\nCSV exports complete\n');
fprintf('  Trial centroids: %s\n', trial_csv);
fprintf('  Summary: %s\n', summary_csv);

%% -------------------------
% PLOTS
% -------------------------
if ~isempty(summary_table_filtered)
    channels_u = unique(summary_table_filtered.stim_channel);
    currents_u = unique(summary_table_filtered.current_uA);
    heat_mean_dist = nan(numel(channels_u), numel(currents_u));
    heat_std_dist = nan(numel(channels_u), numel(currents_u));

    for i = 1:height(summary_table_filtered)
        r = find(channels_u == summary_table_filtered.stim_channel(i), 1);
        c = find(currents_u == summary_table_filtered.current_uA(i), 1);
        heat_mean_dist(r, c) = summary_table_filtered.mean_distance_to_group_centroid_px(i);
        heat_std_dist(r, c) = summary_table_filtered.std_distance_to_group_centroid_px(i);
    end

    fig1 = figure('Color', 'w', 'Name', 'Centroid consistency heatmaps');
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    h1 = imagesc(ax1, heat_mean_dist);
    set(h1, 'AlphaData', ~isnan(heat_mean_dist));
    axis(ax1, 'image');
    colorbar(ax1);
    title(ax1, 'Mean centroid distance (px)');
    xlabel(ax1, 'Current (uA)');
    ylabel(ax1, 'Channel');
    set(ax1, 'XTick', 1:numel(currents_u), 'XTickLabel', string(currents_u), ...
        'YTick', 1:numel(channels_u), 'YTickLabel', string(channels_u), 'YDir', 'normal');

    ax2 = nexttile;
    h2 = imagesc(ax2, heat_std_dist);
    set(h2, 'AlphaData', ~isnan(heat_std_dist));
    axis(ax2, 'image');
    colorbar(ax2);
    title(ax2, 'SD of centroid distance (px)');
    xlabel(ax2, 'Current (uA)');
    ylabel(ax2, 'Channel');
    set(ax2, 'XTick', 1:numel(currents_u), 'XTickLabel', string(currents_u), ...
        'YTick', 1:numel(channels_u), 'YTickLabel', string(channels_u), 'YDir', 'normal');

    if save_png
        saveas(fig1, fullfile(out_dir, 'centroid_consistency_heatmaps.png'));
    end

    fig2 = figure('Color', 'w', 'Name', 'Trial centroid scatter');
    tiledlayout(numel(channels_u), 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    for ch_i = 1:numel(channels_u)
        ax = nexttile;
        hold(ax, 'on');
        ch = channels_u(ch_i);
        for cur_i = 1:numel(currents_u)
            cur = currents_u(cur_i);
            idx = Tf.stim_channel == ch & Tf.current_uA == cur;
            if ~any(idx)
                continue;
            end
            scatter(ax, Tf.centroid_x(idx), Tf.centroid_y(idx), 30, Tf.peak_dff(idx), 'filled', ...
                'DisplayName', sprintf('%g uA', cur));
        end
        set(ax, 'YDir', 'reverse');
        axis(ax, 'image');
        grid(ax, 'on');
        xlabel(ax, 'Centroid x (binned px)');
        ylabel(ax, 'Centroid y (binned px)');
        title(ax, sprintf('Trial centroids | Ch %d', ch));
        legend(ax, 'Location', 'bestoutside');
        colorbar(ax);
    end

    if save_png
        saveas(fig2, fullfile(out_dir, 'trial_centroid_scatter_by_channel.png'));
    end
end

%% -------------------------
% SAVE MAT
% -------------------------
if save_mat
    save(fullfile(out_dir, sprintf('%s_centroid_consistency_summary.mat', h5_base)), ...
        'trial_table', 'Tf', 'summary_table', 'summary_table_filtered', ...
        'peak_dff_threshold', 'min_trials_per_group', 'centroid_weight_mode', ...
        'v1_mask', '-v7.3');
end

%% -------------------------
% LOCAL FUNCTIONS
% -------------------------
function [cx, cy, valid_centroid, weight_sum] = compute_weighted_centroid(map_i, xx, yy, weight_mode)
switch lower(weight_mode)
    case 'positive_only'
        w = map_i;
        w(~isfinite(w)) = NaN;
        w(w < 0) = 0;
    case 'all_finite'
        w = map_i;
        w(~isfinite(w)) = NaN;
    otherwise
        error('Unknown centroid_weight_mode "%s".', weight_mode);
end

valid = isfinite(w);
if ~any(valid(:))
    cx = NaN;
    cy = NaN;
    valid_centroid = false;
    weight_sum = NaN;
    return;
end

wv = w(valid);
xv = xx(valid);
yv = yy(valid);
weight_sum = sum(wv, 'omitnan');

if ~isfinite(weight_sum) || weight_sum == 0
    cx = NaN;
    cy = NaN;
    valid_centroid = false;
    return;
end

cx = sum(xv .* wv, 'omitnan') / weight_sum;
cy = sum(yv .* wv, 'omitnan') / weight_sum;
valid_centroid = isfinite(cx) && isfinite(cy);
end
