function [experiments, problems] = wf_scan_disk(diskRoot, cfg)
%WF_SCAN_DISK  Find every imaging experiment on the portable disk.
%
%   [experiments, problems] = WF_SCAN_DISK(diskRoot, cfg)
%
% Walks the disk for folders of numbered TIFFs, pairs each with the nearest
% .nev and trial CSV, reads the subject and date out of the folder names, and
% groups sessions that share a subject and date into one experiment. An
% experiment with one session runs down the single-session pipeline; one with
% two or more runs down the combined pipeline that pools their trials.
%
% If sessions.csv exists at the disk root it is read first and its rows take
% precedence, so anything the scanner gets wrong can be pinned down by hand
% without changing code.
%
% OUTPUTS
%   experiments  struct array, one per subject+date
%     .subject .date .track .sessions .out_dir .retino .ok .notes
%   problems     cellstr describing every session that could not be resolved

if nargin < 2 || isempty(cfg), cfg = wf_config(); end

experiments = wf_empty_experiments();
problems    = {};

scanRoot = diskRoot;
if ~isempty(cfg.disk_subfolder)
    scanRoot = fullfile(diskRoot, cfg.disk_subfolder);
end
assert(exist(scanRoot, 'dir') == 7, 'wf_scan:noRoot', ...
    'Scan root does not exist:\n  %s', scanRoot);

%% ---- 1. manifest rows, if any -----------------------------------------
manifest = wf_read_manifest(fullfile(diskRoot, 'sessions.csv'));
if ~isempty(manifest)
    wf_log('Manifest: %d row(s) read from sessions.csv', numel(manifest));
end

%% ---- 2. crawl for TIFF folders ----------------------------------------
wf_log('Scanning %s for imaging sessions...', scanRoot);
tiffDirs = wf_find_tiff_dirs(scanRoot, cfg.min_tiffs, cfg.scan_max_depth);
wf_log('Found %d folder(s) of TIFFs', numel(tiffDirs));

%% ---- 3. resolve each into a session -----------------------------------
sessions = wf_empty_sessions();

for i = 1:numel(tiffDirs)
    s = wf_resolve_session(tiffDirs{i}, diskRoot, cfg);
    if isempty(s.subject) || isempty(s.date)
        problems{end+1} = sprintf(...
            'Could not read subject/date from folder name: %s', tiffDirs{i}); %#ok<AGROW>
        continue;
    end
    if isempty(s.nev)
        problems{end+1} = sprintf('No .nev file found near: %s', tiffDirs{i}); %#ok<AGROW>
    end
    if isempty(s.csv)
        problems{end+1} = sprintf('No trial CSV found near: %s', tiffDirs{i}); %#ok<AGROW>
    end
    sessions(end+1) = s; %#ok<AGROW>
end

%% ---- 4. manifest rows override scanned ones ---------------------------
for i = 1:numel(manifest)
    m   = manifest(i);
    hit = find(strcmpi({sessions.img_dir}, m.img_dir), 1);
    if isempty(hit)
        sessions(end+1) = m; %#ok<AGROW>
    else
        sessions(hit) = m;
    end
end

if isempty(sessions)
    return;
end

%% ---- 5. group into experiments ----------------------------------------
keys = arrayfun(@(s) sprintf('%s_%s', s.subject, s.date), sessions, ...
    'UniformOutput', false);
[uKeys, ~, gi] = unique(keys, 'stable');

for k = 1:numel(uKeys)
    grp = sessions(gi == k);
    grp = wf_order_sessions(grp, cfg);

    e = struct();
    e.subject  = grp(1).subject;
    e.date     = grp(1).date;
    e.sessions = grp;
    e.n        = numel(grp);

    if e.n == 1
        e.track = 'single';
        e.sessions(1).label = '';
    else
        e.track = 'combined';
    end

    % The experiment's own folder on the disk: the one holding img/ephys for
    % a single session, or the one holding session1..3 for a combined run.
    e.data_dir  = wf_data_dir(grp);
    e.out_dir   = wf_output_dir(e, cfg.output_location, '', cfg);
    e.disk_root = diskRoot;
    e.retino    = wf_find_retino(e.subject, diskRoot, cfg);

    missing = {};
    for j = 1:numel(grp)
        if isempty(grp(j).nev), missing{end+1} = 'nev'; end %#ok<AGROW>
        if isempty(grp(j).csv), missing{end+1} = 'csv'; end %#ok<AGROW>
    end
    e.ok = isempty(missing);

    notes = {};
    if ~e.ok
        notes{end+1} = sprintf('missing %s', strjoin(unique(missing), ' + '));
    end
    if isempty(e.retino)
        notes{end+1} = 'retinotopy will be built by pre-step A';
    end
    if e.n > 3
        notes{end+1} = sprintf('%d sessions found - check this is intended', e.n);
    end
    e.notes = strjoin(notes, '; ');

    experiments(end+1) = e; %#ok<AGROW>
end

%% ---- 6. leave a manifest stub for anything unresolved -----------------
if ~isempty(problems)
    stub = fullfile(diskRoot, 'sessions_unresolved.csv');
    wf_write_manifest_stub(stub, sessions, problems);
    wf_log('Wrote %s - fill it in and rename to sessions.csv to pin these down', stub);
end

end

% =====================================================================
function dirs = wf_find_tiff_dirs(root, minTiffs, depth)

dirs = {};
if depth < 0 || exist(root, 'dir') ~= 7, return; end

n = numel(dir(fullfile(root, '*.tif'))) + numel(dir(fullfile(root, '*.tiff')));
if n >= minTiffs
    dirs = {root};      % a TIFF folder never contains another TIFF folder
    return;
end

listing = dir(root);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    nm = listing(i).name;
    if any(strcmp(nm, {'.', '..'})) || strncmp(nm, '$', 1) || strncmp(nm, '.', 1)
        continue;
    end
    dirs = [dirs, wf_find_tiff_dirs(fullfile(root, nm), minTiffs, depth - 1)]; %#ok<AGROW>
end

end

% =====================================================================
function s = wf_resolve_session(tiffDir, diskRoot, cfg)
%WF_RESOLVE_SESSION  Read subject, date and session label; find .nev and CSV.

s = wf_empty_sessions();
s(1).img_dir = tiffDir;
s(1).exp_dir = '';
s(1).subject = '';
s(1).date    = '';
s(1).label   = '';
s(1).nev     = '';
s(1).csv     = '';

% Walk from the TIFF folder up towards the disk root, taking the first
% subject/date the naming patterns recognise. Nearest name wins.
%
% The folder whose NAME carries the subject and date is also the experiment
% folder, and it is remembered here. That is what "results next to the data"
% uses, so the analysis folder lands beside the session folders however many
% levels sit between them:
%
%   ...\LGN24_08272026_postblind_WFimage\img                     <- exp_dir
%   ...\LGN24_08272026_postblind_WFimage\session1\img            <- exp_dir
%   ...\LGN24_08272026_postblind_WFimage\data\session1\img       <- exp_dir
%
% Counting levels upward from the TIFFs would give a different answer for
% each of those; matching on the name gives the same one every time.
chain = wf_ancestor_chain(tiffDir, diskRoot);
paths = wf_ancestor_paths(tiffDir, diskRoot);

for i = 1:numel(chain)
    [subj, dt] = wf_parse_id(chain{i}, cfg);
    if isempty(s(1).subject) && ~isempty(subj), s(1).subject = subj; end
    if isempty(s(1).date)    && ~isempty(dt),   s(1).date    = dt;   end
    if ~isempty(dt) && isempty(s(1).exp_dir) && i <= numel(paths)
        s(1).exp_dir = paths{i};
    end
    if ~isempty(s(1).subject) && ~isempty(s(1).date), break; end
end

% Session label from any folder in the chain that names a session number.
for i = 1:numel(chain)
    lbl = wf_parse_session_label(chain{i}, cfg);
    if ~isempty(lbl), s(1).label = lbl; break; end
end

% .nev and CSV live in a SIBLING of the TIFF folder, not above it:
%     ...\session1\img     <- TIFFs
%     ...\session1\ephys   <- .nev and .csv
% so the search covers the TIFF folder, then its siblings (ephys-looking
% ones first), and only then the ancestors themselves.
searchDirs = wf_search_dirs(tiffDir, diskRoot, cfg);
s(1).nev = wf_first_match(searchDirs, '*.nev');
s(1).csv = wf_first_csv(searchDirs, cfg);

end

% =====================================================================
function dirs = wf_search_dirs(tiffDir, diskRoot, cfg)
%WF_SEARCH_DIRS  Where to look for this session's .nev and trial CSV.
%
% Deliberately does NOT scan the children of higher ancestors. Doing so
% would let session1 pick up session2's .nev when session1's ephys folder is
% empty or misnamed - a silent mis-pairing that would be very hard to spot
% in the results. Better to report the session as unresolved and let the
% manifest sort it out.

dirs   = {tiffDir};
parent = fileparts(tiffDir);

if ~isempty(parent) && ~strcmp(parent, tiffDir)
    dirs{end+1} = parent;

    listing = dir(parent);
    listing = listing([listing.isdir]);
    sibs    = {};
    for i = 1:numel(listing)
        n = listing(i).name;
        if any(strcmp(n, {'.', '..'})), continue; end
        p = fullfile(parent, n);
        if strcmpi(p, tiffDir), continue; end
        sibs{end+1} = p; %#ok<AGROW>
    end

    % ephys-looking siblings first, then any other sibling.
    named = false(1, numel(sibs));
    for i = 1:numel(sibs)
        [~, nm] = fileparts(sibs{i});
        named(i) = any(strcmpi(nm, cfg.ephys_folder_names));
    end
    dirs = [dirs, sibs(named), sibs(~named)];
end

% Follow single-subfolder chains, e.g. session1\ephys\<recording>\*.nev.
% Done only for these session-local folders, never for the ancestors below,
% so the search still cannot wander into a neighbouring session.
dirs = wf_expand_single_child(dirs, cfg.ephys_descend_depth);

% Finally the ancestors themselves, for layouts that keep the .nev higher up.
dirs = [dirs, wf_ancestor_dirs(parent, diskRoot)];

end

% =====================================================================
function out = wf_expand_single_child(dirs, maxDepth)
%WF_EXPAND_SINGLE_CHILD  Append each folder's sole-subfolder chain.
%
% A folder is followed only when it contains exactly one subfolder. Two or
% more is ambiguous, and picking one would risk pairing a session with the
% wrong recording, so those are left alone and the session ends up in the
% unresolved list where it is visible.

out = {};

for i = 1:numel(dirs)
    out{end+1} = dirs{i}; %#ok<AGROW>

    cur = dirs{i};
    for d = 1:maxDepth
        kids = wf_child_dirs(cur);
        if numel(kids) ~= 1, break; end
        cur = kids{1};
        out{end+1} = cur; %#ok<AGROW>
    end
end

end

% =====================================================================
function kids = wf_child_dirs(d)

kids = {};
if exist(d, 'dir') ~= 7, return; end

listing = dir(d);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    n = listing(i).name;
    if any(strcmp(n, {'.', '..'})) || strncmp(n, '$', 1) || strncmp(n, '.', 1)
        continue;
    end
    kids{end+1} = fullfile(d, n); %#ok<AGROW>
end

end

% =====================================================================
function chain = wf_ancestor_chain(d, stopAt)
%WF_ANCESTOR_CHAIN  Folder NAMES from d upwards, nearest first.

chain = {};
cur   = d;
for i = 1:8
    [parent, name] = fileparts(cur);
    if isempty(name), break; end
    chain{end+1} = name; %#ok<AGROW>
    if strcmpi(wf_norm(parent), wf_norm(stopAt)) || isempty(parent) || strcmp(parent, cur)
        break;
    end
    cur = parent;
end

end

% =====================================================================
function paths = wf_ancestor_paths(d, stopAt)
%WF_ANCESTOR_PATHS  Full paths matching WF_ANCESTOR_CHAIN element for element.

paths = {};
cur   = d;
for i = 1:8
    [parent, name] = fileparts(cur);
    if isempty(name), break; end
    paths{end+1} = cur; %#ok<AGROW>
    if strcmpi(wf_norm(parent), wf_norm(stopAt)) || isempty(parent) || strcmp(parent, cur)
        break;
    end
    cur = parent;
end

end

% =====================================================================
function dirs = wf_ancestor_dirs(d, stopAt)
%WF_ANCESTOR_DIRS  Folder PATHS above d, nearest first, up to stopAt.

dirs = {};
cur  = d;
for i = 1:8
    parent = fileparts(cur);
    if isempty(parent) || strcmp(parent, cur), break; end
    dirs{end+1} = parent; %#ok<AGROW>
    if strcmpi(wf_norm(parent), wf_norm(stopAt)), break; end
    cur = parent;
end

end

% =====================================================================
function [subj, dt] = wf_parse_id(name, cfg)
%WF_PARSE_ID  Pull subject and a normalised YYYYMMDD date out of a name.

subj = '';
dt   = '';

for i = 1:size(cfg.id_patterns, 1)
    tok = regexpi(name, cfg.id_patterns{i,1}, 'names', 'once');
    if isempty(tok), continue; end

    if isfield(tok, 'subj') && ~isempty(tok.subj), subj = upper(tok.subj); end
    if isfield(tok, 'date') && ~isempty(tok.date)
        dt = wf_normalise_date(tok.date, cfg.id_patterns{i,2}, cfg);
    end
    if ~isempty(dt), return; end
end

end

% =====================================================================
function out = wf_normalise_date(raw, kind, cfg)
%WF_NORMALISE_DATE  Convert a matched date token to YYYYMMDD.

out = '';
raw = char(raw);

switch kind
    case 'ymd'
        if numel(raw) == 8, out = raw; end

    case 'mdy'
        if numel(raw) == 8
            mm = raw(1:2); dd = raw(3:4); yy = raw(5:8);
            if str2double(mm) >= 1 && str2double(mm) <= 12 && ...
               str2double(dd) >= 1 && str2double(dd) <= 31
                out = [yy mm dd];
            end
        end

    case 'md'
        if numel(raw) == 4
            mm = raw(1:2); dd = raw(3:4);
            if str2double(mm) >= 1 && str2double(mm) <= 12 && ...
               str2double(dd) >= 1 && str2double(dd) <= 31
                yy = cfg.assume_year;
                if isempty(yy), yy = datestr(now, 'yyyy'); end
                out = [yy mm dd];
            end
        end
end

% Reject impossible dates outright rather than carrying them downstream.
if ~isempty(out)
    try
        datetime(out, 'InputFormat', 'yyyyMMdd');
    catch
        out = '';
    end
end

end

% =====================================================================
function lbl = wf_parse_session_label(name, cfg)

lbl = '';
for i = 1:numel(cfg.session_patterns)
    if ~isempty(regexpi(name, cfg.session_patterns{i}, 'once'))
        lbl = sprintf('session%d', i);
        return;
    end
end

end

% =====================================================================
function f = wf_first_match(dirs, pattern)

f = '';
for i = 1:numel(dirs)
    hits = dir(fullfile(dirs{i}, pattern));
    hits = hits(~[hits.isdir]);
    if ~isempty(hits)
        [~, k] = max([hits.bytes]);      % the real recording, not a stub
        f = fullfile(dirs{i}, hits(k).name);
        return;
    end
end

end

% =====================================================================
function f = wf_first_csv(dirs, cfg)
%WF_FIRST_CSV  Nearest .csv/.txt that looks like the trial design table.
%
% A header naming a channel and a current column is the strong signal. Some
% exports have no header row at all, so as a fallback the only tabular file
% in the first folder that contains one is accepted - with three numeric
% columns, that is almost certainly the trial list.

f = '';
fallback = '';

for i = 1:numel(dirs)
    hits = [dir(fullfile(dirs{i}, '*.csv')); dir(fullfile(dirs{i}, '*.txt'))];
    hits = hits(~[hits.isdir]);

    cands = {};
    for k = 1:numel(hits)
        if isempty(regexpi(hits(k).name, cfg.csv_pattern, 'once')), continue; end
        cands{end+1} = fullfile(dirs{i}, hits(k).name); %#ok<AGROW>
    end
    if isempty(cands), continue; end

    for k = 1:numel(cands)
        if wf_looks_like_trial_csv(cands{k})
            f = cands{k};
            return;
        end
    end

    % Exactly one candidate in this folder: take it. A .csv is accepted on
    % its extension alone, since a headerless two-column export is still the
    % trial list; a .txt has to look tabular before it is trusted, so a
    % stray notes file is not mistaken for the trial design.
    if isempty(fallback) && numel(cands) == 1
        [~, ~, ext] = fileparts(cands{1});
        if strcmpi(ext, '.csv') || wf_looks_tabular(cands{1})
            fallback = cands{1};
        end
    end
end

f = fallback;

end

% =====================================================================
function tf = wf_looks_like_trial_csv(p)
%WF_LOOKS_LIKE_TRIAL_CSV  Header mentions a channel and a current column.

tf = false;
head = wf_first_line(p);
if isempty(head), return; end

head = lower(head);
tf = ~isempty(strfind(head, 'chan')) && ...
     (~isempty(strfind(head, 'current')) || ~isempty(strfind(head, 'ua')));

end

% =====================================================================
function tf = wf_looks_tabular(p)
%WF_LOOKS_TABULAR  At least three comma- or tab-separated numeric columns.

tf = false;
head = wf_first_line(p);
if isempty(head), return; end

parts = regexp(strtrim(head), '[,\t;]', 'split');
tf = numel(parts) >= 3;

end

% =====================================================================
function head = wf_first_line(p)

head = '';
fid  = fopen(p, 'r');
if fid < 0, return; end
c = onCleanup(@() fclose(fid));

for i = 1:5                    % skip blank or commented leading lines
    line = fgetl(fid);
    if ~ischar(line), return; end
    if ~isempty(strtrim(line)) && ~strncmp(strtrim(line), '#', 1)
        head = line;
        return;
    end
end

end

% =====================================================================
function grp = wf_order_sessions(grp, cfg) %#ok<INUSD>
%WF_ORDER_SESSIONS  Put sessions in session1, session2, session3 order.
%
% Labelled sessions sort by their label. Unlabelled ones fall back to folder
% name, then get sequential labels, so a three-session experiment whose
% folders are named anything ascending still lines up correctly.

hasLabel = ~cellfun(@isempty, {grp.label});

if all(hasLabel)
    [~, ord] = sort({grp.label});
else
    [~, ord] = sort(lower({grp.img_dir}));
end
grp = grp(ord);

for i = 1:numel(grp)
    if isempty(grp(i).label)
        grp(i).label = sprintf('session%d', i);
    end
end

end

% =====================================================================
function f = wf_find_retino(subject, diskRoot, cfg)
%WF_FIND_RETINO  Retinotopy maps for this subject: disk first, then the
% local retinotopic_mapping results folder.

f = '';

roots = {fullfile(diskRoot, 'retinotopy'), diskRoot, cfg.retino_root};
for i = 1:numel(roots)
    if exist(roots{i}, 'dir') ~= 7, continue; end
    hits = wf_search(roots{i}, cfg.retino_pattern, 3);
    if isempty(hits), continue; end

    % Prefer a file whose path mentions this subject.
    mine = hits(~cellfun(@isempty, regexpi(hits, subject, 'once')));
    if ~isempty(mine), hits = mine; end

    d = cellfun(@(x) wf_mtime(x), hits);
    [~, k] = max(d);
    f = hits{k};
    return;
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
    nm = listing(i).name;
    if any(strcmp(nm, {'.', '..'})) || strncmp(nm, '$', 1), continue; end
    out = [out, wf_search(fullfile(root, nm), pattern, depth - 1)]; %#ok<AGROW>
end

end

% =====================================================================
function t = wf_mtime(f)

d = dir(f);
if isempty(d), t = 0; else, t = d.datenum; end

end

% =====================================================================
function d = wf_data_dir(grp)
%WF_DATA_DIR  The experiment's own folder on the portable disk.
%
% This is the "results next to the data" destination. It is the folder whose
% name carries the subject and date, found while parsing:
%
%   ...\LGN24_08272026_postblind_WFimage\img
%   ...\LGN24_08272026_postblind_WFimage\session1\img
%   ...\LGN24_08272026_postblind_WFimage\data\session1\img
%
% all give the same answer. Only when that is unavailable - a manifest row,
% say, where nothing was parsed from a folder name - does it fall back to
% counting levels up from the TIFFs.

d = '';
if isfield(grp, 'exp_dir') && ~isempty(grp(1).exp_dir)
    d = grp(1).exp_dir;
    return;
end

first = grp(1).img_dir;
if numel(grp) == 1
    d = fileparts(first);
else
    d = fileparts(fileparts(first));
end

end

% =====================================================================
function s = wf_date_mdy(ymd)
%WF_DATE_MDY  20260630 -> 06302026, matching the existing WF_result folders.

if numel(ymd) == 8
    s = [ymd(5:6) ymd(7:8) ymd(1:4)];
else
    s = ymd;
end

end

% =====================================================================
function s = wf_norm(p)

s = regexprep(char(p), '[\\/]+$', '');

end

% =====================================================================
function e = wf_empty_experiments()

e = struct('subject', {}, 'date', {}, 'sessions', {}, 'n', {}, ...
           'track', {}, 'data_dir', {}, 'out_dir', {}, 'disk_root', {}, ...
           'retino', {}, 'ok', {}, 'notes', {});

end

% =====================================================================
function s = wf_empty_sessions()

s = struct('subject', {}, 'date', {}, 'label', {}, ...
           'img_dir', {}, 'exp_dir', {}, 'nev', {}, 'csv', {});

end
