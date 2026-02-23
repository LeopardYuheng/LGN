function patterns = create_grating_patterns(orientations, spatialFreqs, phases, contrast, bg, dispWidth, dispHeight, ppcm, n_trial)
% CREATE_GRATING_PATTERNS generates a 3D uint8 array of static grating stimuli 
% in a randomized sequence.
%
% Inputs:
%   orientations - Vector of orientations in degrees (e.g., [0, 30, 60, ...]).
%   spatialFreqs - Vector of spatial frequencies in cycles/degree (e.g., [0.02, ...]).
%   phases       - Vector of phases as fractions of 1 cycle (e.g., [0, 0.25, 0.5, 0.75]).
%   contrast     - Grating contrast from 0 to 1 (e.g., 0.8).
%   bg           - Background gray level (0-255), typically 127.
%   dispWidth    - Display width in pixels.
%   dispHeight   - Display height in pixels.
%   ppcm         - Pixels per centimeter (for spatial frequency conversion).
%   n_trial      - Number of times each unique stimulus is repeated.
%
% Output:
%   patterns     - 3D uint8 array [dispHeight, dispWidth, nStim*n_trial], where the base
%                  stimulus set (nStim = length(orientations)*length(spatialFreqs)*length(phases))
%                  is repeated n_trial times in a randomized order.

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
    
    % Create coordinate grid (centered)
    [x, y] = meshgrid(1:dispWidth, 1:dispHeight);
    x = x - dispWidth / 2;
    y = y - dispHeight / 2;
    
    % Stimulus counter
    stimIdx = 1;
    
    % Loop over all combinations of orientation, frequency, and phase.
    for o = 1:nOrient
        theta = orientations(o) * pi / 180; % Convert to radians
        
        for f = 1:nFreq
            freq_cpd = spatialFreqs(f); % cycles per degree
            
            % Convert spatial frequency to cycles per pixel.
            % Assumes viewing distance of 57 cm (1 deg ≈ 1 cm).
            freq_cpp = freq_cpd / (ppcm / 57); % cycles/pixel
            
            % Spatial component of the grating
            xt = x * cos(theta) + y * sin(theta);
            
            for p = 1:nPhase
                phase = phases(p) * 2 * pi; % Convert phase to radians
                
                % Grating equation
                grating = gray + amplitude * cos(2 * pi * freq_cpp * xt + phase);
                
                % Clip to [0, 255] and convert to uint8
                grating = uint8(min(max(grating, 0), 255));
                
                % Store this base pattern
                basePatterns(:, :, stimIdx) = grating;
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
    
    % Create the final patterns array using the randomized indices.
    for i = 1:totalStim
        patterns(:, :, i) = basePatterns(:, :, randOrder(i));
    end
    
    disp(['Generated ', num2str(totalStim), ' grating stimuli (', num2str(nStim), ' unique stimuli repeated ', num2str(n_trial), ' times in random order).']);
end

