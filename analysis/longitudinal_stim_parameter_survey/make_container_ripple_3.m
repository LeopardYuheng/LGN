%% make_container_ripple.m
% Builds a small day pointer from a widefield trial alignment file:
%   {subject}_{date}_wf_trial_alignment.mat
%
% ROBUST TO:
%   - Partial experimental runs
%   - Mismatched trial vector lengths
%   - Incorrect preallocated n_trials
%
% Container stores:
%   - dataset_root
%   - relative paths3       
%   - cfg
%   - entries grouped by (stim_channel, current_uA)
%
% This is a single script version. Run the whole file directly.

clc; clear;

%% ---------------- USER INPUTS ----------------
cfg = struct();
cfg.pre_sec  = 1;
cfg.post_sec = 3;

out_mat_file = 'C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-04-24\analysis\LGN11_20260424_wf_trial_alignment.mat';
container_name = 'LGN11_20260424_day_pointer.mat';

%% ---------------- MAIN ----------------
container_path = make_container_ripple_(out_mat_file, cfg, container_name);

fprintf('\nDone.\nContainer path:\n%s\n', container_path);

%% ============================================================
% Local functions
% ============================================================

function container_path = make_container_ripple_(out_mat_file, cfg, container_name)
% make_container_ripple
%
% Single-script version of the Ripple pointer-only container builder.

    % ---- FIXED ROOT ----
    dataset_root = 'C:\Albert Li\LGN\LGN11_longitudinal';

    if nargin < 2 || isempty(cfg)
        cfg = struct();
    end
    cfg = fill_cfg_defaults(cfg);

    assert(exist(out_mat_file,'file')==2, ...
        'out_mat_file not found: %s', out_mat_file);

    X = load(out_mat_file);
    if isfield(X,'wf_trial_alignment')
        out = X.wf_trial_alignment;
    elseif isfield(X,'out')
        out = X.out;
    else
        error('Expected variable "wf_trial_alignment" or legacy variable "out" in %s', out_mat_file);
    end

    % -----------------------------
    % Basic metadata
    % -----------------------------
    subject_id = getfield_safe(out, 'subject_id', '');
    date_str   = getfield_safe(out, 'date_str',   '');

    if nargin < 3 || isempty(container_name)
        container_name = sprintf('%s_%s_day_pointer.mat', subject_id, date_str);
    end

    img_dir        = getfield_safe(out, 'img_dir', '');
    day_setup_file = getfield_safe(out, 'day_setup_file', '');
    session_mat    = getfield_safe(out, 'session_mat', '');
    csv_file       = getfield_safe(out, 'csv_file', '');
    
    assert(~isempty(img_dir) && exist(img_dir,'dir')==7, ...
        'out.img_dir missing/invalid.');
    assert(~isempty(day_setup_file) && exist(day_setup_file,'file')==2, ...
        'out.day_setup_file missing/invalid.');
    assert(~isempty(session_mat) && exist(session_mat,'file')==2, ...
        'out.session_mat missing/invalid.');
    assert(~isempty(csv_file) && exist(csv_file,'file')==2, ...
        'out.csv_file missing/invalid.');

    Freq = double(getfield_safe(out, 'Freq', NaN));
    assert(isfinite(Freq) && Freq > 0, ...
        'out.Freq missing/invalid.');

    % -----------------------------
    % Pull trial vectors
    % -----------------------------
    onset = double(getfield_safe(out, 'trial_onset_frame_idx', []));
    onset = onset(:);

    stim_chan = double(getfield_safe(out, 'trial_stim_chan', []));
    if isempty(stim_chan)
        stim_chan = double(getfield_safe(out, 'trial_channel', []));
    end
    stim_chan = stim_chan(:);

    current_uA = double(getfield_safe(out, 'trial_current_uA', []));
    current_uA = current_uA(:);

    assert(~isempty(onset),      'trial_onset_frame_idx missing/empty.');
    assert(~isempty(stim_chan),  'trial_stim_chan / trial_channel missing.');
    assert(~isempty(current_uA), 'trial_current_uA missing.');

    % -----------------------------
    % ROBUST LENGTH HANDLING
    % -----------------------------
    L = [numel(onset), numel(stim_chan), numel(current_uA)];
    N = min(L);

    if any(L ~= N)
        warning(['Trial vectors mismatched (onset=%d stim=%d current=%d). ' ...
                 'Truncating to N=%d.'], ...
                 L(1), L(2), L(3), N);
    end

    onset      = onset(1:N);
    stim_chan  = stim_chan(1:N);
    current_uA = current_uA(1:N);

    trial_idx = (1:N)';

    % Remove invalid trials
    valid = isfinite(onset) & isfinite(stim_chan) & isfinite(current_uA);
    onset      = onset(valid);
    stim_chan  = stim_chan(valid);
    current_uA = current_uA(valid);
    trial_idx  = trial_idx(valid);

    fprintf('Valid trials stored: %d\n', numel(onset));

    % -----------------------------
    % Container path
    % -----------------------------
    analysis_dir = fileparts(out_mat_file);
    container_path = fullfile(analysis_dir, container_name);

    % -----------------------------
    % Initialize container if needed
    % -----------------------------
    if ~exist(container_path,'file')

        day_pointer = struct();

        day_pointer.meta = struct();
        day_pointer.meta.dataset_root = dataset_root;
        day_pointer.meta.source       = 'ripple';
        day_pointer.meta.subject_id   = subject_id;
        day_pointer.meta.date_str     = date_str;

        day_pointer.meta.wf_trial_alignment_file_rel = relpath(out_mat_file, dataset_root);
        day_pointer.meta.img_dir_rel      = relpath(img_dir, dataset_root);
        day_pointer.meta.day_setup_file_rel = relpath(day_setup_file, dataset_root);        
        day_pointer.meta.session_mat_rel  = relpath(session_mat, dataset_root);
        day_pointer.meta.csv_file_rel     = relpath(csv_file, dataset_root);

        day_pointer.meta.created_at = char(datetime('now'));
        day_pointer.meta.updated_at = day_pointer.meta.created_at;

        day_pointer.cfg = cfg;
        day_pointer.entries = struct([]);

        save(container_path, 'day_pointer', '-v7.3');
    end

    M = matfile(container_path, 'Writable', true);
    tmp = load(container_path);
    if isfield(tmp,'day_pointer')
        day_pointer = tmp.day_pointer;
    elseif isfield(tmp,'C')
        day_pointer = tmp.C;
    else
        error('Expected variable "day_pointer" or legacy variable "C" in %s', container_path);
    end
    day_pointer.cfg = cfg;

    % -----------------------------
    % Group by (stim_channel, current)
    % -----------------------------
    pair = [stim_chan, current_uA];
    [uniq_pairs, ~, grp] = unique(pair, 'rows', 'stable');

    for g = 1:size(uniq_pairs,1)

        sc = uniq_pairs(g,1);
        cu = uniq_pairs(g,2);

        idx = find(grp == g);
        if isempty(idx)
            continue;
        end

        entry = struct();
        entry.key = sprintf('stim%03d_c%s', round(sc), num2str(cu));
        entry.stim_channel = sc;
        entry.current_uA   = cu;
        entry.Freq         = Freq;

        entry.trial_index = trial_idx(idx);
        entry.trial_onset_frame_idx = onset(idx);

        entry.img_dir_rel = relpath(img_dir, dataset_root);

        entry.provenance = struct();
        entry.provenance.source_out_mat_rel = relpath(out_mat_file, dataset_root);
        entry.provenance.updated_at = char(datetime('now'));

        % Overwrite existing key if present
        exists_idx = [];
        if isfield(day_pointer,'entries') && ~isempty(day_pointer.entries)
            keys = string({day_pointer.entries.key});
            j = find(keys == string(entry.key), 1);
            if ~isempty(j)
                exists_idx = j;
            end
        end

        if isempty(exists_idx)
            day_pointer.entries = [day_pointer.entries; entry];
        else
            day_pointer.entries(exists_idx) = entry;
        end
    end

    day_pointer.meta.updated_at = char(datetime('now'));
    M.day_pointer = day_pointer;

    fprintf('\nSaved day pointer:\n  %s\n', container_path);
end

function cfg = fill_cfg_defaults(cfg)
    if ~isfield(cfg,'pre_sec')
        cfg.pre_sec = 1.0;
    end
    if ~isfield(cfg,'post_sec')
        cfg.post_sec = 3.0;
    end
end

function v = getfield_safe(S, f, default)
    if isstruct(S) && isfield(S,f)
        v = S.(f);
        if isempty(v)
            v = default;
        end
    else
        v = default;
    end
end

function rel = relpath(fullpath, root_dir)

    fullpath = char(fullpath);
    root_dir = char(root_dir);

    fullpath = strrep(fullpath, '/', filesep);
    fullpath = strrep(fullpath, '\', filesep);
    root_dir = strrep(root_dir, '/', filesep);
    root_dir = strrep(root_dir, '\', filesep);

    if startsWith(fullpath, root_dir)
        rel = fullpath(numel(root_dir)+2:end);
    else
        rel = fullpath;  % outside root — keep absolute
    end

    rel = strrep(rel, '\', '/');
end
