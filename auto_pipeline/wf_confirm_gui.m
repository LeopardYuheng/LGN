function selected = wf_confirm_gui(experiments, cfg)
%WF_CONFIRM_GUI  Show what was found on the disk and let the user approve it.
%
%   selected = WF_CONFIRM_GUI(experiments, cfg)
%
% Returns the ticked rows with their final output folders, or an empty struct
% array if the user cancels.
%
% Two things are editable per experiment:
%
%   Track         single or combined, if the scanner grouped sessions wrongly
%   Results to    WF_result, next to the data on the disk, or a folder you
%                 choose. The resulting path is shown in the next column and
%                 can also be typed directly.
%
% Rows the scanner flagged as incomplete start unticked and cannot run until
% the missing file is supplied.

if nargin < 2 || isempty(cfg), cfg = wf_config(); end

selected = experiments([]);
if isempty(experiments), return; end

DEST_OPTIONS = {'WF_result', 'Next to data', 'Choose folder...', 'Custom'};
COL_RUN = 1; COL_TRACK = 4; COL_DEST = 7; COL_OUT = 8;

n = numel(experiments);

fig = figure('Name', 'Widefield pipeline - confirm what will run and where', ...
             'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
             'Color', [0.96 0.96 0.97], ...
             'Position', [110 140 1220 560], ...
             'CloseRequestFcn', @(s,e) onCancel(s));

uicontrol(fig, 'Style', 'text', 'String', ...
    sprintf('%d experiment(s) found. Check where each one''s results should go.', n), ...
    'Units', 'normalized', 'Position', [0.02 0.92 0.96 0.05], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 11, ...
    'HorizontalAlignment', 'left');

data = cell(n, 9);
for i = 1:n
    data(i,:) = wf_row(experiments(i), cfg);
end

tbl = uitable(fig, 'Units', 'normalized', 'Position', [0.02 0.24 0.96 0.66], ...
    'Data', data, ...
    'ColumnName', {'Run', 'Subject', 'Date', 'Track', 'Sessions', ...
                   'Retinotopy', 'Results to', 'Output folder', 'Notes'}, ...
    'ColumnFormat', {'logical', 'char', 'char', {'single','combined'}, ...
                     'numeric', 'char', DEST_OPTIONS, 'char', 'char'}, ...
    'ColumnEditable', [true false false true false false true true false], ...
    'ColumnWidth', {40, 70, 90, 90, 70, 85, 110, 360, 200}, ...
    'RowName', [], 'FontSize', 10, ...
    'CellEditCallback', @onEdit);

uicontrol(fig, 'Style', 'text', 'String', 'Set every experiment to:', ...
    'Units', 'normalized', 'Position', [0.02 0.175 0.16 0.04], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 10, ...
    'HorizontalAlignment', 'left');

uicontrol(fig, 'Style', 'pushbutton', 'String', 'WF_result', ...
    'Units', 'normalized', 'Position', [0.18 0.175 0.11 0.045], ...
    'FontSize', 9, 'Callback', @(s,e) setAllDest(fig, 'WF_result'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Next to data', ...
    'Units', 'normalized', 'Position', [0.30 0.175 0.11 0.045], ...
    'FontSize', 9, 'Callback', @(s,e) setAllDest(fig, 'Next to data'));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'One folder for all...', ...
    'Units', 'normalized', 'Position', [0.42 0.175 0.15 0.045], ...
    'FontSize', 9, 'Callback', @(s,e) setAllCustom(fig));

uicontrol(fig, 'Style', 'text', 'String', ...
    ['Untick anything you do not want analysed. "Next to data" writes results ' ...
     'into the experiment''s own folder on the disk, beside img\ and ephys\. ' ...
     'You can also type a path straight into the Output folder column.'], ...
    'Units', 'normalized', 'Position', [0.02 0.10 0.96 0.06], ...
    'BackgroundColor', [0.96 0.96 0.97], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'ForegroundColor', [0.3 0.3 0.35]);

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Run selected', ...
    'Units', 'normalized', 'Position', [0.02 0.025 0.18 0.06], ...
    'FontSize', 11, 'FontWeight', 'bold', 'Callback', @(s,ev) onRun(fig));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Select all', ...
    'Units', 'normalized', 'Position', [0.22 0.025 0.11 0.06], ...
    'FontSize', 10, 'Callback', @(s,ev) onAll(fig, true));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Select none', ...
    'Units', 'normalized', 'Position', [0.34 0.025 0.11 0.06], ...
    'FontSize', 10, 'Callback', @(s,ev) onAll(fig, false));

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Cancel', ...
    'Units', 'normalized', 'Position', [0.86 0.025 0.12 0.06], ...
    'FontSize', 10, 'Callback', @(s,ev) onCancel(fig));

st = struct('tbl', tbl, 'go', false, 'experiments', experiments, 'cfg', cfg);
guidata(fig, st);

uiwait(fig);

if ~ishandle(fig), return; end

st   = guidata(fig);
data = get(st.tbl, 'Data');
go   = st.go;
delete(fig);

if ~go, return; end

keep = false(n, 1);
for i = 1:n
    keep(i) = logical(data{i, COL_RUN});
    experiments(i).track   = data{i, COL_TRACK};
    experiments(i).out_dir = strtrim(data{i, COL_OUT});

    % Honour a hand-corrected Track value.
    if strcmp(experiments(i).track, 'single') && experiments(i).n > 1
        experiments(i).sessions = experiments(i).sessions(1);
        experiments(i).n        = 1;
        experiments(i).sessions(1).label = '';
    end
end

selected = experiments(keep);

end

% =====================================================================
function row = wf_row(e, cfg)
%WF_ROW  One table row from one experiment.

if strcmpi(cfg.output_location, 'with_data')
    dest = 'Next to data';
else
    dest = 'WF_result';
end

if isempty(e.retino), retino = 'pre-step A'; else, retino = 'ready'; end

row = {logical(e.ok), e.subject, wf_pretty_date(e.date), e.track, e.n, ...
       retino, dest, e.out_dir, e.notes};

end

% =====================================================================
function onEdit(src, evt)
%ONEDIT  Keep the destination choice and the folder path in step.

if isempty(evt.Indices), return; end

COL_DEST = 7; COL_OUT = 8;

fig = ancestor(src, 'figure');
st  = guidata(fig);
r   = evt.Indices(1);
c   = evt.Indices(2);
data = get(src, 'Data');

switch c

    case COL_DEST
        choice = data{r, COL_DEST};

        switch choice
            case 'WF_result'
                data{r, COL_OUT} = wf_output_dir(st.experiments(r), 'result_root', '', st.cfg);

            case 'Next to data'
                p = wf_output_dir(st.experiments(r), 'with_data', '', st.cfg);
                if isempty(st.experiments(r).data_dir)
                    uiwait(msgbox(sprintf(...
                        ['No data folder is known for %s %s, so results ' ...
                         'cannot go next to the data. Left at:\n\n%s'], ...
                        st.experiments(r).subject, st.experiments(r).date, p), ...
                        'No data folder', 'warn', 'modal'));
                    data{r, COL_DEST} = 'WF_result';
                end
                data{r, COL_OUT} = p;

            case 'Choose folder...'
                start = fileparts(data{r, COL_OUT});
                if isempty(start) || exist(start, 'dir') ~= 7
                    start = st.cfg.output_root;
                end
                root = uigetdir(start, sprintf('Results folder for %s %s', ...
                    st.experiments(r).subject, st.experiments(r).date));
                if isequal(root, 0)
                    data{r, COL_DEST} = 'WF_result';
                    data{r, COL_OUT}  = wf_output_dir(st.experiments(r), 'result_root', '', st.cfg);
                else
                    data{r, COL_DEST} = 'Custom';
                    data{r, COL_OUT}  = wf_output_dir(st.experiments(r), 'custom', root, st.cfg);
                end

            case 'Custom'
                % Leave whatever path is already there.
        end

    case COL_OUT
        % A path typed by hand is a custom destination by definition.
        data{r, COL_DEST} = 'Custom';
end

set(src, 'Data', data);

end

% =====================================================================
function setAllDest(fig, dest)

COL_DEST = 7; COL_OUT = 8;

st   = guidata(fig);
data = get(st.tbl, 'Data');

for i = 1:size(data, 1)
    if strcmp(dest, 'Next to data') && isempty(st.experiments(i).data_dir)
        continue;                       % nowhere to put it; leave this row
    end
    data{i, COL_DEST} = dest;
    if strcmp(dest, 'Next to data')
        data{i, COL_OUT} = wf_output_dir(st.experiments(i), 'with_data', '', st.cfg);
    else
        data{i, COL_OUT} = wf_output_dir(st.experiments(i), 'result_root', '', st.cfg);
    end
end

set(st.tbl, 'Data', data);

end

% =====================================================================
function setAllCustom(fig)

COL_DEST = 7; COL_OUT = 8;

st   = guidata(fig);
root = uigetdir(st.cfg.output_root, ...
    'Parent folder for every experiment''s results');
if isequal(root, 0), return; end

data = get(st.tbl, 'Data');
for i = 1:size(data, 1)
    data{i, COL_DEST} = 'Custom';
    data{i, COL_OUT}  = wf_output_dir(st.experiments(i), 'custom', root, st.cfg);
end
set(st.tbl, 'Data', data);

end

% =====================================================================
function onRun(fig)

st = guidata(fig);
st.go = true;
guidata(fig, st);
uiresume(fig);

end

% =====================================================================
function onCancel(fig)

st = guidata(fig);
if isempty(st), st = struct('go', false); end
st.go = false;
guidata(fig, st);
uiresume(fig);

end

% =====================================================================
function onAll(fig, val)

COL_RUN = 1; COL_NOTES = 9;

st   = guidata(fig);
data = get(st.tbl, 'Data');
for i = 1:size(data, 1)
    data{i, COL_RUN} = val && isempty(strfind(lower(data{i, COL_NOTES}), 'missing'));
end
set(st.tbl, 'Data', data);

end

% =====================================================================
function s = wf_pretty_date(d)

if numel(d) == 8
    s = sprintf('%s-%s-%s', d(1:4), d(5:6), d(7:8));
else
    s = d;
end

end
