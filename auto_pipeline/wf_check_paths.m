function [ok, missing] = wf_check_paths(verbose)
%WF_CHECK_PATHS  Confirm the installation is wired up correctly.
%
%   [ok, missing] = WF_CHECK_PATHS()
%   WF_CHECK_PATHS(true)   also prints a report
%
% Checks that every pipeline script the automation calls exists where
% cfg.pipeline_root says it should, and that neither this folder nor the
% output folder sits inside the analysis repository - they are deliberately
% kept outside it so nothing here can land on top of an original script.

if nargin < 1, verbose = false; end

cfg     = wf_config();
P       = wf_paths();
missing = {};

if exist(P.repo_root, 'dir') ~= 7
    missing{end+1} = sprintf('pipeline_root does not exist : %s', P.repo_root);
    ok = false;
    if verbose
        fprintf('wf_check_paths: %s\n', missing{1});
        fprintf('  Set cfg.pipeline_root in wf_config.m to the analysis repository.\n');
    end
    return;
end

tracks = {'single', 'combined'};
steps  = {'step0', 'retinocombine', 'step1', 'tiffcheck', 'step2', 'step3', ...
          'tifffix', 'step4', 'step5A', 'step6'};

for t = 1:numel(tracks)
    d = P.(tracks{t}).dir;
    if exist(d, 'dir') ~= 7
        missing{end+1} = sprintf('%s / folder : %s', tracks{t}, d); %#ok<AGROW>
        continue;
    end
    for s = 1:numel(steps)
        f = P.(tracks{t}).(steps{s});
        if exist(f, 'file') ~= 2
            missing{end+1} = sprintf('%s / %s : %s', tracks{t}, steps{s}, f); %#ok<AGROW>
        end
    end
end

% Results must never be written inside the analysis repository.
if wf_is_inside(cfg.output_root, P.repo_root)
    missing{end+1} = sprintf(...
        ['output_root (%s) is inside pipeline_root (%s). Point it somewhere ' ...
         'else so results cannot overwrite original scripts.'], ...
        cfg.output_root, P.repo_root);
end
if wf_is_inside(P.auto_root, P.repo_root)
    missing{end+1} = sprintf(...
        ['this automation folder (%s) is inside pipeline_root (%s). Move it ' ...
         'out so the analysis repository stays untouched.'], ...
        P.auto_root, P.repo_root);
end

ok = isempty(missing);

if verbose
    if ok
        fprintf('wf_check_paths: installation looks correct.\n');
        fprintf('  automation : %s\n', P.auto_root);
        fprintf('  scripts    : %s  (read only)\n', P.repo_root);
        fprintf('  results    : %s\n', cfg.output_root);
    else
        fprintf('wf_check_paths: %d problem(s):\n', numel(missing));
        fprintf('  %s\n', missing{:});
    end
end

end

% =====================================================================
function tf = wf_is_inside(child, parent)

c = wf_norm(child);
p = wf_norm(parent);

tf = ~isempty(p) && strncmpi(c, [p filesep], numel(p) + 1);

end

% =====================================================================
function s = wf_norm(p)

s = regexprep(char(p), '[\\/]+$', '');

end
