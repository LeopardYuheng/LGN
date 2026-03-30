%% current_thresholding_V1_cluster_sharedclim_option.m
% ROI-free threshold analysis using V1-restricted pixelwise significance
% and cluster detection, based on grouped Ripple container entries.
%
% CHANGES:
%   1) Uses the SAME displayed mean evoked map as the montage script:
%        mean_evoked_map = mean(dff_cur, 3, 'omitnan')
%   2) Does NOT subtract the 0 uA map again
%   3) Adds option to use a shared CLim across channel plots or not
%
% Uses:
%   - day_pointer
%   - day_pointer.cfg.pre_sec / day_pointer.cfg.post_sec
%   - day_setup.reference_mask.final_mask
%   - day_setup.retino_align.V1_mask_stim
%   - day_setup.retino_align.azi_stim
%   - day_setup.retino_align.alt_stim
%
% Outputs:
%   - per-channel threshold estimates
%   - per-current cluster metrics
%   - visual field scatter plot
%   - saved summary MAT

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
Fs = 10;                        % camera rate
response_sec = [0 1.0];         % post-stim response window
alpha = 0.05;                   % t-test alpha
min_cluster_size = 15;          % cluster size threshold
conn = 8;                       % connectivity for bwconncomp

use_shared_clim = true;         % true = one CLim across all anchor plots
shared_clim = [-0.06 0.06];               % leave [] to auto-compute from all anchor maps
                                % or set manually, e.g. [-0.01 0.02]

mask_outside_for_display = false;  % false matches montage look better
use_analysis_mask_for_stats = true; % true = stats only inside final_mask & V1_mask

%% -------------------------
% LOAD CONTAINER
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select day pointer');
if isequal(fn,0), error('No file selected'); end

S = load(fullfile(fp, fn));
if isfield(S,'day_pointer')
    day_pointer = S.day_pointer;
elseif isfield(S,'C')
    day_pointer = S.C;
else
    error('Selected file must contain struct "day_pointer" or legacy struct "C".');
end

assert(isfield(day_pointer,'meta'), 'day_pointer.meta missing.');
assert(isfield(day_pointer,'cfg'), 'day_pointer.cfg missing.');
assert(isfield(day_pointer,'entries') && ~isempty(day_pointer.entries), 'day_pointer.entries missing or empty.');

%% -------------------------
% RESOLVE PATHS
% -------------------------
dataset_root = day_pointer.meta.dataset_root;

p_day = day_pointer.meta.day_setup_file_rel;
if exist(p_day, 'file') == 2
    day_setup_file = p_day;
else
    day_setup_file = fullfile(dataset_root, p_day);
end

p_img = day_pointer.meta.img_dir_rel;
if exist(p_img, 'dir') == 7
    img_dir = p_img;
else
    img_dir = fullfile(dataset_root, p_img);
end

fprintf('Resolved dataset_root:\n  %s\n', dataset_root);
fprintf('Resolved day_setup_file:\n  %s\n', day_setup_file);
fprintf('Resolved img_dir:\n  %s\n', img_dir);

assert(exist(day_setup_file, 'file') == 2, ...
    'Resolved day_setup_file does not exist.');
assert(exist(img_dir, 'dir') == 7, ...
    'Resolved img_dir does not exist.');

%% -------------------------
% LOAD DAY SETUP
% -------------------------
D = load(day_setup_file);
assert(isfield(D,'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask    = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;

azi_stim = day_setup.retino_align.azi_stim;
alt_stim = day_setup.retino_align.alt_stim;

[H,W] = size(analysis_mask);

%% -------------------------
% LOAD TIFF FILES
% -------------------------
image_files = [dir(fullfile(img_dir, '*.tif')); dir(fullfile(img_dir, '*.tiff'))];
assert(~isempty(image_files), 'No TIFFs found');

nums = nan(numel(image_files),1);
for i = 1:numel(image_files)
    tok = regexp(image_files(i).name, '(\d+)\.(tif|tiff)$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename missing trailing numeric index: %s', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~,ord] = sort(nums);
image_files = image_files(ord);

nFrames = numel(image_files);
fprintf('Found %d TIFF frames.\n', nFrames);

%% -------------------------
% CAMERA RATE / WINDOWS FROM CONTAINER
% -------------------------
pre_sec  = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames  = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);

full_win = -pre_frames:post_frames;
baseline_idx = full_win < 0;
response_idx = full_win > response_sec(1) & full_win <= response_sec(2);

assert(any(baseline_idx), 'No baseline frames selected.');
assert(any(response_idx), 'No response frames selected.');

fprintf('Camera rate: %.3f Hz\n', Fs);
fprintf('pre_sec = %.3f, post_sec = %.3f\n', pre_sec, post_sec);
fprintf('Baseline frames: %d\n', sum(baseline_idx));
fprintf('Response frames: %d\n', sum(response_idx));

%% -------------------------
% RECONSTRUCT PER-TRIAL VECTORS FROM GROUPED ENTRIES
% -------------------------
entries = day_pointer.entries;

frame_idx = [];
channels  = [];
currents  = [];
trial_index = [];

for i = 1:numel(entries)

    assert(isfield(entries(i), 'trial_onset_frame_idx'), ...
        'Entry %d missing trial_onset_frame_idx', i);
    assert(isfield(entries(i), 'stim_channel'), ...
        'Entry %d missing stim_channel', i);
    assert(isfield(entries(i), 'current_uA'), ...
        'Entry %d missing current_uA', i);

    onset_i = double(entries(i).trial_onset_frame_idx(:));
    n_i = numel(onset_i);

    frame_idx = [frame_idx; onset_i];
    channels  = [channels; repmat(double(entries(i).stim_channel), n_i, 1)];
    currents  = [currents; repmat(double(entries(i).current_uA), n_i, 1)];

    if isfield(entries(i), 'trial_index') && ~isempty(entries(i).trial_index)
        trial_index = [trial_index; double(entries(i).trial_index(:))];
    else
        trial_index = [trial_index; nan(n_i,1)];
    end
end

valid = isfinite(frame_idx) & isfinite(channels) & isfinite(currents) & ...
        frame_idx > pre_frames & frame_idx <= (nFrames - post_frames);

fprintf('Keeping %d / %d trials after frame validity filter.\n', ...
    sum(valid), numel(frame_idx));

frame_idx   = frame_idx(valid);
channels    = channels(valid);
currents    = currents(valid);
trial_index = trial_index(valid);

%% -------------------------
% RESULTS STRUCT
% -------------------------
unique_channels = unique(channels);

results = struct( ...
    'channel', {}, ...
    'threshold_uA', {}, ...
    'anchor_current_uA', {}, ...
    'azi', {}, ...
    'alt', {}, ...
    'peak_xy', {}, ...
    'current_summary', {}, ...
    'anchor_mean_map', {} );
% ----- compute once near the top of the script, same as montage script -----
pad_xy = 10;

[y_v1, x_v1] = find(V1_mask);

ymin_v1 = min(y_v1);
ymax_v1 = max(y_v1);
xmin_v1 = min(x_v1);
xmax_v1 = max(x_v1);

ymin_v1 = max(1, ymin_v1 - pad_xy);
ymax_v1 = min(size(V1_mask,1), ymax_v1 + pad_xy);
xmin_v1 = max(1, xmin_v1 - pad_xy);
xmax_v1 = min(size(V1_mask,2), xmax_v1 + pad_xy);

global_v1_xlim = [xmin_v1 xmax_v1];
global_v1_ylim = [ymin_v1 ymax_v1];
global_min_v1 = inf;
global_max_v1 = -inf;
%% -------------------------
% PASS 1: MAIN LOOP + STORE ANCHOR MAPS
% -------------------------
for ch_i = 1:numel(unique_channels)

    ch = unique_channels(ch_i);
    fprintf('\nChannel %d\n', ch);

    idx_ch = channels == ch;
    currents_ch = unique(currents(idx_ch));
    currents_ch = sort(currents_ch);

    if ~any(currents_ch == 0)
        fprintf('  Skipping channel %d (no 0 uA baseline)\n', ch);
        continue;
    end

    % baseline stack still computed because t-tests compare condition trials
    % against 0 uA trials, but maps are not baseline-subtracted again
    idx_base = idx_ch & currents == 0;
    dff_base = build_trial_stack(frame_idx(idx_base), img_dir, image_files, ...
        full_win, baseline_idx, response_idx, H, W);

    if isempty(dff_base)
        fprintf('  Skipping channel %d (baseline trial stack empty)\n', ch);
        continue;
    end

    current_summary = struct( ...
        'current_uA', {}, ...
        'n_trials', {}, ...
        'has_cluster', {}, ...
        'largest_cluster_size', {}, ...
        'fraction_V1_activated', {}, ...
        'mean_cluster_effect', {}, ...
        'sig_cluster_mask', {}, ...
        'mean_evoked_map', {} );

    threshold_uA = nan;

    nonzero_currents = currents_ch(currents_ch > 0);
    if isempty(nonzero_currents)
        anchor_current = 0;
    else
        anchor_current = max(nonzero_currents);
    end
    anchor_mean_map = [];

    for cur_i = 1:numel(currents_ch)

        cur = currents_ch(cur_i);
        if cur == 0
            continue;
        end

        idx_cur = idx_ch & currents == cur;
        dff_cur = build_trial_stack(frame_idx(idx_cur), img_dir, image_files, ...
            full_win, baseline_idx, response_idx, H, W);
        % ----- collect global min/max over ALL trials in V1 -----
        for t = 1:size(dff_cur,3)
            frame = dff_cur(:,:,t);
            vals = frame(V1_mask);
        
            if isempty(vals)
                continue;
            end
        
            global_min_v1 = min(global_min_v1, min(vals, [], 'omitnan'));
            global_max_v1 = max(global_max_v1, max(vals, [], 'omitnan'));
        end

        if isempty(dff_cur)
            fprintf('  %g uA -> no valid trials\n', cur);
            continue;
        end

        % SAME map as montage script
        mean_evoked_map = mean(dff_cur, 3, 'omitnan');

        if cur == anchor_current
            anchor_mean_map = mean_evoked_map;
        end

        % Use raw mean evoked map as effect map too
        effect_map = mean_evoked_map;

        % Pixelwise significance inside analysis mask
        p_map = nan(H,W);

        if use_analysis_mask_for_stats
            pix_idx = find(analysis_mask);
        else
            pix_idx = find(final_mask);
        end

        dff_cur_2d  = reshape(dff_cur,  [], size(dff_cur,3));
        dff_base_2d = reshape(dff_base, [], size(dff_base,3));

        for k = 1:numel(pix_idx)
            pix = pix_idx(k);

            x = dff_cur_2d(pix, :);
            b = dff_base_2d(pix, :);

            x = x(isfinite(x));
            b = b(isfinite(b));

            if numel(x) < 3 || numel(b) < 3
                continue;
            end

            [~, p] = ttest2(x, b);
            p_map(pix) = p;
        end

        if use_analysis_mask_for_stats
            sig_pixels = (p_map < alpha) & (effect_map > 0) & analysis_mask;
            denom_mask = analysis_mask;
        else
            sig_pixels = (p_map < alpha) & (effect_map > 0) & final_mask;
            denom_mask = final_mask;
        end

        % Cluster filtering
        CC = bwconncomp(sig_pixels, conn);
        sig_cluster_mask = false(H,W);

        cluster_sizes = zeros(CC.NumObjects,1);
        cluster_effects = nan(CC.NumObjects,1);

        for c_i = 1:CC.NumObjects
            pix_list = CC.PixelIdxList{c_i};
            cluster_sizes(c_i) = numel(pix_list);
            cluster_effects(c_i) = mean(effect_map(pix_list), 'omitnan');

            if numel(pix_list) >= min_cluster_size
                sig_cluster_mask(pix_list) = true;
            end
        end

        has_cluster = any(sig_cluster_mask(:));

        if isempty(cluster_sizes)
            largest_cluster_size = 0;
        else
            largest_cluster_size = max(cluster_sizes);
        end

        fraction_activated = sum(sig_cluster_mask(:)) / sum(denom_mask(:));
        mean_cluster_effect = mean(effect_map(sig_cluster_mask), 'omitnan');
        if ~has_cluster
            mean_cluster_effect = NaN;
        end

        fprintf('  %g uA -> cluster: %d | largest_cluster=%d | frac=%.4f\n', ...
            cur, has_cluster, largest_cluster_size, fraction_activated);

        current_summary(end+1).current_uA = cur;
        current_summary(end).n_trials = size(dff_cur,3);
        current_summary(end).has_cluster = has_cluster;
        current_summary(end).largest_cluster_size = largest_cluster_size;
        current_summary(end).fraction_V1_activated = fraction_activated;
        current_summary(end).mean_cluster_effect = mean_cluster_effect;
        current_summary(end).sig_cluster_mask = sig_cluster_mask;
        current_summary(end).mean_evoked_map = mean_evoked_map;

        if isnan(threshold_uA) && has_cluster
            threshold_uA = cur;
        end
    end

    if isempty(anchor_mean_map)
        if ~isempty(dff_base)
            anchor_mean_map = mean(dff_base, 3, 'omitnan');
        else
            anchor_mean_map = nan(H,W);
        end
    end

    % display masking option
    if mask_outside_for_display
        anchor_mean_map(~final_mask) = nan;
    end

    % peak search inside analysis mask
    search_map = anchor_mean_map;
    search_map(~analysis_mask) = nan;

    if all(isnan(search_map(:)))
        x_peak = NaN;
        y_peak = NaN;
        azi_val = NaN;
        alt_val = NaN;
    else
        [~, idx_max] = max(search_map(:));
        [y_peak, x_peak] = ind2sub(size(search_map), idx_max);
        azi_val = azi_stim(y_peak, x_peak);
        alt_val = alt_stim(y_peak, x_peak);
    end

    results(end+1).channel = ch;
    results(end).threshold_uA = threshold_uA;
    results(end).anchor_current_uA = anchor_current;
    results(end).azi = azi_val;
    results(end).alt = alt_val;
    results(end).peak_xy = [x_peak, y_peak];
    results(end).current_summary = current_summary;
    results(end).anchor_mean_map = anchor_mean_map;
end
fprintf('\nGLOBAL V1 VALUE RANGE (all trials):\n');
fprintf('  min = %.5f\n', global_min_v1);
fprintf('  max = %.5f\n', global_max_v1);
%% -------------------------
% COMPUTE SHARED CLIM IF REQUESTED
% -------------------------
if use_shared_clim
    if isempty(shared_clim)
        all_vals = [];

        for i = 1:numel(results)
            M = results(i).anchor_mean_map;
            if isempty(M)
                continue;
            end

            if mask_outside_for_display
                vals = M(final_mask & isfinite(M));
            else
                vals = M(isfinite(M));
            end

            all_vals = [all_vals; vals(:)];
        end

        if isempty(all_vals)
            clim_to_use = [];
        else
            clim_to_use = [min(all_vals), max(all_vals)];
        end
    else
        clim_to_use = shared_clim;
    end
else
    clim_to_use = [];
end

%% -------------------------
% PASS 2: PLOT PER-CHANNEL SUMMARY
% -------------------------
for i = 1:numel(results)

    ch = results(i).channel;
    anchor_current = results(i).anchor_current_uA;
    anchor_mean_map = results(i).anchor_mean_map;
    current_summary = results(i).current_summary;
    x_peak = results(i).peak_xy(1);
    y_peak = results(i).peak_xy(2);
    threshold_uA = results(i).threshold_uA;

    fig_ch = figure('Color','w', 'Name', sprintf('Channel %d summary', ch));

    subplot(1,2,1);
    ax_map = gca;
    
    % IMPORTANT:
    % anchor_mean_map must be assigned from:
    % anchor_mean_map = mean(dff_cur, 3, 'omitnan');
    % for the anchor current, with NO extra subtraction and NO masking for display
    
    imagesc(ax_map, anchor_mean_map);
    axis(ax_map, 'image');
    axis(ax_map, 'off');
    set(ax_map, 'YDir', 'normal');
    
    % same crop as montage script
    xlim(ax_map, global_v1_xlim);
    ylim(ax_map, global_v1_ylim);
    
    % same colormap / CLim
    colormap(ax_map, parula);
    if use_shared_clim && ~isempty(clim_to_use)
        caxis(ax_map, clim_to_use);
    elseif ~use_shared_clim
        % optional per-plot autoscale that matches montage logic
        vals = anchor_mean_map(:);
        vals = vals(isfinite(vals));
        if isempty(vals)
            clim_local = [-0.01 0.01];
        else
            q = quantile(vals, [0.02 0.98]);
            m = max(abs(q));
            if m == 0 || ~isfinite(m)
                m = 0.01;
            end
            clim_local = [-m m];
        end
        caxis(ax_map, clim_local);
    end
    
    hold(ax_map, 'on');
    
    % same overlays as montage script
    visboundaries(ax_map, V1_mask, 'Color', 'w', 'LineWidth', 1.2);
    visboundaries(ax_map, final_mask, 'Color', 'y', 'LineWidth', 1.0);
    
    % same peak marker if you want it
    if ~isnan(x_peak)
        plot(ax_map, x_peak, y_peak, 'wo', 'MarkerSize', 8, 'LineWidth', 2);
    end
    
    title(ax_map, sprintf('Mean map\nCh %d | %g uA', ch, anchor_current), ...
        'Interpreter', 'none');
    
    cb = colorbar(ax_map, 'eastoutside');
    cb.Label.String = '\DeltaF/F';
    if use_shared_clim && ~isempty(clim_to_use)
        cb.Limits = clim_to_use;
    end

    subplot(1,2,2);
    cur_vals = [current_summary.current_uA];
    cluster_vals = double([current_summary.has_cluster]);
    largest_vals = [current_summary.largest_cluster_size];

    yyaxis left;
    plot(cur_vals, cluster_vals, '-o', 'LineWidth', 1.5);
    ylabel('Has cluster');
    ylim([-0.05 1.05]);

    yyaxis right;
    plot(cur_vals, largest_vals, '-s', 'LineWidth', 1.5);
    ylabel('Largest cluster size');

    xlabel('Current (uA)');
    title(sprintf('Threshold = %g uA', threshold_uA));
    grid on;

    drawnow;
end

%% -------------------------
% SUMMARY SCATTER PLOT
% -------------------------
if isempty(results)
    warning('No channel results were generated.');
else
    azi_vals = [results.azi];
    alt_vals = [results.alt];
    thr_vals = [results.threshold_uA];

    fig_sum = figure('Color','w');
    scatter(azi_vals, alt_vals, 80, thr_vals, 'filled');
    colorbar;
    xlabel('Azimuth');
    ylabel('Altitude');
    title('Channel thresholds in visual space');
    grid on;
end

%% -------------------------
% SAVE
% -------------------------
save_dir = fullfile(img_dir, '..', 'analysis');
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

save_file = fullfile(save_dir, 'current_thresholding_V1_cluster_results_sharedclim_option.mat');
save(save_file, 'results', 'alpha', 'min_cluster_size', 'conn', ...
    'pre_sec', 'post_sec', 'Fs', 'response_sec', ...
    'analysis_mask', 'V1_mask', 'final_mask', ...
    'use_shared_clim', 'shared_clim', 'clim_to_use', ...
    'mask_outside_for_display', 'use_analysis_mask_for_stats', '-v7.3');

fprintf('\nSaved results to:\n  %s\n', save_file);

%% =========================
% LOCAL FUNCTION
% =========================
function dff_trials = build_trial_stack(frame_idx, img_dir, image_files, full_win, baseline_idx, response_idx, H, W)

n = numel(frame_idx);
if n == 0
    dff_trials = [];
    return;
end

dff_trials = nan(H,W,n);

for i = 1:n
    f = frame_idx(i);
    frames = f + full_win;

    stack = zeros(H,W,numel(frames));

    for k = 1:numel(frames)
        img = imread(fullfile(img_dir, image_files(frames(k)).name));
        stack(:,:,k) = double(img);
    end

    baseline = mean(stack(:,:,baseline_idx), 3);
    response = mean(stack(:,:,response_idx), 3);

    dff = (response - baseline) ./ baseline;
    dff_trials(:,:,i) = dff;
end
end
