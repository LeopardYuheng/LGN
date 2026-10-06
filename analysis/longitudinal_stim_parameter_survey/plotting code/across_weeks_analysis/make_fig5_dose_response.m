%% make_fig5_dose_response.m
% FIGURE 5 — per channel, the dose-response curve before blindness against
% the one from the high-current session after blindness.
%
%   x = stimulation current, y = ROI dF/F at the channel's fixed read-out
%   time (wf_roi_sample_time.m) — never a per-current maximum search.
%
% Two curves per channel:
%   week before blindness   0, 2, 4, 5, 6, 7 uA
%   high-current session    0, 3, 6, 8, 10, 12 uA (LGN24, post week 6)
%                           0, 3, 6, 8, 10 uA     (LGN26, post week 5)
% They overlap at 0 and 6 uA, which anchors the comparison.
%
% EQUIVALENT-CURRENT CONSTRUCTION
% For each reference current before blindness (6 and 7 uA), a horizontal
% dashed line marks the dF/F it produced. Where that level meets the
% post-blind curve, a vertical dashed line drops to the axis and is labelled
% with the current now needed to reach the same activation. That gap is the
% figure's whole point: the response is not lost, it costs more current.
%
% If the post-blind curve never reaches the pre-blind level within the
% currents tested, the figure says so rather than extrapolating.
%
% Reads:  <root>/roi_traces.mat  (from extract_roi_traces.m)
% Writes: <root>/figure5_dose_response/version_A_current_x/*.png
%         <root>/figure5_dose_response/fig5_values.csv
%         <root>/figure5_dose_response/fig5_equivalent_currents.csv

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
pre_week_index   = -1;          % week before blindness
post_week_min    = 5;           % high-current session (post week 5 or 6)

% Channels dropped as unreliable / at the noise floor
exclude_keys = ["LGN24_45", "LGN24_101", "LGN24_43", ...
                "LGN26_49", "LGN26_51"];

reference_currents = [6 7];     % pre-blind levels to carry across
ref_styles         = {':', '--'};
ref_colors         = {[0.45 0.45 0.45], [0.15 0.15 0.15]};

pre_color        = [0.12 0.47 0.71];
post_color       = [0.84 0.15 0.16];
marker_size      = 7;
line_width       = 1.9;
font_size_axis   = 12;
font_size_title  = 13;

out_subfolder    = 'figure5_dose_response';

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

dir_A = fullfile(root_dir, out_subfolder, 'version_A_current_x');
if ~exist(dir_A, 'dir'), mkdir(dir_A); end

% Clear this script's own previous PNGs, so a channel dropped from the
% selection cannot linger in the folder and end up on a slide.
old = dir(fullfile(dir_A, 'fig5A_*.png'));
for i = 1:numel(old), delete(fullfile(old(i).folder, old(i).name)); end
if ~isempty(old), fprintf('Removed %d stale figure(s) from %s\n', numel(old), dir_A); end

%% -------------------------
% ONE FIGURE PER CHANNEL
% -------------------------
keys = unique(arrayfun(@(r) string(sprintf('%s_%d', r.mouse, r.channel)), R), 'stable');
keys = setdiff(keys, exclude_keys, 'stable');
fprintf('\nChannels included (%d): %s\n\n', numel(keys), strjoin(cellstr(keys), ', '));

rows = table();
eq_rows = table();

for ki = 1:numel(keys)
    parts = split(keys(ki), '_');
    mouse = char(parts(1));
    ch    = str2double(parts(2));
    t_read = wf_roi_sample_time(mouse, ch);

    in_ch = strcmp({R.mouse}, mouse) & [R.channel] == ch;
    pre  = collect_curve(R, in_ch & [R.week_index] == pre_week_index, t_read);
    post = collect_curve(R, in_ch & [R.week_index] >= post_week_min, t_read);

    if isempty(pre.currents)
        fprintf('%-13s no pre-blind curve — skipped.\n', keys(ki));
        continue;
    end

    fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 800 580]);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');

    plot(ax, pre.currents, pre.vals, '-o', 'Color', pre_color, 'LineWidth', line_width, ...
        'MarkerSize', marker_size, 'MarkerFaceColor', pre_color, ...
        'MarkerEdgeColor', 'w', 'DisplayName', 'week before blindness');
    note = '';
    if ~isempty(post.currents)
        plot(ax, post.currents, post.vals, '-o', 'Color', post_color, ...
            'LineWidth', line_width, 'MarkerSize', marker_size, ...
            'MarkerFaceColor', post_color, 'MarkerEdgeColor', 'w', ...
            'DisplayName', post.label);
    else
        note = 'no ROI for the high-current session — comparison missing';
    end

    all_cur = unique([pre.currents; post.currents]);
    xticks(ax, all_cur');
    pad = 0.06 * (max(all_cur) - min(all_cur));
    xlim(ax, [min(all_cur) - pad, max(all_cur) + pad]);
    yline(ax, 0, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');

    % --- equivalent-current construction ---
    eq = draw_equivalence(ax, pre, post, reference_currents, ref_styles, ref_colors);

    xlabel(ax, 'Stimulation current (\muA)', 'FontSize', font_size_axis);
    ylabel(ax, sprintf('ROI \\DeltaF/F at t = %+.2f s', t_read), 'FontSize', font_size_axis);
    title(ax, sprintf('%s  ch%d  |  ROI \\DeltaF/F at t = %+.2f s', mouse, ch, t_read), ...
        'FontSize', font_size_title);
    if ~isempty(note)
        subtitle(ax, note, 'FontSize', 9, 'Color', [0.5 0.2 0.2]);
    end
    legend(ax, 'Location', 'northwest', 'Box', 'off', 'Interpreter', 'none');
    grid(ax, 'on'); box(ax, 'on');

    exportgraphics(fig, fullfile(dir_A, sprintf('fig5A_%s_ch%d.png', mouse, ch)), ...
        'Resolution', 150);
    close(fig);

    fprintf('%-13s t=%+.2fs', keys(ki), t_read);
    for e = 1:numel(eq)
        if isfinite(eq(e).required_current)
            fprintf('  |  %g uA (%.3f) -> %.1f uA', eq(e).ref_current, ...
                eq(e).ref_dff, eq(e).required_current);
        else
            fprintf('  |  %g uA (%.3f) -> not reached', eq(e).ref_current, eq(e).ref_dff);
        end
        eq_rows = [eq_rows; table(string(mouse), ch, eq(e).ref_current, eq(e).ref_dff, ...
            eq(e).required_current, string(post.label), ...
            'VariableNames', {'mouse', 'channel', 'preblind_current_uA', ...
            'preblind_dff', 'required_current_uA_postblind', 'postblind_session'})]; %#ok<AGROW>
    end
    fprintf('\n');

    for c = 1:2
        if c == 1, cur = pre.currents; v = pre.vals; lab = 'week before blindness';
        else,      cur = post.currents; v = post.vals; lab = post.label; end
        if isempty(cur), continue; end
        rows = [rows; table(repmat(string(mouse), numel(cur), 1), ...
            repmat(ch, numel(cur), 1), repmat(string(lab), numel(cur), 1), ...
            repmat(t_read, numel(cur), 1), cur(:), v(:), ...
            'VariableNames', {'mouse', 'channel', 'session', 'readout_time_s', ...
            'current_uA', 'roi_dff'})]; %#ok<AGROW>
    end
end

writetable(rows, fullfile(root_dir, out_subfolder, 'fig5_values.csv'));
writetable(eq_rows, fullfile(root_dir, out_subfolder, 'fig5_equivalent_currents.csv'));
fprintf('\nFigures: %s\n', dir_A);
fprintf('Values:  %s\n', fullfile(root_dir, out_subfolder, 'fig5_values.csv'));
fprintf('Equivalent currents: %s\n', ...
    fullfile(root_dir, out_subfolder, 'fig5_equivalent_currents.csv'));

%% =========================
% LOCAL FUNCTIONS
%% =========================

function c = collect_curve(R, mask, t_read)
% Currents (ascending) and the ROI dF/F at the fixed read-out time.
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

function eq = draw_equivalence(ax, pre, post, ref_currents, styles, colors)
% Horizontal line at each pre-blind reference level; where it meets the
% post-blind curve, a vertical line marks the current now required.
eq = struct('ref_current', {}, 'ref_dff', {}, 'required_current', {});
xl = xlim(ax);
yl = ylim(ax);

for i = 1:numel(ref_currents)
    k = find(abs(pre.currents - ref_currents(i)) < 1e-9, 1);
    if isempty(k), continue; end
    y_ref = pre.vals(k);

    xi = NaN;
    if ~isempty(post.currents)
        xi = first_upward_crossing(post.currents, post.vals, y_ref);
    end

    st = styles{min(i, numel(styles))};
    co = colors{min(i, numel(colors))};

    % Horizontal: stop at the crossing when there is one
    x_end = xl(2);
    if isfinite(xi), x_end = xi; end
    plot(ax, [xl(1) x_end], [y_ref y_ref], st, 'Color', co, 'LineWidth', 1.1, ...
        'HandleVisibility', 'off');
    text(ax, xl(1) + 0.01 * diff(xl), y_ref, sprintf(' %g \\muA before', ref_currents(i)), ...
        'Color', co, 'FontSize', 8, 'VerticalAlignment', 'bottom');

    if isfinite(xi)
        plot(ax, [xi xi], [yl(1) y_ref], st, 'Color', co, 'LineWidth', 1.1, ...
            'HandleVisibility', 'off');
        % Stagger the labels vertically: the two required currents can land
        % within a fraction of a uA of each other and would overprint.
        y_txt = yl(1) + (0.02 + 0.07 * (i - 1)) * diff(yl);
        text(ax, xi, y_txt, sprintf(' %.1f \\muA', xi), ...
            'Color', co, 'FontSize', 9, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    end

    eq(end+1) = struct('ref_current', ref_currents(i), 'ref_dff', y_ref, ...
        'required_current', xi); %#ok<AGROW>
end
ylim(ax, yl);
end

function xi = first_upward_crossing(x, y, y_ref)
% Current at which the curve first rises to y_ref, linearly interpolated
% between the sampled currents. NaN when the curve never gets there, so the
% figure can say "not reached" instead of extrapolating past what was tested.
xi = NaN;
if isempty(x) || ~isfinite(y_ref), return; end
if y(1) >= y_ref
    xi = x(1);      % already at or above that level at the lowest current
    return;
end
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
