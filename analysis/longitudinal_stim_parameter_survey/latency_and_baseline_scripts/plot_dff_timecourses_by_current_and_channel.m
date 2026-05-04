%% plot_dff_timecourses_by_current_and_channel.m
% Build trial-wise dF/F time courses from a day_pointer and plot:
%   1) one figure per current level with channels overlaid in different colors
%   2) one figure per channel with one subplot per current showing mean +/- std
%
% Spatial averaging mode:
%   - If a threshold-results file is provided and contains channel masks,
%     use each channel's threshold_cluster_mask
%   - Otherwise fall back to the shared analysis mask = final_mask & V1_mask

close all; clc; clear; fclose('all');

%% -------------------------
% USER OPTIONS
% -------------------------
Fs_default = 10;
mask_mode = 'threshold_or_analysis_mask';  % threshold_or_analysis_mask | analysis_mask_only
save_png = true;
line_width = 2;
trace_alpha = 0.20;

%% -------------------------
% LOAD DAY POINTER
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
% OPTIONAL THRESHOLD RESULTS
% -------------------------
use_threshold_masks = false;
threshold_results = struct([]);
[thr_name, thr_path] = uigetfile('*.mat', ...
    'Optional: select current thresholding results file (Cancel to skip)');
if ~isequal(thr_name,0)
    T = load(fullfile(thr_path, thr_name));
    if isfield(T,'results')
        threshold_results = T.results;
        use_threshold_masks = true;
    else
        warning('Selected file does not contain variable "results". Continuing without threshold masks.');
    end
end

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
assert(nnz(analysis_mask) > 0, 'analysis_mask is empty.');

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
% CAMERA RATE / WINDOWS
% -------------------------
if isfield(day_pointer.meta, 'camera_rate_hz')
    Fs = double(day_pointer.meta.camera_rate_hz);
elseif isfield(day_pointer.meta, 'Freq')
    Fs = double(day_pointer.meta.Freq);
else
    Fs = Fs_default;
end

pre_sec  = double(day_pointer.cfg.pre_sec);
post_sec = double(day_pointer.cfg.post_sec);

pre_frames  = round(pre_sec * Fs);
post_frames = round(post_sec * Fs);
full_win = -pre_frames:post_frames;
t_s = full_win(:) / Fs;

baseline_idx = full_win < 0;
assert(any(baseline_idx), 'No baseline frames selected.');

%% -------------------------
% RECONSTRUCT PER-TRIAL VECTORS
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

frame_idx   = frame_idx(valid);
channels    = channels(valid);
currents    = currents(valid);
trial_index = trial_index(valid);

fprintf('Keeping %d / %d trials after frame validity filter.\n', ...
    sum(valid), numel(valid));

channel_list = unique(channels);
channel_list = sort(channel_list(:));

current_list = unique(currents);
current_list = sort(current_list(:));

fprintf('Found %d channels and %d current levels.\n', numel(channel_list), numel(current_list));

%% -------------------------
% OUTPUT FOLDER
% -------------------------
out_dir = fullfile(img_dir, '..', 'analysis', 'dff_timecourse_by_current_and_channel');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% -------------------------
% BUILD CHANNEL MASKS
% -------------------------
channel_masks = containers.Map('KeyType','double','ValueType','any');
for i = 1:numel(channel_list)
    ch = channel_list(i);
    mask_ch = [];

    if use_threshold_masks && strcmp(mask_mode, 'threshold_or_analysis_mask')
        idx_match = find(arrayfun(@(r) isfield(r,'channel') && isequal(r.channel, ch), threshold_results), 1);
        if ~isempty(idx_match) && isfield(threshold_results(idx_match), 'threshold_cluster_mask')
            mask_tmp = logical(threshold_results(idx_match).threshold_cluster_mask);
            if isequal(size(mask_tmp), [H W]) && any(mask_tmp(:))
                mask_ch = mask_tmp;
            end
        end
    end

    if isempty(mask_ch)
        mask_ch = analysis_mask;
    end

    channel_masks(ch) = mask_ch;
end

%% -------------------------
% COMPUTE TIME COURSES
% -------------------------
trace_store = struct();
for ch_i = 1:numel(channel_list)
    ch = channel_list(ch_i);
    mask_ch = channel_masks(ch);
    pix_idx = find(mask_ch);

    for cur_i = 1:numel(current_list)
        cur = current_list(cur_i);
        idx = channels == ch & currents == cur;
        these_frames = frame_idx(idx);
        these_trial_index = trial_index(idx);

        traces = build_trial_trace_stack(these_frames, img_dir, image_files, ...
            full_win, baseline_idx, pix_idx);

        field_ch = sprintf('ch_%d', ch);
        field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));

        if ~isfield(trace_store, field_ch)
            trace_store.(field_ch) = struct();
        end

        trace_store.(field_ch).(field_cur).traces = traces;
        trace_store.(field_ch).(field_cur).trial_index = these_trial_index;
        trace_store.(field_ch).(field_cur).n_trials = size(traces,1);

        if isempty(traces)
            trace_store.(field_ch).(field_cur).mean_trace = nan(size(t_s'));
            trace_store.(field_ch).(field_cur).std_trace  = nan(size(t_s'));
        else
            trace_store.(field_ch).(field_cur).mean_trace = mean(traces, 1, 'omitnan');
            trace_store.(field_ch).(field_cur).std_trace  = std(traces, 0, 1, 'omitnan');
        end
    end
end

%% -------------------------
% SHARED Y-LIMITS FOR ALL TIME-COURSE PLOTS
% -------------------------
all_trace_vals = [];
for ch_i = 1:numel(channel_list)
    ch = channel_list(ch_i);
    field_ch = sprintf('ch_%d', ch);

    for cur_i = 1:numel(current_list)
        cur = current_list(cur_i);
        field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));

        mean_trace = trace_store.(field_ch).(field_cur).mean_trace;
        std_trace  = trace_store.(field_ch).(field_cur).std_trace;

        if any(isfinite(mean_trace))
            all_trace_vals = [all_trace_vals; mean_trace(:) - std_trace(:); mean_trace(:) + std_trace(:)]; %#ok<AGROW>
        end
    end
end

all_trace_vals = all_trace_vals(isfinite(all_trace_vals));
if isempty(all_trace_vals)
    global_trace_ylim = [-0.05 0.05];
else
    y_min = min(all_trace_vals);
    y_max = max(all_trace_vals);
    if y_min == y_max
        pad = max(0.01, abs(y_min) * 0.1 + 0.01);
    else
        pad = 0.05 * (y_max - y_min);
    end
    global_trace_ylim = [y_min - pad, y_max + pad];
end

%% -------------------------
% PLOT 1: ONE FIGURE PER CURRENT, CHANNELS OVERLAID
% -------------------------
cmap = lines(max(numel(channel_list),1));

for cur_i = 1:numel(current_list)
    cur = current_list(cur_i);
    field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));

    fig_cur = figure('Color','w', 'Name', sprintf('Current %g uA', cur));
    ax = axes(fig_cur);
    hold(ax, 'on');

    for ch_i = 1:numel(channel_list)
        ch = channel_list(ch_i);
        field_ch = sprintf('ch_%d', ch);
        mean_trace = trace_store.(field_ch).(field_cur).mean_trace;

        if all(~isfinite(mean_trace))
            continue;
        end

        plot(ax, t_s, mean_trace, 'LineWidth', line_width, ...
            'Color', cmap(ch_i,:), 'DisplayName', sprintf('Ch %d', ch));
    end

    xline(ax, 0, 'k--', 'LineWidth', 1);
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Mean dF/F');
    title(ax, sprintf('Average dF/F over time | %g uA', cur));
    ylim(ax, global_trace_ylim);
    legend(ax, 'Location', 'bestoutside');
    grid(ax, 'on');

    if save_png
        saveas(fig_cur, fullfile(out_dir, sprintf('timecourse_by_current_%g_uA.png', cur)));
    end
end

%% -------------------------
% PLOT 2: ONE FIGURE PER CHANNEL, ALL CURRENTS WITH STD SHADING
% -------------------------
for ch_i = 1:numel(channel_list)
    ch = channel_list(ch_i);
    field_ch = sprintf('ch_%d', ch);

    fig_ch = figure('Color','w', 'Name', sprintf('Channel %d time courses', ch));
    tiledlayout(numel(current_list), 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    for cur_i = 1:numel(current_list)
        cur = current_list(cur_i);
        field_cur = matlab.lang.makeValidName(sprintf('uA_%g', cur));

        mean_trace = trace_store.(field_ch).(field_cur).mean_trace;
        std_trace  = trace_store.(field_ch).(field_cur).std_trace;
        n_trials   = trace_store.(field_ch).(field_cur).n_trials;

        ax = nexttile;
        hold(ax, 'on');

        if any(isfinite(mean_trace))
            fill_x = [t_s; flipud(t_s)];
            fill_y = [mean_trace(:) - std_trace(:); flipud(mean_trace(:) + std_trace(:))];
            patch(ax, fill_x, fill_y, cmap(ch_i,:), ...
                'FaceAlpha', trace_alpha, 'EdgeColor', 'none');

            plot(ax, t_s, mean_trace, 'LineWidth', line_width, 'Color', cmap(ch_i,:));
        end

        xline(ax, 0, 'k--', 'LineWidth', 1);
        ylabel(ax, 'dF/F');
        title(ax, sprintf('Ch %d | %g uA | n=%d', ch, cur, n_trials), ...
            'Interpreter', 'none');
        ylim(ax, global_trace_ylim);
        grid(ax, 'on');

        if cur_i == numel(current_list)
            xlabel(ax, 'Time (s)');
        else
            set(ax, 'XTickLabel', []);
        end
    end

    if save_png
        saveas(fig_ch, fullfile(out_dir, sprintf('timecourse_by_channel_%d.png', ch)));
    end
end

%% -------------------------
% SAVE SUMMARY DATA
% -------------------------
save(fullfile(out_dir, 'dff_timecourse_summary.mat'), ...
    'trace_store', 'channel_list', 'current_list', 't_s', ...
    'analysis_mask', 'channel_masks', 'Fs', 'pre_sec', 'post_sec', '-v7.3');

fprintf('\nSaved time-course figures and summary data to:\n  %s\n', out_dir);

%% =========================
% LOCAL FUNCTION
% =========================
function traces = build_trial_trace_stack(frame_idx, img_dir, image_files, full_win, baseline_idx, pix_idx)

n_trials = numel(frame_idx);
n_t = numel(full_win);

if n_trials == 0
    traces = [];
    return;
end

traces = nan(n_trials, n_t);

for i = 1:n_trials
    f = frame_idx(i);
    frames = f + full_win;

    stack = nan(numel(pix_idx), n_t);
    for k = 1:n_t
        img = double(imread(fullfile(img_dir, image_files(frames(k)).name)));
        stack(:,k) = img(pix_idx);
    end

    baseline = mean(stack(:,baseline_idx), 2, 'omitnan');
    valid_baseline = isfinite(baseline) & baseline ~= 0;

    dff_stack = nan(size(stack));
    dff_stack(valid_baseline,:) = (stack(valid_baseline,:) - baseline(valid_baseline)) ./ baseline(valid_baseline);

    traces(i,:) = mean(dff_stack, 1, 'omitnan');
end
end
