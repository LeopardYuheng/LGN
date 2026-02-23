function patterns = create_rf_pattern(n_col, n_row, bg, point, dispWidth, dispHeight)
% CREATE_RF_PATTERN generates a 3D uint8 array of full-HD stimuli.
%
% Each stimulus is a full-HD image (dispWidth x dispHeight) with a background
% color 'bg' and one grid cell set to the dot color 'point'. The grid is defined
% by n_col columns and n_row rows, and each stimulus has its dot placed in a
% unique, randomly ordered cell.
%
% Inputs:
%   n_col     - Number of columns in the grid.
%   n_row     - Number of rows in the grid.
%   bg        - Background color (e.g., 255 for white).
%   point     - Dot color (e.g., 0 for black).
%   dispWidth - Display width in pixels (e.g., 1920).
%   dispHeight- Display height in pixels (e.g., 1080).
%
% Output:
%   patterns  - 3D uint8 array of size [dispHeight, dispWidth, n_col*n_row].
%
% Example:
%   patterns = create_rf_pattern(8, 5, 255, 0, 1920, 1080);

    % Fix the random seed for reproducibility
    rng(1234);

    % Total number of stimuli (one per grid cell)
    nStim = n_col * n_row;
    
    % Generate a random permutation of grid positions (1 to nStim)
    order = randperm(nStim);
    
    % Preallocate the 3D array for stimulus images (uint8)
    patterns = zeros(dispHeight, dispWidth, nStim, 'uint8');
    
    % Determine the size of each grid cell (using floor for integer dimensions)
    cellWidth = floor(dispWidth / n_col);
    cellHeight = floor(dispHeight / n_row);
    
    % Loop to create each stimulus image
    for i = 1:nStim
        % Start with a full-HD white background (or specified bg color)
        img = uint8(ones(dispHeight, dispWidth) * bg);
        
        % Determine which grid cell will contain the dot (random order)
        pos = order(i);
        row = ceil(pos / n_col);
        col = mod(pos - 1, n_col) + 1;
        
        % Compute pixel coordinates for this grid cell
        x_start = (col - 1) * cellWidth + 1;
        if col == n_col
            x_end = dispWidth;
        else
            x_end = col * cellWidth;
        end
        
        y_start = (row - 1) * cellHeight + 1;
        if row == n_row
            y_end = dispHeight;
        else
            y_end = row * cellHeight;
        end
        
        % Set the entire cell to the dot color
        img(y_start:y_end, x_start:x_end) = point;
        
        % Store the image in the output 3D array
        patterns(:, :, i) = img;
    end
end

