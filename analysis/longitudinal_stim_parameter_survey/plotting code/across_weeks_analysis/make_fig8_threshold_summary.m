%% make_fig8_threshold_summary.m
% FIGURE 8 — threshold current before blindness vs the high-current session.
%
% A paired, two-session comparison across channels:
%
%   left   week before blindness   (weekly grid: 2, 4, 5, 6, 7 uA)
%   right  week 6 after blindness  (high-current grid: 3, 6, 8, 10, 12 uA;
%                                   LGN26 stopped at 10 uA)
%
% Why only these two sessions. In the intervening weeks most channels have
% NO measurable threshold — they are censored at "> 7 uA" — so any average
% over those weeks either drops them (and then reports the mean of a
% shrinking, self-selected sample) or holds them at a ceiling. In these two
% sessions every channel has a real threshold, so the comparison needs no
% such handling and each channel is its own control.
%
% Each channel is drawn as a line joining its two thresholds, so the reader
% sees the paired structure rather than two disconnected means.
%
% Reads:  <root>/figure7_threshold_current/fig7_thresholds.csv
%         (so figures 7 and 8 share one threshold definition)
% Writes: <root>/figure8_threshold_summary/fig8_threshold_paired.png
%                                          fig8_paired_values.csv

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
pre_week_index  = -1;       % week before blindness
post_week_min   = 5;        % the high-current session (post week 5 or 6)

pre_label       = 'week before blindness';
post_label      = 'week 6 after blindness';

% Channels left out of the summary (on top of whatever figure 7 excluded)
exclude_keys    = "LGN24_105";

% The high-current grid has no 4, 5 or 7 uA. A channel below 6 uA before
% blindness can therefore only be recorded at 6 uA there, so an increase
% this small may be grid resolution rather than a real shift. Those
% channels are drawn dashed and counted separately.
coarse_grid_floor = 6;

pair_color      = [0.70 0.70 0.70];
mean_color      = [0.84 0.15 0.16];
marker_size     = 7;
font_size_axis  = 12;
font_size_title = 14;
show_channel_labels = true;

out_subfolder   = 'figure8_threshold_summary';

%% -------------------------
% LOAD FIGURE 7's THRESHOLDS
% -------------------------
root_dir = uigetdir('C:\Projects\LGN\weekly update\plots for presentation', ...
    'Select the longitudinal_data folder');
if isequal(root_dir, 0), error('No folder selected.'); end

thr_file = fullfile(root_dir, 'figure7_threshold_current', 'fig7_thresholds.csv');
assert(isfile(thr_file), ['No fig7_thresholds.csv in:\n  %s\n' ...
    'Run make_fig7_threshold_current.m first.'], thr_file);
T = readtable(thr_file);
T.key = string(T.mouse) + "_" + string(T.channel);
T = T(~ismember(T.key, exclude_keys), :);

out_dir = fullfile(root_dir, out_subfolder);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
old = dir(fullfile(out_dir, 'fig8_*.png'));
for i = 1:numel(old), delete(fullfile(old(i).folder, old(i).name)); end

%% -------------------------
% PAIR THE TWO SESSIONS
% -------------------------
keys = unique(T.key, 'stable');
rows = table();

for i = 1:numel(keys)
    r_pre  = T(T.key == keys(i) & T.week_index == pre_week_index, :);
    r_post = T(T.key == keys(i) & T.week_index >= post_week_min, :);
    if isempty(r_pre) || isempty(r_post), continue; end
    if ~isfinite(r_pre.threshold_uA(1)) || ~isfinite(r_post.threshold_uA(1)), continue; end

    rows = [rows; table(keys(i), string(r_pre.mouse{1}), r_pre.channel(1), ...
        r_pre.threshold_uA(1), r_pre.censored(1), ...
        r_post.threshold_uA(1), r_post.censored(1), ...
        r_post.max_current_tested_uA(1), ...
        'VariableNames', {'key', 'mouse', 'channel', 'pre_uA', 'pre_censored', ...
        'post_uA', 'post_censored', 'post_max_tested_uA'})]; %#ok<AGROW>
end

assert(~isempty(rows), 'No channel has both sessions.');
n = height(rows);
rows.delta_uA = rows.post_uA - rows.pre_uA;

% Increases that the coarser high-current grid alone could produce
rows.grid_limited = rows.pre_uA < coarse_grid_floor & rows.post_uA == coarse_grid_floor;

fprintf('Channels paired (n = %d):\n', n);
for i = 1:n
    tag = '';
    if rows.grid_limited(i), tag = '   (increase within the coarser grid)'; end
    fprintf('  %-6s ch%-4d  %g -> %g uA   (%+g)%s\n', rows.mouse(i), rows.channel(i), ...
        rows.pre_uA(i), rows.post_uA(i), rows.delta_uA(i), tag);
end

m_pre  = mean(rows.pre_uA);
m_post = mean(rows.post_uA);
e_pre  = std(rows.pre_uA) / sqrt(n);
e_post = std(rows.post_uA) / sqrt(n);
n_up   = sum(rows.delta_uA > 0);
n_dn   = sum(rows.delta_uA < 0);
p_sign = exact_sign_test(n_up, n_dn);

fprintf('\n  %s: %.2f +/- %.2f uA\n', pre_label, m_pre, e_pre);
fprintf('  %s: %.2f +/- %.2f uA\n', post_label, m_post, e_post);
fprintf('  mean change: %+.2f uA   |  %d up, %d down, %d unchanged\n', ...
    m_post - m_pre, n_up, n_dn, n - n_up - n_dn);
fprintf('  exact sign test: p = %.4f\n', p_sign);
fprintf('  increases larger than the grid can explain: %d of %d\n', ...
    sum(~rows.grid_limited & rows.delta_uA > 0), n);

writetable(rows, fullfile(out_dir, 'fig8_paired_values.csv'));

%% -------------------------
% FIGURE
% -------------------------
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 720 620]);
ax = axes(fig); %#ok<LAXES>
hold(ax, 'on');

x = [1 2];
for i = 1:n
    if rows.grid_limited(i), ls = '--'; else, ls = '-'; end
    plot(ax, x, [rows.pre_uA(i) rows.post_uA(i)], ls, 'Color', pair_color, ...
        'LineWidth', 1.2, 'Marker', 'o', 'MarkerSize', marker_size - 2, ...
        'MarkerFaceColor', 'w', 'MarkerEdgeColor', pair_color, ...
        'HandleVisibility', 'off');
end

% Channels that end on the same threshold would overprint each other, so
% label each end value once with all the channels that landed there.
if show_channel_labels
    for v = unique(rows.post_uA)'
        at_v = rows(rows.post_uA == v, :);
        names = arrayfun(@(j) sprintf('%s ch%d', at_v.mouse(j), at_v.channel(j)), ...
            (1:height(at_v))', 'UniformOutput', false);
        text(ax, x(2) + 0.05, v, [' ' strjoin(names, ', ')], ...
            'FontSize', 8, 'Color', [0.35 0.35 0.35], 'VerticalAlignment', 'middle');
    end
end

errorbar(ax, x, [m_pre m_post], [e_pre e_post], '-o', 'Color', mean_color, ...
    'LineWidth', 2.4, 'MarkerSize', marker_size + 3, 'MarkerFaceColor', mean_color, ...
    'MarkerEdgeColor', 'w', 'CapSize', 8, 'DisplayName', 'mean \pm SEM');

% Set beside each mean rather than above/below it: the error bars are
% vertical, so anything placed over them collides.
text(ax, 1 - 0.06, m_pre, sprintf('%.2f \\muA ', m_pre), 'Color', mean_color, ...
    'FontWeight', 'bold', 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
text(ax, 2 - 0.06, m_post, sprintf('%.2f \\muA ', m_post), 'Color', mean_color, ...
    'FontWeight', 'bold', 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

xticks(ax, x);
xticklabels(ax, {pre_label, post_label});
ax.TickLabelInterpreter = 'none';
xlim(ax, [0.7 2.95]);
ylim(ax, [0, max(rows.post_uA) + 2]);
yticks(ax, unique([0 2 3 4 5 6 7 8 10 12]));
ylabel(ax, 'Threshold current (\muA)', 'FontSize', font_size_axis);

title(ax, sprintf('Threshold current rises after blindness  (n = %d channels)', n), ...
    'FontSize', font_size_title);
% No subtitle: the statistics and the dashed/solid distinction are reported
% to the console and written to fig8_paired_values.csv.
legend(ax, 'Location', 'northwest', 'Box', 'off');
grid(ax, 'on'); box(ax, 'on');

png = fullfile(out_dir, 'fig8_threshold_paired.png');
exportgraphics(fig, png, 'Resolution', 150);
close(fig);
fprintf('\nSaved %s\n', png);
fprintf('Values: %s\n', fullfile(out_dir, 'fig8_paired_values.csv'));

%% =========================
% LOCAL FUNCTIONS
%% =========================

function p = exact_sign_test(n_up, n_dn)
% Two-sided exact sign test on the channels that changed. Written out with
% nchoosek so the script needs no Statistics Toolbox.
m = n_up + n_dn;
if m == 0, p = 1; return; end
k = min(n_up, n_dn);
tail = 0;
for i = 0:k
    tail = tail + nchoosek(m, i);
end
p = min(1, 2 * tail / 2^m);
end
