function [patterns, patternParams] = create_grating_patterns(orientations, spatialFreqs, phases, contrast, bg, dispWidth, dispHeight, ppcm, n_trial)
% viewingDist - Viewing distance in cm (NEW)

    % Set luminance levels
    gray = bg;
    amplitude = contrast * gray;
    
    % Total unique stimuli from combinations
    nOrient = length(orientations);
    nFreq = length(spatialFreqs);
    nPhase = length(phases);
    nStim = nOrient * nFreq * nPhase;
    
    % Preallocate base stimulus array (3D)
    basePatterns = zeros(dispHeight, dispWidth, nStim, 'uint8');
    
    % Preallocate base parameter list (NEW)
    baseParams = struct('orientation', [], 'spatialFreq', [], 'phase', []);
    
    % Create coordinate grid (centered)
    [x, y] = meshgrid(1:dispWidth, 1:dispHeight);
    x = x - dispWidth / 2;
    y = y - dispHeight / 2;
    
    % Pixel size in cm (FIXED)
    pixel_size_cm = 1 / ppcm;
    
    % Degrees per pixel (FIXED)
    viewingDist = 20;
    deg_per_pixel = 2 * atan(pixel_size_cm / (2 * viewingDist)) * (180 / pi);
    
    % Stimulus counter
    stimIdx = 1;
    
    % Loop through each combination
    for o = 1:nOrient
        theta = orientations(o) * pi / 180; % Convert to radians
        
        for f = 1:nFreq
            freq_cpd = spatialFreqs(f); % cycles per degree
            
            % Convert spatial frequency to cycles per pixel (FIXED)
            freq_cpp = freq_cpd * deg_per_pixel;
            
            xt = x * cos(theta) + y * sin(theta);
            
            for p = 1:nPhase
                phaseVal = phases(p); % keep as fraction of cycle
                phase = phaseVal * 2 * pi; % Convert to radians
                
                grating = gray + amplitude * cos(2 * pi * freq_cpp * xt + phase);
                
                grating = uint8(min(max(grating, 0), 255));
                
                % Store this base pattern
                basePatterns(:, :, stimIdx) = grating;
                
                % Store its parameters (NEW)
                baseParams(stimIdx).orientation = orientations(o);
                baseParams(stimIdx).spatialFreq = freq_cpd;
                baseParams(stimIdx).phase = phaseVal;
                
                stimIdx = stimIdx + 1;
            end
        end
    end
    
    % Now replicate the base stimuli n_trial times in a randomized order.
    totalStim = nStim * n_trial;
    patterns = zeros(dispHeight, dispWidth, totalStim, 'uint8');
    
    % Create a repeated index vector for the base stimuli.
    baseIndices = repmat(1:nStim, 1, n_trial);
    
    % Randomize the sequence.
    randOrder = baseIndices(randperm(totalStim));
    
    % Preallocate parameter output (NEW)
    patternParams = struct('orientation', cell(totalStim, 1), ...
                           'spatialFreq', cell(totalStim, 1), ...
                           'phase', cell(totalStim, 1));
    
    % Create the final patterns array and corresponding parameters
    for i = 1:totalStim
        idx = randOrder(i);
        patterns(:, :, i) = basePatterns(:, :, idx);
        
        % Store parameters for this pattern (NEW)
        patternParams(i).orientation = baseParams(idx).orientation;
        patternParams(i).spatialFreq = baseParams(idx).spatialFreq;
        patternParams(i).phase = baseParams(idx).phase;
    end
    
    disp(['Generated ', num2str(totalStim), ' grating stimuli (', num2str(nStim), ' unique stimuli repeated ', num2str(n_trial), ' times in random order).']);
end
