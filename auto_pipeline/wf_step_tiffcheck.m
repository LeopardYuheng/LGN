function outFile = wf_step_tiffcheck(track, imgDir, rippleMat, outDir, sessionId, cfg)
%WF_STEP_TIFFCHECK  TIFF-check: build the TIFF-SMA1 frame correction map.
%
%   outFile = WF_STEP_TIFFCHECK(track, imgDir, rippleMat, outDir, sessionId, cfg)
%
% Required for every session, both as a dropped-frame correction and as a QC
% check. Returns the path to {sessionId}_tiff_correction.mat.
%
% build_tiff_sma1_correction_map.m asks for its session ID with a console
% INPUT() call rather than a dialog, and INPUT is a MATLAB built-in that
% cannot be safely shadowed. That one line is therefore rewritten in a
% temporary copy of the script; the original file is left untouched.

if nargin < 6 || isempty(cfg), cfg = wf_config(); end

P       = wf_paths();
outFile = fullfile(outDir, sprintf('%s_tiff_correction.mat', sessionId));

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  tiff-check: already done (%s)', wf_short(outFile));
    return;
end

if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

answers = wf_ans( ...
    'uigetdir',  'Select TIFF image folder',            imgDir, ...
    'uigetfile', 'Select ripple_timing',                rippleMat, ...
    'uigetdir',  'output folder for tiff_correction',   outDir);

% Replace   SESSION_ID = input('...', 's');   with a literal assignment.
patch = { '(?m)^\s*SESSION_ID\s*=\s*input\(.*$', ...
          sprintf('SESSION_ID = ''%s'';', strrep(sessionId, '''', '''''')) };

wf_log('  tiff-check: cross-referencing TIFF timestamps against SMA1 triggers');
wf_run_script(P.(track).tiffcheck, answers, struct( ...
    'strict', cfg.strict_dialogs, ...
    'patch',  {patch}));

assert(exist(outFile, 'file') == 2, 'wf_tiffcheck:noOutput', ...
    'TIFF-check finished but did not produce:\n  %s', outFile);

info = load(outFile, 'dropped_sma1_idx', 'N_SMA1', 'N_TIFF');
wf_log('  tiff-check: %d SMA1 triggers, %d TIFFs, %d dropped frame(s)', ...
    info.N_SMA1, info.N_TIFF, numel(info.dropped_sma1_idx));

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
