% Modify the following matlab code to draw some new figures and analyze
% 1. For the gain modulation, normalized or over the baseline firing rate for each unit
% and draw a scatter figure, x is the gain modulation for session 1, y is the gain modulation for session 2
% 2. Add statiscal analyze for the gain mouldation for two sessions and across all units, and see if we can divide the units into different groups
% (tell me what's the standard)
% 3. Get the threshold for each unit and Analyze the threshold changes for each unit for two sessions
%% ============================================================
% TWO-SESSION FIRING RATE + GAIN + Z-SCORE + NORMALIZED GAIN +
% MATCHED-UNIT SESSION COMPARISON + THRESHOLD ANALYSIS +
% GROUP-WISE LINE PLOTS ACROSS SESSIONS
%
% Main features:
% 1) Disregard trial-unit pairs with no spikes in baseline window
% 2) Adjustable modulation threshold
% 3) Gain:
%       gain = stim_mean - baseline_mean
% 4) Z-score:
%       z = (stim_mean - baseline_unit_mean) / max(baseline_unit_std, min_baseline_std)
% 5) Normalized gain:
%       norm_gain = (stim_mean - baseline_mean) / max(baseline_mean, baseline_floor_hz)
% 6) Matched-unit scatter:
%       x = unit normalized gain in session 1
%       y = unit normalized gain in session 2
% 7) Unit grouping:
%       enhanced_after / reduced_after / stable / nonresponsive / insufficient
% 8) Per-unit threshold:
%       threshold_z = lowest current where mean z-score > mod_thresh_sigma
%       threshold_normgain = lowest current where mean normalized gain > normgain_thresh
% 9) Group-wise line plots across sessions:
%       - Baseline FR
%       - Stim FR
%       - Gain
%       - Normalized gain
%
% IMPORTANT ASSUMPTION:
% selected_unit_id1(k) corresponds to selected_unit_id2(k).
%% ============================================================

clear; clc; close all;

%% ================= USER INPUT =================
filepath1 = 'I:\LGN_EXP\LGN11\2026-02-16\WF_StimSurvey_actual';
filepath2 = 'I:\LGN_EXP\LGN11\2026-03-26\wf_stim_survey';

selected_unit_id1 = [1	6	8	10	14	15	16	18	19	22	24	25	26	28	32	33	35	42	51	57	59	61	66	67	74	76	79	83	86	89	90	91	92	93	94	95];
selected_unit_id2 = [1	7	9	11	13	14	15	16	17	20	21	23	24	25	26	27	28	29	30	32	33	34	36	37	39	41	43	47	51	52	55	56	57	58	60	61];

Fs = 30000;

%% ================= PARAMETERS =================
win = [-1.1 0.5];
bin_w = 0.005;   % 5 ms bins

edges   = win(1):bin_w:win(2);
centers = edges(1:end-1) + bin_w/2;

base_win = [-1.1 -0.1];
stim_win = [0 0.5];

base_idx = centers >= base_win(1) & centers < base_win(2);
stim_idx = centers >= stim_win(1) & centers < stim_win(2);

if ~any(base_idx)
    error('Baseline window does not contain any bins.');
end
if ~any(stim_idx)
    error('Stim window does not contain any bins.');
end

% -------- adjustable parameters --------
mod_thresh_sigma     = 2;      % z-score threshold for modulation
baseline_min_spikes  = 1;      % exclude pair if baseline spikes < this
min_baseline_std     = 0.5;    % z-score denominator floor
baseline_floor_hz    = 1.0;    % normalized gain denominator floor
normgain_thresh      = 0.25;   % threshold for normalized gain threshold
delta_group_thresh   = 0.25;   % grouping threshold for session change
min_pairs_per_current = 2;     % minimum valid trial count for unit threshold at one current

%% ================= OUTPUT DIR =================
timestamp = datestr(now,'yyyymmdd_HHMMSS');
figDir = ['FRmod_2Session_figures_' timestamp];
resDir = ['FRmod_2Session_results_' timestamp];

if ~exist(figDir,'dir'); mkdir(figDir); end
if ~exist(resDir,'dir'); mkdir(resDir); end

%% ================= PROCESS BOTH SESSIONS =================
disp('============================================================')
disp('Processing session 1...')
S1 = process_one_session(filepath1, selected_unit_id1, Fs, win, bin_w, ...
    edges, base_idx, stim_idx, mod_thresh_sigma, baseline_min_spikes, ...
    min_baseline_std, baseline_floor_hz, normgain_thresh, ...
    min_pairs_per_current, 'Session1');

disp('Processing session 2...')
S2 = process_one_session(filepath2, selected_unit_id2, Fs, win, bin_w, ...
    edges, base_idx, stim_idx, mod_thresh_sigma, baseline_min_spikes, ...
    min_baseline_std, baseline_floor_hz, normgain_thresh, ...
    min_pairs_per_current, 'Session2');

%% ================= MATCHED UNIT ANALYSIS =================
disp('============================================================')
disp('Running matched-unit analysis...')

UnitCompareDir = fullfile(figDir, 'MatchedUnit_Analysis');
if ~exist(UnitCompareDir, 'dir'); mkdir(UnitCompareDir); end

U = build_matched_unit_table(S1, S2, delta_group_thresh);
Stats = run_unit_statistics(U);

plot_unit_gain_scatter(U, Stats, UnitCompareDir);
plot_unit_delta_hist(U, UnitCompareDir);
plot_threshold_scatter(U, Stats, UnitCompareDir);
plot_threshold_delta_hist(U, UnitCompareDir);
plot_group_bar(U, UnitCompareDir);

%% ================= GROUP LINE PLOTS =================
disp('============================================================')
disp('Plotting group-wise line plots across sessions...')

GroupLineDir = fullfile(figDir, 'Group_LinePlots');
if ~exist(GroupLineDir, 'dir'); mkdir(GroupLineDir); end

plot_group_lineplots_across_sessions(S1, S2, U, GroupLineDir);

%% ================= SAVE RESULTS =================
Result = struct;

Result.Fs = Fs;
Result.bin_w = bin_w;
Result.win = win;
Result.base_win = base_win;
Result.stim_win = stim_win;
Result.edges = edges;
Result.centers = centers;

Result.filepath1 = filepath1;
Result.filepath2 = filepath2;
Result.selected_unit_id1 = selected_unit_id1;
Result.selected_unit_id2 = selected_unit_id2;

Result.mod_thresh_sigma = mod_thresh_sigma;
Result.baseline_min_spikes = baseline_min_spikes;
Result.min_baseline_std = min_baseline_std;
Result.baseline_floor_hz = baseline_floor_hz;
Result.normgain_thresh = normgain_thresh;
Result.delta_group_thresh = delta_group_thresh;
Result.min_pairs_per_current = min_pairs_per_current;

Result.gain_definition = 'gain = stim_mean - baseline_mean';
Result.normgain_definition = 'norm_gain = (stim_mean - baseline_mean) / max(baseline_mean, baseline_floor_hz)';
Result.zscore_definition = 'zscore = (stim_mean - baseline_unit_mean) / max(baseline_unit_std, min_baseline_std)';
Result.threshold_z_definition = 'lowest current where mean z-score at that current > mod_thresh_sigma';
Result.threshold_normgain_definition = 'lowest current where unit mean normalized gain at that current > normgain_thresh';
Result.unit_matching_definition = 'Units are matched by position in selected_unit_id1 and selected_unit_id2';

Result.Session1 = S1;
Result.Session2 = S2;
Result.MatchedUnits = U;
Result.Stats = Stats;

save(fullfile(resDir, 'FRmod_2Session_MatchedUnit_Result.mat'), 'Result', '-v7.3');

disp('============================================================')
disp('Completed matched-unit normalized gain + threshold + group line plot analysis.')
disp(['Figures saved to: ' figDir])
disp(['Results saved to: ' resDir])

%% ============================================================
%% LOCAL FUNCTIONS
%% ============================================================

function S = process_one_session(filepath, selected_unit_id, Fs, win, bin_w, ...
    edges, base_idx, stim_idx, mod_thresh_sigma, baseline_min_spikes, ...
    min_baseline_std, baseline_floor_hz, normgain_thresh, ...
    min_pairs_per_current, session_name)

    fprintf('Loading data from %s\n', filepath);

    load(fullfile(filepath, 'merged_units_all_shanks.mat'));
    load(fullfile(filepath, 'stim_trial_start_times.mat'));

    if ~exist('merged_spikes','var')
        error('%s: merged_spikes not found in merged_units_all_shanks.mat', session_name);
    end
    if ~exist('trial_matrix','var')
        error('%s: trial_matrix not found in stim_trial_start_times.mat', session_name);
    end

    n_units_total = numel(merged_spikes);

    if isempty(selected_unit_id)
        selected_unit_id = 1:n_units_total;
    else
        selected_unit_id = selected_unit_id(:)';
        selected_unit_id = selected_unit_id(selected_unit_id >= 1 & selected_unit_id <= n_units_total);
    end

    merged_spikes = merged_spikes(selected_unit_id);

    trial_start  = trial_matrix(:,2);
    stim_channel = trial_matrix(:,3);
    current      = trial_matrix(:,4);

    unique_channels = unique(stim_channel);
    unique_currents = sort(unique(current(:)))';

    n_trials = numel(trial_start);
    n_units  = numel(merged_spikes);
    n_currents = numel(unique_currents);

    fprintf('%s: %d selected units, %d trials\n', session_name, n_units, n_trials);

    baseline_mean_mat       = nan(n_trials, n_units);
    stim_mean_mat           = nan(n_trials, n_units);
    gain_mean_mat           = nan(n_trials, n_units);
    normgain_mean_mat       = nan(n_trials, n_units);
    zscore_mean_mat         = nan(n_trials, n_units);

    baseline_std_mat        = nan(n_trials, n_units);
    baseline_spikecount_mat = nan(n_trials, n_units);
    valid_baseline_mat      = false(n_trials, n_units);
    modulated_z_mat         = false(n_trials, n_units);
    modulated_normgain_mat  = false(n_trials, n_units);

    % ---------------- PASS 1 ----------------
    for u = 1:n_units
        spk = double(merged_spikes{u});
        if isempty(spk)
            continue
        end

        for ti = 1:n_trials
            rel = (spk - trial_start(ti)) / Fs;
            rel = rel(rel >= win(1) & rel < win(2));

            counts = histcounts(rel, edges);
            fr = counts / bin_w;

            base_counts = counts(base_idx);
            base_spikecount = sum(base_counts);
            baseline_spikecount_mat(ti,u) = base_spikecount;

            if base_spikecount < baseline_min_spikes
                continue
            end

            valid_baseline_mat(ti,u) = true;

            base_vals = fr(base_idx);
            stim_vals = fr(stim_idx);

            base_mean = mean(base_vals, 'omitnan');
            stim_mean = mean(stim_vals, 'omitnan');
            gain_mean = stim_mean - base_mean;
            norm_gain = gain_mean / max(base_mean, baseline_floor_hz);

            base_std_trial = std(base_vals, 0, 'omitnan');

            baseline_mean_mat(ti,u) = base_mean;
            stim_mean_mat(ti,u)     = stim_mean;
            gain_mean_mat(ti,u)     = gain_mean;
            normgain_mean_mat(ti,u) = norm_gain;
            baseline_std_mat(ti,u)  = base_std_trial;
        end
    end

    % ---------------- PASS 2 ----------------
    baseline_unit_mean = nan(1, n_units);
    baseline_unit_std  = nan(1, n_units);
    valid_unit_mask    = false(1, n_units);

    for u = 1:n_units
        base_trials_u = baseline_mean_mat(valid_baseline_mat(:,u), u);

        if isempty(base_trials_u)
            continue
        end

        baseline_unit_mean(u) = mean(base_trials_u, 'omitnan');
        baseline_unit_std(u)  = std(base_trials_u, 0, 'omitnan');
        valid_unit_mask(u)    = true;

        denom_u = max(baseline_unit_std(u), min_baseline_std);

        valid_trials_u = find(valid_baseline_mat(:,u));
        for k = 1:numel(valid_trials_u)
            ti = valid_trials_u(k);

            stim_mean = stim_mean_mat(ti,u);
            zscore_mean = (stim_mean - baseline_unit_mean(u)) / denom_u;

            zscore_mean_mat(ti,u) = zscore_mean;
            modulated_z_mat(ti,u) = zscore_mean > mod_thresh_sigma;
            modulated_normgain_mat(ti,u) = normgain_mean_mat(ti,u) > normgain_thresh;
        end
    end

    % ---------------- PER-UNIT SUMMARY ----------------
    unit_baseline_mean = nan(1, n_units);
    unit_stim_mean     = nan(1, n_units);
    unit_gain_mean     = nan(1, n_units);
    unit_normgain_mean = nan(1, n_units);
    unit_zscore_mean   = nan(1, n_units);
    unit_n_valid_pairs = zeros(1, n_units);

    for u = 1:n_units
        mask_u = valid_baseline_mat(:,u);
        if ~any(mask_u), continue; end

        b  = baseline_mean_mat(mask_u, u);
        s  = stim_mean_mat(mask_u, u);
        g  = gain_mean_mat(mask_u, u);
        ng = normgain_mean_mat(mask_u, u);
        z  = zscore_mean_mat(mask_u, u);

        good = ~isnan(b) & ~isnan(s) & ~isnan(g) & ~isnan(ng) & ~isnan(z);
        b = b(good); s = s(good); g = g(good); ng = ng(good); z = z(good);

        if isempty(b), continue; end

        unit_baseline_mean(u) = mean(b, 'omitnan');
        unit_stim_mean(u)     = mean(s, 'omitnan');
        unit_gain_mean(u)     = mean(g, 'omitnan');
        unit_normgain_mean(u) = mean(ng, 'omitnan');
        unit_zscore_mean(u)   = mean(z, 'omitnan');
        unit_n_valid_pairs(u) = numel(g);
    end

    % ---------------- PER-UNIT PER-CURRENT SUMMARY ----------------
    unit_current_baseline_mean = nan(n_units, n_currents);
    unit_current_stim_mean     = nan(n_units, n_currents);
    unit_current_gain_mean     = nan(n_units, n_currents);
    unit_current_normgain_mean = nan(n_units, n_currents);
    unit_current_zscore_mean   = nan(n_units, n_currents);
    unit_current_n_pairs       = zeros(n_units, n_currents);

    for u = 1:n_units
        for ci = 1:n_currents
            cur = unique_currents(ci);
            idx = current == cur & valid_baseline_mat(:,u);

            if ~any(idx), continue; end

            b  = baseline_mean_mat(idx, u);
            s  = stim_mean_mat(idx, u);
            g  = gain_mean_mat(idx, u);
            ng = normgain_mean_mat(idx, u);
            z  = zscore_mean_mat(idx, u);

            good = ~isnan(b) & ~isnan(s) & ~isnan(g) & ~isnan(ng) & ~isnan(z);
            b = b(good); s = s(good); g = g(good); ng = ng(good); z = z(good);

            if isempty(b), continue; end

            unit_current_baseline_mean(u, ci) = mean(b, 'omitnan');
            unit_current_stim_mean(u, ci)     = mean(s, 'omitnan');
            unit_current_gain_mean(u, ci)     = mean(g, 'omitnan');
            unit_current_normgain_mean(u, ci) = mean(ng, 'omitnan');
            unit_current_zscore_mean(u, ci)   = mean(z, 'omitnan');
            unit_current_n_pairs(u, ci)       = numel(g);
        end
    end

    % ---------------- THRESHOLDS ----------------
    unit_threshold_z = nan(1, n_units);
    unit_threshold_normgain = nan(1, n_units);

    for u = 1:n_units
        for ci = 1:n_currents
            if unit_current_n_pairs(u, ci) < min_pairs_per_current
                continue
            end

            if isnan(unit_threshold_z(u)) && unit_current_zscore_mean(u, ci) > mod_thresh_sigma
                unit_threshold_z(u) = unique_currents(ci);
            end

            if isnan(unit_threshold_normgain(u)) && unit_current_normgain_mean(u, ci) > normgain_thresh
                unit_threshold_normgain(u) = unique_currents(ci);
            end
        end
    end

    S = struct;
    S.session_name = session_name;
    S.filepath = filepath;
    S.selected_unit_id = selected_unit_id;

    S.Fs = Fs;
    S.bin_w = bin_w;
    S.win = win;
    S.edges = edges;

    S.mod_thresh_sigma = mod_thresh_sigma;
    S.baseline_min_spikes = baseline_min_spikes;
    S.min_baseline_std = min_baseline_std;
    S.baseline_floor_hz = baseline_floor_hz;
    S.normgain_thresh = normgain_thresh;
    S.min_pairs_per_current = min_pairs_per_current;

    S.trial_start = trial_start;
    S.stim_channel = stim_channel;
    S.current = current;
    S.unique_channels = unique_channels;
    S.unique_currents = unique_currents;

    S.baseline_mean_mat = baseline_mean_mat;
    S.stim_mean_mat = stim_mean_mat;
    S.gain_mean_mat = gain_mean_mat;
    S.normgain_mean_mat = normgain_mean_mat;
    S.zscore_mean_mat = zscore_mean_mat;
    S.baseline_std_mat = baseline_std_mat;
    S.baseline_spikecount_mat = baseline_spikecount_mat;
    S.valid_baseline_mat = valid_baseline_mat;
    S.valid_unit_mask = valid_unit_mask;

    S.baseline_unit_mean = baseline_unit_mean;
    S.baseline_unit_std  = baseline_unit_std;

    S.modulated_z_mat = modulated_z_mat;
    S.modulated_normgain_mat = modulated_normgain_mat;

    S.unit_baseline_mean = unit_baseline_mean;
    S.unit_stim_mean = unit_stim_mean;
    S.unit_gain_mean = unit_gain_mean;
    S.unit_normgain_mean = unit_normgain_mean;
    S.unit_zscore_mean = unit_zscore_mean;
    S.unit_n_valid_pairs = unit_n_valid_pairs;

    S.unit_current_baseline_mean = unit_current_baseline_mean;
    S.unit_current_stim_mean = unit_current_stim_mean;
    S.unit_current_gain_mean = unit_current_gain_mean;
    S.unit_current_normgain_mean = unit_current_normgain_mean;
    S.unit_current_zscore_mean = unit_current_zscore_mean;
    S.unit_current_n_pairs = unit_current_n_pairs;

    S.unit_threshold_z = unit_threshold_z;
    S.unit_threshold_normgain = unit_threshold_normgain;
end

function U = build_matched_unit_table(S1, S2, delta_group_thresh)

    n_match = min(numel(S1.selected_unit_id), numel(S2.selected_unit_id));

    unit_index = (1:n_match)';
    unit_id_session1 = S1.selected_unit_id(1:n_match)';
    unit_id_session2 = S2.selected_unit_id(1:n_match)';

    gain1 = S1.unit_gain_mean(1:n_match)';
    gain2 = S2.unit_gain_mean(1:n_match)';

    ng1 = S1.unit_normgain_mean(1:n_match)';
    ng2 = S2.unit_normgain_mean(1:n_match)';

    z1 = S1.unit_zscore_mean(1:n_match)';
    z2 = S2.unit_zscore_mean(1:n_match)';

    thrz1 = S1.unit_threshold_z(1:n_match)';
    thrz2 = S2.unit_threshold_z(1:n_match)';

    thrn1 = S1.unit_threshold_normgain(1:n_match)';
    thrn2 = S2.unit_threshold_normgain(1:n_match)';

    np1 = S1.unit_n_valid_pairs(1:n_match)';
    np2 = S2.unit_n_valid_pairs(1:n_match)';

    d_ng = ng2 - ng1;
    d_gain = gain2 - gain1;
    d_thrz = thrz2 - thrz1;
    d_thrn = thrn2 - thrn1;

    group = strings(n_match,1);
    for i = 1:n_match
        if isnan(ng1(i)) || isnan(ng2(i))
            group(i) = "insufficient";
        elseif abs(ng1(i)) < 0.05 && abs(ng2(i)) < 0.05 && isnan(thrz1(i)) && isnan(thrz2(i))
            group(i) = "nonresponsive";
        elseif d_ng(i) > delta_group_thresh
            group(i) = "enhanced_after";
        elseif d_ng(i) < -delta_group_thresh
            group(i) = "reduced_after";
        else
            group(i) = "stable";
        end
    end

    U = table(unit_index, unit_id_session1, unit_id_session2, ...
        gain1, gain2, d_gain, ...
        ng1, ng2, d_ng, ...
        z1, z2, ...
        thrz1, thrz2, d_thrz, ...
        thrn1, thrn2, d_thrn, ...
        np1, np2, group);
end

function Stats = run_unit_statistics(U)

    Stats = struct;

    % -------- normalized gain paired stats --------
    idx_ng = ~isnan(U.ng1) & ~isnan(U.ng2);
    x = U.ng1(idx_ng);
    y = U.ng2(idx_ng);
    d = y - x;

    Stats.ng_n = numel(d);
    Stats.ng_mean_s1 = mean(x, 'omitnan');
    Stats.ng_mean_s2 = mean(y, 'omitnan');
    Stats.ng_median_s1 = median(x, 'omitnan');
    Stats.ng_median_s2 = median(y, 'omitnan');
    Stats.ng_mean_delta = mean(d, 'omitnan');
    Stats.ng_median_delta = median(d, 'omitnan');

    if numel(d) >= 4
        is_normal = false;
        try
            is_normal = ~lillietest(d);
        catch
            is_normal = false;
        end

        if is_normal
            [~,p,~,st] = ttest(y, x);
            Stats.ng_test = 'paired t-test';
            Stats.ng_p = p;
            Stats.ng_stat = st.tstat;
        else
            p = signrank(y, x);
            Stats.ng_test = 'signrank';
            Stats.ng_p = p;
            Stats.ng_stat = NaN;
        end

        [R,P] = corr(x, y, 'type', 'Spearman', 'rows', 'complete');
        Stats.ng_spearman_r = R;
        Stats.ng_spearman_p = P;
    else
        Stats.ng_test = 'not enough units';
        Stats.ng_p = NaN;
        Stats.ng_stat = NaN;
        Stats.ng_spearman_r = NaN;
        Stats.ng_spearman_p = NaN;
    end

    % -------- threshold paired stats --------
    idx_th = ~isnan(U.thrz1) & ~isnan(U.thrz2);
    x = U.thrz1(idx_th);
    y = U.thrz2(idx_th);
    d = y - x;

    Stats.th_n = numel(d);
    Stats.th_mean_s1 = mean(x, 'omitnan');
    Stats.th_mean_s2 = mean(y, 'omitnan');
    Stats.th_median_s1 = median(x, 'omitnan');
    Stats.th_median_s2 = median(y, 'omitnan');
    Stats.th_mean_delta = mean(d, 'omitnan');
    Stats.th_median_delta = median(d, 'omitnan');

    if numel(d) >= 4
        is_normal = false;
        try
            is_normal = ~lillietest(d);
        catch
            is_normal = false;
        end

        if is_normal
            [~,p,~,st] = ttest(y, x);
            Stats.th_test = 'paired t-test';
            Stats.th_p = p;
            Stats.th_stat = st.tstat;
        else
            p = signrank(y, x);
            Stats.th_test = 'signrank';
            Stats.th_p = p;
            Stats.th_stat = NaN;
        end

        [R,P] = corr(x, y, 'type', 'Spearman', 'rows', 'complete');
        Stats.th_spearman_r = R;
        Stats.th_spearman_p = P;
    else
        Stats.th_test = 'not enough units';
        Stats.th_p = NaN;
        Stats.th_stat = NaN;
        Stats.th_spearman_r = NaN;
        Stats.th_spearman_p = NaN;
    end

    % -------- group counts --------
    g = string(U.group);
    Stats.n_enhanced = sum(g == "enhanced_after");
    Stats.n_reduced = sum(g == "reduced_after");
    Stats.n_stable = sum(g == "stable");
    Stats.n_nonresponsive = sum(g == "nonresponsive");
    Stats.n_insufficient = sum(g == "insufficient");
end

function plot_unit_gain_scatter(U, Stats, outDir)

    fig = figure('Visible','off','Color','w','Position',[100 100 880 760]);
    hold on; box on;

    g = string(U.group);

    idx1 = g == "enhanced_after";
    idx2 = g == "reduced_after";
    idx3 = g == "stable";
    idx4 = g == "nonresponsive";
    idx5 = g == "insufficient";

    scatter(U.ng1(idx1), U.ng2(idx1), 80, [0.85 0.20 0.20], 'filled', 'DisplayName', 'Enhanced after');
    scatter(U.ng1(idx2), U.ng2(idx2), 80, [0.20 0.35 0.85], 'filled', 'DisplayName', 'Reduced after');
    scatter(U.ng1(idx3), U.ng2(idx3), 70, [0.20 0.20 0.20], 'filled', 'DisplayName', 'Stable');
    scatter(U.ng1(idx4), U.ng2(idx4), 70, [0.45 0.45 0.45], 'd', 'LineWidth', 1.5, 'DisplayName', 'Nonresponsive');
    scatter(U.ng1(idx5), U.ng2(idx5), 70, [0.70 0.70 0.70], 'x', 'LineWidth', 1.5, 'DisplayName', 'Insufficient');

    valid = ~isnan(U.ng1) & ~isnan(U.ng2);
    if any(valid)
        allv = [U.ng1(valid); U.ng2(valid)];
        lo = min(allv); hi = max(allv);
        pad = 0.1 * max(1e-6, hi - lo);
        lo = lo - pad; hi = hi + pad;
        plot([lo hi], [lo hi], 'k--', 'LineWidth', 1.5, 'DisplayName', 'Unity line');
        xlim([lo hi]); ylim([lo hi]);
    end

    xlabel('Normalized gain | Session 1', 'FontSize', 18, 'FontWeight', 'bold');
    ylabel('Normalized gain | Session 2', 'FontSize', 18, 'FontWeight', 'bold');
    title(sprintf('Unit-matched normalized gain\nn = %d, %s p = %.3g, Spearman r = %.3f', ...
        Stats.ng_n, Stats.ng_test, Stats.ng_p, Stats.ng_spearman_r), ...
        'FontSize', 18, 'FontWeight', 'bold');
    legend('Location','eastoutside','Box','off','FontSize',12);
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'MatchedUnits_NormalizedGain_Scatter.png'));
    savefig(fig, fullfile(outDir, 'MatchedUnits_NormalizedGain_Scatter.fig'));
    close(fig);
end

function plot_unit_delta_hist(U, outDir)

    fig = figure('Visible','off','Color','w','Position',[120 120 820 650]);
    hold on; box on;

    d = U.d_ng(~isnan(U.d_ng));
    histogram(d, 14, 'FaceColor', [0.3 0.3 0.3], 'EdgeColor', 'w');
    xline(0, 'k--', 'LineWidth', 1.5);

    xlabel('\Delta normalized gain (Session 2 - Session 1)', 'FontSize', 18, 'FontWeight', 'bold');
    ylabel('Number of units', 'FontSize', 18, 'FontWeight', 'bold');
    title('Distribution of normalized gain change across matched units', ...
        'FontSize', 18, 'FontWeight', 'bold');
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'MatchedUnits_NormalizedGain_DeltaHist.png'));
    savefig(fig, fullfile(outDir, 'MatchedUnits_NormalizedGain_DeltaHist.fig'));
    close(fig);
end

function plot_threshold_scatter(U, Stats, outDir)

    fig = figure('Visible','off','Color','w','Position',[100 100 880 760]);
    hold on; box on;

    valid = ~isnan(U.thrz1) & ~isnan(U.thrz2);
    scatter(U.thrz1(valid), U.thrz2(valid), 85, [0.15 0.15 0.15], 'filled', ...
        'DisplayName', 'Matched units');

    if any(valid)
        allv = [U.thrz1(valid); U.thrz2(valid)];
        lo = min(allv); hi = max(allv);
        plot([lo hi], [lo hi], 'k--', 'LineWidth', 1.5, 'DisplayName', 'Unity line');
        xlim([lo-0.1 hi+0.1]); ylim([lo-0.1 hi+0.1]);
    end

    xlabel('Threshold current | Session 1 (\muA)', 'FontSize', 18, 'FontWeight', 'bold');
    ylabel('Threshold current | Session 2 (\muA)', 'FontSize', 18, 'FontWeight', 'bold');
    title(sprintf('Per-unit threshold comparison (z-score threshold)\nn = %d, %s p = %.3g, Spearman r = %.3f', ...
        Stats.th_n, Stats.th_test, Stats.th_p, Stats.th_spearman_r), ...
        'FontSize', 18, 'FontWeight', 'bold');
    legend('Location','best','Box','off','FontSize',12);
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'MatchedUnits_ThresholdZ_Scatter.png'));
    savefig(fig, fullfile(outDir, 'MatchedUnits_ThresholdZ_Scatter.fig'));
    close(fig);
end

function plot_threshold_delta_hist(U, outDir)

    fig = figure('Visible','off','Color','w','Position',[120 120 820 650]);
    hold on; box on;

    d = U.d_thrz(~isnan(U.d_thrz));
    histogram(d, 12, 'FaceColor', [0.2 0.2 0.2], 'EdgeColor', 'w');
    xline(0, 'k--', 'LineWidth', 1.5);

    xlabel('\Delta threshold current (Session 2 - Session 1, \muA)', 'FontSize', 18, 'FontWeight', 'bold');
    ylabel('Number of units', 'FontSize', 18, 'FontWeight', 'bold');
    title('Distribution of threshold change across matched units', ...
        'FontSize', 18, 'FontWeight', 'bold');
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'MatchedUnits_ThresholdZ_DeltaHist.png'));
    savefig(fig, fullfile(outDir, 'MatchedUnits_ThresholdZ_DeltaHist.fig'));
    close(fig);
end

function plot_group_bar(U, outDir)

    fig = figure('Visible','off','Color','w','Position',[140 140 760 620]);
    hold on; box on;

    labels = {'Enhanced after','Reduced after','Stable','Nonresponsive','Insufficient'};
    counts = [sum(U.group=="enhanced_after"), ...
              sum(U.group=="reduced_after"), ...
              sum(U.group=="stable"), ...
              sum(U.group=="nonresponsive"), ...
              sum(U.group=="insufficient")];

    b = bar(counts, 'FaceColor', 'flat');
    b.CData = [0.85 0.20 0.20;
               0.20 0.35 0.85;
               0.20 0.20 0.20;
               0.55 0.55 0.55;
               0.78 0.78 0.78];

    set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels);
    xtickangle(25);

    ylabel('Number of units', 'FontSize', 18, 'FontWeight', 'bold');
    title('Unit grouping based on change in normalized gain', ...
        'FontSize', 18, 'FontWeight', 'bold');
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'MatchedUnits_GroupCounts.png'));
    savefig(fig, fullfile(outDir, 'MatchedUnits_GroupCounts.fig'));
    close(fig);
end

function plot_group_lineplots_across_sessions(S1, S2, U, outDir)

    group_list = ["enhanced_after", "reduced_after", "stable", "nonresponsive"];
    group_titles = {'Enhanced after', 'Reduced after', 'Stable', 'Nonresponsive'};

    common_currents = intersect(S1.unique_currents, S2.unique_currents);
    common_currents = sort(common_currents(:))';

    if isempty(common_currents)
        warning('No common currents between sessions for group line plots.');
        return
    end

    % -------- per group --------
    for gi = 1:numel(group_list)
        gname = group_list(gi);
        idx_units = find(string(U.group) == gname);

        if isempty(idx_units)
            fprintf('Group %s has no units. Skipping.\n', gname);
            continue
        end

        [b1m, b1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'baseline');
        [b2m, b2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'baseline');

        [s1m, s1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'stim');
        [s2m, s2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'stim');

        [g1m, g1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'gain');
        [g2m, g2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'gain');

        [ng1m, ng1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'normgain');
        [ng2m, ng2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'normgain');

        fig = figure('Visible','off','Color','w','Position',[100 100 1200 950]);

        subplot(2,2,1); hold on; box on;
        h1 = plot_mean_sem_shaded(common_currents, b1m, b1s, [0 0.4470 0.7410], '-', 'o', 'Session 1');
        h2 = plot_mean_sem_shaded(common_currents, b2m, b2s, [0.8500 0.3250 0.0980], '--', 's', 'Session 2');
        xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
        ylabel('Baseline FR (Hz)', 'FontSize', 15, 'FontWeight', 'bold');
        title(sprintf('%s | Baseline FR | n = %d', group_titles{gi}, numel(idx_units)), ...
            'FontSize', 16, 'FontWeight', 'bold');
        legend([h1 h2], {'Session 1','Session 2'}, 'Location','best', 'Box','off');
        style_axes(gca);

        subplot(2,2,2); hold on; box on;
        h1 = plot_mean_sem_shaded(common_currents, s1m, s1s, [0 0.4470 0.7410], '-', 'o', 'Session 1');
        h2 = plot_mean_sem_shaded(common_currents, s2m, s2s, [0.8500 0.3250 0.0980], '--', 's', 'Session 2');
        xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
        ylabel('Stim FR (Hz)', 'FontSize', 15, 'FontWeight', 'bold');
        title(sprintf('%s | Stim FR', group_titles{gi}), ...
            'FontSize', 16, 'FontWeight', 'bold');
        legend([h1 h2], {'Session 1','Session 2'}, 'Location','best', 'Box','off');
        style_axes(gca);

        subplot(2,2,3); hold on; box on;
        h1 = plot_mean_sem_shaded(common_currents, g1m, g1s, [0 0.4470 0.7410], '-', 'o', 'Session 1');
        h2 = plot_mean_sem_shaded(common_currents, g2m, g2s, [0.8500 0.3250 0.0980], '--', 's', 'Session 2');
        yline(0, 'k:', 'LineWidth', 1.2);
        xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
        ylabel('Gain (Hz)', 'FontSize', 15, 'FontWeight', 'bold');
        title(sprintf('%s | Gain modulation', group_titles{gi}), ...
            'FontSize', 16, 'FontWeight', 'bold');
        legend([h1 h2], {'Session 1','Session 2'}, 'Location','best', 'Box','off');
        style_axes(gca);

        subplot(2,2,4); hold on; box on;
        h1 = plot_mean_sem_shaded(common_currents, ng1m, ng1s, [0 0.4470 0.7410], '-', 'o', 'Session 1');
        h2 = plot_mean_sem_shaded(common_currents, ng2m, ng2s, [0.8500 0.3250 0.0980], '--', 's', 'Session 2');
        yline(0, 'k:', 'LineWidth', 1.2);
        xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
        ylabel('Normalized gain', 'FontSize', 15, 'FontWeight', 'bold');
        title(sprintf('%s | Normalized gain', group_titles{gi}), ...
            'FontSize', 16, 'FontWeight', 'bold');
        legend([h1 h2], {'Session 1','Session 2'}, 'Location','best', 'Box','off');
        style_axes(gca);

        sgtitle(sprintf('Group-wise session comparison | %s', group_titles{gi}), ...
            'FontSize', 18, 'FontWeight', 'bold');

        saveas(fig, fullfile(outDir, sprintf('GroupLine_%s.png', char(gname))));
        savefig(fig, fullfile(outDir, sprintf('GroupLine_%s.fig', char(gname))));
        close(fig);
    end

    % -------- summary: stim FR + gain across all groups --------
    fig = figure('Visible','off','Color','w','Position',[100 100 1400 560]);

    subplot(1,2,1); hold on; box on;
    colors = lines(numel(group_list));
    h_leg = gobjects(numel(group_list)*2,1);
    leg_txt = cell(numel(group_list)*2,1);
    kk = 0;

    for gi = 1:numel(group_list)
        gname = group_list(gi);
        idx_units = find(string(U.group) == gname);
        if isempty(idx_units), continue; end

        [s1m, s1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'stim');
        [s2m, s2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'stim');

        kk = kk + 1;
        h_leg(kk) = plot_mean_sem_shaded(common_currents, s1m, s1s, colors(gi,:), '-', 'o', 'tmp');
        leg_txt{kk} = sprintf('%s | S1', group_titles{gi});

        kk = kk + 1;
        h_leg(kk) = plot_mean_sem_shaded(common_currents, s2m, s2s, lighten_color(colors(gi,:),0.45), '--', 's', 'tmp');
        leg_txt{kk} = sprintf('%s | S2', group_titles{gi});
    end

    xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
    ylabel('Stim FR (Hz)', 'FontSize', 15, 'FontWeight', 'bold');
    title('Stim FR across groups and sessions', 'FontSize', 16, 'FontWeight', 'bold');
    legend(h_leg(1:kk), leg_txt(1:kk), 'Location','eastoutside', 'Box','off');
    style_axes(gca);

    subplot(1,2,2); hold on; box on;
    h_leg = gobjects(numel(group_list)*2,1);
    leg_txt = cell(numel(group_list)*2,1);
    kk = 0;

    for gi = 1:numel(group_list)
        gname = group_list(gi);
        idx_units = find(string(U.group) == gname);
        if isempty(idx_units), continue; end

        [g1m, g1s] = aggregate_group_metric_by_current(S1, idx_units, common_currents, 'gain');
        [g2m, g2s] = aggregate_group_metric_by_current(S2, idx_units, common_currents, 'gain');

        kk = kk + 1;
        h_leg(kk) = plot_mean_sem_shaded(common_currents, g1m, g1s, colors(gi,:), '-', 'o', 'tmp');
        leg_txt{kk} = sprintf('%s | S1', group_titles{gi});

        kk = kk + 1;
        h_leg(kk) = plot_mean_sem_shaded(common_currents, g2m, g2s, lighten_color(colors(gi,:),0.45), '--', 's', 'tmp');
        leg_txt{kk} = sprintf('%s | S2', group_titles{gi});
    end

    yline(0, 'k:', 'LineWidth', 1.2);
    xlabel('Stimulation current (\muA)', 'FontSize', 15, 'FontWeight', 'bold');
    ylabel('Gain (Hz)', 'FontSize', 15, 'FontWeight', 'bold');
    title('Gain modulation across groups and sessions', 'FontSize', 16, 'FontWeight', 'bold');
    legend(h_leg(1:kk), leg_txt(1:kk), 'Location','eastoutside', 'Box','off');
    style_axes(gca);

    saveas(fig, fullfile(outDir, 'Summary_AllGroups_StimFR_Gain.png'));
    savefig(fig, fullfile(outDir, 'Summary_AllGroups_StimFR_Gain.fig'));
    close(fig);
end

function [metric_mean, metric_sem] = aggregate_group_metric_by_current(S, unit_idx, use_currents, metric_name)

    n_curr = numel(use_currents);
    metric_mean = nan(1, n_curr);
    metric_sem  = nan(1, n_curr);

    switch lower(metric_name)
        case 'baseline'
            metric_mat = S.baseline_mean_mat;
        case 'stim'
            metric_mat = S.stim_mean_mat;
        case 'gain'
            metric_mat = S.gain_mean_mat;
        case 'normgain'
            metric_mat = S.normgain_mean_mat;
        otherwise
            error('Unknown metric_name: %s', metric_name);
    end

    valid_units = unit_idx(unit_idx >= 1 & unit_idx <= size(metric_mat,2));
    if isempty(valid_units)
        return
    end

    for i = 1:n_curr
        cur = use_currents(i);
        trial_mask = (S.current == cur);

        vals_all_units = nan(1, numel(valid_units));

        for uu = 1:numel(valid_units)
            u = valid_units(uu);

            pair_mask = trial_mask & S.valid_baseline_mat(:,u);
            if ~any(pair_mask)
                continue
            end

            vals = metric_mat(pair_mask, u);
            vals = vals(~isnan(vals));

            if ~isempty(vals)
                vals_all_units(uu) = mean(vals, 'omitnan');
            end
        end

        vals_all_units = vals_all_units(~isnan(vals_all_units));

        if ~isempty(vals_all_units)
            metric_mean(i) = mean(vals_all_units, 'omitnan');
            metric_sem(i)  = std(vals_all_units, 0, 'omitnan') / sqrt(numel(vals_all_units));
        end
    end
end

function h = plot_mean_sem_shaded(x, y_mean, y_sem, line_color, line_style, marker_style, label_str)

    x = x(:);
    y_mean = y_mean(:);
    y_sem  = y_sem(:);

    valid = ~isnan(x) & ~isnan(y_mean) & ~isnan(y_sem);
    x = x(valid);
    y_mean = y_mean(valid);
    y_sem  = y_sem(valid);

    if isempty(x)
        h = plot(nan, nan, ...
            'LineStyle', line_style, ...
            'Marker', marker_style, ...
            'Color', line_color, ...
            'LineWidth', 2.8, ...
            'MarkerSize', 7, ...
            'MarkerFaceColor', line_color, ...
            'DisplayName', label_str);
        return
    end

    [x, ord] = sort(x);
    y_mean = y_mean(ord);
    y_sem  = y_sem(ord);

    x_patch = [x; flipud(x)];
    y_patch = [y_mean - y_sem; flipud(y_mean + y_sem)];

    hp = fill(x_patch, y_patch, line_color, ...
        'FaceAlpha', 0.18, ...
        'EdgeColor', 'none');
    set(get(get(hp,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');

    h = plot(x, y_mean, ...
        'LineStyle', line_style, ...
        'Marker', marker_style, ...
        'Color', line_color, ...
        'LineWidth', 2.8, ...
        'MarkerSize', 7, ...
        'MarkerFaceColor', line_color, ...
        'DisplayName', label_str);
end

function c2 = lighten_color(c1, amount)
    c1 = c1(:)';
    amount = max(0, min(1, amount));
    c2 = c1 + (1 - c1) * amount;
    c2 = min(max(c2, 0), 1);
end

function style_axes(ax)
    set(ax, ...
        'FontSize', 14, ...
        'LineWidth', 1.5, ...
        'TickDir', 'out', ...
        'Box', 'off', ...
        'Layer', 'top');
    grid(ax, 'on');
    ax.GridAlpha = 0.18;
    ax.MinorGridAlpha = 0.08;
end