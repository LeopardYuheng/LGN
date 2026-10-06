function varargout = wf_stub_passthrough(fname, nout, args)
%WF_STUB_PASSTHROUGH  Call the genuine MATLAB dialog from inside a stub.
%
% Temporarily drops the uistub folder off the path so that FEVAL resolves
% to MATLAB's own function, then restores it. Used whenever the automation
% has no answer for a dialog and non-strict mode lets the user answer it by
% hand.

stubDir = wf_stub_dir();
onPath  = wf_stub_on_path(stubDir);

if onPath
    rmpath(stubDir);
    restore = onCleanup(@() addpath(stubDir, '-begin'));
end

varargout = cell(1, nout);
[varargout{1:nout}] = feval(fname, args{:});

end

% =====================================================================
function d = wf_stub_dir()

d = fullfile(fileparts(mfilename('fullpath')), 'uistub');

end

% =====================================================================
function tf = wf_stub_on_path(d)

p  = strsplit(path, pathsep);
tf = any(strcmpi(p, d));

end
