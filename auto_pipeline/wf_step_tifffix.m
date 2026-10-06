function outFile = wf_step_tifffix(track, correctionMat, dayPointerMat, cfg)
%WF_STEP_TIFFFIX  TIFF-fix: apply the correction map to the day pointer.
%
%   outFile = WF_STEP_TIFFFIX(track, correctionMat, dayPointerMat, cfg)
%
% Converts onset indices from SMA1 trigger numbers to TIFF file positions and
% drops any trial whose analysis window contains a missing frame. Returns the
% path to <dayPointer>_tiff_corrected.mat, which is the file steps 4 and 5_A
% must use from here on.

if nargin < 4 || isempty(cfg), cfg = wf_config(); end

P = wf_paths();

[d, n, e] = fileparts(dayPointerMat);
outFile   = fullfile(d, [n '_tiff_corrected' e]);

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  tiff-fix: already done (%s)', wf_short(outFile));
    return;
end

assert(exist(correctionMat, 'file') == 2, 'wf_tifffix:noCorrection', ...
    'Correction map not found:\n  %s', correctionMat);
assert(exist(dayPointerMat, 'file') == 2, 'wf_tifffix:noPointer', ...
    'Day pointer not found:\n  %s', dayPointerMat);

answers = wf_ans( ...
    'uigetfile', 'tiff_correction',  correctionMat, ...
    'uigetfile', 'day_pointer',      dayPointerMat);

wf_log('  tiff-fix: applying frame correction to day pointer');
wf_run_script(P.(track).tifffix, answers, struct('strict', cfg.strict_dialogs));

assert(exist(outFile, 'file') == 2, 'wf_tifffix:noOutput', ...
    'TIFF-fix finished but did not produce:\n  %s', outFile);
wf_log('  tiff-fix: saved %s', wf_short(outFile));

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
