function outFile = wf_step2_align(track, imgDir, maskFile, rippleMat, csvFile, ...
                                  subject, dateStr, outDir, sessionLabel, cfg)
%WF_STEP2_ALIGN  Step 2: align widefield frames to stim timing.
%
%   outFile = WF_STEP2_ALIGN(track, imgDir, maskFile, rippleMat, csvFile, ...
%                            subject, dateStr, outDir, sessionLabel, cfg)
%
% sessionLabel is '' for a single-session experiment. On the combined track
% it becomes part of the output filename ('session1', 'session2', ...), which
% is what keeps three same-day sessions from overwriting each other.

if nargin < 10 || isempty(cfg), cfg = wf_config(); end
if nargin <  9, sessionLabel = ''; end

P = wf_paths();

if isempty(sessionLabel)
    outFile = fullfile(outDir, sprintf('%s_%s_wf_trial_alignment.mat', subject, dateStr));
else
    outFile = fullfile(outDir, sprintf('%s_%s_%s_wf_trial_alignment.mat', ...
        subject, dateStr, sessionLabel));
end

if cfg.resume && exist(outFile, 'file') == 2
    wf_log('  step 2: already done (%s)', wf_short(outFile));
    return;
end

assert(exist(imgDir,    'dir')  == 7, 'wf_step2:noImgDir', 'TIFF folder not found:\n  %s', imgDir);
assert(exist(maskFile,  'file') == 2, 'wf_step2:noMask',   'Brain mask not found:\n  %s', maskFile);
assert(exist(rippleMat, 'file') == 2, 'wf_step2:noRipple', 'Step 1 output not found:\n  %s', rippleMat);
assert(exist(csvFile,   'file') == 2, 'wf_step2:noCsv', ...
    ['Trial-design CSV not found:\n  %s\n' ...
     'Step 2 needs the CSV listing trial_index, stim_chan and current_uA.'], csvFile);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

answers = wf_ans( ...
    'uigetdir',  'folder containing TIFF frames',     imgDir, ...
    'uigetfile', 'brain_mask.*day_setup',            maskFile, ...
    'uigetfile', 'ripple_timing',                     rippleMat, ...
    'uigetfile', 'Select CSV',                        csvFile, ...
    'uigetdir',  'output folder for analysis results', outDir);

% The combined-track step 2 asks for a session label; the single-track one
% never does. An unused answer is reported as a warning, not an error, so it
% is safe to always supply it.
if strcmp(track, 'combined')
    answers(end+1) = struct('kind', 'inputdlg', ...
                            'pattern', 'Session label', ...
                            'value', {{sessionLabel}});
end

% Fallback metadata prompt, only reached if subject/date cannot be recovered
% from the mask file or the ripple timing file.
answers(end+1) = struct('kind', 'inputdlg', ...
                        'pattern', 'Metadata \(missing', ...
                        'value', {{subject, dateStr}});

wf_log('  step 2: aligning widefield frames to stim timing%s', ...
    wf_label_suffix(sessionLabel));
wf_run_script(P.(track).step2, answers, ...
    struct('strict', cfg.strict_dialogs, 'addpath', {{P.(track).functions}}));

assert(exist(outFile, 'file') == 2, 'wf_step2:noOutput', ...
    'Step 2 finished but did not produce:\n  %s', outFile);
wf_log('  step 2: saved %s', wf_short(outFile));

end

% =====================================================================
function s = wf_label_suffix(lbl)

if isempty(lbl), s = ''; else, s = sprintf(' [%s]', lbl); end

end

% =====================================================================
function s = wf_short(p)

[d, n, e] = fileparts(p);
[~, dn]   = fileparts(d);
s = fullfile(dn, [n e]);

end
