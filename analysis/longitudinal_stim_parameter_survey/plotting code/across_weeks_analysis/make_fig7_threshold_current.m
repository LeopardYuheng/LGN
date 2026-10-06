%% make_fig7_threshold_current.m
% FIGURE 7 — threshold current per week, one channel at a time.
%
%   x axis : recording week
%   y axis : lowest stimulation current that evoked a response that week
%
% THRESHOLD DEFINITION (see the generated THRESHOLD_CRITERION.md)
%   For each session, the 0 uA sham of that same session gives the noise
%   level: criterion = mean(sham ROI trace) + k * SD(sham ROI trace).
%   The threshold is the LOWEST TESTED current above 0 whose ROI dF/F at the
%   channel's fixed read-out time reaches that criterion.
%
%   No interpolation between tested currents: a threshold is only ever one
%   of the currents actually delivered, so the figure cannot claim a
%   precision the protocol does not have.
%
%   When no tested current reaches the criterion the threshold is CENSORED,
%   not missing: it is drawn at the highest current tested with an open
%   triangle and labelled "> 7 uA" (or "> 12 uA", "> 10 uA" — whatever that
%   session actually reached). Treating those as missing would quietly drop
%   exactly the weeks where the effect is strongest.
%
% Two plots per channel:
%   plot 1  every week the channel has, pre week 1 through the high-current
%           session — only for channels recorded across the full history
%   plot 2  week before blindness through the high-current session
%
% Channels with no ROI for the high-current session are skipped entirely:
% without that session there is nothing to compare the climb against.
%
% Reads:  <root>/roi_traces.mat  (from extract_roi_traces.m)
% Writes: <root>/figure7_threshold_current/plot1_all_weeks/*.png
%         <root>/figure7_threshold_current/plot2_from_preblind/*.png
%         <root>/figure7_threshold_current/fig7_thresholds.csv
%         <root>/figure7_threshold_current/THRESHOLD_CRITERION.md

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
sd_multiplier   = 3;             % criterion = sham mean + k * sham SD
sham_window_s   = [-inf inf];    % part of the 0 uA trace used for mean/SD

% Require the criterion to be met at the threshold current AND at every
% higher current tested that session. Raising the current must not lose the
% response, so a lone point that clears the criterion while the current
% above it falls back below is a noise excursion, not a threshold. With
% this off you get the first crossing, which near the noise floor reports
% thresholds that are not real.
require_sustained = true;

% Channels judged unreliable earlier (same as figures 3/5/6). Channels with
% no high-current ROI are skipped automatically and need not be listed.
exclude_keys    = ["LGN24_45", "LGN24_101"];

line_color      = [0.12 0.47 0.71];
censor_color    = [0.84 0.15 0.16];
marker_size     = 8;
line_width      = 1.8;
font_size_axis  = 12;
font_size_title = 13;

out_subfolder   = 'figure7_threshold_current';

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
dir1 = fullfile(out_dir, 'plot1_all_weeks');
dir2 = fullfile(out_dir, 'plot2_from_preblind');
for d = {out_dir, dir1, dir2}
    if ~exist(d{1}, 'dir'), mkdir(d{1}); end
end

%% -------------------------
% THRESHOLD PER (CHANNEL, WEEK)
% -------------------------
keys = unique(arrayfun(@(r) string(sprintf('%s_%d', r.mouse, r.channel)), R), 'stable');
rows = table();
n_plot1 = 0; n_plot2 = 0;
skipped_no_hi = strings(0, 1);

for ki = 1:numel(keys)
    parts = split(keys(ki), '_');
    mouse = char(parts(1));
    ch    = str2double(parts(2));
    t_read = wf_roi_sample_time(mouse, ch);
    in_ch = strcmp({R.mouse}, mouse) & [R.channel] == ch;

    weeks = unique([R(in_ch).week_index]);

    if ~any(weeks >= 5)
        skipped_no_hi(end+1, 1) = keys(ki); %#ok<SAGROW>
        continue;                % no ROI for the high-current session
    end
    if ismember(keys(ki), exclude_keys)
        fprintf('%-13s excluded by setting.\n', keys(ki));
        continue;
    end

    n_wk = numel(weeks);
    thr       = nan(n_wk, 1);
    censored  = false(n_wk, 1);
    max_cur   = nan(n_wk, 1);
    crit      = nan(n_wk, 1);

    for wi = 1:n_wk
        in_wk = in_ch & [R.week_index] == weeks(wi);

        k0 = find(in_wk & abs([R.current_uA]) < 1e-9, 1);
        if isempty(k0)
            fprintf('%-13s %s: no 0 uA sham — week skipped.\n', keys(ki), ...
                wf_week_display_label(weeks(wi)));
            continue;
        end
        sham = R(k0).trace(:)';
        t_sh = R(k0).t_s(:)';
        in_win = t_sh >= sham_window_s(1) & t_sh <= sham_window_s(2);
        crit(wi) = mean(sham(in_win), 'omitnan') + ...
            sd_multiplier * std(sham(in_win), 'omitnan');

        idx = find(in_wk & [R.current_uA] > 0);
        cur = [R(idx).current_uA];
        [cur, ord] = sort(cur(:));
        idx = idx(ord);
        val = arrayfun(@(k) sample_at(R(k).t_s, R(k).trace, t_read), idx);
        max_cur(wi) = max(cur);

        if require_sustained
            hit = [];
            for j = 1:numel(val)
                if all(val(j:end) >= crit(wi)), hit = j; break; end
            end
        else
            hit = find(val(:) >= crit(wi), 1);
        end
        if isempty(hit)
            thr(wi) = max_cur(wi);      % lower bound, flagged below
            censored(wi) = true;
        else
            thr(wi) = cur(hit);
        end
    end

    ok = isfinite(thr);
    lbl = arrayfun(@(w) string(wf_week_display_label(w)), weeks(:));
    rows = [rows; table(repmat(string(mouse), n_wk, 1), repmat(ch, n_wk, 1), ...
        weeks(:), lbl, repmat(t_read, n_wk, 1), crit(:), thr(:), censored(:), ...
        max_cur(:), ...
        'VariableNames', {'mouse', 'channel', 'week_index', 'week_label', ...
        'readout_time_s', 'criterion_dff', 'threshold_uA', 'censored', ...
        'max_current_tested_uA'})]; %#ok<AGROW>

    txt = strings(n_wk, 1);
    for wi = 1:n_wk
        if ~ok(wi),            txt(wi) = "--";
        elseif censored(wi),   txt(wi) = sprintf(">%g", thr(wi));
        else,                  txt(wi) = sprintf("%g", thr(wi));
        end
    end
    fprintf('%-13s t=%+.2fs  %s\n', keys(ki), t_read, ...
        strjoin(compose("%s:%s", lbl, txt), '  '));

    % --- plot 1: the full history (only if there are pre-blind weeks before
    %     the week before blindness) ---
    if any(weeks < -1)
        make_plot(weeks, thr, censored, max_cur, ok, false, ...
            fullfile(dir1, sprintf('fig7_thresh_all_%s_ch%d.png', mouse, ch)), ...
            sprintf('%s  ch%d  |  threshold current by week', mouse, ch), ...
            sd_multiplier, line_color, censor_color, marker_size, line_width, ...
            font_size_axis, font_size_title);
        n_plot1 = n_plot1 + 1;
    end

    % --- plot 2: week before blindness onward ---
    keep = weeks >= -1;
    make_plot(weeks(keep), thr(keep), censored(keep), max_cur(keep), ok(keep), true, ...
        fullfile(dir2, sprintf('fig7_thresh_pre_%s_ch%d.png', mouse, ch)), ...
        sprintf('%s  ch%d  |  threshold current from the week before blindness', mouse, ch), ...
        sd_multiplier, line_color, censor_color, marker_size, line_width, ...
        font_size_axis, font_size_title);
    n_plot2 = n_plot2 + 1;
end

if ~isempty(skipped_no_hi)
    fprintf('\nSkipped (no ROI for the high-current session): %s\n', ...
        strjoin(cellstr(skipped_no_hi), ', '));
end
fprintf('\n%d channel(s) with plot 1, %d with plot 2.\n', n_plot1, n_plot2);

csv_file = fullfile(out_dir, 'fig7_thresholds.csv');
writetable(rows, csv_file);
fprintf('Thresholds: %s\n', csv_file);

write_criterion_md(fullfile(out_dir, 'THRESHOLD_CRITERION.md'), ...
    sd_multiplier, sham_window_s, require_sustained);
fprintf('Criterion:  %s\n', fullfile(out_dir, 'THRESHOLD_CRITERION.md'));
fprintf('Figures in:\n  %s\n  %s\n', dir1, dir2);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function make_plot(weeks, thr, censored, max_cur, ok, preblind_label, fpath, ttl, ...
    k_sd, col, cen_col, ms, lw, fs_axis, fs_title)
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 800 540]);
ax = axes(fig); %#ok<LAXES>
hold(ax, 'on');

w = weeks(:); y = thr(:); c = censored(:); o = ok(:);

% One line through every week, censored points included as lower bounds
plot(ax, w(o), y(o), '-', 'Color', col, 'LineWidth', lw, 'HandleVisibility', 'off');

sel = o & ~c;
if any(sel)
    plot(ax, w(sel), y(sel), 'o', 'Color', col, 'MarkerSize', ms, ...
        'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 1, ...
        'DisplayName', 'threshold reached');
end
sel = o & c;
if any(sel)
    plot(ax, w(sel), y(sel), '^', 'Color', cen_col, 'MarkerSize', ms + 2, ...
        'MarkerFaceColor', 'w', 'LineWidth', 1.6, ...
        'DisplayName', 'not reached — lower bound');
    for i = find(sel)'
        text(ax, w(i), y(i), sprintf('  >%g \\muA', y(i)), 'Color', cen_col, ...
            'FontSize', 10, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');
    end
end

xline(ax, 0, '--', 'blinding', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
    'LabelVerticalAlignment', 'bottom', 'FontSize', 10, 'HandleVisibility', 'off');

xticks(ax, w');
labs = cell(numel(w), 1);
for i = 1:numel(w)
    if preblind_label && w(i) == -1
        labs{i} = 'week before blindness';
    else
        labs{i} = wf_week_display_label(w(i));
    end
end
xticklabels(ax, labs);
ax.TickLabelInterpreter = 'none';
ax.XAxis.FontSize = max(8, fs_axis - 3);
xlim(ax, [min(w) - 0.5, max(w) + 0.5]);

all_cur = unique([0; max_cur(isfinite(max_cur))]);
ylim(ax, [0, max(all_cur) + 1.5]);
yticks(ax, unique([0 2 3 4 5 6 7 8 10 12]));

xlabel(ax, 'Recording week', 'FontSize', fs_axis);
ylabel(ax, 'Threshold current (\muA)', 'FontSize', fs_axis);
title(ax, ttl, 'FontSize', fs_title);
subtitle(ax, sprintf(['lowest tested current reaching sham mean + %g x SD; ' ...
    'triangles = no tested current reached it'], k_sd), 'FontSize', 9);
legend(ax, 'Location', 'northwest', 'Box', 'off');
grid(ax, 'on'); box(ax, 'on');

exportgraphics(fig, fpath, 'Resolution', 150);
close(fig);
end

function y = sample_at(t, v, t_target)
[~, k] = min(abs(t - t_target));
y = v(k);
end

function write_criterion_md(fpath, k_sd, win, sustained)
if isinf(win(1)) && isinf(win(2))
    win_txt = 'the whole 0 uA trace';
else
    win_txt = sprintf('the 0 uA trace between %+.2f s and %+.2f s', win(1), win(2));
end

lines = {
'# Threshold current — what counts as a response'
''
'This is the rule used by figure 7 (`make_fig7_threshold_current.m`). It is'
'generated by the script, so it always matches the settings that produced'
'the figures next to it.'
''
'## The rule'
''
'For each **channel** and each **session** separately:'
''
'1. **Noise level from that session''s own 0 uA sham.** The ROI mean dF/F'
'   trace of the 0 uA condition is taken over '
sprintf('   %s, giving its mean and SD.', win_txt)
''
sprintf('2. **Criterion** = `mean(sham) + %g x SD(sham)`.', k_sd)
''
'3. **Threshold** = the *lowest tested current above 0 uA* whose ROI dF/F,'
'   read at that channel''s fixed read-out time, reaches the criterion'
sustained_line(sustained)
''
'## Things the rule deliberately does not do'
''
'- **No interpolation between tested currents.** A threshold is always one'
'  of the currents actually delivered (weekly sessions: 2, 4, 5, 6, 7 uA;'
'  high-current session: 3, 6, 8, 10, 12 uA for LGN24, up to 10 uA for'
'  LGN26). Reporting 6.4 uA would imply a resolution the protocol does not'
'  have.'
''
'- **No maximum search over time.** dF/F is read at the channel''s fixed'
'  read-out time (+0.1 s for LGN24 ch49 and ch55, +0.5 s otherwise, see'
'  `wf_roi_sample_time.m`). Searching for each current''s own peak would'
'  find the largest noise excursion at currents that evoke nothing, and'
'  would lower every threshold spuriously.'
''
'- **Nothing is dropped when the criterion is never reached.** That session'
'  is reported as censored — `> 7 uA` in a weekly session, `> 12 uA`'
'  (LGN24) or `> 10 uA` (LGN26) in the high-current session — drawn as an'
'  open triangle at the highest current tested. These are *lower bounds*,'
'  not measurements, and they are exactly the sessions where the effect is'
'  strongest, so discarding them would understate it.'
''
'## Reading the figures'
''
'- filled circle = threshold measured'
'- open triangle with `>` = no tested current reached the criterion'
'- the connecting line passes through both, so any segment ending at a'
'  triangle is a lower bound on how far the threshold actually climbed'
''
'## Why the sham and not a fixed dF/F cut-off'
''
'The 0 uA condition is recorded in the same session, through the same ROI,'
'with the same imaging conditions as the stimulated conditions it is'
'compared against. A fixed cut-off would instead move with GCaMP'
'expression, ROI size and week-to-week imaging quality.'
};

fid = fopen(fpath, 'w');
assert(fid > 0, 'Could not write %s', fpath);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function line = sustained_line(sustained)
if sustained
    line = ['   **and keeps reaching it at every higher current tested that ' ...
        'session**. Raising the current must not lose the response, so a ' ...
        'lone point that clears the criterion while the current above it ' ...
        'falls back below is treated as a noise excursion, not a threshold.'];
else
    line = '   (first crossing only; higher currents are not checked).';
end
end
