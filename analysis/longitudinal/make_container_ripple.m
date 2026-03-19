function container_path = make_container_ripple(out_mat_file, cfg, container_name)
% make_container_ripple_pointer_only
%
% Builds a small pointer-only container from Ripple bookkeeping file:
%   {subject}_{date}_wf_stim_aligned_out.mat  (contains struct "out")
%
% ROBUST TO:
%   - Partial experimental runs (e.g., IBLRig stopped early)
%   - Mismatched trial vector lengths
%   - Incorrect preallocated n_trials
%
% Container stores:
%   - dataset_root (fixed)
%   - relative paths (img_dir, mask_file, session_mat, csv_file, out_mat_file)
%   - cfg (pre/post window for later extraction)
%   - entries grouped by (stim_channel, current_uA)
%       each entry stores trial_onset_frame_idx and trial_index
%
% It does NOT store movies, dF/F, maps, peaks, etc.

    % ---- FIXED ROOT ----
    dataset_root = 'C:\Albert Li\LGN\LGN11_longitudinal';

    if nargin < 2 || isempty(cfg), cfg = struct(); end
    cfg = fill_cfg_defaults(cfg);

    if nargin < 3 || isempty(container_name)
        container_name = 'container_day_pointer_only_ripple.mat';
    end

    assert(exist(out_mat_file,'file')==2, ...
        'out_mat_file not found: %s', out_mat_file);

    X = load(out_mat_file, 'out');
    assert(isfield(X,'out'), ...
        'Expected variable "out" in %s', out_mat_file);

    out = X.out;

    % -----------------------------
    % Basic metadata
    % -----------------------------
    subject_id = getfield_safe(out, 'subject_id', '');
    date_str   = getfield_safe(out, 'date_str',   '');

    img_dir     = getfield_safe(out, 'img_dir', '');
    mask_file   = getfield_safe(out, 'mask_file', '');
    session_mat = getfield_safe(out, 'session_mat', '');
    csv_file    = getfield_safe(out, 'csv_file', '');

    assert(~isempty(img_dir)   && exist(img_dir,'dir')==7, ...
        'out.img_dir missing/invalid.');
    assert(~isempty(mask_file) && exist(mask_file,'file')==2, ...
        'out.mask_file missing/invalid.');
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

        C = struct();

        C.meta = struct();
        C.meta.dataset_root = dataset_root;
        C.meta.source       = 'ripple';
        C.meta.subject_id   = subject_id;
        C.meta.date_str     = date_str;

        C.meta.out_mat_file_rel = relpath(out_mat_file, dataset_root);
        C.meta.img_dir_rel      = relpath(img_dir, dataset_root);
        C.meta.mask_file_rel    = relpath(mask_file, dataset_root);
        C.meta.session_mat_rel  = relpath(session_mat, dataset_root);
        C.meta.csv_file_rel     = relpath(csv_file, dataset_root);

        C.meta.created_at = char(datetime('now'));
        C.meta.updated_at = C.meta.created_at;

        C.cfg = cfg;
        C.entries = struct([]);

        save(container_path, 'C', '-v7.3');
    end

    M = matfile(container_path, 'Writable', true);
    C = M.C;
    C.cfg = cfg;

    % -----------------------------
    % Group by (stim_channel, current)
    % -----------------------------
    pair = [stim_chan, current_uA];
    [uniq_pairs, ~, grp] = unique(pair, 'rows', 'stable');

    for g = 1:size(uniq_pairs,1)

        sc = uniq_pairs(g,1);
        cu = uniq_pairs(g,2);

        idx = find(grp == g);
        if isempty(idx), continue; end

        entry = struct();
        entry.key = sprintf('stim%03d_c%s', round(sc), num2str(cu));
        entry.stim_channel = sc;
        entry.current_uA   = cu;
        entry.Freq         = Freq;

        entry.trial_index = trial_idx(idx);
        entry.trial_onset_frame_idx = onset(idx);

        entry.img_dir_rel = relpath(img_dir, dataset_root);

        entry.provenance = struct();
        entry.provenance.source_out_mat_rel = ...
            relpath(out_mat_file, dataset_root);
        entry.provenance.updated_at = char(datetime('now'));

        % Overwrite existing key if present
        exists_idx = [];
        if isfield(C,'entries') && ~isempty(C.entries)
            keys = string({C.entries.key});
            j = find(keys == string(entry.key), 1);
            if ~isempty(j), exists_idx = j; end
        end

        if isempty(exists_idx)
            C.entries = [C.entries; entry];
        else
            C.entries(exists_idx) = entry;
        end
    end

    C.meta.updated_at = char(datetime('now'));
    M.C = C;

    fprintf('\nSaved Ripple pointer-only container:\n  %s\n', container_path);
end


% ============================================================
% Helpers
% ============================================================

function cfg = fill_cfg_defaults(cfg)
    if ~isfield(cfg,'pre_sec'),  cfg.pre_sec  = 1.0; end
    if ~isfield(cfg,'post_sec'), cfg.post_sec = 3.0; end
end


function v = getfield_safe(S, f, default)
    if isstruct(S) && isfield(S,f)
        v = S.(f);
        if isempty(v), v = default; end
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