%% classify_significant_conditions_from_summary_csv.m
% Read a session_condition_summary.csv file and classify each channel-current
% condition by whether it had significant activation across both days or
% only one day.

close all; clc; clear; fclose('all');

%% -------------------------
% SELECT CSV
% -------------------------
[fn, fp] = uigetfile('*.csv', 'Select session_condition_summary.csv');
if isequal(fn, 0)
    error('No CSV selected.');
end

csv_file = fullfile(fp, fn);
T = readtable(csv_file, 'TextType', 'string');

[pair_fn, pair_fp] = uigetfile('*.csv', 'Select pairwise_condition_comparison.csv');
if isequal(pair_fn, 0)
    error('No pairwise comparison CSV selected.');
end

pairwise_csv_file = fullfile(pair_fp, pair_fn);
P = readtable(pairwise_csv_file, 'TextType', 'string');

required_vars = ["session_label", "channel", "current_uA", "has_cluster"];
missing_vars = required_vars(~ismember(required_vars, string(T.Properties.VariableNames)));
assert(isempty(missing_vars), ...
    'CSV is missing required columns: %s', strjoin(cellstr(missing_vars), ', '));

if ~ismember("condition_key", string(T.Properties.VariableNames))
    T.condition_key = "ch" + string(T.channel) + "_uA_" + string(T.current_uA);
end

session_labels = unique(T.session_label, 'stable');
n_sessions = numel(session_labels);

summary_rows = struct( ...
    'condition_key', {}, ...
    'channel', {}, ...
    'current_uA', {}, ...
    'n_days_present', {}, ...
    'n_days_significant', {}, ...
    'significant_across_both_days', {}, ...
    'significant_in_only_one_day', {}, ...
    'significant_session_labels', {}, ...
    'non_significant_session_labels', {} );

condition_keys = unique(T.condition_key, 'stable');

for i = 1:numel(condition_keys)
    key = condition_keys(i);
    rows_i = T(T.condition_key == key, :);

    sig_mask = logical(rows_i.has_cluster);
    sig_sessions = rows_i.session_label(sig_mask);
    nonsig_sessions = rows_i.session_label(~sig_mask);

    summary_rows(end+1).condition_key = key; %#ok<AGROW>
    summary_rows(end).channel = rows_i.channel(1);
    summary_rows(end).current_uA = rows_i.current_uA(1);
    summary_rows(end).n_days_present = height(rows_i);
    summary_rows(end).n_days_significant = sum(sig_mask);
    summary_rows(end).significant_across_both_days = (sum(sig_mask) >= 2);
    summary_rows(end).significant_in_only_one_day = (sum(sig_mask) == 1);
    summary_rows(end).significant_session_labels = strjoin(sig_sessions, '; ');
    summary_rows(end).non_significant_session_labels = strjoin(nonsig_sessions, '; ');
end

summary_table = struct2table(summary_rows);

both_days_table = summary_table(summary_table.significant_across_both_days, :);
one_day_table = summary_table(summary_table.significant_in_only_one_day, :);

pair_required_vars = ["condition_key", "channel", "current_uA", "session_a", "session_b", ...
    "active_pixels_a", "active_pixels_b", "intersection_pixels", "union_pixels", "dice", "iou"];
missing_pair_vars = pair_required_vars(~ismember(pair_required_vars, string(P.Properties.VariableNames)));
assert(isempty(missing_pair_vars), ...
    'Pairwise CSV is missing required columns: %s', strjoin(cellstr(missing_pair_vars), ', '));

sig_keys = both_days_table.condition_key;
pairwise_sig_table = P(ismember(P.condition_key, sig_keys), :);
pairwise_sig_table.percent_overlap_union = 100 * pairwise_sig_table.intersection_pixels ./ pairwise_sig_table.union_pixels;
pairwise_sig_table.percent_overlap_smaller_mask = 100 * pairwise_sig_table.intersection_pixels ./ ...
    min(pairwise_sig_table.active_pixels_a, pairwise_sig_table.active_pixels_b);

valid_union = isfinite(pairwise_sig_table.percent_overlap_union);
valid_smaller = isfinite(pairwise_sig_table.percent_overlap_smaller_mask);
mean_overlap_union = mean(pairwise_sig_table.percent_overlap_union(valid_union), 'omitnan');
mean_overlap_smaller = mean(pairwise_sig_table.percent_overlap_smaller_mask(valid_smaller), 'omitnan');

save_dir = fullfile(fp, 'significance_from_session_condition_summary');
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

writetable(summary_table, fullfile(save_dir, 'channel_current_significance_summary.csv'));
writetable(both_days_table, fullfile(save_dir, 'significant_across_both_days.csv'));
writetable(one_day_table, fullfile(save_dir, 'significant_in_only_one_day.csv'));
writetable(pairwise_sig_table, fullfile(save_dir, 'significant_pairwise_overlap_summary.csv'));

save(fullfile(save_dir, 'channel_current_significance_summary.mat'), ...
    'summary_table', 'both_days_table', 'one_day_table', 'pairwise_sig_table', ...
    'csv_file', 'pairwise_csv_file', 'session_labels', 'n_sessions', ...
    'mean_overlap_union', 'mean_overlap_smaller');

fprintf('\nLoaded CSV:\n  %s\n', csv_file);
fprintf('Loaded pairwise CSV:\n  %s\n', pairwise_csv_file);
fprintf('Detected %d session labels.\n', n_sessions);
fprintf('Conditions significant across both days: %d\n', height(both_days_table));
fprintf('Conditions significant in only one day: %d\n', height(one_day_table));
fprintf('Saved outputs to:\n  %s\n', save_dir);

fprintf('\nPairwise overlap for channel-currents significant across both days:\n');
if isempty(pairwise_sig_table) || height(pairwise_sig_table) == 0
    fprintf('  None\n');
else
    for i = 1:height(pairwise_sig_table)
        fprintf('  ch%d | %g uA | %s vs %s | overlap=%.2f%% of union | overlap=%.2f%% of smaller mask\n', ...
            pairwise_sig_table.channel(i), ...
            pairwise_sig_table.current_uA(i), ...
            pairwise_sig_table.session_a(i), ...
            pairwise_sig_table.session_b(i), ...
            pairwise_sig_table.percent_overlap_union(i), ...
            pairwise_sig_table.percent_overlap_smaller_mask(i));
    end
end

fprintf('\nAverage overlap across all significant channel-currents:\n');
fprintf('  Mean overlap %% of union (IoU %%): %.2f%%\n', mean_overlap_union);
fprintf('  Mean overlap %% of smaller mask: %.2f%%\n', mean_overlap_smaller);

fprintf('\nSignificant across both days:\n');
if isempty(both_days_table) || height(both_days_table) == 0
    fprintf('  None\n');
else
    for i = 1:height(both_days_table)
        fprintf('  ch%d | %g uA | %s\n', ...
            both_days_table.channel(i), ...
            both_days_table.current_uA(i), ...
            both_days_table.significant_session_labels(i));
    end
end

fprintf('\nSignificant in only one day:\n');
if isempty(one_day_table) || height(one_day_table) == 0
    fprintf('  None\n');
else
    for i = 1:height(one_day_table)
        fprintf('  ch%d | %g uA | %s\n', ...
            one_day_table.channel(i), ...
            one_day_table.current_uA(i), ...
            one_day_table.significant_session_labels(i));
    end
end
