%% make_fig6_average_dose_response.m
% FIGURE 6 — figure 5 averaged across the selected channels.
%
%   x = stimulation current, y = mean ROI dF/F +/- SEM across channels,
%   each channel read at ITS fixed time (wf_roi_sample_time.m).
%
% Two curves:
%   week before blindness   0, 2, 4, 5, 6, 7 uA          (every channel)
%   high-current session    0, 3, 6, 8, 10, 12 uA        (12 uA is LGN24 only,
%                                                         LGN26 stopped at 10)
% n is printed at every point, because it is not constant: only the LGN24
% channels were tested at 12 uA.
%
% The equivalent-current construction from figure 5 is repeated on the mean
% curves: a horizontal dashed line at the mean pre-blind dF/F for 6 and 7 uA,
% and where it meets the post-blind curve, a vertical line labelled with the
% current now required for the same activation.
%
% Two versions are written:
%   absolute     mean dF/F as measured
%   normalised   each channel scaled to its own pre-blind 7 uA value = 100%,
%                so one large channel cannot dominate the mean
%
% Reads:  <root>/roi_traces.mat  (from extract_roi_traces.m)
% Writes: <root>/figure6_average_dose_response/fig6_average_absolute.png
%                                              fig6_average_normalised.png
%                                              fig6_channels.csv
%                                              fig6_values.csv

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
pre_week_index = -1;
post_week_min  = 5;

% Same selection as figure 5
exclude_keys = ["LGN24_45", "LGN24_101", "LGN24_43", ...
                "LGN26_49", "LGN26_51"];

reference_currents = [6 7];
ref_styles         = {':', '--'};
ref_colors         = {[0.45 0.45 0.45], [0.15 0.15 0.15]};

norm_reference_current = 7;     % per-channel 100% level for the normalised version

pre_color       = [0.12 0.47 0.71];
post_color      = [0.84 0.15 0.16];
marker_size     = 8;
line_width      = 2.0;
font_size_axis  = 12;
font_size_title = 14;

out_subfolder   = 'figure6_average_dose_response';

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

out_dir = fullfile(root_dir, out_subfolder);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

keys = unique(arrayfun(@(r) string(sprintf('%s_%d', r.mouse, r.channel)), R), 'stable');
keys = setdiff(keys, exclude_keys, 'stable');

%% -------------------------
% GATHER PER-CHANNEL CURVES
% -------------------------
pre_cur_all  = [];
post_cur_all = [];
ch_list = table();
per_ch = struct('key', {}, 'mouse', {}, 'channel', {}, 't_read', {}, ...
    'pre_cur', {}, 'pre_val', {}, 'post_cur', {}, 'post_val', {}, 'post_label', {});

for ki = 1:numel(keys)
    parts = split(keys(ki), '_');
    mouse = char(parts(1));
    ch    = str2double(parts(2));
    t_read = wf_roi_sample_time(mouse, ch);

    in_ch = strcmp({R.mouse}, mouse) & [R.channel] == ch;
    pre  = collect_curve(R, in_ch & [R.week_index] == pre_week_index, t_read);
    post = collect_curve(R, in_ch & [R.week_index] >= post_week_min, t_read);

    if isempty(pre.currents) || isempty(post.currents)
        fprintf('%-13s missing a curve — left out of the average.\n', keys(ki));
        continue;
    end

    per_ch(end+1) = struct('key', keys(ki), 'mouse', mouse, 'channel', ch, ...
        't_read', t_read, 'pre_cur', pre.currents, 'pre_val', pre.vals, ...
        'post_cur', post.currents, 'post_val', post.vals, ...
        'post_label', post.label); %#ok<SAGROW>

    pre_cur_all  = union(pre_cur_all,  pre.currents);
    post_cur_all = union(post_cur_all, post.currents);

    ch_list = [ch_list; table(string(mouse), ch, t_read, string(post.label), ...
        'VariableNames', {'mouse', 'channel', 'readout_time_s', ...
        'postblind_session'})]; %#ok<AGROW>
end

n_ch = numel(per_ch);
assert(n_ch > 0, 'No channel has both curves.');

fprintf('\nChannels averaged (n = %d):\n', n_ch);
for i = 1:n_ch
    fprintf('  %-6s ch%-4d  read-out t = %+.2f s   high-current session: %s\n', ...
        per_ch(i).mouse, per_ch(i).channel, per_ch(i).t_read, per_ch(i).post_label);
end
writetable(ch_list, fullfile(out_dir, 'fig6_channels.csv'));

%% -------------------------
% AVERAGE, ABSOLUTE AND NORMALISED
% -------------------------
for mode = ["absolute", "normalised"]
    [pre_m, pre_e, pre_n] = avg_at(per_ch, pre_cur_all,  'pre',  mode, norm_reference_current);
    [post_m, post_e, post_n] = avg_at(per_ch, post_cur_all, 'post', mode, norm_reference_current);

    fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 860 620]);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');

    errorbar(ax, pre_cur_all, pre_m, pre_e, '-o', 'Color', pre_color, ...
        'LineWidth', line_width, 'MarkerSize', marker_size, ...
        'MarkerFaceColor', pre_color, 'MarkerEdgeColor', 'w', 'CapSize', 6, ...
        'DisplayName', 'week before blindness');
    errorbar(ax, post_cur_all, post_m, post_e, '-o', 'Color', post_color, ...
        'LineWidth', line_width, 'MarkerSize', marker_size, ...
        'MarkerFaceColor', post_color, 'MarkerEdgeColor', 'w', 'CapSize', 6, ...
        'DisplayName', 'high-current session after blindness');

    all_cur = unique([pre_cur_all(:); post_cur_all(:)]);
    xticks(ax, all_cur');
    pad = 0.06 * (max(all_cur) - min(all_cur));
    xlim(ax, [min(all_cur) - pad, max(all_cur) + pad]);
    if mode == "absolute"
        yline(ax, 0, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    else
        yline(ax, 100, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    end

    pre_curve  = struct('currents', pre_cur_all(:),  'vals', pre_m(:));
    post_curve = struct('currents', post_cur_all(:), 'vals', post_m(:));
    eq = draw_equivalence(ax, pre_curve, post_curve, reference_currents, ...
        ref_styles, ref_colors);

    % n above each post-blind point (12 uA is LGN24 only). Placed on the
    % point rather than along the top edge, where it would run into the
    % legend.
    yl = ylim(ax);
    top = yl(2);
    for j = 1:numel(post_cur_all)
        if ~isfinite(post_m(j)), continue; end
        y_lab = post_m(j) + post_e(j) + 0.025 * diff(yl);
        text(ax, post_cur_all(j), y_lab, sprintf('n=%d', post_n(j)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 8, 'Color', post_color);
        top = max(top, y_lab + 0.04 * diff(yl));
    end
    ylim(ax, [yl(1) top]);

    xlabel(ax, 'Stimulation current (\muA)', 'FontSize', font_size_axis);
    if mode == "absolute"
        ylabel(ax, 'mean ROI \DeltaF/F', 'FontSize', font_size_axis);
    else
        ylabel(ax, sprintf('%% of pre-blind %g \\muA response', norm_reference_current), ...
            'FontSize', font_size_axis);
    end
    title(ax, sprintf('ROI \\DeltaF/F vs current  |  before blindness vs high-current session  |  n = %d channels', ...
        n_ch), 'FontSize', font_size_title);
    subtitle(ax, channel_summary(per_ch), 'FontSize', 9, 'Interpreter', 'none');
    legend(ax, 'Location', 'northwest', 'Box', 'off', 'Interpreter', 'none');
    grid(ax, 'on'); box(ax, 'on');

    png = sprintf('fig6_average_%s.png', mode);
    exportgraphics(fig, fullfile(out_dir, png), 'Resolution', 150);
    close(fig);
    fprintf('\nsaved: %s\n', png);

    for e = 1:numel(eq)
        if isfinite(eq(e).required_current)
            fprintf('  %s: %g uA before (%.4f) -> %.1f uA after\n', mode, ...
                eq(e).ref_current, eq(e).ref_dff, eq(e).required_current);
        else
            fprintf('  %s: %g uA before (%.4f) -> not reached within the currents tested\n', ...
                mode, eq(e).ref_current, eq(e).ref_dff);
        end
    end

    if mode == "absolute"
        vals = table([pre_cur_all(:); post_cur_all(:)], ...
            [repmat("week before blindness", numel(pre_cur_all), 1); ...
             repmat("high-current session", numel(post_cur_all), 1)], ...
            [pre_m(:); post_m(:)], [pre_e(:); post_e(:)], [pre_n(:); post_n(:)], ...
            'VariableNames', {'current_uA', 'session', 'mean_roi_dff', 'sem', 'n_channels'});
        writetable(vals, fullfile(out_dir, 'fig6_values.csv'));
    end
end

fprintf('\nFigures and tables in:\n  %s\n', out_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function c = collect_curve(R, mask, t_read)
c = struct('currents', [], 'vals', [], 'label', '');
idx = find(mask);
if isempty(idx), return; end
cur = [R(idx).current_uA];
[cur, ord] = sort(cur(:));
idx = idx(ord);
v = arrayfun(@(k) sample_at(R(k).t_s, R(k).trace, t_read), idx);
c.currents = cur(:);
c.vals = v(:);
c.label = wf_week_display_label(R(idx(1)).week_index);
end

function [m, e, n] = avg_at(per_ch, currents, which, mode, norm_ref)
% Mean / SEM / n across channels at each current. A channel that was not
% tested at a current simply does not contribute there.
m = nan(numel(currents), 1);
e = zeros(numel(currents), 1);
n = zeros(numel(currents), 1);

for j = 1:numel(currents)
    v = [];
    for i = 1:numel(per_ch)
        if strcmp(which, 'pre')
            cur = per_ch(i).pre_cur; val = per_ch(i).pre_val;
        else
            cur = per_ch(i).post_cur; val = per_ch(i).post_val;
        end
        k = find(abs(cur - currents(j)) < 1e-9, 1);
        if isempty(k), continue; end
        x = val(k);

        if mode == "normalised"
            kr = find(abs(per_ch(i).pre_cur - norm_ref) < 1e-9, 1);
            if isempty(kr) || ~isfinite(per_ch(i).pre_val(kr)) || per_ch(i).pre_val(kr) == 0
                continue;
            end
            x = x / per_ch(i).pre_val(kr) * 100;
        end
        if isfinite(x), v(end+1) = x; end %#ok<AGROW>
    end
    n(j) = numel(v);
    if isempty(v), continue; end
    m(j) = mean(v);
    if numel(v) > 1, e(j) = std(v) / sqrt(numel(v)); end
end
end

function s = channel_summary(per_ch)
bym = containers.Map();
for i = 1:numel(per_ch)
    if ~isKey(bym, per_ch(i).mouse), bym(per_ch(i).mouse) = {}; end
    lst = bym(per_ch(i).mouse);
    lst{end+1} = sprintf('ch%d', per_ch(i).channel); %#ok<AGROW>
    bym(per_ch(i).mouse) = lst;
end
parts = {};
ks = keys(bym);
for i = 1:numel(ks)
    parts{end+1} = sprintf('%s %s', ks{i}, strjoin(bym(ks{i}), ', ')); %#ok<AGROW>
end
s = strjoin(parts, '   |   ');
end

function eq = draw_equivalence(ax, pre, post, ref_currents, styles, colors)
eq = struct('ref_current', {}, 'ref_dff', {}, 'required_current', {});
xl = xlim(ax);
yl = ylim(ax);

for i = 1:numel(ref_currents)
    k = find(abs(pre.currents - ref_currents(i)) < 1e-9, 1);
    if isempty(k), continue; end
    y_ref = pre.vals(k);
    if ~isfinite(y_ref), continue; end

    xi = first_upward_crossing(post.currents, post.vals, y_ref);
    st = styles{min(i, numel(styles))};
    co = colors{min(i, numel(colors))};

    x_end = xl(2);
    if isfinite(xi), x_end = xi; end
    plot(ax, [xl(1) x_end], [y_ref y_ref], st, 'Color', co, 'LineWidth', 1.2, ...
        'HandleVisibility', 'off');
    text(ax, xl(1) + 0.01 * diff(xl), y_ref, sprintf(' %g \\muA before', ref_currents(i)), ...
        'Color', co, 'FontSize', 9, 'VerticalAlignment', 'bottom');

    if isfinite(xi)
        plot(ax, [xi xi], [yl(1) y_ref], st, 'Color', co, 'LineWidth', 1.2, ...
            'HandleVisibility', 'off');
        y_txt = yl(1) + (0.02 + 0.07 * (i - 1)) * diff(yl);
        text(ax, xi, y_txt, sprintf(' %.1f \\muA', xi), 'Color', co, ...
            'FontSize', 10, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    end

    eq(end+1) = struct('ref_current', ref_currents(i), 'ref_dff', y_ref, ...
        'required_current', xi); %#ok<AGROW>
end
ylim(ax, yl);
end

function xi = first_upward_crossing(x, y, y_ref)
xi = NaN;
if isempty(x) || ~isfinite(y_ref), return; end
if y(1) >= y_ref, xi = x(1); return; end
for i = 1:numel(x) - 1
    y1 = y(i); y2 = y(i + 1);
    if ~isfinite(y1) || ~isfinite(y2), continue; end
    if y1 < y_ref && y2 >= y_ref
        xi = x(i) + (y_ref - y1) * (x(i + 1) - x(i)) / (y2 - y1);
        return;
    end
end
end

function y = sample_at(t, v, t_target)
[~, k] = min(abs(t - t_target));
y = v(k);
end
