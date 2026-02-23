function [ ] = retinotopicMappingStimulus_modifR(  )
% Beta retinotopic mapping code
%   Written KS 180123

clear
close all

file_save = input('Give the path for the folder you want the time_stamps to be saved in');
%% Preparing movie database, change this path to point to the directory containing '4direction_stim.mat'
movFiles = dir(fullfile('C:\Users\LASX-Admin\Documents\SWR_task\Ret-map\Goard\Stimulus'));
% Load the movie
load([movFiles(3).folder '\' movFiles(5).name]);
% load('4directions_stim_new_sync.mat')
% Concatenating into one big movie

full_stim = uint8(cat(4,new_forward_stim,new_backward_stim,new_upward_stim,new_downward_stim));

%prepare screen function for psychtoolbox
screens=Screen('Screens');
% screenid=max(screens);
screenid=1;
mov_length = size(new_forward_stim,3); % each presentation of the stimulus will be this length
 

%% Stimulus parameters (change these to your liking)
repeats =1; %repeats of total movie list(default = 30)
offTime = 2; %gray screen in between each direction
refreshRate = Screen('NominalFrameRate', screenid);

background = 0;
waitframes = 2; %reduce frame rate to 30Hz (wait 2 frames in between each retrace)
onTime = round(mov_length/(refreshRate/2)); %movie length (default = 30)
% Customization

%Length of stimulus set
stim_dur = onTime + offTime;
repDur = stim_dur*4; % four directions
totalDur = repDur*repeats;
disp(['Stimulus duration: ' num2str(totalDur) ' sec'])

%% Psych toolbox set up
Screen('Preference','SkipSyncTests',1);

Screen('Preference','VisualDebugLevel',0);
Screen('Preference','SuppressAllWarnings',1);

% patch size & location
patchArea = [0 0 1 1];
[width,height] = Screen('WindowSize',screenid);
patchArea([1 3]) = patchArea([1 3])*width;  % scale area of patch (width)
patchArea([2 4]) = patchArea([2 4])*height;  % scale area of patch (height)


%  window
win = Screen('OpenWindow', screenid, background*255);
ifi = Screen('GetFlipInterval', win);
vbl = Screen('Flip', win);
priorityLevel = MaxPriority(win);
Priority(priorityLevel);

% Make a rectangle for the synchronization signal
[screenXpixels, screenYpixels] = Screen('WindowSize', win);
xCenter=screenXpixels/2;
SyncRect = [0 0 600 600];
SyncRect = CenterRectOnPointd(SyncRect, xCenter, screenYpixels-600); %Place the screen in the middle bottom of the screen
rectColor = [1 1 1];


tstart = GetSecs;
blank_on=zeros(repeats,4);
blank_end=zeros(repeats,4);
mov_on=zeros(repeats,4);
move_end=zeros(repeats,4);
%% Display stimulus
% Displays the pre-recorded movies, one in each direction
for rep = 1:repeats

    for drxn = 1:4
        % Draw a blank screen
        blank_on(rep,drxn) = GetSecs-tstart
        tclose = (rep-1)*repDur+(drxn-1)*stim_dur+offTime;
        DrawBlank(win,background,tclose,tstart)
        blank_end(rep,drxn) = GetSecs-tstart
        
        %display movies
        mov_on(rep,drxn) = GetSecs-tstart
        tclose = (rep-1)*repDur+(drxn)*stim_dur;
        frameIdx = 1; %default = 100
        while (GetSecs-tstart)<tclose % Play sign mapping movie
            tic
            % disp(num2str(frameIdx))
            [movie] = Screen('MakeTexture',win,full_stim(:,:,frameIdx,drxn));
            Screen('DrawTexture',win,movie,[],[0 0 width height]);
            [rate] = Screen('FrameRate',win, [2], [30]);
            Screen('Flip',win, (ifi*.2));
            vbl = Screen('Flip',win,vbl+(waitframes-0.5)*ifi); % correct timing to 30hz
            frameIdx = min(frameIdx+1,mov_length);
        end
        mov_end(rep,drxn) = GetSecs-tstart
    end
end
tfinal = (GetSecs-tstart)

%% Clean up

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

