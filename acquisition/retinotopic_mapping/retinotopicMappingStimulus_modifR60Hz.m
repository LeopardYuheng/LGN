function retinotopicMappingStimulus_modifR60Hz()
% RETINOTOPICMAPPINGSTIMULUS_MODIFR60HZ
% Beta retinotopic mapping code
% Written by KS on 180123
%
% This function loads a pre-recorded stimulus movie, configures the 
% PulsePal device and Psychtoolbox window, then displays the stimulus
% in four directions with a blank screen in between.
%
% The function prompts for a folder to save the timing data.

%% Clean up and initialize
clear;
close all;

% Initialize PulsePal device
PulsePal;

% Prompt user for save folder (input as a string)
file_save = input('Give the path for the folder you want the time_stamps to be saved in: ', 's');

%% Load stimulus movie
% Change this path to point to the directory containing your movie files
movFiles = dir(fullfile('H:\SWR_task\Ret-map\Goard\Stimulus'));

% Load the fourth movie file in the directory
load(fullfile(movFiles(4).folder, movFiles(4).name));

% Set up Psychtoolbox defaults
PsychDefaultSetup(2);

% Combine the four stimulus movies into a 4D array
full_stim = uint8(cat(4, new_forward_stim, new_backward_stim, new_upward_stim, new_downward_stim));

%% Configure PulsePal parameters
ProgramPulsePalParam(1, 'CustomTrainID', 0);      % Parameterized pulse train
ProgramPulsePalParam(1, 'IsBiphasic', 0);           % Monophasic pulses
ProgramPulsePalParam(1, 'Phase1Duration', 0.01);     % 10ms pulse duration
ProgramPulsePalParam(1, 'InterPulseInterval', 0.09); % 90ms inter-pulse interval
SetContinuousLoop(1, 1);
pause(5);

%% Setup Psychtoolbox screen
screens = Screen('Screens');
screenid = 1;  % You can change this to max(screens) if needed

% Determine the length of the movie (number of frames)
mov_length = size(new_forward_stim, 3);

%% Stimulus parameters
repeats = 25;             % Number of complete stimulus repeats
offTime = 6;             % Duration of blank (gray) screen between directions (sec)
refreshRate = Screen('NominalFrameRate', screenid);
background = 0.4980;          % Background color (0 for black), 0,4980 for gray
waitframes = 1;          % Number of frames to wait (controls effective refresh rate)
onTime = round(mov_length / refreshRate); % Duration of movie presentation

% Calculate overall durations
stim_dur = onTime + offTime;      % Duration for one direction
repDur = stim_dur * 4;            % Duration for all four directions
totalDur = repDur * repeats;
disp(['Stimulus duration: ' num2str(totalDur) ' sec']);

%% Psychtoolbox window configuration
Screen('Preference', 'SkipSyncTests', 1);
Screen('Preference', 'VisualDebugLevel', 0);
Screen('Preference', 'SuppressAllWarnings', 1);

% Open Psychtoolbox window
win = Screen('OpenWindow', screenid, background * 255);
ifi = Screen('GetFlipInterval', win);
Screen('Flip', win);
priorityLevel = MaxPriority(win);
Priority(priorityLevel);

% (Optional) Setup patch area (not used later but available for customization)
% Define patch size and position (bottom-left corner)
% Get the screen dimensions
[screenXpixels, screenYpixels] = Screen('WindowSize', win);
patchWidth = 100;
patchHeight = 100;

% To display the patch in the TOP-LEFT corner, set its rectangle as:
patchRect = [0, 0, patchWidth, patchHeight];


% Initialize timing arrays for stimulus events
tstart = GetSecs;
blank_on = zeros(repeats, 4);
blank_end = zeros(repeats, 4);
mov_on   = zeros(repeats, 4);
mov_end  = zeros(repeats, 4);

%% Display stimulus
% Displays the pre-recorded movies, one in each direction
[width, height] = Screen('WindowSize', screenid);
for rep = 1:repeats
    for drxn = 1:4
        % Record movie onset time
        mov_on(rep,drxn) = GetSecs-tstart;
        tclose = (rep-1)*repDur + (drxn-1)*stim_dur + onTime;
        frameIdx = 1;
        
        while (GetSecs-tstart) < tclose % Play sign mapping movie
            % Create texture for current frame
            movie = Screen('MakeTexture', win, full_stim(:,:,frameIdx,drxn));
            % Draw the video frame covering the whole screen
            Screen('DrawTexture', win, movie, [], [0 0 width height]);
            
            % Draw a white patch in the top left corner
            Screen('FillRect', win, 255, patchRect);
            
            % Flip the screen to display the frame and patch
            Screen('Flip', win, ifi);
            frameIdx = min(frameIdx+1, mov_length);
        end
        
        mov_end(rep,drxn) = GetSecs-tstart;
        
        % Draw a blank screen (see modified DrawBlank function below)
        blank_on(rep,drxn) = GetSecs-tstart;
        tclose = (rep-1)*repDur + (drxn)*stim_dur;
        DrawBlank(win, background, tclose, tstart);
        blank_end(rep,drxn) = GetSecs-tstart;
    end
end

tfinal = GetSecs - tstart;

%% Clean up
Screen('CloseAll');
Priority(0);

%% Save stimulus timing data
Stimdata.blank_on = blank_on;
Stimdata.blank_end = blank_end;
Stimdata.mov_on = mov_on;
Stimdata.mov_end = mov_end;
Stimdata.off_time = offTime;
Stimdata.repeats = repeats;
Stimdata.on_time = onTime;

% Change directory to the user-specified save folder and save the file
cd(file_save);
save(['retinotopicMapping_' replace(char(datetime), {':', ' '}, '-')], 'Stimdata');
pause(5);

% End PulsePal session
AbortPulsePal;
EndPulsePal();

end
