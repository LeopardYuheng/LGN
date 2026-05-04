% replot_pixelwise_significance_maps.m
% Load pixelwise_threshold_region_results.mat and replot activation borders.
clc;clear;
[fn, fp] = uigetfile('*.mat', 'Select pixelwise_threshold_region_results.mat');
if isequal(fn,0), return; end
S = load(fullfile(fp, fn));
if ~isfield(S, 'results')
    error('Selected MAT does not contain ''results'' variable.');
end
results = S.results;

% Plotting context (use saved values when present, otherwise safe fallbacks)
if isfield(S, 'conn') && ~isempty(S.conn)
    conn = S.conn;
else
    conn = 8;
end

if isfield(S, 'final_mask') && ~isempty(S.final_mask)
    final_mask = logical(S.final_mask);
else
    first_mask = [];
    for rr = 1:numel(results)
        if isfield(results(rr), 'current_summary') && ~isempty(results(rr).current_summary)
            for kk = 1:numel(results(rr).current_summary)
                if isfield(results(rr).current_summary(kk), 'sig_cluster_mask') && ~isempty(results(rr).current_summary(kk).sig_cluster_mask)
                    first_mask = results(rr).current_summary(kk).sig_cluster_mask;
                    break;
                end
            end
        end
        if ~isempty(first_mask), break; end
    end
    if isempty(first_mask)
        error('No final_mask in MAT and no cluster masks found to infer image size.');
    end
    warning('final_mask not found; using full-frame mask fallback.');
    final_mask = true(size(first_mask));
end

if isfield(S, 'V1_mask') && ~isempty(S.V1_mask)
    V1_mask = logical(S.V1_mask);
else
    V1_mask = final_mask;
end

if isfield(S, 'global_v1_xlim') && ~isempty(S.global_v1_xlim)
    global_v1_xlim = S.global_v1_xlim;
else
    [~, x_m] = find(V1_mask);
    if isempty(x_m)
        global_v1_xlim = [1 size(final_mask,2)];
    else
        pad_xy = 10;
        global_v1_xlim = [max(1, min(x_m)-pad_xy), min(size(final_mask,2), max(x_m)+pad_xy)];
    end
end

if isfield(S, 'global_v1_ylim') && ~isempty(S.global_v1_ylim)
    global_v1_ylim = S.global_v1_ylim;
else
    [y_m, ~] = find(V1_mask);
    if isempty(y_m)
        global_v1_ylim = [1 size(final_mask,1)];
    else
        pad_xy = 10;
        global_v1_ylim = [max(1, min(y_m)-pad_xy), min(size(final_mask,1), max(y_m)+pad_xy)];
    end
end

% --- channel / current selection ---------------------------------------
% You can predefine variables in the workspace before running this script:
% - selected_channels : numeric vector of channel ids to replot (empty => all)
% - selected_currents : numeric vector of currents (uA) to replot (empty => all)
channels_available = [results.channel];
currents_available = [];
for r_i = 1:numel(results)
    if ~isfield(results(r_i), 'current_summary') || isempty(results(r_i).current_summary)
        continue;
    end
    cs_currents = [results(r_i).current_summary.current_uA];
    cs_currents = cs_currents(isfinite(cs_currents));
    currents_available = [currents_available, cs_currents]; %#ok<AGROW>
end
currents_available = sort(unique(currents_available));

if ~exist('selected_channels', 'var') || isempty(selected_channels)
    liststr = arrayfun(@(c) sprintf('Channel %d', c), channels_available, 'UniformOutput', false);
    [sel_idx, ok] = listdlg('ListString', liststr, 'PromptString', 'Select channels to replot', 'ListSize', [300 300]);
    if isempty(sel_idx) || ~ok
        fprintf('No channels selected. Exiting.\n');
        return;
    end
    selected_channels = channels_available(sel_idx);
else
    selected_channels = selected_channels(:)';
end

% currents with significant activation in selected channels only
sig_currents_available = [];
for ch_i = 1:numel(selected_channels)
    ch = selected_channels(ch_i);
    r_idx = find([results.channel] == ch, 1);
    if isempty(r_idx) || ~isfield(results(r_idx), 'current_summary') || isempty(results(r_idx).current_summary)
        continue;
    end
    cs = results(r_idx).current_summary;
    has_sig = isfield(cs, 'has_cluster') & [cs.has_cluster];
    if any(has_sig)
        sig_currents_available = [sig_currents_available, [cs(has_sig).current_uA]]; %#ok<AGROW>
    end
end
sig_currents_available = sort(unique(sig_currents_available(isfinite(sig_currents_available))));
if isempty(sig_currents_available)
    error('No significant activations found for the selected channels.');
end

if ~exist('selected_currents', 'var') || isempty(selected_currents)
    default_currents = '';
    if any(ismember(sig_currents_available, 5))
        default_currents = '5';
    elseif ~isempty(sig_currents_available)
        default_currents = strjoin(cellstr(num2str(sig_currents_available(:))), ', ');
    end
    answ = inputdlg({'Enter currents (uA) as comma-separated list (leave blank for ALL SIGNIFICANT):'}, 'Select currents', 1, {default_currents});
    if isempty(answ)
        fprintf('No current selection provided. Exiting.\n');
        return;
    end
    cur_str = strtrim(answ{1});
    if isempty(cur_str)
        selected_currents = [];
    else
        selected_currents = str2num(cur_str); %#ok<ST2NM>
        if isempty(selected_currents)
            error('Could not parse selected currents. Provide numbers separated by commas.');
        end
    end
else
    selected_currents = selected_currents(:)';
end

if isempty(selected_currents)
    currents_str = 'ALL_SIGNIFICANT';
    currents_to_plot = sig_currents_available;
else
    currents_to_plot = intersect(selected_currents, sig_currents_available);
    if isempty(currents_to_plot)
        error('None of the requested currents have significant activations in the selected channels.');
    end
    if numel(currents_to_plot) < numel(unique(selected_currents))
        fprintf('Dropped non-significant currents. Using: %s\n', mat2str(currents_to_plot));
    end
    currents_str = mat2str(currents_to_plot);
end
fprintf('Replotting channels: %s; currents: %s\n', mat2str(selected_channels), currents_str);
% -----------------------------------------------------------------------

out_dir = fullfile(fp, 'replots');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

fig_dir = fullfile(out_dir, 'border_overlays');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

for cur_i = 1:numel(currents_to_plot)
    cur = currents_to_plot(cur_i);

    active_channels = [];
    for ch_i = 1:numel(selected_channels)
        ch = selected_channels(ch_i);
        r_idx = find([results.channel] == ch, 1);
        if isempty(r_idx)
            continue;
        end
        cs = results(r_idx).current_summary;
        idx_cur = find([cs.current_uA] == cur & [cs.has_cluster], 1);
        if ~isempty(idx_cur)
            active_channels(end+1) = ch; %#ok<AGROW>
        end
    end

    if isempty(active_channels)
        fprintf('No selected channels have significant activation at %g uA. Skipping.\n', cur);
        continue;
    end

    fig = figure('Visible','off','Color','w', 'Name', sprintf('Border overlay %g uA', cur), ...
        'Position', [100 100 760 520]);
    ax = axes(fig);
    imagesc(ax, double(final_mask));
    axis(ax, 'image');
    axis(ax, 'off');
    set(ax, 'YDir', 'normal');
    xlim(ax, global_v1_xlim);
    ylim(ax, global_v1_ylim);
    colormap(ax, gray);
    caxis(ax, [0 1]);
    hold(ax, 'on');
    visboundaries(ax, V1_mask, 'Color', 'w', 'LineWidth', 1.2);
    visboundaries(ax, final_mask, 'Color', 'y', 'LineWidth', 1.2);

    cmap_cur = lines(numel(active_channels));
    legend_handles = gobjects(0);
    legend_labels = {};

    for a_i = 1:numel(active_channels)
        ch = active_channels(a_i);
        r_idx = find([results.channel] == ch, 1);
        cs = results(r_idx).current_summary;

        active_idx = find([cs.current_uA] == cur & [cs.has_cluster], 1);
        if isempty(active_idx)
            continue;
        end

        cs_i = cs(active_idx(1));
        if any(cs_i.sig_cluster_mask(:))
            B = bwboundaries(cs_i.sig_cluster_mask & final_mask, conn, 'noholes');
            for b_i = 1:numel(B)
                boundary = B{b_i};
                patch(ax, boundary(:,2), boundary(:,1), cmap_cur(a_i,:), ...
                    'FaceAlpha', 0.12, 'EdgeColor', cmap_cur(a_i,:), 'LineWidth', 2);
            end
        end
        legend_handles(end+1) = plot(ax, nan, nan, 'o', ...
            'MarkerFaceColor', cmap_cur(a_i,:), 'MarkerEdgeColor', 'k', ...
            'MarkerSize', 6, 'LineStyle', 'none'); %#ok<AGROW>
        legend_labels{end+1} = sprintf('Ch %d', ch); %#ok<AGROW>
    end

    title(ax, sprintf('Current %g uA | selected channel borders', cur), 'Interpreter', 'none');
    if ~isempty(legend_handles)
        legend(ax, legend_handles, legend_labels, 'Location', 'southoutside', 'Box', 'off');
    end
    exportgraphics(fig, fullfile(fig_dir, sprintf('current_%g_uA_border_overlay.png', cur)), 'Resolution', 200);
    close(fig);
end

% -----------------------------------------------------------------------
% Compare mean intensity across significant currents (per channel)
cmp_dir = fullfile(out_dir, 'significant_intensity_comparison');
if ~exist(cmp_dir, 'dir'), mkdir(cmp_dir); end

rows = struct('channel', {}, 'current_uA', {}, 'mean_intensity', {}, 'delta_from_first', {}, 'ratio_to_first', {});

for ch_i = 1:numel(selected_channels)
    ch = selected_channels(ch_i);
    r_idx = find([results.channel] == ch, 1);
    if isempty(r_idx) || ~isfield(results(r_idx), 'current_summary') || isempty(results(r_idx).current_summary)
        continue;
    end

    cs = results(r_idx).current_summary;
    has_sig = isfield(cs, 'has_cluster') & [cs.has_cluster];
    cur_vals = [cs.current_uA];
    in_selected_curr = ismember(cur_vals, currents_to_plot);
    sig_idx = find(has_sig & in_selected_curr);

    % Only compare channels with multiple significant currents
    if numel(sig_idx) < 2
        continue;
    end

    sig_currents = cur_vals(sig_idx);
    [sig_currents, ord] = sort(sig_currents);
    sig_idx = sig_idx(ord);

    mean_intensity = nan(size(sig_idx));
    for k = 1:numel(sig_idx)
        csk = cs(sig_idx(k));
        if isfield(csk, 'mean_cluster_effect') && isfinite(csk.mean_cluster_effect)
            mean_intensity(k) = csk.mean_cluster_effect;
        elseif isfield(csk, 'mean_evoked_map') && ~isempty(csk.mean_evoked_map) && isfield(csk, 'sig_cluster_mask') && ~isempty(csk.sig_cluster_mask)
            roi = logical(csk.sig_cluster_mask) & final_mask;
            mean_intensity(k) = mean(csk.mean_evoked_map(roi), 'omitnan');
        end
    end

    keep = isfinite(mean_intensity) & isfinite(sig_currents);
    sig_currents = sig_currents(keep);
    mean_intensity = mean_intensity(keep);
    if numel(sig_currents) < 2
        continue;
    end

    baseline = mean_intensity(1);
    delta_vals = mean_intensity - baseline;
    if baseline ~= 0
        ratio_vals = mean_intensity ./ baseline;
    else
        ratio_vals = nan(size(mean_intensity));
    end

    fig_cmp = figure('Visible','off', 'Color','w', 'Name', sprintf('Ch %d intensity comparison', ch), ...
        'Position', [120 120 700 460]);
    yyaxis left;
    plot(sig_currents, mean_intensity, 'o-', 'LineWidth', 1.8, 'MarkerSize', 6);
    ylabel('Mean intensity in significant region (\DeltaF/F)');
    yyaxis right;
    bar(sig_currents, delta_vals, 0.35, 'FaceAlpha', 0.25);
    ylabel('\Delta intensity from lowest significant current');
    xlabel('Current (uA)');
    title(sprintf('Ch %d | significant-current intensity comparison', ch), 'Interpreter', 'none');
    grid on;
    legend({'Mean intensity', '\Delta from first'}, 'Location', 'best', 'Box', 'off');
    exportgraphics(fig_cmp, fullfile(cmp_dir, sprintf('channel_%d_significant_intensity_comparison.png', ch)), 'Resolution', 200);
    close(fig_cmp);

    for k = 1:numel(sig_currents)
        rows(end+1).channel = ch; %#ok<AGROW>
        rows(end).current_uA = sig_currents(k);
        rows(end).mean_intensity = mean_intensity(k);
        rows(end).delta_from_first = delta_vals(k);
        rows(end).ratio_to_first = ratio_vals(k);
    end
end

if ~isempty(rows)
    Tcmp = table([rows.channel]', [rows.current_uA]', [rows.mean_intensity]', [rows.delta_from_first]', [rows.ratio_to_first]', ...
        'VariableNames', {'channel','current_uA','mean_intensity','delta_from_lowest_significant','ratio_to_lowest_significant'});
    writetable(Tcmp, fullfile(cmp_dir, 'significant_intensity_comparison.csv'));
    fprintf('Saved significant intensity comparison to: %s\n', cmp_dir);

    % ---------------------------------------------------------------
    % Population summary: does intensity generally increase with current?
    pop_dir = fullfile(out_dir, 'population_intensity_trend');
    if ~exist(pop_dir, 'dir'), mkdir(pop_dir); end

    channels_u = unique(Tcmp.channel);
    slope_rows = struct('channel', {}, 'n_points', {}, 'slope', {}, 'rho', {}, 'rho_p', {});
    pooled_channel = [];
    pooled_current = [];
    pooled_ratio = [];

    for c_i = 1:numel(channels_u)
        ch = channels_u(c_i);
        idx = Tcmp.channel == ch;
        cur = Tcmp.current_uA(idx);
        ratio = Tcmp.ratio_to_lowest_significant(idx);

        keep = isfinite(cur) & isfinite(ratio);
        cur = cur(keep);
        ratio = ratio(keep);
        if numel(cur) < 2
            continue;
        end

        [cur, ord] = sort(cur);
        ratio = ratio(ord);
        pf = polyfit(cur, ratio, 1);
        slope_i = pf(1);
        [rho_i, p_i] = corr(cur, ratio, 'Type', 'Spearman', 'Rows', 'complete');

        slope_rows(end+1).channel = ch; %#ok<AGROW>
        slope_rows(end).n_points = numel(cur);
        slope_rows(end).slope = slope_i;
        slope_rows(end).rho = rho_i;
        slope_rows(end).rho_p = p_i;

        pooled_channel = [pooled_channel; repmat(ch, numel(cur), 1)]; %#ok<AGROW>
        pooled_current = [pooled_current; cur(:)]; %#ok<AGROW>
        pooled_ratio = [pooled_ratio; ratio(:)]; %#ok<AGROW>
    end

    if ~isempty(slope_rows)
        Tslope = table([slope_rows.channel]', [slope_rows.n_points]', [slope_rows.slope]', [slope_rows.rho]', [slope_rows.rho_p]', ...
            'VariableNames', {'channel','n_points','slope_ratio_vs_current','spearman_rho','spearman_p'});
        writetable(Tslope, fullfile(pop_dir, 'channelwise_trend_stats.csv'));

        slopes = Tslope.slope_ratio_vs_current;
        try
            p_slopes = signrank(slopes, 0, 'tail', 'right');
        catch
            p_slopes = NaN;
        end
        frac_positive = mean(slopes > 0);

        ucur = unique(pooled_current);
        mean_ratio = nan(size(ucur));
        sem_ratio = nan(size(ucur));
        for u_i = 1:numel(ucur)
            v = pooled_ratio(pooled_current == ucur(u_i));
            mean_ratio(u_i) = mean(v, 'omitnan');
            sem_ratio(u_i) = std(v, 0, 'omitnan') / sqrt(max(1, sum(isfinite(v))));
        end

        fig_pop = figure('Visible','off', 'Color','w', 'Name', 'Population intensity trend', ...
            'Position', [140 140 780 500]);
        errorbar(ucur, mean_ratio, sem_ratio, 'o-', 'LineWidth', 1.8, 'MarkerSize', 6);
        grid on;
        xlabel('Current (uA)');
        ylabel('Normalized intensity (ratio to channel''s lowest significant current)');
        title('Population trend across channels', 'Interpreter', 'none');
        set(gca, 'XTick', ucur);
        if numel(ucur) > 1
            xlim([min(ucur)-0.2, max(ucur)+0.2]);
        end
        exportgraphics(fig_pop, fullfile(pop_dir, 'population_normalized_intensity_trend.png'), 'Resolution', 200);
        close(fig_pop);

        Tpooled = table(pooled_channel, pooled_current, pooled_ratio, ...
            'VariableNames', {'channel','current_uA','ratio_to_channel_lowest_significant'});
        writetable(Tpooled, fullfile(pop_dir, 'population_normalized_points.csv'));

        fprintf('Saved population intensity trend outputs to: %s\n', pop_dir);
    else
        fprintf('Not enough channel-wise points for population trend analysis.\n');
    end
else
    fprintf('No channels with >=2 significant currents found in selection.\n');
end

fprintf('Replots saved to: %s\n', out_dir);
