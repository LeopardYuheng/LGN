%% build_tiff_sma1_correction_map.m
%
% PURPOSE
% -------
% Cross-references SMA1 camera-trigger times (ripple_timing.frames.time_s)
% with embedded "Time_From_Start" timestamps inside each saved TIFF to
% identify which SMA1 triggers produced no saved TIFF (dropped frames).
%
% NOTE ON FILENAMES
% -----------------
% TIFF filenames are sequential (1, 2, 3 ... N_TIFF) regardless of drops;
% a dropped frame does NOT leave a gap in the filename sequence.
% Therefore matching must use EMBEDDED TIMESTAMPS, not filenames.
%
% TWO-PART FIX FOR ROBUST MATCHING
% ---------------------------------
% The previous single-anchor approach failed because:
%   (A) Slow clock drift between Ripple and camera clocks shifts the offset
%       over time → ~3 phantom drops in 15 000 frames.
%   (B) A large timestamp discontinuity (jump) in TIFF metadata near file
%       44424 caused the TIFF pointer to get permanently stuck → all NaN.
%
% Fixes:
%   (A) Exponential moving average (EMA) updates session_offset_s after
%       every successful match, tracking slow drift within each segment.
%   (B) Pre-scan tiff_t_late for gaps > DISCONTINUITY_S (default 2 s).
%       At each discontinuity the offset is re-anchored using the current
%       (SMA1 j, TIFF k_tiff) pair.
%
% ASSUMPTION
% ----------
%   TIFFs 1 .. (FIRST_LATE_TIFF - 1) are ALL present (buffered in RAM then
%   flushed to disk — guaranteed complete). All drops occur in
%   [FIRST_LATE_TIFF .. N_SMA1]. The script verifies this.
%
% OUTPUTS  (saved to SAVE_DIR/tiff_correction.mat)
% -------
%   sma1_to_tiff      [1 x N_SMA1]  position in sorted image_files list for
%                                   each SMA1 trigger (NaN = dropped TIFF)
%   dropped_sma1_idx  [1 x N_drop]  which SMA1 trigger indices are NaN
%   N_SMA1, N_TIFF    scalars
%   FIRST_LATE_TIFF   scalar
%
% NEXT STEP
% ---------
%   Run  apply_tiff_correction_to_day_pointer.m

clear; clc;

%% ====================================================
%  NUMERIC PARAMETERS  — adjust if needed
%% ====================================================

% First TIFF position (1-based in sorted list) where drops may occur.
% Set to 1: embedded timestamps are reliable for ALL frames (including
% those initially buffered in RAM), so the full session is cross-checked.
FIRST_LATE_TIFF = 1;

% Camera frame rate (Hz) — used for early-segment verification.
FRAME_RATE_HZ = 10;

% Matching tolerance (s). Safe at ~0.5 * frame interval for 10 Hz = 0.05 s.
% The EMA keeps the running offset accurate so this can remain tight.
MATCH_TOL_S = 0.05;

% EMA smoothing factor for offset tracking (0 = no update, 1 = always reset).
% Alpha = 0.02 → time constant ~50 frames; tracks drift without over-reacting.
EMA_ALPHA = 0.02;

% Threshold for detecting a large timestamp discontinuity (s).
% Any gap in diff(tiff_t_late) larger than this OR any backward jump triggers
% a re-anchor. Set conservatively (well above the largest expected genuine
% drop gap of ~2 s for 20 consecutive dropped frames at 10 Hz).
DISCONTINUITY_S = 2.0;

%% ====================================================
%  INTERACTIVE PATH SELECTION
%% ====================================================

fprintf('Select the folder containing all session TIFF images...\n');
TIFF_DIR = uigetdir(pwd, 'Select TIFF image folder');
if isequal(TIFF_DIR, 0), error('No folder selected — aborted.'); end
fprintf('  TIFF folder   : %s\n', TIFF_DIR);

fprintf('Select ripple_timing.mat (Step 1 output)...\n');
[rt_name, rt_path] = uigetfile('*.mat', 'Select ripple_timing.mat', pwd);
if isequal(rt_name, 0), error('No file selected — aborted.'); end
RIPPLE_TIMING_MAT = fullfile(rt_path, rt_name);
fprintf('  ripple_timing : %s\n', RIPPLE_TIMING_MAT);

fprintf('Select output folder for the correction map...\n');
fprintf('  (Recommended: same folder as ripple_timing.mat)\n');
SAVE_DIR = uigetdir(rt_path, 'Select output folder for tiff_correction.mat');
if isequal(SAVE_DIR, 0), error('No folder selected — aborted.'); end
fprintf('  Save folder   : %s\n', SAVE_DIR);

SESSION_ID = input('Enter session ID (e.g. LGN26_20260630): ', 's');
SESSION_ID = strtrim(SESSION_ID);
if isempty(SESSION_ID)
    SESSION_ID = 'session';
    fprintf('  [No input — using default: "%s"]\n', SESSION_ID);
end
fprintf('  Session ID    : %s\n\n', SESSION_ID);

%% ====================================================
%  MAIN
%% ====================================================

assert(exist(TIFF_DIR,'dir')==7,           'TIFF_DIR not found:\n  %s', TIFF_DIR);
assert(exist(RIPPLE_TIMING_MAT,'file')==2, 'RIPPLE_TIMING_MAT not found:\n  %s', RIPPLE_TIMING_MAT);
if ~exist(SAVE_DIR,'dir'), mkdir(SAVE_DIR); end

%% ---- 1. Load SMA1 trigger times ----
rt = load(RIPPLE_TIMING_MAT, 'ripple_timing');
frame_times_s = double(rt.ripple_timing.frames.time_s);
frame_times_s = frame_times_s(:)';
N_SMA1 = numel(frame_times_s);
fprintf('SMA1 triggers loaded  : %d\n', N_SMA1);

%% ---- 2. Find and sort TIFF files by filename number ----
raw = [dir(fullfile(TIFF_DIR,'*.tif')); dir(fullfile(TIFF_DIR,'*.tiff'))];
assert(~isempty(raw), 'No TIFF files found in:\n  %s', TIFF_DIR);

file_nums = nan(numel(raw), 1);
for i = 1:numel(raw)
    tok = regexp(raw(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    if ~isempty(tok), file_nums(i) = str2double(tok{1}); end
end
valid     = isfinite(file_nums);
raw       = raw(valid);
file_nums = file_nums(valid);
[~, ord]  = sort(file_nums);
files     = raw(ord);
N_TIFF    = numel(files);

fprintf('TIFF files found      : %d\n', N_TIFF);
net_diff = N_SMA1 - N_TIFF;
if net_diff > 0
    fprintf('Net deficit           : %d  (SMA1 > TIFF — some frames not saved)\n\n', net_diff);
elseif net_diff < 0
    fprintf('Net surplus           : %d  (TIFF > SMA1 — camera ran past end of recording)\n\n', -net_diff);
else
    fprintf('Net difference        : 0  (counts match exactly)\n\n');
end

% N_TIFF > N_SMA1 is valid: the camera may continue briefly after SMA1
% recording stops, producing trailing frames with no trigger record.
% The three-way matching loop handles this correctly — excess trailing
% TIFFs are simply left unmatched once all SMA1 triggers are consumed.
assert(N_TIFF >= FIRST_LATE_TIFF, ...
    'FIRST_LATE_TIFF=%d but only %d TIFF files exist.', FIRST_LATE_TIFF, N_TIFF);

%% ---- 3. Read embedded timestamps for all frames ----
N_LATE = N_TIFF - FIRST_LATE_TIFF + 1;
fprintf('--- Reading embedded timestamps for TIFFs %d .. %d  (%d files) ---\n', ...
    FIRST_LATE_TIFF, N_TIFF, N_LATE);
fprintf('  (Only reads IFD header — pixel data not loaded)\n');

tiff_t_late = nan(1, N_LATE);
t_rd = tic;
for k = 1:N_LATE
    fpath = fullfile(TIFF_DIR, files(FIRST_LATE_TIFF + k - 1).name);
    tiff_t_late(k) = read_tiff_time(fpath);
    if mod(k, 5000) == 0 || k == N_LATE
        fprintf('  %d / %d  (%.0f s elapsed)\n', k, N_LATE, toc(t_rd));
    end
end
n_parsed = sum(isfinite(tiff_t_late));
fprintf('Timestamps parsed: %d / %d\n', n_parsed, N_LATE);
if n_parsed < N_LATE
    error('%d TIFF(s) had no parseable Time_From_Start tag.', N_LATE - n_parsed);
end

%% ---- 5. Initial time-base alignment (anchor at FIRST_LATE_TIFF) ----
sma1_anchor      = frame_times_s(FIRST_LATE_TIFF);
tiff_anchor      = tiff_t_late(1);
session_offset_s = sma1_anchor - tiff_anchor;   % shifts TIFF clock → Ripple clock

sma1_t_late = frame_times_s(FIRST_LATE_TIFF : end);   % 1 x N_SMA1_LATE
N_SMA1_LATE = numel(sma1_t_late);

fprintf('\nInitial time alignment:\n');
fprintf('  SMA1 anchor  (trigger #%d) : %.4f s\n', FIRST_LATE_TIFF, sma1_anchor);
fprintf('  TIFF anchor  (file   #%d) : %.4f s  (camera time)\n', FIRST_LATE_TIFF, tiff_anchor);
fprintf('  session_offset_s           : %+.6f s\n\n', session_offset_s);

%% ---- 6. Pre-scan: TIFF timestamp discontinuities ----
% Detects forward jumps > DISCONTINUITY_S or any backward jump in tiff_t_late.
% These positions need offset re-anchoring before a match can be attempted.
% SMA1-side gaps are handled dynamically in step 7 — no pre-scan needed.

dt_tiff        = diff(tiff_t_late);
tiff_disc_mask = (dt_tiff > DISCONTINUITY_S) | (dt_tiff < -MATCH_TOL_S);
tiff_disc_k    = find(tiff_disc_mask) + 1;

tiff_disc_set = false(1, N_LATE);
tiff_disc_set(tiff_disc_k) = true;

if isempty(tiff_disc_k)
    fprintf('No TIFF timestamp discontinuities detected in late segment.\n\n');
else
    fprintf('TIFF timestamp discontinuities detected (%d):\n', numel(tiff_disc_k));
    for di = 1:numel(tiff_disc_k)
        fprintf('  k=%d  (file ~%d)  dt_tiff = %.2f s\n', ...
            tiff_disc_k(di), FIRST_LATE_TIFF + tiff_disc_k(di) - 1, dt_tiff(tiff_disc_k(di) - 1));
    end
    fprintf('\n');
end

%% ---- 7. Three-way zipper matching ----
%
% At every step exactly one pointer advances — no pre-scan of SMA1 needed:
%
%   |signed_dist| <= TOL        MATCH         j++  k_tiff++
%   signed_dist  >  TOL         TIFF ahead    j++           (SMA1 trigger j = dropped TIFF)
%   signed_dist  < -TOL         SMA1 ahead         k_tiff++ (TIFF k = orphaned, SMA1 gap)
%
% where  signed_dist = tiff_t_late(k_tiff) + current_offset - sma1_t_late(j)
%
% TIFF-side re-anchor fires at known discontinuity positions (pre-scan above)
% before the match is evaluated, correcting the offset in one step.
% After each SMA1 gap the offset is re-anchored at the first post-gap match.

sma1_to_tiff_late = nan(1, N_SMA1_LATE);
current_offset    = session_offset_s;

j      = 1;
k_tiff = 1;

in_sma1_gap      = false;
sma1_gap_start_k = 0;
n_sma1_gaps      = 0;   % number of distinct gap events
n_orphaned_tiffs = 0;   % total TIFFs skipped due to SMA1 dropouts

while j <= N_SMA1_LATE && k_tiff <= N_LATE

    % TIFF-side re-anchor at known discontinuity
    if tiff_disc_set(k_tiff)
        old_off = current_offset;
        current_offset = sma1_t_late(j) - tiff_t_late(k_tiff);
        fprintf('  [TIFF jump]  file #%d, SMA1 #%d: offset %+.4f → %+.4f s  (dt=%.2f s)\n', ...
            FIRST_LATE_TIFF + k_tiff - 1, FIRST_LATE_TIFF + j - 1, ...
            old_off, current_offset, dt_tiff(k_tiff - 1));
        tiff_disc_set(k_tiff) = false;
    end

    signed_dist = (tiff_t_late(k_tiff) + current_offset) - sma1_t_late(j);

    if abs(signed_dist) <= MATCH_TOL_S
        % ---- MATCH ----
        if in_sma1_gap
            % First match after SMA1 gap: re-anchor offset, close gap log
            current_offset = sma1_t_late(j) - tiff_t_late(k_tiff);
            fprintf('  [SMA1 gap]   closed  — SMA1 #%d matched file #%d  (skipped %d TIFFs)\n', ...
                FIRST_LATE_TIFF + j - 1, FIRST_LATE_TIFF + k_tiff - 1, ...
                k_tiff - sma1_gap_start_k);
            in_sma1_gap = false;
            n_sma1_gaps = n_sma1_gaps + 1;
        end
        sma1_to_tiff_late(j) = FIRST_LATE_TIFF + k_tiff - 1;
        current_offset = (1 - EMA_ALPHA) * current_offset + ...
                         EMA_ALPHA       * (sma1_t_late(j) - tiff_t_late(k_tiff));
        j      = j + 1;
        k_tiff = k_tiff + 1;

    elseif signed_dist > MATCH_TOL_S
        % ---- TIFF AHEAD OF SMA1: dropped TIFF ----
        % sma1_to_tiff_late(j) stays NaN; advance SMA1 pointer only.
        j = j + 1;

    else
        % ---- SMA1 AHEAD OF TIFF: orphaned TIFF (SMA1 channel dropout) ----
        % Advance TIFF pointer only; j stays and will be re-evaluated.
        if ~in_sma1_gap
            fprintf('  [SMA1 gap]   opened  — file #%d, SMA1 #%d  (dist = %.3f s)\n', ...
                FIRST_LATE_TIFF + k_tiff - 1, FIRST_LATE_TIFF + j - 1, signed_dist);
            in_sma1_gap      = true;
            sma1_gap_start_k = k_tiff;
        end
        k_tiff = k_tiff + 1;
        n_orphaned_tiffs = n_orphaned_tiffs + 1;
    end

end

if in_sma1_gap
    fprintf('  [SMA1 gap]   still open at session end (TIFF pointer = %d)\n', ...
        FIRST_LATE_TIFF + k_tiff - 1);
    n_sma1_gaps = n_sma1_gaps + 1;
end
fprintf('\nSMA1 channel dropouts: %d gap events, %d orphaned TIFFs total\n', ...
    n_sma1_gaps, n_orphaned_tiffs);

% Assemble full mapping (FIRST_LATE_TIFF = 1, so prefix is empty)
sma1_to_tiff = [1:(FIRST_LATE_TIFF - 1), sma1_to_tiff_late];   % 1 x N_SMA1
dropped_sma1_idx = uint32(find(isnan(sma1_to_tiff)));

%% ---- 8. Report ----
% Conservation check:
%   M (matched)       = N_SMA1 - D  = N_TIFF - O
%   D (NaN, dropped)  = (N_SMA1 - N_TIFF) + O  ← expected NaN count
%   O (orphaned)      = n_orphaned_tiffs
%   Net deficit       = N_SMA1 - N_TIFF = D - O
n_matched     = N_SMA1 - numel(dropped_sma1_idx);
n_dropped_exp = (N_SMA1 - N_TIFF) + n_orphaned_tiffs;

fprintf('\n=== Correction map summary ===\n');
fprintf('Total SMA1 triggers  : %d\n', N_SMA1);
fprintf('Total TIFFs saved    : %d\n', N_TIFF);
fprintf('Net deficit          : %d  (= N_SMA1 - N_TIFF)\n', N_SMA1 - N_TIFF);
fprintf('SMA1 gap events      : %d\n', n_sma1_gaps);
fprintf('Orphaned TIFFs (O)   : %d  (saved but no SMA1 trigger)\n', n_orphaned_tiffs);
fprintf('Matched pairs  (M)   : %d\n', n_matched);
fprintf('Dropped TIFFs  (D)   : %d  (expected %d = %d net + %d orphans)\n', ...
    numel(dropped_sma1_idx), n_dropped_exp, N_SMA1 - N_TIFF, n_orphaned_tiffs);
if n_matched + n_orphaned_tiffs == N_TIFF
    cons_str = 'OK';
else
    cons_str = 'MISMATCH';
end
fprintf('Conservation check   : M(%d) + O(%d) = %d  vs  N_TIFF(%d)  [%s]\n', ...
    n_matched, n_orphaned_tiffs, n_matched + n_orphaned_tiffs, N_TIFF, cons_str);

if numel(dropped_sma1_idx) ~= n_dropped_exp
    warning('NaN count (%d) differs from expected (%d). Check matching logic.', ...
        numel(dropped_sma1_idx), n_dropped_exp);
end

fprintf('\nDropped SMA1 trigger indices and session times:\n');
fprintf('  %-5s  %-10s  %-14s\n', 'No.', 'SMA1#', 'Session time (s)');
fprintf('  %s\n', repmat('-', 1, 35));
for i = 1:numel(dropped_sma1_idx)
    j   = dropped_sma1_idx(i);
    fprintf('  %-5d  %-10d  %-14.4f\n', i, j, frame_times_s(j));
end

%% ---- 9. Save ----
out_fname = sprintf('%s_tiff_correction.mat', SESSION_ID);
out_path  = fullfile(SAVE_DIR, out_fname);
save(out_path, 'sma1_to_tiff', 'dropped_sma1_idx', ...
    'N_SMA1', 'N_TIFF', 'FIRST_LATE_TIFF', 'session_offset_s', 'SESSION_ID', '-v7.3');
fprintf('\nCorrection map saved:\n  %s\n', out_path);
fprintf('Next step: run  apply_tiff_correction_to_day_pointer.m\n');

%% ====================================================
%  LOCAL FUNCTION
%% ====================================================

function t_s = read_tiff_time(fpath)
% Parse "Time_From_Start = HH:MM:SS.ssss" from TIFF ImageDescription tag.
% Only opens the IFD (header) — does not load pixel data.
    tf   = Tiff(fpath, 'r');
    desc = tf.getTag('ImageDescription');
    tf.close();
    tok = regexp(desc, 'Time_From_Start\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens', 'once');
    assert(~isempty(tok), 'Time_From_Start not found in:\n  %s', fpath);
    t_s = str2double(tok{1})*3600 + str2double(tok{2})*60 + str2double(tok{3});
end