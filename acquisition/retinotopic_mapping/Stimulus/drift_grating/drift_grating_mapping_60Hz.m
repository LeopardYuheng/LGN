function [stimOnsetTimes, stimOffsetTimes, moviesBase, movieParamsTrial, trialOrder] = drift_grating_mapping_60Hz(movieDuration, pauseDuration, n_trial, orientations, spatialFreqs, temporalFreqs, phases, contrast, bg, ppcm, frameRate)
% DRIFT_GRATING_MAPPING_60HZ - Present drifting grating movies at 60Hz with sync patches.
%
% Inputs:
%   movieDuration  - Duration of each drifting movie in seconds (e.g., 2).
%   pauseDuration  - Duration of the pause (gray screen) after each movie (e.g., 1).
%   n_trial        - Number of times each unique stimulus is repeated.
%   orientations   - Vector of grating orientations (in degrees).
%   spatialFreqs   - Vector of spatial frequencies (cycles/deg).
%   temporalFreqs  - Vector of temporal frequencies (Hz) for drifting.
%   phases         - Vector of grating phases (fractions of cycle, 0 to 1).
%   contrast       - Grating contrast (0–1).
%   bg             - Background gray level (0–255).
%   ppcm           - Pixels per centimeter.
%   frameRate      - Display refresh rate (e.g., 60).
%
% Outputs:
%   stimOnsetTimes  - Vector of stimulus onset times.
%   stimOffsetTimes - Vector of stimulus offset times.
%   moviesBase      - 4D uint8 array of base drifting grating movies
%                     (height x width x nFrames x nUniqueStim).
%   movieParamsTrial- Struct array (length = total trials) with fields: orientation, spatialFreq, temporalFreq, phase.
%   trialOrder      - 1 x totalTrials vector of indices indicating the presentation order.
%
% This function first generates one copy of each unique drifting grating movie 
% (using create_drift_grating_patterns with n_trial=1) and then creates a randomized 
% trial order that repeats these base movies n_trial times. Each movie is played, 
% followed by a pause (blank screen), and a sync patch in the top-left corner flashes 
% white during the movie presentation.

    %% Initialization and Screen Setup
    close all;
    PsychDefaultSetup(2);
    
    Screen('Preference', 'SkipSyncTests', 1);
    Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'SuppressAllWarnings', 1);
    
    screenNumber = max(Screen('Screens'));
    [win, windowRect] = Screen('OpenWindow', screenNumber, bg);
    ifi = Screen('GetFlipInterval', win);
    [width, height] = Screen('WindowSize', win);

    %% Generate Base Drifting Grating Movies (Unique Stimuli Only)
    % Generate the unique drifting grating movies by setting n_trial=1.
    [moviesBase, movieParamsBase] = create_drift_grating_patterns(orientations, spatialFreqs, temporalFreqs, phases, contrast, bg, width, height, ppcm, 1, movieDuration, frameRate);
    nUniqueStim = size(moviesBase, 4);
    totalTrials = nUniqueStim * n_trial;
    
    % Create a trial order: replicate base indices n_trial times and then shuffle.
    baseIndices = repmat(1:nUniqueStim, 1, n_trial);
    trialOrder = baseIndices(randperm(totalTrials));
    
    % Create a trial-specific parameters array by indexing into the base parameters.
    movieParamsTrial = struct('orientation', cell(totalTrials, 1), ...
                              'spatialFreq', cell(totalTrials, 1), ...
                              'temporalFreq', cell(totalTrials, 1), ...
                              'phase', cell(totalTrials, 1));
    for i = 1:totalTrials
        movieParamsTrial(i) = movieParamsBase(trialOrder(i));
    end

    %% Define Sync Patch (Top-Left Corner)
    syncPatchSize = 150;
    syncPatchRect = [0 0 syncPatchSize syncPatchSize];

    %% Preallocate Timing Arrays for All Trials
    stimOnsetTimes  = zeros(totalTrials, 1);
    stimOffsetTimes = zeros(totalTrials, 1);
    
    %% Present an Initial Blank Screen for 3 Seconds
    Screen('FillRect', win, [bg bg bg], windowRect);
    Screen('Flip', win);
    WaitSecs(3);
    
    % Record experiment start time.
    startTime = GetSecs;
    
    % Determine the number of frames for the movie and for the pause period.
    nMovieFrames = round(movieDuration * frameRate);
    nPauseFrames = round(pauseDuration / ifi);

    %% Stimulus Presentation Loop
    for i = 1:totalTrials
        % Get the index of the base movie to present this trial.
        baseIdx = trialOrder(i);
        
        % Present the drifting movie.
        for frame = 1:nMovieFrames
            % Create texture from the current frame of the selected base movie.
            currentFrame = moviesBase(:, :, frame, baseIdx);
            texture = Screen('MakeTexture', win, currentFrame);
            
            % Draw the texture to fill the entire window.
            Screen('DrawTexture', win, texture, [], []);
            
            % Draw sync patch: flash white.
            Screen('FillRect', win, [255 255 255], syncPatchRect);
            
            % Flip to screen.
            vbl = Screen('Flip', win);
            if frame == 1
                stimOnsetTimes(i) = vbl;
                if i > 1
                    stimOffsetTimes(i - 1) = vbl;
                end
            end
            
            % Clean up texture to free memory.
            Screen('Close', texture);
        end
        
        % Pause period: present a blank (gray) screen for pauseDuration seconds.
        for frame = 1:nPauseFrames
            Screen('FillRect', win, [bg bg bg], windowRect);
            % Keep the sync patch black during the pause.
            Screen('FillRect', win, [0 0 0], syncPatchRect);
            Screen('Flip', win);
        end
        
        % Print progress after each trial.
        fprintf('Presented trial %d of %d (%.1f%% complete).\n', i, totalTrials, (i/totalTrials)*100);
    end

    % Final flip to mark the last stimulus offset.
    Screen('FillRect', win, [bg bg bg], windowRect);
    lastVBL = Screen('Flip', win);
    stimOffsetTimes(totalTrials) = lastVBL;

    %% Post-presentation Blank Screen for 5 Seconds
    Screen('FillRect', win, [bg bg bg], windowRect);
    Screen('FillRect', win, [0 0 0], syncPatchRect);  % Ensure sync patch is black.
    Screen('Flip', win);
    WaitSecs(5);

    % Record experiment end time and print total experiment time.
    endTime = GetSecs;
    totalTime = endTime - startTime;
    fprintf('Total experiment time: %.2f seconds\n', totalTime);

    %% Clean Up
    Screen('CloseAll');
    Priority(0);

    disp('Drifting grating presentation complete!');
end

