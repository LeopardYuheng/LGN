function outFile = wf_step6_retino(track, maskFile, retinoFile, subject, dateStr, outDir, cfg)
%WF_STEP6_RETINO  Step 6: align retinotopy to the stim image, you drive it.
%
%   outFile = WF_STEP6_RETINO(track, maskFile, retinoFile, subject, dateStr, outDir, cfg)
%
% Returns the path to {subject}_{date}_day_setup.mat, or '' when step 6 is
% skipped. The V1 boundary this produces is a display overlay only - step
% 5_A's dF/F values are identical with or without it.
%
% HOW THE ALIGNMENT RUNS
% ----------------------
% retino_alignment_with_brain_mask_6.m opens CPSELECT so you pick matching
% landmarks on the retinotopy reference and the stimulation-day image, and
% fits an affine from them. When it finishes, the warped visual-area
% boundaries and the V1 outline are drawn over the stimulation image and you
% are asked whether to keep the result. Choosing "Re-align" throws that
% attempt away and reopens cpselect, as many times as you like, until you
% accept it. Nothing downstream ever sees a rejected attempt.
%
% Setting cfg.retino.auto_register to true switches to the script's other
% path - imregtform proposes the affine and the nudge GUI corrects it - with
% the same accept/re-align loop around it. Manual is the default because
% multimodal registration between a retinotopy reference and a widefield
% image fails quietly often enough to be not worth the risk.
%
% THE V1 POLYGON
% --------------
% V1 is drawn in retino space once per subject and cached as
% {subject}_V1_mask_retino_master.mat. Re-aligning does not ask for it again:
% only the affine is being redone, the polygon is unchanged. A master from an
% earlier session of the same subject is copied in first, so it is normally
% drawn once ever.
%
% WHICH COPY OF STEP 6 RUNS
% -------------------------
% Always the one in analysis/longitudinal_stim_parameter_survey, for both
% tracks. The combined folder's README states step 6 is an unmodified copy,
% and the original has since gained the all-visual-areas overlay that the
% copy predates.

if nargin < 7 || isempty(cfg), cfg = wf_config(); end

outFile = '';

if ~cfg.retino.enabled
    wf_log('  step 6: disabled in config, skipping (5_A runs without a V1 overlay)');
    return;
end

if isempty(retinoFile) || exist(retinoFile, 'file') ~= 2
    wf_log('  step 6: no retinotopy file for %s, skipping', subject);
    return;
end

P       = wf_paths();
outFile = fullfile(outDir, sprintf('%s_%s_day_setup.mat', subject, dateStr));

if cfg.retino.reuse_existing && exist(outFile, 'file') == 2
    wf_log('  step 6: reusing existing day_setup (%s)', wf_short(outFile));
    return;
end

assert(exist(maskFile, 'file') == 2, 'wf_step6:noMask', ...
    'Brain mask not found:\n  %s', maskFile);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

wf_seed_v1_master(subject, outDir, cfg);

%% ---- alignment attempts ------------------------------------------------
attempt = 0;

while true
    attempt = attempt + 1;

    if exist(outFile, 'file') == 2
        delete(outFile);            % a rejected attempt is never kept
    end

    if cfg.retino.auto_register
        wf_log('  step 6: attempt %d - auto affine, then the nudge GUI', attempt);
    else
        wf_log('  step 6: attempt %d - pick matching landmarks in cpselect', attempt);
    end

    answers = wf_ans( ...
        'uigetfile', 'brain_mask',                    maskFile, ...
        'inputdlg',  'Session metadata',              {subject, dateStr}, ...
        'uigetdir',  'save day_setup',                outDir, ...
        'uigetfile', 'retino_registration_ready|retino_session_output', retinoFile);

    opts = struct('strict', cfg.strict_dialogs, 'addpath', {{P.single.functions}});

    % The script's own flags select the method. Manual (Option A) is its
    % default, so only the automatic route needs the temporary rewrite.
    if cfg.retino.auto_register
        opts.patch = { ...
            '(?m)^\s*RUN_OPTION_A\s*=\s*true\s*;.*$',  'RUN_OPTION_A = false;' ; ...
            '(?m)^\s*RUN_OPTION_B\s*=\s*false\s*;.*$', 'RUN_OPTION_B = true;'  };
    end

    wf_run_script(P.single.step6, answers, opts);

    if exist(outFile, 'file') ~= 2
        wf_log('  step 6: no day_setup was produced, skipping the V1 overlay');
        outFile = '';
        return;
    end

    if ~cfg.retino.verify
        wf_log('  step 6: saved %s (verification off)', wf_short(outFile));
        return;
    end

    action = wf_verify_alignment(outFile, subject, dateStr, attempt);

    switch action
        case 'accept'
            wf_log('  step 6: alignment accepted on attempt %d', attempt);
            wf_log('  step 6: saved %s', wf_short(outFile));
            return;

        case 'redo'
            wf_log('  step 6: alignment rejected, starting over');

        case 'skip'
            wf_log('  step 6: skipped by user, 5_A runs without a V1 overlay');
            if exist(outFile, 'file') == 2, delete(outFile); end
            outFile = '';
            return;
    end
end

end

% =====================================================================
function action = wf_verify_alignment(daySetupFile, subject, dateStr, attempt)
%WF_VERIFY_ALIGNMENT  Show the result over the stim image; keep it or redo.

S  = load(daySetupFile, 'day_setup');
ra = S.day_setup.retino_align;

stimRef = wf_gray(ra.stim_reference_image);
V1      = [];
overlay = [];
if isfield(ra, 'V1_mask_stim'),    V1      = logical(ra.V1_mask_stim);    end
if isfield(ra, 'retOverlay_stim'), overlay = logical(ra.retOverlay_stim); end

fig = figure('Name', sprintf('Step 6: check alignment - %s %s (attempt %d)', ...
                             subject, dateStr, attempt), ...
             'NumberTitle', 'off', 'Color', 'w', ...
             'Position', [110 80 1080 700], ...
             'CloseRequestFcn', @(s,e) finish('accept'));

% left: the stimulation image on its own, for comparison
ax1 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.04 0.20 0.44 0.72]);
imagesc(ax1, stimRef); colormap(ax1, gray); axis(ax1, 'image');
title(ax1, 'Stimulation-day image', 'FontSize', 11);
set(ax1, 'XTick', [], 'YTick', []);

% right: the same image with the warped retinotopy drawn over it
ax2 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.52 0.20 0.44 0.72]);
imagesc(ax2, stimRef); colormap(ax2, gray); axis(ax2, 'image'); hold(ax2, 'on');
if ~isempty(overlay) && any(overlay(:))
    ov = imagesc(ax2, cat(3, ones(size(overlay)), 0.55 * ones(size(overlay)), ...
                             zeros(size(overlay))));
    set(ov, 'AlphaData', double(imdilate(overlay, strel('disk', 1))));
end
if ~isempty(V1) && any(V1(:))
    visboundaries(ax2, V1, 'Color', [0.1 0.9 0.3], 'LineWidth', 2);
end
title(ax2, 'Aligned: visual areas (orange), V1 (green)', 'FontSize', 11);
set(ax2, 'XTick', [], 'YTick', []);
hold(ax2, 'off');

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.115 0.92 0.05], 'BackgroundColor', 'w', ...
    'FontSize', 10, 'HorizontalAlignment', 'left', ...
    'String', ['Do the visual-area boundaries sit where they should on this brain? ' ...
               'If not, re-align and pick the landmarks again - repeat as often as ' ...
               'you like, only the accepted attempt is saved.']);

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Looks right, keep it', ...
    'Units', 'normalized', 'Position', [0.04 0.03 0.24 0.07], ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'Callback', @(s,e) finish('accept'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Re-align', ...
    'Units', 'normalized', 'Position', [0.30 0.03 0.18 0.07], ...
    'FontSize', 11, 'Callback', @(s,e) finish('redo'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip step 6 for this experiment', ...
    'Units', 'normalized', 'Position', [0.68 0.03 0.28 0.07], ...
    'FontSize', 10, 'Callback', @(s,e) finish('skip'));

guidata(fig, struct('action', 'accept'));
uiwait(fig);

action = 'accept';
if ishandle(fig)
    st     = guidata(fig);
    action = st.action;
    delete(fig);
end

    function finish(act)
        if ~ishandle(fig), return; end
        guidata(fig, struct('action', act));
        uiresume(fig);
    end

end

% =====================================================================
function G = wf_gray(I)

I = double(I);
if ndims(I) == 3, I = mean(I, 3); end
lo = min(I(:));
hi = max(I(:));
if hi > lo, G = (I - lo) / (hi - lo); else, G = zeros(size(I)); end

end

% =====================================================================
function wf_seed_v1_master(subject, outDir, cfg)
%WF_SEED_V1_MASTER  Reuse this subject's V1 polygon from an earlier session.

target = fullfile(outDir, sprintf('%s_V1_mask_retino_master.mat', subject));
if exist(target, 'file') == 2, return; end

hits = wf_find_files(cfg.output_root, ...
    sprintf('%s_V1_mask_retino_master.mat', subject), 3);
if isempty(hits), return; end

d = cellfun(@(f) wf_mtime(f), hits);
[~, k] = max(d);

copyfile(hits{k}, target);
wf_log('  step 6: reusing V1 polygon from %s', wf_short(hits{k}));

end

% =====================================================================
function out = wf_find_files(root, name, maxDepth)

out = {};
if exist(root, 'dir') ~= 7 || maxDepth < 0, return; end

f = fullfile(root, name);
if exist(f, 'file') == 2, out{end+1} = f; end

listing = dir(root);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    if any(strcmp(listing(i).name, {'.', '..'})), continue; end
    out = [out, wf_find_files(fullfile(root, listing(i).name), name, maxDepth - 1)]; %#ok<AGROW>
end

end

% =====================================================================
function t = wf_mtime(f)

d = dir(f);
if isempty(d), t = 0; else, t = d(1).datenum; end

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
