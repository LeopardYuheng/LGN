function [selection, ok] = listdlg(varargin)
%LISTDLG  Automation stub. Shadows MATLAB's listdlg while the WF auto
% pipeline is running; falls through to the real dialog otherwise.
%
% Answer value semantics (see WF_UI):
%   numeric vector   indices to "select"
%   function handle  @(listStrings) -> indices  (e.g. select every condition)
%   0 or []          simulate the user pressing Cancel
%
% Note: an empty selection is expressed as 0, because [] is what WF_UI
% returns when no answer matched.

name    = wf_stub_param(varargin, 'Name',         '');
prompt  = wf_stub_param(varargin, 'PromptString', '');
listStr = wf_stub_param(varargin, 'ListString',   {});

if ischar(prompt) || isstring(prompt)
    promptTxt = char(string(prompt));
elseif iscell(prompt)
    promptTxt = strjoin(cellfun(@(x) char(string(x)), prompt(:)', ...
        'UniformOutput', false), ' ');
else
    promptTxt = '';
end

if ischar(listStr) || isstring(listStr)
    listStr = cellstr(listStr);
end

txt = strtrim([char(string(name)) ' | ' promptTxt]);
val = wf_ui('take', 'listdlg', txt);

if isempty(val)
    [selection, ok] = wf_stub_passthrough('listdlg', 2, varargin);
    return;
end

if isa(val, 'function_handle')
    val = val(listStr);
end

if isempty(val) || (isscalar(val) && isnumeric(val) && val == 0)
    selection = [];
    ok        = 0;
    return;
end

selection = double(val(:))';
n = numel(listStr);
if n > 0
    bad = selection < 1 | selection > n | selection ~= round(selection);
    assert(~any(bad), 'wf_stub:badListdlgValue', ...
        'listdlg answer for "%s" contains out-of-range indices (list has %d items).', ...
        txt, n);
end
ok = 1;

end
