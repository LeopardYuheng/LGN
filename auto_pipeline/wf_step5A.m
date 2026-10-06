function outDir = wf_step5A(track, dayPointers, maskFile, daySetupFile, outDir, cfg)
%WF_STEP5A  Step 5_A: whole-brain dF/F movies with a per-trial baseline.
%
%   outDir = WF_STEP5A(track, dayPointers, maskFile, daySetupFile, outDir, cfg)
%
% dayPointers is a cellstr. One entry on the single-session track; three (in
% session order) on the combined track, where every condition's trials are
% pooled across sessions before averaging.
%
% daySetupFile is the step 6 output used for the optional V1 contour. Pass ''
% to run without the overlay - the dF/F result itself is identical either
% way, V1 is drawn for display only.
%
% Produces, under outDir, one subfolder per channel-current condition
% containing the per-trial movies, the trial-averaged movie and the
% frame-grid figure.

if nargin < 6 || isempty(cfg), cfg = wf_config(); end
if nargin <  4, daySetupFile = ''; end

P = wf_paths();

if ischar(dayPointers), dayPointers = {dayPointers}; end
assert(~isempty(dayPointers), 'wf_step5A:noPointers', 'No day pointer supplied.');

for i = 1:numel(dayPointers)
    assert(exist(dayPointers{i}, 'file') == 2, 'wf_step5A:noPointer', ...
        'Day pointer %d not found:\n  %s', i, dayPointers{i});
end
assert(exist(maskFile, 'file') == 2, 'wf_step5A:noMask', ...
    'Brain mask not found:\n  %s', maskFile);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

if cfg.resume && wf_step5A_complete(outDir)
    wf_log('  step 5A: already done (%d condition folder(s) present)', ...
        numel(wf_condition_dirs(outDir)));
    return;
end

% ---- video export selection --------------------------------------------
vidSel = [];
if cfg.video_per_trial, vidSel(end+1) = 1; end
if cfg.video_mean,      vidSel(end+1) = 2; end
if isempty(vidSel), vidSel = 0; end          % 0 = press "Skip videos"

% ---- condition selection ------------------------------------------------
condPick = wf_condition_picker(cfg.conditions);

% ---- answer table -------------------------------------------------------
answers = wf_ans( ...
    'uigetdir', 'output folder for dF/F movies', outDir, ...
    'listdlg',  'Export dF/F movies as video',   vidSel);

if strcmp(track, 'combined')
    answers(end+1) = struct('kind', 'inputdlg', ...
                            'pattern', 'How many sessions to combine', ...
                            'value', {{num2str(numel(dayPointers))}});
end

for i = 1:numel(dayPointers)
    answers(end+1) = struct('kind', 'uigetfile', ...
                            'pattern', 'select day pointer', ...
                            'value', dayPointers{i}); %#ok<AGROW>
end

answers(end+1) = struct('kind', 'uigetfile', 'pattern', 'brain_mask', 'value', maskFile);

if isempty(daySetupFile) || exist(daySetupFile, 'file') ~= 2
    v1val = 0;                     % press Cancel: run without the V1 overlay
    wf_log('  step 5A: no V1 overlay (step 6 output not available)');
else
    v1val = daySetupFile;
end
answers(end+1) = struct('kind', 'uigetfile', 'pattern', 'V1 boundary', 'value', v1val);

answers(end+1) = struct('kind', 'inputdlg', 'pattern', 'Frame-grid display window', ...
    'value', {{num2str(cfg.display_tmin), num2str(cfg.display_tmax)}});

answers(end+1) = struct('kind', 'listdlg', 'pattern', 'Select conditions to analyze', ...
    'value', condPick);

wf_log('  step 5A: computing dF/F movies (%d session(s), conditions: %s)', ...
    numel(dayPointers), wf_conditions_label(cfg.conditions));

wf_run_script(P.(track).step5A, answers, ...
    struct('strict', cfg.strict_dialogs, 'addpath', {{P.(track).functions}}));

dirs = wf_condition_dirs(outDir);
assert(~isempty(dirs), 'wf_step5A:noOutput', ...
    'Step 5_A finished but produced no condition folders under:\n  %s', outDir);
wf_log('  step 5A: %d condition folder(s) written to %s', numel(dirs), outDir);

end

% =====================================================================
function pick = wf_condition_picker(spec)
%WF_CONDITION_PICKER  Turn cfg.conditions into a listdlg answer.
%
% The dialog lists entries formatted 'Ch %d  |  %g uA', sorted by channel
% then current. 'all' selects every row; a {channel, current} table selects
% only the rows that match, and complains about any pair that is not offered.

if ischar(spec) && strcmpi(spec, 'all')
    pick = @(items) 1:numel(items);
    return;
end

assert(iscell(spec) && size(spec, 2) == 2, 'wf_step5A:badConditions', ...
    'cfg.conditions must be ''all'' or an n-by-2 cell of {channel, current}.');

wanted = cell2mat(spec);

pick = @(items) wf_match_conditions(items, wanted);

end

% =====================================================================
function idx = wf_match_conditions(items, wanted)

n  = numel(items);
ch = nan(n, 1);
cu = nan(n, 1);

for i = 1:n
    tok = regexp(char(string(items{i})), ...
        'Ch\s*(-?\d+)\s*\|\s*(-?[\d.]+)\s*uA', 'tokens', 'once');
    if ~isempty(tok)
        ch(i) = str2double(tok{1});
        cu(i) = str2double(tok{2});
    end
end

idx = [];
missing = {};
for r = 1:size(wanted, 1)
    hit = find(ch == wanted(r,1) & abs(cu - wanted(r,2)) < 1e-9);
    if isempty(hit)
        missing{end+1} = sprintf('ch%d %g uA', wanted(r,1), wanted(r,2)); %#ok<AGROW>
    else
        idx = [idx, hit(:)']; %#ok<AGROW>
    end
end

assert(~isempty(idx), 'wf_step5A:noMatchingConditions', ...
    'None of the requested conditions exist in this day pointer. Requested: %s', ...
    strjoin(missing, ', '));

if ~isempty(missing)
    warning('wf_step5A:someConditionsMissing', ...
        'These requested conditions are not in this day pointer and were skipped: %s', ...
        strjoin(missing, ', '));
end

idx = unique(idx, 'stable');

end

% =====================================================================
function d = wf_condition_dirs(outDir)

if exist(outDir, 'dir') ~= 7, d = {}; return; end
listing = dir(fullfile(outDir, 'ch*uA'));
listing = listing([listing.isdir]);
d = {listing.name};

end

% =====================================================================
function tf = wf_step5A_complete(outDir)
%WF_STEP5A_COMPLETE  Treat 5_A as done only if every condition folder holds a
% trial-averaged movie, so a run killed mid-condition is redone.

dirs = wf_condition_dirs(outDir);
if isempty(dirs), tf = false; return; end

tf = true;
for i = 1:numel(dirs)
    if isempty(dir(fullfile(outDir, dirs{i}, 'mean_dff_*.mat')))
        tf = false;
        return;
    end
end

end

% =====================================================================
function s = wf_conditions_label(spec)

if ischar(spec), s = spec; else, s = sprintf('%d selected', size(spec, 1)); end

end
