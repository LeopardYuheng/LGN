% From a ripple recoding (.nev file), extract the DIO triggers and the stim
% timings and save into a mat folder for later extraction 

clc; clear; close all; fclose('all');
addpath('C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\Code\neuroshare');

completeFilePath = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\wf_stim_ephys\WF_StimSurvey_20260210\ephys_154356.nev';
[ns_status, hFile] = ns_OpenFile(completeFilePath);

% Status checker (your Neuroshare returns 'ns_OK')
is_ok = @(r) (isnumeric(r) && all(r(:)==0)) || ...
             (ischar(r)   && strcmpi(strtrim(r),'ns_OK')) || ...
             (isstring(r) && strcmpi(strtrim(r),"ns_OK"));

mouse_id = string(input('Mouse ID (e.g., LGN11): ', 's'));
experiment_id = string(input('Experiment ID (e.g., WF_StimSurvey_20260210): ', 's'));

base_name = string(input('Base name (e.g., nev_timing): ', 's'));
if strlength(base_name)==0
    base_name = "dio_stim_timing";
end

%% =========================
% 1) CAMERA TTL (Reason = "SMA 1") -> frame_times_s
%% =========================
targetReason = "SMA 1";
HIGH_VAL = 32767;

isEvent  = strcmpi({hFile.Entity.EntityType}, 'Event');

reasonsCell = {hFile.Entity.Reason};
reasons = strings(size(reasonsCell));
for k = 1:numel(reasonsCell)
    r = reasonsCell{k};
    if isempty(r), reasons(k) = "";
    else,          reasons(k) = string(r);
    end
end

match = find(isEvent & strcmpi(reasons, targetReason));
assert(~isempty(match), 'Could not find Event entity with Reason "%s".', targetReason);
camEntityID = match(1);

[~, camInfo] = ns_GetEntityInfo(hFile, camEntityID);
Ncam = camInfo.ItemCount;

cam_time_s = nan(Ncam,1);
cam_value  = nan(Ncam,1);
for i = 1:Ncam
    [~, cam_time_s(i), cam_value(i)] = ns_GetEventData(hFile, camEntityID, i);
end

rising_mask = (cam_value == HIGH_VAL);
frame_times_s = cam_time_s(rising_mask);
frame_times_s = frame_times_s(:);
frame_idx     = uint32((1:numel(frame_times_s))');

assert(~isempty(frame_times_s), 'No camera rising edges found (value==%d).', HIGH_VAL);

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

%% =========================
% 5) SAVE (no tables)
%% =========================
session = struct();

session.frames.time_s = frame_times_s;   % double
session.frames.idx    = frame_idx;       % uint32

session.stim.time_s   = stim_time_s;     % double
session.stim.channel  = stim_channel;    % uint16
session.stim.entityID = stim_entityID;   % uint16 (optional)
session.stim.frame_idx = stim_frame_idx; % uint32 (optional alignment)

session.trains.time_s    = onset_time_s;      % double
session.trains.channel   = onset_channel;     % uint16
session.trains.train_idx = onset_train_idx;   % uint32
session.trains.frame_idx = onset_frame_idx;   % uint32 (optional alignment)

session.metadata = struct();
session.metadata.file = completeFilePath;
session.metadata.date = datestr(now);
session.metadata.camera_reason = targetReason;
session.metadata.camera_high_value = HIGH_VAL;
session.metadata.gap_thr_s = gap_thr_s;

saveDir  = 'C:\Users\LuanLab\OneDrive - Rice University\Desktop\LGN\wf_stim_ephys\wf_stimSurvey_20260216';
saveName = 'LGN11_wf_stim_from_data_extraction.mat';
savePath = fullfile(saveDir, saveName);

if exist(saveDir,'dir') ~= 7
    mkdir(saveDir);
end

save(savePath, 'session', '-v7.3');

% quick validation
S = load(savePath, 'session');
fprintf('\nSaved OK: %s\n', savePath);
fprintf('  frames: %d\n', numel(S.session.frames.time_s));
fprintf('  stim pulses: %d\n', numel(S.session.stim.time_s));
fprintf('  train onsets: %d\n', numel(S.session.trains.time_s));
