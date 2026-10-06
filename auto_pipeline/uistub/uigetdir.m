function folder = uigetdir(varargin)
%UIGETDIR  Automation stub. Shadows MATLAB's uigetdir while the WF auto
% pipeline is running; falls through to the real dialog otherwise.
%
% Answer value semantics (see WF_UI):
%   char/string  folder to "select" (created if it does not yet exist)
%   0            simulate the user pressing Cancel

txt = wf_stub_text(varargin, 2);
val = wf_ui('take', 'uigetdir', txt);

if isempty(val)
    folder = wf_stub_passthrough('uigetdir', 1, varargin);
    return;
end

if isnumeric(val) && isscalar(val) && val == 0
    folder = 0;
    return;
end

folder = char(string(val));
if exist(folder, 'dir') ~= 7
    [ok, msg] = mkdir(folder);
    if ~ok
        error('wf_stub:mkdirFailed', ...
            'Could not create output folder "%s": %s', folder, msg);
    end
end

end
