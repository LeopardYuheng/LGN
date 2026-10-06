%% Clear Environment and Add Paths
close all;                % Close any open figure windows
clear;                    % Clear workspace variables
% addpath(genpath('C:\Data_processing'));  % Add all subdirectories from Data_processing
addpath(genpath('\\10.129.151.108\xieluanlabs\xl_LGN\LGN_ALBERT\TOOLBOX_YC\Data_processing_Xiaorong'));
% Make SignMapperModifR_masked findable. Point this at the folder that holds
% SignMapperModifR_masked.m (edit if you move the analysis_code folder).
addpath('I:\yuheng\retinomap_code\retinomap_analysis_code');
%analysisfolder = (uigetdir(pwd, 'Select a data folder to analysis'));
%cd(analysisfolder)
%     'xl_LGN\LGN_ALBERT\LGN imaging\code_wf+stim_+old_code\Data_processing_Xiaorong']));
% Z:\xl_LGN\LGN_ALBERT\TOOLBOX_YC
%% Select Output Folder
% All saved files will be written under this folder instead of the current code/data folder.
originalFolder = pwd;
outputRoot = uigetdir(pwd, 'Select OUTPUT folder to save all results');
if isequal(outputRoot, 0)
    error('No output folder selected. Operation cancelled.');
end

matFolder     = fullfile(outputRoot, 'MAT_files');
figFolder     = fullfile(outputRoot, 'Figures');
videoFolder   = fullfile(outputRoot, 'Videos');
signMapFolder = fullfile(outputRoot, 'SignMap_outputs');

outputFolders = {matFolder, figFolder, videoFolder, signMapFolder};
for dd = 1:numel(outputFolders)
    if ~exist(outputFolders{dd}, 'dir')
        mkdir(outputFolders{dd});
    end
end

fprintf('All outputs will be saved to:\n%s\n', outputRoot);


%% Load Intan RHD Data
% Get list of .rhd files in the current folder
DIR = dir('*.rhd');

% Preallocate cell arrays for digital input data and time stamps
numFiles = numel(DIR);
recFile = cell(1, numFiles);
tIntan  = cell(1, numFiles);

for i = 1:numFiles
    % Read the Intan RHD2000 data file. This should load board_dig_in_data and t_dig.
    read_Intan_RHD2000_fileV3(DIR(i).name, []);
    recFile{1, i} = board_dig_in_data;
    tIntan{1, i}  = t_dig;
end

% Concatenate digital input data across files and save the results
recFile = cat(2, recFile{:});
save(fullfile(matFolder, 'DIN.mat'), 'recFile', 'tIntan', 'frequency_parameters', '-v7.3');

%% Process Diode Pulse Data
% Sampling rate from Intan frequency parameters
Fs = frequency_parameters.amplifier_sample_rate;

% Find rising edges in the first row of recFile (positive transitions)
t_rising_edge_diode = find(diff(recFile(4, :)) > 0);%row 4 is the PD digital input in INTAN
% Compute inter-pulse intervals (in samples)
inter_pulse_interval_diode = diff(t_rising_edge_diode);

%% Detect Screen Flashing Points
% Define time (and amplitude inversion) for display purposes
pd_t = t_rising_edge_diode(1:end-1);
pd = -inter_pulse_interval_diode;

% Plot the original signal of rising edge intervals
figOriginalPD = figure('Color', 'w');
plot(pd_t, pd, 'b', 'LineWidth', 1);
title('Original Signal');
xlabel('Time');
ylabel('Amplitude');
grid on;
saveas(figOriginalPD, fullfile(figFolder, 'original_pd_signal.png'));
savefig(figOriginalPD, fullfile(figFolder, 'original_pd_signal.fig'));
% % 
% % replace this code '[pks, locs] = findpeaks(pd, pd_t, 'MinPeakHeight', -3.5, 'MinPeakDistance', 70000);
% % figDetectedPeaks = figure('Color', 'w');
% % plot(pd_t, pd, 'b-'); hold on;
% % plot(locs, pks, 'ro', 'MarkerFaceColor', 'r');
% % hold off;
% % ylabel('Amplitude');
% % title('Detected Peaks');
% % disp(['Number of peaks detected: ', num2str(length(pks))]);
% % saveas(figDetectedPeaks, fullfile(figFolder, 'detected_peaks.png'));
% % savefig(figDetectedPeaks, fullfile(figFolder, 'detected_peaks.fig'));
% % save(fullfile(matFolder, 'peaks.mat'), 'locs', 'pks');
% % ' with the following method of the rising edge detection, the output should be locs as before
% % also do it for the whole dataset
% % 
% Detect Screen Flashing Points
% Define time (and amplitude inversion) for display purposes
pd_t = t_rising_edge_diode(1:end-1);
pd = -inter_pulse_interval_diode;

% Plot the original signal of rising edge intervals
figOriginalPD = figure('Color', 'w');
plot(pd_t, pd, 'b', 'LineWidth', 1);
title('Original Signal');
xlabel('Time');
ylabel('Amplitude');
grid on;
saveas(figOriginalPD, fullfile(figFolder, 'original_pd_signal.png'));
savefig(figOriginalPD, fullfile(figFolder, 'original_pd_signal.fig'));

% % %% Find Peaks in the Signal
% % % Detect peaks with a given minimum height and minimum distance between them
% % % [pks, locs] = findpeaks(pd, pd_t, 'MinPeakHeight', -5, 'MinPeakDistance', 30000);
% % % 
% % % % part of data
% % % end_point = 1e6;
% % % % Limit the data to the specified endpoint
% % % temp_pd = pd(1:end_point);
% % % temp_pd_t = pd_t(1:end_point);
% % % 
% % % % temp_pd: input numeric vector (row or column)
% % % x = temp_pd(:);                 % ensure column
% % % 
% % % % 1) Threshold to binary (1 where value > -300)
% % % bw = x > -400;
% % % 
% % % % 2) Remove small components (objects) smaller than 10000 samples
% % % minSize = 10;
% % % bw_clean = bwareaopen(bw, minSize);   % requires Image Processing Toolbox
% % % 
% % % % 3) Optional: close small gaps (dilate then erode) with kernel length 10000
% % % se = true(minSize,1);                  % 1D structuring element
% % % bw_closed = imclose(bw_clean, se);     % imclose does dilation then erosion
% % % 
% % % % Use either bw_clean or bw_closed as the denoised result:
% % % bw_final = bw_closed;
% % % 
% % % % 4) Find rising edges (indices of the second sample where 0->1 occurs)
% % % rising = find(bw_final(1:end-1)==0 & bw_final(2:end)==1) + 1;
% % % 
% % % % Output
% % % risingIndices = rising;
% % % bw_processed = bw_final;
% % % 
% % % figure;
% % % plot(temp_pd_t, temp_pd, 'b-'); 
% % % figure;
% % % plot(temp_pd_t,bw_processed);
% % % 
% % % %%
% % % 
% %% Detect stimulus starts using thresholded binary rising edges across the whole dataset
% This replaces findpeaks(). It uses the full pd / pd_t vectors, not a subset.
% locs is kept as the detected stimulus-start sample locations, same role as before.
x = pd(:);          % full dataset, force column vector
pd_t_col = pd_t(:); % matching sample-location vector

% 1) Threshold to binary: true where the interval signal enters the stimulus-marker state
pdThreshold = -80;
bw = x > pdThreshold;

% 2) Remove small noisy components
minSize = 10;
bw_clean = bwareaopen(bw, minSize);   % requires Image Processing Toolbox

% 3) Close small gaps in the binary signal
se = true(minSize, 1);                 % 1D structuring element
bw_processed = imclose(bw_clean, se);  % dilation then erosion

% 4) Find rising edges of the processed binary signal, i.e., 0 -> 1 transitions
risingIndices = find(bw_processed(1:end-1) == 0 & bw_processed(2:end) == 1) + 1;
if ~isempty(bw_processed) && bw_processed(1)
    % If the recording starts inside a detected stimulus-marker block, keep that first block.
    risingIndices = [1; risingIndices(:)];
else
    risingIndices = risingIndices(:);
end

% Output in the same format expected downstream:
% locs should be the original Intan sample locations, not the index inside pd.
locs = pd_t_col(risingIndices);
pks  = x(risingIndices);  % keep pks for saving / plotting compatibility

figDetectedPeaks = figure('Color', 'w');
plot(pd_t_col, x, 'b-'); hold on;
plot(locs, pks, 'ro', 'MarkerFaceColor', 'r');
hold off;
ylabel('Amplitude');
title('Detected Stimulus Starts from Binary Rising Edges');
grid on;
disp(['Number of binary rising edges detected: ', num2str(numel(locs))]);
saveas(figDetectedPeaks, fullfile(figFolder, 'detected_binary_rising_edges.png'));
savefig(figDetectedPeaks, fullfile(figFolder, 'detected_binary_rising_edges.fig'));

figProcessedBinary = figure('Color', 'w');
plot(pd_t_col, bw_processed, 'k-');
ylabel('Processed binary signal');
xlabel('Intan sample index');
title('Processed Binary Signal for Stimulus Detection');
ylim([-0.1, 1.1]);
grid on;
saveas(figProcessedBinary, fullfile(figFolder, 'processed_binary_signal.png'));
savefig(figProcessedBinary, fullfile(figFolder, 'processed_binary_signal.fig'));
locs = locs(2:161);
pks = pks(2:161);
save(fullfile(matFolder, 'peaks.mat'), 'locs', 'pks', 'risingIndices', ...
    'bw_processed', 'pdThreshold', 'minSize', '-v7.3');
% % % part of data
% % end_point = 1e6;
% % % Limit the data to the specified endpoint
% % temp_pd = pd(1:end_point);
% % temp_pd_t = pd_t(1:end_point);
% % 
% % % temp_pd: input numeric vector (row or column)
% % x = temp_pd(:);                 % ensure column
% % 
% % % 1) Threshold to binary (1 where value > -300)
% % bw = x > -400;
% % 
% % % 2) Remove small components (objects) smaller than 10000 samples
% % minSize = 10;
% % bw_clean = bwareaopen(bw, minSize);   % requires Image Processing Toolbox
% % 
% % % 3) Optional: close small gaps (dilate then erode) with kernel length 10000
% % se = true(minSize,1);                  % 1D structuring element
% % bw_closed = imclose(bw_clean, se);     % imclose does dilation then erosion
% % 
% % % Use either bw_clean or bw_closed as the denoised result:
% % bw_final = bw_closed;
% % 
% % % 4) Find rising edges (indices of the second sample where 0->1 occurs)
% % rising = find(bw_final(1:end-1)==0 & bw_final(2:end)==1) + 1;
% % 
% % % Output
% % risingIndices = rising;
% % bw_processed = bw_final;
% % 
% % figure;
% % plot(temp_pd_t, temp_pd, 'b-'); 
% % figure;
% % plot(temp_pd_t,bw_processed);
% % 
% % %%
% % 


% % 
% % % Limit the data to the specified endpoint
% % x = pd;
% % temp_pd_t = pd_t;
% % 
% % % temp_pd: input numeric vector (row or column)
% % % x = temp_pd(:);                 % ensure column
% % 
% % % 1) Threshold to binary (1 where value > -300)
% % bw = x > -400;
% % 
% % % 2) Remove small components (objects) smaller than 10000 samples
% % minSize = 10;
% % bw_clean = bwareaopen(bw, minSize);   % requires Image Processing Toolbox
% % 
% % % 3) Optional: close small gaps (dilate then erode) with kernel length 10000
% % se = true(minSize,1);                  % 1D structuring element
% % bw_closed = imclose(bw_clean, se);     % imclose does dilation then erosion
% % 
% % % Use either bw_clean or bw_closed as the denoised result:
% % bw_final = bw_closed;
% % 
% % % 4) Find rising edges (indices of the second sample where 0->1 occurs)
% % rising = find(bw_final(1:end-1)==0 & bw_final(2:end)==1) + 1;
% % 
% % % Output
% % risingIndices = rising;
% % bw_processed = bw_final;
% % % 
% % % figure;
% % % plot(temp_pd_t, temp_pd, 'b-'); 
% % % figure;
% % % plot(temp_pd_t,bw_processed);
% % locs = risingIndices(1:numel(locs)-1);
% % save('peaks.mat', 'locs');
% load('peaks.mat');
%% Define Stimulus Trials and Peak Intervals
% Assume locs contains alternating start and end times of stimuli
TrialsStart = locs(1:1:end);
% TrialsEnd   = locs(2:2:end);

% TrialsStart = locs;
peakIntervals = diff(TrialsStart)/Fs;

% Plot the histogram of the inter-trial intervals
figTrialIntervals = figure('Color', 'w');
histogram(peakIntervals, BinWidth=0.002);
xlabel('Interval between Peaks (s)');
ylabel('Frequency');
title('Distribution of Trial length');
saveas(figTrialIntervals, fullfile(figFolder, 'trial_interval_histogram.png'));
savefig(figTrialIntervals, fullfile(figFolder, 'trial_interval_histogram.fig'));

%% Load Stimulus Data
[fn, fp] = uigetfile('*.mat', 'Select the Stimulus Data MAT File');
load(fullfile(fp, fn));  % Loads a variable (or variables) from the chosen file

%% Validate Image Count Versus Rising Edges
% Determine camera rising and falling edges from channel 2 of recFile
camera_diff    = diff(recFile(3, :));
camera_rising  = find(camera_diff > 0);
camera_falling = find(camera_diff < 0);
camera_indicator = camera_falling;  % Using falling edges as the indicator

% Estimate camera sampling rate using rising edge intervals
camera_sampling_rate = round(1 / (mean(diff(camera_rising)) / Fs));
disp(['Camera sampling rate: ', num2str(camera_sampling_rate)]);

num_rising_edges = length(camera_indicator);
disp(['Number of rising edges: ', num2str(num_rising_edges)]);

% Ask user to select the folder containing the images
folder_path = uigetdir(pwd, 'Select Corresponding Image Folder');
% Get and sort image files (expecting *.tif filenames with numeric tokens)
image_files = dir(fullfile(folder_path, '*.tif'));
nFiles = numel(image_files);
fileNumbers = zeros(nFiles, 1);
for i = 1:nFiles
    tokens = regexp(image_files(i).name, '_([0-9]+)\.tif$', 'tokens');
    if ~isempty(tokens)
        fileNumbers(i) = str2double(tokens{1}{1});
    else
        error('Filename "%s" does not match expected format.', image_files(i).name);
    end
end
[~, sortedIdx] = sort(fileNumbers);
image_files = image_files(sortedIdx);
n_images = length(image_files);
disp(['Number of images: ', num2str(n_images)]);

if num_rising_edges == n_images
    disp('Rising edge and image count match.');
else
    disp('Mismatch between rising edges and image count.');
    response = questdlg('Rising edge and image count mismatch. Continue anyway?', ...
        'Mismatch Warning', 'Yes', 'No', 'No');
    if strcmp(response, 'No')
        return;
    end
end

%% Compute On and Off Indices for Each Trial
numTrials = numel(TrialsStart);
% numTrials = floor(numTrials / 4) * 4;

on_indices_trial  = cell(numTrials, 1);
off_indices_trial = cell(numTrials, 1);

% Define the number of frames per stimulus-on period
on_time   = Stimdata.on_time;  % from the loaded stimulus data
on_frames = on_time * camera_sampling_rate;

% Compute on-indices for each trial: choose the smallest camera_indicator value greater than TrialsStart(i)
for i = 1:numTrials
    %onIndex = find((camera_indicator > TrialsStart(i)) & (camera_indicator <= TrialsEnd(i)));
    %for some old data
    onIndex = find((camera_indicator > TrialsStart(i)));
    onStartIndex = onIndex(1);
    on_indices_trial{i} = onStartIndex : (onStartIndex + on_frames - 1);
end

% Define off-period frames using a duration (in seconds) preceding the on period
before_second = 2;  % seconds
off_frames = before_second * camera_sampling_rate;
for i = 1:numTrials
    onStartIndex = on_indices_trial{i}(1);
    off_indices_trial{i} = (onStartIndex - off_frames) : (onStartIndex - 1);
end

%% Get Image Size from the Last Image
firstFile = image_files(end);
fullPath = fullfile(firstFile.folder, firstFile.name);
first_img = imread(fullPath);
info = imfinfo(fullPath);
width  = info(1).Width;
height = info(1).Height;
fprintf('Image size is %d (height) x %d (width)\n', height, width);

%% Separate Orientation Images into Repeats
% Assumption: Every 4 trials correspond to front, back, up, and down orientations.
repeats = numTrials / 4;

% Preallocate arrays for on-phase images (dimensions: [height, width, on_frames, repeats])
dims_on = [height, width, on_frames, repeats];
azi_on_f = zeros(dims_on, 'single');
azi_on_b = zeros(dims_on, 'single');
alt_on_u = zeros(dims_on, 'single');
alt_on_d = zeros(dims_on, 'single');

% Preallocate arrays for off-phase images (dimensions: [height, width, off_frames, repeats])
dims_off = [height, width, off_frames, repeats];
azi_off_f = zeros(dims_off, 'single');
azi_off_b = zeros(dims_off, 'single');
alt_off_u = zeros(dims_off, 'single');
alt_off_d = zeros(dims_off, 'single');

%% Optimized: Read On-Phase Images and Group by Repeat Using parfor
disp(' 1. load images')
parfor rep = 1:repeats
    % Determine trial numbers for each orientation in the current repeat
    trial_front = 4*(rep - 1) + 1;
    trial_back  = 4*(rep - 1) + 2;
    trial_up    = 4*(rep - 1) + 3;
    trial_down  = 4*(rep - 1) + 4;
    
    % Retrieve on-indices for each trial
    idxF = on_indices_trial{trial_front};
    idxB = on_indices_trial{trial_back};
    idxU = on_indices_trial{trial_up};
    idxD = on_indices_trial{trial_down};
    
    % Preallocate temporary arrays for this repeat
    tmp_on_f = zeros(height, width, on_frames, 'single');
    tmp_on_b = zeros(height, width, on_frames, 'single');
    tmp_on_u = zeros(height, width, on_frames, 'single');
    tmp_on_d = zeros(height, width, on_frames, 'single');
    
    % Loop over frames in the on period
    for f = 1:on_frames
        % --- Front trial ---
        fileIdx = idxF(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_on_f(:, :, f) = single(imread(fullPath));
        
        % --- Back trial ---
        fileIdx = idxB(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_on_b(:, :, f) = single(imread(fullPath));
        
        % --- Up trial ---
        fileIdx = idxU(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_on_u(:, :, f) = single(imread(fullPath));
        
        % --- Down trial ---
        fileIdx = idxD(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_on_d(:, :, f) = single(imread(fullPath));
    end
    
    % Write the results back to the preallocated 4D arrays
    azi_on_f(:, :, :, rep) = tmp_on_f;
    azi_on_b(:, :, :, rep) = tmp_on_b;
    alt_on_u(:, :, :, rep) = tmp_on_u;
    alt_on_d(:, :, :, rep) = tmp_on_d;
end


%% Optimized: Read Off-Phase Images and Group by Repeat Using parfor
parfor rep = 1:repeats
    % Determine trial numbers for each orientation in the current repeat
    trial_front = 4*(rep - 1) + 1;
    trial_back  = 4*(rep - 1) + 2;
    trial_up    = 4*(rep - 1) + 3;
    trial_down  = 4*(rep - 1) + 4;
    
    % Retrieve off-indices for each trial
    off_idxF = off_indices_trial{trial_front};
    off_idxB = off_indices_trial{trial_back};
    off_idxU = off_indices_trial{trial_up};
    off_idxD = off_indices_trial{trial_down};
    
    % Preallocate temporary arrays for this repeat
    tmp_off_f = zeros(height, width, off_frames, 'single');
    tmp_off_b = zeros(height, width, off_frames, 'single');
    tmp_off_u = zeros(height, width, off_frames, 'single');
    tmp_off_d = zeros(height, width, off_frames, 'single');
    
    % Loop over frames in the off period
    for f = 1:off_frames
        % --- Front trial off-phase ---
        fileIdx = off_idxF(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_off_f(:, :, f) = single(imread(fullPath));
        
        % --- Back trial off-phase ---
        fileIdx = off_idxB(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_off_b(:, :, f) = single(imread(fullPath));
        
        % --- Up trial off-phase ---
        fileIdx = off_idxU(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_off_u(:, :, f) = single(imread(fullPath));
        
        % --- Down trial off-phase ---
        fileIdx = off_idxD(f);
        fullPath = fullfile(image_files(fileIdx).folder, image_files(fileIdx).name);
        tmp_off_d(:, :, f) = single(imread(fullPath));
    end
    
    % Write the results back to the preallocated 4D arrays
    azi_off_f(:, :, :, rep) = tmp_off_f;
    azi_off_b(:, :, :, rep) = tmp_off_b;
    alt_off_u(:, :, :, rep) = tmp_off_u;
    alt_off_d(:, :, :, rep) = tmp_off_d;
end

disp('images loaded')

%%
% Continue saving to the outputRoot selected at the beginning.
disp(['Saving processing outputs to: ', outputRoot]);
disp('Baseline subtracting and averaging over repeats...');

m_azi_off_f = squeeze(mean(azi_off_f, 3));
m_azi_off_b =  squeeze(mean(azi_off_b, 3));
m_alt_off_u = squeeze(mean(alt_off_u, 3));
m_alt_off_d = squeeze(mean(alt_off_d, 3));

% Preallocate 3D arrays to hold the average responses (dimensions: [height, width, on_frames])
azi_f_avg = zeros(height, width, on_frames, 'single');
azi_b_avg = zeros(height, width, on_frames, 'single');
alt_u_avg = zeros(height, width, on_frames, 'single');
alt_d_avg = zeros(height, width, on_frames, 'single');

% Process each repeat sequentially to update the average
for rep = 1:repeats
    % Compute the difference for the current repeat
    diff_azi_f = azi_on_f(:,:,:,rep) - m_azi_off_f(:,:,rep);
    diff_azi_b = azi_on_b(:,:,:,rep) - m_azi_off_b(:,:,rep);
    diff_alt_u = alt_on_u(:,:,:,rep) - m_alt_off_u(:,:,rep);
    diff_alt_d = alt_on_d(:,:,:,rep) - m_alt_off_d(:,:,rep);
    
    % Accumulate the differences
    azi_f_avg = azi_f_avg + diff_azi_f;
    azi_b_avg = azi_b_avg + diff_azi_b;
    alt_u_avg = alt_u_avg + diff_alt_u;
    alt_d_avg = alt_d_avg + diff_alt_d;
end

% Divide by the number of repeats to obtain the average
azi_f_avg = azi_f_avg / repeats;
azi_b_avg = azi_b_avg / repeats;
alt_u_avg = alt_u_avg / repeats;
alt_d_avg = alt_d_avg / repeats;
save(fullfile(matFolder, 'averaged_responses.mat'), 'azi_f_avg', 'azi_b_avg', 'alt_u_avg', 'alt_d_avg', '-v7.3');

% Cell array of averaged data for the 4 directions
averagedVideos = {azi_f_avg, azi_b_avg, alt_u_avg, alt_d_avg};

% Corresponding MP4 file names (note the .mp4 extension)
videoNames = {'azi_f_avg_video.mp4', 'azi_b_avg_video.mp4', ...
              'alt_u_avg_video.mp4', 'alt_d_avg_video.mp4'};

% Loop over each direction to generate an MP4 video
for v = 1:length(averagedVideos)
    % Create a VideoWriter object with the MPEG-4 profile for MP4 files
    videoPath = fullfile(videoFolder, videoNames{v});
    writerObj = VideoWriter(videoPath, 'MPEG-4');
    writerObj.FrameRate = camera_sampling_rate; % Use camera_sampling_rate as frame rate
    open(writerObj);
    
    % Get the current averaged 3D array, with dimensions [height, width, frames]
    currentAvg = averagedVideos{v};
    
    % Loop over each frame of the current averaged array
    for k = 1:size(currentAvg, 3)
        % Normalize the frame into [0,1] and convert to uint8
        frame = im2uint8(mat2gray(currentAvg(:,:,k)));
        % Write the frame into the video
        writeVideo(writerObj, frame);
    end
    
    % Close the VideoWriter to finalize and save the file
    close(writerObj);
    fprintf('Saved video %s\n', videoPath);
end

%% Parameters
T = on_time;                 % Stimulus period in seconds
f_target = 1/T;          % Stimulus frequency (Hz)
% It is assumed that: on_frames = T * camera_sampling_rate

%% Get FFT along the time dimension (dimension 3)
% Compute the FFT for each averaged response array.
fft_azi_f = fft(azi_f_avg, [], 3);
fft_azi_b = fft(azi_b_avg, [], 3);
fft_alt_u = fft(alt_u_avg, [], 3);
fft_alt_d = fft(alt_d_avg, [], 3);

%% Run fourier transforms
fourier_data(:,:,:,1) = fft_azi_f;
fourier_data(:,:,:,2) = fft_azi_b;
fourier_data(:,:,:,3) = fft_alt_u;
fourier_data(:,:,:,4) = fft_alt_d;
%Could try Ming's way of doing Fourier's transform based on frequency of
%the stim 
save(fullfile(matFolder, 'processing_data.mat'), 'fourier_data', '-v7.3'); 

%%
sm = SignMapperModifR_masked();   % subclass: weighted (masked) phase-unwrap inside getRetinotopicMap
sm.ref_img = first_img;

%% Load brain mask (draw it beforehand with draw_brain_mask.m)
[bmName, bmPath] = uigetfile('*.mat', 'Select brain_mask.mat (from draw_brain_mask.m)');
if isequal(bmName, 0)
    error('No brain_mask.mat selected. Run draw_brain_mask.m first.');
end
bm = load(fullfile(bmPath, bmName), 'brain_mask');
brain_mask_raw = logical(bm.brain_mask);   % raw image space (same H x W as first_img)

% Align the mask to the phase-map space. getRetinotopicMap rot90's the phase
% maps internally, so rotate the raw-space mask the same way. This single
% mask_map is reused below for the input/output masking too.
mask_map = rot90(brain_mask_raw);
mp_size  = [size(fourier_data,2), size(fourier_data,1)];   % phase-map size (after rot90)
if ~isequal(size(mask_map), mp_size)
    mask_map = imresize(mask_map, mp_size, 'nearest');
end
mask_map = logical(mask_map);

% Feed the mask into the sign mapper so the phase-unwrap inside getRetinotopicMap
% is WEIGHTED: cement pixels get weight 0 and drop out of the global Poisson
% solve, so they no longer leak into the brain interior. Must be set BEFORE
% findRetinotopicMap / getRetinotopicMap are called below.
sm.brain_mask = double(mask_map);

figReferenceImage = figure('Color', 'w');
imagesc(first_img); axis image; title('Reference Image');
saveas(figReferenceImage, fullfile(figFolder, 'reference_image.png'));
savefig(figReferenceImage, fullfile(figFolder, 'reference_image.fig'));
k = sm.findRetinotopicMap(fourier_data); % Find the correct harmonic for retinotopic maps
 % Get the lowest harmonic which isn't normally distributed
  % the real map is very positively skewed
[azi,alt] = sm.getRetinotopicMap(fourier_data,k); % Get the retinotopic map of determined harmonic
sm.displayMaps(azi,alt); % Show maps

% (azi/alt are masked and saved after the manual harmonic-check loop below)
% Below allows you to manually redefine maps if the auto-chooser got the wrong harmonic
while true
    goodmap = questdlg('Do your maps look good?','Map quality','Yes','No','Yes');
    close
    
    switch goodmap
        case 'No'
            k = sm.manualFindRetinotopicMap(fourier_data);
            [azi,alt] = sm.getRetinotopicMap(fourier_data,k);
            sm.displayMaps(azi,alt);
        case 'Yes'
            break
    end
end

%% ===== Apply brain mask (INPUT + OUTPUT, with weighted unwrap) =====
% The phase-unwrap inside getRetinotopicMap was already WEIGHTED by the mask
% (sm.brain_mask, set above), so cement did not leak into the brain interior of
% azi/alt. Here we additionally (a) flat-fill cement before the sign-mapping
% step and (b) mask the saved/displayed outputs. mask_map was computed above.
if ~isequal(size(mask_map), size(azi))
    mask_map = imresize(mask_map, size(azi), 'nearest');   % safety
end
mask_map = logical(mask_map);

% INPUT masking for the SIGN MAP step: replace cement with the in-brain mean so
% the exterior is flat (~zero gradient -> VFS ~ 0 there). Avoids NaNs, which
% would corrupt the resample/gradient steps inside the sign-mapping algorithm.
azi_in = azi;  alt_in = alt;
azi_in(~mask_map) = mean(azi(mask_map), 'omitnan');
alt_in(~mask_map) = mean(alt(mask_map), 'omitnan');

% OUTPUT masking: masked maps for display / saving / quantification (cement -> NaN).
azi(~mask_map) = NaN;
alt(~mask_map) = NaN;

% Verification overlay: confirm the mask lines up with the brain in map space.
figMaskCheck = figure('Color','w');
imagesc(azi); axis image; colormap hsv; colorbar; hold on;
visboundaries(mask_map, 'Color', 'k', 'LineWidth', 1);
title('Masked Azimuth (verify brain/cement alignment)');
saveas(figMaskCheck, fullfile(figFolder, 'mask_alignment_check.png'));
savefig(figMaskCheck, fullfile(figFolder, 'mask_alignment_check.fig'));

save(fullfile(matFolder, 'azi.mat'), 'azi', '-v7.3', '-nocompression')
save(fullfile(matFolder, 'alt.mat'), 'alt', '-v7.3', '-nocompression')
save(fullfile(matFolder, 'brain_mask_applied.mat'), 'mask_map', 'brain_mask_raw', '-v7.3')

% Save the final accepted retinotopic map figure
sm.displayMaps(azi, alt);
figFinalMaps = gcf;
saveas(figFinalMaps, fullfile(figFolder, 'final_retinotopic_maps.png'));
savefig(figFinalMaps, fullfile(figFolder, 'final_retinotopic_maps.fig'));

% Save trial/camera alignment information for later checking
save(fullfile(matFolder, 'trial_camera_alignment_info.mat'), ...
    'TrialsStart', 'peakIntervals', 'camera_indicator', 'camera_rising', 'camera_falling', ...
    'camera_sampling_rate', 'on_indices_trial', 'off_indices_trial', ...
    'folder_path', 'image_files', 'on_time', 'on_frames', 'off_frames', 'repeats', '-v7.3');

% Some SignMapper methods save files to the current folder.
% Temporarily switch to signMapFolder so those files are also saved in the output path.
oldFolder = pwd;
cd(signMapFolder);
if ~exist('AdditionalSignMapMaterials', 'dir')
    mkdir('AdditionalSignMapMaterials'); % Additional save directory for supplemental stuff
end

maps = sm.Juavinett2017_signMapping(azi_in, alt_in); % INPUT+OUTPUT: sign map on flat-filled maps

% Mask the VFS products to the brain area (resize the mask to the VFS grid).
% NOTE: VFS lives on a different grid/orientation than azi/alt (see README);
% inspect overlay_map.jpg to confirm alignment.
vfsMask = imresize(mask_map, [size(maps.VFS_raw,1) size(maps.VFS_raw,2)], 'nearest');
maps.VFS_raw(~vfsMask)        = NaN;
maps.VFS_processed(~vfsMask)  = NaN;
maps.VFS_boundaries(~vfsMask) = 0;

save(fullfile(matFolder, 'signmap_results.mat'), 'maps', 'azi', 'alt', 'k', 'mask_map', '-v7.3');

sm.saveSignMaps(maps);   % Save SignMapper outputs into signMapFolder
sm.exportSignMaps(maps); % Export overlay image into signMapFolder

cd(oldFolder);
fprintf('Finished. All outputs saved under:\n%s\n', outputRoot);
