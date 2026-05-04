%% minimal_qc_end_anchor_alignment.m
% Minimal QC script to:
% 1) load TIFFs and compute a V1-only fluorescence trace
% 2) compare TIFF frame count vs ephys camera trigger count
% 3) test for likely double-edge counting
% 4) compare first-anchored vs end-anchored alignment
% 5) overlay candidate stim frame indices on the V1 trace
%
% Assumes:
% - one TIFF = one saved frame
% - your wf_trial_alignment file contains wf_trial_alignment.V1_mask_stim and wf_trial_alignment.session_mat
% - your timing file contains ripple_timing.frames.time_s
% - if available, session.trains.time_s / onset_s / start_s will be used
%   for principled first-vs-last anchoring
%
% If train times are NOT available, the script falls back to a frame-index
% shift test using the already-computed train_frame_idx values.

clear; clc; close all;

%% ---------------- USER INPUTS ----------------
out_file = 'C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-03-17\analysis\LGN11_20260317_wf_trial_alignment.mat';

% Speed option for TIFF reading
frame_step = 1;   % use 1 for every frame, 5 for quick QC

% Peak detection for optional event visualization
peak_thresh_z = 2.5;
peak_min_dist_frames = 10;

%% ---------------- LOAD OUT + SESSION ----------------
A = load(out_file);
if isfield(A, 'wf_trial_alignment')
    out = A.wf_trial_alignment;
elseif isfield(A, 'out')
    out = A.out;
else
    error('File must contain variable "wf_trial_alignment" or legacy variable "out".');
end

assert(isfield(out, 'V1_mask_stim') && ~isempty(out.V1_mask_stim), ...
    'out.V1_mask_stim missing.');
V1_mask = logical(out.V1_mask_stim);

assert(isfield(out, 'img_dir') && isfolder(out.img_dir), ...
    'out.img_dir missing or invalid.');
img_dir = out.img_dir;

assert(isfield(out, 'session_mat') && isfile(out.session_mat), ...
    'out.session_mat missing or invalid.');
S = load(out.session_mat);
if isfield(S, 'ripple_timing')
    session = S.ripple_timing;
elseif isfield(S, 'session')
    session = S.session;
else
    error('Timing file must contain variable "ripple_timing" or legacy variable "session".');
end

assert(isfield(session, 'frames') && isfield(session.frames, 'time_s'), ...
    'session.frames.time_s missing.');
cam_trigger_times_s = double(session.frames.time_s(:));

assert(isfield(out, 'trial_onset_frame_idx'), 'out.trial_onset_frame_idx missing.');
train_frame_idx = double(out.trial_onset_frame_idx(:));

n_trains = numel(train_frame_idx);
n_cam_events = numel(cam_trigger_times_s);

fprintf('\nLoaded out file: %s\n', out_file);
fprintf('Ephys camera trigger events: %d\n', n_cam_events);
fprintf('Stim trains: %d\n', n_trains);

%% ---------------- LOAD TIFF LIST ----------------
image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    image_files = dir(fullfile(img_dir, '*.tiff'));
end
assert(~isempty(image_files), 'No TIFF files found.');

% sort by trailing number if present
nFiles = numel(image_files);
nums = nan(nFiles,1);
for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.tif{1,2}$', 'tokens', 'once');
    if ~isempty(tok)
        nums(i) = str2double(tok{1});
    else
        nums(i) = i;
    end
end
[~, ord] = sort(nums);
image_files = image_files(ord);

n_tiffs = numel(image_files);
fprintf('Saved TIFF frames: %d\n', n_tiffs);
fprintf('Ratio (ephys camera events / TIFFs): %.3f\n', n_cam_events / n_tiffs);

%% ---------------- CAMERA TRIGGER DIAGNOSTICS ----------------
dt = diff(cam_trigger_times_s);

figure('Color','w');
histogram(dt, 100);
xlabel('Inter-event interval (s)');
ylabel('Count');
title('Ephys camera trigger inter-event intervals');

% Simple double-edge collapse:
% keep only events separated by > 50 ms
keep_oneedge = [true; diff(cam_trigger_times_s) > 0.05];
cam_times_oneedge_s = cam_trigger_times_s(keep_oneedge);

fprintf('\nAfter collapsing close camera events (>50 ms rule):\n');
fprintf('Collapsed camera events: %d\n', numel(cam_times_oneedge_s));
fprintf('Ratio (collapsed camera events / TIFFs): %.3f\n', numel(cam_times_oneedge_s) / n_tiffs);

%% ---------------- COMPUTE V1 TRACE FROM TIFFS ----------------
idx_read = 1:frame_step:n_tiffs;
v1_trace = nan(numel(idx_read), 1);

fprintf('\nComputing V1 trace using every %d frame(s)...\n', frame_step);

for k = 1:numel(idx_read)
    i = idx_read(k);
    frame = double(imread(fullfile(img_dir, image_files(i).name)));

    if k == 1
        assert(isequal(size(frame), size(V1_mask)), ...
            'Frame size (%d x %d) does not match V1 mask size (%d x %d).', ...
            size(frame,1), size(frame,2), size(V1_mask,1), size(V1_mask,2));
    end

    v1_trace(k) = mean(frame(V1_mask), 'omitnan');
end

v1_trace_z = (v1_trace - median(v1_trace, 'omitnan')) ./ std(v1_trace, [], 'omitnan');

figure('Color','w');
plot(idx_read, v1_trace_z, 'k');
xlabel('Frame');
ylabel('V1 fluorescence (z-score)');
title(sprintf('V1 trace (every %d frame(s))', frame_step));
grid on;

% Optional peak detection
[pks, locs_sub] = findpeaks(v1_trace_z, ...
    'MinPeakHeight', peak_thresh_z, ...
    'MinPeakDistance', peak_min_dist_frames);
locs_full = idx_read(locs_sub);

hold on;
plot(locs_full, pks, 'ro', 'MarkerSize', 4);
legend({'V1 trace', 'Detected peaks'});

fprintf('Detected V1 peaks above %.2f z: %d\n', peak_thresh_z, numel(locs_full));

%% ---------------- TRY TO GET STIM TIMES ----------------
stim_times_s = [];
if isfield(session, 'trains')
    if isfield(session.trains, 'time_s')
        stim_times_s = double(session.trains.time_s(:));
    elseif isfield(session.trains, 'onset_s')
        stim_times_s = double(session.trains.onset_s(:));
    elseif isfield(session.trains, 'start_s')
        stim_times_s = double(session.trains.start_s(:));
    end
end

have_stim_times = ~isempty(stim_times_s) && numel(stim_times_s) == n_trains;

%% ---------------- FIRST- VS END-ANCHORED TEST ----------------
if have_stim_times
    fprintf('\nStim train times found in session.trains.*\n');

    % Use collapsed one-edge camera events if that count is closer to TIFF count,
    % otherwise use raw camera events.
    if abs(numel(cam_times_oneedge_s) - n_tiffs) < abs(numel(cam_trigger_times_s) - n_tiffs)
        cam_base_s = cam_times_oneedge_s;
        fprintf('Using collapsed camera events for alignment.\n');
    else
        cam_base_s = cam_trigger_times_s;
        fprintf('Using raw camera events for alignment.\n');
    end

    assert(numel(cam_base_s) >= n_tiffs, ...
        'Chosen camera event vector has fewer entries than TIFF frames.');

    frame_times_first_s = cam_base_s(1:n_tiffs);
    frame_times_last_s  = cam_base_s(end - n_tiffs + 1 : end);

    % validity: stim time must lie within the chosen TIFF time window
    valid_first = stim_times_s >= frame_times_first_s(1) & stim_times_s <= frame_times_first_s(end);
    valid_last  = stim_times_s >= frame_times_last_s(1)  & stim_times_s <= frame_times_last_s(end);

    stim_frame_first = nan(n_trains,1);
    stim_frame_last  = nan(n_trains,1);

    for i = 1:n_trains
        if valid_first(i)
            [~, stim_frame_first(i)] = min(abs(frame_times_first_s - stim_times_s(i)));
        end
        if valid_last(i)
            [~, stim_frame_last(i)] = min(abs(frame_times_last_s - stim_times_s(i)));
        end
    end

    fprintf('\nFirst-anchored valid stim trials: %d / %d\n', sum(valid_first), n_trains);
    fprintf('End-anchored valid stim trials:   %d / %d\n', sum(valid_last),  n_trains);

    % peak matching score
    tol_frames = max(2, round(5 / frame_step));  % loose tolerance on subsampled trace

    score_first = 0;
    score_last  = 0;

    stim_frame_first_sub = round((stim_frame_first - 1) / frame_step) + 1;
    stim_frame_last_sub  = round((stim_frame_last  - 1) / frame_step) + 1;
    peak_sub = round((locs_full - 1) / frame_step) + 1;

    for i = 1:n_trains
        if ~isnan(stim_frame_first_sub(i))
            if any(abs(peak_sub - stim_frame_first_sub(i)) <= tol_frames)
                score_first = score_first + 1;
            end
        end
        if ~isnan(stim_frame_last_sub(i))
            if any(abs(peak_sub - stim_frame_last_sub(i)) <= tol_frames)
                score_last = score_last + 1;
            end
        end
    end

    fprintf('Peak-match score, first-anchored: %d\n', score_first);
    fprintf('Peak-match score, end-anchored:   %d\n', score_last);

    % overlay on V1 trace
    figure('Color','w');
    plot(idx_read, v1_trace_z, 'k'); hold on;
    yl = ylim;

    good_first = stim_frame_first(~isnan(stim_frame_first));
    good_last  = stim_frame_last(~isnan(stim_frame_last));

    for i = 1:numel(good_first)
        xline(good_first(i), 'b-');
    end
    for i = 1:numel(good_last)
        xline(good_last(i), 'r-');
    end

    plot(locs_full, pks, 'ko', 'MarkerSize', 4);
    ylim(yl);
    xlabel('Frame');
    ylabel('V1 fluorescence (z-score)');
    title('V1 trace with first-anchored (blue) and end-anchored (red) stim frames');
    grid on;

    % frame-index views
    figure('Color','w');

    subplot(2,1,1);
    stem(stim_frame_first, 'b', 'filled');
    hold on;
    yline(1, '--k');
    yline(n_tiffs, '--k');
    title(sprintf('First-anchored stim frame indices (valid = %d / %d)', sum(valid_first), n_trains));
    xlabel('Stim train #');
    ylabel('Frame index');

    subplot(2,1,2);
    stem(stim_frame_last, 'r', 'filled');
    hold on;
    yline(1, '--k');
    yline(n_tiffs, '--k');
    title(sprintf('End-anchored stim frame indices (valid = %d / %d)', sum(valid_last), n_trains));
    xlabel('Stim train #');
    ylabel('Frame index');

else
    fprintf('\nNo stim train times found in session.trains.time_s/onset_s/start_s.\n');
    fprintf('Falling back to frame-index end-shift test only.\n');

    shift_to_end = n_tiffs - max(train_frame_idx);
    train_frame_idx_end = train_frame_idx + shift_to_end;

    valid_original = train_frame_idx >= 1 & train_frame_idx <= n_tiffs;
    valid_end      = train_frame_idx_end >= 1 & train_frame_idx_end <= n_tiffs;

    fprintf('Original valid frame_idx: %d / %d\n', sum(valid_original), n_trains);
    fprintf('End-shift valid frame_idx: %d / %d\n', sum(valid_end), n_trains);

    % simple peak match score
    tol_frames = max(2, round(5 / frame_step));
    peak_sub = round((locs_full - 1) / frame_step) + 1;

    original_sub = round((train_frame_idx - 1) / frame_step) + 1;
    end_sub      = round((train_frame_idx_end - 1) / frame_step) + 1;

    score_original = 0;
    score_end = 0;

    for i = 1:n_trains
        if valid_original(i)
            if any(abs(peak_sub - original_sub(i)) <= tol_frames)
                score_original = score_original + 1;
            end
        end
        if valid_end(i)
            if any(abs(peak_sub - end_sub(i)) <= tol_frames)
                score_end = score_end + 1;
            end
        end
    end

    fprintf('Peak-match score, original frame_idx: %d\n', score_original);
    fprintf('Peak-match score, end-shifted frame_idx: %d\n', score_end);

    figure('Color','w');
    plot(idx_read, v1_trace_z, 'k'); hold on;
    yl = ylim;

    good_orig = train_frame_idx(valid_original);
    good_end  = train_frame_idx_end(valid_end);

    for i = 1:numel(good_orig)
        xline(good_orig(i), 'b-');
    end
    for i = 1:numel(good_end)
        xline(good_end(i), 'r-');
    end

    plot(locs_full, pks, 'ko', 'MarkerSize', 4);
    ylim(yl);
    xlabel('Frame');
    ylabel('V1 fluorescence (z-score)');
    title('V1 trace with original (blue) and end-shifted (red) frame indices');
    grid on;

    figure('Color','w');

    subplot(2,1,1);
    stem(train_frame_idx, 'b', 'filled');
    hold on;
    yline(1, '--k');
    yline(n_tiffs, '--k');
    title(sprintf('Original out.trial_onset_frame_idx (valid = %d / %d)', sum(valid_original), n_trains));
    xlabel('Stim train #');
    ylabel('Frame index');

    subplot(2,1,2);
    stem(train_frame_idx_end, 'r', 'filled');
    hold on;
    yline(1, '--k');
    yline(n_tiffs, '--k');
    title(sprintf('End-shifted frame_idx (valid = %d / %d)', sum(valid_end), n_trains));
    xlabel('Stim train #');
    ylabel('Frame index');
end

fprintf('\nDone.\n');
