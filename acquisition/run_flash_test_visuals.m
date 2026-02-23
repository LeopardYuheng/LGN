sca;
close all;
clear;

PulsePal

file_save = input('Give the path for the folder you want the time_stamps to be saved in: ', 's');
% Here we call some default settings for setting up Psychtoolbox
PsychDefaultSetup(2);
% PulsePal
ProgramPulsePalParam(1, 'CustomTrainID', 0); % Sets output channel 1 to use its parameterized pulse train
ProgramPulsePalParam(1, 'IsBiphasic', 0); % Sets output channel 1 to use monophasic pulses
ProgramPulsePalParam(1, 'Phase1Duration', 0.01); % Sets output channel 1 to produce 10ms pulses
ProgramPulsePalParam(1, 'InterPulseInterval', 0.09); % Sets output channel 1 to use a 90ms pulse interval
SetContinuousLoop(1,1);
pause(5)

% Set up Psychtoolbox defaults
PsychDefaultSetup(2);
Screen('Preference', 'SkipSyncTests', 1);
Screen('Preference', 'VisualDebugLevel', 0);
Screen('Preference', 'SuppressAllWarnings', 1);

% Get the screen numbers
screens = Screen('Screens');

% Draw to the external screen if avaliable
screenid = 1;
background = 0.4980; 
win = Screen('OpenWindow', screenid, 0);
ifi = Screen('GetFlipInterval', win);
Screen('Flip', win);
priorityLevel = MaxPriority(win);
Priority(priorityLevel);

% Get the size of the on screen window
[screenXpixels, screenYpixels] = Screen('WindowSize', win);
patchRect = [0, 0, screenXpixels, screenYpixels];

% Set the color of the rect to blue
rectColor = [1 1 1];

% Our square will oscilate with a sine wave function to the left and right
% of the screen. These are the parameters for the sine wave
% See: http://en.wikipedia.org/wiki/Sine_wave


% Sync us and get a time stamp
vbl = Screen('Flip', win);
waitframes = 1;
time=0;
% Maximum priority level

repeats = 60;
blank_on=zeros(repeats,1);
blank_end=zeros(repeats,1);
mov_on=zeros(repeats,1);
move_end=zeros(repeats,1);
tstart = GetSecs;
offTime=4.5;
onTime = 0.5;
repDur = onTime + offTime;

for rep = 1:repeats
        % Draw a blank screen
        blank_on(rep) = GetSecs-tstart;
        tclose = (rep-1)*repDur+offTime;
        DrawBlank(win,0,tclose,tstart)
        blank_end(rep) = GetSecs-tstart;
        
        %display movies
        mov_on(rep) = GetSecs-tstart;
        tclose = rep*repDur;
        frameIdx = 1; %default = 100
        while (GetSecs-tstart)<tclose % Play sign mapping movie
            
            % Draw the rect to the screen
            Screen('FillRect', win, 255, patchRect);
            % Flip to the screen
            vbl  = Screen('Flip', win, vbl + (waitframes - 0.5) * ifi);
            % Increment the time
            time = time + ifi;
        end
        mov_end(rep) = GetSecs-tstart;
end
tfinal = (GetSecs-tstart);

% Clear the screen
Screen('CloseAll')
Priority(0);

%% Save stimulus data file

Stimdata.blank_on = blank_on;
Stimdata.blank_end = blank_end;
Stimdata.mov_on = mov_on;
Stimdata.mov_end = mov_end;
Stimdata.off_time = offTime;
Stimdata.repeats = repeats;
Stimdata.on_time = onTime;
cd(file_save);
save(['FlashTest_' replace(char(datetime), {':', ' '}, '-')], 'Stimdata');

AbortPulsePal
EndPulsePal()