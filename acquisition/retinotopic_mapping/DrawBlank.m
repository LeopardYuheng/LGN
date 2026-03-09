function DrawBlank(win, background, tclose, tstart)
% Ensure OpenGL and GLSL are available
AssertOpenGL;
AssertGLSL;

% Get screen dimensions
[~, screenYpixels] = Screen('WindowSize', win);
patchWidth = 100; 
patchHeight = 100; 
patchRect = [0, 0, patchWidth, patchHeight];

% Retrieve the frame interval for timing
ifi = Screen('GetFlipInterval', win);

% Fill the entire screen with the background color
Screen('FillRect', win, background * 255);

% Draw the black patch in the bottom-left corner
Screen('FillRect', win, 0, patchRect);

% Flip the screen to display the blank screen with the patch
vbl = Screen('Flip', win);

% Continue displaying until tclose is reached
while (GetSecs - tstart) < tclose  
    % Fill the screen with the background color
    Screen('FillRect', win, background * 255);
    % Draw the black patch again
    Screen('FillRect', win, 0, patchRect);
    
    % Flip at the next vertical retrace
    vbl = Screen('Flip', win, vbl + 0.5 * ifi);
end
end

