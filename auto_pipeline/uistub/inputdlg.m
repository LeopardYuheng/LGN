function answer = inputdlg(varargin)
%INPUTDLG  Automation stub. Shadows MATLAB's inputdlg while the WF auto
% pipeline is running; falls through to the real dialog otherwise.
%
% Answer value semantics (see WF_UI):
%   cellstr             one entry per prompt field, in order
%   function handle     @(prompts, defaults) -> cellstr
%   0                   simulate the user pressing Cancel

prompts = {};
if nargin >= 1
    p = varargin{1};
    if ischar(p) || isstring(p)
        prompts = {char(string(p))};
    elseif iscell(p)
        prompts = cellfun(@(x) char(string(x)), p(:)', 'UniformOutput', false);
    end
end

title = '';
if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
    title = char(string(varargin{2}));
end

defaults = {};
if nargin >= 4 && iscell(varargin{4})
    defaults = cellfun(@(x) char(string(x)), varargin{4}(:)', 'UniformOutput', false);
end

txt = strtrim([strjoin(prompts, ' | ') ' | ' title]);
val = wf_ui('take', 'inputdlg', txt);

if isempty(val)
    answer = wf_stub_passthrough('inputdlg', 1, varargin);
    return;
end

if isnumeric(val) && isscalar(val) && val == 0
    answer = {};
    return;
end

if isa(val, 'function_handle')
    val = val(prompts, defaults);
end

if ischar(val) || isstring(val)
    val = {char(string(val))};
end

assert(iscell(val), 'wf_stub:badInputdlgValue', ...
    'inputdlg answer for "%s" must be a cellstr.', txt);

val = cellfun(@(x) char(string(x)), val(:), 'UniformOutput', false);

n = max(numel(prompts), 1);
if numel(val) < n
    % Pad with the dialog's own defaults so partially-specified answers work.
    for i = numel(val)+1 : n
        if i <= numel(defaults), val{i} = defaults{i}; else, val{i} = ''; end
    end
elseif numel(val) > n
    val = val(1:n);
end

answer = val;

end
