function choice = wf_error_choice(e, err, cfg, phase)
%WF_ERROR_CHOICE  Ask what to do about a failed step.
%
%   choice = WF_ERROR_CHOICE(e, err, cfg, phase)
%
% Returns 'retry', 'skip' or 'stop'. With cfg.on_error set to 'continue' or
% 'stop' no dialog appears and that answer is used directly.
%
% phase is 'setup' or 'analysis', and only changes the wording.

if nargin < 4, phase = 'analysis'; end

switch lower(cfg.on_error)
    case 'continue', choice = 'skip';  return;
    case 'stop',     choice = 'stop';  return;
end

if strcmpi(phase, 'setup')
    what = 'Setting up';
    hint = ['Retry restarts the setup for this experiment. Anything already ' ...
            'accepted - the retinotopy, the brain mask - is kept, so you are ' ...
            'not asked those again.'];
else
    what = 'Analysis of';
    hint = ['Retry re-runs this experiment; steps that already finished are ' ...
            'skipped, so it picks up where it stopped.'];
end

msg = sprintf('%s %s %s failed.\n\n%s\n\n%s', ...
    what, e.subject, e.date, wf_trim(err.message, 400), hint);

answer = questdlg(msg, 'Pipeline error', ...
    'Retry this experiment', 'Skip it and continue', 'Stop everything', ...
    'Skip it and continue');

switch answer
    case 'Retry this experiment',  choice = 'retry';
    case 'Stop everything',        choice = 'stop';
    otherwise,                     choice = 'skip';   % includes closing it
end

end

% =====================================================================
function s = wf_trim(t, n)

t = char(string(t));
if numel(t) > n, s = [t(1:n) ' ...']; else, s = t; end

end
