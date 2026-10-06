function wf_run_script(scriptPath, answers, opts)
%WF_RUN_SCRIPT  Run an unmodified pipeline script with its dialogs answered.
%
%   WF_RUN_SCRIPT(scriptPath, answers)
%   WF_RUN_SCRIPT(scriptPath, answers, opts)
%
% The script is executed in the base workspace exactly as if you had pressed
% Run in the editor, so its behaviour is identical to a manual run. The only
% difference is that uigetfile / uigetdir / inputdlg / listdlg / questdlg are
% shadowed by the stubs in this folder's uistub, which take their answers
% from the table you pass in.
%
% INPUTS
%   scriptPath  full path to the .m script to run
%   answers     answer table, see WF_ANS / WF_UI
%   opts        struct, all fields optional
%     .strict       true (default): error on any dialog with no answer.
%                   false: show the real dialog so the user can answer it.
%     .addpath      cellstr of extra folders to put on the path for this run
%     .patch        n-by-2 cellstr of {regexp, replacement} applied to a
%                   TEMPORARY COPY of the script. Used for the two places a
%                   dialog stub cannot reach: the console INPUT() call in
%                   build_tiff_sma1_correction_map, and the RUN_OPTION_A/B
%                   literals in step 6. The original file is never touched.
%
% Console output is not captured here. WF_RUN_EXPERIMENT turns DIARY on for
% the whole experiment, which records this script's output and the
% pipeline's own progress lines into one log file in the right order.
%
% See also WF_UI, WF_ANS.

if nargin < 3, opts = struct(); end
strict   = wf_getdef(opts, 'strict',  true);
extra    = wf_getdef(opts, 'addpath', {});
patch    = wf_getdef(opts, 'patch',   {});

assert(exist(scriptPath, 'file') == 2, 'wf_run_script:missingScript', ...
    'Pipeline script not found:\n  %s', scriptPath);

% ---------------------------------------------------------------- patching
tempDir = '';
runPath = scriptPath;
if ~isempty(patch)
    [tempDir, runPath] = wf_patch_script(scriptPath, patch);
end

% ------------------------------------------------------------------- paths
stubDir    = fullfile(fileparts(mfilename('fullpath')), 'uistub');
scriptDir  = fileparts(scriptPath);
addDirs    = [{scriptDir}, wf_cellify(extra)];
if ~isempty(tempDir), addDirs = [{tempDir}, addDirs]; end

oldPath = path();
cleanupPath = onCleanup(@() path(oldPath));

for i = numel(addDirs):-1:1
    if exist(addDirs{i}, 'dir') == 7
        addpath(addDirs{i});
    end
end
addpath(stubDir, '-begin');   % stubs must win over MATLAB's own dialogs

% --------------------------------------------------------------------- run
wf_ui('begin', answers, strict);
cleanupUI = onCleanup(@() wf_ui('end'));

runErr = [];
try
    evalin('base', sprintf('run(''%s'');', strrep(runPath, '''', '''''')));
catch runErr %#ok<CTCH>
end

% Report answers that were prepared but never asked for. This is how a
% silent behaviour change in an upstream script shows up: the script stopped
% asking something we expected it to ask.
leftover = wf_ui('unused');
if ~isempty(leftover)
    warning('wf_run_script:unusedAnswers', ...
        'Script "%s" never asked for %d prepared answer(s): %s', ...
        wf_basename(scriptPath), numel(leftover), ...
        strjoin(arrayfun(@(a) sprintf('%s/%s', a.kind, a.pattern), ...
            leftover(:)', 'UniformOutput', false), ', '));
end

if ~isempty(tempDir)
    rmdir(tempDir, 's');
end

if ~isempty(runErr)
    rethrow(runErr);
end

end

% =====================================================================
function [tempDir, runPath] = wf_patch_script(scriptPath, patch)
%WF_PATCH_SCRIPT  Copy a script to a temp folder and apply text edits to it.

txt = fileread(scriptPath);

for i = 1:size(patch, 1)
    before = txt;
    txt = regexprep(txt, patch{i,1}, patch{i,2}, 'dotexceptnewline');
    if strcmp(before, txt)
        error('wf_run_script:patchMissed', ...
            ['A required source patch matched nothing in "%s".\n' ...
             '  pattern: %s\n' ...
             'The upstream script has probably changed; update the patch in ' ...
             'the step wrapper.'], wf_basename(scriptPath), patch{i,1});
    end
end

tempDir = fullfile(tempdir, sprintf('wf_auto_%s_%d', ...
    datestr(now, 'yyyymmdd_HHMMSSFFF'), randi(9999)));
mkdir(tempDir);

runPath = fullfile(tempDir, wf_basename(scriptPath));
fid = fopen(runPath, 'w');
assert(fid > 0, 'wf_run_script:tempWrite', ...
    'Could not write the patched copy to %s', runPath);
fwrite(fid, txt);
fclose(fid);

end

% =====================================================================
function b = wf_basename(p)

[~, n, e] = fileparts(p);
b = [n e];

end

% =====================================================================
function c = wf_cellify(v)

if isempty(v),      c = {};
elseif ischar(v),   c = {v};
elseif isstring(v), c = cellstr(v);
else,               c = v;
end

end

% =====================================================================
function v = wf_getdef(s, f, d)

if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end

end
