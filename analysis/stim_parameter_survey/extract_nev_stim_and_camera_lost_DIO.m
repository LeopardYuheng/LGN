% From a ripple recording (.nev file), extract the camera triggers and stim
% timings and save into a mat folder for later extraction.
% If DIO/camera event is missing, store TRAIN ONSETS as surrogate DIO.

clc; clear; close all; fclose('all');
addpath('C:\Users\LuanLab\OneDrive - Rice University\Documents\GitHub\Luan_lab_retinomap-pipeline\analysis\stim_parameter_survey\neuroshare');

%% =========================
% USER METADATA
%% =========================
prompt = { ...
    'Mouse ID (e.g., LGN11):', ...
    'Date (YYYYMMDD):', ...
    'Experiment ID (optional, e.g., WF_StimSurvey):', ...
    'Base name (default: dio_stim_timing):' ...
};

dlg_title = 'Session Metadata';
dims = [1 70];
definput = {'', '', '', 'dio_stim_timing'};

answ = inputdlg(prompt, dlg_title, dims, definput);
if isempty(answ)
    error('User cancelled metadata input.');
end

mouse_id      = string(strtrim(answ{1}));
date_str      = string(strtrim(answ{2}));
experiment_id = string(strtrim(answ{3}));
base_name     = string(strtrim(answ{4}));

if strlength(mouse_id)==0
    error('Mouse ID is required.');
end

if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be in YYYYMMDD format.');
end

try
    datetime(char(date_str), 'InputFormat', 'yyyyMMdd');
catch
    error('Invalid date. Must be a real date in YYYYMMDD format.');
end

if strlength(base_name)==0
    base_name = "dio_stim_timing";
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

[ns_status, hFile] = ns_OpenFile(completeFilePath); %#ok<NASGU>

is_ok = @(r) (isnumeric(r) && all(r(:)==0)) || ...
             (ischar(r)   && strcmpi(strtrim(r),'ns_OK')) || ...
             (isstring(r) && strcmpi(strtrim(r),"ns_OK"));

%% =========================
% 1) CAMERA TTL (optional)
%% =========================
targetReason = "SMA 4";
HIGH_VAL = 32767;

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

frame_times_s = [];
frame_idx = uint32([]);

if isempty(match)
    warning('Could not find Event entity with Reason "%s". Camera TTL not saved.', targetReason);
else
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

    if isempty(frame_times_s)
        warning('No camera rising edges found (value == %d).', HIGH_VAL);
    end
end

%% =========================
% 2) STIM PULSES (all stim channels)
%% =========================
stimEntityIDs = find([hFile.Entity(:).ElectrodeID] >= 5120);

stim_time_s   = [];
stim_channel  = [];
stim_entityID = [];

for ii = 1:numel(stimEntityIDs)
    eid = stimEntityIDs(ii);
    Nseg = hFile.Entity(eid).Count;
    if Nseg == 0
        continue;
    end

    ch = hFile.Entity(eid).ElectrodeID - 5120;

    ts = nan(Nseg,1);
    for j = 1:Nseg
        [ns_result, ts(j), ~, ~] = ns_GetSegmentData(hFile, eid, j);
        if ~is_ok(ns_result)
            ts(j) = NaN;
        end
    end
    ts = ts(~isnan(ts));

    stim_time_s   = [stim_time_s; ts]; %#ok<AGROW>
    stim_channel  = [stim_channel; repmat(uint16(ch), numel(ts), 1)]; %#ok<AGROW>
    stim_entityID = [stim_entityID; repmat(uint16(eid), numel(ts), 1)]; %#ok<AGROW>
end

[stim_time_s, ord] = sort(stim_time_s);
stim_channel  = stim_channel(ord);
stim_entityID = stim_entityID(ord);

%% =========================
% 3) TRAIN ONSETS = FIRST PULSE OF EACH TRAIN
%% =========================
gap_thr_s = 0.5;

onset_time_s    = [];
onset_channel   = [];
onset_train_idx = [];

ch_list = unique(stim_channel);

for c = 1:numel(ch_list)
    ch = ch_list(c);

    idxc = find(stim_channel == ch);
    t = stim_time_s(idxc);
    if isempty(t)
        continue;
    end

    dt = [inf; diff(t)];
    is_new_train = dt > gap_thr_s;

    t_on = t(is_new_train);

    onset_time_s     = [onset_time_s; t_on]; %#ok<AGROW>
    onset_channel    = [onset_channel; repmat(ch, numel(t_on), 1)]; %#ok<AGROW>
    onset_train_idx  = [onset_train_idx; uint32((1:numel(t_on))')]; %#ok<AGROW>
end

[onset_time_s, ord2] = sort(onset_time_s);
onset_channel   = onset_channel(ord2);
onset_train_idx = onset_train_idx(ord2);

%% =========================
% 4) MAP TO NEAREST FRAME INDEX (if camera exists)
%% =========================
stim_frame_idx = uint32([]);
onset_frame_idx = uint32([]);

if ~isempty(frame_times_s)
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
end

%% =========================
% 5) SAVE
%% =========================
session = struct();

% camera
session.frames.time_s = frame_times_s;
session.frames.idx    = frame_idx;

% all stim pulses
session.stim.time_s    = stim_time_s;
session.stim.channel   = stim_channel;
session.stim.entityID  = stim_entityID;
session.stim.frame_idx = stim_frame_idx;

% first pulse of each train
session.trains.time_s    = onset_time_s;
session.trains.channel   = onset_channel;
session.trains.train_idx = onset_train_idx;
session.trains.frame_idx = onset_frame_idx;

% ---- surrogate DIO fields using TRAIN ONSETS ----
% This is the key fallback you asked for.
session.dio.time_s    = onset_time_s;
session.dio.channel   = onset_channel;
session.dio.train_idx = onset_train_idx;
session.dio.frame_idx = onset_frame_idx;
session.dio.source    = 'train_onsets_from_stim_segments';

% metadata
session.metadata = struct();
session.metadata.mouse_id = mouse_id;
session.metadata.date_str = date_str;
session.metadata.experiment_id = experiment_id;
session.metadata.base_name = base_name;
session.metadata.file = completeFilePath;
session.metadata.saved_at = datestr(now);
session.metadata.camera_reason = targetReason;
session.metadata.camera_high_value = HIGH_VAL;
session.metadata.gap_thr_s = gap_thr_s;
session.metadata.dio_surrogate = true;
session.metadata.dio_note = 'DIO missing; session.dio uses first pulse of each stim train';

%% =========================
% SAVE PATH
%% =========================
saveName = sprintf('%s_%s_%s.mat', mouse_id, date_str, base_name);
savePath = fullfile(saveDir, saveName);

if exist(saveDir,'dir') ~= 7
    mkdir(saveDir);
end

save(savePath, 'session', '-v7.3');

%% =========================
% VALIDATION
%% =========================
S = load(savePath, 'session');

fprintf('\nSaved OK: %s\n', savePath);
fprintf('  frames: %d\n', numel(S.session.frames.time_s));
fprintf('  stim pulses: %d\n', numel(S.session.stim.time_s));
fprintf('  train onsets: %d\n', numel(S.session.trains.time_s));
fprintf('  surrogate dio events: %d\n', numel(S.session.dio.time_s));