%% current_thresholding_analysis_fixedROI_with_visualfield.m
% Fixed ROI per channel + visual field mapping
%
% Works with aligned out files containing:
%   out.reference_mask.final_mask
%   out.retino_align.V1_mask_stim
%   out.retino_align.azi_stim
%   out.retino_align.alt_stim
%
% Also prefers trial bookkeeping already stored in out:
%   out.trial_onset_frame_idx
%   out.trial_stim_chan
%   out.trial_current_uA
%   out.csv_file
%
% Requires wf utilities on path:
%   wf_sort_tiffs
%   wf_mean_evoked_map
%   wf_read_tiff_frame

close all; clc; clear; fclose('all');
addpath('C:\Users\LuanLab\OneDrive - Rice University\Documents\GitHub\Luan_lab_retinomap-pipeline\analysis\stim_parameter_survey\functions');

%% -------------------------
% USER SELECT FILES
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select final aligned out file (contains out)');
if isequal(fn,0), error('No .mat selected.'); end
R = load(fullfile(fp, fn));
assert(isfield(R,'out'), 'Selected .mat must contain struct variable "out".');
out = R.out;

assert(isfield(out,'img_dir') && exist(out.img_dir,'dir')==7, 'out.img_dir missing or not found.');
img_dir = out.img_dir;

%% -------------------------
% onset frames
% -------------------------
if isfield(out,'trial_onset_frame_idx') && ~isempty(out.trial_onset_frame_idx)
    trial_onset_frame_idx = double(out.trial_onset_frame_idx(:));
elseif isfield(out,'session_mat') && ~isempty(out.session_mat)
    X = load(out.session_mat,'session');
    assert(isfield(X,'session') && isfield(X.session,'trains') && isfield(X.session.trains,'frame_idx'), ...
        'session_mat does not contain session.trains.frame_idx');
    trial_onset_frame_idx = double(X.session.trains.frame_idx(:));
else
    error('Need out.trial_onset_frame_idx OR out.session_mat with session.trains.frame_idx.');
end

Ntr = numel(trial_onset_frame_idx);
assert(Ntr > 0, 'No trials found.');

%% -------------------------
% load masks / retino directly from out
% -------------------------
if isfield(out,'reference_mask') && isfield(out.reference_mask,'final_mask')
    final_mask = logical(out.reference_mask.final_mask);
elseif isfield(out,'final_mask') && ~isempty(out.final_mask)
    final_mask = logical(out.final_mask);
else
    error('No final mask found in out.reference_mask.final_mask or out.final_mask.');
end

if isfield(out,'reference_mask') && isfield(out.reference_mask,'crop_rect')
    crop_rect = out.reference_mask.crop_rect;
elseif isfield(out,'crop_rect')
    crop_rect = out.crop_rect;
else
    crop_rect = [];
end

USE_V1_MASK = true;
if isfield(out,'retino_align') && isfield(out.retino_align,'V1_mask_stim') && ~isempty(out.retino_align.V1_mask_stim)
    V1_mask_stim = logical(out.retino_align.V1_mask_stim);
elseif isfield(out,'V1_mask_stim') && ~isempty(out.V1_mask_stim)
    V1_mask_stim = logical(out.V1_mask_stim);
else
    warning('V1 mask missing. Using full final_mask only.');
    USE_V1_MASK = false;
    V1_mask_stim = true(size(final_mask));
end

USE_RETINO = true;
if isfield(out,'retino_align') && isfield(out.retino_align,'azi_stim') && isfield(out.retino_align,'alt_stim') ...
        && ~isempty(out.retino_align.azi_stim) && ~isempty(out.retino_align.alt_stim)
    azi_stim = double(out.retino_align.azi_stim);
    alt_stim = double(out.retino_align.alt_stim);
elseif isfield(out,'azi_stim') && isfield(out,'alt_stim') ...
        && ~isempty(out.azi_stim) && ~isempty(out.alt_stim)
    azi_stim = double(out.azi_stim);
    alt_stim = double(out.alt_stim);
else
    warning('azi/alt maps missing. Visual field mapping disabled.');
    USE_RETINO = false;
    azi_stim = [];
    alt_stim = [];
end

assert(isequal(size(final_mask), size(V1_mask_stim)), 'final_mask and V1_mask_stim size mismatch.');
if USE_RETINO
    assert(isequal(size(final_mask), size(azi_stim)), 'azi_stim size mismatch.');
    assert(isequal(size(final_mask), size(alt_stim)), 'alt_stim size mismatch.');
end

analysis_mask = final_mask & logical(V1_mask_stim);
assert(nnz(analysis_mask) > 0, 'analysis_mask is empty.');

%% -------------------------
% trial channel/current bookkeeping
% Prefer values already stored in out
% -------------------------
use_csv_fallback = false;

if isfield(out,'trial_stim_chan') && isfield(out,'trial_current_uA') && ...
        ~isempty(out.trial_stim_chan) && ~isempty(out.trial_current_uA)

    trial_stim_chan  = double(out.trial_stim_chan(:));
    trial_current_uA = double(out.trial_current_uA(:));

    if numel(trial_stim_chan) ~= Ntr || numel(trial_current_uA) ~= Ntr
        warning('out trial vectors do not match trial_onset_frame_idx length. Falling back to CSV.');
        use_csv_fallback = true;
    else
        fprintf('Using trial_stim_chan and trial_current_uA directly from out.\n');
        csv_file = '';
    end
else
    use_csv_fallback = true;
end

if use_csv_fallback
    if isfield(out,'csv_file') && ~isempty(out.csv_file) && exist(out.csv_file,'file')==2
        csv_file = out.csv_file;
        fprintf('Using out.csv_file:\n  %s\n', csv_file);
    else
        [csv_name, csv_path] = uigetfile({'*.csv;*.txt','CSV or TXT (*.csv, *.txt)'}, ...
            'Select CSV: trial_index, stim_chan, current_uA');
        if isequal(csv_name,0), error('No CSV selected.'); end
        csv_file = fullfile(csv_path, csv_name);
    end

    Tcsv = readtable(csv_file);

    vars = lower(string(Tcsv.Properties.VariableNames));
    col_trial = find(vars=="trial_index" | vars=="trial" | vars=="trial_idx", 1);
    col_chan  = find(vars=="stim_chan" | vars=="channel" | vars=="stim_channel" | vars=="stimchan", 1);
    col_curr  = find(vars=="current_ua" | vars=="current" | vars=="currentlevel" | vars=="current_level", 1);

    assert(~isempty(col_trial), 'CSV must contain trial_index column.');
    assert(~isempty(col_chan),  'CSV must contain stim_chan column.');
    assert(~isempty(col_curr),  'CSV must contain current_uA column.');

    trial_index_csv = double(Tcsv{:, col_trial});
    stim_chan_csv   = double(Tcsv{:, col_chan});
    current_uA_csv  = double(Tcsv{:, col_curr});

    keep = isfinite(trial_index_csv) & isfinite(stim_chan_csv) & isfinite(current_uA_csv);
    trial_index_csv = trial_index_csv(keep);
    stim_chan_csv   = stim_chan_csv(keep);
    current_uA_csv  = current_uA_csv(keep);

    trial_stim_chan  = nan(Ntr,1);
    trial_current_uA = nan(Ntr,1);

    if all(ismember(1:Ntr, trial_index_csv))
        [~, ia] = unique(trial_index_csv, 'stable');
        ti = trial_index_csv(ia);
        ch = stim_chan_csv(ia);
        cu = current_uA_csv(ia);
        trial_stim_chan(ti)  = ch;
        trial_current_uA(ti) = cu;
        fprintf('Mapped CSV by trial_index.\n');
    else
        M = min(numel(stim_chan_csv), Ntr);
        trial_stim_chan(1:M)  = stim_chan_csv(1:M);
        trial_current_uA(1:M) = current_uA_csv(1:M);
        warning('Mapped CSV by row order for first %d trials.', M);
    end
end

ch_list = unique(trial_stim_chan(isfinite(trial_stim_chan)));
ch_list = sort(ch_list(:));
fprintf('Found %d channels.\n', numel(ch_list));

%% -------------------------
% Output folder
% -------------------------
save_root = uigetdir(pwd, 'Select OUTPUT folder to save results');
if isequal(save_root,0), save_root = pwd; end
out_dir = fullfile(save_root, 'autoROI_threshold_fixed_visualfield');
if exist(out_dir,'dir')~=7, mkdir(out_dir); end

%% -------------------------
% USER PARAMS
% -------------------------
roi_radius_px = input('Enter ROI radius (pixels): ');
assert(isfinite(roi_radius_px) && roi_radius_px > 0, 'ROI radius must be > 0.');

polarity = 'pos';
response_metric = 'mean_respwin';

ANCHOR_RULE = 'max_current';
ANCHOR_CURRENT_VALUE = NaN;

alpha = 0.05;
use_ci_rule = true;
z = 1.96;

SAVE_PER_CHANNEL_FIGS = true;
SAVE_MASTER_SUMMARY   = true;
SAVE_VISUAL_FIELD_FIG = true;

SAVE_7UA_MAPS = true;
TARGET_MAP_CURRENT = 7;

MAP_THRESHOLD_FRAC = 0.70;
VF_THRESHOLD_FRAC  = 0.70;

USE_PERCENT_DFF    = true;
USE_FIXED_DFF_CLIM = true;

if USE_PERCENT_DFF
    DFF_CLIM = [-5 20];
else
    DFF_CLIM = [-0.05 0.20];
end

%% -------------------------
% Get timing parameters from out
% -------------------------
if isfield(out,'Freq') && ~isempty(out.Freq)
    Freq = out.Freq;
elseif isfield(out,'session_mat') && ~isempty(out.session_mat)
    X = load(out.session_mat,'session');
    if isfield(X,'session') && isfield(X.session,'frames') && isfield(X.session.frames,'time_s')
        dt = diff(double(X.session.frames.time_s(:)));
        Freq = 1 / median(dt);
    else
        error('No out.Freq and cannot infer from session.frames.time_s.');
    end
else
    error('No out.Freq and no out.session_mat to infer it.');
end

if isfield(out,'before_time') && ~isempty(out.before_time)
    before_s = out.before_time;
else
    before_s = input('before_time (s): ');
end

if isfield(out,'after_time') && ~isempty(out.after_time)
    after_s = out.after_time;
else
    after_s = input('after_time (s): ');
end

if isfield(out,'resp_win') && ~isempty(out.resp_win)
    resp_win = out.resp_win;
else
    resp_win = input('resp_win [t1 t2] (s): ');
end

preFrames  = round(before_s * Freq);
postFrames = round(after_s  * Freq);
L          = preFrames + postFrames + 1;

t = ((0:L-1)/Freq) - before_s;
base_idx = 1:preFrames;
resp_idx = find(t >= resp_win(1) & t <= resp_win(2));

assert(~isempty(base_idx), 'Baseline window too short.');
assert(~isempty(resp_idx), 'resp_win yields no frames.');

%% -------------------------
% Load & sort TIFF files
% -------------------------
image_files = wf_sort_tiffs(img_dir);

max_onset = max(trial_onset_frame_idx(isfinite(trial_onset_frame_idx)));
max_needed = min(max_onset + postFrames, numel(image_files));
if max_needed < numel(image_files)
    fprintf('Trimming TIFF list: using %d / %d frames\n', max_needed, numel(image_files));
end
image_files = image_files(1:max_needed);

img1 = wf_read_tiff_frame(img_dir, image_files, 1, crop_rect);
[H,W] = size(img1);
assert(all(size(final_mask)==[H W]), 'final_mask size mismatch TIFF size.');
assert(all(size(analysis_mask)==[H W]), 'analysis_mask size mismatch TIFF size.');
if USE_RETINO
    assert(all(size(azi_stim)==[H W]), 'azi_stim size mismatch TIFF size.');
    assert(all(size(alt_stim)==[H W]), 'alt_stim size mismatch TIFF size.');
end

[XX,YY] = meshgrid(1:W, 1:H);