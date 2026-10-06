%% plot_max_dff_vs_current_overlay.m
% Overlay several sessions' max-dF/F-vs-current curves on one axes.
%
% Reads the max_dff_vs_current_avg_*.mat files written by
% plot_circle_max_dff_vs_current.m (its cross-channel average) and plots
% every selected file's curve together in a single figure — one color per
% file, so e.g. two recording days can be compared directly.
%
% Files can be picked from several folders: the picker reopens until you
% choose "Done".
%
% Each curve's legend entry defaults to that file's saved date label
% (date_label) and is editable in one dialog before plotting, along with
% the figure title.
%
% The figure is shown on screen first; only afterwards are you asked where
% to save it (Cancel = keep the figure, save nothing).

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
% First two colors are the high-contrast pair used for a two-session
% comparison; later entries only matter if more files are selected.
curve_colors = [ ...
    0.12 0.47 0.71;   % blue
    0.84 0.15 0.16;   % red
    0.20 0.63 0.17;   % green
    0.58 0.40 0.74;   % purple
    1.00 0.50 0.05;   % orange
    0.09 0.75 0.81];  % cyan
curve_markers      = {'o', 's', '^', 'd', 'v', 'p'};
show_sem_errorbars = true;   % SEM across channels, if the file stores it
line_width         = 1.8;
marker_size        = 7;

%% -------------------------
% SELECT THE .mat FILES (repeat the picker to reach several folders)
% -------------------------
file_paths = {};
start_dir  = pwd;
while true
    [fn, fp] = uigetfile( ...
        {'*max_dff_vs_current_avg*.mat', 'Averaged max dF/F curves (*.mat)'; ...
         '*.mat', 'All MAT-files (*.mat)'}, ...
        'Select max_dff_vs_current_avg .mat file(s) — Ctrl+click for several', ...
        start_dir, 'MultiSelect', 'on');
    if isequal(fn, 0)
        if isempty(file_paths), error('No file selected.'); end
        break;                      % Cancel = done adding
    end
    if ischar(fn), fn = {fn}; end
    for i = 1:numel(fn)
        file_paths{end+1} = fullfile(fp, fn{i}); %#ok<AGROW>
    end
    start_dir = fp;

    more_choice = questdlg( ...
        sprintf('%d file(s) selected so far. Add more from another folder?', numel(file_paths)), ...
        'Add more files', 'Add more', 'Done', 'Done');
    if ~strcmp(more_choice, 'Add more'), break; end
end

file_paths = unique(file_paths, 'stable');
n_file = numel(file_paths);
fprintf('Selected %d file(s):\n', n_file);
for i = 1:n_file, fprintf('  %s\n', file_paths{i}); end
if n_file == 1
    warning('Only one file selected — the plot will show a single curve.');
end

%% -------------------------
% LOAD EVERY CURVE
% -------------------------
curves = struct('file', {}, 'currents_uA', {}, 'avg_max_dff', {}, 'sem_max_dff', {}, ...
    'n_ch_per_cur', {}, 'date_label', {}, 'subject_label', {}, 'resp_win_s', {}, ...
    'channels_used', {});

for i = 1:n_file
    S = load(file_paths{i});
    [~, base_i] = fileparts(file_paths{i});

    assert(isfield(S, 'currents_uA') && isfield(S, 'avg_max_dff'), ...
        ['Not a max_dff_vs_current_avg file (missing currents_uA / avg_max_dff):\n  %s\n' ...
         'Pick a file written by plot_circle_max_dff_vs_current.m.'], file_paths{i});

    x = double(S.currents_uA(:));
    y = double(S.avg_max_dff(:));
    assert(numel(x) == numel(y), ...
        'currents_uA (%d) and avg_max_dff (%d) lengths differ in:\n  %s', ...
        numel(x), numel(y), file_paths{i});

    if isfield(S, 'sem_max_dff') && numel(S.sem_max_dff) == numel(y)
        e = double(S.sem_max_dff(:));
    else
        e = zeros(size(y));
    end
    e(~isfinite(e)) = 0;

    curves(i).file          = file_paths{i};
    curves(i).currents_uA   = x;
    curves(i).avg_max_dff   = y;
    curves(i).sem_max_dff   = e;
    curves(i).n_ch_per_cur  = get_field_or(S, 'n_ch_per_cur', []);
    curves(i).date_label    = char(get_field_or(S, 'date_label', ''));
    curves(i).subject_label = char(get_field_or(S, 'subject_label', ''));
    curves(i).resp_win_s    = get_field_or(S, 'resp_win_s', []);
    curves(i).channels_used = get_field_or(S, 'channels_used', []);

    if isempty(curves(i).date_label), curves(i).date_label = base_i; end

    fprintf('  %s: %d current level(s), %s uA', base_i, numel(x), mat2str(x'));
    if ~isempty(curves(i).channels_used)
        fprintf(', %d channel(s) averaged', numel(curves(i).channels_used));
    end
    fprintf('\n');
end

% Comparing curves measured over different response windows is legitimate
% but worth knowing about, so say so rather than silently overlaying them.
wins = {curves.resp_win_s};
wins = wins(~cellfun(@isempty, wins));
if numel(wins) > 1 && ~all(cellfun(@(w) isequal(w, wins{1}), wins))
    warning(['The selected files do not all use the same response window. ' ...
             'Their maxima are taken over different time ranges.']);
end

%% -------------------------
% LEGEND ENTRIES + TITLE (pre-filled, editable)
% -------------------------
subj = unique({curves.subject_label});
subj = subj(~cellfun(@isempty, subj));
if isscalar(subj)
    default_title = sprintf('max dF/F  |  %s', subj{1});
else
    default_title = 'max dF/F';
end

prompts  = cell(n_file + 1, 1);
defaults = cell(n_file + 1, 1);
for i = 1:n_file
    [~, base_i] = fileparts(curves(i).file);
    prompts{i}  = sprintf('Legend entry for %s:', base_i);
    defaults{i} = curves(i).date_label;
end
prompts{end}  = 'Figure title:';
defaults{end} = default_title;

lbl_ans = inputdlg(prompts, 'Legend entries & title', [1 70], defaults);
if isempty(lbl_ans), error('Legend entries not specified. Cancelled.'); end

legend_labels = cell(n_file, 1);
for i = 1:n_file
    legend_labels{i} = strtrim(lbl_ans{i});
    if isempty(legend_labels{i}), legend_labels{i} = curves(i).date_label; end
end
plot_title = strtrim(lbl_ans{end});

%% -------------------------
% OVERLAY FIGURE
% -------------------------
fig = figure('Color', 'w', 'Position', [100 100 820 600], 'Name', plot_title);
ax  = axes(fig);
hold(ax, 'on');

handles = gobjects(n_file, 1);
for i = 1:n_file
    col = curve_colors(mod(i - 1, size(curve_colors, 1)) + 1, :);
    mrk = curve_markers{mod(i - 1, numel(curve_markers)) + 1};

    x  = curves(i).currents_uA;
    y  = curves(i).avg_max_dff;
    e  = curves(i).sem_max_dff;
    ok = isfinite(y);

    if show_sem_errorbars && any(e(ok) > 0)
        handles(i) = errorbar(ax, x(ok), y(ok), e(ok), ['-' mrk], ...
            'Color', col, 'LineWidth', line_width, 'MarkerSize', marker_size, ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'CapSize', 6);
    else
        handles(i) = plot(ax, x(ok), y(ok), ['-' mrk], ...
            'Color', col, 'LineWidth', line_width, 'MarkerSize', marker_size, ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'w');
    end
end

yline(ax, 0, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'HandleVisibility', 'off');

all_currents = unique(vertcat(curves.currents_uA));
xticks(ax, all_currents');
if numel(all_currents) > 1
    pad = 0.06 * (max(all_currents) - min(all_currents));
    if pad > 0, xlim(ax, [min(all_currents) - pad, max(all_currents) + pad]); end
end

xlabel(ax, 'Stimulation current (\muA)');
ylabel(ax, 'Max mean \DeltaF/F in circle of interest');
title(ax, plot_title, 'Interpreter', 'none');
legend(ax, handles, legend_labels, 'Location', 'best', 'Box', 'off', 'Interpreter', 'none');
grid(ax, 'on'); box(ax, 'on');

drawnow;

%% -------------------------
% OUTPUT — asked for only after the figure is on screen
% -------------------------
save_choice = questdlg('Save this plot?', 'Save output', 'Save', 'Do not save', 'Save');
if ~strcmp(save_choice, 'Save')
    fprintf('\nNot saved. Figure left open.\n');
    return;
end

save_dir = uigetdir(fileparts(file_paths{1}), ...
    'Select output folder for the plot (Cancel = do not save)');
if isequal(save_dir, 0)
    fprintf('\nNo output folder selected — not saved. Figure left open.\n');
    return;
end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

label_tag = strjoin(cellfun(@sanitize, legend_labels(:)', 'UniformOutput', false), '_vs_');
base_fname = sprintf('max_dff_vs_current_overlay_%s', label_tag);
if numel(base_fname) > 150, base_fname = base_fname(1:150); end

exportgraphics(fig, fullfile(save_dir, [base_fname '.png']), 'Resolution', 150);
fprintf('\nSaved figure: %s\n', fullfile(save_dir, [base_fname '.png']));

source_files = file_paths(:);
save(fullfile(save_dir, [base_fname '.mat']), ...
    'curves', 'legend_labels', 'plot_title', 'source_files');
fprintf('Saved data:   %s\n', fullfile(save_dir, [base_fname '.mat']));

%% =========================
% LOCAL FUNCTIONS
%% =========================

function v = get_field_or(S, name, default_val)
if isfield(S, name) && ~isempty(S.(name))
    v = S.(name);
else
    v = default_val;
end
end

function s = sanitize(str)
% Filename-safe version of a free-text label ('08/14/2026' -> '08_14_2026').
s = regexprep(char(str), '[^A-Za-z0-9]+', '_');
s = regexprep(s, '^_+|_+$', '');
if isempty(s), s = 'x'; end
end
