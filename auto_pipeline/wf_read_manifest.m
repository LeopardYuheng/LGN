function sessions = wf_read_manifest(csvPath, diskRoot)
%WF_READ_MANIFEST  Read a sessions.csv that pins down where session data lives.
%
%   sessions = WF_READ_MANIFEST(csvPath)
%   sessions = WF_READ_MANIFEST(csvPath, diskRoot)
%
% Returns an empty struct array when the file does not exist, so callers can
% treat "no manifest" and "empty manifest" the same way.
%
% FORMAT
%   subject,date,session_label,tiff_dir,nev_file,csv_file
%   LGN26,20260630,,D:\LGN26\0630\images,D:\LGN26\0630\r.nev,D:\LGN26\0630\t.csv
%
% Notes
%   - The header row is required; column order does not matter.
%   - date accepts YYYYMMDD or MMDDYYYY and is normalised to YYYYMMDD.
%   - session_label is blank for a single-session experiment, otherwise
%     session1 / session2 / session3.
%   - Paths may be absolute, or relative to the disk root.
%   - Blank lines and lines starting with # are ignored.

% exp_dir is what "results next to the data" uses. The scanner fills it from
% the folder whose name carries the subject and date; a manifest row has no
% such folder to point at, so it is left empty and WF_DATA_DIR falls back to
% walking up from the TIFF folder.
sessions = struct('subject', {}, 'date', {}, 'label', {}, ...
                  'img_dir', {}, 'exp_dir', {}, 'nev', {}, 'csv', {});

if nargin < 2, diskRoot = fileparts(csvPath); end
if exist(csvPath, 'file') ~= 2, return; end

txt   = fileread(csvPath);
lines = regexp(txt, '\r\n|\r|\n', 'split');
lines = lines(~cellfun(@(l) isempty(strtrim(l)) || strncmp(strtrim(l), '#', 1), lines));
if isempty(lines), return; end

header = wf_split_csv_line(lines{1});
header = lower(strtrim(header));

col = @(name) find(strcmp(header, name), 1);
iSubj  = col('subject');
iDate  = col('date');
iLabel = col('session_label');
iTiff  = col('tiff_dir');
iNev   = col('nev_file');
iCsv   = col('csv_file');

assert(~isempty(iSubj) && ~isempty(iDate) && ~isempty(iTiff), ...
    'wf_manifest:badHeader', ...
    ['%s must have at least the columns: subject, date, tiff_dir\n' ...
     'Found: %s'], csvPath, strjoin(header, ', '));

for k = 2:numel(lines)
    f = wf_split_csv_line(lines{k});
    if numel(f) < numel(header)
        f(end+1:numel(header)) = {''};
    end

    s = struct();
    s.subject = upper(strtrim(f{iSubj}));
    s.date    = wf_norm_date(strtrim(f{iDate}));
    if isempty(iLabel), s.label = ''; else, s.label = strtrim(f{iLabel}); end
    s.img_dir = wf_abs(strtrim(f{iTiff}), diskRoot);
    s.exp_dir = '';
    if isempty(iNev), s.nev = ''; else, s.nev = wf_abs(strtrim(f{iNev}), diskRoot); end
    if isempty(iCsv), s.csv = ''; else, s.csv = wf_abs(strtrim(f{iCsv}), diskRoot); end

    if isempty(s.subject) || isempty(s.date) || isempty(s.img_dir)
        warning('wf_manifest:skipRow', ...
            'Skipping manifest row %d: subject, date and tiff_dir are all required.', k);
        continue;
    end

    sessions(end+1) = s; %#ok<AGROW>
end

end

% =====================================================================
function f = wf_split_csv_line(line)
%WF_SPLIT_CSV_LINE  Comma split that respects "quoted, fields".

f    = {};
cur  = '';
inQ  = false;
line = char(line);

for i = 1:numel(line)
    c = line(i);
    if c == '"'
        inQ = ~inQ;
    elseif c == ',' && ~inQ
        f{end+1} = cur; %#ok<AGROW>
        cur = '';
    else
        cur(end+1) = c; %#ok<AGROW>
    end
end
f{end+1} = cur;

end

% =====================================================================
function out = wf_norm_date(raw)

out = '';
raw = regexprep(char(raw), '[^\d]', '');
if numel(raw) ~= 8, return; end

if strncmp(raw, '20', 2) && str2double(raw(5:6)) <= 12
    out = raw;                                  % YYYYMMDD
elseif str2double(raw(1:2)) <= 12
    out = [raw(5:8) raw(1:2) raw(3:4)];         % MMDDYYYY
else
    out = raw;
end

try
    datetime(out, 'InputFormat', 'yyyyMMdd');
catch
    out = '';
end

end

% =====================================================================
function p = wf_abs(p, root)

if isempty(p), return; end
if ~isempty(regexp(p, '^([A-Za-z]:|\\\\|/)', 'once')), return; end
p = fullfile(root, p);

end
