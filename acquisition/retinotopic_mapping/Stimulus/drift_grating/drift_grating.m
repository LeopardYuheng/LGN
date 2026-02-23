%% Add the Stimulus Folder to the MATLAB Path
addpath 'D:\Xiaorong\SWR_task\Ret-map\Goard\Stimulus'

%% Define Grating and Presentation Parameters for Drifting Gratings
% Grating parameters
orientations  = 0:45:359;           % 8 orientations (in degrees)
spatialFreqs  = [0.08];             % Spatial frequency in cycles/degree
temporalFreqs = [1 2 4 8 15];        % 5 temporal frequencies (Hz) for drifting
phases        = 0;                 % Phase (fraction of a cycle; 0 means 0°)
contrast      = 0.8;               % 80% contrast
bg            = 127;               % Background gray level (0-255)
ppcm          = 2560 / 70.7;       % Pixels per cm (adjust to your display)

% Presentation parameters
movieDuration = 2;                % Duration of each drifting movie in seconds
pauseDuration = 1;                % Duration of the pause (gray screen) after each movie in seconds
n_trial       = 15;               % Number of repetitions per unique stimulus
frameRate     = 60;               % Display refresh rate (Hz)

%% Ask User for Save Folder
file_save = input('Give the path for the folder you want the data to be saved in: ', 's');

%% Call the Drifting Grating Mapping Function
% This function generates the base drifting grating movies (unique stimuli)
% and then shuffles them for each trial.
% It returns:
%   stimOnsetTimes, stimOffsetTimes - Timing information for each trial.
%   moviesBase                      - The unique drifting grating movies.
%   movieParamsTrial                - A struct array with stimulus parameters for each trial.
%   trialOrder                      - The randomized order of base stimuli indices.
[stimOnsetTimes, stimOffsetTimes, moviesBase, movieParamsTrial, trialOrder] = ...
    drift_grating_mapping_60Hz(movieDuration, pauseDuration, n_trial, ...
    orientations, spatialFreqs, temporalFreqs, phases, contrast, bg, ppcm, frameRate);

%% Save All Preset Parameters and Data into a Structure
Stimdata.orientations     = orientations;
Stimdata.spatialFreqs     = spatialFreqs;
Stimdata.temporalFreqs    = temporalFreqs;
Stimdata.phases           = phases;
Stimdata.contrast         = contrast;
Stimdata.bg               = bg;
Stimdata.ppcm             = ppcm;
Stimdata.n_trial          = n_trial;
Stimdata.movieDuration    = movieDuration;
Stimdata.pauseDuration    = pauseDuration;
Stimdata.frameRate        = frameRate;
Stimdata.stimOnsetTimes   = stimOnsetTimes;
Stimdata.stimOffsetTimes  = stimOffsetTimes;
Stimdata.movieParams      = movieParamsTrial;  % Trial-specific parameters.
Stimdata.trialOrder       = trialOrder;
% Optionally, include the base movies array (warning: this may result in a large file)
% Stimdata.moviesBase       = moviesBase;

%% Save the Structure to a MAT File
currentFolder = pwd;
cd(file_save);

% Create a filename with a timestamp (replace spaces and ':' with '-')
timestamp = replace(char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss')), {' ', ':'}, '-');
filename = ['drift_grating_', timestamp];

save([filename, '.mat'], 'Stimdata', '-v7.3');

cd(currentFolder);

disp(['Data saved in ', fullfile(file_save, [filename, '.mat'])]);
