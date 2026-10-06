function [filename, pathname, filterindex] = uigetfile(varargin)
%UIGETFILE  Automation stub. Shadows MATLAB's uigetfile while the WF auto
% pipeline is running; falls through to the real dialog otherwise.
%
% Answer value semantics (see WF_UI):
%   char/string  full path to the file to "select"
%   0            simulate the user pressing Cancel

txt = wf_stub_text(varargin, 2);
val = wf_ui('take', 'uigetfile', txt);

if isempty(val)
    [filename, pathname, filterindex] = ...
        wf_stub_passthrough('uigetfile', 3, varargin);
    return;
end

if isnumeric(val) && isscalar(val) && val == 0
    filename    = 0;
    pathname    = 0;
    filterindex = 0;
    return;
end

full = char(string(val));
if exist(full, 'file') ~= 2
    error('wf_stub:missingFile', ...
        ['The automated pipeline was told to select a file that does not exist.\n' ...
         '  dialog : %s\n  path   : %s'], txt, full);
end

[p, n, e]   = fileparts(full);
filename    = [n e];
pathname    = [p filesep];
filterindex = 1;

end
