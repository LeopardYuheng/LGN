addpath 'H:\SWR_task\Ret-map\Goard\Stimulus'

%% Define Grating and Presentation Parameters
% These parameters match the figures you sent.
% orientations = 0:30:150;                   % 6 orientations (in degrees)
% spatialFreqs = [0.02, 0.04, 0.08, 0.16, 0.32]; % 5 spatial frequencies (cycles/degree)
% phases = [0, 0.25, 0.5, 0.75];             % 4 phases (fractions of a cycle)
orientations = 0:22.5:157.5;
spatialFreqs = [0.08];
phases = 0;
contrast = 0.8;                            % 80% contrast
bg = 127;                                  % Background gray (0-255)
ppcm = 2560 / 70.7;                        % Pixels per cm (adjust to your display)

t_trial = 0.25; % Duration for each stimulus in seconds
n_trial = 750;   % Number of repetitions

%% Ask User for Save Folder
file_save = input('Give the path for the folder you want the data to be saved in: ', 's');

%% Call the Static Grating Mapping Function
% The static_grating_mapping_60Hz function uses create_grating_patterns to generate
% the grating stimuli (which, as set, should be identical to your figures)
[stimOnsetTimes, stimOffsetTimes, patterns, patternParams] = ...
    static_grating_mapping_60Hz(t_trial, n_trial, orientations, spatialFreqs, phases, contrast, bg, ppcm);

%% Save All Preset Parameters and Data into a Structure
Stimdata.orientations     = orientations;
Stimdata.spatialFreqs     = spatialFreqs;
Stimdata.phases           = phases;
Stimdata.contrast         = contrast;
Stimdata.bg               = bg;
Stimdata.ppcm             = ppcm;
Stimdata.n_trial          = n_trial;
Stimdata.t_trial          = t_trial;
Stimdata.stimOnsetTimes   = stimOnsetTimes;
Stimdata.stimOffsetTimes  = stimOffsetTimes;
% Stimdata.patterns         = patterns;       % Grating patterns (3D uint8 array)
Stimdata.patternParams    = patternParams;  % Parameters of each randomized pattern

%% Save the Structure to a MAT File
currentFolder = pwd;
cd(file_save);

% Create a filename with a timestamp (replace ':' and spaces with '-')
timestamp = replace(char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss')), {' ', ':'}, '-');
filename = ['static_grating_', timestamp];

save([filename, '.mat'], 'Stimdata', '-v7.3');

cd(currentFolder);

disp(['Data saved in ', fullfile(file_save, [filename, '.mat'])]);

