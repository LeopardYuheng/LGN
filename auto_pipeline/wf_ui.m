function varargout = wf_ui(cmd, varargin)
%WF_UI  Answer store that drives the automated pipeline's dialog stubs.
%
% The original pipeline scripts are NEVER modified. Instead, this store is
% loaded with pre-computed answers, the stub folder (uistub)
% is put at the front of the MATLAB path, and the shadowed dialog functions
% (uigetfile, uigetdir, inputdlg, listdlg, questdlg) pull their answers from
% here instead of showing a window.
%
% State lives in the graphics root's application data, so it survives the
% `clear` / `close all` statements at the top of every pipeline script.
%
% COMMANDS
%   wf_ui('begin', answers, strict)  start automation with an answer table
%   wf_ui('end')                     stop automation, restore normal dialogs
%   ans = wf_ui('take', kind, text)  called by the stubs; returns the answer
%                                    or [] if nothing matched
%   tf  = wf_ui('active')            is automation currently on?
%   wf_ui('note', txt)               append a line to the interaction log
%   L   = wf_ui('log')               retrieve the interaction log
%   U   = wf_ui('unused')            answers that were never consumed
%
% ANSWER TABLE
%   A struct array (or the output of WF_ANS) with fields:
%     .kind    'uigetfile' | 'uigetdir' | 'inputdlg' | 'listdlg' | 'questdlg'
%     .pattern case-insensitive regexp matched against the dialog's prompt
%              and title text
%     .value   see below
%
%   .value by kind
%     uigetfile  full path to the file, or 0 to simulate Cancel
%     uigetdir   folder path, or 0 to simulate Cancel
%     inputdlg   cellstr of the answers, in order
%     listdlg    vector of indices, or a function handle
%                @(listStrings) -> indices  (e.g. select every condition),
%                or 0 to simulate Cancel
%     questdlg   the exact button label to "click"
%
%   Entries are matched in table order and each is consumed once, so several
%   entries sharing a pattern serve successive calls (e.g. the per-session
%   day-pointer prompts in the combined step 5_A).
%
% See also WF_ANS, WF_RUN_SCRIPT.

narginchk(1, 3);
varargout = {};

switch lower(cmd)

    case 'begin'
        answers = varargin{1};
        if nargin < 3, strict = true; else, strict = logical(varargin{2}); end
        answers = wf_ui_validate(answers);
        setappdata(0, 'WF_UI_TABLE',  answers);
        setappdata(0, 'WF_UI_USED',   false(numel(answers), 1));
        setappdata(0, 'WF_UI_STRICT', strict);
        setappdata(0, 'WF_UI_LOG',    {});
        setappdata(0, 'WF_UI_ACTIVE', true);

    case 'end'
        setappdata(0, 'WF_UI_ACTIVE', false);

    case 'active'
        varargout{1} = isappdata(0, 'WF_UI_ACTIVE') && getappdata(0, 'WF_UI_ACTIVE');

    case 'take'
        kind = varargin{1};
        text = varargin{2};
        varargout{1} = wf_ui_take(kind, text);

    case 'note'
        L = getappdata(0, 'WF_UI_LOG');
        if isempty(L), L = {}; end
        L{end+1} = varargin{1}; %#ok<AGROW>
        setappdata(0, 'WF_UI_LOG', L);

    case 'log'
        L = getappdata(0, 'WF_UI_LOG');
        if isempty(L), L = {}; end
        varargout{1} = L;

    case 'unused'
        T = getappdata(0, 'WF_UI_TABLE');
        U = getappdata(0, 'WF_UI_USED');
        if isempty(T), varargout{1} = T; else, varargout{1} = T(~U); end

    otherwise
        error('wf_ui:badCommand', 'Unknown command "%s".', cmd);
end

end

% =====================================================================
function out = wf_ui_take(kind, text)

out = [];
if ~(isappdata(0, 'WF_UI_ACTIVE') && getappdata(0, 'WF_UI_ACTIVE'))
    return;   % automation off -> stub falls through to the real dialog
end

T = getappdata(0, 'WF_UI_TABLE');
U = getappdata(0, 'WF_UI_USED');
if isempty(T)
    hit = [];
else
    hit = [];
    for i = 1:numel(T)
        if U(i),                              continue; end
        if ~strcmpi(T(i).kind, kind),         continue; end
        if isempty(regexpi(text, T(i).pattern, 'once')), continue; end
        hit = i;
        break;
    end
end

if isempty(hit)
    wf_ui('note', sprintf('UNMATCHED  %-10s  "%s"', kind, wf_ui_trim(text)));
    if getappdata(0, 'WF_UI_STRICT')
        error('wf_ui:noAnswer', ...
            ['The automated pipeline hit a dialog it has no answer for.\n' ...
             '  kind   : %s\n' ...
             '  prompt : %s\n\n' ...
             'Add a matching entry to the step wrapper''s answer table, or ' ...
             'run with strict mode off to answer this one by hand.'], ...
            kind, wf_ui_trim(text));
    end
    return;   % non-strict: stub shows the real dialog
end

U(hit) = true;
setappdata(0, 'WF_UI_USED', U);
out = T(hit).value;
wf_ui('note', sprintf('answered   %-10s  "%s"  ->  %s', ...
    kind, wf_ui_trim(text), wf_ui_describe(out)));

end

% =====================================================================
function T = wf_ui_validate(T)

if isempty(T)
    T = struct('kind', {}, 'pattern', {}, 'value', {});
    return;
end
assert(isstruct(T), 'wf_ui:badTable', 'Answer table must be a struct array.');
need = {'kind', 'pattern', 'value'};
for k = 1:numel(need)
    assert(isfield(T, need{k}), 'wf_ui:badTable', ...
        'Answer table is missing the "%s" field.', need{k});
end
valid = {'uigetfile', 'uigetdir', 'inputdlg', 'listdlg', 'questdlg'};
for i = 1:numel(T)
    assert(any(strcmpi(T(i).kind, valid)), 'wf_ui:badTable', ...
        'Answer %d has unsupported kind "%s".', i, T(i).kind);
end

end

% =====================================================================
function s = wf_ui_trim(t)

t = regexprep(char(string(t)), '\s+', ' ');
if numel(t) > 90, s = [t(1:87) '...']; else, s = t; end

end

% =====================================================================
function s = wf_ui_describe(v)

if isa(v, 'function_handle')
    s = ['@' func2str(v)];
elseif iscell(v)
    s = ['{' strjoin(cellfun(@(x) char(string(x)), v(:)', 'UniformOutput', false), ', ') '}'];
elseif ischar(v) || isstring(v)
    s = char(string(v));
elseif isnumeric(v) || islogical(v)
    s = mat2str(v);
else
    s = class(v);
end
s = wf_ui_trim(s);

end
