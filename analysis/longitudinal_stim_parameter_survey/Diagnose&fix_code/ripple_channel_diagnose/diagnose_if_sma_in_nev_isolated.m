%% diagnose_sma_isolated.m
% Fast + trustworthy entity summary for a .nev file's Event/Segment data,
% using the official Neuroshare decoding (so SMA channels are correctly
% labelled "SMA 1" / "SMA 2" / "SMA 3" -- no guessing of raw byte layouts).
%
% WHY THIS IS FAST: ns_OpenFile is slow mainly because it auto-discovers
% and indexes any companion .nsX continuous-data files in the same folder
% (which can be tens of GB). This script copies ONLY the small .nev file
% into an isolated, empty temp folder first, so when ns_OpenFile looks for
% companion .nsX files there, it finds none and skips them entirely.
%
% SAFETY: the ORIGINAL .nev/.nsX files are only ever READ, never written.
% A new temporary COPY of the .nev is created (via copyfile) in a fresh
% temp folder; that copy -- not the original -- is what gets opened and
% deleted again at the end. The original files are untouched throughout.

clear; clc; close all; fclose('all');

%% -------------------------
% NEUROSHARE PATH
% -------------------------
ns_candidate = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'neuroshare');
if exist(ns_candidate, 'dir')
    addpath(ns_candidate);
elseif ~exist('ns_OpenFile', 'file')
    ns_dir = uigetdir(pwd, 'Select the neuroshare/ folder (contains ns_OpenFile.m)');
    if isequal(ns_dir, 0), error('neuroshare folder not selected.'); end
    addpath(ns_dir);
end

%% -------------------------
% SELECT .nev FILE (original -- read-only)
% -------------------------
[fn, fp] = uigetfile('*.nev', 'Select Ripple .nev file (original is never modified)');
if isequal(fn, 0), error('No file selected.'); end
orig_nev_path = fullfile(fp, fn);
fprintf('Original file (read-only): %s\n', orig_nev_path);

%% -------------------------
% COPY .nev INTO AN ISOLATED TEMP FOLDER (no companion .nsX there)
% -------------------------
tmp_dir = fullfile(tempdir, ['nev_isolated_' datestr(now, 'yyyymmdd_HHMMSSFFF')]);
mkdir(tmp_dir);
tmp_nev_path = fullfile(tmp_dir, fn);

fprintf('Copying .nev only (no .nsX) to isolated temp folder:\n  %s\n', tmp_dir);
t0 = tic;
copyfile(orig_nev_path, tmp_nev_path);
fprintf('  copy took %.2f s\n\n', toc(t0));

% Always clean up the temp copy, even if something below errors.
cleanup_tmp = onCleanup(@() cleanup_temp_folder(tmp_dir));

%% -------------------------
% OPEN THE ISOLATED COPY (no .nsX present -> fast)
% -------------------------
fprintf('Opening isolated copy via Neuroshare...\n');
t0 = tic;
[~, hFile] = ns_OpenFile(tmp_nev_path);
fprintf('  ns_OpenFile took %.2f s\n\n', toc(t0));

n_entities = numel(hFile.Entity);

%% -------------------------
% ENTITY SUMMARY (Event + Segment only -- no Analog/.nsX entities exist here)
% -------------------------
fprintf('=== Entity summary (from isolated .nev copy) ===\n');
fprintf('%-5s  %-12s  %-12s  %-6s  %s\n', 'ID', 'Type', 'Count', 'ElecID', 'Label/Reason');
fprintf('%s\n', repmat('-', 1, 68));

for i = 1:n_entities
    e = hFile.Entity(i);

    cnt_str = '?';
    if isfield(e, 'Count'), cnt_str = num2str(double(e.Count)); end

    eid_str = '';
    if isfield(e, 'ElectrodeID') && ~isempty(e.ElectrodeID)
        eid_str = num2str(double(e.ElectrodeID));
    end

    lbl = '';
    if isfield(e, 'Label')  && ~isempty(e.Label),  lbl = char(e.Label);  end
    rsn = '';
    if isfield(e, 'Reason') && ~isempty(e.Reason), rsn = char(e.Reason); end
    combined = strtrim([lbl ' ' rsn]);

    etype = '';
    if isfield(e, 'EntityType'), etype = char(e.EntityType); end

    fprintf('%-5d  %-12s  %-12s  %-6s  %s\n', i, etype, cnt_str, eid_str, combined);
end

fprintf('\nDone. Original .nev/.nsX files were never modified.\n');
fprintf('(Temp copy will be deleted automatically on script exit.)\n');

%% =========================================================================
% LOCAL FUNCTIONS
%% =========================================================================

function cleanup_temp_folder(tmp_dir)
% Removes the isolated temp copy created above. Only ever touches files
% inside tmp_dir (a freshly created temp folder) -- never the originals.
try
    if exist(tmp_dir, 'dir')
        rmdir(tmp_dir, 's');
    end
catch
    fprintf('Note: could not auto-delete temp folder, please remove manually:\n  %s\n', tmp_dir);
end
end