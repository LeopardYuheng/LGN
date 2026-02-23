addpath('D:\Xiaorong\SWR_task\Ret-map\Goard\Stimulus')

%%
n_col = 14;
n_row = 8;
bg_black_dot = 255;
point_black_dot = 0;
bg_white_dot = 0;
point_white_dot = 255;
n_trial = 30;
t_trial = 0.2; %s

file_save = input('Give the path for the folder you want the time_stamps to be saved in: ', 's');

[stimOnsetTimes_black_dot, stimOffsetTimes_black_dot] = rf_mapping_60Hz(n_col, n_row, bg_black_dot, point_black_dot, t_trial, n_trial);
[stimOnsetTimes_white_dot, stimOffsetTimes_white_dot] = rf_mapping_60Hz(n_col, n_row, bg_white_dot, point_white_dot, t_trial, n_trial);

Stimdata.black_on = stimOnsetTimes_black_dot;
Stimdata.black_off = stimOffsetTimes_black_dot;
Stimdata.white_on = stimOnsetTimes_white_dot;
Stimdata.white_off = stimOffsetTimes_white_dot;
Stimdata.n_col = n_col;
Stimdata.n_row = n_row;
Stimdata.n_trial = n_trial;
Stimdata.t_trial = t_trial;

cd(file_save);
filename = ['receptive_field_', replace(char(datetime('now')), {':', ' '}, '-')];
save([filename, '.mat'], 'Stimdata', '-v7.3');

%% Define Grating and Presentation Parameters
% These parameters match the figures you sent.

orientations = 0:30:150;                   % 6 orientations (in degrees)
spatialFreqs = [0.02, 0.04, 0.08, 0.16, 0.32]; % 5 spatial frequencies (cycles/degree)
phases = [0, 0.25, 0.5, 0.75];             % 4 phases (fractions of a cycle)
contrast = 0.8;                            % 80% contrast
bg = 127;                                  % Background gray (0-255)
ppcm = 2560 / 70.7;                        % Pixels per cm (adjust to your display)

t_trial = 0.25; % Duration for each stimulus in seconds
n_trial = 50;   % Number of repetitions
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
Stimdata.patterns         = patterns;       % Grating patterns (3D uint8 array)
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