function prep = wf_prepare_experiment(e, cfg, idx, total)
%WF_PREPARE_EXPERIMENT  Phase 1: everything for one experiment that needs you.
%
%   prep = WF_PREPARE_EXPERIMENT(e, cfg, idx, total)
%
% Does the three things a person has to answer, and nothing else:
%
%   output folder   created, with its log file opened
%   pre-step A      find or build the retinotopy input, and show you the maps
%                   so you can confirm they belong to this experiment
%   step 0          automatic brain mask, you approve or adjust it
%   step 6          you align retinotopy to the stim image, re-aligning until
%                   it looks right
%
% WF_AUTO_RUN calls this for every selected experiment before it processes
% any of them, so with five experiments you answer everything at the start
% and the machine then works through all five without interrupting you.
%
% Returns
%   prep.ok         true when phase 2 can run this experiment
%   prep.status     'ready' | 'stopped' | 'failed' | 'skipped'
%   prep.maskFile   brain mask for every session
%   prep.daySetup   step 6 output, '' when there is no V1 overlay
%   prep.retino     the confirmed retinotopy input, '' when skipped
%   prep.logFile    log this experiment writes to, reused in phase 2

if nargin < 3, idx   = 1; end
if nargin < 4, total = 1; end
if nargin < 2 || isempty(cfg), cfg = wf_config(); end

prep          = struct();
prep.subject  = e.subject;
prep.date     = e.date;
prep.out_dir  = e.out_dir;
prep.ok       = false;
prep.status   = 'failed';
prep.message  = '';
prep.maskFile = '';
prep.daySetup = '';
prep.retino   = '';
prep.logFile  = '';

outDir = e.out_dir;
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

logDir = fullfile(outDir, 'logs');
if exist(logDir, 'dir') ~= 7, mkdir(logDir); end
logFile = fullfile(logDir, sprintf('run_%s.log', datestr(now, 'yyyymmdd_HHMMSS')));
prep.logFile = logFile;

diaryOn = cfg.capture_script_output;
if diaryOn
    if strcmp(get(0, 'Diary'), 'on'), diary off; end
    diary(logFile);
    wf_log('open', '');
else
    wf_log('open', logFile);
end
setappdata(0, 'WF_CURRENT_LOG', logFile);

wf_log('================================================================');
wf_log('SETUP %d of %d   %s  %s   [%s, %d session(s)]', ...
    idx, total, e.subject, e.date, e.track, e.n);
wf_log('output -> %s', outDir);
wf_log('================================================================');

attempt = 0;

while true
    attempt = attempt + 1;
    if attempt > 1
        wf_log('---- setup retry %d ----', attempt - 1);
    end

    try
        %% ---- retinotopy input, confirmed by you --------------------
        wf_checkpoint('before the retinotopy check');
        retDir     = fullfile(outDir, 'step6_V1overlay');
        retinoFile = e.retino;

        if cfg.retino.enabled
            % Anything the scanner found is passed in as a hint: it gets
            % copied into this experiment's folder and offered for
            % confirmation first, so the experiment owns the exact input it
            % was analysed against.
            retinoFile = wf_step_retino_combine(e.track, e.subject, e.date, ...
                retDir, wf_disk_root(e), cfg, retinoFile);
        else
            retinoFile = '';
            wf_log('  step 6 disabled: no retinotopy, no V1 overlay');
        end
        prep.retino = retinoFile;

        %% ---- brain mask -------------------------------------------
        wf_checkpoint('before the brain mask');
        prep.maskFile = wf_step0_auto_mask(e.sessions(1).img_dir, ...
            e.subject, e.date, outDir, cfg);

        %% ---- alignment --------------------------------------------
        wf_checkpoint('before the alignment');
        prep.daySetup = wf_step6_retino(e.track, prep.maskFile, retinoFile, ...
            e.subject, e.date, retDir, cfg);

        prep.ok      = true;
        prep.status  = 'ready';
        prep.message = 'setup complete';
        wf_log('SETUP DONE  %s %s', e.subject, e.date);
        break;

    catch err

        if strcmp(err.identifier, 'wf:stopped')
            prep.status  = 'stopped';
            prep.message = err.message;
            wf_log('SETUP STOPPED  %s %s  (%s)', e.subject, e.date, err.message);
            break;
        end

        if wf_is_interrupt(err)
            prep.status  = 'stopped';
            prep.message = 'interrupted with Ctrl+C';
            wf_stop('request', 'Ctrl+C');
            wf_log('SETUP STOPPED  %s %s  (Ctrl+C)', e.subject, e.date);
            break;
        end

        wf_log('SETUP ERROR in %s %s', e.subject, e.date);
        wf_log('  %s', err.message);
        for k = 1:numel(err.stack)
            wf_log('    at %s line %d', err.stack(k).name, err.stack(k).line);
        end

        switch wf_error_choice(e, err, cfg, 'setup')
            case 'retry'
                continue;
            case 'skip'
                prep.status  = 'failed';
                prep.message = err.message;
                wf_log('Skipping %s %s.', e.subject, e.date);
                break;
            case 'stop'
                prep.status  = 'failed';
                prep.message = err.message;
                wf_stop('request', sprintf('error setting up %s %s', e.subject, e.date));
                break;
        end
    end
end

if diaryOn, diary off; end
wf_log('close');

end

% =====================================================================
function wf_checkpoint(where)

if wf_stop('check')
    reason = wf_stop('reason');
    if isempty(reason), reason = 'stop requested'; end
    error('wf:stopped', 'Stopped %s (%s).', where, reason);
end

end

% =====================================================================
function r = wf_disk_root(e)

if isfield(e, 'disk_root') && ~isempty(e.disk_root)
    r = e.disk_root;
else
    r = fileparts(fileparts(e.sessions(1).img_dir));
end

end

% =====================================================================
function tf = wf_is_interrupt(err)

tf = ~isempty(strfind(lower(err.identifier), 'interrupt')) || ...
     strcmpi(strtrim(err.message), 'operation terminated by user during matlab');

end
