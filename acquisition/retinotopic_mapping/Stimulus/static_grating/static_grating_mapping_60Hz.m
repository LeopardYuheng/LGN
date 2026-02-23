function [stimOnsetTimes, stimOffsetTimes, patterns, patternParams] = static_grating_mapping_60Hz(t_trial, n_trial, orientations, spatialFreqs, phases, contrast, bg, ppcm)
% STATIC_GRATING_MAPPING_60HZ - Present static grating stimuli at 60Hz with sync patches.
%
% Inputs:
%   t_trial      - Stimulus duration in seconds (e.g., 0.25).
%   n_trial      - Number of times each unique stimulus is repeated.
%   orientations - Vector of grating orientations (in degrees).
%   spatialFreqs - Vector of spatial frequencies (cycles/deg).
%   phases       - Vector of grating phases (fractions of cycle).
%   contrast     - Grating contrast (0-1).
%   bg           - Background gray level (0-255).
%   ppcm         - Pixels per cm.
%
% Outputs:
%   stimOnsetTimes  - Vector of stimulus onset times.
%   stimOffsetTimes - Vector of stimulus offset times.
%   patterns        - 3D uint8 array of the generated grating stimuli.
%   patternParams   - Struct array with fields: orientation, spatialFreq, phase.

    %% Initialization and Screen Setup
    close all;
    PsychDefaultSetup(2);
    
    Screen('Preference', 'SkipSyncTests', 1);
    Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'SuppressAllWarnings', 1);
    
%     screenNumber = max(Screen('Screens'));
    screenNumber = 1;
    [win, windowRect] = Screen('OpenWindow', screenNumber, bg);
    ifi = Screen('GetFlipInterval', win);
    [width, height] = Screen('WindowSize', win);

    %% Generate Grating Stimuli (randomized sequence with n_trial repetitions)
    % The updated create_grating_patterns returns both patterns and params.
    [patterns, patternParams] = create_grating_patterns(orientations, spatialFreqs, phases, contrast, bg, width, height, ppcm, n_trial);
    totalStim = size(patterns, 3);  % total number of non-blank presentations
    
    % Create textures from patterns
    patternTextures = nan(1, totalStim);
    for i = 1:totalStim
        patternTextures(i) = Screen('MakeTexture', win, patterns(:, :, i));
    end

    %% Define Sync Patch (Top-Left Corner)
    syncPatchSize = 150;
    syncPatchRect = [0 0 syncPatchSize syncPatchSize];

    %% Preallocate Timing Arrays
    % Insert a blank sweep every 25 stimuli.
    nBlankSweeps = floor(totalStim / 25);
    totalPresentations = totalStim + nBlankSweeps;
    stimOnsetTimes  = zeros(totalPresentations, 1);
    stimOffsetTimes = zeros(totalPresentations, 1);
    stimCount = 0;
    stimSinceBlank = 0;

    %% Determine Frame Count per Stimulus Presentation
    n_trial_frame = round(t_trial / ifi);

    %% Present an Initial Blank Screen for 3 Seconds
    Screen('FillRect', win, [bg bg bg], windowRect);
    Screen('Flip', win);
    WaitSecs(3);
    
    % Record experiment start time
    startTime = GetSecs;

    %% Stimulus Presentation Loop
    for i = 1:totalStim
        stimCount = stimCount + 1;
        stimSinceBlank = stimSinceBlank + 1;
        
        % Insert a blank sweep every 25 stimuli
        if stimSinceBlank > 25
            for frame = 1:n_trial_frame
                Screen('FillRect', win, [bg bg bg], windowRect);
                % For a blank sweep (gray screen), sync patch is always black.
                Screen('FillRect', win, [0 0 0], syncPatchRect);
                vbl = Screen('Flip', win);
                if frame == 1
                    stimOnsetTimes(stimCount) = vbl;
                    if stimCount > 1
                        stimOffsetTimes(stimCount - 1) = vbl;
                    end
                end
            end
            % Reset counter after blank sweep.
            stimSinceBlank = 1;
            stimCount = stimCount + 1;
            fprintf('Inserted blank sweep after 25 stimuli. Total presentations so far: %d out of %d.\n', stimCount, totalStim);
        end
        
        % Present the current stimulus
        for frame = 1:n_trial_frame
            Screen('DrawTexture', win, patternTextures(i), [], []);
            % During stimulus presentation, sync patch flashes:
            if frame <= n_trial_frame / 2
                Screen('FillRect', win, [255 255 255], syncPatchRect);
            else
                Screen('FillRect', win, [0 0 0], syncPatchRect);
            end
            vbl = Screen('Flip', win);
            if frame == 1
                stimOnsetTimes(stimCount) = vbl;
                if stimCount > 1
                    stimOffsetTimes(stimCount - 1) = vbl;
                end
            end
        end
        
        % Print progress after each stimulus is presented.
        fprintf('Presented stimulus %d of %d (%.1f%% complete).\n', i, totalStim, (i/totalStim)*100);
    end

    % Final flip to mark the last stimulus offset.
    Screen('FillRect', win, [bg bg bg], windowRect);
    lastVBL = Screen('Flip', win);
    stimOffsetTimes(stimCount) = lastVBL;

    %% Post-presentation Blank Screen for 5 Seconds
    Screen('FillRect', win, [bg bg bg], windowRect);
    Screen('FillRect', win, [0 0 0], syncPatchRect);  % Ensure sync patch is black during final blank.
    Screen('Flip', win);
    WaitSecs(5);

    % Record experiment end time and print total experiment time.
    endTime = GetSecs;
    totalTime = endTime - startTime;
    fprintf('Total experiment time: %.2f seconds\n', totalTime);

    %% Clean Up
    Screen('Close', patternTextures);
    Screen('CloseAll');
    Priority(0);

    disp('Static grating presentation complete!');
end