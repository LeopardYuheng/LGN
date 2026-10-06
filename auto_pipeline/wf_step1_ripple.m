function outFile = wf_step1_ripple(track, nevFile, subject, dateStr, outDir, cfg)
%WF_STEP1_RIPPLE  Step 1: extract Ripple stim and camera timing from the .nev.
%
%   outFile = WF_STEP1_RIPPLE(track, nevFile, subject, dateStr, outDir, cfg)
%
% track is 'single' or 'combined'. Returns the path to the saved
% {subject}_{date}_{base_name}.mat.
%
% NOTE ON THE METADATA DIALOG
% ---------------------------
% extract_nev_stim_and_camera_1.m reads its four dialog fields as:
%     mouse_id      = answ{1}
%     experiment_id = answ{2}     <- field labelled "Date (YYYYMMDD)"
%     date_str      = answ{3}     <- field labelled "Experiment ID"
% Fields 2 and 3 are swapped relative to their labels in the script itself.
% The answers below are supplied in the order the script READS them, so the
% date lands in date_str and the output filename is correct. If that script
% is ever fixed, swap the middle two entries here to match.

if nargin < 6 || isempty(cfg), cfg = wf_config(); end

P    = wf_paths();
base = cfg.base_name;
if isempty(base), base = 'ripple_timing'; end

outFile = fullfile(outDir, sprintf('%s_%s_%s.mat', subject, dateStr, base));

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  step 1: already done (%s)', wf_short(outFile));
    return;
end

assert(exist(nevFile, 'file') == 2, 'wf_step1:noNev', ...
    'Ripple .nev file not found:\n  %s', nevFile);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

answers = wf_ans( ...
    'inputdlg',  'Session Metadata',                    {subject, cfg.experiment_id, dateStr, base}, ...
    'uigetdir',  'output folder to save session',       outDir, ...
    'uigetfile', 'Select Ripple .nev file',             nevFile);

wf_log('  step 1: extracting stim and camera timing from %s', wf_short(nevFile));
wf_run_script(P.(track).step1, answers, ...
    struct('strict', cfg.strict_dialogs, 'addpath', {{P.(track).neuroshare}}));

assert(exist(outFile, 'file') == 2, 'wf_step1:noOutput', ...
    'Step 1 finished but did not produce:\n  %s', outFile);
wf_log('  step 1: saved %s', wf_short(outFile));

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
