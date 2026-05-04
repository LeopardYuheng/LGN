%% compare_channels_using_frmod.m
% Compare stimulation channels based on unit firing-rate responses from
% FRmod_2Session_MatchedUnit_Result.mat (MATLAB v7.3/HDF5).
%
% Outputs (in out_dir):
%   - FR_per_unit_per_channel_Session1.csv
%   - FR_per_unit_per_channel_Session2.csv
%   - FR_per_unit_per_channel_combined.csv
%   - spearman_corr_channels_Session1.csv
%   - spearman_corr_channels_Session2.csv
%   - spearman_corr_channels_combined.csv
%   - spearman_corr_channels_Session1.png
%   - spearman_corr_channels_Session2.png
%   - spearman_corr_channels_combined.png

close all; clc;

%% -------------------------
% USER OPTIONS
% -------------------------
mat_file = "";
out_dir = "";

%% -------------------------
% RESOLVE INPUT/OUTPUT
% -------------------------
if strlength(mat_file) == 0
    script_dir = fileparts(mfilename('fullpath'));
    default_mat = fullfile(script_dir, 'FRmod_2Session_MatchedUnit_Result.mat');
    if isfile(default_mat)
        mat_file = string(default_mat);
    else
        [fn, fp] = uigetfile('*.mat', 'Select FRmod_2Session_MatchedUnit_Result.mat');
        if isequal(fn, 0)
            error('No MAT file selected.');
        end
        mat_file = string(fullfile(fp, fn));
    end
end

if strlength(out_dir) == 0
    out_dir = string(fileparts(mat_file));
end

if ~isfolder(out_dir)
    mkdir(out_dir);
end

assert(isfile(mat_file), 'MAT file not found: %s', mat_file);

sessions = ["Session1", "Session2"];
per_session = struct();
corr_session = struct();
channels_session = struct();
session_data = struct();

% Plot/display channels in shank-near order for the similarity matrices.
display_channel_order = [16 50 32 18 84 86 96 122 114 87];

%% -------------------------
% PER-SESSION ANALYSIS
% -------------------------
for s = 1:numel(sessions)
    session = sessions(s);

    stim_mean_path = sprintf('/Result/%s/stim_mean_mat', session);
    stim_channel_path = sprintf('/Result/%s/stim_channel', session);
    current_path = sprintf('/Result/%s/current', session);

    stim_mean = double(h5read(mat_file, stim_mean_path)); % units x trials
    stim_channel = double(h5read(mat_file, stim_channel_path));
    stim_channel = stim_channel(:)';
    current_uA = double(h5read(mat_file, current_path));
    current_uA = current_uA(:)';

    % MATLAB h5read may return dimensions flipped relative to Python.
    if size(stim_mean, 1) == numel(stim_channel) && size(stim_mean, 2) ~= numel(stim_channel)
        stim_mean = stim_mean';
    end

    [n_units, n_trials] = size(stim_mean);
    assert(numel(stim_channel) == n_trials, ...
        '%s: stim_channel length (%d) does not match stim_mean trials (%d).', ...
        session, numel(stim_channel), n_trials);
    assert(numel(current_uA) == n_trials, ...
        '%s: current length (%d) does not match stim_mean trials (%d).', ...
        session, numel(current_uA), n_trials);

    [per_unit_chan, chan_vals] = compute_per_unit_channel_mean(stim_mean, stim_channel);
    [corr_mat, shared_n] = pairwise_spearman(per_unit_chan);
    [per_unit_chan, chan_vals, corr_mat, shared_n] = apply_channel_order(per_unit_chan, chan_vals, corr_mat, shared_n, display_channel_order);

    per_session.(session) = per_unit_chan;
    corr_session.(session) = corr_mat;
    channels_session.(session) = chan_vals;
    session_data.(session).stim_mean = stim_mean;
    session_data.(session).stim_channel = stim_channel;
    session_data.(session).current_uA = current_uA;

    per_unit_csv = fullfile(out_dir, sprintf('FR_per_unit_per_channel_%s.csv', session));
    corr_csv = fullfile(out_dir, sprintf('spearman_corr_channels_%s.csv', session));
    corr_png = fullfile(out_dir, sprintf('spearman_corr_channels_%s.png', session));

    write_per_unit_table(per_unit_chan, chan_vals, per_unit_csv);
    write_corr_table(corr_mat, chan_vals, corr_csv);
    save_corr_heatmap(corr_mat, chan_vals, sprintf('Channel Similarity (%s)', session), corr_png);

    % Optional debug output for shared pair counts
    shared_csv = fullfile(out_dir, sprintf('spearman_shared_n_%s.csv', session));
    write_corr_table(shared_n, chan_vals, shared_csv);

    % Per-current analysis for this session
    unique_curr = unique(current_uA, 'stable');
    for ci = 1:numel(unique_curr)
        cur = unique_curr(ci);
        idx_cur = abs(current_uA - cur) < 1e-9;
        if sum(idx_cur) < 2
            continue;
        end

        [per_unit_cur, chan_cur] = compute_per_unit_channel_mean(stim_mean(:, idx_cur), stim_channel(idx_cur));
        if numel(chan_cur) < 2
            continue;
        end
        [corr_cur, shared_n_cur] = pairwise_spearman(per_unit_cur);
        [per_unit_cur, chan_cur, corr_cur, shared_n_cur] = apply_channel_order(per_unit_cur, chan_cur, corr_cur, shared_n_cur, display_channel_order);

        cur_tag = current_tag(cur);
        per_unit_cur_csv = fullfile(out_dir, sprintf('FR_per_unit_per_channel_%s_current_%s.csv', session, cur_tag));
        corr_cur_csv = fullfile(out_dir, sprintf('spearman_corr_channels_%s_current_%s.csv', session, cur_tag));
        corr_cur_png = fullfile(out_dir, sprintf('spearman_corr_channels_%s_current_%s.png', session, cur_tag));
        shared_cur_csv = fullfile(out_dir, sprintf('spearman_shared_n_%s_current_%s.csv', session, cur_tag));

        write_per_unit_table(per_unit_cur, chan_cur, per_unit_cur_csv);
        write_corr_table(corr_cur, chan_cur, corr_cur_csv);
        write_corr_table(shared_n_cur, chan_cur, shared_cur_csv);
        save_corr_heatmap(corr_cur, chan_cur, sprintf('Channel Similarity (%s | %g uA)', session, cur), corr_cur_png);
    end
end

%% -------------------------
% COMBINED ANALYSIS
% -------------------------
chan1 = channels_session.Session1;
chan2 = channels_session.Session2;
common_chan = intersect(chan1, chan2, 'stable');
assert(numel(common_chan) >= 2, 'Need at least two common channels across sessions.');

idx1 = ismember(chan1, common_chan);
idx2 = ismember(chan2, common_chan);

P1 = per_session.Session1(:, idx1);
P2 = per_session.Session2(:, idx2);

% Ensure same channel order for Session2 matrix.
    [~, ord2] = ismember(common_chan, chan2(idx2));
    P2 = P2(:, ord2);

% Align to shared units by index (1..min units).
n_units_common = min(size(P1, 1), size(P2, 1));
P1 = P1(1:n_units_common, :);
P2 = P2(1:n_units_common, :);

combined = (P1 + P2) / 2;
[corr_comb, shared_n_comb] = pairwise_spearman(combined);
    [combined, common_chan, corr_comb, shared_n_comb] = apply_channel_order(combined, common_chan, corr_comb, shared_n_comb, display_channel_order);

combined_per_unit_csv = fullfile(out_dir, 'FR_per_unit_per_channel_combined.csv');
combined_corr_csv = fullfile(out_dir, 'spearman_corr_channels_combined.csv');
combined_corr_png = fullfile(out_dir, 'spearman_corr_channels_combined.png');
combined_shared_csv = fullfile(out_dir, 'spearman_shared_n_combined.csv');

write_per_unit_table(combined, common_chan, combined_per_unit_csv);
write_corr_table(corr_comb, common_chan, combined_corr_csv);
write_corr_table(shared_n_comb, common_chan, combined_shared_csv);
save_corr_heatmap(corr_comb, common_chan, 'Channel Similarity (Combined Sessions)', combined_corr_png);

%% -------------------------
% PER-CURRENT COMBINED ANALYSIS
% -------------------------
curr1 = unique(session_data.Session1.current_uA, 'stable');
curr2 = unique(session_data.Session2.current_uA, 'stable');
common_curr = intersect(curr1, curr2, 'stable');

for ci = 1:numel(common_curr)
    cur = common_curr(ci);
    idx1_cur = abs(session_data.Session1.current_uA - cur) < 1e-9;
    idx2_cur = abs(session_data.Session2.current_uA - cur) < 1e-9;
    if sum(idx1_cur) < 2 || sum(idx2_cur) < 2
        continue;
    end

    [P1_cur, chan1_cur] = compute_per_unit_channel_mean(session_data.Session1.stim_mean(:, idx1_cur), ...
        session_data.Session1.stim_channel(idx1_cur));
    [P2_cur, chan2_cur] = compute_per_unit_channel_mean(session_data.Session2.stim_mean(:, idx2_cur), ...
        session_data.Session2.stim_channel(idx2_cur));

    common_chan_cur = intersect(chan1_cur, chan2_cur, 'stable');
    if numel(common_chan_cur) < 2
        continue;
    end

    idx_c1 = ismember(chan1_cur, common_chan_cur);
    idx_c2 = ismember(chan2_cur, common_chan_cur);
    A = P1_cur(:, idx_c1);
    B = P2_cur(:, idx_c2);

    [~, ord_b] = ismember(common_chan_cur, chan2_cur(idx_c2));
    B = B(:, ord_b);

    n_units_cur = min(size(A, 1), size(B, 1));
    A = A(1:n_units_cur, :);
    B = B(1:n_units_cur, :);

    combined_cur = (A + B) / 2;
    [corr_comb_cur, shared_n_comb_cur] = pairwise_spearman(combined_cur);
    [combined_cur, common_chan_cur, corr_comb_cur, shared_n_comb_cur] = apply_channel_order(combined_cur, common_chan_cur, corr_comb_cur, shared_n_comb_cur, display_channel_order);

    cur_tag = current_tag(cur);
    out_per_unit = fullfile(out_dir, sprintf('FR_per_unit_per_channel_combined_current_%s.csv', cur_tag));
    out_corr = fullfile(out_dir, sprintf('spearman_corr_channels_combined_current_%s.csv', cur_tag));
    out_shared = fullfile(out_dir, sprintf('spearman_shared_n_combined_current_%s.csv', cur_tag));
    out_png = fullfile(out_dir, sprintf('spearman_corr_channels_combined_current_%s.png', cur_tag));

    write_per_unit_table(combined_cur, common_chan_cur, out_per_unit);
    write_corr_table(corr_comb_cur, common_chan_cur, out_corr);
    write_corr_table(shared_n_comb_cur, common_chan_cur, out_shared);
    save_corr_heatmap(corr_comb_cur, common_chan_cur, ...
        sprintf('Channel Similarity (Combined Sessions | %g uA)', cur), out_png);
end

%% -------------------------
% TOP PAIR SUMMARY
% -------------------------
[flat_vals, i_idx, j_idx] = upper_triangle_values(corr_comb);
valid = isfinite(flat_vals);
flat_vals = flat_vals(valid);
i_idx = i_idx(valid);
j_idx = j_idx(valid);

[flat_sorted, ord] = sort(flat_vals, 'descend');
i_idx = i_idx(ord);
j_idx = j_idx(ord);

top_n = min(10, numel(flat_sorted));

fprintf('Input MAT: %s\n', mat_file);
fprintf('Output dir: %s\n', out_dir);
fprintf('Top %d channel-pair Spearman correlations (combined):\n', top_n);
for k = 1:top_n
    ch_a = common_chan(i_idx(k));
    ch_b = common_chan(j_idx(k));
    fprintf('  %g vs %g: rho = %.6f\n', ch_a, ch_b, flat_sorted(k));
end

%% =========================
% LOCAL FUNCTIONS
% =========================
function [per_unit_chan, chan_vals] = compute_per_unit_channel_mean(stim_mean, stim_channel)
chan_vals = unique(stim_channel, 'stable');
n_units = size(stim_mean, 1);
n_chan = numel(chan_vals);

per_unit_chan = nan(n_units, n_chan);
for c = 1:n_chan
    idx = stim_channel == chan_vals(c);
    per_unit_chan(:, c) = mean(stim_mean(:, idx), 2, 'omitnan');
end
end

function [rho, shared_n] = pairwise_spearman(X)
n_chan = size(X, 2);
rho = nan(n_chan, n_chan);
shared_n = zeros(n_chan, n_chan);

for i = 1:n_chan
    xi = X(:, i);
    for j = i:n_chan
        xj = X(:, j);
        valid = isfinite(xi) & isfinite(xj);
        n_valid = sum(valid);
        shared_n(i, j) = n_valid;
        shared_n(j, i) = n_valid;
        if n_valid >= 3
            r = corr(xi(valid), xj(valid), 'Type', 'Spearman');
            rho(i, j) = r;
            rho(j, i) = r;
        end
    end
end
end

function write_per_unit_table(M, chan_vals, out_csv)
var_names = channel_var_names(chan_vals);
T = array2table(M, 'VariableNames', var_names);
T = addvars(T, (1:height(T))', 'Before', 1, 'NewVariableNames', 'unit');
writetable(T, out_csv);
end

function write_corr_table(M, chan_vals, out_csv)
var_names = channel_var_names(chan_vals);
T = array2table(M, 'VariableNames', var_names, 'RowNames', var_names);
writetable(T, out_csv, 'WriteRowNames', true);
end

function save_corr_heatmap(M, chan_vals, fig_title, out_png)
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [100 100 800 700]);
ax = axes(fig);
imagesc(ax, M, [-1 1]);
axis(ax, 'image');
colormap(ax, 'parula');
cb = colorbar(ax);
cb.Label.String = 'Spearman rho';

lbl = arrayfun(@(v) sprintf('%g', v), chan_vals, 'UniformOutput', false);
set(ax, 'XTick', 1:numel(chan_vals), 'XTickLabel', lbl, ...
    'YTick', 1:numel(chan_vals), 'YTickLabel', lbl, ...
    'XTickLabelRotation', 45, 'YDir', 'normal');

xlabel(ax, 'Stim channel');
ylabel(ax, 'Stim channel');
title(ax, fig_title, 'Interpreter', 'none');

exportgraphics(fig, out_png, 'Resolution', 200);
close(fig);
end

function var_names = channel_var_names(chan_vals)
var_names = cell(1, numel(chan_vals));
for i = 1:numel(chan_vals)
    var_names{i} = matlab.lang.makeValidName(sprintf('ch_%g', chan_vals(i)));
end
end

function [vals, i_idx, j_idx] = upper_triangle_values(M)
n = size(M, 1);
mask = triu(true(n), 1);
vals = M(mask);
[i_idx, j_idx] = find(mask);
end

function tag = current_tag(cur)
tag = sprintf('%g_uA', cur);
tag = strrep(tag, '.', 'p');
tag = strrep(tag, '-', 'm');
tag = strrep(tag, '+', 'p');
end

function [M, chan_vals, corr_mat, shared_n] = apply_channel_order(M, chan_vals, corr_mat, shared_n, desired_order)
% Reorder channels to place nearby shank channels next to each other.
desired_order = desired_order(:)';
chan_vals = chan_vals(:)';

ordered = desired_order(ismember(desired_order, chan_vals));
remaining = chan_vals(~ismember(chan_vals, desired_order));
remaining = sort(remaining);
new_order = [ordered, remaining];

[tf, idx] = ismember(new_order, chan_vals);
idx = idx(tf);

M = M(:, idx);
chan_vals = chan_vals(idx);

if nargin >= 3 && ~isempty(corr_mat)
    corr_mat = corr_mat(idx, idx);
end
if nargin >= 4 && ~isempty(shared_n)
    shared_n = shared_n(idx, idx);
end
end
