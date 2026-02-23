function [csv_path, trial_table] = write_trials_to_csv_wf_stim( ...
    currents_uA, channels, num_trials_per_parameter, path, base_name)
%WRITE_TRIALS_TO_CSV_WF_STIM Generate randomized stim trials and write to CSV.
%
% Inputs
%   currents_uA              numeric vector, e.g. [0 2 3 4 5 7]
%   channels                 numeric vector, e.g. [10 11 12 13 14 15 16 17]
%   num_trials_per_parameter positive integer, e.g. 30
%   path                     directory where CSV will be saved
%   base_name                (optional) filename prefix
%
% Outputs
%   csv_path                 full path to written CSV
%   trial_table              MATLAB table of randomized trials

    % ---- defaults ----
    if nargin < 5 || isempty(base_name)
        base_name = 'wf_stim_trials';
    end
    if nargin < 4 || isempty(path)
        path = pwd;
    end

    % ---- validate ----
    validateattributes(currents_uA, {'numeric'}, {'vector', 'nonempty', 'finite', 'real'});
    validateattributes(channels,    {'numeric'}, {'vector', 'nonempty', 'finite', 'integer'});
    validateattributes(num_trials_per_parameter, {'numeric'}, {'scalar', 'integer', 'positive'});

    currents_uA = currents_uA(:);
    channels    = channels(:);

    % ---- build full factorial (channel × current) ----
    [ch_grid, cur_grid] = ndgrid(channels, currents_uA);
    combos = [ch_grid(:), cur_grid(:)];

    % ---- replicate each combo ----
    combos_rep = repelem(combos, num_trials_per_parameter, 1);

    % ---- randomize order ----
    n_trials = size(combos_rep, 1);
    perm = randperm(n_trials);
    combos_rep = combos_rep(perm, :);

    % ---- table ----
    trial_table = table;
    trial_table.trial_index  = (1:n_trials).';
    trial_table.stim_channel = combos_rep(:,1);
    trial_table.current_uA   = combos_rep(:,2);

    % ---- ensure directory exists ----
    if ~exist(path, 'dir')
        mkdir(path);
    end

    % ---- timestamped filename ----
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    filename = sprintf('%s_%s.csv', base_name, ts);
    csv_path = fullfile(path, filename);

    % ---- write ----
    writetable(trial_table, csv_path);
end
