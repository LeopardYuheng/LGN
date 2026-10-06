function selftest_wf_pipeline()
%SELFTEST_WF_PIPELINE  Check the automation works on this machine, no data needed.
%
%   selftest_wf_pipeline
%
% Run this once after installing, and again after MATLAB upgrades or after
% anyone edits the pipeline scripts. It takes a couple of seconds and touches
% nothing outside the temp folder.
%
% What it proves
%   1  every pipeline script the automation calls is where it expects
%   2  the dialog stubs really do shadow MATLAB's own dialogs
%   3  a script with local functions still runs correctly through the runner,
%      including its "clear" and "close all" preamble
%   4  the temporary source-patching used for step 6 and the TIFF-check works
%   5  answers are matched by prompt text, in order, and an unanswered dialog
%      is a clear error rather than a silent hang
%   6  the automatic brain-mask segmentation finds a known synthetic shape
%   7  manifest reading handles absolute paths, relative paths and quoting

here = fileparts(mfilename('fullpath'));
addpath(here);

fprintf('\n  Self-test: LGN widefield auto pipeline\n');
fprintf('  %s\n\n', repmat('=', 1, 64));

results = {};
results = runTest(results, 'pipeline scripts present',   @test_paths);
results = runTest(results, 'dialog stubs shadow MATLAB', @test_stub_shadowing);
results = runTest(results, 'script runner + local funcs',@test_runner);
results = runTest(results, 'source patching',            @test_patch);
results = runTest(results, 'answer matching and errors', @test_matching);
results = runTest(results, 'automatic brain mask',       @test_auto_mask);
results = runTest(results, 'manifest reading',           @test_manifest);
results = runTest(results, 'stop signal',                @test_stop);
results = runTest(results, 'output folder choices',      @test_output_dir);

fprintf('\n  %s\n', repmat('-', 1, 64));
nFail = sum(~[results{:,2}]);
if nFail == 0
    fprintf('  All %d checks passed. The pipeline is ready to run.\n\n', size(results,1));
else
    fprintf('  %d of %d checks FAILED:\n', nFail, size(results,1));
    for i = 1:size(results,1)
        if ~results{i,2}
            fprintf('    %-32s %s\n', results{i,1}, results{i,3});
        end
    end
    fprintf('\n');
end

end

% =====================================================================
function results = runTest(results, name, fcn)

fprintf('  %-34s', name);
try
    fcn();
    fprintf('ok\n');
    results(end+1, :) = {name, true, ''};
catch err
    fprintf('FAILED\n');
    fprintf('      %s\n', err.message);
    results(end+1, :) = {name, false, err.message};
end

end

% =====================================================================
function test_paths()

[ok, missing] = wf_check_paths();
assert(ok, 'Missing: %s', strjoin(missing, '; '));

end

% =====================================================================
function test_stub_shadowing()
%TEST_STUB_SHADOWING  With the stub folder in front, our functions must win.

stubDir = fullfile(fileparts(mfilename('fullpath')), 'uistub');
oldPath = path();
c = onCleanup(@() path(oldPath));

addpath(stubDir, '-begin');

for f = {'uigetfile', 'uigetdir', 'inputdlg', 'listdlg', 'questdlg'}
    resolved = which(f{1});
    assert(strncmpi(resolved, stubDir, numel(stubDir)), ...
        ['MATLAB resolved %s to\n    %s\ninstead of the stub in\n    %s\n' ...
         'The automation cannot answer dialogs on this MATLAB version.'], ...
        f{1}, resolved, stubDir);
end

end

% =====================================================================
function test_runner()
%TEST_RUNNER  A script that clears, closes, and has a local function.

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

scriptPath = fullfile(d, 'wf_selftest_script.m');
outFile    = fullfile(d, 'selftest_out.mat');

lines = {
    'close all; clc; clear; fclose(''all'');'
    'folder = uigetdir(pwd, ''Select the pretend output folder'');'
    '[fn, fp] = uigetfile(''*.mat'', ''Select the pretend input file'');'
    'answ = inputdlg({''First value:'', ''Second value:''}, ''Pretend metadata'', [1 40], {'''',''''});'
    '[sel, ok] = listdlg(''Name'', ''Pretend picker'', ''PromptString'', ''Pick some'', ''ListString'', {''a'',''b'',''c''});'
    'btn = questdlg(''Pretend question?'', ''Pretend title'', ''Yes'', ''No'', ''Yes'');'
    'result.folder  = folder;'
    'result.file    = fullfile(fp, fn);'
    'result.answ    = answ;'
    'result.sel     = sel;'
    'result.ok      = ok;'
    'result.btn     = btn;'
    'result.doubled = wf_selftest_double(21);'
    'save(fullfile(folder, ''selftest_out.mat''), ''result'');'
    ''
    'function y = wf_selftest_double(x)'
    'y = 2 * x;'
    'end'
    };
writeLines(scriptPath, lines);

dummyMat = fullfile(d, 'dummy_input.mat');
tmp = 1; save(dummyMat, 'tmp'); %#ok<NASGU>

answers = wf_ans( ...
    'uigetdir',  'pretend output folder', d, ...
    'uigetfile', 'pretend input file',    dummyMat, ...
    'inputdlg',  'Pretend metadata',      {'alpha', 'beta'}, ...
    'listdlg',   'Pretend picker',        [1 3], ...
    'questdlg',  'Pretend question',      'Yes');

wf_run_script(scriptPath, answers, struct('strict', true));

assert(exist(outFile, 'file') == 2, 'The test script produced no output file.');
S = load(outFile);
r = S.result;

assert(strcmp(r.folder, d),                    'uigetdir answer did not arrive.');
assert(strcmp(r.file, dummyMat),               'uigetfile answer did not arrive.');
assert(isequal(r.answ, {'alpha'; 'beta'}),     'inputdlg answer did not arrive.');
assert(isequal(r.sel, [1 3]) && r.ok == 1,     'listdlg answer did not arrive.');
assert(strcmp(r.btn, 'Yes'),                   'questdlg answer did not arrive.');
assert(r.doubled == 42,                        'The script''s local function did not run.');

end

% =====================================================================
function test_patch()
%TEST_PATCH  The temp-copy rewrite used for step 6's option flags.

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

scriptPath = fullfile(d, 'wf_selftest_patch.m');
writeLines(scriptPath, {
    'RUN_OPTION_A = true;   % manual'
    'RUN_OPTION_B = false;  % auto'
    'assignin(''base'', ''wf_selftest_flags'', [RUN_OPTION_A RUN_OPTION_B]);'
    });

patch = { '(?m)^\s*RUN_OPTION_A\s*=\s*true\s*;.*$',  'RUN_OPTION_A = false;'
          '(?m)^\s*RUN_OPTION_B\s*=\s*false\s*;.*$', 'RUN_OPTION_B = true;'  };

wf_run_script(scriptPath, wf_ans(), struct('strict', true, 'patch', {patch}));

flags = evalin('base', 'wf_selftest_flags');
evalin('base', 'clear wf_selftest_flags');
assert(isequal(flags, [false true]), ...
    'Source patching did not take effect (flags were [%d %d]).', flags(1), flags(2));

assert(~isempty(strfind(fileread(scriptPath), 'RUN_OPTION_A = true;')), ...
    'The ORIGINAL script was modified. Patching must only touch the temp copy.');

end

% =====================================================================
function test_matching()
%TEST_MATCHING  Ordered consumption, and a loud error when nothing matches.

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

f1 = fullfile(d, 'one.mat'); f2 = fullfile(d, 'two.mat');
tmp = 1; save(f1, 'tmp'); save(f2, 'tmp'); %#ok<NASGU>

scriptPath = fullfile(d, 'wf_selftest_order.m');
writeLines(scriptPath, {
    '[a_n, a_p] = uigetfile(''*.mat'', ''Session 1 of 2: select day pointer'');'
    '[b_n, b_p] = uigetfile(''*.mat'', ''Session 2 of 2: select day pointer'');'
    'assignin(''base'', ''wf_selftest_order'', {fullfile(a_p,a_n), fullfile(b_p,b_n)});'
    });

answers = wf_ans('uigetfile', 'select day pointer', f1, ...
                 'uigetfile', 'select day pointer', f2);
wf_run_script(scriptPath, answers, struct('strict', true));

got = evalin('base', 'wf_selftest_order');
evalin('base', 'clear wf_selftest_order');
assert(strcmp(got{1}, f1) && strcmp(got{2}, f2), ...
    'Repeated patterns were not consumed in table order.');

% An unanswered dialog must raise wf_ui:noAnswer, not hang on a real dialog.
scriptPath2 = fullfile(d, 'wf_selftest_unanswered.m');
writeLines(scriptPath2, {'x = uigetdir(pwd, ''Something nobody prepared an answer for'');'});

threw = false;
try
    wf_run_script(scriptPath2, wf_ans(), struct('strict', true));
catch err
    threw = strcmp(err.identifier, 'wf_ui:noAnswer');
end
assert(threw, 'An unanswered dialog in strict mode did not raise wf_ui:noAnswer.');

end

% =====================================================================
function test_auto_mask()
%TEST_AUTO_MASK  Segment a synthetic bright disc on a dark noisy background.

H = 240; W = 320;
[xx, yy] = meshgrid(1:W, 1:H);
truth = ((xx - 150).^2 + (yy - 120).^2) <= 80^2;

rng(0);
img = 300 + 40 * randn(H, W);
img(truth) = 1400 + 40 * randn(sum(truth(:)), 1);

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

imgDir = fullfile(d, 'images');
mkdir(imgDir);
for i = 1:5
    imwrite(uint16(img), fullfile(imgDir, sprintf('frame_%03d.tif', i)));
end

cfg = wf_config();
cfg.output_root      = d;
cfg.mask.verify      = false;      % no window during a self-test
cfg.mask.n_ref_frames = 5;
cfg.mask.reuse_existing = false;

maskFile = wf_step0_auto_mask(imgDir, 'TEST', '20260101', d, cfg);
assert(exist(maskFile, 'file') == 2, 'No brain_mask.mat was produced.');

S = load(maskFile);
m = S.reference_mask_struct.final_mask;

assert(isequal(size(m), [H W]), 'Mask is the wrong size.');
assert(isequal(size(S.reference_mask_struct.circle_mask), [H W]), 'circle_mask is the wrong size.');
assert(all(all(S.reference_mask_struct.final_mask <= S.reference_mask_struct.circle_mask)), ...
    'final_mask is not contained in circle_mask, so downstream assumptions break.');

overlap = sum(m(:) & truth(:)) / sum(m(:) | truth(:));
assert(overlap > 0.75, ...
    'Segmentation only matched the known shape by %.0f%% (want > 75%%).', 100 * overlap);

end

% =====================================================================
function test_manifest()

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

f = fullfile(d, 'sessions.csv');
writeLines(f, {
    '# a comment line'
    'subject,date,session_label,tiff_dir,nev_file,csv_file'
    'lgn26,20260630,,C:\data\imgs,C:\data\r.nev,C:\data\t.csv'
    'LGN24,07082026,session2,rel\imgs,rel\r.nev,"rel\has,comma.csv"'
    });

s = wf_read_manifest(f, d);

assert(numel(s) == 2, 'Expected 2 manifest rows, got %d.', numel(s));
assert(strcmp(s(1).subject, 'LGN26'), 'Subject was not upper-cased.');
assert(strcmp(s(1).date, '20260630'), 'YYYYMMDD date was altered.');
assert(strcmp(s(2).date, '20260708'), 'MMDDYYYY date was not normalised.');
assert(strcmp(s(1).img_dir, 'C:\data\imgs'), 'Absolute path was rewritten.');
assert(strcmp(s(2).img_dir, fullfile(d, 'rel\imgs')), 'Relative path was not resolved.');
assert(~isempty(strfind(s(2).csv, ',')), 'Quoted field with a comma was split.');

end

% =====================================================================
function test_stop()
%TEST_STOP  The stop flag must survive the CLEAR every pipeline script runs.

d = fullfile(tempdir, sprintf('wf_selftest_%d', randi(99999)));
mkdir(d);
c = onCleanup(@() rmdir(d, 's'));

wf_stop('arm', d);
assert(~wf_stop('check'), 'A freshly armed run already reports a stop.');

wf_stop('request', 'self-test');
assert(wf_stop('check'), 'A requested stop was not seen.');
assert(strcmp(wf_stop('reason'), 'self-test'), 'The stop reason was lost.');

% Every pipeline script starts with these; the signal must outlive them.
evalin('base', 'clear');
assert(wf_stop('check'), ...
    'The stop signal did not survive a CLEAR, so it would be lost mid-run.');

sentinel = fullfile(d, '.wf_stop_requested');
assert(exist(sentinel, 'file') == 2, ...
    'No stop sentinel file was written next to the results.');

wf_stop('clear');
assert(~wf_stop('check'), 'The stop signal could not be cleared.');
assert(exist(sentinel, 'file') ~= 2, 'The stop sentinel file was left behind.');

end

% =====================================================================
function test_output_dir()
%TEST_OUTPUT_DIR  The three result destinations resolve as advertised.

cfg = wf_config();
cfg.output_root = 'C:\Results';

e = struct('subject', 'LGN24', 'date', '20260821', ...
           'data_dir', 'E:\Yuheng_LGN\LGN24_08212026_postblind_WFimage');

a = wf_output_dir(e, 'result_root', '', cfg);
assert(strcmp(a, fullfile('C:\Results', 'LGN24_08212026')), ...
    'result_root gave "%s"', a);

% Next to the data: a named analysis folder inside the experiment folder.
b = wf_output_dir(e, 'with_data', '', cfg);
assert(strcmp(b, fullfile(e.data_dir, 'LGN24_08212026_analysis')), ...
    'with_data gave "%s"', b);

c = wf_output_dir(e, 'custom', 'D:\Elsewhere', cfg);
assert(strcmp(c, fullfile('D:\Elsewhere', 'LGN24_08212026')), ...
    'custom gave "%s"', c);

% Empty suffix means straight into the experiment folder.
cfg2 = cfg;
cfg2.output_with_data_suffix = '';
d = wf_output_dir(e, 'with_data', '', cfg2);
assert(strcmp(d, e.data_dir), 'with_data + empty suffix gave "%s"', d);

% No data folder known: must fall back rather than write somewhere odd.
e2 = e; e2.data_dir = '';
f = wf_output_dir(e2, 'with_data', '', cfg);
assert(strcmp(f, fullfile('C:\Results', 'LGN24_08212026')), ...
    'with_data without a data folder gave "%s"', f);

end

% =====================================================================
function writeLines(p, lines)

fid = fopen(p, 'w');
assert(fid > 0, 'Could not write %s', p);
for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end
fclose(fid);

end
