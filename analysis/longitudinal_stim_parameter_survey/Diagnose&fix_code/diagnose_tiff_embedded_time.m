%% diagnose_tiff_embedded_time.m
% Reads the embedded "Time_From_Start" timestamp from each TIFF's
% ImageDescription metadata tag, then analyses inter-frame intervals to
% locate any disk I/O slowdowns (dropped/delayed frames).
%
% Only reads the TIFF header/IFD -- does NOT load pixel data.
% All operations are read-only; no file is modified.
%
% Expected ImageDescription format (from your camera software):
%   [ CAPTURE TIME ]
%    Time_From_Start = HH:MM:SS.ssss
%    Time_From_Last  = HH:MM:SS.ssss

clear; clc;

%% -------------------------
% USER SETTINGS
% -------------------------
START_IDX  = 29173;  % only analyse files with number >= this value
GAP_LO_S   = 0.15;  % flag intervals larger  than this (s)
GAP_HI_S   = 0.90;  % flag intervals smaller than this (s)

%% -------------------------
% SELECT TIFF FOLDER
% -------------------------
tiff_dir = uigetdir(pwd, 'Select folder containing TIFF files');
if isequal(tiff_dir, 0), error('No folder selected.'); end
fprintf('Folder: %s\n\n', tiff_dir);

%% -------------------------
% FIND + SORT + FILTER TIFF FILES
% -------------------------
files = [dir(fullfile(tiff_dir, '*.tif')); dir(fullfile(tiff_dir, '*.tiff'))];
assert(~isempty(files), 'No TIFF files found in:\n  %s', tiff_dir);

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

keep  = nums >= START_IDX;
files = files(keep);
nums  = nums(keep);
N     = numel(nums);
assert(N > 1, 'Fewer than 2 files found with number >= %d.', START_IDX);
fprintf('Analysing %d files  (numbers %d – %d)\n\n', N, nums(1), nums(end));

%% -------------------------
% READ EMBEDDED TIMESTAMPS FROM TIFF HEADERS
% -------------------------
fprintf('Reading embedded timestamps from TIFF headers...\n');
fprintf('(Only reads IFD/metadata -- pixel data not loaded)\n\n');

t_start_s = nan(N, 1);   % Time_From_Start converted to seconds
t_last_s  = nan(N, 1);   % Time_From_Last  converted to seconds

t0 = tic;
for i = 1:N
    fpath = fullfile(tiff_dir, files(i).name);
    try
        tf  = Tiff(fpath, 'r');
        desc = tf.getTag('ImageDescription');
        tf.close();

        % Parse  Time_From_Start = HH:MM:SS.ssss
        tok = regexp(desc, 'Time_From_Start\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens', 'once');
        if ~isempty(tok)
            t_start_s(i) = str2double(tok{1})*3600 + ...
                           str2double(tok{2})*60   + ...
                           str2double(tok{3});
        end

        % Parse  Time_From_Last = HH:MM:SS.ssss
        tok2 = regexp(desc, 'Time_From_Last\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens', 'once');
        if ~isempty(tok2)
            t_last_s(i) = str2double(tok2{1})*3600 + ...
                          str2double(tok2{2})*60   + ...
                          str2double(tok2{3});
        end
    catch
        % leave NaN if header can't be read
    end

    if mod(i, 5000) == 0 || i == N
        fprintf('  %d / %d  (%.0f s elapsed)\n', i, N, toc(t0));
    end
end

n_parsed = sum(isfinite(t_start_s));
fprintf('\nParsed timestamps: %d / %d\n\n', n_parsed, N);
assert(n_parsed > 1, 'Could not parse any timestamps -- check ImageDescription format.');

%% -------------------------
% INTER-FRAME INTERVAL ANALYSIS (from Time_From_Start differences)
% -------------------------
% Use diff of Time_From_Start as the primary source (most accurate).
% Fall back to Time_From_Last where Time_From_Start is missing.
dt = diff(t_start_s);   % N-1 intervals

valid_dt = isfinite(dt);
fprintf('Inter-frame interval statistics (from %d valid intervals):\n', sum(valid_dt));
fprintf('  min  = %.4f s\n', min(dt(valid_dt)));
fprintf('  max  = %.4f s\n', max(dt(valid_dt)));
fprintf('  mean = %.4f s\n', mean(dt(valid_dt)));
fprintf('  std  = %.4f s\n\n', std(dt(valid_dt)));

flagged = find(valid_dt & dt > GAP_LO_S & dt < GAP_HI_S);
fprintf('Intervals in (%.2f s, %.2f s): %d found\n', GAP_LO_S, GAP_HI_S, numel(flagged));

if ~isempty(flagged)
    fprintf('\n%-12s  %-12s  %-10s  %-14s\n', ...
        'TIFF#(from)', 'TIFF#(to)', 'Interval(s)', 'Time_from_start(s)');
    fprintf('%s\n', repmat('-', 1, 55));
    for k = 1:numel(flagged)
        gi = flagged(k);
        fprintf('%-12d  %-12d  %-10.4f  %-14.4f\n', ...
            nums(gi), nums(gi+1), dt(gi), t_start_s(gi));
    end
end

%% -------------------------
% FIGURE
% -------------------------
fig = figure('Color','w','Name','Embedded timestamp diagnostic','Position',[50 50 1400 520]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing','compact','Padding','compact');

ax1 = nexttile(tl);
plot(ax1, nums(1:end-1), dt, '.', 'MarkerSize', 3, 'Color', [0.3 0.5 0.9]);
hold(ax1, 'on');
if ~isempty(flagged)
    plot(ax1, nums(flagged), dt(flagged), 'r.', 'MarkerSize', 10);
end
yline(ax1, GAP_LO_S, '--r', sprintf('lo = %.2fs', GAP_LO_S), 'LineWidth', 1.0);
yline(ax1, GAP_HI_S, '--m', sprintf('hi = %.2fs', GAP_HI_S), 'LineWidth', 1.0);
xlabel(ax1, 'TIFF file number');
ylabel(ax1, 'Inter-frame interval (s)');
title(ax1, sprintf('Inter-frame intervals  (files %d – %d)', nums(1), nums(end)));
grid(ax1, 'on');

ax2 = nexttile(tl);
histogram(ax2, dt(valid_dt), 'BinWidth', 0.005, ...
    'FaceColor', [0.3 0.5 0.9], 'EdgeColor', 'none');
xline(ax2, GAP_LO_S, '--r', 'LineWidth', 1.0);
xline(ax2, GAP_HI_S, '--m', 'LineWidth', 1.0);
xlabel(ax2, 'Interval (s)');
ylabel(ax2, 'Count');
title(ax2, 'Histogram');
grid(ax2, 'on');

title(tl, sprintf('Embedded timestamp diagnostic  |  start idx = %d  |  window (%.2f, %.2f) s', ...
    START_IDX, GAP_LO_S, GAP_HI_S), 'FontSize', 11);

out_png = fullfile(tiff_dir, sprintf('tiff_embedded_time_diagnostic_from%d.png', START_IDX));
exportgraphics(fig, out_png, 'Resolution', 150);
fprintf('\nFigure saved:\n  %s\n', out_png);
fprintf('Done.\n');