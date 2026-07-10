%% consensus_7E.m
% Step 7_E: Sustained and latency-consistent activation region (Method 1).
%
% Identifies pixels with BOTH:
%   1. A consecutive activated (or suppressed) run of >= min_duration_s
%      seconds in >= min_trials_sust trials (post-stim only).
%   2. Among those sustained trials, >= min_trials_win trials whose onset
%      time clusters within any onset_window_s-wide sliding window.
%
% Per-trial thresholding (same as 7_C):
%   baseline_dF/F(x,y) = mean( dF/F(x,y, t<0) )
%   sigma_pre(x,y)     = std(  dF/F(x,y, t<0) )
%   activated  <=>  dF/F - baseline >  n_std * sigma_pre
%   suppressed <=>  dF/F - baseline < -n_std * sigma_pre
%
% Onset time t_onset_k = time of the first frame of the first qualifying
% consecutive run (>= min_duration_s) in trial k.
%
% Activation and suppression are evaluated independently.
%
% Requires:
%   - Per-trial Method 1 dF/F movies from one condition folder
%     (method1/ch{N}_{I}uA/  from step 5_B)
%   - brain_mask.mat  (from pre-step B)
%
% Outputs (tagged sustained_<cond>_<n>s_dur<D>s_sust<MS>_wmin<MW>_wsize<W>s_m1):
%   _region.png  — activated (red) and suppressed (blue) region maps
%   .mat         — region masks, count maps, onset window info, parameters

close all; clc; clear; fclose('all');

%% -------------------------
% SELECT CONDITION FOLDER
% -------------------------
cond_dir = uigetdir(pwd, 'Select condition folder (method1/ch{N}_{I}uA/)');
if isequal(cond_dir, 0), error('No folder selected.'); end

trial_files = dir(fullfile(cond_dir, 'dff_m1_*_trial*.mat'));
assert(~isempty(trial_files), 'No dff_m1_*_trial*.mat files found in:\n  %s', cond_dir);
n_trials = numel(trial_files);
fprintf('Found %d trial file(s) in:\n  %s\n', n_trials, cond_dir);

[~, folder_name] = fileparts(cond_dir);
tok = regexp(folder_name, '(ch\d+_[\d.]+uA)', 'tokens', 'once');
cond_label = tok{1};
if isempty(cond_label), cond_label = folder_name; end
fprintf('Condition: %s\n', cond_label);

%% -------------------------
% SELECT OUTPUT FOLDER
% -------------------------
save_dir = uigetdir(cond_dir, 'Select output folder');
if isequal(save_dir, 0), error('No output folder selected.'); end
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

%% -------------------------
% LOAD BRAIN MASK
% -------------------------
[mask_fn, mask_fp] = uigetfile('*.mat', 'Select brain_mask.mat');
if isequal(mask_fn, 0), error('No brain mask selected.'); end

M = load(fullfile(mask_fp, mask_fn));
assert(isfield(M, 'reference_mask_struct') && isfield(M.reference_mask_struct, 'final_mask'), ...
    'File does not contain reference_mask_struct.final_mask. Did you run draw_brain_mask_0.m?');
final_mask = logical(M.reference_mask_struct.final_mask);
[H, W] = size(final_mask);
fprintf('Brain mask: %d x %d  |  %d in-mask pixels\n', H, W, sum(final_mask(:)));

%% -------------------------
% OPTIONAL: V1 BOUNDARY OVERLAY
% -------------------------
v1_outline_color = [0.10 0.85 0.30];
[v1_fn, v1_fp] = uigetfile('*.mat', ...
    'Optional: select day_setup with V1 boundary (Cancel = none)');
if isequal(v1_fn, 0)
    V1_mask = [];
    fprintf('No V1 overlay selected.\n');
else
    V1_mask = load_v1_mask(fullfile(v1_fp, v1_fn), [H W]);
    if ~isempty(V1_mask)
        fprintf('V1 boundary loaded: %s\n', v1_fn);
    end
end

%% -------------------------
% PARAMETERS
% -------------------------
sigma_char = char(963);

answer = inputdlg({ ...
    sprintf('Threshold multiplier n_std  (same as 7_C; %s_pre = pre-stim std):', sigma_char), ...
    'Minimum consecutive activation duration (s)  [min_duration_s]:', ...
    'Minimum trials with a sustained run  [min_trials_sustained]:', ...
    'Minimum sustained trials with onset in same window  [min_trials_window]:', ...
    'Onset consistency window width (s)  [onset_window_s]:'}, ...
    'Step 7_E parameters', [1 72], ...
    {'1', '0.3', '15', '12', '0.5'});

if isempty(answer), error('No parameters entered. Cancelled.'); end

n_std           = str2double(answer{1});
min_duration_s  = str2double(answer{2});
min_trials_sust = round(str2double(answer{3}));
min_trials_win  = round(str2double(answer{4}));
onset_window_s  = str2double(answer{5});

assert(isfinite(n_std) && n_std > 0,                   'n_std must be a positive number.');
assert(isfinite(min_duration_s) && min_duration_s > 0, 'min_duration_s must be positive.');
assert(min_trials_sust > 0,                            'min_trials_sustained must be positive.');
assert(min_trials_win  > 0,                            'min_trials_window must be positive.');
assert(isfinite(onset_window_s) && onset_window_s > 0, 'onset_window_s must be positive.');

fprintf('\nParameters:\n');
fprintf('  n_std          = %g\n', n_std);
fprintf('  min_duration_s = %.2f s\n', min_duration_s);
fprintf('  min_trials_sust= %d\n', min_trials_sust);
fprintf('  min_trials_win = %d\n', min_trials_win);
fprintf('  onset_window_s = %.2f s\n', onset_window_s);

if n_trials < min_trials_sust
    warning('n_trials (%d) < min_trials_sustained (%d) — no pixel can qualify.', ...
        n_trials, min_trials_sust);
end

%% -------------------------
% LOAD FIRST TRIAL — get dimensions and timing
% -------------------------
S0 = load(fullfile(cond_dir, trial_files(1).name), 'dff_movie', 't_s');
assert(isfield(S0, 'dff_movie') && isfield(S0, 't_s'), ...
    'Trial file must contain dff_movie and t_s.');
[H2, W2, T] = size(S0.dff_movie);
assert(H2 == H && W2 == W, ...
    'Movie size (%dx%d) does not match brain mask (%dx%d).', H2, W2, H, W);

t_s = double(S0.t_s(:)');
assert(numel(t_s) == T, 't_s length does not match movie frame count.');

Fs          = 1 / (t_s(2) - t_s(1));
prestim_idx = find(t_s < 0);
post_idx    = find(t_s >= 0);
T_post      = numel(post_idx);
t_s_post    = t_s(post_idx);

assert(~isempty(prestim_idx), 'No pre-stim frames (t_s < 0).');
assert(~isempty(post_idx),    'No post-stim frames (t_s >= 0).');

min_frames = max(1, round(min_duration_s * Fs));
fprintf('\nCamera rate: %.2f Hz  |  min_duration = %d frames\n', Fs, min_frames);
fprintf('Post-stim frames: %d  (%.2f to %.2f s)\n', T_post, t_s_post(1), t_s_post(end));

%% -------------------------
% MAIN LOOP — per-trial sustained detection
% -------------------------
% onset_mat_act/sup : n_trials x H x W (single), NaN = trial not sustained
onset_mat_act = NaN(n_trials, H, W, 'single');
onset_mat_sup = NaN(n_trials, H, W, 'single');

n_sustained_act = zeros(H, W, 'uint16');
n_sustained_sup = zeros(H, W, 'uint16');

fprintf('\nProcessing %d trials...\n', n_trials);

for k = 1:n_trials
    Sk  = load(fullfile(cond_dir, trial_files(k).name), 'dff_movie');
    dff = double(Sk.dff_movie);   % H x W x T

    baseline = mean(dff(:,:,prestim_idx), 3);     % H x W
    sigma    = std( dff(:,:,prestim_idx), 0, 3);  % H x W
    thresh   = n_std * sigma;                      % H x W

    dff_c    = dff - baseline;                     % H x W x T (broadcasts)

    act_post = dff_c(:,:,post_idx) >  thresh;      % H x W x T_post (logical)
    sup_post = dff_c(:,:,post_idx) < -thresh;      % H x W x T_post (logical)

    [has_act, t_act] = first_sustained_onset(act_post, min_frames, t_s_post);
    [has_sup, t_sup] = first_sustained_onset(sup_post, min_frames, t_s_post);

    n_sustained_act = n_sustained_act + uint16(has_act);
    n_sustained_sup = n_sustained_sup + uint16(has_sup);

    onset_mat_act(k,:,:) = single(t_act);   % NaN where not sustained
    onset_mat_sup(k,:,:) = single(t_sup);

    if mod(k, 10) == 0 || k == n_trials
        fprintf('  Trial %d / %d\n', k, n_trials);
    end
end

%% -------------------------
% SLIDING WINDOW ONSET COUNT
% -------------------------
fprintf('Computing onset consistency (sliding window)...\n');

[peak_onset_count_act, best_win_act] = sliding_window_peak(onset_mat_act, onset_window_s, H, W);
[peak_onset_count_sup, best_win_sup] = sliding_window_peak(onset_mat_sup, onset_window_s, H, W);

%% -------------------------
% REGION MASKS
% -------------------------
activated_region  = final_mask & ...
    (double(n_sustained_act) >= min_trials_sust) & ...
    (peak_onset_count_act    >= min_trials_win);

suppressed_region = final_mask & ...
    (double(n_sustained_sup) >= min_trials_sust) & ...
    (peak_onset_count_sup    >= min_trials_win);

fprintf('Activated region:  %d pixels\n', sum(activated_region(:)));
fprintf('Suppressed region: %d pixels\n', sum(suppressed_region(:)));

%% -------------------------
% OUTPUT TAG
% -------------------------
if n_std == round(n_std)
    n_std_lbl = sprintf('%d%s', round(n_std), sigma_char);
else
    n_std_lbl = sprintf('%g%s', n_std, sigma_char);
end

out_tag = sprintf('%s_%s_dur%gs_sust%d_wmin%d_wsize%gs_m1', ...
    cond_label, n_std_lbl, min_duration_s, min_trials_sust, min_trials_win, onset_window_s);

%% -------------------------
% SAVE .mat
% -------------------------
mat_fname = sprintf('sustained_%s.mat', out_tag);
save(fullfile(save_dir, mat_fname), ...
    'activated_region', 'suppressed_region', ...
    'n_sustained_act',  'n_sustained_sup', ...
    'peak_onset_count_act', 'peak_onset_count_sup', ...
    'best_win_act', 'best_win_sup', ...
    'n_std', 'min_duration_s', 'min_trials_sust', 'min_trials_win', 'onset_window_s', ...
    'cond_label', 't_s', 'n_trials', 'final_mask', 'V1_mask', '-v7.3');
fprintf('Saved: %s\n', mat_fname);

%% -------------------------
% FIGURE: region map (activated | suppressed)
% -------------------------
fig = figure('Color', 'w', ...
    'Name', sprintf('Sustained region — %s', cond_label), ...
    'Position', [50 50 1200 520]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
image(ax1, region_rgb(final_mask, activated_region, [0.85 0.15 0.15]));
axis(ax1, 'image'); axis(ax1, 'off'); set(ax1, 'YDir', 'normal');
hold(ax1, 'on');
visboundaries(ax1, final_mask, 'Color', [0.8 0.8 0.8], 'LineWidth', 0.8);
if ~isempty(V1_mask)
    visboundaries(ax1, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
end
title(ax1, sprintf('Activated  (%d px)', sum(activated_region(:))), 'FontSize', 11);

ax2 = nexttile(tl);
image(ax2, region_rgb(final_mask, suppressed_region, [0.15 0.15 0.85]));
axis(ax2, 'image'); axis(ax2, 'off'); set(ax2, 'YDir', 'normal');
hold(ax2, 'on');
visboundaries(ax2, final_mask, 'Color', [0.8 0.8 0.8], 'LineWidth', 0.8);
if ~isempty(V1_mask)
    visboundaries(ax2, V1_mask, 'Color', v1_outline_color, 'LineWidth', 1.0);
end
title(ax2, sprintf('Suppressed  (%d px)', sum(suppressed_region(:))), 'FontSize', 11);

title(tl, sprintf('%s  |  %s  |  dur≥%.2fs  sust≥%d  wmin≥%d  win=%.2fs', ...
    cond_label, n_std_lbl, min_duration_s, min_trials_sust, min_trials_win, onset_window_s), ...
    'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');

fig_fname = sprintf('sustained_%s_region.png', out_tag);
exportgraphics(fig, fullfile(save_dir, fig_fname), 'Resolution', 150);
close(fig);
fprintf('Saved: %s\n', fig_fname);

fprintf('\nDone. Outputs in:\n  %s\n', save_dir);

%% =========================
% LOCAL FUNCTIONS
%% =========================

function [has_sustained, onset_time] = first_sustained_onset(binary_post, min_frames, t_s_post)
% For each pixel, find the first consecutive run of >= min_frames in
% binary_post (H x W x T_post) and return:
%   has_sustained : H x W logical
%   onset_time    : H x W double, NaN where not sustained
[H, W, T_post] = size(binary_post);
running_count = zeros(H, W);
has_sustained = false(H, W);
onset_time    = NaN(H, W);

for ti = 1:T_post
    frame         = double(binary_post(:,:,ti));
    running_count = frame .* (running_count + 1);

    % Pixels completing a qualifying run for the first time this frame
    just_qualified = (running_count >= min_frames) & ~has_sustained;
    if any(just_qualified(:))
        onset_post_idx            = max(1, ti - min_frames + 1);
        onset_time(just_qualified) = t_s_post(onset_post_idx);
        has_sustained              = has_sustained | just_qualified;
    end

    if all(has_sustained(isfinite(onset_time) | ~has_sustained))  % early exit
        break;
    end
end
end


function [peak_count, best_window] = sliding_window_peak(onset_mat, window_s, H, W)
% For each pixel, find the window of width window_s containing the most
% onset times.
%   onset_mat   : n_trials x H x W (single), NaN = not sustained
%   Returns:
%   peak_count  : H x W double
%   best_window : H x W x 2 double ([t_start t_end] of best window)
n_trials   = size(onset_mat, 1);
peak_count  = zeros(H, W);
best_window = NaN(H, W, 2);

for i = 1:n_trials
    t_start = reshape(onset_mat(i,:,:), H, W);   % H x W, NaN if not sustained

    % Count onsets in [t_start, t_start + window_s) for every pixel
    t_start_3d = reshape(t_start, [1 H W]);       % 1 x H x W for broadcasting
    in_window  = (onset_mat >= t_start_3d) & ...
                 (onset_mat <  t_start_3d + window_s);  % n_trials x H x W
    count = reshape(sum(in_window, 1), H, W);     % H x W

    % Pixels where trial i is not sustained contribute nothing
    count(isnan(t_start)) = 0;

    better = count > peak_count;
    peak_count(better) = count(better);
    best_window(:,:,1) = best_window(:,:,1) .* ~better + t_start         .* better;
    best_window(:,:,2) = best_window(:,:,2) .* ~better + (t_start + window_s) .* better;
end
end


function rgb = region_rgb(in_mask, region_mask, region_color)
% Build an H x W x 3 RGB image:
%   out-of-mask pixels : dark gray [0.15 0.15 0.15]
%   in-mask, non-region: medium gray [0.55 0.55 0.55]
%   region pixels      : region_color (1x3)
[H, W] = size(in_mask);
rgb = zeros(H, W, 3);
for c = 1:3
    layer = 0.15 * ones(H, W);
    layer(in_mask)      = 0.55;
    layer(region_mask)  = region_color(c);
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
        warning('V1_mask size does not match movie size — V1 overlay skipped.');
        V1_mask = [];
    end
catch ME
    warning('Could not load V1 boundary: %s', ME.message);
end
end