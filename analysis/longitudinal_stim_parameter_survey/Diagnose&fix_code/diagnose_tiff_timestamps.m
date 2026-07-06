%% diagnose_tiff_timestamps.m
% Analyse TIFF file modification timestamps to locate disk I/O slowdowns
% that may explain missing frames.
%
% Compares consecutive file modification times to detect any periods where
% saving was unusually slow (possible dropped frames).
%
% Only analyses files whose numeric index >= START_IDX (set below), so you
% can focus on the portion of the session where problems are suspected.
%
% READ-ONLY. This script only reads file metadata (timestamps from the OS);
% it does not open, modify, or delete any TIFF files.

clear; clc;

%% -------------------------
% USER SETTINGS
% -------------------------
START_IDX   = 29173;   % only analyse TIFF files with number >= this value
GAP_LO_S = 0.15;   % report intervals larger  than this (seconds)
GAP_HI_S = 0.90;   % report intervals smaller than this (seconds)

%% -------------------------
% SELECT TIFF FOLDER
% -------------------------
tiff_dir = uigetdir(pwd, 'Select folder containing TIFF files');
if isequal(tiff_dir, 0), error('No folder selected.'); end
fprintf('Folder: %s\n', tiff_dir);

%% -------------------------
% FIND AND SORT TIFF FILES
% -------------------------
files = [dir(fullfile(tiff_dir, '*.tif')); dir(fullfile(tiff_dir, '*.tiff'))];
assert(~isempty(files), 'No .tif/.tiff files found in:\n  %s', tiff_dir);

nums = nan(numel(files), 1);
for i = 1:numel(files)
    tok = regexp(files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    if ~isempty(tok), nums(i) = str2double(tok{1}); end
end

valid = isfinite(nums);
files = files(valid);
nums  = nums(valid);

[nums, ord] = sort(nums);
files = files(ord);

fprintf('Total TIFF files found: %d  (numbers %d – %d)\n', ...
    numel(nums), nums(1), nums(end));

%% -------------------------
% FILTER TO START_IDX AND ABOVE
% -------------------------
keep  = nums >= START_IDX;
files = files(keep);
nums  = nums(keep);

assert(~isempty(nums), 'No files found with number >= %d.', START_IDX);
fprintf('Analysing %d files with number >= %d  (%d – %d)\n\n', ...
    numel(nums), START_IDX, nums(1), nums(end));

%% -------------------------
% EXTRACT FILE MODIFICATION TIMESTAMPS
% -------------------------
% files(i).datenum  -- MATLAB serial date number stored directly by dir(),
%   sourced from the OS (NTFS on Windows: ~100ns resolution in the file
%   system; MATLAB preserves at least millisecond precision here).
%
% Avoid datenum(files(i).date): that converts a FORMATTED STRING such as
%   '01-Jul-2026 14:32:05', which only has 1-second resolution and makes
%   it impossible to distinguish 0.10 s from 0.20 s intervals.
fprintf('Reading file timestamps (using files.datenum for sub-second precision)...\n');

if ~isfield(files, 'datenum')
    error(['files.datenum field not available. ' ...
           'Upgrade to MATLAB R2019b or later, or use a different timestamp source.']);
end

mod_t   = [files.datenum]';            % MATLAB serial date number (ms-level on NTFS)
mod_t_s = (mod_t - mod_t(1)) * 86400; % seconds elapsed since the first file

fprintf('  Done. Span of modification times: %.1f s (%.1f min)\n\n', ...
    mod_t_s(end), mod_t_s(end)/60);

%% -------------------------
% INTER-FILE SAVE INTERVAL ANALYSIS
% -------------------------
dt = diff(mod_t_s);   % seconds between consecutive file saves

fprintf('Save interval statistics:\n');
fprintf('  min  = %.4f s\n', min(dt));
fprintf('  max  = %.4f s\n', max(dt));
fprintf('  mean = %.4f s  (expected ~%.4f s at 10 Hz)\n', mean(dt), 0.100);
fprintf('  std  = %.4f s\n\n', std(dt));

large_gaps = find(dt > GAP_LO_S & dt < GAP_HI_S);
fprintf('Save gaps in (%.2f s, %.2f s): %d found\n', GAP_LO_S, GAP_HI_S, numel(large_gaps));

if ~isempty(large_gaps)
    fprintf('\n%-10s  %-10s  %-12s  %-10s\n', ...
        'TIFF#(from)', 'TIFF#(to)', 'Gap(s)', 'Time_from_start(s)');
    fprintf('%s\n', repmat('-', 1, 55));
    for k = 1:numel(large_gaps)
        gi = large_gaps(k);
        fprintf('%-10d  %-10d  %-12.3f  %-10.1f\n', ...
            nums(gi), nums(gi+1), dt(gi), mod_t_s(gi));
    end
end

%% -------------------------
% SUMMARY FIGURE
% -------------------------
fig = figure('Color','w','Name','TIFF save interval diagnostic','Position',[50 50 1300 500]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing','compact','Padding','compact');

% Left: full interval trace
ax1 = nexttile(tl);
plot(ax1, nums(1:end-1), dt, '.', 'MarkerSize', 3, 'Color', [0.3 0.5 0.9]);
hold(ax1,'on');
if ~isempty(large_gaps)
    plot(ax1, nums(large_gaps), dt(large_gaps), 'r.', 'MarkerSize', 10);
end
yline(ax1, GAP_LO_S, '--r', sprintf('lo=%.2fs', GAP_LO_S), 'LineWidth', 1.0);
yline(ax1, GAP_HI_S, '--m', sprintf('hi=%.2fs', GAP_HI_S), ...
    'LineWidth', 1.0);
xlabel(ax1, 'TIFF file number');
ylabel(ax1, 'Inter-file save interval (s)');
title(ax1, sprintf('Save intervals  |  files %d – %d', nums(1), nums(end)));
grid(ax1,'on');

% Right: histogram of intervals
ax2 = nexttile(tl);
histogram(ax2, dt, 50, 'FaceColor',[0.3 0.5 0.9], 'EdgeColor','none');
xline(ax2, GAP_LO_S, '--r', 'LineWidth', 1.0);
xline(ax2, GAP_HI_S, '--m', 'LineWidth', 1.0);
xlabel(ax2, 'Interval (s)');
ylabel(ax2, 'Count');
title(ax2, 'Histogram of save intervals');
grid(ax2,'on');

title(tl, sprintf('TIFF save-timestamp diagnostic  |  start idx = %d  |  interval window (%.2f, %.2f) s', ...
    START_IDX, GAP_LO_S, GAP_HI_S), 'FontSize', 11);

out_png = fullfile(tiff_dir, sprintf('tiff_timestamp_diagnostic_from%d_lo%.2f_hi%.2f.png', ...
    START_IDX, GAP_LO_S, GAP_HI_S));
exportgraphics(fig, out_png, 'Resolution', 150);
fprintf('\nFigure saved: %s\n', out_png);
fprintf('Done.\n');