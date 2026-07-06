%% inspect_trial_tiff_assignment.m
%
% Shows which TIFF files and SMA1 triggers are assigned to each frame
% of a chosen trial.
%
% OUTPUT (printed + returned in workspace):
%   assigned_files  — cell array of TIFF filenames for the chosen trial window
%   frame_times_s   — TIFF embedded timestamps for those files (NaN if unreadable)
%   sma1_indices    — corresponding SMA1 trigger index for each frame (NaN if orphan)

clear; clc;

%% ── 1. Select files ─────────────────────────────────────────────────
fprintf('Select day_pointer (original or tiff_corrected)...\n');
[dn, dd] = uigetfile('*.mat', 'Select day_pointer.mat');
if isequal(dn,0), return; end
tmp = load(fullfile(dd,dn));
assert(isfield(tmp,'day_pointer'), 'Variable "day_pointer" not found.');
dp = tmp.day_pointer;

fprintf('Select tiff_correction.mat (for SMA1 ↔ TIFF mapping)...\n');
[cn, cd] = uigetfile('*.mat', 'Select tiff_correction.mat', dd);
have_corr = ~isequal(cn, 0);
if have_corr
    C = load(fullfile(cd, cn), 'sma1_to_tiff', 'N_SMA1', 'N_TIFF');
    sma1_to_tiff = double(C.sma1_to_tiff);   % 1 x N_SMA1, NaN = dropped TIFF
    % Inverse map: TIFF position → SMA1 trigger index (NaN for orphan TIFFs)
    tiff_to_sma1 = nan(1, C.N_TIFF);
    valid = ~isnan(sma1_to_tiff);
    tiff_to_sma1(sma1_to_tiff(valid)) = find(valid);
    fprintf('  Correction map loaded: %d SMA1 triggers, %d TIFFs.\n', C.N_SMA1, C.N_TIFF);
else
    fprintf('  (skipped — SMA1# column will be omitted)\n');
end

fprintf('Select folder containing TIFF images...\n');
tiff_dir = uigetdir(dd, 'Select TIFF folder');
if isequal(tiff_dir,0), return; end

%% ── 2. Build sorted file list ───────────────────────────────────────
raw = [dir(fullfile(tiff_dir,'*.tif')); dir(fullfile(tiff_dir,'*.tiff'))];
assert(~isempty(raw), 'No .tif/.tiff files found in selected folder.');
nums = nan(numel(raw),1);
for i = 1:numel(raw)
    tok = regexp(raw(i).name, '(\d+)\.(tiff?)$', 'tokens','once');
    if ~isempty(tok), nums(i) = str2double(tok{1}); end
end
raw  = raw(isfinite(nums));
[~, ord] = sort(nums(isfinite(nums)));
files = raw(ord);
N_TIFF = numel(files);
fprintf('\n%d TIFF files found.\n', N_TIFF);

%% ── 3. Choose condition ─────────────────────────────────────────────
fprintf('\nAvailable conditions:\n');
for g = 1:numel(dp.entries)
    e = dp.entries(g);
    corrected = isfield(e,'tiff_correction_applied') && e.tiff_correction_applied;
    fprintf('  [%2d]  ch%d  %4d uA   (%d trials)%s\n', ...
        g, e.stim_channel, e.current_uA, numel(e.trial_onset_frame_idx), ...
        repmat('  [corrected]', corrected));
end
g_sel = input('\nEnter condition number: ');
entry = dp.entries(g_sel);
n_tr  = numel(entry.trial_onset_frame_idx);

%% ── 4. Choose trial ─────────────────────────────────────────────────
fprintf('\n%d trials available. Enter trial number (1..%d), or 0 for last: ', n_tr, n_tr);
t_sel = input('');
if t_sel == 0, t_sel = n_tr; end
assert(t_sel >= 1 && t_sel <= n_tr, 'Trial index out of range.');

onset  = entry.trial_onset_frame_idx(t_sel);
Freq   = entry.Freq;
pre_fr = round(dp.cfg.pre_sec  * Freq);
post_fr= round(dp.cfg.post_sec * Freq);
win    = (-pre_fr : post_fr);

% Check whether TIFF correction has been applied.
% After correction, onset is a TIFF file position (1-based index into the
% sorted image list).  Before correction, onset is an SMA1 trigger index —
% using it to index TIFF files is only valid when no frames were dropped.
corrected = isfield(entry,'tiff_correction_applied') && entry.tiff_correction_applied;
if corrected
    fprintf('\n[INFO] tiff_correction applied — onset is a TIFF file position.\n');
else
    fprintf('\n[WARNING] tiff_correction NOT applied — onset is an SMA1 trigger index.\n');
    fprintf('          Indexing into TIFF files with SMA1 indices is only correct\n');
    fprintf('          when N_SMA1 == N_TIFF and no frames were dropped.\n');
    fprintf('          Use the _tiff_corrected day pointer for reliable results.\n');
end

frames = onset + win;   % TIFF file positions (if corrected) or SMA1 indices (if not)

%% ── 5. Print assignment table ───────────────────────────────────────
fprintf('\n=== Trial %d / %d  |  ch%d  %d uA ===\n', ...
    t_sel, n_tr, entry.stim_channel, entry.current_uA);
idx_type = 'TIFF file position';
if ~corrected, idx_type = 'SMA1 trigger index'; end
fprintf('Onset (%s) : %d\n', idx_type, onset);
fprintf('Window            : [-%d  .. +%d] frames  (%.2f .. %.2f s)\n', ...
    pre_fr, post_fr, -dp.cfg.pre_sec, dp.cfg.post_sec);
fprintf('TIFF positions    : %d .. %d\n\n', frames(1), frames(end));

out_of_range = frames < 1 | frames > N_TIFF;
if any(out_of_range)
    warning('%d frame(s) fall outside the TIFF list (will show as <OOB>).', ...
        sum(out_of_range));
end

%col1 = 'TIFF#'; if ~corrected, col1 = 'SMA1#'; end
col1 = 'TIFF#';
if have_corr
    fprintf('%-6s  %-6s  %-8s  %-40s  %s\n', col1, 'SMA1#', 'Time(s)', 'Filename', 'Embedded timestamp (s)');
    fprintf('%s\n', repmat('-',1,90));
else
    fprintf('%-6s  %-8s  %-40s  %s\n', col1, 'Time(s)', 'Filename', 'Embedded timestamp (s)');
    fprintf('%s\n', repmat('-',1,80));
end

assigned_files = cell(numel(frames),1);
frame_times_s  = nan(numel(frames),1);
sma1_indices   = nan(numel(frames),1);

for k = 1:numel(frames)
    fi    = frames(k);
    t_rel = win(k) / Freq;
    onset_marker = '';
    if win(k) == 0, onset_marker = ' ← onset'; end

    if fi < 1 || fi > N_TIFF
        if have_corr
            fprintf('%-6d  %-6s  %+7.3f   %-40s\n', fi, '—', t_rel, '<OUT OF RANGE>');
        else
            fprintf('%-6d  %+7.3f   %-40s\n', fi, t_rel, '<OUT OF RANGE>');
        end
        assigned_files{k} = '<OOB>';
        continue;
    end

    fname = files(fi).name;
    assigned_files{k} = fname;

    % SMA1 trigger for this TIFF position
    sma1_str = '—';
    if have_corr
        s = tiff_to_sma1(fi);
        if ~isnan(s)
            sma1_indices(k) = s;
            sma1_str = num2str(s);
        else
            sma1_str = 'orphan';
        end
    end

    % embedded timestamp
    fpath = fullfile(tiff_dir, fname);
    try
        tf   = Tiff(fpath,'r');
        desc = tf.getTag('ImageDescription');
        tf.close();
        tok  = regexp(desc, 'Time_From_Start\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens','once');
        if ~isempty(tok)
            frame_times_s(k) = str2double(tok{1})*3600 + ...
                                str2double(tok{2})*60   + ...
                                str2double(tok{3});
        end
    catch
    end

    ts_str = '(no timestamp)';
    if ~isnan(frame_times_s(k)), ts_str = sprintf('%.4f', frame_times_s(k)); end

    if have_corr
        fprintf('%-6d  %-8s  %+7.3f   %-40s  %s%s\n', ...
            fi, sma1_str, t_rel, fname, ts_str, onset_marker);
    else
        fprintf('%-6d  %+7.3f   %-40s  %s%s\n', ...
            fi, t_rel, fname, ts_str, onset_marker);
    end
end

fprintf('\nassigned_files, frame_times_s, and sma1_indices saved to workspace.\n');