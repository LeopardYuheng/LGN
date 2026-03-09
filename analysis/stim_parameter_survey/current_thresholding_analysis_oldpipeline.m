%% current_thresholding_analysis
% For each stim channel:
%   FIXED ROI ONLY:
%     - ROI defined once from anchor current (default: max current)
%     - same ROI used for all currents
% Outputs per channel:
%   - curve plot + threshold line
%   - per-channel .mat with scalars, p-values, CI, ROI center
%
% Retino/V1 restriction: uses analysis_mask = final_mask & V1_mask_stim (if provided)

close all; clc; clear; fclose('all');

%% -------------------------
% USER SELECT FILES
% -------------------------
[fn, fp] = uigetfile('*.mat', 'Select .mat file containing extracted stim and camera trigger times (contains out)');
if isequal(fn,0), error('No .mat selected.'); end
R = load(fullfile(fp, fn));
assert(isfield(R,'out'), 'Selected .mat must contain struct variable "out".');
out = R.out;

assert(isfield(out,'img_dir') && exist(out.img_dir,'dir')==7, 'out.img_dir missing or not found on disk.');
assert(isfield(out,'trial_onset_frame_idx'), 'out.trial_onset_frame_idx missing.');
assert(isfield(out,'trial_maps'), 'out.trial_maps missing.');
assert(isfield(out,'Freq') && out.Freq > 0, 'out.Freq missing/invalid.');
assert(isfield(out,'before_time') && isfield(out,'after_time'), 'out.before_time/out.after_time missing.');
assert(isfield(out,'resp_win'), 'out.resp_win missing.');

[mask_name, mask_path] = uigetfile('*.mat', 'Select reference_mask.mat (contains final_mask, optional crop_rect)');
if isequal(mask_name,0), error('No mask selected.'); end
S = load(fullfile(mask_path, mask_name));
assert(isfield(S,'final_mask'), 'Mask file must contain final_mask.');
final_mask = logical(S.final_mask);
if isfield(S,'crop_rect'), crop_rect = S.crop_rect; else, crop_rect = []; end

% Optional V1 mask in stim space
USE_V1_MASK = true;
V1_mask_stim = true(size(final_mask));
v1_file = "";
[v1_name, v1_path] = uigetfile('*.mat', 'Select V1_mask_stim_option.mat (Cancel to skip)');
if ~isequal(v1_name,0)
    v1_file = fullfile(v1_path, v1_name);
    V1_mask_stim = load_v1_mask_stim(v1_file);
    assert(isequal(size(V1_mask_stim), size(final_mask)), 'V1_mask_stim size mismatch.');
else
    USE_V1_MASK = false;
    V1_mask_stim = true(size(final_mask));
end

analysis_mask = final_mask & logical(V1_mask_stim);
assert(nnz(analysis_mask) > 0, 'analysis_mask is empty (final_mask & V1_mask).');

% CSV mapping
[csv_name, csv_path] = uigetfile({'*.csv;*.txt','CSV or TXT (*.csv, *.txt)'}, ...
    'Select CSV: trial_index, stim_chan, current_uA');
if isequal(csv_name,0), error('No CSV selected.'); end
csv_file = fullfile(csv_path, csv_name);
Tcsv = readtable(csv_file);

save_root = uigetdir(pwd, 'Select OUTPUT folder to save batch results');
if isequal(save_root,0), save_root = pwd; end
out_dir = fullfile(save_root, 'autoROI_threshold_fixed_only');
if exist(out_dir,'dir')~=7, mkdir(out_dir); end

%% -------------------------
% USER PARAMS
% -------------------------
roi_radius_px = input('Enter ROI radius (pixels): ');
assert(isfinite(roi_radius_px) && roi_radius_px > 0, 'ROI radius must be > 0.');

polarity = 'pos';                % 'pos' or 'neg'
response_metric = 'mean_respwin';% 'mean_respwin' or 'peak_respwin'

ANCHOR_RULE = 'max_current';     % 'max_current' or 'user_value'
ANCHOR_CURRENT_VALUE = NaN;      % only used if user_value

% Significance rule
alpha = 0.05;
use_ci_rule = true;   % true: CI_low > 0, false: p < alpha
z = 1.96;             % 95% CI approx

SAVE_PER_CHANNEL_FIGS = true;
SAVE_MASTER_SUMMARY   = true;

%% -------------------------
% Time indices
% -------------------------
Freq      = out.Freq;
before_s  = out.before_time;
after_s   = out.after_time;
resp_win  = out.resp_win;

preFrames  = round(before_s * Freq);
postFrames = round(after_s  * Freq);
L          = preFrames + postFrames + 1;

t = ((0:L-1)/Freq) - before_s;
base_idx = 1:preFrames;
resp_idx = find(t >= resp_win(1) & t <= resp_win(2));
assert(~isempty(base_idx), 'Baseline window too short.');
assert(~isempty(resp_idx), 'resp_win yields no frames.');

%% -------------------------
% Load & sort TIFF files
% -------------------------
img_dir = out.img_dir;
image_files = dir(fullfile(img_dir, '*.tif'));
assert(~isempty(image_files), 'No .tif files found in %s', img_dir);

nFiles = numel(image_files);
nums = nan(nFiles,1);
for i = 1:nFiles
    tok = regexp(image_files(i).name, '(\d+)\.tif$', 'tokens', 'once');
    assert(~isempty(tok), 'Filename "%s" has no trailing numeric index.', image_files(i).name);
    nums(i) = str2double(tok{1});
end
[~, ord] = sort(nums);
image_files = image_files(ord);

onsets = double(out.trial_onset_frame_idx(:));
max_onset = max(onsets(isfinite(onsets)));
max_needed = min(max_onset + postFrames, numel(image_files));
image_files = image_files(1:max_needed);

img1 = imread(fullfile(img_dir, image_files(1).name));
if ~isempty(crop_rect), img1 = imcrop(img1, crop_rect); end
[H,W] = size(img1);
assert(all(size(final_mask)==[H W]), 'final_mask size mismatch TIFF size.');
assert(all(size(analysis_mask)==[H W]), 'analysis_mask size mismatch TIFF size.');

[XX,YY] = meshgrid(1:W, 1:H);

%% -------------------------
% Parse CSV mapping
% -------------------------
vars = lower(string(Tcsv.Properties.VariableNames));
col_trial = find(vars=="trial_index" | vars=="trial" | vars=="trial_idx", 1);
col_chan  = find(vars=="stim_chan" | vars=="channel" | vars=="stim_channel" | vars=="stimchan", 1);
col_curr  = find(vars=="current_ua" | vars=="current" | vars=="currentlevel" | vars=="current_level", 1);

assert(~isempty(col_trial), 'CSV must contain trial_index column.');
assert(~isempty(col_chan),  'CSV must contain stim_chan column.');
assert(~isempty(col_curr),  'CSV must contain current_uA column.');

trial_index_csv = double(Tcsv{:, col_trial});
stim_chan_csv   = double(Tcsv{:, col_chan});
current_uA_csv  = double(Tcsv{:, col_curr});

keep = isfinite(trial_index_csv) & isfinite(stim_chan_csv) & isfinite(current_uA_csv);
trial_index_csv = trial_index_csv(keep);
stim_chan_csv   = stim_chan_csv(keep);
current_uA_csv  = current_uA_csv(keep);

Ntr = size(out.trial_maps, 3);
trial_stim_chan   = nan(Ntr,1);
trial_current_uA  = nan(Ntr,1);

if all(ismember(1:Ntr, trial_index_csv))
    [~, ia] = unique(trial_index_csv, 'stable');
    ti = trial_index_csv(ia);
    ch = stim_chan_csv(ia);
    cu = current_uA_csv(ia);
    trial_stim_chan(ti)  = ch;
    trial_current_uA(ti) = cu;
    fprintf('Mapped CSV by trial_index.\n');
else
    M = min(numel(stim_chan_csv), Ntr);
    trial_stim_chan(1:M)  = stim_chan_csv(1:M);
    trial_current_uA(1:M) = current_uA_csv(1:M);
    warning('Mapped CSV by row order for first %d trials.', M);
end

ch_list = unique(trial_stim_chan(isfinite(trial_stim_chan)));
ch_list = sort(ch_list(:));
fprintf('Found %d channels.\n', numel(ch_list));

%% -------------------------
% Run fixed ROI per channel
% -------------------------
master = struct();
master.meta.session_mat = fullfile(fp, fn);
master.meta.csv_file = csv_file;
master.meta.mask_file = fullfile(mask_path, mask_name);
master.meta.v1_mask_file = v1_file;
master.meta.roi_radius_px = roi_radius_px;
master.meta.polarity = polarity;
master.meta.response_metric = response_metric;
master.meta.resp_win = resp_win;
master.meta.threshold_rule = ternary(use_ci_rule,'CI_low>0','p<alpha');
master.meta.alpha = alpha;

chan_res = cell(numel(ch_list), 1);

roi_overlay = struct();
roi_overlay.ch   = [];
roi_overlay.mask = {};
roi_overlay.center_xy = [];
roi_overlay.anchor_current = [];

for c = 1:numel(ch_list)
    CH = ch_list(c);

    sel = (trial_stim_chan == CH) & isfinite(trial_current_uA) & isfinite(out.trial_onset_frame_idx(:));
    trial_idx_sel = find(sel);
    curr_sel = trial_current_uA(sel);

    if isempty(trial_idx_sel)
        continue;
    end

    uCurr = unique(curr_sel); uCurr = sort(uCurr(:));
    if ~any(uCurr==0)
        fprintf('[%d/%d] ch%03d skipped (no 0 uA)\n', c, numel(ch_list), CH);
        continue;
    end

    % anchor current
    if strcmpi(ANCHOR_RULE,'max_current')
        anchor_current = max(uCurr);
    else
        anchor_current = ANCHOR_CURRENT_VALUE;
        if ~ismember(anchor_current, uCurr)
            fprintf('[%d/%d] ch%03d skipped (anchor %.4g not present)\n', c, numel(ch_list), CH, anchor_current);
            continue;
        end
    end

    % --- compute anchor ROI center from mean map at anchor current ---
    idx_anchor = trial_idx_sel(curr_sel == anchor_current);
    mean_map_anchor = mean(out.trial_maps(:,:,idx_anchor), 3, 'omitnan');
    tmpA = mean_map_anchor;
    tmpA(~analysis_mask) = NaN;

    switch polarity
        case 'pos', [~, linA] = max(tmpA(:));
        case 'neg', [~, linA] = min(tmpA(:));
        otherwise, error('polarity must be pos/neg');
    end
    [ay, ax] = ind2sub([H W], linA);
    anchor_center = [ax ay];

    roi_mask = ((XX - ax).^2 + (YY - ay).^2) <= roi_radius_px^2;
    roi_mask = roi_mask & analysis_mask;

    % --- store for final ROI overlay ---
    roi_overlay.ch(end+1,1) = CH;
    roi_overlay.mask{end+1,1} = roi_mask;
    roi_overlay.center_xy(end+1,:) = [ax ay];
    roi_overlay.anchor_current(end+1,1) = anchor_current;

    if nnz(roi_mask)==0
        fprintf('[%d/%d] ch%03d skipped (anchor ROI empty)\n', c, numel(ch_list), CH);
        continue;
    end

    % --- per current: compute FIXED ROI scalars ---
    nC = numel(uCurr);
    trial_scalar = cell(nC,1);
    m = nan(nC,1);
    s = nan(nC,1);
    ntr = zeros(nC,1);

    for i = 1:nC
        cu = uCurr(i);
        idx_curr = trial_idx_sel(curr_sel == cu);
        ntr(i) = numel(idx_curr);
        if ntr(i) < 1, continue; end

        scal = nan(ntr(i),1);
        for k = 1:ntr(i)
            tr = idx_curr(k);
            f0 = double(out.trial_onset_frame_idx(tr));
            dff_t = trial_roi_dff(f0, roi_mask, img_dir, image_files, crop_rect, preFrames, postFrames, L, base_idx);
            x = dff_t(resp_idx);
            scal(k) = summarize_resp(x, response_metric, polarity);
        end

        trial_scalar{i} = scal;
        m(i) = mean(scal, 'omitnan');
        s(i) = std(scal, 0, 'omitnan');
    end

    % --- significance vs 0 ---
    [sig, p_vs0, ci_diff, thresh_uA] = sig_vs0(uCurr, trial_scalar, alpha, use_ci_rule, z);

    % --- plot ---
    if SAVE_PER_CHANNEL_FIGS
        fig = figure('Visible','off','Color','w'); hold on;

        [x_all, y_all, x_jit] = make_scatter(uCurr, trial_scalar);
        plot(x_jit, y_all, '.', 'MarkerSize', 10, 'DisplayName','Trials (fixed ROI)');

        errorbar(uCurr, m, s, 'o-', 'LineWidth', 1.6, 'MarkerSize', 5, ...
            'DisplayName','Mean±std (fixed ROI)');

        xlabel('Current (\muA)');
        ylabel(sprintf('ROI scalar (%s)', response_metric));
        title(sprintf('ch%03d | FIXED ROI r=%gpx | anchor=%.4g | rule=%s', ...
            CH, roi_radius_px, anchor_current, ternary(use_ci_rule,'CI_low>0','p<alpha')), ...
            'Interpreter','none');
        grid on;

        yl = ylim;
        if isfinite(thresh_uA)
            plot([thresh_uA thresh_uA], yl, 'k--', 'LineWidth', 1.2, ...
                'DisplayName', sprintf('Threshold=%.4g uA', thresh_uA));
        end
        ylim(yl);

        legend('Location','bestoutside');
        hold off;

        exportgraphics(fig, fullfile(out_dir, sprintf('ch%03d_fixed_threshold.png', CH)), 'Resolution', 220);
        close(fig);
    end

    % --- save per-channel mat ---
    cres = struct();
    cres.chan = CH;
    cres.uCurr = uCurr;
    cres.ntr = ntr;

    cres.anchor_current = anchor_current;
    cres.roi_center_xy = anchor_center;

    cres.fixed.trial_scalar = trial_scalar;
    cres.fixed.mean = m;
    cres.fixed.std  = s;
    cres.fixed.sig  = sig;
    cres.fixed.p_vs0 = p_vs0;
    cres.fixed.ci_diff = ci_diff;
    cres.fixed.threshold_uA = thresh_uA;

    save(fullfile(out_dir, sprintf('ch%03d_fixed_results.mat', CH)), 'cres', '-v7.3');

    chan_res{c} = cres;

    fprintf('[%d/%d] ch%03d done | thresh=%s\n', ...
        c, numel(ch_list), CH, ...
        ternary(isfinite(thresh_uA), sprintf('%.4g', thresh_uA), 'NaN'));
end

master.chan_res = chan_res;

if SAVE_MASTER_SUMMARY
    save(fullfile(out_dir, 'MASTER_fixed_all_channels.mat'), 'master', '-v7.3');
end

fprintf('\nDONE.\nSaved to: %s\n', out_dir);

%% -------------------------
% FINAL A: Color-coded ROI outlines + legend + V1 mask
% -------------------------
if ~isempty(roi_overlay.ch)

    base = imread(fullfile(img_dir, image_files(1).name));
    if ~isempty(crop_rect), base = imcrop(base, crop_rect); end
    base = mat2gray(base);

    figO = figure('Color','w');
    imshow(base, []); hold on;

    % --- V1 boundary (on top of image, under ROI outlines) ---
    if exist('V1_mask_stim','var') && ~isempty(V1_mask_stim)
        visboundaries(logical(V1_mask_stim), 'Color','y', 'LineWidth', 2);
    end

    % (optional) analysis mask boundary too
    if exist('analysis_mask','var') && ~isempty(analysis_mask)
        visboundaries(logical(analysis_mask), 'Color',[0 1 1], 'LineWidth', 1); % cyan
    end

    nR = numel(roi_overlay.ch);

    % Generate N distinct colors
    cmap = hsv(nR);   % good for many categories
    
    % Optional: shuffle so similar hues aren't next to each other
    rng(0);  % reproducible
    cmap = cmap(randperm(nR), :);
    
    % Optional: avoid very bright/yellow colors (hard to see)
    cmap = 0.85 * cmap + 0.15;  % desaturate slightly

    h = gobjects(nR,1);
    legtxt = strings(nR,1);

    for k = 1:nR
        mk = roi_overlay.mask{k};
        B = bwboundaries(mk);
        if isempty(B), continue; end

        for b = 1:numel(B)
            bb = B{b};
            h(k) = plot(bb(:,2), bb(:,1), '-', 'LineWidth', 2, 'Color', cmap(k,:));
        end
        legtxt(k) = sprintf('ch%03d', roi_overlay.ch(k));
    end

    title(sprintf('Fixed ROIs + V1 boundary | r=%g px', roi_radius_px), 'Interpreter','none');

    good = isgraphics(h);
    legend(h(good), legtxt(good), 'Location','eastoutside');

    out_png = fullfile(out_dir, 'ALL_CHANNELS_fixedROI_overlay_colorLegend_V1.png');
    exportgraphics(figO, out_png, 'Resolution', 240);
    close(figO);

    fprintf('Saved overlay+V1:\n  %s\n', out_png);
end

%% -------------------------
% FINAL: Overlay ONLY channels that pass threshold
% -------------------------
if ~isempty(roi_overlay.ch)

    % Identify which channels have a valid threshold
    nR = numel(roi_overlay.ch);
    keep = false(nR,1);

    for k = 1:nR
        % match channel to stored results
        ch = roi_overlay.ch(k);

        % find corresponding cres in chan_res
        found = false;
        for c = 1:numel(chan_res)
            if isempty(chan_res{c}), continue; end
            if chan_res{c}.chan == ch
                found = true;

                % ---- choose mode ----
                thresh = chan_res{c}.fixed.threshold_uA;  % FIXED ROI
                % thresh = chan_res{c}.peak.threshold_uA; % if you want peak mode

                if isfinite(thresh)
                    keep(k) = true;
                end
                break;
            end
        end

        if ~found
            warning('Channel %d not found in chan_res', ch);
        end
    end

    fprintf('Keeping %d / %d channels with valid threshold\n', sum(keep), nR);

    % --- Base image ---
    base = imread(fullfile(img_dir, image_files(1).name));
    if ~isempty(crop_rect), base = imcrop(base, crop_rect); end
    base = mat2gray(base);

    fig = figure('Color','w');
    imshow(base, []); hold on;

    % --- V1 boundary ---
    if exist('V1_mask_stim','var') && ~isempty(V1_mask_stim)
        visboundaries(logical(V1_mask_stim), 'Color','y', 'LineWidth', 2);
    end

    % --- Colors ---
    idx_keep = find(keep);
    nK = numel(idx_keep);

    cmap = hsv(nK);
    cmap = cmap(randperm(nK), :);  % shuffle

    h = gobjects(nK,1);
    legtxt = strings(nK,1);

    % --- Plot only kept ROIs ---
    for i = 1:nK
        k = idx_keep(i);
        mk = roi_overlay.mask{k};

        B = bwboundaries(mk);
        if isempty(B), continue; end

        for b = 1:numel(B)
            bb = B{b};
            h(i) = plot(bb(:,2), bb(:,1), '-', ...
                'LineWidth', 2.5, ...
                'Color', cmap(i,:));
        end

        legtxt(i) = sprintf('ch%03d', roi_overlay.ch(k));
    end

    title(sprintf('Responsive ROIs (threshold passed) | r=%g px | n=%d', ...
        roi_radius_px, nK), 'Interpreter','none');

    legend(h, legtxt, 'Location','eastoutside');

    out_png = fullfile(out_dir, 'RESPONSIVE_CHANNELS_fixedROI_overlay.png');
    exportgraphics(fig, out_png, 'Resolution', 240);
    close(fig);

    fprintf('Saved responsive overlay:\n  %s\n', out_png);
end



%% ===================== LOCAL FUNCTIONS =====================

function v1 = load_v1_mask_stim(v1_file)
    T = load(v1_file);
    f = fieldnames(T);
    pick = "";
    for k = 1:numel(f)
        if contains(lower(f{k}), "v1") && contains(lower(f{k}), "mask")
            pick = f{k};
            break;
        end
    end
    assert(pick~="", 'Could not find V1 mask variable in %s', v1_file);
    v1 = logical(T.(pick));
end

function y = summarize_resp(x, response_metric, polarity)
    switch response_metric
        case 'mean_respwin'
            y = mean(x, 'omitnan');
        case 'peak_respwin'
            if strcmpi(polarity,'pos')
                y = max(x);
            else
                y = min(x);
            end
        otherwise
            error('Unknown response_metric: %s', response_metric);
    end
end

function [sig, p_vs0, ci_diff, thresh_uA] = sig_vs0(uCurr, trial_scalar, alpha, use_ci_rule, z)
    nC = numel(uCurr);
    sig = false(nC,1);
    p_vs0 = nan(nC,1);
    ci_diff = nan(nC,2);

    i0 = find(uCurr==0, 1);
    y0 = trial_scalar{i0};
    y0 = y0(isfinite(y0));
    if numel(y0) < 2
        thresh_uA = NaN;
        return;
    end

    for i = 1:nC
        if uCurr(i)==0, continue; end
        y = trial_scalar{i};
        y = y(isfinite(y));
        if numel(y) < 2, continue; end

        [~, p] = ttest2(y, y0, 'Vartype','unequal', 'Alpha', alpha);
        p_vs0(i) = p;

        m1 = mean(y);  s1 = std(y);  n1 = numel(y);
        m2 = mean(y0); s2 = std(y0); n2 = numel(y0);

        d = m1 - m2;
        se = sqrt((s1^2)/n1 + (s2^2)/n2);
        ci = [d - z*se, d + z*se];
        ci_diff(i,:) = ci;

        if use_ci_rule
            sig(i) = (ci(1) > 0);
        else
            sig(i) = (p < alpha);
        end
    end

    thresh_uA = NaN;
    cand = uCurr(sig);
    if ~isempty(cand), thresh_uA = min(cand); end
end

function [x_all, y_all, x_jit] = make_scatter(uCurr, trial_scalar)
    x_all = [];
    y_all = [];
    for i = 1:numel(uCurr)
        y = trial_scalar{i};
        if isempty(y), continue; end
        y = y(:);
        x = uCurr(i) * ones(size(y));
        x_all = [x_all; x]; %#ok<AGROW>
        y_all = [y_all; y]; %#ok<AGROW>
    end
    keep = isfinite(y_all) & isfinite(x_all);
    x_all = x_all(keep);
    y_all = y_all(keep);
    jit = 0.06;
    x_jit = x_all + (rand(size(x_all)) - 0.5) * 2 * jit;
end

function dff_t = trial_roi_dff(f0, roi_mask, img_dir, image_files, crop_rect, preFrames, postFrames, L, base_idx)
    f0 = double(f0);
    f_start = f0 - preFrames;
    f_end   = f0 + postFrames;

    if f_start < 1 || f_end > numel(image_files)
        error('Trial frames out of bounds: f_start=%d, f_end=%d, nFiles=%d', ...
              f_start, f_end, numel(image_files));
    end

    roi_mask = logical(roi_mask);
    if nnz(roi_mask) == 0, error('ROI mask is empty.'); end

    raw = nan(L,1,'single');

    kk = 0;
    for f = f_start:f_end
        kk = kk + 1;
        img = imread(fullfile(img_dir, image_files(f).name));
        if ~isempty(crop_rect), img = imcrop(img, crop_rect); end
        img = single(img);
        raw(kk) = mean(img(roi_mask), 'omitnan');
    end

    F0 = mean(raw(base_idx), 'omitnan');
    dff_t = (raw - F0) ./ F0;
    dff_t = double(dff_t);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
