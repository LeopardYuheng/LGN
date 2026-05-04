%% identify_channel_preferring_units.m
% Identify neurons (units) that respond preferentially to specific channels
% using FRmod_2Session_MatchedUnit_Result.mat.
%
% The script summarizes, for each session and current level:
%   - mean stimulus response per unit per channel
%   - mean z-score response per unit per channel
%   - preferred channel per unit
%   - a simple selectivity index
%   - a CSV of top units for each channel
%
% Outputs are written to the same folder as the MAT file by default.

close all; clc;

%% -------------------------
% USER OPTIONS
% -------------------------
mat_file = "";
out_dir = "";
top_n_units_per_channel = 10;
response_metric = "stim_mean_mat"; % or "zscore_mean_mat"
z_threshold = 2.0;

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

fprintf('Input MAT: %s\n', mat_file);
fprintf('Output dir: %s\n', out_dir);

%% -------------------------
% ANALYSIS
% -------------------------
for s = 1:numel(sessions)
    session = sessions(s);
    base = sprintf('/Result/%s', session);

    stim_channel = double(h5read(mat_file, sprintf('%s/stim_channel', base)));
    stim_channel = stim_channel(:)';
    current_uA = double(h5read(mat_file, sprintf('%s/current', base)));
    current_uA = current_uA(:)';

    response_mat = double(h5read(mat_file, sprintf('%s/%s', base, response_metric)));
    if size(response_mat, 1) == numel(stim_channel) && size(response_mat, 2) ~= numel(stim_channel)
        response_mat = response_mat';
    end

    zscore_mat = double(h5read(mat_file, sprintf('%s/zscore_mean_mat', base)));
    if size(zscore_mat, 1) == numel(stim_channel) && size(zscore_mat, 2) ~= numel(stim_channel)
        zscore_mat = zscore_mat';
    end

    valid_unit_mask = logical(double(h5read(mat_file, sprintf('%s/valid_unit_mask', base))));
    valid_unit_mask = valid_unit_mask(:);

    [n_units, n_trials] = size(response_mat);
    if numel(stim_channel) ~= n_trials
        error('%s: trial metadata mismatch.', session);
    end
    if numel(valid_unit_mask) ~= n_units
        valid_unit_mask = true(n_units, 1);
    end

    units = (1:n_units)';
    unique_currents = unique(current_uA, 'stable');
    unique_channels = unique(stim_channel, 'stable');

    summary_rows = table();
    channel_top_rows = table();

    for ci = 1:numel(unique_currents)
        cur = unique_currents(ci);
        idx_cur = abs(current_uA - cur) < 1e-9;
        if sum(idx_cur) < 2
            continue;
        end

        resp_cur = response_mat(:, idx_cur);
        z_cur = zscore_mat(:, idx_cur);
        chan_cur = stim_channel(idx_cur);
        chan_vals = unique(chan_cur, 'stable');
        if numel(chan_vals) < 2
            continue;
        end

        per_unit_channel = nan(n_units, numel(chan_vals));
        per_unit_z = nan(n_units, numel(chan_vals));
        n_trials_channel = zeros(1, numel(chan_vals));

        for k = 1:numel(chan_vals)
            idx_chan = chan_cur == chan_vals(k);
            n_trials_channel(k) = sum(idx_chan);
            per_unit_channel(:, k) = mean(resp_cur(:, idx_chan), 2, 'omitnan');
            per_unit_z(:, k) = mean(z_cur(:, idx_chan), 2, 'omitnan');
        end

        % Save the exact unit-by-channel matrix used for this current level.
        matrix_csv = fullfile(out_dir, sprintf('%s_unit_by_channel_current_%s.csv', session, current_tag(cur)));
        matrix_table = array2table(per_unit_channel, 'VariableNames', channel_var_names(chan_vals));
        matrix_table = addvars(matrix_table, units, 'Before', 1, 'NewVariableNames', 'unit');
        writetable(matrix_table, matrix_csv);

        % Simple selectivity: winner minus runner-up normalized by sum.
        [best_resp, best_idx] = max(per_unit_channel, [], 2, 'omitnan');
        sorted_resp = sort(per_unit_channel, 2, 'descend', 'MissingPlacement', 'last');
        if size(sorted_resp, 2) >= 2
            second_best = sorted_resp(:, 2);
        else
            second_best = nan(n_units, 1);
        end
        selectivity_index = (best_resp - second_best) ./ (abs(best_resp) + abs(second_best) + eps);

        [best_z, best_z_idx] = max(per_unit_z, [], 2, 'omitnan');

        for u = 1:n_units
            if ~valid_unit_mask(u)
                continue;
            end
            summary_rows = [summary_rows; table( ...
                string(session), cur, units(u), chan_vals(best_idx(u)), chan_vals(best_z_idx(u)), ...
                best_resp(u), best_z(u), selectivity_index(u), ...
                'VariableNames', {'session','current_uA','unit','preferred_channel_by_response','preferred_channel_by_zscore', ...
                                  'best_mean_response','best_mean_zscore','selectivity_index'})]; %#ok<AGROW>
        end

        % Top units for each channel, ranked by response then z-score.
        for ch_i = 1:numel(chan_vals)
            ch = chan_vals(ch_i);
            idx_chan = chan_cur == ch;
            if sum(idx_chan) < 1
                continue;
            end

            unit_resp = per_unit_channel(:, ch_i);
            unit_z = per_unit_z(:, ch_i);
            is_active = isfinite(unit_resp) & isfinite(unit_z);
            if ~any(is_active)
                continue;
            end

            ranked = table(units(is_active), unit_resp(is_active), unit_z(is_active), selectivity_index(is_active), ...
                'VariableNames', {'unit','mean_response','mean_zscore','selectivity_index'});
            ranked = sortrows(ranked, {'mean_response','mean_zscore'}, {'descend','descend'});
            if height(ranked) > top_n_units_per_channel
                ranked = ranked(1:top_n_units_per_channel, :);
            end

            ranked.session = repmat(string(session), height(ranked), 1);
            ranked.current_uA = repmat(cur, height(ranked), 1);
            ranked.channel = repmat(ch, height(ranked), 1);
            ranked = movevars(ranked, {'session','current_uA','channel'}, 'Before', 1);
            channel_top_rows = [channel_top_rows; ranked]; %#ok<AGROW>
        end
    end

    summary_csv = fullfile(out_dir, sprintf('%s_unit_channel_preference_summary.csv', session));
    tops_csv = fullfile(out_dir, sprintf('%s_top_units_by_channel.csv', session));

    writetable(summary_rows, summary_csv);
    writetable(channel_top_rows, tops_csv);

    fprintf('Saved %s\n', summary_csv);
    fprintf('Saved %s\n', tops_csv);
end

%% -------------------------
% COMBINED SUMMARY ACROSS SESSIONS
% -------------------------
% Keep only channels/units that appear in both sessions by joining on unit and current.
all_summaries = table();
for s = 1:numel(sessions)
    session = sessions(s);
    summary_csv = fullfile(out_dir, sprintf('%s_unit_channel_preference_summary.csv', session));
    if isfile(summary_csv)
        T = readtable(summary_csv);
        all_summaries = [all_summaries; T]; %#ok<AGROW>
    end
end
if ~isempty(all_summaries)
    combined_csv = fullfile(out_dir, 'combined_unit_channel_preference_summary.csv');
    writetable(all_summaries, combined_csv);
    fprintf('Saved %s\n', combined_csv);
end

fprintf('Done.\n');

%% -------------------------
% LOCAL HELPERS
% -------------------------
function tag = current_tag(cur)
tag = sprintf('%g_uA', cur);
tag = strrep(tag, '.', 'p');
tag = strrep(tag, '-', 'm');
tag = strrep(tag, '+', 'p');
end

function var_names = channel_var_names(chan_vals)
var_names = cell(1, numel(chan_vals));
for i = 1:numel(chan_vals)
    var_names{i} = matlab.lang.makeValidName(sprintf('ch_%g', chan_vals(i)));
end
end
