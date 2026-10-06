function readyFile = wf_step_retino_combine(track, subject, dateStr, outDir, diskRoot, cfg, hintFile)
%WF_STEP_RETINO_COMBINE  Pre-step A: build retino_registration_ready.mat.
%
%   readyFile = WF_STEP_RETINO_COMBINE(track, subject, dateStr, outDir, diskRoot, cfg)
%   readyFile = WF_STEP_RETINO_COMBINE(..., cfg, hintFile)
%
% hintFile is a ready-made registration file the scanner already found for
% this experiment. It is copied in and offered for confirmation first.
%
% Runs retino_inputcombine.m, which merges azi.mat, alt.mat and
% additional_maps.mat from a retinotopy session into the single file step 6
% consumes. Returns '' when no source folder could be resolved, in which case
% step 6 is skipped and step 5_A runs without the V1 contour.
%
% HOW THE SOURCE IS FOUND
%   1  a retino_registration_ready.mat already in this experiment's folder
%   2  one already produced for this subject, anywhere under the output root
%   3  a folder on the portable disk holding all three raw map files, whose
%      path names this subject
%   4  otherwise, a folder picker opens so you can point at it yourself
%      (turn this off with cfg.retino_ask_if_missing)
%
% Whatever it finds, the maps are then shown and you confirm they are the
% right ones for THIS experiment before anything is aligned to them - see
% WF_VERIFY_RETINO_MAP for why that matters. Answering "pick a different
% folder" rebuilds from your choice and asks again.
%
% The combined file is written into outDir, so each experiment keeps its own
% copy of the retinotopy input it was analysed against.

if nargin < 6 || isempty(cfg), cfg = wf_config(); end
if nargin < 7, hintFile = ''; end

readyFile = fullfile(outDir, 'retino_registration_ready.mat');
note      = '';

%% ---- find something to show -------------------------------------------
if exist(readyFile, 'file') == 2
    wf_log('  pre-step A: found %s', wf_short(readyFile));
    note = 'Already present in this experiment''s output folder.';

elseif ~isempty(hintFile) && exist(hintFile, 'file') == 2
    if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
    copyfile(hintFile, readyFile);
    wf_log('  pre-step A: copied %s', hintFile);
    note = sprintf('Found by the disk scan: %s', hintFile);

else
    existing = wf_find_existing(subject, cfg);
    if ~isempty(existing)
        if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
        copyfile(existing, readyFile);
        wf_log('  pre-step A: copied this subject''s retinotopy from %s', wf_short(existing));
        note = sprintf('Reused from an earlier analysis: %s', existing);
    else
        srcDir = wf_find_raw_folder(subject, diskRoot, cfg);
        if isempty(srcDir)
            srcDir = wf_ask_for_folder(subject, diskRoot, cfg);
        end
        if isempty(srcDir)
            readyFile = '';
            return;
        end

        readyFile = wf_build(track, srcDir, outDir, cfg);
        if isempty(readyFile), return; end
        note = sprintf('Built from: %s', srcDir);
    end
end

%% ---- confirm it is the right map --------------------------------------
if ~cfg.retino.confirm_map
    return;
end

while true
    action = wf_verify_retino_map(readyFile, subject, dateStr, note);

    switch action
        case 'accept'
            wf_log('  pre-step A: retinotopy confirmed for %s', subject);
            return;

        case 'skip'
            wf_log('  pre-step A: retinotopy rejected, step 6 will be skipped');
            readyFile = '';
            return;

        case 'choose'
            srcDir = wf_ask_for_folder(subject, diskRoot, cfg);
            if isempty(srcDir)
                wf_log('  pre-step A: no folder chosen, step 6 will be skipped');
                readyFile = '';
                return;
            end
            built = wf_build(track, srcDir, outDir, cfg);
            if isempty(built)
                readyFile = '';
                return;
            end
            readyFile = built;
            note      = sprintf('Rebuilt from: %s', srcDir);
    end
end

end

% =====================================================================
function d = wf_ask_for_folder(subject, diskRoot, cfg)
%WF_ASK_FOR_FOLDER  Folder picker for the three raw retinotopy map files.

d = '';

if ~cfg.retino_ask_if_missing
    wf_log('  pre-step A: no retinotopy for %s and asking is off, skipping step 6', subject);
    return;
end

start = diskRoot;
if isempty(start) || exist(start, 'dir') ~= 7, start = pwd; end

picked = uigetdir(start, sprintf( ...
    ['%s: select the retinotopy folder (azi.mat, alt.mat, ' ...
     'additional_maps.mat) - Cancel to skip step 6'], subject));

if isequal(picked, 0)
    wf_log('  pre-step A: no folder selected, step 5_A will run without a V1 overlay');
    return;
end

missing = {};
for i = 1:numel(cfg.retino_raw_files)
    if exist(fullfile(picked, cfg.retino_raw_files{i}), 'file') ~= 2
        missing{end+1} = cfg.retino_raw_files{i}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    uiwait(msgbox(sprintf(['That folder is missing %s.\n\n%s\n\nPick a folder ' ...
        'holding all three map files.'], strjoin(missing, ', '), picked), ...
        'Retinotopy folder', 'warn', 'modal'));
    d = wf_ask_for_folder(subject, diskRoot, cfg);
    return;
end

d = picked;

end

% =====================================================================
function readyFile = wf_build(track, srcDir, outDir, cfg)
%WF_BUILD  Run retino_inputcombine.m on srcDir, writing into outDir.

P         = wf_paths();
readyFile = fullfile(outDir, 'retino_registration_ready.mat');

if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

answers = wf_ans( ...
    'uigetdir', 'contains the alt\.mat, azi\.mat',      srcDir, ...
    'uigetdir', 'output folder for retino_registration', outDir);

wf_log('  pre-step A: combining retinotopy maps from %s', srcDir);
wf_run_script(P.(track).retinocombine, answers, struct('strict', cfg.strict_dialogs));

if exist(readyFile, 'file') ~= 2
    wf_log('  pre-step A: retino_inputcombine produced no output, skipping step 6');
    readyFile = '';
    return;
end

wf_log('  pre-step A: saved %s', wf_short(readyFile));

end

% =====================================================================
function f = wf_find_existing(subject, cfg)
%WF_FIND_EXISTING  A combined file this subject already has, most recent wins.

f = '';
hits = wf_search(cfg.output_root, cfg.retino_pattern, 3);

if ~isempty(cfg.retino_root)
    hits = [hits, wf_search(cfg.retino_root, cfg.retino_pattern, 3)];
end
if isempty(hits), return; end

mine = hits(~cellfun(@isempty, regexpi(hits, subject, 'once')));
if isempty(mine), return; end        % never borrow another subject's maps

d = cellfun(@wf_mtime, mine);
[~, k] = max(d);
f = mine{k};

end

% =====================================================================
function d = wf_find_raw_folder(subject, diskRoot, cfg)
%WF_FIND_RAW_FOLDER  Folder holding all three raw retinotopy map files.
%
% The folder's path must name this subject. A retinotopy map belongs to one
% animal: silently handing LGN24 the only retinotopy folder on the disk,
% which happens to be LGN26's, would corrupt every V1 boundary downstream
% while looking perfectly normal. When nothing names this subject we return
% empty and let the folder picker decide, which keeps the choice explicit.

d = '';
if isempty(diskRoot) || exist(diskRoot, 'dir') ~= 7, return; end

cands = wf_folders_with(diskRoot, cfg.retino_raw_files, cfg.scan_max_depth + 1);
if isempty(cands)
    wf_log('  pre-step A: no folder on the disk holds %s', ...
        strjoin(cfg.retino_raw_files, ' + '));
    return;
end

mine = cands(~cellfun(@isempty, regexpi(cands, subject, 'once')));

if isempty(mine)
    wf_log(['  pre-step A: %d retinotopy folder(s) on the disk, none naming %s ' ...
            '- not guessing'], numel(cands), subject);
    return;
end

d = wf_newest(mine);
if numel(mine) > 1
    wf_log('  pre-step A: %d folders name %s, using the most recent (%s)', ...
        numel(mine), subject, d);
end

end

% =====================================================================
function out = wf_folders_with(root, names, depth)

out = {};
if depth < 0 || exist(root, 'dir') ~= 7, return; end

haveAll = true;
for i = 1:numel(names)
    if exist(fullfile(root, names{i}), 'file') ~= 2
        haveAll = false;
        break;
    end
end
if haveAll
    out = {root};
    return;
end

listing = dir(root);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    n = listing(i).name;
    if any(strcmp(n, {'.', '..'})) || strncmp(n, '$', 1) || strncmp(n, '.', 1)
        continue;
    end
    out = [out, wf_folders_with(fullfile(root, n), names, depth - 1)]; %#ok<AGROW>
end

end

% =====================================================================
function out = wf_search(root, pattern, depth)

out = {};
if depth < 0 || exist(root, 'dir') ~= 7, return; end

hits = dir(fullfile(root, pattern));
hits = hits(~[hits.isdir]);
for i = 1:numel(hits)
    out{end+1} = fullfile(root, hits(i).name); %#ok<AGROW>
end

listing = dir(root);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    n = listing(i).name;
    if any(strcmp(n, {'.', '..'})) || strncmp(n, '$', 1), continue; end
    out = [out, wf_search(fullfile(root, n), pattern, depth - 1)]; %#ok<AGROW>
end

end

% =====================================================================
function d = wf_newest(paths)

t = cellfun(@wf_mtime, paths);
[~, k] = max(t);
d = paths{k};

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
