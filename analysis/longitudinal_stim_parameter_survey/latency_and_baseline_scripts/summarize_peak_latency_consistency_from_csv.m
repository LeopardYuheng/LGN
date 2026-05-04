%% summarize_peak_latency_consistency_from_csv.m
% Summarize peak-latency consistency across channel/current conditions.
%
% This script:
%   1. loads the per-trial CSV from export_v1_trial_latency_table_csv.m
%   2. keeps only trials with ROI mean dF/F > peak_dff_threshold
%   3. groups trials by (stim_channel, current_uA)
%   4. computes latency consistency metrics per group
%   5. exports a summary CSV and plots including heatmaps and trial-level box/scatter views

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
latency_csv_file = "C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-03-29\analysis\v1_trial_latency_table\LGN11_20260329_day_pointer_v1_trial_latency_table.csv";

peak_dff_threshold = 0.04;
boxplot_peak_dff_cap = 0.15;
within_window_sec = 0.2;
min_trials_per_group = 10;

save_png = true;
save_mat = true;

%% -------------------------
% LOAD CSV
% -------------------------
if strlength(latency_csv_file) == 0
    [fn, fp] = uigetfile('*.csv', 'Select v1 trial latency table CSV');
    if isequal(fn, 0)
        error('No CSV selected.');
    end
    latency_csv_file = fullfile(fp, fn);
end

T = readtable(latency_csv_file);
assert(~isempty(T), 'Selected CSV is empty.');

required_vars = { ...
    'stim_channel', 'current_uA', ...
    'roi_mean_dff', 'peak_latency_s', ...
    'late_flag', 'video_label'};
for i = 1:numel(required_vars)
    assert(ismember(required_vars{i}, T.Properties.VariableNames), ...
        'CSV missing required column "%s".', required_vars{i});
end

fprintf('Loaded latency CSV:\n  %s\n', latency_csv_file);
fprintf('Rows in CSV: %d\n', height(T));

%% -------------------------
% FILTER TRIALS
% -------------------------
valid = isfinite(T.peak_dff) & isfinite(T.peak_latency_s) & ...
    isfinite(T.roi_mean_dff) & isfinite(T.stim_channel) & isfinite(T.current_uA);
valid = valid & T.roi_mean_dff > peak_dff_threshold;

Tf = T(valid, :);
assert(~isempty(Tf), 'No trials remain after applying peak_dff threshold.');

fprintf('Trials after roi_mean_dff > %.3f filter: %d\n', peak_dff_threshold, height(Tf));

%% -------------------------
% GROUP BY CHANNEL / CURRENT
% -------------------------
group_keys = [double(Tf.stim_channel(:)), double(Tf.current_uA(:))];
[uniq_groups, ~, grp] = unique(group_keys, 'rows', 'stable');
n_groups = size(uniq_groups, 1);

summary_table = table('Size', [n_groups 14], ...
    'VariableTypes', {'double','double','double','double','double','double','double', ...
    'double','double','double','double','double','double','double'}, ...
    'VariableNames', {'stim_channel','current_uA','n_trials', ...
    'mean_peak_latency_s','median_peak_latency_s','std_peak_latency_s', ...
    'iqr_peak_latency_s','min_peak_latency_s','max_peak_latency_s', ...
    'frac_within_window_of_median','mean_roi_dff','std_roi_dff', ...
    'frac_late_flag','peak_dff_threshold'});

for g = 1:n_groups
    idx = grp == g;
    lat = double(Tf.peak_latency_s(idx));
    pk = double(Tf.roi_mean_dff(idx));
    lf = double(Tf.late_flag(idx));

    median_lat = median(lat, 'omitnan');
    frac_within = mean(abs(lat - median_lat) <= within_window_sec, 'omitnan');

    summary_table.stim_channel(g) = uniq_groups(g, 1);
    summary_table.current_uA(g) = uniq_groups(g, 2);
    summary_table.n_trials(g) = sum(idx);
    summary_table.mean_peak_latency_s(g) = mean(lat, 'omitnan');
    summary_table.median_peak_latency_s(g) = median_lat;
    summary_table.std_peak_latency_s(g) = std(lat, 0, 'omitnan');
    summary_table.iqr_peak_latency_s(g) = iqr(lat);
    summary_table.min_peak_latency_s(g) = min(lat);
    summary_table.max_peak_latency_s(g) = max(lat);
    summary_table.frac_within_window_of_median(g) = frac_within;
    summary_table.mean_roi_dff(g) = mean(pk, 'omitnan');
    summary_table.std_roi_dff(g) = std(pk, 0, 'omitnan');
    summary_table.frac_late_flag(g) = mean(lf, 'omitnan');
    summary_table.peak_dff_threshold(g) = peak_dff_threshold;
end

summary_table = sortrows(summary_table, {'stim_channel', 'current_uA'});

summary_table_filtered = summary_table(summary_table.n_trials >= min_trials_per_group, :);

fprintf('Groups total: %d\n', height(summary_table));
fprintf('Groups with n >= %d: %d\n', min_trials_per_group, height(summary_table_filtered));

%% -------------------------
% OUTPUT PATHS
% -------------------------
[csv_dir, csv_base, ~] = fileparts(latency_csv_file);
out_dir = fullfile(csv_dir, 'peak_latency_consistency_summary');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

summary_csv = fullfile(out_dir, sprintf('%s_peak_latency_consistency_summary.csv', csv_base));
writetable(summary_table_filtered, summary_csv);

fprintf('\nSummary CSV written:\n  %s\n', summary_csv);

%% -------------------------
% PLOTS
% -------------------------
if ~isempty(summary_table_filtered)
    channels = unique(summary_table_filtered.stim_channel);
    currents = unique(summary_table_filtered.current_uA);
    heat_sd = nan(numel(channels), numel(currents));
    heat_frac = nan(numel(channels), numel(currents));

    for i = 1:height(summary_table_filtered)
        r = find(channels == summary_table_filtered.stim_channel(i), 1);
        c = find(currents == summary_table_filtered.current_uA(i), 1);
        heat_sd(r, c) = summary_table_filtered.std_peak_latency_s(i);
        heat_frac(r, c) = summary_table_filtered.frac_within_window_of_median(i);
    end

    % Keep only trials belonging to groups that pass min_trials_per_group.
    keep_trial = false(height(Tf), 1);
    for i = 1:height(summary_table_filtered)
        keep_trial = keep_trial | ...
            (Tf.stim_channel == summary_table_filtered.stim_channel(i) & ...
             Tf.current_uA == summary_table_filtered.current_uA(i));
    end
    Tplot = Tf(keep_trial, :);
    condition_labels = strings(height(Tplot), 1);
    for i = 1:height(Tplot)
        condition_labels(i) = sprintf('Ch %d | %g uA', Tplot.stim_channel(i), Tplot.current_uA(i));
    end
    ordered_labels = strings(height(summary_table_filtered), 1);
    for i = 1:height(summary_table_filtered)
        ordered_labels(i) = sprintf('Ch %d | %g uA', ...
            summary_table_filtered.stim_channel(i), summary_table_filtered.current_uA(i));
    end
    condition_cat = categorical(condition_labels, ordered_labels, 'Ordinal', true);

    %% -------------------------
    % PLOT 1: LATENCY SD HEATMAP
    % -------------------------
    fig1 = figure('Color', 'w', 'Name', 'Peak latency consistency heatmaps');
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    h1 = imagesc(ax1, heat_sd);
    axis(ax1, 'image');
    set(h1, 'AlphaData', ~isnan(heat_sd));
    colorbar(ax1);
    title(ax1, sprintf('Peak latency SD (s) | ROI mean dF/F > %.2f (0-3 s)', peak_dff_threshold));
    xlabel(ax1, 'Current (uA)');
    ylabel(ax1, 'Channel');
    set(ax1, 'XTick', 1:numel(currents), 'XTickLabel', string(currents), ...
        'YTick', 1:numel(channels), 'YTickLabel', string(channels), 'YDir', 'normal');

    ax2 = nexttile;
    h2 = imagesc(ax2, heat_frac, [0 1]);
    axis(ax2, 'image');
    set(h2, 'AlphaData', ~isnan(heat_frac));
    colorbar(ax2);
    title(ax2, sprintf('Frac within +/- %.2f s of median', within_window_sec));
    xlabel(ax2, 'Current (uA)');
    ylabel(ax2, 'Channel');
    set(ax2, 'XTick', 1:numel(currents), 'XTickLabel', string(currents), ...
        'YTick', 1:numel(channels), 'YTickLabel', string(channels), 'YDir', 'normal');

    if save_png
        saveas(fig1, fullfile(out_dir, 'peak_latency_consistency_heatmaps.png'));
    end

    %% -------------------------
    % PLOT 2: CONDITION SCATTER (SUMMARY METRICS)
    % -------------------------
    group_labels = strings(height(summary_table_filtered), 1);
    for i = 1:height(summary_table_filtered)
        group_labels(i) = sprintf('Ch %d | %g uA', ...
            summary_table_filtered.stim_channel(i), summary_table_filtered.current_uA(i));
    end

    fig2 = figure('Color', 'w', 'Name', 'Peak latency consistency scatter');
    tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax3 = nexttile;
    scatter(ax3, 1:height(summary_table_filtered), summary_table_filtered.std_peak_latency_s, 50, ...
        summary_table_filtered.mean_roi_dff, 'filled');
    colorbar(ax3);
    ylabel(ax3, 'Latency SD (s)');
    title(ax3, sprintf('Per-condition peak latency spread (0-3 s) | ROI mean dF/F > %.2f', peak_dff_threshold));
    set(ax3, 'XTick', 1:height(summary_table_filtered), 'XTickLabel', group_labels, 'XTickLabelRotation', 45);
    grid(ax3, 'on');

    ax4 = nexttile;
    scatter(ax4, 1:height(summary_table_filtered), summary_table_filtered.frac_within_window_of_median, 50, ...
        summary_table_filtered.n_trials, 'filled');
    colorbar(ax4);
    ylabel(ax4, 'Frac within window');
    title(ax4, sprintf('Consistency fraction within +/- %.2f s of median', within_window_sec));
    set(ax4, 'XTick', 1:height(summary_table_filtered), 'XTickLabel', group_labels, 'XTickLabelRotation', 45);
    ylim(ax4, [0 1]);
    grid(ax4, 'on');

    if save_png
        saveas(fig2, fullfile(out_dir, 'peak_latency_consistency_scatter.png'));
    end

    %% -------------------------
    % PLOT 3: TRIAL-LEVEL PEAK LATENCY BOXPLOT + SCATTER
    % -------------------------
    fig3 = figure('Color', 'w', 'Name', 'Trial-level peak latency by condition');
    ax5 = axes(fig3);
    boxplot(ax5, Tplot.peak_latency_s, condition_cat, 'LabelOrientation', 'inline');
    hold(ax5, 'on');

    x_pos = double(condition_cat);
    jitter = 0.18 * (rand(size(x_pos)) - 0.5);
    scatter(ax5, x_pos + jitter, Tplot.peak_latency_s, 22, Tplot.roi_mean_dff, ...
        'filled', 'MarkerFaceAlpha', 0.65, 'MarkerEdgeAlpha', 0.65);
    cb = colorbar(ax5);
    cb.Label.String = 'ROI mean dF/F';
    caxis(ax5, [peak_dff_threshold boxplot_peak_dff_cap]);

    ylabel(ax5, 'Peak latency (s)');
    xlabel(ax5, 'Channel | Current');
    title(ax5, sprintf('Trial peak latency by condition (0-3 s) | ROI mean dF/F > %.2f', peak_dff_threshold));
    grid(ax5, 'on');
    set(ax5, 'XTickLabelRotation', 45);

    if save_png
        saveas(fig3, fullfile(out_dir, 'peak_latency_trial_boxplot_scatter.png'));
    end
end

%% -------------------------
% SAVE MAT
% -------------------------
if save_mat
    save(fullfile(out_dir, sprintf('%s_peak_latency_consistency_summary.mat', csv_base)), ...
        'T', 'Tf', 'summary_table', 'summary_table_filtered', ...
        'peak_dff_threshold', 'within_window_sec', 'min_trials_per_group', '-v7.3');
end
