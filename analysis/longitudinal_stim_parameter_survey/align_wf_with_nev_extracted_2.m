% This script:
%   - Loads {subject}_{date}_ripple_timing.mat (contains "ripple_timing")
%   - Loads {subject}_{date}_reference_mask_and_retino_alignment.mat (contains "day_setup")
%   - Sorts TIFF filenames
%   - Verifies frame alignment
%   - Looks at SMA2 / PulsePal timestamps if present
%   - Uses SMA3 camera-ready gating if present to identify TIFF-backed SMA1 frames
%   - Loads CSV (trial_index, stim_chan, current_uA)
%   - Builds clean bookkeeping struct "wf_trial_alignment"
%
% It does NOT compute trial maps or ΔF/F.
%
% Output:
%   analysis/{subject}_{date}_wf_trial_alignment.mat
%
% Final wf_trial_alignment contains:
%   wf_trial_alignment.reference_mask
%   wf_trial_alignment.retino_align
%   wf_trial_alignment.sma2_times_s
%   wf_trial_alignment.has_sma2
%   wf_trial_alignment.sma3_times_s
%   wf_trial_alignment.has_sma3
%   wf_trial_alignment.frame_alignment_mode
% in addition to trial timing / CSV alignment / frame bookkeeping

close all; clc; clear; fclose('all');

%% -------------------------
% Select inputs
% -------------------------

img_dir = uigetdir(pwd, 'Select folder containing TIFF frames');
if isequal(img_dir,0), error('No image folder selected.'); end

[setup_name, setup_path] = uigetfile('*.mat', ...
    'Select brain_mask.mat  OR  day_setup.mat');
if isequal(setup_name,0), error('No setup file selected.'); end
setup_file = fullfile(setup_path, setup_name);

[ses_name, ses_path] = uigetfile('*.mat', ...
    'Select {subject}_{date}_ripple_timing.mat');
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

retino_available = false;
if isfield(D, 'day_setup')
    % Full day_setup from reference_mask_and_retino_alignment.m or retino_alignment_with_brain_mask.m
    day_setup = D.day_setup;
    assert(isfield(day_setup,'reference_mask') && isfield(day_setup.reference_mask,'final_mask'), ...
        'day_setup.reference_mask.final_mask missing.');
    final_mask = logical(day_setup.reference_mask.final_mask);
    if isfield(day_setup, 'retino_align') && ~isempty(fieldnames(day_setup.retino_align))
        retino_available = true;
    else
        warning('day_setup.retino_align missing or empty — retino fields will not be stored in output.');
    end
elseif isfield(D, 'reference_mask_struct')
    % brain_mask.mat from draw_brain_mask_0.m (no retino alignment yet)
    reference_mask_struct = D.reference_mask_struct;
    assert(isfield(reference_mask_struct,'final_mask'), ...
        'reference_mask_struct.final_mask missing. Is this a valid brain_mask.mat?');
    final_mask = logical(reference_mask_struct.final_mask);
    day_setup = struct();
    day_setup.reference_mask = reference_mask_struct;
    if isfield(D,'subject_id'), day_setup.subject_id = D.subject_id; end
    if isfield(D,'date_str'),   day_setup.date_str   = D.date_str;   end
    if isfield(D,'img_dir'),    day_setup.img_dir    = D.img_dir;    end
    fprintf('Loaded brain_mask.mat — no retino alignment. Retino fields will be empty in output.\n');
else
    error('Selected file must contain "day_setup" (full setup) or "reference_mask_struct" (brain_mask.mat).');
end

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

% 2) Backup: from ripple timing metadata
session_meta = load_ripple_timing_struct(session_mat);

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
% Load ripple timing
% -------------------------

session = load_ripple_timing_struct(session_mat);

assert(isfield(session,'frames') && isfield(session.frames,'time_s'), ...
    'session.frames.time_s missing');

frame_times_s = double(session.frames.time_s(:));
dt = diff(frame_times_s);
assert(~isempty(dt), 'Not enough frame times.');
Freq = 1 / median(dt);

assert(isfield(session,'trains') && isfield(session.trains,'time_s'), ...
    'session.trains.time_s missing');
assert(isfield(session.trains,'channel'), ...
    'session.trains.channel missing');

train_times_s   = double(session.trains.time_s(:));
train_channel   = double(session.trains.channel(:));
n_trains = numel(train_times_s);

fprintf('Found %d stim trains.\n', n_trains);
fprintf('Estimated camera rate: %.3f Hz\n', Freq);

%% -------------------------
% Pull SMA2 / PulsePal timestamps
% Exact expected field: session.sma2.time_s
% -------------------------

has_sma2 = false;
sma2_times_s = [];
sma2_source_name = '';

if isfield(session,'sma2') && isfield(session.sma2,'time_s') && ~isempty(session.sma2.time_s)
    sma2_times_s = double(session.sma2.time_s(:));
    sma2_times_s = sma2_times_s(isfinite(sma2_times_s));
    has_sma2 = ~isempty(sma2_times_s);
    sma2_source_name = 'session.sma2.time_s';
end

if has_sma2
    fprintf('Found %d SMA2 / PulsePal timestamps from %s\n', ...
        numel(sma2_times_s), sma2_source_name);
else
    fprintf('No SMA2 / PulsePal timestamps found in session.sma2.time_s. Skipping SMA2 diagnostics.\n');
end

%% -------------------------
% Pull SMA3 camera-ready timestamps / gated frame list
% Exact expected fields:
%   session.sma3.time_s
%   session.frames_ready.time_s
% -------------------------

has_sma3 = false;
sma3_times_s = [];
sma3_values = [];
frames_ready_s = [];
frames_ready_raw_idx = [];
sma3_source_name = '';

if isfield(session,'sma3') && isfield(session.sma3,'time_s') && ~isempty(session.sma3.time_s)
    sma3_times_s = double(session.sma3.time_s(:));
    sma3_times_s = sma3_times_s(isfinite(sma3_times_s));
    has_sma3 = ~isempty(sma3_times_s);
    sma3_source_name = 'session.sma3.time_s';

    if isfield(session.sma3,'value') && ~isempty(session.sma3.value)
        sma3_values = double(session.sma3.value(:));
        if numel(sma3_values) ~= numel(sma3_times_s)
            warning('session.sma3.value length mismatch. Ignoring SMA3 values.');
            sma3_values = [];
        end
    end
end

if isfield(session,'frames_ready') && isfield(session.frames_ready,'time_s') && ~isempty(session.frames_ready.time_s)
    frames_ready_s = double(session.frames_ready.time_s(:));
    frames_ready_s = frames_ready_s(isfinite(frames_ready_s));

    if isfield(session.frames_ready,'raw_frame_idx') && ~isempty(session.frames_ready.raw_frame_idx)
        frames_ready_raw_idx = double(session.frames_ready.raw_frame_idx(:));
    else
        frames_ready_raw_idx = [];
    end
end

if has_sma3
    fprintf('Found %d SMA3 camera-ready events from %s\n', ...
        numel(sma3_times_s), sma3_source_name);
end

%% -------------------------
% Sort TIFF files
% -------------------------

image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFF files found.');

nFiles = numel(image_files);
nums = nan(nFiles,1);

for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    if isempty(tok)
        error('Filename "%s" missing trailing index.', image_files(i).name);
    end
    nums(i) = str2double(tok{1});
end

[~, ord] = sort(nums);
image_files = image_files(ord);

fprintf('Total TIFF frames: %d\n', numel(image_files));

%% -------------------------
% Output folder
% -------------------------

analysisFolder = uigetdir(fileparts(img_dir), 'Select output folder for analysis results');
if isequal(analysisFolder,0), error('No output folder selected.'); end
if ~exist(analysisFolder,'dir')
    mkdir(analysisFolder);
end

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
% Keep SMA1 as the authoritative camera output.
% Use SMA3 only to identify which SMA1 triggers were TIFF-backed.
% -------------------------

n_tiffs = numel(image_files);

selected_frame_alignment_mode = 'sma1_camera_output';
selected_frame_times_s = frame_times_s;
selected_raw_frame_idx = (1:numel(frame_times_s))';
tiff_backed_frame_times_s = frame_times_s;
tiff_backed_raw_frame_idx = selected_raw_frame_idx;

if ~isempty(frames_ready_s)
    frames_ready_count = numel(frames_ready_s);
    raw_count = numel(frame_times_s);

    raw_mismatch = abs(raw_count - n_tiffs);
    ready_mismatch = abs(frames_ready_count - n_tiffs);

    if ready_mismatch < raw_mismatch
        tiff_backed_frame_times_s = frames_ready_s;
        if ~isempty(frames_ready_raw_idx) && numel(frames_ready_raw_idx) == numel(frames_ready_s)
            tiff_backed_raw_frame_idx = frames_ready_raw_idx;
            selected_frame_alignment_mode = 'sma1_camera_output_with_sma3_tiff_backed_subset';
        else
            tiff_backed_raw_frame_idx = nan(numel(frames_ready_s),1);
            selected_frame_alignment_mode = 'sma1_camera_output_with_sma3_tiff_backed_subset_no_rawidx';
        end
    else
        selected_frame_alignment_mode = 'sma1_camera_output_only';
    end
else
    selected_frame_alignment_mode = 'sma1_camera_output_only';
end

fprintf('\nFrame stream selection:\n');
fprintf('  raw camera triggers         : %d\n', numel(frame_times_s));
if ~isempty(frames_ready_s)
    fprintf('  SMA3-ready gated triggers   : %d\n', numel(frames_ready_s));
end
fprintf('  TIFF frames                 : %d\n', n_tiffs);
fprintf('  selected mode               : %s\n', selected_frame_alignment_mode);

if isempty(tiff_backed_frame_times_s)
    error('Selected TIFF-backed frame stream is empty. Cannot align stim trains to TIFFs.');
end

train_frame_idx = nan(n_trains,1);
for i = 1:n_trains
    [~, j] = min(abs(tiff_backed_frame_times_s - train_times_s(i)));
    train_frame_idx(i) = j;
end

train_frame_idx_raw_camera = nan(n_trains,1);
for i = 1:n_trains
    [~, j] = min(abs(frame_times_s - train_times_s(i)));
    train_frame_idx_raw_camera(i) = j;
end

if ~isempty(frames_ready_s)
    train_frame_idx_ready_camera = nan(n_trains,1);
    for i = 1:n_trains
        [~, j] = min(abs(frames_ready_s - train_times_s(i)));
        train_frame_idx_ready_camera(i) = j;
    end
else
    train_frame_idx_ready_camera = [];
end

%% -------------------------
% Validate frame indices
% -------------------------

valid_idx = train_frame_idx >= 1 & train_frame_idx <= n_tiffs;
bad_idx   = ~valid_idx;

fprintf('\nFrame alignment diagnostics:\n');
fprintf('  TIFF frames                 : %d\n', n_tiffs);
fprintf('  Camera frame timestamps     : %d\n', numel(frame_times_s));
fprintf('  TIFF-backed SMA1 frames     : %d (%s)\n', numel(tiff_backed_frame_times_s), selected_frame_alignment_mode);
fprintf('  Stim trains                 : %d\n', numel(train_frame_idx));
fprintf('  Valid stim->frame mappings  : %d\n', sum(valid_idx));
fprintf('  Invalid stim->frame mappings: %d\n', sum(bad_idx));

if has_sma2
    fprintf('  SMA2 / PulsePal timestamps  : %d\n', numel(sma2_times_s));
    fprintf('  SMA2 - camera frame count   : %+d\n', numel(sma2_times_s) - numel(frame_times_s));
    fprintf('  SMA2 - TIFF frame count     : %+d\n', numel(sma2_times_s) - n_tiffs);
end

if ~isempty(frames_ready_s)
    fprintf('  SMA3-ready frame count      : %d\n', numel(frames_ready_s));
    fprintf('  SMA3-ready - TIFF count     : %+d\n', numel(frames_ready_s) - n_tiffs);
end

if any(bad_idx)
    fprintf('Bad stim train numbers:\n');
    disp(find(bad_idx)');

    fprintf('Bad frame_idx values:\n');
    disp(train_frame_idx(bad_idx)');
end

stim_times_from_frameidx = nan(size(train_frame_idx));
stim_times_from_frameidx(valid_idx) = tiff_backed_frame_times_s(train_frame_idx(valid_idx));

last_valid_time_s = tiff_backed_frame_times_s(min(n_tiffs, numel(tiff_backed_frame_times_s)));

%% -------------------------
% Plot 1: full session timeline
% -------------------------

fig_diag1 = figure('Name','Stim-camera-SMA2-SMA3 alignment overview','Color','w');
hold on;

plot(frame_times_s, ones(size(frame_times_s)), 'k.', 'MarkerSize', 4);

if has_sma2
    plot(sma2_times_s, 1.03*ones(size(sma2_times_s)), ...
        'g.', 'MarkerSize', 8);
end

if ~isempty(frames_ready_s)
    plot(frames_ready_s, 1.06*ones(size(frames_ready_s)), ...
        'c.', 'MarkerSize', 8);
end

plot(stim_times_from_frameidx(valid_idx), 1.09*ones(sum(valid_idx),1), ...
    'bo', 'MarkerSize', 4, 'LineWidth', 1);

if any(bad_idx)
    plot(last_valid_time_s * ones(sum(bad_idx),1), 1.12*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 8, 'LineWidth', 1.5);
end

xline(last_valid_time_s, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF-backed frame', 'LabelVerticalAlignment', 'bottom');

if has_sma2 && ~isempty(frames_ready_s)
    ylim([0.98 1.14]);
    yticks([1.00 1.03 1.06 1.09 1.12]);
    yticklabels({'Camera frames','SMA2 triggers','SMA3-ready frames','Valid stim trains','Invalid stim trains'});
elseif has_sma2
    ylim([0.98 1.13]);
    yticks([1.00 1.03 1.09 1.12]);
    yticklabels({'Camera frames','SMA2 triggers','Valid stim trains','Invalid stim trains'});
elseif ~isempty(frames_ready_s)
    ylim([0.98 1.13]);
    yticks([1.00 1.06 1.09 1.12]);
    yticklabels({'Camera frames','SMA3-ready frames','Valid stim trains','Invalid stim trains'});
else
    ylim([0.98 1.13]);
    yticks([1.00 1.09 1.12]);
    yticklabels({'Camera frames','Valid stim trains','Invalid stim trains'});
end

xlabel('Time (s)');
title(sprintf('Full session: %s', strrep(selected_frame_alignment_mode,'_',' ')));
grid on;

saveas(fig_diag1, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_overview.png', subject_id, date_str)));

%% -------------------------
% Plot 2: end-of-session zoom
% -------------------------

fig_diag2 = figure('Name','Stim-camera-SMA2-SMA3 alignment end zoom','Color','w');
hold on;

t_end = frame_times_s(end);
zoom_window_s = 60;
t_start_zoom = max(frame_times_s(1), t_end - zoom_window_s);

frame_keep = frame_times_s >= t_start_zoom;
plot(frame_times_s(frame_keep), ones(sum(frame_keep),1), 'k.', 'MarkerSize', 6);

if has_sma2
    sma2_keep = sma2_times_s >= t_start_zoom & sma2_times_s <= t_end;
    plot(sma2_times_s(sma2_keep), 1.03*ones(sum(sma2_keep),1), ...
        'g.', 'MarkerSize', 10);
end

if ~isempty(frames_ready_s)
    ready_keep = frames_ready_s >= t_start_zoom & frames_ready_s <= t_end;
    plot(frames_ready_s(ready_keep), 1.06*ones(sum(ready_keep),1), ...
        'c.', 'MarkerSize', 10);
end

valid_keep = valid_idx & stim_times_from_frameidx >= t_start_zoom;
plot(stim_times_from_frameidx(valid_keep), 1.09*ones(sum(valid_keep),1), ...
    'bo', 'MarkerSize', 5, 'LineWidth', 1);

if any(bad_idx)
    plot(last_valid_time_s * ones(sum(bad_idx),1), 1.12*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 9, 'LineWidth', 1.5);
end

xline(last_valid_time_s, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF-backed frame', 'LabelVerticalAlignment', 'bottom');

xlim([t_start_zoom t_end]);

if has_sma2 && ~isempty(frames_ready_s)
    ylim([0.98 1.14]);
    yticks([1.00 1.03 1.06 1.09 1.12]);
    yticklabels({'Camera frames','SMA2 triggers','SMA3-ready frames','Valid stim trains','Invalid stim trains'});
elseif has_sma2
    ylim([0.98 1.13]);
    yticks([1.00 1.03 1.09 1.12]);
    yticklabels({'Camera frames','SMA2 triggers','Valid stim trains','Invalid stim trains'});
elseif ~isempty(frames_ready_s)
    ylim([0.98 1.13]);
    yticks([1.00 1.06 1.09 1.12]);
    yticklabels({'Camera frames','SMA3-ready frames','Valid stim trains','Invalid stim trains'});
else
    ylim([0.98 1.13]);
    yticks([1.00 1.09 1.12]);
    yticklabels({'Camera frames','Valid stim trains','Invalid stim trains'});
end

xlabel('Time (s)');
title('End of session zoom');
grid on;

saveas(fig_diag2, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_endzoom.png', subject_id, date_str)));

%% -------------------------
% Plot 3: frame index diagnostic
% -------------------------

fig_diag3 = figure('Name','Stim frame_idx diagnostic','Color','w');
hold on;

plot(1:n_tiffs, ones(1,n_tiffs), 'k.', 'MarkerSize', 4);
plot(train_frame_idx(valid_idx), 1.05*ones(sum(valid_idx),1), ...
    'bo', 'MarkerSize', 4, 'LineWidth', 1);

if any(bad_idx)
    plot(train_frame_idx(bad_idx), 1.10*ones(sum(bad_idx),1), ...
        'rx', 'MarkerSize', 8, 'LineWidth', 1.5);
end

xline(n_tiffs, 'r--', 'LineWidth', 1.5, ...
    'Label', 'Last TIFF index', 'LabelVerticalAlignment', 'bottom');

xlabel('Frame index');
yticks([1.00 1.05 1.10]);
yticklabels({'Existing TIFF frames','Valid stim frame_idx','Invalid stim frame_idx'});
title('Frame index diagnostic');
grid on;

saveas(fig_diag3, fullfile(analysisFolder, ...
    sprintf('%s_%s_alignment_diagnostic_frameidx.png', subject_id, date_str)));

%% -------------------------
% Plot 4: camera dt diagnostic
% -------------------------

fig_diag4 = figure('Name','Camera frame interval diagnostic','Color','w');
plot(diff(frame_times_s), 'k-', 'LineWidth', 1);
hold on;
yline(median(diff(frame_times_s)), 'r--', 'Median dt', 'LineWidth', 1.5);
xlabel('Frame number');
ylabel('\Delta t between camera timestamps (s)');
title('Camera timestamp interval diagnostic');
grid on;

saveas(fig_diag4, fullfile(analysisFolder, ...
    sprintf('%s_%s_camera_dt_diagnostic.png', subject_id, date_str)));

%% -------------------------
% Plot 5: SMA2 dt diagnostic
% -------------------------

if has_sma2 && numel(sma2_times_s) > 1
    fig_diag5 = figure('Name','SMA2 interval diagnostic','Color','w');
    plot(diff(sma2_times_s), 'g-', 'LineWidth', 1);
    hold on;
    yline(median(diff(sma2_times_s)), 'r--', 'Median dt', 'LineWidth', 1.5);
    xlabel('SMA2 pulse number');
    ylabel('\Delta t between SMA2 timestamps (s)');
    title('SMA2 / PulsePal interval diagnostic');
    grid on;

    saveas(fig_diag5, fullfile(analysisFolder, ...
        sprintf('%s_%s_sma2_dt_diagnostic.png', subject_id, date_str)));
end

%% -------------------------
% Plot 6: SMA2-camera timing offset
% -------------------------

if has_sma2
    n_compare = min(numel(frame_times_s), numel(sma2_times_s));

    if n_compare > 0
        time_offset = sma2_times_s(1:n_compare) - frame_times_s(1:n_compare);

        fprintf('\nSMA2 vs camera timing:\n');
        fprintf('  Compared pulses            : %d\n', n_compare);
        fprintf('  Mean offset (SMA2-camera)  : %.6f s\n', mean(time_offset));
        fprintf('  Median offset              : %.6f s\n', median(time_offset));
        fprintf('  Std offset                 : %.6f s\n', std(time_offset));

        fig_diag6 = figure('Name','SMA2 vs Camera timing offset','Color','w');
        plot(time_offset, 'k-', 'LineWidth', 1);
        hold on;
        yline(median(time_offset), 'r--', 'Median', 'LineWidth', 1.5);
        xlabel('Pulse number');
        ylabel('SMA2 time - camera time (s)');
        title('Timing offset between SMA2 PulsePal and camera TTL');
        grid on;

        saveas(fig_diag6, fullfile(analysisFolder, ...
            sprintf('%s_%s_sma2_minus_camera_offset.png', subject_id, date_str)));
    end
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

if isfield(day_setup.reference_mask,'ref_img')
    if ~isequal(size(final_mask), size(day_setup.reference_mask.ref_img))
        warning('final_mask size does not match day_setup.reference_mask.ref_img size.');
    end
end

if retino_available && isfield(day_setup.retino_align,'V1_mask_stim') && ~isempty(day_setup.retino_align.V1_mask_stim)
    if ~isequal(size(day_setup.retino_align.V1_mask_stim), size(final_mask))
        warning('V1_mask_stim size does not match final_mask size.');
    end
end

%% -------------------------
% Save bad stim train table if needed
% -------------------------

if any(bad_idx)
    bad_table = table( ...
        find(bad_idx), ...
        train_frame_idx(bad_idx), ...
        train_frame_idx_raw_camera(bad_idx), ...
        trial_stim_chan(bad_idx), ...
        trial_current_uA(bad_idx), ...
        'VariableNames', {'stim_train_number','frame_idx','raw_camera_frame_idx','stim_chan','current_uA'});

    disp(bad_table);

    writetable(bad_table, fullfile(analysisFolder, ...
        sprintf('%s_%s_bad_stim_trains.csv', subject_id, date_str)));
end

%% -------------------------
% Build FINAL wf_trial_alignment struct
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
out.frame_times_selected_s = tiff_backed_frame_times_s;
out.frame_alignment_mode = selected_frame_alignment_mode;
out.frame_alignment_raw_frame_idx = tiff_backed_raw_frame_idx;

out.trial_onset_frame_idx = train_frame_idx;
out.trial_onset_time_s    = train_times_s;
out.trial_onset_frame_idx_raw_camera = train_frame_idx_raw_camera;
out.trial_onset_frame_idx_ready_camera = train_frame_idx_ready_camera;
out.trial_channel         = train_channel;
out.trial_stim_chan       = trial_stim_chan;
out.trial_current_uA      = trial_current_uA;

out.n_trials = n_trains;

out.mask_size = size(final_mask);
out.crop_rect = crop_rect;

out.reference_mask = day_setup.reference_mask;
out.final_mask     = day_setup.reference_mask.final_mask;

if retino_available
    out.retino_align = day_setup.retino_align;
    if isfield(day_setup.retino_align,'V1_mask_stim')
        out.V1_mask_stim = day_setup.retino_align.V1_mask_stim;
    end
    if isfield(day_setup.retino_align,'azi_stim')
        out.azi_stim = day_setup.retino_align.azi_stim;
    end
    if isfield(day_setup.retino_align,'alt_stim')
        out.alt_stim = day_setup.retino_align.alt_stim;
    end
else
    out.retino_align = struct();
end

% SMA2 bookkeeping
out.has_sma2 = has_sma2;
out.sma2_source_name = sma2_source_name;

if has_sma2
    out.sma2_times_s = sma2_times_s;
    out.sma2_count = numel(sma2_times_s);
    out.sma2_minus_camera_count = numel(sma2_times_s) - numel(frame_times_s);
    out.sma2_minus_tiff_count   = numel(sma2_times_s) - n_tiffs;
else
    out.sma2_times_s = [];
    out.sma2_count = 0;
    out.sma2_minus_camera_count = [];
    out.sma2_minus_tiff_count   = [];
end

% SMA3 bookkeeping
out.has_sma3 = has_sma3;
out.sma3_source_name = sma3_source_name;
out.sma3_times_s = sma3_times_s;
out.sma3_values = sma3_values;
out.frames_ready_s = frames_ready_s;
out.frames_ready_count = numel(frames_ready_s);
out.frames_ready_minus_tiff_count = numel(frames_ready_s) - n_tiffs;

out.created_on = datestr(now);

%% -------------------------
% Save
% -------------------------

wf_trial_alignment = out;

saveName = sprintf('%s_%s_wf_trial_alignment.mat', subject_id, date_str);
savePath = fullfile(analysisFolder, saveName);

save(savePath, 'wf_trial_alignment', '-v7.3');

fprintf('\nSaved wf_trial_alignment file:\n  %s\n', savePath);
fprintf('This file now contains bookkeeping + reference_mask + retino_align + SMA2/SMA3 diagnostics.\n');


%%
fprintf('Last camera TTL time: %.3f s\n', frame_times_s(end));
fprintf('Last TIFF-backed camera time: %.3f s\n', tiff_backed_frame_times_s(min(n_tiffs, numel(tiff_backed_frame_times_s))));
fprintf('Difference: %.3f s\n', frame_times_s(end) - tiff_backed_frame_times_s(min(n_tiffs, numel(tiff_backed_frame_times_s))));

fprintf('Max stim frame_idx: %d\n', max(train_frame_idx));
fprintf('Last TIFF index   : %d\n', n_tiffs);
fprintf('Margin to TIFF end: %d frames\n', n_tiffs - max(train_frame_idx));

function ripple_timing = load_ripple_timing_struct(session_mat)
X = load(session_mat);

if isfield(X, 'ripple_timing')
    ripple_timing = X.ripple_timing;
elseif isfield(X, 'session')
    ripple_timing = X.session;
else
    error('Timing file must contain variable "ripple_timing" or legacy variable "session".');
end
end
