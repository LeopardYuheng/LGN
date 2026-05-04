% This script:
%   - Loads {subject}_{date}_dio_stim_timing.mat (contains "session")
%   - Loads reference_mask.mat
%   - Sorts TIFF filenames
%   - Verifies frame alignment
%   - Loads CSV (trial_index, stim_chan, current_uA)
%   - Builds clean bookkeeping struct "out"
%
% It does NOT compute trial maps or ΔF/F.
%
% Output:
%   analysis/{subject}_{date}_wf_stim_aligned_out.mat

close all; clc; clear; fclose('all');

%% -------------------------
% Select inputs
% -------------------------

img_dir = uigetdir(pwd, 'Select folder containing TIFF frames');
if isequal(img_dir,0), error('No image folder selected.'); end

[mask_name, mask_path] = uigetfile('*.mat', 'Select reference_mask.mat');
if isequal(mask_name,0), error('No mask selected.'); end
mask_file = fullfile(mask_path, mask_name);

[ses_name, ses_path] = uigetfile('*.mat', 'Select {subject}_{date}_dio_stim_timing.mat');
if isequal(ses_name,0), error('No session file selected.'); end
session_mat = fullfile(ses_path, ses_name);

[csv_name, csv_path] = uigetfile({'*.csv;*.txt'}, ...
    'Select CSV (trial_index, stim_chan, current_uA)');
if isequal(csv_name,0), error('No CSV selected.'); end
csv_file = fullfile(csv_path, csv_name);

%% -------------------------
% Pull subject + date from session_mat (preferred)
% -------------------------

Xmeta = load(session_mat, 'session');
assert(isfield(Xmeta,'session'), 'Session file must contain variable "session".');
session_meta = Xmeta.session;

subject_id = '';
date_str   = '';

% 1) Preferred: stored metadata inside session.metadata
if isfield(session_meta,'metadata')
    md = session_meta.metadata;

    % subject
    if isfield(md,'mouse_id') && ~isempty(md.mouse_id)
        subject_id = char(string(md.mouse_id));
    elseif isfield(md,'subject_id') && ~isempty(md.subject_id)
        subject_id = char(string(md.subject_id));
    end

    % date
    if isfield(md,'date_str') && ~isempty(md.date_str)
        date_str = char(string(md.date_str));
    end
end

% 2) Backup: parse from session_mat filename: {subject}_{YYYYMMDD}_*.mat
if isempty(strtrim(subject_id)) || isempty(strtrim(date_str))
    [~, ses_base, ~] = fileparts(session_mat);
    tok = regexp(ses_base, '^(?<subj>[^_]+)_(?<date>\d{8})_', 'names', 'once');
    if ~isempty(tok)
        if isempty(strtrim(subject_id)), subject_id = tok.subj; end
        if isempty(strtrim(date_str)),   date_str   = tok.date; end
    end
end

% 3) Final fallback: prompt user
if isempty(strtrim(subject_id)) || isempty(strtrim(date_str))
    prompt = {'Enter subject ID (e.g., LGN11):', 'Enter date (YYYYMMDD):'};
    dlg_title = 'Metadata (missing from session file)';
    dims = [1 60];
    definput = {subject_id, date_str};

    answer = inputdlg(prompt, dlg_title, dims, definput);
    if isempty(answer)
        error('User cancelled metadata input.');
    end

    subject_id = strtrim(answer{1});
    date_str   = strtrim(answer{2});
end

% Validate
if isempty(subject_id)
    error('Subject ID is required.');
end
if isempty(regexp(date_str, '^\d{8}$', 'once'))
    error('Date must be in YYYYMMDD format.');
end

fprintf('Metadata:\n  subject_id = %s\n  date_str   = %s\n', subject_id, date_str);

%% -------------------------
% Load session + mask
% -------------------------

S = load(mask_file);
assert(isfield(S,'final_mask'), 'Mask must contain final_mask');
final_mask = S.final_mask;
if isfield(S,'crop_rect'), crop_rect = S.crop_rect;
else, crop_rect = [];
end

X = load(session_mat,'session');
assert(isfield(X,'session'), 'Session file must contain variable "session"');
session = X.session;

assert(isfield(session,'frames') && isfield(session.frames,'time_s'), ...
    'session.frames.time_s missing');

frame_times_s = session.frames.time_s(:);
dt = diff(frame_times_s);
assert(~isempty(dt), 'Not enough frame times.');
Freq = 1 / median(dt);

assert(isfield(session,'trains') && isfield(session.trains,'frame_idx'), ...
    'session.trains.frame_idx missing');
assert(isfield(session.trains,'channel'), ...
    'session.trains.channel missing');

train_frame_idx = double(session.trains.frame_idx(:));
train_channel   = double(session.trains.channel(:));
n_trains = numel(train_frame_idx);

fprintf('Found %d stim trains.\n', n_trains);
fprintf('Estimated camera rate: %.3f Hz\n', Freq);

%% -------------------------
% Sort TIFF files
% -------------------------

image_files = dir(fullfile(img_dir, '*.tif'));
assert(~isempty(image_files), 'No TIFF files found.');

nFiles = numel(image_files);
nums = nan(nFiles,1);

for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.tif$', 'tokens', 'once');
    if isempty(tok)
        error('Filename "%s" missing trailing index.', image_files(i).name);
    end
    nums(i) = str2double(tok{1});
end

[~,ord] = sort(nums);
image_files = image_files(ord);

fprintf('Total TIFF frames: %d\n', numel(image_files));

%% -------------------------
% Load CSV mapping
% -------------------------

Tcsv = readtable(csv_file);
vars = lower(string(Tcsv.Properties.VariableNames));

col_trial = find(vars=="trial_index" | vars=="trial" | vars=="trial_idx", 1);
col_chan  = find(vars=="stim_chan" | vars=="channel" | vars=="stim_channel", 1);
col_curr  = find(vars=="current_ua" | vars=="current" | vars=="current_level", 1);

assert(~isempty(col_trial) && ~isempty(col_chan) && ~isempty(col_curr), ...
    'CSV must contain trial_index, stim_chan, current_uA');

trial_index_csv = double(Tcsv{:,col_trial});
stim_chan_csv   = double(Tcsv{:,col_chan});
current_uA_csv  = double(Tcsv{:,col_curr});

% Clean rows
keep = isfinite(trial_index_csv) & isfinite(stim_chan_csv) & isfinite(current_uA_csv);
trial_index_csv = trial_index_csv(keep);
stim_chan_csv   = stim_chan_csv(keep);
current_uA_csv  = current_uA_csv(keep);

%% -------------------------
% Build aligned trial vectors
% -------------------------

trial_stim_chan  = nan(n_trains,1);
trial_current_uA = nan(n_trains,1);

if all(ismember(1:n_trains, trial_index_csv))
    trial_stim_chan(trial_index_csv)  = stim_chan_csv;
    trial_current_uA(trial_index_csv) = current_uA_csv;
else
    M = min(numel(stim_chan_csv), n_trains);
    trial_stim_chan(1:M)  = stim_chan_csv(1:M);
    trial_current_uA(1:M) = current_uA_csv(1:M);
    warning('CSV not 1:N mapping. Used row-order fallback.');
end

%% -------------------------
% Validate frame indices
% -------------------------

valid_idx = train_frame_idx >= 1 & train_frame_idx <= numel(image_files);
if ~all(valid_idx)
    warning('%d stim trains have frame_idx outside TIFF range.', ...
        sum(~valid_idx));
end

%% -------------------------
% Build BASE struct
% -------------------------

out = struct();

out.subject_id = subject_id;
out.date_str   = date_str;

out.img_dir     = img_dir;
out.mask_file   = mask_file;
out.session_mat = session_mat;
out.csv_file    = csv_file;

out.image_files_sorted = {image_files.name}';
out.n_frames           = numel(image_files);

out.Freq          = Freq;
out.frame_times_s = frame_times_s;

out.trial_onset_frame_idx = train_frame_idx;
out.trial_channel         = train_channel;
out.trial_stim_chan       = trial_stim_chan;
out.trial_current_uA      = trial_current_uA;

out.n_trials   = n_trains;

out.mask_size  = size(final_mask);
out.crop_rect  = crop_rect;

out.created_on = datestr(now);

%% -------------------------
% Save
% -------------------------

analysisFolder = fullfile(fileparts(img_dir), 'analysis');
if ~exist(analysisFolder,'dir'), mkdir(analysisFolder); end

saveName = sprintf('%s_%s_wf_stim_aligned_out.mat', subject_id, date_str);
savePath = fullfile(analysisFolder, saveName);

save(savePath, 'out', '-v7.3');

fprintf('\nSaved base session file:\n  %s\n', savePath);
fprintf('This file contains only bookkeeping. No ΔF/F computed.\n');