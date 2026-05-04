%% make_container_intan_single_script.m
% Pointer-only container for one day/session directory.
%
% Stores:
%   - dataset_root
%   - relative paths to img/ and rhd run dirs
%   - stim_channel
%   - current_uA
%   - Freq
%   - trial_onset_frame_idx
%
% Does NOT store movies, dF/F, maps, peaks, etc.

clc; clear;

%% ---------------- USER INPUTS ----------------
day_dir = 'C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-1-30';

cfg = struct();
cfg.stimDI = 5;
cfg.camDI  = 2;
cfg.pre_sec  = 1;
cfg.post_sec = 3;
cfg.expected_n_trials = 1800;

container_name = 'container_day_pointer_only.mat';

%% ---------------- MAIN ----------------
container_path = make_container_intan(day_dir, cfg, container_name);

fprintf('\nDone.\nContainer path:\n%s\n', container_path);

%% ============================================================
% Local functions
% ============================================================

function container_path = make_container_intan(day_dir, cfg, container_name)
% make_container_intan
% Single-script version of the Intan pointer-only container builder.

    % ---- FIXED ROOT ----
    dataset_root = 'C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal';

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end
    cfg = fill_cfg_defaults(cfg);

    if nargin < 3 || isempty(container_name)
        container_name = 'container_day_pointer_only.mat';
    end

    % ---- locate mask file (expect it inside day_dir) ----
    mask_file = fullfile(day_dir, 'reference_mask.mat');
    assert(exist(mask_file,'file')==2, ...
        'Expected reference_mask.mat in day_dir: %s', day_dir);

    S = load(mask_file);
    assert(isfield(S,'final_mask'), ...
        'reference_mask.mat must contain final_mask');

    if isfield(S,'crop_rect')
        crop_rect = S.crop_rect;
    else
        crop_rect = [];
    end

    out_dir = fullfile(day_dir, 'group_outputs');
    if ~exist(out_dir,'dir')
        mkdir(out_dir);
    end
    container_path = fullfile(out_dir, container_name);

    % ---- discover ALL condition folders recursively that contain img/ ----
    img_dirs = dir(fullfile(day_dir, '**', 'img'));
    img_dirs = img_dirs([img_dirs.isdir]);

    cond_dirs = strings(0,1);
    for i = 1:numel(img_dirs)
        cond_dirs(end+1,1) = string(fileparts(img_dirs(i).folder)); %#ok<AGROW>
    end
    cond_dirs = unique(cond_dirs);

    % Exclude derived folders if they contain img/
    cond_dirs = cond_dirs(~contains(cond_dirs, filesep + "group_outputs") & ...
                          ~contains(cond_dirs, filesep + "analysis") & ...
                          ~contains(cond_dirs, filesep + "derived"));

    assert(~isempty(cond_dirs), ...
        'No condition folders with img/ found under day_dir: %s', day_dir);

    % ---- init container if missing ----
    if ~exist(container_path,'file')
        C = struct();

        C.meta = struct();
        C.meta.dataset_root  = dataset_root;
        C.meta.day_dir_rel   = relpath(day_dir, dataset_root);
        C.meta.mask_file_rel = relpath(mask_file, dataset_root);
        C.meta.created_at    = char(datetime('now'));
        C.meta.updated_at    = C.meta.created_at;

        C.cfg = cfg;
        C.mask = struct();
        C.mask.crop_rect = crop_rect;

        C.entries = struct([]);

        save(container_path, 'C', '-v7.3');
    end

    M = matfile(container_path, 'Writable', true);
    C = M.C;

    % Update cfg so reruns reflect current config
    C.cfg = cfg;

    % ---- process each condition folder ----
    for k = 1:numel(cond_dirs)
        cond_dir = char(cond_dirs(k));
        entry = extract_intan_pointer_entry(cond_dir, cfg, dataset_root);

        key = entry.key;

        exists_idx = [];
        if isfield(C,'entries') && ~isempty(C.entries)
            keys = string({C.entries.key});
            j = find(keys == string(key), 1);
            if ~isempty(j)
                exists_idx = j;
            end
        end

        if isempty(exists_idx)
            C.entries = [C.entries; entry];
        else
            C.entries(exists_idx) = entry;
        end
    end

    C.meta.updated_at = char(datetime('now'));
    M.C = C;

    fprintf('\nSaved pointer-only day container:\n  %s\n', container_path);
end

function cfg = fill_cfg_defaults(cfg)
    if ~isfield(cfg,'stimDI')
        cfg.stimDI = 5;
    end
    if ~isfield(cfg,'camDI')
        cfg.camDI = 2;
    end
    if ~isfield(cfg,'pre_sec')
        cfg.pre_sec = 1.0;
    end
    if ~isfield(cfg,'post_sec')
        cfg.post_sec = 3.0;
    end
    if ~isfield(cfg,'expected_n_trials')
        cfg.expected_n_trials = NaN;
    end
end

function entry = extract_intan_pointer_entry(cond_dir, cfg, dataset_root)

    [~, folder_name] = fileparts(cond_dir);

    stim_channel = parse_stim_channel_from_folder(folder_name);
    current_uA   = parse_current_from_folder(folder_name);

    img_dir = fullfile(cond_dir, 'img');
    assert(exist(img_dir,'dir')==7, ...
        'Missing img/ in condition folder: %s', cond_dir);

    % Find run folder with .rhd
    run_dir = find_rhd_run_dir(cond_dir);

    % Compute onset indices + FPS
    [trial_onset_frame_idx, Freq] = compute_trial_onsets_intan(run_dir, cfg.stimDI, cfg.camDI);

    entry = struct();

    entry.key          = relpath(cond_dir, dataset_root);
    entry.cond_dir_rel = relpath(cond_dir, dataset_root);
    entry.img_dir_rel  = relpath(img_dir, dataset_root);
    entry.run_dir_rel  = relpath(run_dir, dataset_root);

    entry.folder_name  = folder_name;
    entry.stim_channel = stim_channel;
    entry.current_uA   = current_uA;

    entry.Freq = Freq;
    entry.trial_onset_frame_idx = trial_onset_frame_idx(:);

    entry.stim_frame_in_trial = round(cfg.pre_sec * Freq) + 1;
    entry.pre_sec  = cfg.pre_sec;
    entry.post_sec = cfg.post_sec;

    entry.n_trials_recorded = numel(entry.trial_onset_frame_idx);
    if isfinite(cfg.expected_n_trials)
        entry.n_trials_expected = cfg.expected_n_trials;
        entry.is_incomplete = entry.n_trials_recorded < entry.n_trials_expected;
    else
        entry.n_trials_expected = NaN;
        entry.is_incomplete = false;
    end

    entry.provenance = struct();
    entry.provenance.updated_at = char(datetime('now'));
end

function [trial_onset_frame_idx, Freq] = compute_trial_onsets_intan(run_dir, stimDI, camDI)
% Returns trial onset frame indices into camera TTL sequence

    old_dir = pwd;
    cleanupObj = onCleanup(@() cd(old_dir)); %#ok<NASGU>
    cd(run_dir);

    DIR = dir('*.rhd');
    assert(~isempty(DIR), 'No .rhd files in %s', run_dir);

    recFile = cell(1, numel(DIR));
    for i = 1:numel(DIR)
        read_Intan_RHD2000_fileV3(DIR(i).name, []);
        dig = evalin('base','board_dig_in_data');
        recFile{1,i} = dig;
    end
    recFile = cat(2, recFile{:});

    fp = evalin('base','frequency_parameters');
    Fs = fp.amplifier_sample_rate;

    % Stim rising edges
    x = recFile(stimDI,:);
    stim_on = find(diff(x) > 0) + 1;
    assert(~isempty(stim_on), 'No stim rising edges found in %s', run_dir);

    % Camera rising edges
    camera_rising = find(diff(recFile(camDI,:)) > 0) + 1;
    assert(numel(camera_rising) > 10, ...
        'Not enough camera TTL edges in %s', run_dir);

    % Estimate FPS
    Freq = 1 / (mean(diff(camera_rising)) / Fs);

    % Map each stim onset to nearest camera frame index
    trial_onset_frame_idx = zeros(numel(stim_on), 1);
    for i = 1:numel(stim_on)
        [~, j] = min(abs(camera_rising - stim_on(i)));
        trial_onset_frame_idx(i) = j;
    end
end

function stim_channel = parse_stim_channel_from_folder(folder_name)
% e.g. "...ch2_16..." => (2-1)*32 + 16 = 48
    stim_channel = NaN;
    tok = regexp(folder_name, 'ch(\d+)_(\d+)', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    shank = str2double(tok{1});
    ch    = str2double(tok{2});
    stim_channel = (shank - 1) * 32 + ch;
end

function current_uA = parse_current_from_folder(folder_name)
% e.g. "..._c0p5" => 0.5
    current_uA = NaN;
    tok = regexp(folder_name, '_c([0-9]+(?:p[0-9]+)?)', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    s = strrep(tok{1}, 'p', '.');
    current_uA = str2double(s);
end

function run_dir = find_rhd_run_dir(cond_dir)

    % Case 1: .rhd directly in cond_dir
    rhd_here = dir(fullfile(cond_dir, '*.rhd'));
    if ~isempty(rhd_here)
        run_dir = cond_dir;
        return;
    end

    % Case 2: .rhd in a subfolder
    sub = dir(cond_dir);
    sub = sub([sub.isdir]);
    sub = sub(~ismember({sub.name}, {'.','..','img','analysis','group_outputs','derived'}));

    assert(~isempty(sub), ...
        'No subfolders found in %s (expected a run folder with .rhd files).', cond_dir);

    candidates = {};
    for i = 1:numel(sub)
        this_dir = fullfile(cond_dir, sub(i).name);
        rhd_here = dir(fullfile(this_dir, '*.rhd'));
        if ~isempty(rhd_here)
            candidates{end+1} = this_dir; %#ok<AGROW>
        end
    end

    assert(~isempty(candidates), ...
        'No subfolder in %s contains .rhd files.', cond_dir);

    if numel(candidates) > 1
        counts = cellfun(@(p) numel(dir(fullfile(p,'*.rhd'))), candidates);
        [~, j] = max(counts);
        run_dir = candidates{j};
        warning('Multiple run folders found in %s. Using folder with most .rhd: %s', cond_dir, run_dir);
    else
        run_dir = candidates{1};
    end
end

function rel = relpath(fullpath, root_dir)
% Store relative paths to avoid future drive-letter/path edits.

    fullpath = char(fullpath);
    root_dir = char(root_dir);

    fullpath = strrep(fullpath, '/', filesep);
    fullpath = strrep(fullpath, '\', filesep);
    root_dir = strrep(root_dir, '/', filesep);
    root_dir = strrep(root_dir, '\', filesep);

    if startsWith(fullpath, root_dir)
        rel = fullpath(numel(root_dir)+2:end);
    else
        rel = fullpath;
    end

    rel = strrep(rel, '\', '/');
end