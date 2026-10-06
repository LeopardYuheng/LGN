function T = wf_ans(varargin)
%WF_ANS  Compact constructor for a WF_UI answer table.
%
%   T = WF_ANS(kind1, pattern1, value1, kind2, pattern2, value2, ...)
%
% Example
%   T = wf_ans( ...
%       'uigetdir',  'output folder to save session', outDir, ...
%       'uigetfile', '\.nev',                         nevFile, ...
%       'inputdlg',  'Session Metadata',              {'LGN26','20260630','',''});
%
% See also WF_UI.

assert(mod(nargin, 3) == 0, 'wf_ans:badArgs', ...
    'Arguments must come in (kind, pattern, value) triplets.');

n = nargin / 3;
T = struct('kind', cell(1, n), 'pattern', cell(1, n), 'value', cell(1, n));
for i = 1:n
    T(i).kind    = varargin{3*i - 2};
    T(i).pattern = varargin{3*i - 1};
    T(i).value   = varargin{3*i};
end

end
