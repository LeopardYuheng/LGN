function outFile = wf_step3_container(track, wfAlignFile, subject, dateStr, sessionLabel, cfg)
%WF_STEP3_CONTAINER  Step 3: build the day pointer from the step 2 alignment.
%
%   outFile = WF_STEP3_CONTAINER(track, wfAlignFile, subject, dateStr, sessionLabel, cfg)
%
% The day pointer is written next to the step 2 file, which is where
% make_container_ripple_3.m puts it.
%
% make_container_ripple_3.m APPENDS to an existing container rather than
% replacing it. When we are deliberately rebuilding (resume off, or a
% previous run left a partial file), the old container is deleted first so
% trials cannot be counted twice.

if nargin < 6 || isempty(cfg), cfg = wf_config(); end
if nargin <  5, sessionLabel = ''; end

P      = wf_paths();
outDir = fileparts(wfAlignFile);

if isempty(sessionLabel)
    outFile = fullfile(outDir, sprintf('%s_%s_day_pointer.mat', subject, dateStr));
else
    outFile = fullfile(outDir, sprintf('%s_%s_%s_day_pointer.mat', ...
        subject, dateStr, sessionLabel));
end

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  step 3: already done (%s)', wf_short(outFile));
    return;
end

if exist(outFile, 'file') == 2
    delete(outFile);   % never append to a stale container
end

assert(exist(wfAlignFile, 'file') == 2, 'wf_step3:noInput', ...
    'Step 2 output not found:\n  %s', wfAlignFile);

answers = wf_ans('uigetfile', 'wf_trial_alignment', wfAlignFile);

wf_log('  step 3: building day pointer');
wf_run_script(P.(track).step3, answers, ...
    struct('strict', cfg.strict_dialogs, 'addpath', {{P.(track).functions}}));

assert(exist(outFile, 'file') == 2, 'wf_step3:noOutput', ...
    'Step 3 finished but did not produce:\n  %s', outFile);
wf_log('  step 3: saved %s', wf_short(outFile));

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
