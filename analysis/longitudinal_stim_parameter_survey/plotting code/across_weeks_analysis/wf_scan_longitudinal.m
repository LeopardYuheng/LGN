function S = wf_scan_longitudinal(root_dir)
%WF_SCAN_LONGITUDINAL  Index the longitudinal_data tree of mean dF/F files.
%
%   S = wf_scan_longitudinal(root_dir)
%
% Walks the channel-major tree
%
%   <root>/<MOUSE>_CH<N>[-]/<phase>_WEEK<k>/mean_dff_ch<N>_<I>uA.mat
%
% and returns one struct element per (channel, week) session that actually
% holds files, sorted by mouse, channel, then time.
%
% Fields:
%   mouse, channel, chan_folder, week_folder, phase
%   week_index   signed position on the time axis: pre-blind weeks are
%                -4..-1, post-blind weeks +1.. . Blinding sits at 0, so the
%                spacing between points is correct by construction.
%   week_label   what goes on the x axis ('pre W1' ... 'post W6')
%   currents     ascending vector of currents (uA) present in that folder
%   files        matching cellstr of full paths
%   is_high_current  true for the 0/3/6/8/10/12 uA protocol session
%
% The two mice were blinded a week apart, so the SAME calendar session
% (0916, the high-current day) is post-week 6 for LGN24 but post-week 5 for
% LGN26. Both sit in a folder named postblind_WEEK5, so that one case is
% corrected here rather than by renaming anyone's data.

if nargin < 1 || isempty(root_dir)
    root_dir = uigetdir(pwd, 'Select the longitudinal_data folder');
    if isequal(root_dir, 0), error('No folder selected.'); end
end
assert(isfolder(root_dir), 'Not a folder:\n  %s', root_dir);

S = struct('mouse', {}, 'channel', {}, 'chan_folder', {}, 'week_folder', {}, ...
    'phase', {}, 'week_index', {}, 'week_label', {}, 'currents', {}, ...
    'files', {}, 'is_high_current', {});

chan_dirs = dir(root_dir);
chan_dirs = chan_dirs([chan_dirs.isdir]);
chan_dirs = chan_dirs(~ismember({chan_dirs.name}, {'.', '..'}));

for ci = 1:numel(chan_dirs)
    cname = chan_dirs(ci).name;
    tok = regexp(cname, '^(\w+?)_CH(\d+)', 'tokens', 'once');
    if isempty(tok)
        % Only flag folders that look like a mis-named channel; output
        % folders written into the tree (figures, ROIs, ...) are skipped
        % quietly so every run is not noisy.
        if ~isempty(regexpi(cname, 'ch\d', 'once'))
            warning('Skipping folder that is not <MOUSE>_CH<N>: %s', cname);
        end
        continue;
    end
    mouse = tok{1};
    ch    = str2double(tok{2});

    wk_dirs = dir(fullfile(root_dir, cname));
    wk_dirs = wk_dirs([wk_dirs.isdir]);
    wk_dirs = wk_dirs(~ismember({wk_dirs.name}, {'.', '..'}));

    for wi = 1:numel(wk_dirs)
        wname = wk_dirs(wi).name;
        wtok = regexp(wname, '^(pre|post)blind_WEEK(\d+)$', 'tokens', 'once');
        if isempty(wtok)
            warning('Skipping folder that is not <phase>blind_WEEK<k>: %s/%s', cname, wname);
            continue;
        end
        phase = wtok{1};
        k     = str2double(wtok{2});

        d = dir(fullfile(root_dir, cname, wname, sprintf('mean_dff_ch%d_*uA.mat', ch)));
        if isempty(d), continue; end   % week not copied / not recorded

        cur = nan(numel(d), 1);
        for fi = 1:numel(d)
            ct = regexp(d(fi).name, '_([\d.]+)uA\.mat$', 'tokens', 'once');
            if ~isempty(ct), cur(fi) = str2double(ct{1}); end
        end
        keep = isfinite(cur);
        d = d(keep); cur = cur(keep);
        [cur, ord] = sort(cur);
        d = d(ord);

        widx = week_index_for(mouse, phase, k);
        S(end+1) = struct( ...
            'mouse',           mouse, ...
            'channel',         ch, ...
            'chan_folder',     cname, ...
            'week_folder',     wname, ...
            'phase',           phase, ...
            'week_index',      widx, ...
            'week_label',      label_for(widx), ...
            'currents',        cur(:), ...
            'files',           {fullfile({d.folder}', {d.name}')}, ...
            'is_high_current', any(cur > 7)); %#ok<AGROW>
    end
end

assert(~isempty(S), 'No mean_dff files found under:\n  %s', root_dir);

% Sort by mouse (alphabetical), then channel, then time. The keys are kept
% numeric: sorting week_index as text would put +1 before -4.
[~, ~, mouse_id] = unique(string({S.mouse}'));
[~, ord] = sortrows([mouse_id, [S.channel]', [S.week_index]']);
S = S(ord);
end

% =========================================================================
function widx = week_index_for(mouse, phase, k)
% Pre-blind WEEK1..4 -> -4..-1 (blinding at 0), post-blind WEEK k -> +k.
if strcmpi(phase, 'pre')
    widx = k - 5;
else
    widx = k;
    % LGN24 was blinded a week before LGN26 and has no post-week-5 session,
    % so its postblind_WEEK5 folder actually holds post-week 6 (0916).
    if strcmpi(mouse, 'LGN24') && k == 5
        widx = 6;
    end
end
end

% =========================================================================
function lbl = label_for(widx)
if widx < 0
    lbl = sprintf('pre W%d', widx + 5);
else
    lbl = sprintf('post W%d', widx);
end
end
