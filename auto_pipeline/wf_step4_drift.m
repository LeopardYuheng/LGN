function outFile = wf_step4_drift(track, dayPointer, maskFile, outDir, cfg)
%WF_STEP4_DRIFT  Step 4: per-pixel baseline drift model from the 0 uA trials.
%
%   outFile = WF_STEP4_DRIFT(track, dayPointer, maskFile, outDir, cfg)
%
% Required for Method 1 (steps 5_B / 7_B / 7_C / 7_D). For a step 5_A run it
% is QC only: the slope and R-squared maps tell you whether the per-trial
% local baseline of Method 0 is the right choice for this session.
%
% On the combined track this runs once per session, against that session's
% own day pointer, because the drift model is fit in that session's own
% clock time.

if nargin < 5 || isempty(cfg), cfg = wf_config(); end

P       = wf_paths();
outFile = fullfile(outDir, 'baseline_drift_4.mat');

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  step 4: already done (%s)', wf_short(outFile));
    return;
end

assert(exist(dayPointer, 'file') == 2, 'wf_step4:noPointer', ...
    'Day pointer not found:\n  %s', dayPointer);
assert(exist(maskFile, 'file') == 2, 'wf_step4:noMask', ...
    'Brain mask not found:\n  %s', maskFile);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

answers = wf_ans( ...
    'uigetfile', 'Select day pointer',  dayPointer, ...
    'uigetfile', 'brain_mask',          maskFile, ...
    'uigetdir',  'Select output folder', outDir);

wf_log('  step 4: fitting baseline drift across the 0 uA trials');
wf_run_script(P.(track).step4, answers, ...
    struct('strict', cfg.strict_dialogs, 'addpath', {{P.(track).functions}}));

assert(exist(outFile, 'file') == 2, 'wf_step4:noOutput', ...
    'Step 4 finished but did not produce:\n  %s', outFile);
wf_log('  step 4: saved %s', wf_short(outFile));

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
