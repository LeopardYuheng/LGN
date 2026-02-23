function [stimOnsetTimes, stimOffsetTimes] = rf_mapping_60Hz(n_col, n_row, bg, point, t_trial, n_trial)
    % rf_mapping_60Hz - Present RF mapping stimuli at 60Hz with sync patches.
    %
    % This function generates RF mapping stimuli using a full-HD grid
    % pattern (via create_rf_pattern) and presents each pattern for t_trial
    % seconds (displayed for multiple frames based on the screen refresh rate).
    % The entire set of stimuli is repeated for n_trial repetitions.
    % A top-left sync patch flashes white during the first half of each stimulus,
    % while the bottom-left patch has been removed.
    % Stimulus onset and offset times are logged using GetSecs timestamps.
    %
    % Inputs:
    %   n_col   - Number of columns in the grid.
    %   n_row   - Number of rows in the grid.
    %   bg      - Background color (normalized, e.g., 0.4980 for gray).
    %   point   - Dot color (e.g., 0 for black).
    %   t_trial - Duration for each stimulus presentation in seconds.
    %   n_trial - Number of repetitions for the entire stimulus set.
    %
    % Outputs:
    %   stimOnsetTimes  - A vector of onset timestamps (one per stimulus presentation).
    %   stimOffsetTimes - A vector of offset timestamps (one per stimulus presentation).

    %% Initialization and Screen Setup
    close all;
    PsychDefaultSetup(2);
    
    % Compute background color in 0-255 range.
    background = 0.4980; 
    bgColor = round(0.4980 * 255);
    
    % Set screen preferences.
    Screen('Preference', 'SkipSyncTests', 1);
    Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'SuppressAllWarnings', 1);
    
    % Open the Psychtoolbox window.
    screenNumber = max(Screen('Screens'));
    [win, windowRect] = Screen('OpenWindow', screenNumber, bgColor);
    ifi = Screen('GetFlipInterval', win);
    [width, height] = Screen('WindowSize', win);
    
    %% Generate Stimulus Patterns and Create Textures
    % patterns: 3D uint8 array [height x width x numPatterns]
    patterns = create_rf_pattern(n_col, n_row, bg, point, width, height);
    numPatterns = size(patterns, 3);
    
    % Pre-create textures for efficient drawing.
    patternTextures = nan(1, numPatterns);
    for i = 1:numPatterns
        patternTextures(i) = Screen('MakeTexture', win, patterns(:,:,i));
    end
    
    %% Define Sync Patch (Top-Left Corner)
    syncPatchSize = 100;
    syncPatchRect = [0 0 syncPatchSize syncPatchSize];
    
    %% Preallocate Timing Arrays
    totalPresentations = n_trial * numPatterns;
    stimOnsetTimes  = zeros(totalPresentations, 1);
    stimOffsetTimes = zeros(totalPresentations, 1);
    stimCount = 0;  % Counter to index each stimulus presentation.
    
    % Calculate number of frames per stimulus presentation.
    n_trial_frame = round(t_trial / ifi);

    %% Show Blank Gray Screen for 5 Seconds
    Screen('FillRect', win, [bgColor bgColor bgColor], windowRect);
    Screen('Flip', win);
    WaitSecs(3);
    
    % Initial flip (clear the screen) to start timing.
    Screen('Flip', win);
    
    %% Stimulus Presentation Loop
    for trial = 1:n_trial
        for p = 1:numPatterns
            stimCount = stimCount + 1;  % Increment presentation count
            for frame = 1:n_trial_frame
                % Draw the current stimulus texture full-screen.
                Screen('DrawTexture', win, patternTextures(p), [], []);
                
                % Top-left sync patch: flash white for first half, then black.
                if frame <= n_trial_frame / 2
                    Screen('FillRect', win, [255 255 255], syncPatchRect);
                else
                    Screen('FillRect', win, [0 0 0], syncPatchRect);
                end
                
                % Flip to present the frame and record the timestamp.
                vbl = Screen('Flip', win);
                
                % Log onset time at the first frame of the stimulus.
                if frame == 1
                    stimOnsetTimes(stimCount) = vbl;
                    % If this is not the first presentation overall, record the previous offset.
                    if stimCount > 1
                        stimOffsetTimes(stimCount - 1) = vbl;
                    end
                end
            end
        end
    end
    
    % Final flip to a blank screen (black) to mark the last stimulus offset.
    Screen('FillRect', win, 0, windowRect);
    lastVBL = Screen('Flip', win);
    stimOffsetTimes(stimCount) = lastVBL;

    %% Show Blank Gray Screen for 5 Seconds
    Screen('FillRect', win, [bgColor bgColor bgColor], windowRect);
    Screen('Flip', win);
    WaitSecs(5);

    %% Clean Up
    Screen('Close', patternTextures);
    Screen('CloseAll');
    Priority(0);
end
