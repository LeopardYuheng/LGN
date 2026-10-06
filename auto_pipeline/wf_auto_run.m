function reports = wf_auto_run(varargin)
%WF_AUTO_RUN  Run the widefield pipeline over everything on the portable disk.
%
%   reports = WF_AUTO_RUN()
%       Find the disk, scan it, confirm the list with you, run every
%       experiment through to step 5_A output.
%
%   reports = WF_AUTO_RUN('experiments', E)
%       Run a list you already have, e.g. the rows ticked in the GUI.
%
%   reports = WF_AUTO_RUN('disk', 'E:\')            use this disk
%   reports = WF_AUTO_RUN('confirm', false)         skip the confirmation
%   reports = WF_AUTO_RUN('config', cfg)            use a modified config
%
% Returns one report struct per experiment, with .status 'ok' or 'failed'.

p = wf_parse_args(varargin);
cfg = p.config;

% Note: the log sink is deliberately left alone here. When the GUI started
% this run it has registered a sink to mirror progress into its pane, and
% resetting it would blind the window for the whole batch.
wf_log('Widefield auto pipeline, %s', datestr(now, 'yyyy-mm-dd HH:MM'));

%% ---- sanity check the installation ------------------------------------
[pathsOk, missing] = wf_check_paths();
if ~pathsOk
    error('wf_auto_run:missingScripts', ...
        ['Some pipeline scripts are missing. Check cfg.pipeline_root in ' ...
         'wf_config.m points at your analysis repository.\n  %s'], strjoin(missing, sprintf('\n  ')));
end

%% ---- find the experiments ---------------------------------------------
if ~isempty(p.experiments)
    experiments = p.experiments;
else
    diskRoot = p.disk;
    if isempty(diskRoot), diskRoot = wf_find_disk(cfg); end

    if isempty(diskRoot)
        error('wf_auto_run:noDisk', ...
            ['No portable disk with imaging data was found on %s\n' ...
             'Connect the disk, or set cfg.disk_root in wf_config.m.'], ...
            strjoin(cfg.disk_search_letters, ' '));
    end
    wf_log('Disk: %s', diskRoot);

    [experiments, problems] = wf_scan_disk(diskRoot, cfg);

    if isempty(experiments)
        error('wf_auto_run:nothingFound', ...
            ['No complete experiments found on %s\n' ...
             'Either the folder naming does not match cfg.id_patterns, or the ' ...
             '.nev / trial CSV files are somewhere the scanner does not look.'], diskRoot);
    end

    for i = 1:numel(problems)
        wf_log('  ! %s', problems{i});
    end
end

wf_log('%d experiment(s) detected:', numel(experiments));
for i = 1:numel(experiments)
    e = experiments(i);
    wf_log('  %-8s %-10s %-9s %d session(s)  %s', ...
        e.subject, e.date, e.track, e.n, e.notes);
    wf_log('           -> %s', e.out_dir);
end

%% ---- confirmation ------------------------------------------------------
if p.confirm && cfg.confirm_before_run
    experiments = wf_confirm_gui(experiments, cfg);
    if isempty(experiments)
        wf_log('Cancelled - nothing was run.');
        reports = struct([]);
        return;
    end
end

% Two experiments sharing one output folder would overwrite each other's
% prep_steps and Step5A_method0 silently, and the damage would only show up
% as results that do not match the data. Refuse rather than allow it.
outDirs = lower({experiments.out_dir});
if numel(unique(outDirs)) < numel(outDirs)
    [~, firstIdx] = unique(outDirs, 'stable');
    dupIdx = setdiff(1:numel(outDirs), firstIdx);
    error('wf_auto_run:duplicateOutput', ...
        ['More than one experiment is set to write into the same folder, ' ...
         'for example:\n  %s\nGive each experiment its own output folder.'], ...
        experiments(dupIdx(1)).out_dir);
end

runnable = experiments(logical([experiments.ok]));
skipped  = experiments(~logical([experiments.ok]));

for i = 1:numel(skipped)
    wf_log('Skipping %s %s: %s', skipped(i).subject, skipped(i).date, skipped(i).notes);
end

if isempty(runnable)
    wf_log('Nothing runnable - every detected experiment is missing a required file.');
    reports = struct([]);
    return;
end

%% ---- run ---------------------------------------------------------------
reports = struct('subject', {}, 'date', {}, 'track', {}, 'out_dir', {}, ...
                 'status', {}, 'message', {}, 'started', {}, 'step5A', {}, ...
                 'finished', {}, 'log', {});

% Armed here, and deliberately NOT cleared on the way out: the caller needs
% to be able to ask afterwards whether the batch was stopped or ran to the
% end. The next run's 'arm' clears it.
wf_stop('arm', cfg.output_root);

t0 = tic;

%% ---- PHASE 1: everything that needs you, for every experiment ---------
% Front-loading the interactive work is the whole point of this ordering.
% Five experiments means answering five sets of windows now, then nothing
% for the hours the analysis takes, instead of being called back to the
% machine between every one.
wf_log(' ');
wf_log('################  SETUP PHASE  ################');
wf_log('Retinotopy check, brain mask and alignment for %d experiment(s).', ...
    numel(runnable));
wf_log('Once these are done the rest runs without asking anything.');

preps = struct('subject', {}, 'date', {}, 'out_dir', {}, 'ok', {}, ...
               'status', {}, 'message', {}, 'maskFile', {}, 'daySetup', {}, ...
               'retino', {}, 'logFile', {});

for i = 1:numel(runnable)

    if wf_stop('check')
        wf_log(' ');
        wf_log('Stopped during setup (%s). %d experiment(s) not set up.', ...
            wf_stop('reason'), numel(runnable) - i + 1);
        break;
    end

    wf_log(' ');
    preps(end+1) = wf_prepare_experiment(runnable(i), cfg, i, numel(runnable)); %#ok<AGROW>
end

ready = false(1, numel(runnable));
for i = 1:numel(preps)
    ready(i) = preps(i).ok;
end

wf_log(' ');
wf_log('Setup finished: %d of %d experiment(s) ready to analyse.', ...
    sum(ready), numel(runnable));
for i = 1:numel(preps)
    if ~preps(i).ok
        wf_log('  not ready: %s %s (%s)', ...
            preps(i).subject, preps(i).date, preps(i).status);
    end
end

if ~any(ready)
    wf_log('Nothing to analyse.');
    wf_write_summary(cfg.output_root, reports);
    return;
end

%% ---- PHASE 2: unattended -----------------------------------------------
wf_log(' ');
wf_log('################  ANALYSIS PHASE  ################');
wf_log('%d experiment(s), no further input needed. Safe to leave.', sum(ready));

order = find(ready);
for k = 1:numel(order)
    i = order(k);

    if wf_stop('check')
        wf_log(' ');
        wf_log('Stopped before %s %s (%s). %d experiment(s) not started.', ...
            runnable(i).subject, runnable(i).date, wf_stop('reason'), ...
            numel(order) - k + 1);
        break;
    end

    wf_log(' ');
    wf_log('[%d/%d] %s %s', k, numel(order), runnable(i).subject, runnable(i).date);
    reports(end+1) = wf_run_experiment(runnable(i), preps(i), cfg); %#ok<AGROW>
end

%% ---- summary -----------------------------------------------------------
wf_log(' ');
wf_log('================ SUMMARY  (%s) ================', wf_duration(toc(t0)));
nOk = 0;
for i = 1:numel(reports)
    r = reports(i);
    switch r.status
        case 'ok'
            nOk = nOk + 1;
            wf_log('  OK       %s %s   %s', r.subject, r.date, r.step5A);
        case 'stopped'
            wf_log('  STOPPED  %s %s   %s', r.subject, r.date, r.message);
            wf_log('           finished steps are kept; re-running resumes here');
        otherwise
            wf_log('  FAILED   %s %s   %s', r.subject, r.date, r.message);
            wf_log('           log: %s', r.log);
    end
end
wf_log('%d of %d experiment(s) completed.', nOk, numel(reports));

wf_write_summary(cfg.output_root, reports);

end

% =====================================================================
function p = wf_parse_args(args)

% Built field by field on purpose: struct('experiments', struct([]), ...)
% would collapse the whole thing to a 0-by-0 struct array, because struct()
% expands an empty struct value into zero elements.
p             = struct();
p.experiments = struct([]);
p.disk        = '';
p.confirm     = true;
p.config      = wf_config();

for i = 1:2:numel(args)-1
    switch lower(args{i})
        case 'experiments', p.experiments = args{i+1};
        case 'disk',        p.disk        = args{i+1};
        case 'confirm',     p.confirm     = logical(args{i+1});
        case 'config',      p.config      = args{i+1};
        otherwise
            error('wf_auto_run:badArg', 'Unknown option "%s".', args{i});
    end
end

end

% =====================================================================
function wf_write_summary(outRoot, reports)
%WF_WRITE_SUMMARY  One line per run, appended to WF_result\pipeline_runs.csv.

if isempty(reports), return; end
if exist(outRoot, 'dir') ~= 7, mkdir(outRoot); end

f      = fullfile(outRoot, 'pipeline_runs.csv');
isNew  = exist(f, 'file') ~= 2;

fid = fopen(f, 'a');
if fid < 0, return; end

if isNew
    fprintf(fid, 'finished,subject,date,track,status,message,output\r\n');
end
for i = 1:numel(reports)
    r = reports(i);
    fprintf(fid, '%s,%s,%s,%s,%s,"%s","%s"\r\n', ...
        datestr(r.finished, 'yyyy-mm-dd HH:MM:SS'), r.subject, r.date, ...
        r.track, r.status, strrep(r.message, '"', ''''), r.out_dir);
end
fclose(fid);

end

% =====================================================================
function s = wf_duration(sec)

h = floor(sec / 3600);
m = floor(mod(sec, 3600) / 60);
s = sprintf('%dh %02dm', h, m);

end
