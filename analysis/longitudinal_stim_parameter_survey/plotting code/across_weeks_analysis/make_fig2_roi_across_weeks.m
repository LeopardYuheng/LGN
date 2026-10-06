%% make_fig2_roi_across_weeks.m
% FIGURE 2 — ROI dF/F across weeks, one figure per channel, one current.
%
%   x axis : recording week, pre week 1..4 then post week 1..4
%   y axis : mean dF/F inside that week's ROI, read at a FIXED time
%            (+0.5 s for most channels, +0.1 s for LGN24 ch49 and ch55 —
%             see wf_roi_sample_time.m)
%
% The value is read at that fixed time, never at each week's own maximum.
% A per-week maximum search would find the largest noise excursion on a week
% with no response, inflating exactly the weeks the figure is meant to show
% as flat.
%
% The high-current session (post W5/W6) is outside the x range on purpose:
% it used a different protocol and never tested this current.
%
% A week you skipped while drawing ROIs has no value and appears as a GAP —
% the line breaks rather than dropping to zero, because "not measured" and
% "no response" are different statements.
%
% The 0 uA sham of each week is drawn as a grey band, so "no response" is
% something the reader can see rather than take on trust.
%
% Reads:  <root>/roi_traces.mat  (from extract_roi_traces.m)
% Writes: <root>/figure2_roi_across_weeks/fig2_roi_<MOUSE>_ch<N>_<I>uA.png
%         <root>/figure2_roi_across_weeks/fig2_roi_values.csv

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
target_current_uA = 7;          % pre W1 has no 6 uA, so 7 uA covers all 8 weeks
week_index_range  = [-4 4];     % pre W1 (-4) .. post W4 (+4); 0 is blinding

show_sham_band    = true;       % grey band = this channel's 0 uA level
line_color        = [0.12 0.47 0.71];
sham_color        = [0.60 0.60 0.60];
marker_size       = 7;
line_width        = 1.8;
font_size_axis    = 12;
font_size_title   = 13;

out_subfolder     = 'figure2_roi_across_weeks';

%% -------------------------
% LOAD EXTRACTED TRACES
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

%% -------------------------
% ONE FIGURE PER CHANNEL
% -------------------------
chan_folders = unique(string({R.chan_folder}), 'stable');
rows = table();

for ci = 1:numel(chan_folders)
    cf = chan_folders(ci);
    in_chan = strcmp({R.chan_folder}, cf);

    sel = R(in_chan & [R.current_uA] == target_current_uA & ...
        [R.week_index] >= week_index_range(1) & [R.week_index] <= week_index_range(2));
    if isempty(sel)
        fprintf('%-14s no %g uA data in the week range — skipped.\n', cf, target_current_uA);
        continue;
    end
    [~, ord] = sort([sel.week_index]);
    sel = sel(ord);

    mouse = sel(1).mouse;
    ch    = sel(1).channel;
    t_read = wf_roi_sample_time(mouse, ch);

    wk   = [sel.week_index]';
    vals = arrayfun(@(s) sample_at(s.t_s, s.trace, t_read), sel)';
    lbls = string({sel.week_label}');

    % Matching 0 uA sham for the same weeks, as a noise reference
    sham = nan(size(vals));
    if show_sham_band
        sh = R(in_chan & [R.current_uA] == 0);
        for i = 1:numel(wk)
            k = find([sh.week_index] == wk(i), 1);
            if ~isempty(k), sham(i) = sample_at(sh(k).t_s, sh(k).trace, t_read); end
        end
    end

    % --- Expected weeks: gaps must stay visible as gaps ---
    all_wk = [week_index_range(1):-1, 1:week_index_range(2)]';
    y = nan(size(all_wk));
    y_sham = nan(size(all_wk));
    for i = 1:numel(all_wk)
        k = find(wk == all_wk(i), 1);
        if ~isempty(k), y(i) = vals(k); y_sham(i) = sham(k); end
    end
    missing = all_wk(isnan(y));

    fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 780 520]);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');

    if show_sham_band && any(isfinite(y_sham))
        lo = min(y_sham, [], 'omitnan');
        hi = max(y_sham, [], 'omitnan');
        if isfinite(lo) && isfinite(hi)
            if hi == lo, hi = lo + eps; end
            patch(ax, [min(all_wk)-0.5 max(all_wk)+0.5 max(all_wk)+0.5 min(all_wk)-0.5], ...
                [lo lo hi hi], sham_color, 'FaceAlpha', 0.30, 'EdgeColor', 'none', ...
                'DisplayName', '0 \muA sham range');
        end
    end

    % Blinding sits at week 0, between pre W4 and post W1
    xline(ax, 0, '--', 'blinding', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
        'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'center', ...
        'FontSize', 10, 'HandleVisibility', 'off');

    plot(ax, all_wk, y, '-o', 'Color', line_color, 'LineWidth', line_width, ...
        'MarkerSize', marker_size, 'MarkerFaceColor', line_color, ...
        'MarkerEdgeColor', 'w', 'DisplayName', sprintf('%g \\muA', target_current_uA));
    yline(ax, 0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');

    xticks(ax, all_wk');
    xticklabels(ax, cellstr(week_labels(all_wk)));
    xlim(ax, [min(all_wk) - 0.5, max(all_wk) + 0.5]);
    xlabel(ax, 'Recording week', 'FontSize', font_size_axis);
    ylabel(ax, sprintf('ROI \\DeltaF/F at t = %+.2f s', t_read), 'FontSize', font_size_axis);
    title(ax, sprintf('%s  ch%d  |  %g \\muA  |  ROI \\DeltaF/F at t = %+.2f s', ...
        mouse, ch, target_current_uA, t_read), 'FontSize', font_size_title);
    legend(ax, 'Location', 'best', 'Box', 'off');
    grid(ax, 'on'); box(ax, 'on');

    if ~isempty(missing)
        subtitle(ax, sprintf('no ROI drawn for: %s', ...
            strjoin(cellstr(week_labels(missing)), ', ')), ...
            'FontSize', 9, 'Color', [0.5 0.2 0.2]);
    end

    png = sprintf('fig2_roi_%s_ch%d_%guA.png', mouse, ch, target_current_uA);
    exportgraphics(fig, fullfile(out_dir, png), 'Resolution', 150);
    close(fig);

    fprintf('%-14s t=%+.2fs  %d/%d week(s)%s\n', cf, t_read, ...
        nnz(isfinite(y)), numel(all_wk), ...
        ternary(isempty(missing), '', sprintf('  [gap: %s]', ...
            strjoin(cellstr(week_labels(missing)), ', '))));

    rows = [rows; table(repmat(string(mouse), numel(all_wk), 1), ...
        repmat(ch, numel(all_wk), 1), all_wk, week_labels(all_wk), ...
        repmat(target_current_uA, numel(all_wk), 1), ...
        repmat(t_read, numel(all_wk), 1), y, y_sham, ...
        'VariableNames', {'mouse', 'channel', 'week_index', 'week_label', ...
        'current_uA', 'readout_time_s', 'roi_dff', 'sham_0uA_dff'})]; %#ok<AGROW>
end

csv_file = fullfile(out_dir, 'fig2_roi_values.csv');
writetable(rows, csv_file);
fprintf('\nDone. Figures in:\n  %s\nValues: %s\n', out_dir, csv_file);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function y = sample_at(t, v, t_target)
[~, k] = min(abs(t - t_target));
y = v(k);
end

function L = week_labels(widx)
% Spelled out for slides ("pre week 1", "post week 4") via the shared helper.
L = strings(numel(widx), 1);
for i = 1:numel(widx)
    L(i) = string(wf_week_display_label(widx(i)));
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
