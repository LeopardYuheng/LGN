%% plot_LGN_electrode_to_visual_field_map.m
close all; clc; clear;

% Select master results file
[fn, fp] = uigetfile('*.mat', 'Select MASTER_fixed_all_channels.mat');
if isequal(fn,0), error('No file selected.'); end

S = load(fullfile(fp, fn));
assert(isfield(S,'master'), 'Selected file must contain variable "master".');
master = S.master;

assert(isfield(master,'chan_res'), 'master.chan_res missing.');
chan_res = master.chan_res;

% Collect values
chan_id   = [];
azi_deg   = [];
alt_deg   = [];
thr_uA    = [];
anchor_uA = [];

for i = 1:numel(chan_res)
    if isempty(chan_res{i}), continue; end
    cres = chan_res{i};

    if ~isfield(cres,'retino') || isempty(cres.retino)
        continue;
    end

    x = cres.retino.activation_azi_weighted_deg;
    y = cres.retino.activation_alt_weighted_deg;

    if ~isfinite(x) || ~isfinite(y)
        continue;
    end

    chan_id(end+1,1)   = cres.chan; %#ok<AGROW>
    azi_deg(end+1,1)   = x; %#ok<AGROW>
    alt_deg(end+1,1)   = y; %#ok<AGROW>
    thr_uA(end+1,1)    = cres.fixed.threshold_uA; %#ok<AGROW>
    anchor_uA(end+1,1) = cres.anchor_current; %#ok<AGROW>
end

assert(~isempty(chan_id), 'No valid retinotopic channel results found.');

%% -------------------------
% FIGURE 1: colored by threshold current
% -------------------------
figure('Color','w');
hold on;

sc = scatter(azi_deg, alt_deg, 120, thr_uA, 'filled');
colormap jet;
cb = colorbar;
cb.Label.String = 'Threshold current (\muA)';

for i = 1:numel(chan_id)
    text(azi_deg(i), alt_deg(i), sprintf('  ch%d', chan_id(i)), ...
        'FontSize', 9, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
end

xlabel('Azimuth (deg)');
ylabel('Altitude (deg)');
title('LGN electrode \rightarrow visual field map');
axis equal;
grid on;
box on;

%% -------------------------
% Optional save
% -------------------------
saveas(gcf, fullfile(fp, 'LGN_electrode_to_visual_field_map_threshold.png'));


%%
%% plot_mean_evoked_maps_7uA.m
% Opens analysis results and plots mean evoked maps at 7 µA

close all; clc; clear;

%% -------------------------
% Select summary results file
% -------------------------

[fn, fp] = uigetfile('*.mat', ...
    'Select ALL_CONDITIONS_SUMMARY.mat');

if isequal(fn,0)
    error('No results file selected.');
end

S = load(fullfile(fp, fn));

assert(isfield(S,'results'), ...
    'Selected file must contain variable "results".');

results = S.results;

fprintf('Loaded %d result entries\n', numel(results));

%% -------------------------
% Select reference mask
% -------------------------

[mask_name, mask_path] = uigetfile('*.mat', ...
    'Select reference_mask.mat');

if isequal(mask_name,0)
    error('No mask selected.');
end

M = load(fullfile(mask_path, mask_name));

assert(isfield(M,'final_mask'), ...
    'Mask file must contain final_mask');

final_mask = M.final_mask;

%% -------------------------
% Parameters
% -------------------------

target_current = 7;

% Optional: fix color scaling
use_fixed_scale = true;
vmax = 0.02;

%% -------------------------
% Create figure
% -------------------------

figure('Color','w','Position',[100 100 1200 800]);
tiledlayout('flow');

n_plotted = 0;

%% -------------------------
% Loop through conditions
% -------------------------

for k = 1:numel(results)

    if ~isfield(results(k),'current_uA')
        continue
    end

    if results(k).current_uA ~= target_current
        continue
    end

    if ~isfield(results(k),'trial_maps')
        continue
    end

    trial_maps = results(k).trial_maps;

    if isempty(trial_maps)
        continue
    end

    % Mean evoked map
    mean_map = mean(trial_maps,3);

    % Apply mask
    mean_map(~final_mask) = NaN;

    % Plot
    nexttile

    if use_fixed_scale
        imagesc(mean_map, [-vmax vmax]);
    else
        imagesc(mean_map);
    end

    axis image off
    colormap parula
    colorbar

    % Channel label
    if isfield(results(k),'stim_channel')
        ch = results(k).stim_channel;
    else
        ch = NaN;
    end

    title(sprintf('Channel %d | %d µA', ch, target_current));

    n_plotted = n_plotted + 1;

end

sgtitle(sprintf('Mean Evoked Maps at %d µA', target_current));

fprintf('Plotted %d channels\n', n_plotted);

%% -------------------------
% Save figure
% -------------------------

save_path = fullfile(fp, ...
    sprintf('mean_evoked_maps_%duA.png', target_current));

saveas(gcf, save_path);

fprintf('Saved figure:\n%s\n', save_path);