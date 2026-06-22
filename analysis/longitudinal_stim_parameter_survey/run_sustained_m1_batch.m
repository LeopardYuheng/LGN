function run_sustained_m1_batch(cond_dir, save_dir, brain_mask_file, ...
    n_std, min_duration_s, min_trials_sust, min_trials_win, onset_window_s, ...
    v1_source_file)
% run_sustained_m1_batch  Headless batch version of consensus_7E.
%
% Runs the sustained + latency-consistent activation analysis for one
% channel-current condition folder with no UI dialogs.
%
% Usage:
%   run_sustained_m1_batch(cond_dir, save_dir, brain_mask_file, ...
%       n_std, min_duration_s, min_trials_sust, min_trials_win, onset_window_s)
%   run_sustained_m1_batch(..., v1_source_file)
%
% Arguments:
%   cond_dir          folder of per-trial Method 1 movies (method1/ch{N}_{I}uA/)
%   save_dir          output folder (created if absent)
%   brain_mask_file   path to brain_mask.mat
%   n_std             threshold multiplier (e.g. 1)
%   min_duration_s    minimum consecutive activation duration in seconds (e.g. 0.3)
%   min_trials_sust   trials that must have a sustained run (e.g. 15)
%   min_trials_win    sustained trials whose onset must cluster in one window (e.g. 12)
%   onset_window_s    sliding window width for onset consistency in seconds (e.g. 0.5)
%   v1_source_file    optional: path to day_setup .mat with V1 boundary; '' = none

if nargin < 9, v1_source_file = ''; end

sigma_char       = char(963);
v1_outline_color = [0.10 0.85 0.30];

%% -------------------------
% VALIDATE AND COLLECT FILES
% -------------------------
assert(isfolder(cond_dir), 'Condition folder not found:\n  %s', cond_dir);

trial_files = dir(fullfile(cond_dir, 'dff_m1_*_trial*.mat'));
assert(~isempty(trial_files), 'No dff_m1_*_trial*.mat files in:\n  %s', cond_dir);

nums = nan(numel(trial_files), 1);
for i = 1:numel(trial_files)
    tok = regexp(trial_files(i).name, 'trial(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok), nums(i) = str2double(tok{1}); end
end
[~, ord]    = sort(nums);
trial_files = trial_files(ord);
n_trials    = numel(trial_files);

[~, folder_name] = fileparts(cond_dir);
tok = regexp(trial_files(1).name, '(ch\d+_[\d.]+uA)', 'tokens', 'once');
if ~isempty(tok), cond_label = tok{1}; else, cond_label = folder_name; end

fprintf('Condition %s : %d trial(s)\n', cond_label, n_trials);

if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% LOAD BRAIN MASK
% -------------------------
assert(isfile(brain_mask_file), 'brain_mask_file not found:\n  %s', brain_mask_file);
M = load(brain_mask_file, 'reference_mask_struct');
assert(isfield(M, 'reference_mask_struct') && isfield(M.reference_mask_struct, 'final_mask'), ...
    'brain_mask_file does not contain reference_mask_struct.final_mask.');
final_mask = logical(M.reference_mask_struct.final_mask);
[H, W] = size(final_mask);
fprintf('Brain mask: %d x %d\n', H, W);

%% -------------------------
% OPTIONAL V1 OVERLAY
% -------------------------
V1_mask = [];
if ~isempty(v1_source_file) && isfile(v1_source_file)
    V1_mask = load_v1_mask(v1_source_file, [H W]);
    if ~isempty(V1_mask), fprintf('V1 boundary loaded.\n'); end
end

%% -------------------------
% TIMING FROM FIRST TRIAL
% -------------------------
S0 = load(fullfile(cond_dir, trial_files(1).name), 'dff_movie', 't_s');
[H2, W2, T] = size(S0.dff_movie);
assert(H2 == H && W2 == W, 'Movie size (%dx%d) does not match brain mask (%dx%d).', H2, W2, H, W);

t_s         = double(S0.t_s(:)');
Fs          = 1 / (t_s(2) - t_s(1));
prestim_idx = find(t_s < 0);
post_idx    = find(t_s >= 0);
T_post      = numel(post_idx);
t_s_post    = t_s(post_idx);
min_frames  = max(1, round(min_duration_s * Fs));

assert(~isempty(prestim_idx), 'No pre-stim frames (t_s < 0).');
assert(~isempty(post_idx),    'No post-stim frames (t_s >= 0).');

fprintf('Fs = %.2f Hz | min_duration = %d frames | post-stim frames = %d\n', ...
    Fs, min_frames, T_post);
if n_trials < min_trials_sust
    warning('n_trials (%d) < min_trials_sust (%d) — no pixel can qualify.', ...
        n_trials, min_trials_sust);
end

%% -------------------------
% MAIN LOOP — per-trial sustained detection
% -------------------------
onset_mat_act = NaN(n_trials, H, W, 'single');
onset_mat_sup = NaN(n_trials, H, W, 'single');
n_sustained_act = zeros(H, W, 'uint16');
n_sustained_sup = zeros(H, W, 'uint16');

for k = 1:n_trials
    Sk  = load(fullfile(cond_dir, trial_files(k).name), 'dff_movie');
    dff = double(Sk.dff_movie);

    baseline = mean(dff(:,:,prestim_idx), 3);
    sigma    = std( dff(:,:,prestim_idx), 0, 3);
    thresh   = n_std * sigma;
    dff_c    = dff - baseline;

    act_post = dff_c(:,:,post_idx) >  thresh;
    sup_post = dff_c(:,:,post_idx) < -thresh;

    [has_act, t_act] = first_sustained_onset(act_post, min_frames, t_s_post);
    [has_sup, t_sup] = first_sustained_onset(sup_post, min_frames, t_s_post);

    n_sustained_act = n_sustained_act + uint16(has_act);
    n_sustained_sup = n_sustained_sup + uint16(has_sup);
    onset_mat_act(k,:,:) = single(t_act);
    onset_mat_sup(k,:,:) = single(t_sup);

    if mod(k, 10) == 0 || k == n_trials
        fprintf('  Trial %d / %d\n', k, n_trials);
    end
end

%% -------------------------
% SLIDING WINDOW ONSET COUNT
% -------------------------
[peak_onset_count_act, best_win_act] = sliding_window_peak(onset_mat_act, onset_window_s, H, W);
[peak_onset_count_sup, best_win_sup] = sliding_window_peak(onset_mat_sup, onset_window_s, H, W);

%% -------------------------
% REGION MASKS
% -------------------------
activated_region  = final_mask & ...
    (double(n_sustained_act) >= min_trials_sust) & (peak_onset_count_act >= min_trials_win);
suppressed_region = final_mask & ...
    (double(n_sustained_sup) >= min_trials_sust) & (peak_onset_count_sup >= min_trials_win);

fprintf('Activated region:  %d px\n', sum(activated_region(:)));
fprintf('Suppressed region: %d px\n', sum(suppressed_region(:)));

%% -------------------------
% OUTPUT TAG AND SAVE
% -------------------------
if n_std == round(n_std)
    n_std_lbl = sprintf('%d%s', round(n_std), sigma_char);
else
    n_std_lbl = sprintf('%g%s', n_std, sigma_char);
end

out_tag = sprintf('%s_%s_dur%gs_sust%d_wmin%d_wsize%gs_m1', ...
    cond_label, n_std_lbl, min_duration_s, min_trials_sust, min_trials_win, onset_window_s);

save(fullfile(save_dir, sprintf('sustained_%s.mat', out_tag)), ...
    'activated_region', 'suppressed_region', ...
    'n_sustained_act', 'n_sustained_sup', ...
    'peak_onset_count_act', 'peak_onset_count_sup', ...
    'best_win_act', 'best_win_sup', ...
    'n_std', 'min_duration_s', 'min_trials_sust', 'min_trials_win', 'onset_window_s', ...
    'cond_label', 't_s', 'n_trials', 'final_mask', 'V1_mask', '-v7.3');

%% -------------------------
% FIGURE
% -------------------------
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [50 50 1200 520]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
image(ax1, region_rgb(final_mask, activated_region, [0.85 0.15 0.15]));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal'); hold(ax1, 'on');
visboundaries(ax1, final_mask, 'Color', [0.8 0.8 0.8], 'LineWidth', 0.8);
if ~isempty(V1_mask), visboundaries(ax1, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0); end
title(ax1, sprintf('Activated  (%d px)', sum(activated_region(:))), 'FontSize', 11);

ax2 = nexttile(tl);
image(ax2, region_rgb(final_mask, suppressed_region, [0.15 0.15 0.85]));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal'); hold(ax2, 'on');
visboundaries(ax2, final_mask, 'Color', [0.8 0.8 0.8], 'LineWidth', 0.8);
if ~isempty(V1_mask), visboundaries(ax2, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0); end
title(ax2, sprintf('Suppressed  (%d px)', sum(suppressed_region(:))), 'FontSize', 11);

title(tl, sprintf('%s  |  %s  |  dur≥%.2fs  sust≥%d  wmin≥%d  win=%.2fs', ...
    cond_label, n_std_lbl, min_duration_s, min_trials_sust, min_trials_win, onset_window_s), ...
    'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');

fig_fname = sprintf('sustained_%s_region.png', out_tag);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', fig_fname);
fprintf('Done. Outputs in:\n  %s\n', save_dir);
end

%% =========================
% LOCAL FUNCTIONS
%% =========================

function [has_sustained, onset_time] = first_sustained_onset(binary_post, min_frames, t_s_post)
[H, W, T_post] = size(binary_post);
running_count = zeros(H, W);
has_sustained = false(H, W);
onset_time    = NaN(H, W);
for ti = 1:T_post
    running_count = double(binary_post(:,:,ti)) .* (running_count + 1);
    just_qualified = (running_count >= min_frames) & ~has_sustained;
    if any(just_qualified(:))
        onset_post_idx = max(1, ti - min_frames + 1);
        onset_time(just_qualified) = t_s_post(onset_post_idx);
        has_sustained = has_sustained | just_qualified;
    end
end
end

function [peak_count, best_window] = sliding_window_peak(onset_mat, window_s, H, W)
n_trials    = size(onset_mat, 1);
peak_count  = zeros(H, W);
best_window = NaN(H, W, 2);
for i = 1:n_trials
    t_start    = reshape(onset_mat(i,:,:), H, W);
    t_start_3d = reshape(t_start, [1 H W]);
    in_window  = (onset_mat >= t_start_3d) & (onset_mat < t_start_3d + window_s);
    count      = reshape(sum(in_window, 1), H, W);
    count(isnan(t_start)) = 0;
    better = count > peak_count;
    peak_count(better) = count(better);
    best_window(:,:,1) = best_window(:,:,1) .* ~better + t_start             .* better;
    best_window(:,:,2) = best_window(:,:,2) .* ~better + (t_start + window_s).* better;
end
end

function rgb = region_rgb(in_mask, region_mask, region_color)
[H, W] = size(in_mask);
rgb = zeros(H, W, 3);
for c = 1:3
    layer = 0.15 * ones(H, W);
    layer(in_mask)     = 0.55;
    layer(region_mask) = region_color(c);
    rgb(:,:,c) = layer;
end
end

function V1_mask = load_v1_mask(fpath, expected_size)
V1_mask = [];
try
    D = load(fpath);
    if isfield(D, 'retino_align') && isfield(D.retino_align, 'V1_mask_stim')
        V1_mask = logical(D.retino_align.V1_mask_stim);
    elseif isfield(D, 'day_setup') && isfield(D.day_setup, 'retino_align')
        V1_mask = logical(D.day_setup.retino_align.V1_mask_stim);
    end
    if ~isempty(expected_size) && ~isempty(V1_mask) && ~isequal(size(V1_mask), expected_size)
        warning('V1_mask size mismatch — overlay skipped.');
        V1_mask = [];
    end
catch ME
    warning('Could not load V1 boundary: %s', ME.message);
end
end