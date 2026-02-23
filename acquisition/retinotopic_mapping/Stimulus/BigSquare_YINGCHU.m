sca;
close all;
clear;

PulsePal

file_save = input('Give the path for the folder you want the time_stamps to be saved in', 's');
% Here we call some default settings for setting up Psychtoolbox
PsychDefaultSetup(2);
% PulsePal
ProgramPulsePalParam(1, 'CustomTrainID', 0); % Sets output channel 1 to use its parameterized pulse train
ProgramPulsePalParam(1, 'IsBiphasic', 0); % Sets output channel 1 to use monophasic pulses
ProgramPulsePalParam(1, 'Phase1Duration', 0.01); % Sets output channel 1 to produce 10ms pulses
ProgramPulsePalParam(1, 'InterPulseInterval', 0.04); % Sets output channel 1 to use a 90ms pulse interval
SetContinuousLoop(1,1);
pause(5)
% Get the screen numbers
screens = Screen('Screens');

% Draw to the external screen if avaliable
screenNumber = 1;

% Define black and white
white = WhiteIndex(screenNumber);
black = BlackIndex(screenNumber);

% Open an on screen window
[window, windowRect] = PsychImaging('OpenWindow', screenNumber, black);

% Enable alpha blending for anti-aliasing
Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

% Get the size of the on screen window
[screenXpixels, screenYpixels] = Screen('WindowSize', window);

% Query the frame duration
ifi = Screen('GetFlipInterval', window);

% Get the centre coordinate of the window
[xCenter, yCenter] = RectCenter(windowRect);

% Make a base Rect of 200 by 200 pixels
baseRect = [0 0 screenXpixels screenYpixels];

% Set the color of the rect to blue
rectColor = [1 1 1];

% Our square will oscilate with a sine wave function to the left and right
% of the screen. These are the parameters for the sine wave
% See: http://en.wikipedia.org/wiki/Sine_wave

background = 0;
trial_number = 5;
stimli_iteration = 1;%*8;
off_time = 4;
% Sync us and get a time stamp
vbl = Screen('Flip', window);
waitframes = 1;
time=0;
% Maximum priority level
topPriorityLevel = MaxPriority(window); 
Priority(topPriorityLevel);

centeredRect = CenterRectOnPointd(baseRect, xCenter, yCenter);
for i = 1:trial_number
    repeats = stimli_iteration;
    blank_on=zeros(repeats,1);
    blank_end=zeros(repeats,1);
    mov_on=zeros(repeats,1);
    move_end=zeros(repeats,1);
    tstart = GetSecs;
    offTime=0.5;%0125;%0.1 
    onTime = 0.5;%0125;%0.1
    repDur = onTime + offTime;
    for rep = 1:repeats
            % Draw a blank screen
            blank_on(rep) = GetSecs-tstart;
            tclose = (rep-1)*repDur+offTime;
            DrawBlank(window,background,tclose,tstart)
            blank_end(rep) = GetSecs-tstart;

            %display movies
            mov_on(rep) = GetSecs-tstart;
            tclose = rep*repDur;
            frameIdx = 1; %default = 100
            while (GetSecs-tstart)<tclose % Play sign mapping movie

                % Draw the rect to the screen
                Screen('FillRect', window, rectColor, centeredRect);
                % Flip to the screen
                vbl  = Screen('Flip', window, vbl + (waitframes - 0.5) * ifi);
                % Increment the time
                time = time + ifi;
            end
            mov_end(rep) = GetSecs-tstart;
    end
    DrawBlank(window,0,off_time,tstart);
    pause(off_time);
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
save(replace(char(datetime),{':',' '},'-'),'Stimdata')
% 
AbortPulsePal
EndPulsePal()