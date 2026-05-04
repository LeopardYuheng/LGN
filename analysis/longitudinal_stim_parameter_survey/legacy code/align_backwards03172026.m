% This script:
%   - Loads {subject}_{date}_dio_stim_timing.mat (contains "session")
%   - Loads {subject}_{date}_reference_mask_and_retino_alignment.mat (contains "day_setup")
%   - Sorts TIFF filenames
%   - ALIGNS TIFFS TO THE END of session.frames.time_s
%   - Loads CSV (trial_index, stim_chan, current_uA)
%   - Builds clean bookkeeping struct "out"
%
% It does NOT compute trial maps or ΔF/F.
%
% Output:
%   analysis/{subject}_{date}_wf_stim_aligned_out_ENDALIGNED.mat

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

[ses_name, ses_path] = uigetfile('*.mat', ...
    'Select {subject}_{date}_dio_stim_timing.mat');
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
% -------------------------

subject_id = '';
date_str   = '';

if isfield(day_setup,'subject_id') && ~isempty(day_setup.subject_id)
    subject_id = char(string(day_setup.subject_id));
end
if isfield(day_setup,'date_str') && ~isempty(day_setup.date_str)
    date_str = char(string(day_setup.date_str));
end

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

if isempty(strtrim(subject_id)) || isempty(strtrim(date_str))
    [~, ses_base, ~] = fileparts(session_mat);
    tok = regexp(ses_base, '^(?<subj>[^_]+)_(?<date>\d{8})_', 'names', 'once');
    if ~isempty(tok)
        if isempty(strtrim(subject_id)), subject_id = tok.subj; end
        if isempty(strtrim(date_str)),   date_str   = tok.date; end
    end
end

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

frame_times_s = double(session.frames.time_s(:));
dt = diff(frame_times_s);
assert(~isempty(dt), 'Not enough frame times.');
Freq = 1 / median(dt);

assert(isfield(session,'trains') && isfield(session.trains,'frame_idx'), ...
    'session.trains.frame_idx missing');
assert(isfield(session,'trains') && isfield(session.trains,'channel'), ...
    'session.trains.channel missing');

train_frame_idx_raw = double(session.trains.frame_idx(:));
train_channel       = double(session.trains.channel(:));
n_trains = numel(train_frame_idx_raw);

fprintf('Found %d stim trains.\n', n_trains);
fprintf('Estimated camera rate: %.3f Hz\n', Freq);

%% -------------------------
% Sort TIFF files
% -------------------------

image_files = dir(fullfile(img_dir, '*.tif'));
if isempty(image_files)
    image_files = dir(fullfile(img_dir, '*.tiff'));
end
assert(~isempty(image_files), 'No TIFF files found.');

nFiles = numel(image_files);
nums = nan(nFiles,1);

for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.tif{1,2}$', 'tokens', 'once');
    if isempty(tok)
        nums(i) = i;
    else
        nums(i) = str2double(tok{1});
    end
end

[~,ord] = sort(nums);
image_files = image_files(ord);

n_tiffs = numel(image_files);
n_cam_frames = numel(frame_times_s);

fprintf('Total TIFF frames: %d\n', n_tiffs);
fprintf('Camera frame timestamps: %d\n', n_cam_frames);

analysisFolder = fullfile(fileparts(img_dir), 'analysis');
if ~exist(analysisFolder,'dir'), mkdir(analysisFolder); end

%% -------------------------
% END-ALIGN TIFFs TO CAMERA FRAMES
% -------------------------

if n_cam_frames < n_tiffs
    error(['There are fewer camera timestamps (%d) than TIFF frames (%d). ' ...
           'End alignment is not possible.'], n_cam_frames, n_tiffs);
end

frame_offset = n_cam_frames - n_tiffs;

% Raw session frame_idx lives in full camera-frame index space.
% Convert it into TIFF index space assuming TIFFs are the LAST n_tiffs frames.
train_frame_idx = train_frame_idx_raw - frame_offset;

fprintf('\nEND-ALIGNMENT APPLIED:\n');
fprintf('  frame_offset = n_cam_frames - n_tiffs = %d\n', frame_offset);
fprintf('  TIFF frame 1 corresponds to camera frame %d\n', frame_offset + 1);
fprintf('  TIFF frame %d corresponds to camera frame %d\n', n_tiffs, n_cam_frames);

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
% Validate END-ALIGNED frame indices
% -------------------------

valid_idx = train_frame_idx >= 1 & train_frame_idx <= n_tiffs;
bad_idx   = ~valid_idx;

if any(bad_idx)
    warning('%d stim trains have END-ALIGNED frame_idx outside TIFF range.', sum(bad_idx));
end

fprintf('\nFrame alignment diagnostics (END-ALIGNED):\n');
fprintf('  TIFF frames                 : %d\n', n_tiffs);
fprintf('  Camera frame timestamps     : %d\n', n_cam_frames);
fprintf('  frame_offset                : %d\n', frame_offset);
fprintf('  Stim trains                 : %d\n', n_trains);
fprintf('  Valid stim->frame mappings  : %d\n', sum(valid_idx));
fprintf('  Invalid stim->frame mappings: %d\n', sum(bad_idx));

if any(bad_idx)
    fprintf('Bad stim train numbers:\n');
    disp(find(bad_idx)');

    fprintf('Bad raw session.trains.frame_idx values:\n');
    disp(train_frame_idx_raw(bad_idx)');

    fprintf('Bad END-ALIGNED frame_idx values:\n');
    disp(train_frame_idx(bad_idx)');
end

%% -------------------------
% Diagnostic time assignment
% -------------------------

% Time assigned using raw camera-frame indices, but only if the raw index lies
% inside the last n_tiffs camera frames.
raw_idx_in_end_window = train_frame_idx_raw >= (frame_offset + 1) & train_frame_idx_raw <= n_cam_frames;

stim_times_from_rawidx = nan(size(train_frame_idx_raw));
stim_times_from_rawidx(raw_idx_in_end_window) = frame_times_s(train_frame_idx_raw(raw_idx_in_end_window));

first_tiff_time_s = frame_times_s(frame_offset + 1);
last_tiff_time_s  = frame_times_s(n_cam_frames);

%% -------------------------
% Plot 1: full session timeline
% -------------------------

fig_diag1 = figure('Name','Stim-camera alignment overview END-ALIGNED','Color','w');
hold on;

plot(frame_times_s, ones(size(frame_times_s)), 'k.', 'MarkerSize', 4);

plot(stim_times_from_rawidx(valid_idx), 1.05*ones(sum(valid_idx),1), ...
    'bo', 'MarkerSize', 4, 'LineWidth', 1);

if any(bad_idx)
    plot(last_tiff_time_s * ones(sum(bad_idx),1), 1.10*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 8, 'LineWidth', 1.5);
end

xline(first_tiff_time_s, 'g--', 'LineWidth', 1.5, ...
    'Label', 'First TIFF-backed frame (end-aligned)', ...
    'LabelVerticalAlignment', 'bottom');

xline(last_tiff_time_s, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF-backed frame', ...
    'LabelVerticalAlignment', 'bottom');

ylim([0.98 1.12]);
xlabel('Time (s)');
yticks([1.00 1.05 1.10]);
yticklabels({'Camera frames','Valid stim trains','Invalid stim trains'});
title('Full session: camera frames vs stim trains (END-ALIGNED)');
grid on;

saveas(fig_diag1, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_overview_ENDALIGNED.png', subject_id, date_str)));

%% -------------------------
% Plot 2: zoom in on end of session
% -------------------------

fig_diag2 = figure('Name','Stim-camera alignment end zoom END-ALIGNED','Color','w');
hold on;

t_end = frame_times_s(end);
zoom_window_s = 60;
t_start_zoom = max(frame_times_s(1), t_end - zoom_window_s);

frame_keep = frame_times_s >= t_start_zoom;
plot(frame_times_s(frame_keep), ones(sum(frame_keep),1), 'k.', 'MarkerSize', 6);

valid_keep = valid_idx & stim_times_from_rawidx >= t_start_zoom;
plot(stim_times_from_rawidx(valid_keep), 1.05*ones(sum(valid_keep),1), ...
    'bo', 'MarkerSize', 5, 'LineWidth', 1);

if any(bad_idx)
    plot(last_tiff_time_s * ones(sum(bad_idx),1), 1.10*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 9, 'LineWidth', 1.5);
end

xline(first_tiff_time_s, 'g--', 'LineWidth', 1.5, ...
    'Label', 'First TIFF-backed frame', ...
    'LabelVerticalAlignment', 'bottom');

xline(last_tiff_time_s, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF-backed frame', ...
    'LabelVerticalAlignment', 'bottom');

xlim([t_start_zoom t_end]);
ylim([0.98 1.12]);
xlabel('Time (s)');
yticks([1.00 1.05 1.10]);
yticklabels({'Camera frames','Valid stim trains','Invalid stim trains'});
title('End of session zoom (END-ALIGNED)');
grid on;

saveas(fig_diag2, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_endzoom_ENDALIGNED.png', subject_id, date_str)));

%% -------------------------
% Plot 3: frame index space directly
% -------------------------

fig_diag3 = figure('Name','Stim frame_idx diagnostic END-ALIGNED','Color','w');
hold on;

plot(1:n_tiffs, ones(1,n_tiffs), 'k.', 'MarkerSize', 4);
plot(train_frame_idx(valid_idx), 1.05*ones(sum(valid_idx),1), ...
    'bo', 'MarkerSize', 4, 'LineWidth', 1);

if any(bad_idx)
    plot(train_frame_idx(bad_idx), 1.10*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 8, 'LineWidth', 1.5);
end

xline(1, 'g--', 'LineWidth', 1.5, ...
    'Label', 'First TIFF index', 'LabelVerticalAlignment', 'bottom');
xline(n_tiffs, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF index', 'LabelVerticalAlignment', 'bottom');

xlabel('END-ALIGNED TIFF frame index');
yticks([1.00 1.05 1.10]);
yticklabels({'Existing TIFF frames','Valid stim frame_idx','Invalid stim frame_idx'});
title('Frame index diagnostic (END-ALIGNED)');
grid on;

saveas(fig_diag3, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_frameidx_ENDALIGNED.png', subject_id, date_str)));

%% -------------------------
% Sanity checks against day_setup
% -------------------------

if isfield(day_setup,'img_dir')
    if ~strcmpi(string(day_setup.img_dir), string(img_dir))
        warning(['Selected img_dir differs from day_setup.img_dir.\n' ...
                 '  img_dir: %s\n  day_setup.img_dir: %s'], ...
                 img_dir, day_setup.img_dir);
    end
end

if isfield(day_setup.reference_mask,'img_dir')
    if ~strcmpi(string(day_setup.reference_mask.img_dir), string(img_dir))
        warning(['Selected img_dir differs from day_setup.reference_mask.img_dir.\n' ...
                 '  img_dir: %s\n  refmask.img_dir: %s'], ...
                 img_dir, day_setup.reference_mask.img_dir);
    end
end

if isfield(day_setup.reference_mask,'ref_img')
    if ~isequal(size(final_mask), size(day_setup.reference_mask.ref_img))
        warning('final_mask size does not match day_setup.reference_mask.ref_img size.');
    end
end

if isfield(day_setup.retino_align,'V1_mask_stim') && ~isempty(day_setup.retino_align.V1_mask_stim)
    if ~isequal(size(day_setup.retino_align.V1_mask_stim), size(final_mask))
        warning('V1_mask_stim size does not match final_mask size.');
    end
end

if any(bad_idx)
    bad_table = table( ...
        find(bad_idx), ...
        train_frame_idx_raw(bad_idx), ...
        train_frame_idx(bad_idx), ...
        trial_stim_chan(bad_idx), ...
        trial_current_uA(bad_idx), ...
        'VariableNames', {'stim_train_number','raw_frame_idx','end_aligned_frame_idx','stim_chan','current_uA'});

    disp(bad_table);

    writetable(bad_table, fullfile(analysisFolder, ...
        sprintf('%s_%s_bad_stim_trains_ENDALIGNED.csv', subject_id, date_str)));
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
out.n_frames           = n_tiffs;

out.Freq          = Freq;
out.frame_times_s = frame_times_s;

% Save both raw and end-aligned versions
out.trial_onset_frame_idx_raw         = train_frame_idx_raw;
out.trial_onset_frame_idx             = train_frame_idx;
out.trial_frame_idx_alignment_mode    = 'end_aligned_to_last_n_tiffs';
out.frame_offset                      = frame_offset;
out.first_tiff_camera_frame_idx       = frame_offset + 1;
out.last_tiff_camera_frame_idx        = n_cam_frames;

out.trial_channel    = train_channel;
out.trial_stim_chan  = trial_stim_chan;
out.trial_current_uA = trial_current_uA;

out.n_trials = n_trains;

out.mask_size = size(final_mask);
out.crop_rect = crop_rect;

out.reference_mask = day_setup.reference_mask;
out.retino_align   = day_setup.retino_align;

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

saveName = sprintf('%s_%s_wf_stim_aligned_out_ENDALIGNED.mat', subject_id, date_str);
savePath = fullfile(analysisFolder, saveName);

save(savePath, 'out', '-v7.3');

fprintf('\nSaved final END-ALIGNED out file:\n  %s\n', savePath);
fprintf('This file now contains bookkeeping + reference_mask + retino_align.\n');