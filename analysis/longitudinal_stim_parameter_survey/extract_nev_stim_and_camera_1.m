% From a ripple recoding (.nev file), extract the DIO triggers and the stim
% timings and save into a mat folder for later extraction 

clc; clear; close all; fclose('all');
addpath(fullfile(fileparts(mfilename('fullpath')), 'neuroshare'));
%% =========================
% USER METADATA (subject + date, user-entered)
%% =========================
prompt = { ...
    'Mouse ID (e.g., LGN11):', ...
    'Date (YYYYMMDD):', ...
    
    'Experiment ID (optional, e.g., WF_StimSurvey):', ...
    'Base name (default: ripple_timing):' ...
};

dlg_title = 'Session Metadata';
dims = [1 70];
definput = {'', '', '', 'ripple_timing'};

answ = inputdlg(prompt, dlg_title, dims, definput);
if isempty(answ)
    error('User cancelled metadata input.');
end

mouse_id      = string(strtrim(answ{1}));
date_str      = string(strtrim(answ{3}));
experiment_id = string(strtrim(answ{2}));

base_name     = string(strtrim(answ{4}));

if strlength(mouse_id)==0
    error('Mouse ID is required.');
end

if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be in YYYYMMDD format.');
end

% Optional: validate real calendar date
try
    datetime(char(date_str), 'InputFormat', 'yyyyMMdd');
catch
    error('Invalid date. Must be a real date in YYYYMMDD format.');
end

if strlength(base_name)==0
    base_name = "ripple_timing";
end

saveDir = uigetdir(pwd, 'Select output folder to save session .mat');
if isequal(saveDir,0)
    error('No save folder selected.');
end
%% =========================
% Select .nev file
%% =========================

[nev_name, nev_path] = uigetfile('*.nev', 'Select Ripple .nev file');

if isequal(nev_name,0)
    error('No .nev file selected.');
end

completeFilePath = fullfile(nev_path, nev_name);

fprintf('Selected file:\n  %s\n', completeFilePath);

% Copy the .nev into an isolated temp folder so that ns_OpenFile does not
% auto-discover and index the companion .ns5/.ns6 continuous-data files
% (which can be tens of GB).  Step 1 only needs Event + Segment data, both
% of which live exclusively in the .nev.  The original file is never
% modified; only a temporary copy is opened.
tmp_nev_dir  = fullfile(tempdir, ['nev_step1_' datestr(now, 'yyyymmdd_HHMMSSFFF')]);
mkdir(tmp_nev_dir);
tmp_nev_path = fullfile(tmp_nev_dir, nev_name);
fprintf('Copying .nev to isolated temp folder (skips .ns5 indexing)...\n');
t_copy = tic;
copyfile(completeFilePath, tmp_nev_path);
fprintf('  copy done in %.1f s\n', toc(t_copy));
cleanup_nev_tmp = onCleanup(@() rmdir_safe(tmp_nev_dir));

[ns_status, hFile] = ns_OpenFile(tmp_nev_path);

% Status checker (your Neuroshare returns 'ns_OK')
is_ok = @(r) (isnumeric(r) && all(r(:)==0)) || ...
             (ischar(r)   && strcmpi(strtrim(r),'ns_OK')) || ...
             (isstring(r) && strcmpi(strtrim(r),"ns_OK"));

HIGH_VAL = 32767;

%% =========================
% Helper: read Ripple event stream by Reason
%% =========================
read_event_stream = @(targetReason) local_read_event_stream(hFile, targetReason, HIGH_VAL);


%% =========================
% 1) CAMERA TTL (Reason = "SMA 1") -> frame_times_s
%% =========================
targetReason = "SMA 1";
% Changed for 0208
% targetReason = "SMA 4";

[cam_time_s, cam_value, frame_times_s] = read_event_stream(targetReason);
frame_times_s = frame_times_s(:);
frame_idx     = uint32((1:numel(frame_times_s))');

assert(~isempty(frame_times_s), 'No camera rising edges found (value==%d).', HIGH_VAL);

%% =========================
% 1b) SMA 2 TTL (PulsePal) -> sma2_times_s
%% =========================
targetReason_sma2 = "SMA 2";

[sma2_time_s, sma2_value, sma2_times_s] = read_event_stream(targetReason_sma2);
if isempty(sma2_times_s)
    warning('Could not find Event entity with Reason "%s". SMA2 will be empty.', targetReason_sma2);
    sma2_idx     = uint32([]);
else
    sma2_idx     = uint32((1:numel(sma2_times_s))');

    fprintf('SMA2 rising edges found: %d\n', numel(sma2_times_s));
end

%% =========================
% 1c) SMA 3 camera-ready stream
% Store the full state-transition stream and a per-SMA1 trigger readiness mask.
%% =========================
targetReason_sma3 = "SMA 3";
[sma3_time_s, sma3_value, sma3_high_times_s] = read_event_stream(targetReason_sma3);

if isempty(sma3_time_s)
    warning('Could not find Event entity with Reason "%s". SMA3 camera-ready stream will be empty.', targetReason_sma3);
    sma3_idx = uint32([]);
    frame_ready_mask = true(size(frame_times_s));
    frame_times_ready_s = frame_times_s;
    sma3_ready_state_value = [];
    sma3_ready_state_mode = 'missing_sma3_fallback_all_ready';
else
    sma3_idx = uint32((1:numel(sma3_time_s))');

    % Infer whether the ready state is SMA3 high or low by checking which state
    % explains more camera triggers. This is more robust than hard-coding polarity.
    frame_ready_mask_high = false(size(frame_times_s));
    frame_ready_mask_low  = false(size(frame_times_s));
    for i = 1:numel(frame_times_s)
        last_state_idx = find(sma3_time_s <= frame_times_s(i), 1, 'last');
        if isempty(last_state_idx)
            frame_ready_mask_high(i) = false;
            frame_ready_mask_low(i)  = false;
        else
            frame_ready_mask_high(i) = (sma3_value(last_state_idx) == HIGH_VAL);
            frame_ready_mask_low(i)  = (sma3_value(last_state_idx) ~= HIGH_VAL);
        end
    end

    if sum(frame_ready_mask_high) >= sum(frame_ready_mask_low)
        frame_ready_mask = frame_ready_mask_high;
        sma3_ready_state_value = HIGH_VAL;
        sma3_ready_state_mode = 'high_is_ready';
    else
        frame_ready_mask = frame_ready_mask_low;
        sma3_ready_state_value = 0;
        sma3_ready_state_mode = 'low_is_ready';
    end

    frame_times_ready_s = frame_times_s(frame_ready_mask);

    fprintf('SMA3 events found: %d\n', numel(sma3_time_s));
    fprintf('Camera triggers while ready (SMA3 mode %s): %d / %d\n', ...
        sma3_ready_state_mode, numel(frame_times_ready_s), numel(frame_times_s));
end

frame_idx_ready = uint32((1:numel(frame_times_ready_s))');
%% =========================
% 2) STIM PULSES (all stim channels) -> stim_time_s, stim_channel
%% =========================
stimEntityIDs = find([hFile.Entity(:).ElectrodeID] >= 5120);

stim_time_s   = [];
stim_channel  = [];
stim_entityID = [];  % optional but cheap

for ii = 1:numel(stimEntityIDs)
    eid = stimEntityIDs(ii);
    Nseg = hFile.Entity(eid).Count;
    if Nseg == 0, continue; end

    ch = hFile.Entity(eid).ElectrodeID - 5120;  % channel index

    ts = nan(Nseg,1);
    for j = 1:Nseg
        [ns_result, ts(j), ~, ~] = ns_GetSegmentData(hFile, eid, j);
        if ~is_ok(ns_result), ts(j) = NaN; end
    end
    ts = ts(~isnan(ts));

    stim_time_s   = [stim_time_s; ts]; %#ok<AGROW>
    stim_channel  = [stim_channel; repmat(uint16(ch), numel(ts), 1)]; %#ok<AGROW>
    stim_entityID = [stim_entityID; repmat(uint16(eid), numel(ts), 1)]; %#ok<AGROW>
end

% sort by time
[stim_time_s, ord] = sort(stim_time_s);
stim_channel  = stim_channel(ord);
stim_entityID = stim_entityID(ord);

%% =========================
% 3) TRAIN ONSETS (per channel) -> onset_time_s, onset_channel, onset_train_idx
%% =========================
gap_thr_s = 0.5;  % seconds (adjust)

onset_time_s   = [];
onset_channel  = [];
onset_train_idx = [];

ch_list = unique(stim_channel);

for c = 1:numel(ch_list)
    ch = ch_list(c);

    idxc = find(stim_channel == ch);
    t = stim_time_s(idxc);
    if isempty(t), continue; end

    dt = [inf; diff(t)];
    is_new_train = dt > gap_thr_s;

    t_on = t(is_new_train);

    onset_time_s   = [onset_time_s; t_on]; %#ok<AGROW>
    onset_channel  = [onset_channel; repmat(ch, numel(t_on), 1)]; %#ok<AGROW>
    onset_train_idx = [onset_train_idx; uint32((1:numel(t_on))')]; %#ok<AGROW>
end

% sort onsets by time (optional)
[onset_time_s, ord2] = sort(onset_time_s);
onset_channel   = onset_channel(ord2);
onset_train_idx = onset_train_idx(ord2);

%% =========================
% 4) OPTIONAL: map stim times -> nearest frame index
%% =========================
% This gives you direct alignment without tables.
% If your stim always occurs within camera coverage, this is safe.
stim_frame_idx = uint32(zeros(size(stim_time_s)));
for i = 1:numel(stim_time_s)
    [~, j] = min(abs(frame_times_s - stim_time_s(i)));
    stim_frame_idx(i) = uint32(j);
end

onset_frame_idx = uint32(zeros(size(onset_time_s)));
for i = 1:numel(onset_time_s)
    [~, j] = min(abs(frame_times_s - onset_time_s(i)));
    onset_frame_idx(i) = uint32(j);
end

stim_frame_idx_ready = uint32(zeros(size(stim_time_s)));
onset_frame_idx_ready = uint32(zeros(size(onset_time_s)));

if ~isempty(frame_times_ready_s)
    for i = 1:numel(stim_time_s)
        [~, j] = min(abs(frame_times_ready_s - stim_time_s(i)));
        stim_frame_idx_ready(i) = uint32(j);
    end

    for i = 1:numel(onset_time_s)
        [~, j] = min(abs(frame_times_ready_s - onset_time_s(i)));
        onset_frame_idx_ready(i) = uint32(j);
    end
end

%% =========================
% 5) SAVE (no tables)
%% =========================
ripple_timing = struct();


ripple_timing.frames.time_s = frame_times_s;   % double
ripple_timing.frames.idx    = frame_idx;       % uint32

ripple_timing.frames_ready.time_s = frame_times_ready_s;   % double
ripple_timing.frames_ready.idx    = frame_idx_ready;       % uint32
ripple_timing.frames_ready.raw_frame_idx = uint32(find(frame_ready_mask)); % uint32
ripple_timing.frames_ready.ready_mask = logical(frame_ready_mask);         % logical wrt ripple_timing.frames


ripple_timing.sma2.time_s   = sma2_times_s;    % double
ripple_timing.sma2.idx      = sma2_idx;        % uint32
ripple_timing.sma2.event_time_s = sma2_time_s; % double
ripple_timing.sma2.event_value  = sma2_value;  % double

ripple_timing.stim.time_s   = stim_time_s;     % double
ripple_timing.stim.channel  = stim_channel;    % uint16
ripple_timing.stim.entityID = stim_entityID;   % uint16 (optional)
ripple_timing.stim.frame_idx = stim_frame_idx; % uint32 (optional alignment)
ripple_timing.stim.frame_idx_ready = stim_frame_idx_ready; % uint32

ripple_timing.trains.time_s    = onset_time_s;      % double
ripple_timing.trains.channel   = onset_channel;     % uint16
ripple_timing.trains.train_idx = onset_train_idx;   % uint32
ripple_timing.trains.frame_idx = onset_frame_idx;   % uint32 (optional alignment)
ripple_timing.trains.frame_idx_ready = onset_frame_idx_ready; % uint32

ripple_timing.sma3.time_s        = sma3_time_s;        % double
ripple_timing.sma3.value         = sma3_value;         % double
ripple_timing.sma3.high_times_s  = sma3_high_times_s;  % double
ripple_timing.sma3.idx           = sma3_idx;           % uint32

ripple_timing.metadata = struct();
ripple_timing.metadata.mouse_id = mouse_id;
ripple_timing.metadata.date_str = date_str;
ripple_timing.metadata.experiment_id = experiment_id;
ripple_timing.metadata.base_name = base_name;
ripple_timing.metadata.file = completeFilePath;
ripple_timing.metadata.date = datestr(now);
ripple_timing.metadata.camera_reason = targetReason;
ripple_timing.metadata.camera_high_value = HIGH_VAL;
ripple_timing.metadata.gap_thr_s = gap_thr_s;
ripple_timing.metadata.sma2_reason = targetReason_sma2;
ripple_timing.metadata.sma3_reason = targetReason_sma3;
ripple_timing.metadata.frames_ready_source = 'SMA1 triggers gated by latest SMA3 state';
ripple_timing.metadata.sma3_ready_state_mode = sma3_ready_state_mode;
ripple_timing.metadata.sma3_ready_state_value = sma3_ready_state_value;

% Legacy alias retained temporarily so older scripts can still load this file.
session = ripple_timing;

%% =========================
% SAVE PATH (standardized)
%% =========================



% Example: LGN11_20260223_ripple_timing.mat
saveName = sprintf('%s_%s_%s.mat', mouse_id, date_str, base_name);
savePath = fullfile(saveDir, saveName);

if exist(saveDir,'dir') ~= 7
    mkdir(saveDir);
end

save(savePath, 'ripple_timing', 'session', '-v7.3');

% quick validation
S = load(savePath, 'ripple_timing');
fprintf('\nSaved OK: %s\n', savePath);
fprintf('  frames: %d\n', numel(S.ripple_timing.frames.time_s));
fprintf('  frames_ready: %d\n', numel(S.ripple_timing.frames_ready.time_s));
fprintf('  stim pulses: %d\n', numel(S.ripple_timing.stim.time_s));
fprintf('  train onsets: %d\n', numel(S.ripple_timing.trains.time_s));

%% =========================
% Segmented timing diagnostic plots
%% =========================
segment_window_s = 10;
n_segments = 6;

if ~isempty(frame_times_s)
    seg_centers = linspace(frame_times_s(1), frame_times_s(end), n_segments);
    seg_starts = max(frame_times_s(1), seg_centers - segment_window_s/2);

    fig_seg = figure('Name','SMA1-SMA2-SMA3 segmented alignment','Color','w');
    tiledlayout(n_segments, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    for i = 1:n_segments
        ax = nexttile;
        hold(ax, 'on');

        t0 = seg_starts(i);
        t1 = min(frame_times_s(end), t0 + segment_window_s);

        cam_keep = frame_times_s >= t0 & frame_times_s <= t1;
        sma2_keep = sma2_times_s >= t0 & sma2_times_s <= t1;
        sma3_keep = sma3_time_s >= t0 & sma3_time_s <= t1;

        plot(ax, frame_times_s(cam_keep), 1.00 * ones(sum(cam_keep),1), ...
            'k.', 'MarkerSize', 10);

        if ~isempty(sma2_times_s)
            plot(ax, sma2_times_s(sma2_keep), 1.08 * ones(sum(sma2_keep),1), ...
                'g.', 'MarkerSize', 12);
        end

        if ~isempty(sma3_time_s)
            high_keep = sma3_keep & (sma3_value == HIGH_VAL);
            low_keep  = sma3_keep & (sma3_value ~= HIGH_VAL);

            plot(ax, sma3_time_s(high_keep), 1.16 * ones(sum(high_keep),1), ...
                'b.', 'MarkerSize', 12);
            plot(ax, sma3_time_s(low_keep), 1.24 * ones(sum(low_keep),1), ...
                'r.', 'MarkerSize', 12);
        end

        xlim(ax, [t0 t1]);
        ylim(ax, [0.96 1.28]);
        yticks(ax, [1.00 1.08 1.16 1.24]);
        yticklabels(ax, {'SMA1 camera','SMA2 PulsePal','SMA3 high','SMA3 low'});
        grid(ax, 'on');

        if i == 1
            title(ax, sprintf('Segmented alignment view (%0.1f s windows)', segment_window_s));
        end

        if i < n_segments
            set(ax, 'XTickLabel', []);
        else
            xlabel(ax, 'Time (s)');
        end

        text(ax, t0, 1.275, sprintf('  %.3f to %.3f s', t0, t1), ...
            'VerticalAlignment', 'top', 'FontSize', 9);
    end

    saveas(fig_seg, fullfile(saveDir, ...
        sprintf('%s_%s_sma_alignment_segments.png', mouse_id, date_str)));

    fig_end = figure('Name','SMA1-SMA2-SMA3 end zoom','Color','w');
    hold on;

    end_window_s = 30;
    t0 = max(frame_times_s(1), frame_times_s(end) - end_window_s);
    t1 = frame_times_s(end);

    cam_keep = frame_times_s >= t0 & frame_times_s <= t1;
    sma2_keep = sma2_times_s >= t0 & sma2_times_s <= t1;
    sma3_keep = sma3_time_s >= t0 & sma3_time_s <= t1;

    plot(frame_times_s(cam_keep), 1.00 * ones(sum(cam_keep),1), ...
        'k.', 'MarkerSize', 10);

    if ~isempty(sma2_times_s)
        plot(sma2_times_s(sma2_keep), 1.08 * ones(sum(sma2_keep),1), ...
            'g.', 'MarkerSize', 12);
    end

    if ~isempty(sma3_time_s)
        high_keep = sma3_keep & (sma3_value == HIGH_VAL);
        low_keep  = sma3_keep & (sma3_value ~= HIGH_VAL);

        plot(sma3_time_s(high_keep), 1.16 * ones(sum(high_keep),1), ...
            'b.', 'MarkerSize', 12);
        plot(sma3_time_s(low_keep), 1.24 * ones(sum(low_keep),1), ...
            'r.', 'MarkerSize', 12);
    end

    xlim([t0 t1]);
    ylim([0.96 1.28]);
    yticks([1.00 1.08 1.16 1.24]);
    yticklabels({'SMA1 camera','SMA2 PulsePal','SMA3 high','SMA3 low'});
    xlabel('Time (s)');
    title('End-of-session alignment zoom');
    grid on;

    saveas(fig_end, fullfile(saveDir, ...
        sprintf('%s_%s_sma_alignment_endzoom.png', mouse_id, date_str)));
end

function rmdir_safe(d)
% Removes the isolated temp folder. Only ever touches files inside the
% freshly-created temp folder -- never the original .nev/.nsX files.
try
    if exist(d, 'dir'), rmdir(d, 's'); end
catch
end
end

function [event_time_s, event_value, rising_times_s] = local_read_event_stream(hFile, targetReason, highVal)
isEvent  = strcmpi({hFile.Entity.EntityType}, 'Event');

reasonsCell = {hFile.Entity.Reason};
reasons = strings(size(reasonsCell));
for k = 1:numel(reasonsCell)
    r = reasonsCell{k};
    if isempty(r)
        reasons(k) = "";
    else
        reasons(k) = string(r);
    end
end

match = find(isEvent & strcmpi(reasons, targetReason));
if isempty(match)
    event_time_s = [];
    event_value = [];
    rising_times_s = [];
    return;
end

entityID = match(1);
[~, eventInfo] = ns_GetEntityInfo(hFile, entityID);
N = eventInfo.ItemCount;

event_time_s = nan(N,1);
event_value  = nan(N,1);
for i = 1:N
    [~, event_time_s(i), event_value(i)] = ns_GetEventData(hFile, entityID, i);
end

rising_times_s = event_time_s(event_value == highVal);
event_time_s = event_time_s(:);
event_value = event_value(:);
rising_times_s = rising_times_s(:);
end
