% This script:
%   - Loads {subject}_{date}_dio_stim_timing.mat (contains "session")
%   - Loads {subject}_{date}_reference_mask_and_retino_alignment.mat (contains "day_setup")
%   - Sorts TIFF filenames
%   - Verifies frame alignment
%   - Loads CSV (trial_index, stim_chan, current_uA)
%   - Builds clean bookkeeping struct "out"
%
% It does NOT compute trial maps or ΔF/F.
%
% Output:
%   analysis/{subject}_{date}_wf_stim_aligned_out.mat
%
% Final out contains:
%   out.reference_mask
%   out.retino_align
% in addition to trial timing / CSV alignment / frame bookkeeping

close all; clc; clear; fclose('all');

%% -------------------------
% Select inputs
% -------------------------

img_dir = uigetdir(pwd, 'Select folder containing TIFF frames');
if isequal(img_dir,0), error('No image folder selected.'); end

[setup_name, setup_path] = uigetfile('*.mat', ...
    'Select {subject}_{date}_reference_mask_and_retino_alignment.mat');
if isequal(setup_name,0), error('No day setup file selected.'); end
setup_file = fullfile(setup_path, setup_name);

[ses_name, ses_path] = uigetfile('*.mat', 'Select {subject}_{date}_dio_stim_timing.mat');
if isequal(ses_name,0), error('No session file selected.'); end
session_mat = fullfile(ses_path, ses_name);

[csv_name, csv_path] = uigetfile({'*.csv;*.txt'}, ...
    'Select CSV (trial_index, stim_chan, current_uA)');
if isequal(csv_name,0), error('No CSV selected.'); end
csv_file = fullfile(csv_path, csv_name);

%% -------------------------
% Load day setup
% -------------------------

D = load(setup_file);

if isfield(D,'day_setup')
    day_setup = D.day_setup;
else
    error('Selected setup file must contain variable "day_setup".');
end

assert(isfield(day_setup,'reference_mask') && isfield(day_setup.reference_mask,'final_mask'), ...
    'day_setup.reference_mask.final_mask missing.');
assert(isfield(day_setup,'retino_align'), ...
    'day_setup.retino_align missing.');

final_mask = logical(day_setup.reference_mask.final_mask);

if isfield(day_setup.reference_mask,'crop_rect')
    crop_rect = day_setup.reference_mask.crop_rect;
else
    crop_rect = [];
end

%% -------------------------
% Pull subject + date
% Prefer day_setup, then session.metadata, then filename, then prompt
% -------------------------

subject_id = '';
date_str   = '';

% 1) Preferred: from day_setup
if isfield(day_setup,'subject_id') && ~isempty(day_setup.subject_id)
    subject_id = char(string(day_setup.subject_id));
end
if isfield(day_setup,'date_str') && ~isempty(day_setup.date_str)
    date_str = char(string(day_setup.date_str));
end

% 2) Backup: from session metadata
Xmeta = load(session_mat, 'session');
assert(isfield(Xmeta,'session'), 'Session file must contain variable "session".');
session_meta = Xmeta.session;

if (isempty(strtrim(subject_id)) || isempty(strtrim(date_str))) && isfield(session_meta,'metadata')
    md = session_meta.metadata;

    if isempty(strtrim(subject_id))
        if isfield(md,'mouse_id') && ~isempty(md.mouse_id)
            subject_id = char(string(md.mouse_id));
        elseif isfield(md,'subject_id') && ~isempty(md.subject_id)
            subject_id = char(string(md.subject_id));
        end
    end

    if isempty(strtrim(date_str))
        if isfield(md,'date_str') && ~isempty(md.date_str)
            date_str = char(string(md.date_str));
        end
    end
end

% 3) Backup: parse from session filename
if isempty(strtrim(subject_id)) || isempty(strtrim(date_str))
    [~, ses_base, ~] = fileparts(session_mat);
    tok = regexp(ses_base, '^(?<subj>[^_]+)_(?<date>\d{8})_', 'names', 'once');
    if ~isempty(tok)
        if isempty(strtrim(subject_id)), subject_id = tok.subj; end
        if isempty(strtrim(date_str)),   date_str   = tok.date; end
    end
end

% 4) Final fallback: prompt user
if isempty(strtrim(subject_id)) || isempty(strtrim(date_str))
    prompt = {'Enter subject ID (e.g., LGN11):', 'Enter date (YYYYMMDD):'};
    dlg_title = 'Metadata (missing from setup/session file)';
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
% Load session
% -------------------------

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
% Sanity checks against day_setup
% -------------------------

if isfield(day_setup,'img_dir')
    if ~strcmpi(string(day_setup.img_dir), string(img_dir))
        warning('Selected img_dir differs from day_setup.img_dir.\n  img_dir: %s\n  day_setup.img_dir: %s', ...
            img_dir, day_setup.img_dir);
    end
end

if isfield(day_setup.reference_mask,'img_dir')
    if ~strcmpi(string(day_setup.reference_mask.img_dir), string(img_dir))
        warning('Selected img_dir differs from day_setup.reference_mask.img_dir.\n  img_dir: %s\n  refmask.img_dir: %s', ...
            img_dir, day_setup.reference_mask.img_dir);
    end
end

if ~isequal(size(final_mask), size(day_setup.reference_mask.ref_img))
    warning('final_mask size does not match day_setup.reference_mask.ref_img size.');
end

if isfield(day_setup.retino_align,'V1_mask_stim') && ~isempty(day_setup.retino_align.V1_mask_stim)
    if ~isequal(size(day_setup.retino_align.V1_mask_stim), size(final_mask))
        warning('V1_mask_stim size does not match final_mask size.');
    end
end

%% -------------------------
% Build FINAL out struct
% -------------------------

out = struct();

out.subject_id = subject_id;
out.date_str   = date_str;

out.img_dir        = img_dir;
out.day_setup_file = setup_file;
out.session_mat    = session_mat;
out.csv_file       = csv_file;

out.image_files_sorted = {image_files.name}';
out.n_frames           = numel(image_files);

out.Freq          = Freq;
out.frame_times_s = frame_times_s;

out.trial_onset_frame_idx = train_frame_idx;
out.trial_channel         = train_channel;
out.trial_stim_chan       = trial_stim_chan;
out.trial_current_uA      = trial_current_uA;

out.n_trials = n_trains;

out.mask_size = size(final_mask);
out.crop_rect = crop_rect;

% Add full day setup products directly into out
out.reference_mask = day_setup.reference_mask;
out.retino_align   = day_setup.retino_align;

% Optional convenience top-level shortcuts
out.final_mask = day_setup.reference_mask.final_mask;

if isfield(day_setup.retino_align,'V1_mask_stim')
    out.V1_mask_stim = day_setup.retino_align.V1_mask_stim;
end
if isfield(day_setup.retino_align,'azi_stim')
    out.azi_stim = day_setup.retino_align.azi_stim;
end
if isfield(day_setup.retino_align,'alt_stim')
    out.alt_stim = day_setup.retino_align.alt_stim;
end

out.created_on = datestr(now);

%% -------------------------
% Save
% -------------------------

analysisFolder = fullfile(fileparts(img_dir), 'analysis');
if ~exist(analysisFolder,'dir'), mkdir(analysisFolder); end

saveName = sprintf('%s_%s_wf_stim_aligned_out.mat', subject_id, date_str);
savePath = fullfile(analysisFolder, saveName);

save(savePath, 'out', '-v7.3');

fprintf('\nSaved final aligned out file:\n  %s\n', savePath);
fprintf('This file now contains bookkeeping + reference_mask + retino_align.\n');