function button = questdlg(varargin)
%QUESTDLG  Automation stub. Shadows MATLAB's questdlg while the WF auto
% pipeline is running; falls through to the real dialog otherwise.
%
% Answer value semantics (see WF_UI):
%   char/string  the exact button label to "press"
%   0            simulate the dialog being dismissed (returns '')

q = '';
if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}) || iscell(varargin{1}))
    if iscell(varargin{1})
        q = strjoin(cellfun(@(x) char(string(x)), varargin{1}(:)', ...
            'UniformOutput', false), ' ');
    else
        q = char(string(varargin{1}));
    end
end

t = '';
if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
    t = char(string(varargin{2}));
end

txt = strtrim([q ' | ' t]);
val = wf_ui('take', 'questdlg', txt);

if isempty(val)
    button = wf_stub_passthrough('questdlg', 1, varargin);
    return;
end

if isnumeric(val) && isscalar(val) && val == 0
    button = '';
    return;
end

button = char(string(val));

end
