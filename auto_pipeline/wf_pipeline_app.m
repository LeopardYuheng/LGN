function wf_pipeline_app()
%WF_PIPELINE_APP  One-window front end for the automated widefield pipeline.
%
%   wf_pipeline_app
%
% Connect the portable disk, press Scan disk, check the list, press Run.
%
% THE PROGRESS PANE
%   Shows the tail of the log file in the output folder of the experiment
%   currently running. That log carries everything the original pipeline
%   scripts print, not just this tool's own messages, so you see the real
%   detail - which condition, which trial, how many frames.
%
%   MATLAB runs the analysis and this window on one thread, so the pane
%   cannot repaint while a step is inside a loop over TIFF frames; it
%   catches up at the end of each step. To watch a long step in real time,
%   press "Open log file" and keep that window open - the file is written
%   continuously regardless of what the interface is doing.
%
% STOPPING
%   Stop takes effect at the next step boundary, for the same
%   single-thread reason. For an immediate stop press Ctrl+C in the MATLAB
%   command window: that is caught and reported as a clean stop, and since
%   finished steps are skipped on the next run, nothing is wasted.

cfg = wf_config();

% HandleVisibility is off on purpose: every pipeline script begins with
% "close all", which would otherwise close this window mid-run. Hidden
% handles are left alone by close all, and explicit handles still work.
fig = figure('Name', 'LGN widefield pipeline', 'NumberTitle', 'off', ...
             'MenuBar', 'none', 'ToolBar', 'none', ...
             'Color', [0.96 0.96 0.97], ...
             'Position', [100 70 1140 800], ...
             'HandleVisibility', 'off', ...
             'CloseRequestFcn', @onClose);

%% ---- header ------------------------------------------------------------
uicontrol(fig, 'Style', 'text', 'String', 'LGN widefield analysis - step 0 to step 5_A', ...
    'Units', 'normalized', 'Position', [0.02 0.95 0.6 0.038], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 14, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

uicontrol(fig, 'Style', 'text', 'String', 'Disk:', ...
    'Units', 'normalized', 'Position', [0.02 0.905 0.04 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, ...
    'HorizontalAlignment', 'left');

hDisk = uicontrol(fig, 'Style', 'edit', 'String', '', ...
    'Units', 'normalized', 'Position', [0.06 0.903 0.42 0.032], ...
    'BackgroundColor', 'w', 'FontSize', 10, 'HorizontalAlignment', 'left');

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Browse...', ...
    'Units', 'normalized', 'Position', [0.49 0.903 0.09 0.034], ...
    'FontSize', 10, 'Callback', @onBrowse);

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Scan disk', ...
    'Units', 'normalized', 'Position', [0.59 0.903 0.12 0.034], ...
    'FontSize', 10, 'FontWeight', 'bold', 'Callback', @onScan);

hStatus = uicontrol(fig, 'Style', 'text', 'String', 'Ready.', ...
    'Units', 'normalized', 'Position', [0.72 0.903 0.26 0.03], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, ...
    'ForegroundColor', [0.25 0.35 0.6], 'HorizontalAlignment', 'right');

%% ---- experiment table ---------------------------------------------------
hTable = uitable(fig, 'Units', 'normalized', 'Position', [0.02 0.60 0.96 0.29], ...
    'Data', cell(0, 9), ...
    'ColumnName', {'Run', 'Subject', 'Date', 'Track', 'Sessions', ...
                   'Retinotopy', 'Results to', 'Output folder', 'Notes'}, ...
    'ColumnFormat', {'logical', 'char', 'char', {'single','combined'}, ...
                     'numeric', 'char', ...
                     {'WF_result','Next to data','Choose folder...','Custom'}, ...
                     'char', 'char'}, ...
    'ColumnEditable', [true false false true false false true true false], ...
    'ColumnWidth', {40, 70, 90, 85, 70, 85, 110, 330, 190}, ...
    'RowName', [], 'FontSize', 10, ...
    'CellEditCallback', @onTableEdit);

%% ---- options ------------------------------------------------------------
y = 0.555;
hStep4 = uicontrol(fig, 'Style', 'checkbox', 'String', 'Run step 4 (baseline drift QC)', ...
    'Units', 'normalized', 'Position', [0.02 y 0.22 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, 'Value', cfg.run_step4);

hRetino = uicontrol(fig, 'Style', 'checkbox', 'String', 'Run step 6 (V1 overlay)', ...
    'Units', 'normalized', 'Position', [0.24 y 0.18 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, 'Value', cfg.retino.enabled);

hResume = uicontrol(fig, 'Style', 'checkbox', 'String', 'Skip steps already done', ...
    'Units', 'normalized', 'Position', [0.42 y 0.18 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, 'Value', cfg.resume);

hVerify = uicontrol(fig, 'Style', 'checkbox', 'String', 'Verify mask and alignment', ...
    'Units', 'normalized', 'Position', [0.60 y 0.20 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, 'Value', cfg.mask.verify);

hAsk = uicontrol(fig, 'Style', 'checkbox', 'String', 'Ask me when a step fails', ...
    'Units', 'normalized', 'Position', [0.80 y 0.19 0.028], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, ...
    'Value', strcmpi(cfg.on_error, 'ask'));

%% ---- log ---------------------------------------------------------------
uicontrol(fig, 'Style', 'text', 'String', 'Progress', ...
    'Units', 'normalized', 'Position', [0.02 0.515 0.1 0.026], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

hLogPath = uicontrol(fig, 'Style', 'text', 'String', '(no log yet)', ...
    'Units', 'normalized', 'Position', [0.12 0.515 0.62 0.026], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 9, ...
    'ForegroundColor', [0.35 0.35 0.4], 'HorizontalAlignment', 'left');

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Refresh', ...
    'Units', 'normalized', 'Position', [0.75 0.512 0.10 0.032], ...
    'FontSize', 9, 'Callback', @(s,e) tailLog(fig, true));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Open log file', ...
    'Units', 'normalized', 'Position', [0.86 0.512 0.12 0.032], ...
    'FontSize', 9, 'Callback', @onOpenLog);

hLog = uicontrol(fig, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.02 0.115 0.96 0.39], ...
    'BackgroundColor', [1 1 1], 'FontName', 'Consolas', 'FontSize', 9, ...
    'Max', 2, 'Min', 0);

uicontrol(fig, 'Style', 'text', 'String', ...
    ['Stop takes effect at the next step boundary. For an immediate stop, ' ...
     'press Ctrl+C in the MATLAB command window - finished steps are kept.'], ...
    'Units', 'normalized', 'Position', [0.02 0.085 0.96 0.026], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 9, ...
    'ForegroundColor', [0.35 0.35 0.4], 'HorizontalAlignment', 'left');

%% ---- action buttons -----------------------------------------------------
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Run pipeline', ...
    'Units', 'normalized', 'Position', [0.02 0.02 0.19 0.055], ...
    'FontSize', 12, 'FontWeight', 'bold', 'Callback', @onRun);

hStop = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Stop', ...
    'Units', 'normalized', 'Position', [0.22 0.02 0.14 0.055], ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'ForegroundColor', [0.6 0.1 0.1], 'Enable', 'off', ...
    'Callback', @onStop);

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Open results folder', ...
    'Units', 'normalized', 'Position', [0.38 0.02 0.17 0.055], ...
    'FontSize', 10, 'Callback', @(s,e) wf_open_path(cfg.output_root));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Edit settings', ...
    'Units', 'normalized', 'Position', [0.57 0.02 0.13 0.055], ...
    'FontSize', 10, 'Callback', @(s,e) edit('wf_config'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Close', ...
    'Units', 'normalized', 'Position', [0.85 0.02 0.13 0.055], ...
    'FontSize', 10, 'Callback', @onClose);

%% ---- state --------------------------------------------------------------
% Field by field: struct('experiments', struct([]), ...) collapses to a
% 0-by-0 struct array, because struct() expands empty struct values.
S             = struct();
S.experiments = struct([]);
S.busy        = false;
S.logPath     = '';
S.logBytes    = -1;
S.hDisk       = hDisk;
S.hTable      = hTable;
S.hLog        = hLog;
S.hLogPath    = hLogPath;
S.hStatus     = hStatus;
S.hStop       = hStop;
S.hStep4      = hStep4;
S.hRetino     = hRetino;
S.hResume     = hResume;
S.hVerify     = hVerify;
S.hAsk        = hAsk;
S.cfg         = cfg;
guidata(fig, S);

wf_log('sink', @(line) onLogLine(fig, line));
setStatus(fig, 'Looking for the portable disk...');
d = wf_find_disk(cfg);
if isempty(d)
    setStatus(fig, 'No disk found - connect it and press Scan disk');
    appendLine(fig, 'No portable disk with imaging data detected yet.');
else
    set(hDisk, 'String', d);
    setStatus(fig, sprintf('Disk found: %s', d));
    onScan([], []);
end

%% =====================================================================
%  callbacks
%% =====================================================================

    function onBrowse(~, ~)
        start = get(hDisk, 'String');
        if isempty(start), start = pwd; end
        d2 = uigetdir(start, 'Select the disk or folder holding the imaging sessions');
        if ~isequal(d2, 0)
            set(hDisk, 'String', d2);
        end
    end

    function onScan(~, ~)
        St = guidata(fig);
        if St.busy, return; end

        root = strtrim(get(hDisk, 'String'));
        if isempty(root)
            root = wf_find_disk(St.cfg);
            set(hDisk, 'String', root);
        end
        if isempty(root) || exist(root, 'dir') ~= 7
            setStatus(fig, 'That folder does not exist');
            return;
        end

        setStatus(fig, 'Scanning...');
        drawnow;

        try
            [E, problems] = wf_scan_disk(root, St.cfg);
        catch err
            appendLine(fig, ['Scan failed: ' err.message]);
            setStatus(fig, 'Scan failed');
            return;
        end

        for i = 1:numel(problems)
            appendLine(fig, ['  ! ' problems{i}]);
        end

        St.experiments = E;
        guidata(fig, St);

        if strcmpi(St.cfg.output_location, 'with_data')
            defaultDest = 'Next to data';
        else
            defaultDest = 'WF_result';
        end

        data = cell(numel(E), 9);
        for i = 1:numel(E)
            data{i,1} = logical(E(i).ok);
            data{i,2} = E(i).subject;
            data{i,3} = E(i).date;
            data{i,4} = E(i).track;
            data{i,5} = E(i).n;
            if isempty(E(i).retino)
                data{i,6} = 'pre-step A';
            else
                data{i,6} = 'ready';
            end
            data{i,7} = defaultDest;
            data{i,8} = E(i).out_dir;
            data{i,9} = E(i).notes;
        end
        set(hTable, 'Data', data);

        setStatus(fig, sprintf('%d experiment(s) found', numel(E)));
        appendLine(fig, sprintf('Scan complete: %d experiment(s) on %s', numel(E), root));
    end

    function onRun(~, ~)
        St = guidata(fig);
        if St.busy
            setStatus(fig, 'Already running');
            return;
        end
        if isempty(St.experiments)
            setStatus(fig, 'Nothing to run - press Scan disk first');
            return;
        end

        data = get(hTable, 'Data');
        keep = false(size(data, 1), 1);
        E    = St.experiments;
        for i = 1:size(data, 1)
            keep(i)      = logical(data{i,1});
            E(i).track   = data{i,4};
            E(i).out_dir = strtrim(data{i,8});
            if strcmp(E(i).track, 'single') && E(i).n > 1
                E(i).sessions = E(i).sessions(1);
                E(i).n        = 1;
                E(i).sessions(1).label = '';
            end
        end
        E = E(keep);

        % Two experiments writing into one folder would overwrite each
        % other's prep_steps and Step5A_method0 without any warning.
        dirs = lower({E.out_dir});
        if numel(unique(dirs)) < numel(dirs)
            uiwait(msgbox(['Two or more experiments are pointing at the same ' ...
                'output folder. Give each one its own folder before running - ' ...
                'otherwise their results overwrite each other.'], ...
                'Duplicate output folders', 'error', 'modal'));
            setStatus(fig, 'Fix the duplicate output folders');
            return;
        end

        if isempty(E)
            setStatus(fig, 'No experiments ticked');
            return;
        end

        c = St.cfg;
        c.run_step4          = logical(get(hStep4,  'Value'));
        c.retino.enabled     = logical(get(hRetino, 'Value'));
        c.resume             = logical(get(hResume, 'Value'));
        c.mask.verify        = logical(get(hVerify, 'Value'));
        c.retino.verify      = c.mask.verify;
        c.confirm_before_run = false;
        if get(hAsk, 'Value')
            c.on_error = 'ask';
        else
            c.on_error = 'continue';
        end

        wf_stop('clear');
        St.busy = true;
        guidata(fig, St);
        set(hStop, 'Enable', 'on');
        setStatus(fig, sprintf('Running %d experiment(s)...', numel(E)));
        drawnow;

        try
            wf_auto_run('experiments', E, 'confirm', false, 'config', c);
            if wf_stop('check')
                setStatus(fig, 'Stopped');
            else
                setStatus(fig, 'Finished');
            end
        catch err
            appendLine(fig, ['Run failed: ' err.message]);
            setStatus(fig, 'Run failed');
        end

        tailLog(fig, true);

        St = guidata(fig);
        St.busy = false;
        guidata(fig, St);
        set(hStop, 'Enable', 'off');
    end

    function onTableEdit(src, evt)
        % Keep the "Results to" choice and the folder path in step.
        if isempty(evt.Indices), return; end

        St2  = guidata(fig);
        r    = evt.Indices(1);
        col  = evt.Indices(2);
        data = get(src, 'Data');

        if r > numel(St2.experiments), return; end
        ex = St2.experiments(r);

        switch col
            case 7
                switch data{r,7}
                    case 'WF_result'
                        data{r,8} = wf_output_dir(ex, 'result_root', '', St2.cfg);

                    case 'Next to data'
                        p = wf_output_dir(ex, 'with_data', '', St2.cfg);
                        if isempty(ex.data_dir)
                            uiwait(msgbox(sprintf(...
                                ['No data folder is known for %s %s, so results ' ...
                                 'cannot go next to the data.'], ex.subject, ex.date), ...
                                'No data folder', 'warn', 'modal'));
                            data{r,7} = 'WF_result';
                        end
                        data{r,8} = p;

                    case 'Choose folder...'
                        start = fileparts(data{r,8});
                        if isempty(start) || exist(start, 'dir') ~= 7
                            start = St2.cfg.output_root;
                        end
                        root = uigetdir(start, sprintf('Results folder for %s %s', ...
                            ex.subject, ex.date));
                        if isequal(root, 0)
                            data{r,7} = 'WF_result';
                            data{r,8} = wf_output_dir(ex, 'result_root', '', St2.cfg);
                        else
                            data{r,7} = 'Custom';
                            data{r,8} = wf_output_dir(ex, 'custom', root, St2.cfg);
                        end

                    case 'Custom'
                        % keep whatever path is there
                end

            case 8
                % A path typed by hand is a custom destination by definition.
                data{r,7} = 'Custom';
        end

        set(src, 'Data', data);
    end

    function onStop(~, ~)
        wf_stop('request', 'Stop pressed in the pipeline window');
        setStatus(fig, 'Stopping after the current step...');
        appendLine(fig, '>> Stop requested. Finishing the current step first.');
        appendLine(fig, '>> For an immediate stop, press Ctrl+C in the MATLAB window.');
    end

    function onOpenLog(~, ~)
        St = guidata(fig);
        p  = St.logPath;
        if isempty(p) || exist(p, 'file') ~= 2
            setStatus(fig, 'No log file yet');
            return;
        end
        wf_open_path(p);
    end

    function onClose(~, ~)
        St = guidata(fig);
        if ~isempty(St) && isfield(St, 'busy') && St.busy
            answer = questdlg(...
                ['The pipeline is still running. Closing this window will not ' ...
                 'stop it - use Stop for that. Close anyway?'], ...
                'Still running', 'Close', 'Keep open', 'Keep open');
            if ~strcmp(answer, 'Close'), return; end
        end
        wf_log('sink', []);
        delete(fig);
    end

end

% =====================================================================
function onLogLine(fig, line)
%ONLOGLINE  Called for every wf_log line: follow the experiment's log file.
%
% Once an experiment is running its log file has more in it than these
% lines alone - the original scripts' own output goes there too - so the
% pane is refreshed from the file rather than by appending.

if ~ishandle(fig), return; end

S = guidata(fig);
if isempty(S), return; end

current = '';
if isappdata(0, 'WF_CURRENT_LOG'), current = getappdata(0, 'WF_CURRENT_LOG'); end

if ~isempty(current) && exist(current, 'file') == 2
    if ~strcmp(current, S.logPath)
        S.logPath  = current;
        S.logBytes = -1;
        guidata(fig, S);
        set(S.hLogPath, 'String', current);
    end
    tailLog(fig, false);
else
    appendLine(fig, line);
end

end

% =====================================================================
function tailLog(fig, force)
%TAILLOG  Show the last lines of the log file being followed.

if ~ishandle(fig), return; end
S = guidata(fig);
if isempty(S) || isempty(S.logPath) || exist(S.logPath, 'file') ~= 2, return; end

d = dir(S.logPath);
if isempty(d), return; end
if ~force && d(1).bytes == S.logBytes, return; end   % nothing new

S.logBytes = d(1).bytes;
guidata(fig, S);

txt = '';
try
    txt = fileread(S.logPath);
catch
    return;      % being written to right now; the next call will catch up
end

lines = regexp(txt, '\r\n|\r|\n', 'split');
lines = lines(~cellfun(@(l) isempty(strtrim(l)), lines));
if numel(lines) > 400
    lines = lines(end-399:end);
end

set(S.hLog, 'String', lines(:), 'Value', numel(lines));
drawnow limitrate;

end

% =====================================================================
function appendLine(fig, line)
%APPENDLINE  Add one line directly, for messages made before a run starts.

if ~ishandle(fig), return; end
S = guidata(fig);
if isempty(S) || ~isfield(S, 'hLog') || ~ishandle(S.hLog), return; end

L = get(S.hLog, 'String');
if ischar(L), L = cellstr(L); end
L{end+1} = line;
if numel(L) > 2000, L = L(end-1500:end); end

set(S.hLog, 'String', L, 'Value', numel(L));
drawnow limitrate;

end

% =====================================================================
function setStatus(fig, txt)

if ~ishandle(fig), return; end
S = guidata(fig);
if isempty(S) || ~isfield(S, 'hStatus') || ~ishandle(S.hStatus), return; end
set(S.hStatus, 'String', txt);
drawnow limitrate;

end

% =====================================================================
function wf_open_path(p)
%WF_OPEN_PATH  Open a file or folder in Windows.

if exist(p, 'dir') ~= 7 && exist(p, 'file') ~= 2
    mkdir(p);
end
if ispc
    winopen(p);
else
    disp(p);
end

end
