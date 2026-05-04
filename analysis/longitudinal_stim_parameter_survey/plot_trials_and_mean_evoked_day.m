%% plot_individual_trials_and_mean_maps_from_container.m
close all; clc; clear; fclose('all');
set(0, 'DefaultFigureVisible', 'off');

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

assert(exist(day_setup_file, 'file') == 2, 'Resolved day_setup_file does not exist.');
assert(exist(img_dir, 'dir') == 7, 'Resolved img_dir does not exist.');

%% -------------------------
% LOAD DAY SETUP
% -------------------------
D = load(day_setup_file);
assert(isfield(D,'day_setup'), 'day_setup missing from file.');
day_setup = D.day_setup;

final_mask = logical(day_setup.reference_mask.final_mask);
V1_mask    = logical(day_setup.retino_align.V1_mask_stim);
analysis_mask = final_mask & V1_mask;

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
% CAMERA RATE / WINDOWS
% -------------------------
if isfield(day_pointer.meta, 'camera_rate_hz')
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq')
    Fs = double(day_pointer.meta.Freq);
else
    Fs = 10;
end

pre_sec  = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames  = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);

full_win = -pre_frames:post_frames;

baseline_sec = [-1 0];
response_sec = [0.4 0.6];

baseline_idx = full_win >= baseline_sec(1)*Fs & full_win < baseline_sec(2)*Fs;
response_idx = full_win > response_sec(1)*Fs & full_win <= response_sec(2)*Fs;

assert(any(baseline_idx), 'No baseline frames selected.');
assert(any(response_idx), 'No response frames selected.');

fprintf('Camera rate: %.3f Hz\n', Fs);
fprintf('Baseline window: [%.2f %.2f] sec\n', baseline_sec(1), baseline_sec(2));
fprintf('Response window: [%.2f %.2f] sec\n', response_sec(1), response_sec(2));

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
% OUTPUT FOLDER
% -------------------------
out_dir = fullfile(img_dir, '..', 'analysis', 'trial_and_mean_evoked_maps');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% -------------------------
% SETTINGS
% -------------------------
mask_outside = false;                 % full map shown
overlay_V1_boundary = true;
overlay_final_mask_boundary = true;

max_cols = 5;
save_png = true;
save_mat = true;

% One global dF/F scale for all plots
use_global_clim = true;
global_clim = [-0.06 0.06];

% Mean montage pages
save_mean_montage_pages = true;
mean_montage_rows = 5;
mean_montage_cols = 7;

unique_channels = unique(channels);
all_currents_global = unique(currents);
all_currents_global = sort(all_currents_global(:))';

% Storage for montage export
mean_map_store = struct();

%% -------------------------
% GLOBAL V1 BOUNDS
% show the whole V1 in every plot
%% -------------------------
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

%% -------------------------
% MAIN LOOP
% individual trials + mean map per channel/current
%% -------------------------
for ch_i = 1:numel(unique_channels)

    ch = unique_channels(ch_i);
    idx_ch = channels == ch;
    currents_ch = unique(currents(idx_ch));
    currents_ch = sort(currents_ch);

    xlims_ch = global_v1_xlim;
    ylims_ch = global_v1_ylim;

    for cur_i = 1:numel(currents_ch)

        cur = currents_ch(cur_i);
        idx_cur = idx_ch & currents == cur;

        these_frames = frame_idx(idx_cur);
        these_trials = trial_index(idx_cur);

        if isempty(these_frames)
            continue;
        end

        fprintf('\nChannel %d | %g uA | n=%d\n', ch, cur, numel(these_frames));

        dff_trials = build_trial_stack(these_frames, img_dir, image_files, ...
            full_win, baseline_idx, response_idx);

        if isempty(dff_trials)
            fprintf('  Skipping (empty stack)\n');
            continue;
        end

        if mask_outside
            for t = 1:size(dff_trials,3)
                tmp = dff_trials(:,:,t);
                tmp(~analysis_mask) = NaN;
                dff_trials(:,:,t) = tmp;
            end
        end

        mean_map = mean(dff_trials, 3, 'omitnan');

        % Store mean map for montage
        field_ch = sprintf('ch_%d', ch);
        field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));
        if ~isfield(mean_map_store, field_ch)
            mean_map_store.(field_ch) = struct();
        end
        mean_map_store.(field_ch).(field_cur) = mean_map;

        % Determine figure layout
        n_trials = size(dff_trials,3);
        n_panels = n_trials + 1;
        ncols = min(max_cols, ceil(sqrt(n_panels)));
        nrows = ceil(n_panels / ncols);

        if use_global_clim
            clim = global_clim;
        else
            all_vals = dff_trials(:);
            all_vals = all_vals(isfinite(all_vals));
            mean_vals = mean_map(:);
            mean_vals = mean_vals(isfinite(mean_vals));
            all_vals = [all_vals; mean_vals];

            if isempty(all_vals)
                clim = [-0.01 0.01];
            else
                q = quantile(all_vals, [0.02 0.98]);
                m = max(abs(q));
                if m == 0 || ~isfinite(m)
                    m = 0.01;
                end
                clim = [-m m];
            end
        end

        fig = figure('Color','w', ...
            'Name', sprintf('Ch%d_%guA', ch, cur), ...
            'Position', [50 50 350*ncols 300*nrows], ...
            'Visible','off');

        colormap(parula);

        % Individual trials
        for t = 1:n_trials
            ax_trial = subplot(nrows, ncols, t);
            imagesc(ax_trial, dff_trials(:,:,t));
            axis(ax_trial, 'image');
            axis(ax_trial, 'off');
            set(ax_trial, 'YDir', 'normal');
            xlim(ax_trial, xlims_ch);
            ylim(ax_trial, ylims_ch);
            colormap(ax_trial, parula);
            caxis(ax_trial, clim);
            hold(ax_trial, 'on');
            

            if overlay_V1_boundary
                visboundaries(V1_mask, 'Color', 'w', 'LineWidth', 0.8);
            end
            if overlay_final_mask_boundary
                visboundaries(final_mask, 'Color', 'y', 'LineWidth', 0.8);
            end

            if ~isnan(these_trials(t))
                title(sprintf('Trial %d', these_trials(t)), 'Interpreter', 'none');
            else
                title(sprintf('Trial %d', t), 'Interpreter', 'none');
            end
        end

        % Mean map
        % Mean map
        ax_mean = subplot(nrows, ncols, n_trials + 1);
        imagesc(ax_mean, mean_map);
        axis(ax_mean, 'image');
        axis(ax_mean, 'off');
        set(ax_mean, 'YDir', 'normal');
        xlim(ax_mean, xlims_ch);
        ylim(ax_mean, ylims_ch);
        colormap(ax_mean, parula);
        caxis(ax_mean, clim);
        hold(ax_mean, 'on');
        
        if overlay_V1_boundary
            visboundaries(ax_mean, V1_mask, 'Color', 'w', 'LineWidth', 1.2);
        end
        if overlay_final_mask_boundary
            visboundaries(ax_mean, final_mask, 'Color', 'y', 'LineWidth', 1.0);
        end
        
        title(ax_mean, sprintf('Mean map\nCh %d | %g uA | n=%d', ch, cur, n_trials), ...
            'Interpreter', 'none');
        
        cb = colorbar(ax_mean, 'eastoutside');
        cb.Label.String = '\DeltaF/F';
        cb.Limits = clim;

        sgtitle(sprintf('Evoked maps | Channel %d | %g uA', ch, cur), ...
            'Interpreter', 'none');

        if save_png
            exportgraphics(fig, ...
                fullfile(out_dir, sprintf('ch_%d_current_%g_uA_trials_and_mean.png', ch, cur)), ...
                'Resolution', 200);
        end

        if save_mat
            save(fullfile(out_dir, sprintf('ch_%d_current_%g_uA_trials_and_mean.mat', ch, cur)), ...
                'ch', 'cur', 'these_frames', 'these_trials', 'dff_trials', 'mean_map', ...
                'baseline_sec', 'response_sec', 'Fs', 'analysis_mask', ...
                'global_v1_xlim', 'global_v1_ylim', 'global_clim', '-v7.3');
        end

        close(fig);
    end
end

%% -------------------------
% SAVE MONTAGE PAGES OF ALL MEAN EVOKED MAPS
% 7 columns = currents
% 5 rows = channels
%% -------------------------
if save_mean_montage_pages

    montage_dir = fullfile(out_dir, 'mean_map_montage_pages');
    if ~exist(montage_dir, 'dir')
        mkdir(montage_dir);
    end

    channel_list = unique(channels);
    channel_list = sort(channel_list(:))';

    currents_for_cols = all_currents_global;
    n_cols = mean_montage_cols;

    if numel(currents_for_cols) > n_cols
        warning('More than %d currents found. Only first %d sorted currents will be shown.', ...
            n_cols, n_cols);
        currents_for_cols = currents_for_cols(1:n_cols);
    end

    n_rows = mean_montage_rows;
    n_channels_total = numel(channel_list);
    n_pages = ceil(n_channels_total / n_rows);

    for page_i = 1:n_pages

        ch_start = (page_i - 1) * n_rows + 1;
        ch_end = min(page_i * n_rows, n_channels_total);
        page_channels = channel_list(ch_start:ch_end);

        fig_page = figure( ...
            'Color', 'w', ...
            'Visible', 'off', ...
            'Name', sprintf('MeanMapMontage_Page_%d', page_i), ...
            'Position', [50 50 340*n_cols 280*n_rows]);

        tl = tiledlayout(n_rows, n_cols, 'Padding', 'compact', 'TileSpacing', 'compact');
        colormap(parula);
        for r = 1:n_rows
            for c = 1:n_cols

                ax = nexttile;

                if r > numel(page_channels)
                    axis(ax, 'off');
                    continue;
                end

                ch = page_channels(r);

                if c > numel(currents_for_cols)
                    axis(ax, 'off');
                    continue;
                end

                cur = currents_for_cols(c);

                field_ch = sprintf('ch_%d', ch);
                field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));

                if isfield(mean_map_store, field_ch) && isfield(mean_map_store.(field_ch), field_cur)
                    mean_map = mean_map_store.(field_ch).(field_cur);

                    imagesc(ax, mean_map);
                    axis(ax, 'image');
                    axis(ax, 'off');
                    set(ax, 'YDir', 'normal');
                    xlim(ax, global_v1_xlim);
                    ylim(ax, global_v1_ylim);
                    caxis(ax, global_clim);
                    hold(ax, 'on');

                    if overlay_V1_boundary
                        visboundaries(ax, V1_mask, 'Color', 'w', 'LineWidth', 0.8);
                    end
                    if overlay_final_mask_boundary
                        visboundaries(ax, final_mask, 'Color', 'y', 'LineWidth', 0.8);
                    end
                else
                    axis(ax, 'off');
                end

                if r == 1
                    title(ax, sprintf('%g uA', cur), 'Interpreter', 'none', 'FontWeight', 'bold');
                end

                if c == 1
                    text(ax, 0.02, 0.95, sprintf('Ch %d', ch), ...
                        'Units', 'normalized', ...
                        'Color', 'w', ...
                        'FontWeight', 'bold', ...
                        'FontSize', 10, ...
                        'HorizontalAlignment', 'left', ...
                        'VerticalAlignment', 'top', ...
                        'BackgroundColor', 'k', ...
                        'Margin', 1);
                end
            end
        end

        sgtitle(sprintf('Mean evoked maps | Page %d of %d', page_i, n_pages), ...
            'Interpreter', 'none');

        cb = colorbar;
        cb.Label.String = '\DeltaF/F';
        cb.Limits = global_clim;

        exportgraphics(fig_page, ...
            fullfile(montage_dir, sprintf('mean_evoked_map_montage_page_%02d.png', page_i)), ...
            'Resolution', 200);

        close(fig_page);
    end
end

fprintf('\nSaved figures to:\n  %s\n', out_dir);
set(0, 'DefaultFigureVisible', 'on');

%% =========================
% LOCAL FUNCTIONS
% =========================
function dff_trials = build_trial_stack(frame_idx, img_dir, image_files, full_win, baseline_idx, response_idx)

n = numel(frame_idx);
if n == 0
    dff_trials = [];
    return;
end

img0 = double(imread(fullfile(img_dir, image_files(1).name)));
[H,W] = size(img0);

dff_trials = nan(H,W,n);

for i = 1:n
    f = frame_idx(i);
    frames = f + full_win;

    stack = zeros(H,W,numel(frames));

    for k = 1:numel(frames)
        stack(:,:,k) = double(imread(fullfile(img_dir, image_files(frames(k)).name)));
    end

    baseline = mean(stack(:,:,baseline_idx), 3);
    response = mean(stack(:,:,response_idx), 3);

    dff = (response - baseline) ./ baseline;
    dff_trials(:,:,i) = dff;
end
end

function cmap = bluewhitered(m)
    if nargin < 1
        m = 256;
    end

    bottom = [0 0.4470 0.7410];
    middle = [1 1 1];
    top    = [0.8500 0.3250 0.0980];

    x = [0 0.5 1];
    xi = linspace(0,1,m);

    cmap = interp1(x, [bottom; middle; top], xi);
end
