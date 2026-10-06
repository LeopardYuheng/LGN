%% extract_roi_traces.m
% Turn the hand-drawn ROIs into numbers, once, for every later figure.
%
% For every session that has an ROI (from draw_longitudinal_rois.m) and
% every current recorded that week, computes the mean dF/F inside the ROI at
% each frame — the same math as steps 8/8_B — and stores the whole trace.
%
% Storing the trace rather than one summary number matters: figures 2/3 read
% it at a fixed time, figures 5/6 read it per current, figures 7/8 compare it
% against the 0 uA sham. All of them then work off this one file instead of
% re-reading ~13 GB of movies each time.
%
% Sessions you deliberately skipped while drawing ROIs have no ROI and are
% simply absent here — they become gaps in the figures, never zeros.
%
% Reads:
%   <root>/rois_longitudinal.mat
%   the mean_dff files indexed by wf_scan_longitudinal.m
%
% Writes:
%   <root>/roi_traces.mat          full traces + metadata (authoritative)
%   <root>/roi_measurements.csv    one row per (channel, week, current)
%
% The CSV carries dF/F at the fixed read-out time used by figures 2/3
% (wf_roi_sample_time.m), plus the maximum and its latency for reference —
% the maximum is recorded but NOT what figures 2/3 plot.

close all; clc; clear; fclose('all');

%% -------------------------
% USER SETTINGS
% -------------------------
currents_to_extract = [];        % empty = every current present that week

% Reuse traces already in roi_traces.mat when the ROI behind them has not
% moved. Adding or redrawing one ROI then costs seconds instead of a full
% re-read of every movie; a redrawn circle is detected and recomputed.
reuse_existing      = true;
extra_sample_times  = [0.1 0.5]; % extra fixed read-outs written to the CSV
baseline_window_s   = [-inf 0];  % frames used for the pre-stimulus SD

%% -------------------------
% SCAN + LOAD ROIs
% -------------------------
root_dir = uigetdir('C:\Projects\LGN\weekly update\plots for presentation', ...
    'Select the longitudinal_data folder');
if isequal(root_dir, 0), error('No folder selected.'); end

S = wf_scan_longitudinal(root_dir);

roi_file = fullfile(root_dir, 'rois_longitudinal.mat');
assert(isfile(roi_file), ['No rois_longitudinal.mat in:\n  %s\n' ...
    'Run draw_longitudinal_rois.m first.'], root_dir);
L = load(roi_file);
rois = L.rois;
fprintf('Loaded %d ROI(s); tree holds %d session(s).\n', numel(rois), numel(S));

%% -------------------------
% EXTRACT
% -------------------------
traces_out = fullfile(root_dir, 'roi_traces.mat');
prev = [];
if reuse_existing && isfile(traces_out)
    P = load(traces_out);
    if isfield(P, 'R'), prev = P.R; end
    fprintf('Found %d earlier trace(s); reusing those whose ROI has not moved.\n', numel(prev));
end
n_reused = 0;

R = struct('mouse', {}, 'channel', {}, 'chan_folder', {}, 'week_folder', {}, ...
    'week_index', {}, 'week_label', {}, 'current_uA', {}, 't_s', {}, ...
    'trace', {}, 'n_roi_px', {}, 'roi_center', {}, 'roi_radius', {});

n_no_roi = 0;
bad_files = {};      % unreadable / corrupt .mat files, reported at the end

for si = 1:numel(S)
    s = S(si);
    ri = find(strcmp({rois.chan_folder}, s.chan_folder) & ...
              strcmp({rois.week_folder}, s.week_folder), 1);
    if isempty(ri)
        n_no_roi = n_no_roi + 1;
        fprintf('[%3d/%d] %-14s %-9s  no ROI — skipped\n', ...
            si, numel(S), s.chan_folder, s.week_label);
        continue;
    end
    roi = rois(ri);

    curs = s.currents;
    if ~isempty(currents_to_extract)
        curs = curs(ismember(curs, currents_to_extract));
    end
    if isempty(curs), continue; end

    fprintf('[%3d/%d] %-14s %-9s  %d current(s)\n', ...
        si, numel(S), s.chan_folder, s.week_label, numel(curs));

    for k = 1:numel(curs)
        fi = find(abs(s.currents - curs(k)) < 1e-9, 1);

        if ~isempty(prev)
            pk = find(strcmp({prev.chan_folder}, s.chan_folder) & ...
                strcmp({prev.week_folder}, s.week_folder) & ...
                abs([prev.current_uA] - curs(k)) < 1e-9, 1);
            if ~isempty(pk) && isequal(prev(pk).roi_center, roi.center) && ...
                    isequal(prev(pk).roi_radius, roi.radius)
                R(end+1) = prev(pk); %#ok<SAGROW>
                n_reused = n_reused + 1;
                continue;
            end
        end

        % A truncated / corrupt copy must not abort the whole batch: record
        % it and carry on, so one bad file costs one data point, not a run.
        try
            M = load(s.files{fi});
        catch ME
            warning('  UNREADABLE (%s): %s', ME.identifier, s.files{fi});
            bad_files{end+1, 1} = s.files{fi}; %#ok<SAGROW>
            continue;
        end
        if isfield(M, 'mean_dff_movie'), mv = M.mean_dff_movie;
        elseif isfield(M, 'dff_movie'),  mv = M.dff_movie;
        else, warning('  no dF/F movie in %s', s.files{fi}); continue; end
        t_s = double(M.t_s(:)');
        if isfield(M, 'final_mask'), brain = logical(M.final_mask);
        else,                        brain = ~all(isnan(mv), 3); end

        roi_mask = circle_mask(size(mv, 1), size(mv, 2), roi.center, roi.radius) & brain;
        n_px = nnz(roi_mask);
        if n_px == 0
            warning('  ROI has no in-brain pixel: %s %s %g uA', ...
                s.chan_folder, s.week_label, curs(k));
            continue;
        end

        R(end+1) = struct( ...
            'mouse', s.mouse, 'channel', s.channel, 'chan_folder', s.chan_folder, ...
            'week_folder', s.week_folder, 'week_index', s.week_index, ...
            'week_label', s.week_label, 'current_uA', curs(k), 't_s', t_s, ...
            'trace', roi_mean_trace(mv, roi_mask)', 'n_roi_px', n_px, ...
            'roi_center', roi.center, 'roi_radius', roi.radius); %#ok<SAGROW>
    end
end

assert(~isempty(R), 'Nothing extracted — are there ROIs for any session?');
fprintf('\n%d (session x current) trace(s): %d reused, %d newly read; %d session(s) had no ROI.\n', ...
    numel(R), n_reused, numel(R) - n_reused, n_no_roi);

if ~isempty(bad_files)
    fprintf('\n%d FILE(S) COULD NOT BE READ — re-copy these from the source:\n', ...
        numel(bad_files));
    for i = 1:numel(bad_files), fprintf('  %s\n', bad_files{i}); end
    writetable(table(string(bad_files), 'VariableNames', {'unreadable_file'}), ...
        fullfile(root_dir, 'unreadable_files.csv'));
    fprintf('Listed in %s\n', fullfile(root_dir, 'unreadable_files.csv'));
end

save(fullfile(root_dir, 'roi_traces.mat'), 'R', '-v7.3');
fprintf('Wrote %s\n', fullfile(root_dir, 'roi_traces.mat'));

%% -------------------------
% SUMMARY TABLE
% -------------------------
n = numel(R);
readout_time = nan(n, 1);
dff_readout  = nan(n, 1);
max_dff_post = nan(n, 1);
t_at_max     = nan(n, 1);
baseline_sd  = nan(n, 1);
extra = nan(n, numel(extra_sample_times));

for i = 1:n
    t = R(i).t_s;
    v = R(i).trace(:)';

    readout_time(i) = wf_roi_sample_time(R(i).mouse, R(i).channel);
    dff_readout(i)  = sample_at(t, v, readout_time(i));
    for j = 1:numel(extra_sample_times)
        extra(i, j) = sample_at(t, v, extra_sample_times(j));
    end

    post = t >= 0;
    if any(post)
        vp = v; vp(~post) = NaN;
        [mx, mi] = max(vp, [], 'omitnan');
        if isfinite(mx), max_dff_post(i) = mx; t_at_max(i) = t(mi); end
    end

    base = t >= baseline_window_s(1) & t <= baseline_window_s(2);
    if nnz(base) > 1, baseline_sd(i) = std(v(base), 'omitnan'); end
end

T = table(string({R.mouse}'), [R.channel]', string({R.chan_folder}'), ...
    string({R.week_folder}'), [R.week_index]', string({R.week_label}'), ...
    [R.current_uA]', [R.n_roi_px]', readout_time, dff_readout, ...
    max_dff_post, t_at_max, baseline_sd, ...
    'VariableNames', {'mouse', 'channel', 'chan_folder', 'week_folder', ...
    'week_index', 'week_label', 'current_uA', 'n_roi_px', ...
    'readout_time_s', 'dff_at_readout', 'max_dff_post', 't_at_max', 'baseline_sd'});

for j = 1:numel(extra_sample_times)
    cname = sprintf('dff_at_%s', strrep(sprintf('%.2fs', extra_sample_times(j)), '.', 'p'));
    T.(cname) = extra(:, j);
end

T = sortrows(T, {'mouse', 'channel', 'week_index', 'current_uA'});
csv_file = fullfile(root_dir, 'roi_measurements.csv');
writetable(T, csv_file);
fprintf('Wrote %s  (%d row(s))\n', csv_file, height(T));

%% =========================
% LOCAL FUNCTIONS
%% =========================

function m = circle_mask(H, W, c, r)
[xx, yy] = meshgrid(1:W, 1:H);
m = ((xx - c(1)).^2 + (yy - c(2)).^2) <= r^2;
end

function trace = roi_mean_trace(movie, roi_mask)
% Mean dF/F inside the ROI at every frame, ignoring NaN pixels. Same math as
% steps 8/8_B.
[H, W, T] = size(movie);
flat = reshape(movie, H * W, T);
trace = mean(flat(roi_mask(:), :), 1, 'omitnan')';
end

function y = sample_at(t, v, t_target)
% Value at the frame nearest t_target. No maximum search: the read-out time
% is fixed on purpose (see wf_roi_sample_time.m).
[~, k] = min(abs(t - t_target));
y = v(k);
end
