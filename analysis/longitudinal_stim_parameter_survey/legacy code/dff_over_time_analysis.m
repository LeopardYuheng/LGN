%% dff_over_time_analysis.m
% Plot ROI ΔF/F(t) for all groups with GLOBAL Y-LIMS

close all; clc; clear; fclose('all');

%% =========================
% SELECT INPUTS
% =========================

[fn, fp] = uigetfile('*.mat', 'Select widefield_session_results.mat');
R = load(fullfile(fp, fn));
out = R.out;

img_dir = uigetdir(pwd, 'Select TIFF folder');

[ses_name, ses_path] = uigetfile('*.mat', 'Select session_sync*.mat');
S = load(fullfile(ses_path, ses_name));
session = S.session;

[csv_name, csv_path] = uigetfile('*.csv', 'Select CSV mapping');
T = readtable(fullfile(csv_path, csv_name));

save_root = uigetdir(pwd, 'Select OUTPUT folder');

roi_radius = input('Enter ROI radius (pixels): ');

%% =========================
% PARAMETERS
% =========================

before_time = out.before_time;
after_time  = out.after_time;
resp_win    = out.resp_win;

frame_times = session.frames.time_s(:);
Freq = 1 / median(diff(frame_times));

preFrames  = round(before_time * Freq);
postFrames = round(after_time * Freq);
L = preFrames + postFrames + 1;

t = ((0:L-1)/Freq) - before_time;

resp_idx = find(t >= resp_win(1) & t <= resp_win(2));
base_idx = 1:preFrames;

%% =========================
% LOAD TIFF FILES
% =========================

files = dir(fullfile(img_dir, '*.tif'));
nums = zeros(numel(files),1);

for i=1:numel(files)
    tok = regexp(files(i).name, '(\d+)\.tif$', 'tokens');
    nums(i) = str2double(tok{1});
end

[~, ord] = sort(nums);
files = files(ord);

%% =========================
% MAP CSV → TRIALS
% =========================

trial_idx = T.trial_index;
stim_chan = T.stim_channel;
current   = T.current_uA;

N = numel(out.trial_channel);

trial_channel = nan(N,1);
trial_current = nan(N,1);

trial_channel(trial_idx) = stim_chan;
trial_current(trial_idx) = current;

%% =========================
% BUILD GROUPS
% =========================

key = strings(N,1);

for i=1:N
    if isnan(trial_channel(i))
        key(i) = "UNMAPPED";
    else
        key(i) = sprintf("ch%03d_curr%.4g", trial_channel(i), trial_current(i));
    end
end

valid = key ~= "UNMAPPED";

key = key(valid);
trial_onset = out.trial_onset_frame_idx(valid);
trial_channel = trial_channel(valid);
trial_current = trial_current(valid);

[unique_keys,~,gidx] = unique(key);

n_groups = numel(unique_keys);

fprintf('Found %d mapped groups.\n', n_groups);

%% =========================
% ROI FROM MEAN MAP
% =========================

mean_map = out.mean_evoked_map;
[~, ind] = max(mean_map(:));
[cy, cx] = ind2sub(size(mean_map), ind);

[H,W] = size(mean_map);
[xx,yy] = meshgrid(1:W,1:H);

roi_mask = (xx-cx).^2 + (yy-cy).^2 <= roi_radius^2;

%% =========================
% FUNCTION: ROI TRACE
% =========================

function dff = trial_roi_dff(f0, roi_mask, files, img_dir, preFrames, postFrames, base_idx)

    L = preFrames + postFrames + 1;
    dff = nan(L,1);

    f_start = f0 - preFrames;
    f_end   = f0 + postFrames;

    if f_start < 1 || f_end > numel(files)
        return;
    end

    movie = zeros([size(roi_mask), L],'single');

    kk = 0;
    for f = f_start:f_end
        kk = kk + 1;
        img = imread(fullfile(img_dir, files(f).name));
        movie(:,:,kk) = single(img);
    end

    roi_pix = roi_mask(:);

    trace = squeeze(mean(movie(repmat(roi_pix,1,1,L)), 'omitnan'));

    F0 = mean(trace(base_idx));
    dff = (trace - F0) / F0;
end

%% =========================
% COMPUTE ALL TRACES
% =========================

group_mean = cell(n_groups,1);
group_trials = cell(n_groups,1);

fprintf('Computing ROI traces...\n');

for g = 1:n_groups

    idx = find(gidx==g);
    traces = nan(L, numel(idx));

    for k = 1:numel(idx)
        f0 = trial_onset(idx(k));
        traces(:,k) = trial_roi_dff(f0, roi_mask, files, img_dir, preFrames, postFrames, base_idx);
    end

    group_trials{g} = traces;
    group_mean{g} = mean(traces,2,'omitnan');

end

%% =========================
% GLOBAL Y LIMITS
% =========================

all_vals = [];

for g=1:n_groups
    all_vals = [all_vals; group_trials{g}(:)];
end

all_vals = all_vals(isfinite(all_vals));

ymin = prctile(all_vals,2);
ymax = prctile(all_vals,98);

pad = 0.05*(ymax-ymin);
ylims = [ymin-pad ymax+pad];

fprintf('Global y-limits: [%.4f %.4f]\n', ylims);

%% =========================
% SAVE PER GROUP
% =========================

for g = 1:n_groups

    kname = unique_keys(g);
    idx = find(gidx==g);

    gdir = fullfile(save_root, char(kname));
    if ~exist(gdir,'dir'), mkdir(gdir); end

    traces = group_trials{g};

    %% mean overlay
    fig = figure('Visible','off'); hold on;

    plot(t, group_mean{g}, 'LineWidth',2);

    xline(0,'--k');
    xline(resp_win(1),':');
    xline(resp_win(2),':');

    ylim(ylims);

    title(sprintf('%s (n=%d)', kname, size(traces,2)));

    exportgraphics(fig, fullfile(gdir,'mean_trace.png'));
    close(fig);

    %% individual trials
    for k=1:size(traces,2)

        fig = figure('Visible','off');
        plot(t, traces(:,k),'LineWidth',1.5);

        xline(0,'--k');
        xline(resp_win(1),':');
        xline(resp_win(2),':');

        ylim(ylims);

        title(sprintf('%s | trial %d', kname, idx(k)));

        exportgraphics(fig, fullfile(gdir, sprintf('trial_%03d.png', idx(k))));
        close(fig);
    end

end

%% =========================
% GROUP BY CURRENT (channels overlay)
% =========================

currents = unique(trial_current);

for c = currents'

    fig = figure; hold on;

    for g = 1:n_groups
        if trial_current(find(gidx==g,1)) == c
            plot(t, group_mean{g}, 'LineWidth',2);
        end
    end

    xline(0,'--k');
    xline(resp_win(1),':');
    xline(resp_win(2),':');

    ylim(ylims);

    title(sprintf('All channels | current %.2f', c));

    exportgraphics(fig, fullfile(save_root, sprintf('current_%.2f_overlay.png',c)));
    close(fig);
end

%% =========================
% GROUP BY CHANNEL (currents overlay)
% =========================

channels = unique(trial_channel);

for ch = channels'

    fig = figure; hold on;

    for g = 1:n_groups
        if trial_channel(find(gidx==g,1)) == ch
            plot(t, group_mean{g}, 'LineWidth',2);
        end
    end

    xline(0,'--k');
    xline(resp_win(1),':');
    xline(resp_win(2),':');

    ylim(ylims);

    title(sprintf('All currents | ch %d', ch));

    exportgraphics(fig, fullfile(save_root, sprintf('channel_%03d_overlay.png',ch)));
    close(fig);
end

fprintf('DONE\n');
