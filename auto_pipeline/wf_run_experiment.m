function report = wf_run_experiment(e, prep, cfg)
%WF_RUN_EXPERIMENT  Phase 2: run one prepared experiment through to step 5_A.
%
%   report = WF_RUN_EXPERIMENT(e, prep, cfg)
%
% e is one element of the struct array from WF_SCAN_DISK; prep is what
% WF_PREPARE_EXPERIMENT returned for it, carrying the brain mask and the
% day_setup you already approved.
%
% Nothing here opens a window. Every decision was taken during phase 1, so a
% batch of five experiments runs start to finish unattended.
%
%     step 1      Ripple stim and camera timing        per session
%     TIFF-check  frame correction map                 per session
%     step 2      align widefield frames to stim       per session
%     step 3      day pointer                          per session
%     TIFF-fix    apply frame correction               per session
%     step 4      baseline drift model                 per session
%     step 5_A    dF/F movies, per-trial baseline      once, pooling sessions
%
% report.status is 'ok', 'failed' or 'stopped'.
%
% STOPPING
%   A stop requested from the GUI is honoured at each boundary marked below.
%   It cannot interrupt a step already grinding through TIFFs - see WF_STOP.
%   Ctrl+C stops immediately and is reported as a clean stop, not a crash.
%
% ERRORS
%   With cfg.on_error 'ask', a failing step offers Retry, Skip this
%   experiment, or Stop everything. Retry re-enters with finished steps
%   skipped, so it resumes at the step that failed.
%
% OUTPUT LAYOUT   C:\...\WF_result\{SUBJECT}_{MMDDYYYY}\
%     {subject}_{date}_brain_mask.mat
%     prep_steps\                  single-session intermediates
%     prep_steps\session1..3\      one folder per session when combining
%     step6_V1overlay\             retinotopy input + day_setup with V1
%     Step4_baseline_drift\        drift model and QC figures
%     Step5A_method0\              THE RESULT: one folder per ch/current
%     logs\                        full transcript of the run

if nargin < 3 || isempty(cfg), cfg = wf_config(); end

report          = struct();
report.subject  = e.subject;
report.date     = e.date;
report.track    = e.track;
report.out_dir  = e.out_dir;
report.status   = 'running';
report.message  = '';
report.started  = now;
report.step5A   = '';
report.finished = now;
report.log      = prep.logFile;

outDir = e.out_dir;

% Phase 1 opened this log; append to the same file so one experiment has one
% transcript covering setup and analysis together.
diaryOn = cfg.capture_script_output;
if diaryOn
    if strcmp(get(0, 'Diary'), 'on'), diary off; end
    diary(prep.logFile);
    wf_log('open', '');
else
    wf_log('open', prep.logFile);
end
setappdata(0, 'WF_CURRENT_LOG', prep.logFile);

wf_log(' ');
wf_log('================================================================');
wf_log('ANALYSIS  %s  %s   [%s pipeline, %d session(s)]', ...
    e.subject, e.date, e.track, e.n);
wf_log('================================================================');

attempt = 0;

while true
    attempt = attempt + 1;
    if attempt > 1
        wf_log(' ');
        wf_log('---- retry %d for %s %s ----', attempt - 1, e.subject, e.date);
    end

    try
        wf_do_experiment(e, prep, cfg, outDir);
        step5Dir       = fullfile(outDir, 'Step5A_method0');
        report.status  = 'ok';
        report.step5A  = step5Dir;
        report.message = sprintf('%d condition folder(s)', numel(wf_cond_count(step5Dir)));
        wf_log('DONE  %s %s  ->  %s', e.subject, e.date, step5Dir);
        break;

    catch err

        if strcmp(err.identifier, 'wf:stopped')
            report.status  = 'stopped';
            report.message = err.message;
            wf_log('STOPPED  %s %s  (%s)', e.subject, e.date, err.message);
            break;
        end

        if wf_is_interrupt(err)
            report.status  = 'stopped';
            report.message = 'interrupted with Ctrl+C';
            wf_stop('request', 'Ctrl+C');
            wf_log('STOPPED  %s %s  (Ctrl+C)', e.subject, e.date);
            break;
        end

        wf_log('ERROR in %s %s', e.subject, e.date);
        wf_log('  %s', err.message);
        for k = 1:numel(err.stack)
            wf_log('    at %s line %d', err.stack(k).name, err.stack(k).line);
        end

        switch wf_error_choice(e, err, cfg, 'analysis')
            case 'retry'
                continue;

            case 'skip'
                report.status  = 'failed';
                report.message = err.message;
                wf_log('Skipping %s %s and moving on.', e.subject, e.date);
                break;

            case 'stop'
                report.status  = 'failed';
                report.message = err.message;
                wf_stop('request', sprintf('error in %s %s', e.subject, e.date));
                wf_log('Stopping the whole batch at the user''s request.');
                break;
        end
    end
end

report.finished = now;

if diaryOn, diary off; end
wf_log('close');

end

% =====================================================================
function wf_do_experiment(e, prep, cfg, outDir)
%WF_DO_EXPERIMENT  The unattended sequence. Raises wf:stopped when interrupted.

maskFile = prep.maskFile;
daySetup = prep.daySetup;

assert(exist(maskFile, 'file') == 2, 'wf_run:noMask', ...
    ['The brain mask from setup is missing:\n  %s\n' ...
     'Re-run this experiment so setup can produce it again.'], maskFile);

pointers = cell(1, e.n);

for s = 1:e.n
    ses = e.sessions(s);

    if strcmp(e.track, 'single')
        sesDir   = fullfile(outDir, 'prep_steps');
        label    = '';
        sesId    = sprintf('%s_%s', e.subject, e.date);
        baseName = cfg.base_name;
        drfDir   = fullfile(outDir, 'Step4_baseline_drift');
    else
        sesDir   = fullfile(outDir, 'prep_steps', ses.label);
        label    = ses.label;
        sesId    = sprintf('%s_%s_%s', e.subject, e.date, ses.label);
        baseName = sprintf('%s_%s', ses.label, cfg.base_name);
        drfDir   = fullfile(outDir, 'Step4_baseline_drift', ses.label);
    end
    if exist(sesDir, 'dir') ~= 7, mkdir(sesDir); end

    wf_log('---- session %d of %d%s', s, e.n, wf_suffix(label));
    wf_log('     images : %s', ses.img_dir);
    wf_log('     ripple : %s', ses.nev);
    wf_log('     trials : %s', ses.csv);

    scfg = cfg;
    scfg.base_name = baseName;

    wf_checkpoint(sprintf('before step 1 (session %d)', s));
    rippleMat = wf_step1_ripple(e.track, ses.nev, e.subject, e.date, sesDir, scfg);

    wf_checkpoint(sprintf('before TIFF-check (session %d)', s));
    corrMat   = wf_step_tiffcheck(e.track, ses.img_dir, rippleMat, sesDir, sesId, cfg);

    wf_checkpoint(sprintf('before step 2 (session %d)', s));
    alignMat  = wf_step2_align(e.track, ses.img_dir, maskFile, rippleMat, ses.csv, ...
                               e.subject, e.date, sesDir, label, cfg);

    wf_checkpoint(sprintf('before step 3 (session %d)', s));
    pointer   = wf_step3_container(e.track, alignMat, e.subject, e.date, label, cfg);

    wf_checkpoint(sprintf('before TIFF-fix (session %d)', s));
    pointers{s} = wf_step_tifffix(e.track, corrMat, pointer, cfg);

    if cfg.run_step4
        wf_checkpoint(sprintf('before step 4 (session %d)', s));
        wf_step4_drift(e.track, pointers{s}, maskFile, drfDir, cfg);
    else
        wf_log('  step 4: skipped (run_step4 is off; Method 1 tracks will need it)');
    end
end

wf_checkpoint('before step 5A');
step5Dir = fullfile(outDir, 'Step5A_method0');
wf_step5A(e.track, pointers, maskFile, daySetup, step5Dir, cfg);

end

% =====================================================================
function wf_checkpoint(where)
%WF_CHECKPOINT  Honour a stop request at a safe point between steps.

if wf_stop('check')
    reason = wf_stop('reason');
    if isempty(reason), reason = 'stop requested'; end
    error('wf:stopped', 'Stopped %s (%s).', where, reason);
end

end

% =====================================================================
function tf = wf_is_interrupt(err)

tf = ~isempty(strfind(lower(err.identifier), 'interrupt')) || ...
     strcmpi(strtrim(err.message), 'operation terminated by user during matlab');

end

% =====================================================================
function c = wf_cond_count(d)

if exist(d, 'dir') ~= 7, c = {}; return; end
listing = dir(fullfile(d, 'ch*uA'));
c = {listing([listing.isdir]).name};

end

% =====================================================================
function s = wf_suffix(lbl)

if isempty(lbl), s = ''; else, s = sprintf('  [%s]', lbl); end

end
