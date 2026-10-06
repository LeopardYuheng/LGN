function wf_pipeline_launch()
%WF_PIPELINE_LAUNCH  Entry point used by Run_WF_Pipeline.bat.
%
% Puts this folder on the MATLAB path, checks the installation,
% and opens the pipeline window. Kept separate from wf_pipeline_app so the
% .bat file has one stable thing to call.

here = fileparts(mfilename('fullpath'));
addpath(here);

fprintf('\n');
fprintf('  LGN widefield pipeline\n');
fprintf('  %s\n', repmat('-', 1, 60));

[ok, missing] = wf_check_paths();
if ~ok
    fprintf('\n  Installation problem - these pipeline scripts were not found:\n');
    fprintf('    %s\n', missing{:});
    fprintf(['\n  Set cfg.pipeline_root in wf_config.m to the folder holding ' ...
             'your analysis scripts.\n\n']);
    return;
end

req = {'Image Processing Toolbox'};
v   = ver;
have = {v.Name};
for i = 1:numel(req)
    if ~any(strcmp(have, req{i}))
        fprintf('\n  Warning: %s is not installed. Steps 0 and 6 need it.\n', req{i});
    end
end

fprintf('  Opening the pipeline window...\n\n');
wf_pipeline_app();

end
