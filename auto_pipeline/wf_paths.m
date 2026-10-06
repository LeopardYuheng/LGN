function P = wf_paths(pipelineRoot)
%WF_PATHS  Locate every pipeline script the automation needs to run.
%
%   P = WF_PATHS()               use cfg.pipeline_root from wf_config
%   P = WF_PATHS(pipelineRoot)   use an explicit repository root
%
% This folder lives OUTSIDE the analysis repository on purpose, so nothing
% here can overwrite an original script. Everything below is read-only from
% the automation's point of view: scripts are executed where they sit, and
% the two that need a source tweak are copied to the temp folder first.

if nargin < 1 || isempty(pipelineRoot)
    cfg          = wf_config();
    pipelineRoot = cfg.pipeline_root;
end

here = fileparts(mfilename('fullpath'));

if isempty(pipelineRoot)
    % Fallback: look for the analysis repository beside this folder, under
    % either of the names it has had.
    parent = fileparts(here);
    for candidate = {'WF_data analysis pipeline', 'data analysis pipeline'}
        p = fullfile(parent, candidate{1});
        if exist(p, 'dir') == 7
            pipelineRoot = p;
            break;
        end
    end
    if isempty(pipelineRoot)
        pipelineRoot = fullfile(parent, 'WF_data analysis pipeline');
    end
end

root = pipelineRoot;

P = struct();
P.auto_root = here;
P.repo_root = root;
P.uistub    = fullfile(here, 'uistub');

% ---- single-session pipeline -------------------------------------------
S = fullfile(root, 'analysis', 'longitudinal_stim_parameter_survey');
P.single.dir           = S;
P.single.functions     = fullfile(S, 'functions');
P.single.neuroshare    = fullfile(S, 'neuroshare');
P.single.step0         = fullfile(S, 'draw_brain_mask_0.m');
P.single.retinocombine = fullfile(S, 'retino_inputcombine.m');
P.single.step1         = fullfile(S, 'extract_nev_stim_and_camera_1.m');
P.single.tiffcheck     = fullfile(S, 'Diagnose&fix_code', 'time_misalignment_fix', ...
                                      'build_tiff_sma1_correction_map.m');
P.single.step2         = fullfile(S, 'align_wf_with_nev_extracted_2.m');
P.single.step3         = fullfile(S, 'make_container_ripple_3.m');
P.single.tifffix       = fullfile(S, 'Diagnose&fix_code', 'time_misalignment_fix', ...
                                      'apply_tiff_correction_to_day_pointer.m');
P.single.step4         = fullfile(S, 'baseline_drift_analysis_4.m');
P.single.step5A        = fullfile(S, 'current_thresholding_analysis_pixelwise_region_5A.m');
P.single.step6         = fullfile(S, 'retino_alignment_with_brain_mask_6.m');

% ---- combined (three sessions pooled) pipeline --------------------------
C = fullfile(root, 'analysis for combining three 10_trials in one', ...
                   'longitudinal_stim_parameter_survey');
P.combined.dir           = C;
P.combined.functions     = fullfile(C, 'functions');
P.combined.neuroshare    = fullfile(C, 'neuroshare');
P.combined.step0         = fullfile(C, 'draw_brain_mask_0.m');
P.combined.retinocombine = fullfile(C, 'retino_inputcombine.m');
P.combined.step1         = fullfile(C, 'extract_nev_stim_and_camera_1.m');
P.combined.tiffcheck     = fullfile(C, 'Diagnose&fix_code', 'build_tiff_sma1_correction_map.m');
P.combined.step2         = fullfile(C, 'align_wf_with_nev_extracted_2.m');
P.combined.step3         = fullfile(C, 'make_container_ripple_3.m');
P.combined.tifffix       = fullfile(C, 'Diagnose&fix_code', 'apply_tiff_correction_to_day_pointer.m');
P.combined.step4         = fullfile(C, 'baseline_drift_analysis_4.m');
P.combined.step5A        = fullfile(C, 'current_thresholding_analysis_pixelwise_region_5A.m');
P.combined.step6         = fullfile(C, 'retino_alignment_with_brain_mask_6.m');

end
