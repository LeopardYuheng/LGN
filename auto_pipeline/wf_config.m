function cfg = wf_config()
%WF_CONFIG  Every setting the automated widefield pipeline uses.
%
% This is the one file to edit. Nothing else in this folder contains a
% hard-coded path, threshold or naming rule.

cfg = struct();

%% ====================================================================
%  WHERE THINGS LIVE
%  ====================================================================

% The analysis repository holding the original step scripts. This folder is
% only ever READ FROM: scripts are executed where they sit, and the two that
% need a source tweak are copied to the temp folder first. Nothing the
% automation produces is written inside it.
cfg.pipeline_root = 'C:\Projects\LGN\WF_data analysis pipeline';

% Where finished results go by default. One subfolder per experiment,
% named {SUBJECT}_{MMDDYYYY}.
cfg.output_root = 'C:\Projects\LGN\WF_result';

% Default destination offered for each experiment's results. Every
% experiment's folder is shown on the confirmation screen before the run and
% can be changed there individually, whatever this says.
%   'ask'          start from WF_result and let the confirmation screen decide
%   'result_root'  always under cfg.output_root
%   'with_data'    always in the experiment's own folder on the portable disk
cfg.output_location = 'ask';

% When results go next to the data, they go in a new folder inside the
% experiment folder, named {SUBJECT}_{MMDDYYYY} plus this suffix:
%   E:\Yuheng_LGN\LGN24_08212026_postblind_WFimage\LGN24_08212026_analysis\
% Set it to empty to write straight into the experiment folder instead,
% alongside img\ and ephys\.
cfg.output_with_data_suffix = '_analysis';

% Candidate drive letters searched for the portable disk, in order. The
% first removable/available drive containing a folder that looks like
% session data wins. Set cfg.disk_root to a fixed path to skip the search.
cfg.disk_search_letters = {'D:\','E:\','F:\','G:\','H:\','I:\','J:\'};
cfg.disk_root           = '';    % e.g. 'E:\' to pin it

% Optional subfolder on the disk to restrict the scan to (leave empty to
% scan from the disk root). Speeds up scanning on a crowded drive.
cfg.disk_subfolder = '';

% Retinotopy maps for step 6. The pipeline looks for a ready-made file
% matching cfg.retino_pattern for the subject, first on the portable disk,
% then here.
cfg.retino_root    = 'C:\Projects\LGN\retinotopic_mapping\result';
cfg.retino_pattern = '*registration_ready*.mat';

% If no ready-made file exists, pre-step A builds one by running
% retino_inputcombine.m on a folder holding these three raw map files.
% The pipeline searches the portable disk for a folder containing all of
% them; cfg.retino_ask_if_missing decides what happens when it finds none
% or several.
cfg.retino_raw_files    = {'azi.mat', 'alt.mat', 'additional_maps.mat'};
cfg.retino_ask_if_missing = true;   % true: open a folder picker so you can
                                    % point at the retinotopy folder yourself
                                    % false: skip step 6 for that subject

%% ====================================================================
%  DISK SCANNING
%  ====================================================================

% How deep below the scan root to look for session folders.
%   disk\yuheng\lgn24_stim_WF_07242026\session1\img            needs 4
%   disk\Yuheng_LGN\LGN24_..._WFimage\data\session1\img        needs 4
%   ... with an extra folder above either of those             needs 5
% Set well above the deepest layout in use: the cost of a larger number is
% only scan time, while too small a number silently finds nothing.
cfg.scan_max_depth = 7;

% A folder is treated as a TIFF folder if it holds at least this many .tif
% files whose names end in a number.
cfg.min_tiffs = 200;

% Folders holding the .nev and the trial CSV, as siblings of the TIFF
% folder. Tried in this order before any other sibling.
cfg.ephys_folder_names = {'ephys', 'ripple', 'nev'};

% The recording often sits one level deeper, in a single subfolder created
% by the acquisition software:  session1\ephys\<recording>\*.nev
% How many such levels to follow. A level is only followed when it holds
% EXACTLY ONE subfolder - with two or more there is no way to tell which is
% the right one, so the session is reported as unresolved instead of
% guessing. Set to 0 to require the files directly inside ephys.
cfg.ephys_descend_depth = 2;

% Patterns used to pull subject and date out of folder names. Each is a
% regexp with named tokens <subj> and <date>, tried in order; the first that
% yields a valid date wins. Dates are normalised to YYYYMMDD.
%
% ".*?" between the two tokens is what lets "lgn24_stim_WF_07242026" work -
% the subject and the date are separated by free text.
cfg.id_patterns = { ...
    '(?<subj>LGN\d+).*?(?<date>20\d{6})' , 'ymd' ; ...   lgn26_..._20260630
    '(?<subj>LGN\d+).*?(?<date>\d{8})'   , 'mdy' ; ...   lgn24_stim_WF_07242026
    '(?<subj>LGN\d+).*?(?<date>\d{4})'   , 'md'    ...   lgn26_0630
    };

% Year assumed when a folder name carries only MMDD. Leave empty to take the
% year from the TIFF folder's modification date.
cfg.assume_year = '';

% Regexps identifying which of several folders/files under one session is
% session 1, 2 and 3 of a three-session experiment.
cfg.session_patterns = {'(?:^|[^a-z])s(?:ession)?[ _\-]?1(?:$|[^0-9])', ...
                        '(?:^|[^a-z])s(?:ession)?[ _\-]?2(?:$|[^0-9])', ...
                        '(?:^|[^a-z])s(?:ession)?[ _\-]?3(?:$|[^0-9])'};

% Trial-design CSV: how to recognise it among other .csv files.
cfg.csv_pattern = '\.(csv|txt)$';

%% ====================================================================
%  STEP 0 - AUTOMATIC BRAIN MASK
%  ====================================================================

cfg.mask.n_ref_frames   = 200;    % frames averaged into the reference image
cfg.mask.smooth_sigma   = 3;      % gaussian smoothing before thresholding (px)
cfg.mask.close_radius   = 12;     % morphological closing radius (px)
cfg.mask.open_radius    = 6;      % morphological opening radius (px)
cfg.mask.erode_radius   = 4;      % final inward shrink, keeps the rim out (px)
cfg.mask.min_area_frac  = 0.03;   % reject candidate regions smaller than this
cfg.mask.max_area_frac  = 0.95;   % ... or larger than this (fraction of frame)
cfg.mask.verify         = true;   % show the accept/adjust/redraw window
cfg.mask.reuse_existing = true;   % skip step 0 if a brain_mask.mat is present

%% ====================================================================
%  STEP 6 - RETINOTOPIC ALIGNMENT
%  ====================================================================

cfg.retino.enabled        = true;   % false: skip step 6, no V1 overlay

% false (default): you pick matching landmarks in cpselect.
% true           : imregtform proposes the affine and the nudge GUI corrects
%                  it. Either way the accept / re-align loop below applies.
cfg.retino.auto_register  = false;

% After each attempt, show the aligned boundaries over the stimulation image
% and ask whether to keep it. "Re-align" starts that experiment's step 6
% over, as many times as needed. Turning this off accepts the first attempt
% unseen, which is only sensible for a re-run of already-checked data.
cfg.retino.verify         = true;
cfg.retino.reuse_existing = true;   % skip if a day_setup.mat is already there

% Before aligning, show the retinotopy maps themselves (reference image with
% visual-area boundaries, azimuth, altitude) and ask whether they are the
% right ones for this experiment. Retinotopy files are reused across
% sessions and the pipeline may pick one up from an earlier experiment, so
% this is the check that stops another animal's map being used unnoticed.
cfg.retino.confirm_map    = true;

%% ====================================================================
%  ANALYSIS PARAMETERS
%  ====================================================================

% Step 1 metadata
cfg.experiment_id = 'WF_StimSurvey';
cfg.base_name     = 'ripple_timing';

% Step 5_A frame-grid display window (seconds). Saved data is unaffected -
% every frame is always written regardless of this setting.
cfg.display_tmin = -0.2;
cfg.display_tmax =  1.2;

% Which channel/current conditions to process in step 5_A.
%   'all'   every condition present in the day pointer
%   or a cell of {channel, current} pairs, e.g. {101, 5; 29, 6}
cfg.conditions = 'all';

% MP4 export in step 5_A. Both off keeps runtime and disk use down.
cfg.video_per_trial = false;
cfg.video_mean      = false;

% Step 4 (baseline drift) is only required for Method 1 / Tracks B and C.
% For a 5_A-only run it is a useful QC output; leave true unless you are in
% a hurry, since it re-reads every 0 uA trial.
cfg.run_step4 = true;

%% ====================================================================
%  RUN BEHAVIOUR
%  ====================================================================

% Skip a step whose expected output file already exists. Makes a re-run
% after a crash cheap, and lets you re-run one experiment without redoing
% the others.
cfg.resume = true;

% What to do when a step raises an error.
%   'ask'      stop and show the error with Retry / Skip / Stop all
%              (Retry re-enters the experiment; finished steps are skipped,
%              so it resumes at the step that failed)
%   'continue' log it, abandon that experiment, move to the next
%   'stop'     abandon the whole batch
cfg.on_error = 'ask';

% Capture everything the pipeline scripts print into the experiment's log
% file, not just the pipeline's own progress lines. This is what makes the
% log worth watching during a long step.
cfg.capture_script_output = true;

% Strict dialog handling. true: an unanswered dialog is an error, which is
% what you want for an unattended run. false: unanswered dialogs are shown
% so you can answer them, useful when debugging a new data layout.
cfg.strict_dialogs = true;

% Ask for confirmation of the detected experiment list before running.
cfg.confirm_before_run = true;

end
