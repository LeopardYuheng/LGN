%% apply_tiff_correction_to_day_pointer.m
%
% PURPOSE
% -------
% Applies the TIFF-SMA1 correction map (from build_tiff_sma1_correction_map.m)
% to the day_pointer produced by Step 3.
%
% For each trial in each condition entry:
%   1. Checks whether the analysis window [onset - pre .. onset + post] contains
%      any dropped TIFF (NaN in sma1_to_tiff).  If so, the trial is EXCLUDED.
%   2. Converts trial_onset_frame_idx from SMA1 trigger index to TIFF file
%      position (the value to pass to image_files in Steps 5A/5B).
%
% The corrected day_pointer is saved as  <original_name>_tiff_corrected.mat
% next to the original.
%
% PIPELINE USE
% ------------
%   In Steps 5A and 5B, select  day_pointer_*_tiff_corrected.mat  instead of
%   the original day_pointer.mat.  No other changes to those scripts are needed:
%   the corrected onset indices already point to the right positions in the
%   sorted image_files list.
%
% IMPORTANT: sma1_to_tiff(j) is the 1-based POSITION in the sorted TIFF file
%   list (as returned by dir), NOT the numeric file label.  The analysis
%   window  corrected_onset + (-pre:post)  are consecutive positions in that
%   list, which is correct as long as no drop falls inside the window (handled
%   by excluding such trials).

clear; clc;

%% ====================================================
%  FILE SELECTION
%% ====================================================

fprintf('Select tiff_correction.mat (from build_tiff_sma1_correction_map)...\n');
[cn, cd] = uigetfile('*.mat', 'Select tiff_correction.mat');
if isequal(cn, 0), error('No file selected.'); end
CORRECTION_MAT = fullfile(cd, cn);

fprintf('Select day_pointer.mat (from Step 3)...\n');
[dn, dd] = uigetfile('*.mat', 'Select day_pointer.mat', cd);
if isequal(dn, 0), error('No file selected.'); end
DAY_POINTER_MAT = fullfile(dd, dn);

%% ====================================================
%  MAIN  (leave everything below unchanged)
%% ====================================================

assert(exist(CORRECTION_MAT,'file')==2, ...
    'CORRECTION_MAT not found:\n  %s', CORRECTION_MAT);
assert(exist(DAY_POINTER_MAT,'file')==2, ...
    'DAY_POINTER_MAT not found:\n  %s', DAY_POINTER_MAT);

%% ---- Load correction map ----
C = load(CORRECTION_MAT);
sma1_to_tiff = double(C.sma1_to_tiff);   % 1 x N_SMA1, NaN = dropped
dropped_idx  = double(C.dropped_sma1_idx);
N_SMA1       = C.N_SMA1;

fprintf('Correction map loaded:\n');
fprintf('  N_SMA1          : %d\n',  N_SMA1);
fprintf('  N_TIFF          : %d\n',  C.N_TIFF);
fprintf('  Dropped frames  : %d\n',  numel(dropped_idx));
fprintf('  FIRST_LATE_TIFF : %d\n\n', C.FIRST_LATE_TIFF);

%% ---- Load day_pointer ----
tmp = load(DAY_POINTER_MAT);
if isfield(tmp,'day_pointer')
    dp = tmp.day_pointer;
else
    error('Expected variable "day_pointer" in:\n  %s', DAY_POINTER_MAT);
end
fprintf('day_pointer loaded: %d condition group(s)\n\n', numel(dp.entries));

pre_sec  = dp.cfg.pre_sec;
post_sec = dp.cfg.post_sec;

%% ---- Apply correction to each condition entry ----
total_before  = 0;
total_removed = 0;

for g = 1:numel(dp.entries)
    entry   = dp.entries(g);
    Freq    = entry.Freq;
    pre_fr  = round(pre_sec  * Freq);
    post_fr = round(post_sec * Freq);
    win     = (-pre_fr : post_fr);   % frame indices relative to onset

    onsets_orig = double(entry.trial_onset_frame_idx);   % SMA1 trigger indices
    n_tr        = numel(onsets_orig);
    total_before = total_before + n_tr;

    keep             = true(n_tr, 1);
    onsets_corrected = nan(n_tr, 1);
    reason           = repmat("", n_tr, 1);   % for diagnostic printing

    for t = 1:n_tr
        f    = onsets_orig(t);
        fwin = f + win;

        % Reject if window extends outside SMA1 record
        if any(fwin < 1) || any(fwin > N_SMA1)
            keep(t)   = false;
            reason(t) = "out of bounds";
            continue;
        end

        % Reject if any frame in window is a dropped TIFF
        if any(isnan(sma1_to_tiff(fwin)))
            keep(t)   = false;
            reason(t) = "drop in window";
            continue;
        end

        % Correct onset: SMA1 trigger index → TIFF file position
        onsets_corrected(t) = sma1_to_tiff(f);
    end

    n_removed = sum(~keep);
    total_removed = total_removed + n_removed;

    fprintf('  %s  (ch%d, %duA)\n', entry.key, entry.stim_channel, entry.current_uA);
    fprintf('    %d trials  →  %d kept,  %d excluded\n', n_tr, sum(keep), n_removed);

    % Print excluded trials
    excl_idx = find(~keep);
    for ei = 1:numel(excl_idx)
        t    = excl_idx(ei);
        f    = onsets_orig(t);
        fwin = f + win;
        % Find which SMA1 indices in window are dropped
        dropped_in_win = fwin(isnan(sma1_to_tiff(fwin)));
        fprintf('      Trial %3d: SMA1 onset #%d  — %s', ...
            entry.trial_index(t), f, char(reason(t)));
        if ~isempty(dropped_in_win)
            fprintf('  (dropped triggers: %s)', num2str(dropped_in_win));
        end
        fprintf('\n');
    end

    % Store corrected entry
    if any(keep)
        dp.entries(g).trial_onset_frame_idx    = onsets_corrected(keep);
        dp.entries(g).trial_index              = entry.trial_index(keep);
    else
        dp.entries(g).trial_onset_frame_idx    = zeros(0,1);
        dp.entries(g).trial_index              = zeros(0,1);
        fprintf('    WARNING: all trials excluded for this condition.\n');
    end
    dp.entries(g).tiff_correction_applied  = true;
    dp.entries(g).n_trials_excluded        = n_removed;
end

%% ---- Summary ----
fprintf('\n=== Summary ===\n');
fprintf('Trials before correction : %d\n', total_before);
fprintf('Trials excluded          : %d\n', total_removed);
fprintf('Trials remaining         : %d\n', total_before - total_removed);

%% ---- Save corrected day_pointer ----
dp.meta.tiff_correction_mat  = CORRECTION_MAT;
dp.meta.tiff_correction_date = char(datetime('now'));
dp.meta.updated_at           = char(datetime('now'));

[dp_dir, dp_base, dp_ext] = fileparts(DAY_POINTER_MAT);
out_path = fullfile(dp_dir, [dp_base '_tiff_corrected' dp_ext]);

day_pointer = dp;
save(out_path, 'day_pointer', '-v7.3');

fprintf('\nCorrected day_pointer saved:\n  %s\n', out_path);
fprintf('\nPipeline: in Steps 5A and 5B, select this file instead of the original\n');
fprintf('day_pointer.mat when prompted.  No other changes are required.\n');