close all;
% addpath(genpath('G:\xiaorong\Data_processing_Xiaorong'))
addpath(genpath('Z:\xl_cl\Retino\Data_processing_Xiaorong'))


% Load data from Intan RHD files
DIR = dir('*.rhd');

stimDI   = 5;   % <-- set to the new digital input line for stimulus/photodiode
camDI    = 2;   % <-- set to the digital input line for camera TTL (if unchanged)

recFile = cell(1,numel(DIR));
tIntan = cell(1,numel(DIR));
for i = 1:numel(DIR)
    read_Intan_RHD2000_fileV3(DIR(i).name,[]);
    recFile{1,i} = board_dig_in_data;
    tIntan{1,i} = t_dig;
end
save('DIN.mat', 'recFile', '-v7.3');
Fs = frequency_parameters.amplifier_sample_rate;
recFile = cat(2,recFile{:});
t_rising_edge_diode = find(diff(recFile(stimDI,:))>0);
inter_pulse_interval_diode = diff(t_rising_edge_diode);

%% Find all rising points where the screen starts to flash

stimDI = 5; % <-- set to your new stim DI line
k = stimDI;
figure;
plot(recFile(k,:));
xlabel('Sample index');
ylabel('Digital level');
title(sprintf('Digital Input Channel %d', k));
ylim([-0.2 1.2]);
grid on;



% pd_t = t_rising_edge_diode(1:end-1);
% pd = -inter_pulse_interval_diode;
% 
% downsample_factor = 0;
% pd_t_downsampled = pd_t(1:downsample_factor:end);
% pd_downsampled = pd(1:downsample_factor:end);
% 
% diff_pd_downsampled = diff(pd_downsampled);
% threshold = 60;
% pd_rising_edges_downsampled = find(diff_pd_downsampled > threshold);
% % pd_rising_edges_downsampled = pd_rising_edges_downsampled(2:end);
% 
% % Plot signals for visualization and validation
% figure;
% subplot(2, 1, 1);
% plot(pd_t, pd, 'b', 'LineWidth', 1);
% title('Original Signal');
% xlabel('Time');
% ylabel('Amplitude');
% grid on;
% 
% subplot(2, 1, 2);
% plot(pd_t_downsampled, pd_downsampled, 'g', 'LineWidth', 1.5);
% hold on;
% plot(pd_t_downsampled(pd_rising_edges_downsampled), pd_downsampled(pd_rising_edges_downsampled), 'ro', ...
%     'MarkerSize', 8, 'MarkerFaceColor', 'r');
% title('Downsampled Signal with Rising Edge Detection');
% xlabel('Time');
% ylabel('Amplitude');
% legend('Downsampled Signal', 'Rising Edge');
% grid on;
% hold off;
% 
% pd_rising_ts = pd_t_downsampled(pd_rising_edges_downsampled);

%% Validate that images number matches rising edges number
camera_diff = diff(recFile(camDI,:));
camera_rising = find(camera_diff>0);
num_rising_edges = length(camera_rising);
disp(['Number of rising edges: ', num2str(num_rising_edges)]);

% Open image folder and count the image numbers
folder_path = uigetdir(pwd, 'Select corresponding Img folder');
analysisFolder = fullfile(folder_path, 'analysis');
if ~exist(analysisFolder, 'dir')
    mkdir(analysisFolder);
end

% Get image files and sort them properly
image_files = dir(fullfile(folder_path, '*.tif'));
nFiles = numel(image_files);
fileNumbers = zeros(nFiles, 1);

for i = 1:nFiles
    % Extract the number between '_' and '.tif'
    tokens = regexp(image_files(i).name, '_([0-9]+)\.tif$', 'tokens');
    if ~isempty(tokens)
        fileNumbers(i) = str2double(tokens{1}{1});
    else
        error('Filename "%s" does not match expected format.', image_files(i).name);
    end
end

% Sort the files by the extracted numbers
[~, sortedIdx] = sort(fileNumbers);
image_files = image_files(sortedIdx);

n_images = length(image_files);
disp(['Number of imgs: ', num2str(n_images)]);

if num_rising_edges == n_images
    disp('Rising edge and img number matches')
else
    disp('Condition not met. Checking if should proceed...');
    % Allow user to decide whether to continue
    response = questdlg('Rising edge and image count mismatch. Continue anyway?', ...
        'Mismatch Warning', 'Yes', 'No', 'No');
    if strcmp(response, 'No')
        return;
    end
end

%% Find each trial's image indices
before_time = 2; % 2 seconds pre-stimulus period
Freq = 10;      % 10 Hz frame rate
image_indices_trial = {};
for i = 1:length(pd_rising_ts) - 1
    % Find image rising edges between two photodiode edges
    start_index = pd_rising_ts(i);
    end_index = pd_rising_ts(i+1);

    indices_in_range = find(camera_rising >= start_index & camera_rising <= end_index);
    
    % Include pre-stimulus period (2s before stimulus)
    trial_indices = indices_in_range;
    
    % Find frames corresponding to 2s before the stimulus
    pre_stim_start = max(1, indices_in_range(1) - before_time * Freq);
    pre_stim_indices = pre_stim_start:(indices_in_range(1)-1);
    
    % Combine pre-stimulus and stimulus frames
    image_indices_trial{i} = [pre_stim_indices, trial_indices];
end

%% Calculate mean across the twenty trials
n_trials = numel(image_indices_trial);
disp(['Number of trials: ', num2str(n_trials)]);

% Compute the number of frames in each trial
trial_lengths = cellfun(@length, image_indices_trial);

% Find the minimum number of frames among all trials
min_trial_length = min(trial_lengths);
disp(['Minimum trial length: ', num2str(min_trial_length)]);

% Preallocate a matrix to hold the truncated trial indices
images_mat = zeros(min_trial_length, n_trials);

% Truncate each trial's indices to the minimum length and store in matrix
for i = 1:n_trials
    images_mat(:, i) = image_indices_trial{i}(1:min_trial_length);
end

%% Average images across trials
% Load the first image to get its dimensions
sample_image = imread(fullfile(folder_path, image_files(1).name));
[img_height, img_width] = size(sample_image);

% Initialize array for average image sequence
avg_image_seq = zeros(img_height, img_width, min_trial_length);

% Loop over each frame index in the truncated trial length
for frame_idx = 1:min_trial_length
    sum_image = zeros(img_height, img_width);
    valid_trials = 0;
    
    % Loop over each trial
    for trial_idx = 1:n_trials
        img_index = images_mat(frame_idx, trial_idx);
        
        % Check if index is valid
        if img_index > 0 && img_index <= n_images
            curr_img = imread(fullfile(folder_path, image_files(img_index).name));
            % Accumulate the image
            sum_image = sum_image + double(curr_img);
            valid_trials = valid_trials + 1;
        else
            warning('Image index out of bounds: %d (skipping)', img_index);
        end
    end
    
    % Compute mean image for this frame (across valid trials)
    if valid_trials > 0
        avg_image_seq(:,:,frame_idx) = sum_image / valid_trials;
    else
        error('No valid images found for frame %d', frame_idx);
    end
end

%% Calculate F_rest from the 2s pre-stimulus period
preStimulusDuration = 2;               % in seconds
preStimFrames = preStimulusDuration * Freq;  % number of frames corresponding to 2s
% Ensure we have enough pre-stimulus frames
if preStimFrames > size(avg_image_seq, 3)
    error('Not enough frames for 2s pre-stimulus period');
end
Frest = mean(avg_image_seq(:,:,1:preStimFrames), 3);  % mean across pre-stimulus frames

%% Generate ΔF/F movie by subtracting F_rest and dividing by F_rest
deltaFoverF = (avg_image_seq - Frest) ./ Frest;

%% Apply spatial filtering with Gaussian kernel (σ = 258 µm = 5 pixels)
sigma_pixels = 5;  % 258 µm corresponds to 5 pixels
filtered_deltaFoverF = zeros(size(deltaFoverF));
for frame = 1:size(deltaFoverF, 3)
    filtered_deltaFoverF(:,:,frame) = imgaussfilt(deltaFoverF(:,:,frame), sigma_pixels);
end

%% Add manual masking functionality
% This section should be placed after generating filtered_deltaFoverF
% and before computing the maximum intensity projection

% Display first frame to help with mask definition
figure('Name', 'Define Masks', 'Position', [100, 100, 800, 600]);
imagesc(avg_image_seq(:,:,preStimFrames+1)); % Show first frame after stimulus onset
colormap(gray);
title('Define Circle and Rectangle Masks');
axis image;

% Let user draw a circular ROI
disp('Draw a circular region of interest:');
h_circle = drawcircle('Color', 'g', 'LineWidth', 2);
wait(h_circle);
circle_center = h_circle.Center;
circle_radius = h_circle.Radius;

% Create circle mask
[xx, yy] = meshgrid(1:size(filtered_deltaFoverF, 2), 1:size(filtered_deltaFoverF, 1));
circle_mask = ((xx - circle_center(1)).^2 + (yy - circle_center(2)).^2) <= (circle_radius^2);

% Let user draw rectangular exclusion regions inside the circle
disp('Draw rectangular exclusion regions inside the circle (double-click to finish each polygon):');
disp('Press Enter when all rectangles are drawn (or simply close the figure to finish drawing).');

% Initialize the rectangle mask with the same size as the circle mask
rectangle_masks = false(size(circle_mask));
rectangle_handles = [];

% Ask user for the number of rectangles (shank number of the device)
n_rectangles = input('Enter the shank number of the device: ');

for i = 1:n_rectangles
    disp(['Draw rectangle ', num2str(i), ' of ', num2str(n_rectangles)]);
    
    % Draw a polygon (which can be rotated) to represent the exclusion region
    h_rect = drawpolygon('Color', 'r', 'LineWidth', 2);
    wait(h_rect);  % Wait until the drawing is finished
    
    % Get the vertices of the drawn polygon
    vertices = h_rect.Position;  % vertices as [x, y] coordinates
    
    % Create a binary mask from the polygon
    current_mask = poly2mask(vertices(:,1), vertices(:,2), size(rectangle_masks, 1), size(rectangle_masks, 2));
    
    % Combine this mask with any previously drawn masks
    rectangle_masks = rectangle_masks | current_mask;
    
    % Store the handle for later visualization (if needed)
    rectangle_handles = [rectangle_handles, h_rect];
end

% Create the final mask: inside the circle but excluding the drawn rectangles
final_mask = circle_mask & ~rectangle_masks;

% Display the mask for verification
figure('Name', 'Verification', 'Position', [100, 100, 800, 600]);
imagesc(avg_image_seq(:,:,preStimFrames+1)); % Show first frame after stimulus
colormap(gray);
hold on;
h_mask = imagesc(cat(3, ~final_mask, zeros(size(final_mask)), zeros(size(final_mask))));
set(h_mask, 'AlphaData', 0.3); % Make the mask semi-transparent
title('Verification: Red areas will be excluded from analysis');
axis image;

% Ask for confirmation
response = questdlg('Is the mask correct?', 'Mask Verification', 'Yes', 'No, redo', 'Yes');
if strcmp(response, 'No, redo')
    error('Mask definition canceled. Please run the script again.');
end

saveas(gcf, fullfile(analysisFolder, 'mask_confirmation.png'));

% Apply the mask to all frames in the filtered_deltaFoverF
disp('Applying mask to all frames...');
for frame = 1:size(filtered_deltaFoverF, 3)
    % Apply mask by setting excluded regions to NaN
    current_frame = filtered_deltaFoverF(:,:,frame);
    current_frame(~final_mask) = NaN;
    filtered_deltaFoverF(:,:,frame) = current_frame;
end

%% Compute the maximum intensity projection (MIP) over time with masking
% Replace the existing MIP computation with this masked version
choice = menu('Select Wildtype Status', 'True', 'False');

% Assign the logical variable based on the user's choice
if choice == 1
    is_wildtype = true;
else
    is_wildtype = false;
end

% Display the result in the Command Window
disp(['is_wildtype set to: ' mat2str(is_wildtype)]);

%%

if is_wildtype
    mip = min(filtered_deltaFoverF, [], 3, 'omitnan'); 
else
    mip = max(filtered_deltaFoverF, [], 3, 'omitnan'); 
end

% Display the masked MIP
figure('Name', 'Masked MIP');
imagesc(mip);
colormap(jet);
colorbar;
title('Maximum Intensity Projection with Masked Regions');
axis image;


% Allow user to manually choose an ROI on the masked MIP figure
disp('Draw the ROI manually on the masked MIP figure:');
h_roi = drawpolygon('Color', 'w', 'LineWidth', 2);
wait(h_roi);  % Wait until the drawing is finished
manual_roi = h_roi.Position;  % Nx2 matrix containing the vertices of the ROI

% Optionally, display the drawn ROI over the MIP for confirmation
hold on;
if ~isequal(manual_roi(1,:), manual_roi(end,:))
    manual_roi = [manual_roi; manual_roi(1,:)];  % Close the polygon if needed
end
plot(manual_roi(:,1), manual_roi(:,2), 'w-', 'LineWidth', 2);
hold off;

% Save the mask and manual ROI for future reference
save(fullfile(analysisFolder, 'analysis_mask.mat'), 'circle_mask', 'rectangle_masks', 'final_mask', ...
    'circle_center', 'circle_radius', 'manual_roi');
%% Find ROI centered on peak ΔF/F (using masked data)
% For wild-type mice, find minimum (dimmest pixel) in unmasked areas
% For typical cases, find maximum (brightest pixel) in unmasked areas

% Create a copy of MIP for finding peaks (with very negative values for masked areas)
peak_finding_mip = mip;
peak_finding_mip(isnan(peak_finding_mip)) = -inf; % Set masked areas to -inf

if is_wildtype
    % For wild-type, we're looking for minimum values
    % Set masked areas to positive infinity to ignore them
    peak_finding_mip = mip;
    peak_finding_mip(isnan(peak_finding_mip)) = inf;
    
    [min_val, linIdx] = min(peak_finding_mip(:));
    [peak_row, peak_col] = ind2sub(size(peak_finding_mip), linIdx);
    disp(['Minimum ΔF/F value in unmasked region: ', num2str(min_val)]);
else
    % For typical cases, find maximum (brightest pixel)
    [max_val, linIdx] = max(peak_finding_mip(:));
    [peak_row, peak_col] = ind2sub(size(peak_finding_mip), linIdx);
    disp(['Maximum ΔF/F value in unmasked region: ', num2str(max_val)]);
end

% Display the MIP with ROI location marked
figure('Name', 'MIP with ROI');
imagesc(mip);
colormap(jet);
colorbar;
hold on;

% Show the circle mask
viscircles(circle_center, circle_radius, 'EdgeColor', 'g', 'LineWidth', 1);
hold on;

% Plot each drawn polygon (rotated exclusion region)
for i = 1:length(rectangle_handles)
    % Get the vertices of the drawn polygon
    vertices = rectangle_handles(i).Position;  % Nx2 matrix of vertices
    
    % Close the polygon if it is not already closed
    if ~isequal(vertices(1,:), vertices(end,:))
        vertices = [vertices; vertices(1,:)]; 
    end
    
    % Plot the polygon outline
    plot(vertices(:,1), vertices(:,2), 'r-', 'LineWidth', 1);
end

% Optionally, show the peak location (if applicable)
plot(peak_col, peak_row, 'wo', 'MarkerSize', 10, 'LineWidth', 2);
plot(peak_col, peak_row, 'ko', 'MarkerSize', 10, 'LineWidth', 1);
title('Maximum Intensity Projection with ROI Center (Peak ΔF/F in Unmasked Region)');
axis image;
hold off;


%% Continue with the existing code for ROI definition and fluorescence extraction
% Define a 10-pixel (516 µm) square ROI centered on the peak pixel
roi_size = 10;   % 516 µm corresponds to 10 pixels
half_roi = roi_size / 2;

% Determine row and column limits ensuring they are within image bounds
row_start = max(round(peak_row - half_roi + 1), 1);
row_end   = min(round(peak_row + half_roi), size(mip, 1));
col_start = max(round(peak_col - half_roi + 1), 1);
col_end   = min(round(peak_col + half_roi), size(mip, 2));

% Draw ROI on the MIP
rectangle('Position', [col_start, row_start, col_end-col_start, row_end-row_start], ...
    'EdgeColor', 'w', 'LineWidth', 2);
hold off;

% Save this figure
saveas(gcf, fullfile(analysisFolder, 'masked_mip_with_roi.fig'));
saveas(gcf, fullfile(analysisFolder, 'masked_mip_with_roi.png'));


%% Plot the Chosen ROI ΔF/F change along time

% Determine the number of frames
nFrames = size(filtered_deltaFoverF, 3);

% Preallocate vector for ROI fluorescence
roi_fluorescence = zeros(nFrames, 1);

% Loop over each frame to compute the mean ΔF/F in the ROI
for frame = 1:nFrames
    current_frame = filtered_deltaFoverF(:,:,frame);
    % Compute the mean ΔF/F in the ROI, ignoring NaN values (from masked regions)
    roi_fluorescence(frame) = mean(current_frame(row_start:row_end, col_start:col_end), 'all', 'omitnan');
end

% Create a time axis (in seconds) based on the frame rate
time_axis = (1:nFrames) / Freq;
time_axis = time_axis - preStimulusDuration;

% Plot the ROI ΔF/F time course
figure('Name', 'ROI ΔF/F Change Over Time', 'Position', [100, 100, 800, 600]);
plot(time_axis, roi_fluorescence, 'b', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('ΔF/F');
title('ROI ΔF/F Change Over Time');
grid on;

% Save the ROI fluorescence data for later use
save(fullfile(analysisFolder, 'roi_fluorescence.mat'), 'roi_fluorescence', 'time_axis');

% Also save the ROI ΔF/F plot as image files (FIG and PNG)
saveas(gcf, fullfile(analysisFolder, 'ROI_DeltaFoverF_Over_Time.fig'));
saveas(gcf, fullfile(analysisFolder, 'ROI_DeltaFoverF_Over_Time.png'));

%% Plot the Manual Chosen ROI ΔF/F time series
% Create a binary mask from the manually drawn ROI polygon
% (manual_roi was obtained previously using drawpolygon on the masked MIP)
manual_roi_mask = poly2mask(manual_roi(:,1), manual_roi(:,2), size(filtered_deltaFoverF, 1), size(filtered_deltaFoverF, 2));

% Preallocate vector for manual ROI fluorescence
manual_roi_fluorescence = zeros(nFrames, 1);

% Loop over each frame to compute the mean ΔF/F within the manual ROI
for frame = 1:nFrames
    current_frame = filtered_deltaFoverF(:,:,frame);
    manual_roi_fluorescence(frame) = mean(current_frame(manual_roi_mask), 'omitnan');
end

% Plot the manual ROI ΔF/F time course
figure('Name', 'Manual ROI ΔF/F Change Over Time', 'Position', [100, 100, 800, 600]);
plot(time_axis, manual_roi_fluorescence, 'm', 'LineWidth', 2);
xlabel('Time (s)');
ylabel('ΔF/F');
title('Manual ROI ΔF/F Change Over Time');
grid on;

% Save the manual ROI fluorescence data for later use
save(fullfile(analysisFolder, 'manual_roi_fluorescence.mat'), 'manual_roi_fluorescence', 'time_axis');
saveas(gcf, fullfile(analysisFolder, 'Manual_ROI_DeltaFoverF_Over_Time.fig'));
saveas(gcf, fullfile(analysisFolder, 'Manual_ROI_DeltaFoverF_Over_Time.png'));