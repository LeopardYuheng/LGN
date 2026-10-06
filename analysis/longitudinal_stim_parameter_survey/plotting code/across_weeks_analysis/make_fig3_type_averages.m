%% make_fig3_type_averages.m
% FIGURE 3 — ROI dF/F averaged across channels, the two channel types apart.
%
%   x axis : week before blindness, then post week 1..4
%   y axis : mean ROI dF/F at 7 uA across the channels of one type,
%            each channel read at ITS fixed time (wf_roi_sample_time.m)
%
% The two types are averaged separately on purpose. Type 2 holds steady
% across blinding, so pooling it with type 1 would pull the type-1 decline
% toward flat and hide the very effect the figure exists to show.
%
%   type 1  solid response before blindness that weakens at post W1-W2,
%           and mostly returns at higher current (figures 4/5/6)
%   type 2  stable across blindness, no major change
%
% Each channel is drawn as a faint line behind the mean, so the reader can
% see the spread rather than trust an error bar — with n as small as 2
% (type 2) that matters.
%
% Outputs, per type: an ABSOLUTE panel (dF/F as measured) and a NORMALISED
% panel (each channel scaled to its own week-before-blindness value = 100%).
% Normalising stops one large channel from dominating the mean, but a
% channel whose pre-blind response is already at the noise floor has no
% meaningful denominator and is left out of that panel only — it is named
% in the subtitle rather than silently dropped.
%
% Reads:  <root>/roi_traces.mat  (from extract_roi_traces.m)
% Writes: <root>/figure3_type_averages/*.png and fig3_type_values.csv

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
target_current_uA = 7;
week_indices      = [-1 1 2 3 4];    % week before blindness .. post W4
week_tick_labels  = {'week before blindness', 'post week 1', 'post week 2', ...
                     'post week 3', 'post week 4'};

% Channel types, keyed "<MOUSE>_<channel>"
type_defs(1).label = 'Type 1 — response weakened after blindness';
type_defs(1).short = 'type1';
type_defs(1).color = [0.84 0.15 0.16];
type_defs(1).keys  = ["LGN24_43", "LGN24_49", "LGN24_55", "LGN24_67", ...
                      "LGN24_97", "LGN24_101", "LGN24_105", ...
                      "LGN26_2", "LGN26_49", "LGN26_51", "LGN26_64"];

type_defs(2).label = 'Type 2 — stable across blindness';
type_defs(2).short = 'type2';
type_defs(2).color = [0.12 0.47 0.71];
type_defs(2).keys  = ["LGN26_101", "LGN26_106"];

% Dropped entirely. Both sit at or below the noise floor before blindness,
% so they have no response to lose and cannot show a decline.
% Note this selection is deliberately WIDER than figures 5/6: those also
% drop channels that lack a usable high-current session, which this figure
% does not use.
exclude_keys = ["LGN24_45", "LGN24_101"];

% A channel needs a pre-blind response at least this large to be normalised
norm_floor_dff = 0.005;

show_channel_lines = true;
font_size_axis     = 12;
font_size_title    = 13;
out_subfolder      = 'figure3_type_averages';

%% -------------------------
% LOAD
% -------------------------
root_dir = uigetdir('C:\Projects\LGN\weekly update\plots for presentation', ...
    'Select the longitudinal_data folder');
if isequal(root_dir, 0), error('No folder selected.'); end

traces_file = fullfile(root_dir, 'roi_traces.mat');
assert(isfile(traces_file), ['No roi_traces.mat in:\n  %s\n' ...
    'Run extract_roi_traces.m first.'], root_dir);
L = load(traces_file);
R = L.R;
fprintf('Loaded %d extracted trace(s).\n', numel(R));

out_dir = fullfile(root_dir, out_subfolder);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

n_wk = numel(week_indices);
rows = table();
ch_list = table();

%% -------------------------
% PER-TYPE SERIES
% -------------------------
for ti = 1:numel(type_defs)
    keys = setdiff(type_defs(ti).keys, exclude_keys, 'stable');
    n_ch = numel(keys);
    vals = nan(n_ch, n_wk);
    t_read = nan(n_ch, 1);

    for ki = 1:n_ch
        parts = split(keys(ki), '_');
        mouse = char(parts(1));
        ch    = str2double(parts(2));
        t_read(ki) = wf_roi_sample_time(mouse, ch);

        for wi = 1:n_wk
            k = find(strcmp({R.mouse}, mouse) & [R.channel] == ch & ...
                [R.week_index] == week_indices(wi) & ...
                abs([R.current_uA] - target_current_uA) < 1e-9, 1);
            if isempty(k), continue; end     % no ROI that week -> stays NaN
            vals(ki, wi) = sample_at(R(k).t_s, R(k).trace, t_read(ki));
        end
    end

    % --- Normalised copy: each channel against its own pre-blind value ---
    ref = vals(:, 1);
    ok_norm = abs(ref) >= norm_floor_dff & isfinite(ref);
    norm_vals = nan(size(vals));
    norm_vals(ok_norm, :) = vals(ok_norm, :) ./ ref(ok_norm) * 100;
    dropped = keys(~ok_norm);

    fprintf('\n%s: %d channel(s)\n', type_defs(ti).label, n_ch);
    for wi = 1:n_wk
        fprintf('  %-24s n=%2d  mean %+0.4f\n', week_tick_labels{wi}, ...
            nnz(isfinite(vals(:, wi))), mean(vals(:, wi), 'omitnan'));
    end
    if ~isempty(dropped)
        fprintf('  not normalised (pre-blind response below %.3f): %s\n', ...
            norm_floor_dff, strjoin(cellstr(dropped), ', '));
    end

    % --- Figure: absolute | normalised ---
    fig = figure('Color', 'w', 'Visible', 'off', 'Position', [80 80 1180 520]);
    tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(tl);
    plot_panel(ax1, week_indices, vals, type_defs(ti).color, ...
        show_channel_lines, week_tick_labels, font_size_axis);
    ylabel(ax1, 'ROI \DeltaF/F at fixed read-out time', 'FontSize', font_size_axis);
    title(ax1, 'absolute', 'FontSize', font_size_title);
    yline(ax1, 0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');

    ax2 = nexttile(tl);
    plot_panel(ax2, week_indices, norm_vals, type_defs(ti).color, ...
        show_channel_lines, week_tick_labels, font_size_axis);
    ylabel(ax2, '% of week before blindness', 'FontSize', font_size_axis);
    title(ax2, 'normalised per channel', 'FontSize', font_size_title);
    yline(ax2, 100, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');

    n_txt = sprintf('n = %d channel(s), %g \\muA', n_ch, target_current_uA);
    if ~isempty(dropped)
        % "LGN24_101" -> "LGN24 ch101": the title is rendered by the TeX
        % interpreter (for \mu and \Delta), which would read the underscore
        % as a subscript.
        n_txt = sprintf('%s  |  not normalised: %s', n_txt, ...
            strjoin(cellstr(strrep(dropped, '_', ' ch')), ', '));
    end
    title(tl, {type_defs(ti).label, n_txt, channel_summary(keys)}, ...
        'FontSize', font_size_title + 1, 'FontWeight', 'bold', 'Interpreter', 'tex');

    png = sprintf('fig3_%s_%guA.png', type_defs(ti).short, target_current_uA);
    exportgraphics(fig, fullfile(out_dir, png), 'Resolution', 150);
    close(fig);
    fprintf('  saved: %s\n', png);

    % --- Collect for the combined figure and the CSV ---
    type_defs(ti).vals = vals;       %#ok<SAGROW>
    type_defs(ti).norm = norm_vals;  %#ok<SAGROW>
    type_defs(ti).used = keys;       %#ok<SAGROW>

    for ki = 1:n_ch
        p = split(keys(ki), '_');
        ch_list = [ch_list; table(string(type_defs(ti).short), ...
            string(type_defs(ti).label), p(1), str2double(p(2)), t_read(ki), ...
            'VariableNames', {'type', 'type_label', 'mouse', 'channel', ...
            'readout_time_s'})]; %#ok<AGROW>
    end

    for ki = 1:n_ch
        rows = [rows; table(repmat(string(type_defs(ti).short), n_wk, 1), ...
            repmat(keys(ki), n_wk, 1), week_indices(:), string(week_tick_labels(:)), ...
            repmat(t_read(ki), n_wk, 1), vals(ki, :)', norm_vals(ki, :)', ...
            'VariableNames', {'type', 'channel_key', 'week_index', 'week_label', ...
            'readout_time_s', 'roi_dff', 'pct_of_preblind'})]; %#ok<AGROW>
    end
end

%% -------------------------
% COMBINED: the two types on one axes
% -------------------------
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 820 560]);
ax = axes(fig); %#ok<LAXES>
hold(ax, 'on');

h = gobjects(numel(type_defs), 1);
lbl = cell(numel(type_defs), 1);
for ti = 1:numel(type_defs)
    v = type_defs(ti).vals;
    m = mean(v, 1, 'omitnan');
    n = sum(isfinite(v), 1);
    e = std(v, 0, 1, 'omitnan') ./ max(1, sqrt(n));
    e(n < 2) = 0;
    m(n == 0) = NaN;
    h(ti) = errorbar(ax, week_indices, m, e, '-o', 'Color', type_defs(ti).color, ...
        'LineWidth', 1.9, 'MarkerSize', 7, 'MarkerFaceColor', type_defs(ti).color, ...
        'MarkerEdgeColor', 'w', 'CapSize', 6);
    lbl{ti} = sprintf('%s (n = %d)', type_defs(ti).label, numel(type_defs(ti).used));
end

xline(ax, 0, '--', 'blinding', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
    'LabelVerticalAlignment', 'bottom', 'FontSize', 10, 'HandleVisibility', 'off');
yline(ax, 0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
style_week_axis(ax, week_indices, week_tick_labels, font_size_axis);
ylabel(ax, 'mean ROI \DeltaF/F', 'FontSize', font_size_axis);
title(ax, sprintf('ROI \\DeltaF/F across weeks by channel type  |  %g \\muA', ...
    target_current_uA), 'FontSize', font_size_title);
subtitle(ax, sprintf('type 1: %s      type 2: %s', ...
    channel_summary(type_defs(1).used), channel_summary(type_defs(2).used)), ...
    'FontSize', 8, 'Interpreter', 'tex');
legend(ax, h, lbl, 'Location', 'northeast', 'Box', 'off', 'Interpreter', 'none');
grid(ax, 'on'); box(ax, 'on');

png = sprintf('fig3_both_types_%guA.png', target_current_uA);
exportgraphics(fig, fullfile(out_dir, png), 'Resolution', 150);
close(fig);
fprintf('\nsaved: %s\n', png);

csv_file = fullfile(out_dir, 'fig3_type_values.csv');
writetable(rows, csv_file);
ch_file = fullfile(out_dir, 'fig3_channels.csv');
writetable(ch_list, ch_file);
fprintf('Channels: %s\n', ch_file);
fprintf('Done. Figures in:\n  %s\nValues: %s\n', out_dir, csv_file);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function plot_panel(ax, wk, M, col, show_lines, tick_labels, fs)
hold(ax, 'on');
if show_lines
    for i = 1:size(M, 1)
        plot(ax, wk, M(i, :), '-', 'Color', [0.7 0.7 0.7 0.9], 'LineWidth', 0.8, ...
            'HandleVisibility', 'off');
    end
end
m = mean(M, 1, 'omitnan');
n = sum(isfinite(M), 1);
e = std(M, 0, 1, 'omitnan') ./ max(1, sqrt(n));
e(n < 2) = 0;
m(n == 0) = NaN;
errorbar(ax, wk, m, e, '-o', 'Color', col, 'LineWidth', 2.0, 'MarkerSize', 7, ...
    'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'CapSize', 6);

% n under each point, so a gap or a shrinking sample is visible
yl = ylim(ax);
for j = 1:numel(wk)
    text(ax, wk(j), yl(1) + 0.03 * diff(yl), sprintf('n=%d', n(j)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', [0.35 0.35 0.35]);
end

xline(ax, 0, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, 'HandleVisibility', 'off');
style_week_axis(ax, wk, tick_labels, fs);
grid(ax, 'on'); box(ax, 'on');
end

function style_week_axis(ax, wk, tick_labels, fs)
xticks(ax, wk);
xticklabels(ax, tick_labels);
xlim(ax, [min(wk) - 0.4, max(wk) + 0.4]);
ax.XAxis.FontSize = max(8, fs - 3);
ax.TickLabelInterpreter = 'none';
end

function y = sample_at(t, v, t_target)
[~, k] = min(abs(t - t_target));
y = v(k);
end

function s = channel_summary(keys)
% "LGN24_49" ... -> "LGN24 ch49, ch55  |  LGN26 ch2, ch64", grouped by mouse
% and rendered without underscores (the title uses the TeX interpreter).
mice = strings(numel(keys), 1);
chs  = strings(numel(keys), 1);
for i = 1:numel(keys)
    p = split(keys(i), '_');
    mice(i) = p(1);
    chs(i)  = "ch" + p(2);
end
parts = {};
for m = unique(mice, 'stable')'
    parts{end+1} = sprintf('%s %s', m, strjoin(cellstr(chs(mice == m)), ', ')); %#ok<AGROW>
end
s = strjoin(parts, '   |   ');
end
