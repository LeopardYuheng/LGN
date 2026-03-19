%% retinotopic_mapping_pipeline_reusable_outputs.m
% Retinotopic mapping pipeline with:
%   1) reusable saved output struct
%   2) QC figures
%   3) explicit ReferenceImage saving
%   4) optional V1 mask drawing/saving
%
% Main output:
%   retino_session_output.mat   containing struct "out"
%
% QC outputs:
%   qc/peak_detection.png
%   qc/peak_detection_with_detected_peaks.png
%   qc/trial_length_histogram.png
%   qc/reference_image.png
%   qc/azimuth_map.png
%   qc/elevation_map.png
%   qc/signmap_overlay.png
%   qc/V1_mask_overlay.png
%
% Notes:
% - Keeps your first image as the ReferenceImage
% - Keeps your existing SignMapper workflow
% - Packages outputs for later registration to stimulation sessions

%% Clear Environment and Add Paths
close all;
clear;
clc;
addpath(genpath('\\10.129.151.108\xieluanlabs\xl_LGN\LGN_ALBERT\LGN imaging\code_wf+stim_+old_code\Data_processing_Xiaorong'));

%% -------------------- USER SETTINGS --------------------
DRAW_V1_MASK = true;              % draw V1 mask at end if not already available
SAVE_AVERAGE_VIDEOS = true;       % save mp4 videos of averaged responses
PEAK_MIN_HEIGHT = -3.5;
PEAK_MIN_DISTANCE = 70000;
BASELINE_SECONDS = 2;             % seconds before on period
ORIENTATION_ORDER = {'azi_f','azi_b','alt_u','alt_d'};  % assumed trial order

%% -------------------- SELECT INPUT / OUTPUT FOLDERS --------------------
% Folder containing RHD files
rhdFolder = uigetdir(pwd, 'Select folder containing Intan .rhd files');
if isequal(rhdFolder,0)
    error('No RHD folder selected.');
end

% Folder containing widefield images
imgFolder = uigetdir(pwd, 'Select folder containing imaging .tif files');
if isequal(imgFolder,0)
    error('No image folder selected.');
end

% Output folder
saveFolder = uigetdir(pwd, 'Select folder where outputs should be saved');
if isequal(saveFolder,0)
    error('No output folder selected.');
end

if ~exist(saveFolder,'dir')
    mkdir(saveFolder);
end

qcDir = fullfile(saveFolder,'qc');
if ~exist(qcDir,'dir')
    mkdir(qcDir);
end
%% -------------------- LOAD STIMULUS DATA --------------------
[fn, fp] = uigetfile('*.mat', 'Select the Stimulus Data MAT File');
if isequal(fn,0)
    error('No stimulus MAT file selected.');
end
stimMatPath = fullfile(fp, fn);
load(stimMatPath);

assert(exist('Stimdata','var')==1, 'Stimdata variable not found in selected MAT file.');

%% -------------------- LOAD INTAN RHD DATA --------------------
DIR = dir(fullfile(rhdFolder,'*.rhd'));
assert(~isempty(DIR), 'No .rhd files found in current folder.');

numFiles = numel(DIR);
recFile = cell(1, numFiles);
tIntan  = cell(1, numFiles);

for i = 1:numFiles
    read_Intan_RHD2000_fileV3(fullfile(rhdFolder, DIR(i).name), []);
    recFile{1, i} = board_dig_in_data;
    tIntan{1, i}  = t_dig;
end

recFile = cat(2, recFile{:});
save(fullfile(saveFolder, 'DIN.mat'), 'recFile', 'tIntan', 'frequency_parameters', '-v7.3');

Fs = frequency_parameters.amplifier_sample_rate;

%% -------------------- PROCESS PHOTODIODE PULSES --------------------
t_rising_edge_diode = find(diff(recFile(1, :)) > 0);
inter_pulse_interval_diode = diff(t_rising_edge_diode);

pd_t = t_rising_edge_diode(1:end-1);
pd   = -inter_pulse_interval_diode;

fig1 = figure('Color','w');
plot(pd_t, pd, 'b', 'LineWidth', 1);
title('Original Signal');
xlabel('Time (samples)');
ylabel('Amplitude');
grid on;
saveas(fig1, fullfile(qcDir, 'peak_detection.png'));

[pks, locs] = findpeaks(pd, pd_t, ...
    'MinPeakHeight', PEAK_MIN_HEIGHT, ...
    'MinPeakDistance', PEAK_MIN_DISTANCE);

fig2 = figure('Color','w');
plot(pd_t, pd, 'b-'); hold on;
plot(locs, pks, 'ro', 'MarkerFaceColor', 'r');
ylabel('Amplitude');
xlabel('Time (samples)');
title(sprintf('Detected Peaks (n = %d)', length(pks)));
grid on;
saveas(fig2, fullfile(qcDir, 'peak_detection_with_detected_peaks.png'));

disp(['Number of peaks detected: ', num2str(length(pks))]);
save(fullfile(saveFolder, 'peaks.mat'), 'locs', 'pks');

%% -------------------- DEFINE TRIALS --------------------
TrialsStart = locs(1:2:end);
TrialsEnd   = locs(2:2:end);

numTrials = numel(TrialsStart);
assert(numTrials > 0, 'No trials detected.');
assert(mod(numTrials,4)==0, 'Number of detected trials is not divisible by 4. Check trial parsing/order.');

peakIntervals = diff(TrialsStart) / Fs;

fig3 = figure('Color','w');
histogram(peakIntervals, 'BinWidth', 0.002);
xlabel('Interval between Peaks (s)');
ylabel('Frequency');
title('Distribution of Trial Length');
grid on;
saveas(fig3, fullfile(qcDir, 'trial_length_histogram.png'));



%% -------------------- CAMERA TRIGGERS --------------------
camera_diff    = diff(recFile(2, :));
camera_rising  = find(camera_diff > 0);
camera_falling = find(camera_diff < 0);
camera_indicator = camera_falling;

camera_sampling_rate = round(1 / (mean(diff(camera_rising)) / Fs));
disp(['Camera sampling rate: ', num2str(camera_sampling_rate)]);

num_rising_edges = length(camera_indicator);
disp(['Number of camera edges: ', num2str(num_rising_edges)]);

%% -------------------- LOAD IMAGE FILES --------------------
image_files = dir(fullfile(imgFolder, '*.tif'));
nFiles = numel(image_files);
assert(nFiles > 0, 'No tif images found in selected image folder.');

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
    disp('Camera edge count and image count match.');
else
    warning('Mismatch between camera edges (%d) and image count (%d).', num_rising_edges, n_images);
    response = questdlg('Camera edge and image count mismatch. Continue anyway?', ...
        'Mismatch Warning', 'Yes', 'No', 'No');
    if strcmp(response, 'No')
        error('User stopped due to image/trigger mismatch.');
    end
end

%% -------------------- COMPUTE ON/OFF INDICES --------------------
on_time   = Stimdata.on_time;
on_frames = round(on_time * camera_sampling_rate);

on_indices_trial  = cell(numTrials, 1);
off_indices_trial = cell(numTrials, 1);

for i = 1:numTrials
    onIndex = find(camera_indicator > TrialsStart(i));
    assert(~isempty(onIndex), 'Could not find camera index after trial start for trial %d.', i);
    onStartIndex = onIndex(1);
    on_indices_trial{i} = onStartIndex : (onStartIndex + on_frames - 1);
end

off_frames = round(BASELINE_SECONDS * camera_sampling_rate);

for i = 1:numTrials
    onStartIndex = on_indices_trial{i}(1);
    off_indices_trial{i} = (onStartIndex - off_frames) : (onStartIndex - 1);

    if off_indices_trial{i}(1) < 1
        error('Off-period for trial %d goes below frame 1. Increase pre-roll or inspect triggers.', i);
    end
    if on_indices_trial{i}(end) > n_images
        error('On-period for trial %d exceeds available image count.', i);
    end
end

%% -------------------- REFERENCE IMAGE --------------------
firstFile = image_files(end);
refPath = fullfile(firstFile.folder, firstFile.name);
ReferenceImage = imread(refPath);

info = imfinfo(refPath);
width  = info(1).Width;
height = info(1).Height;
fprintf('Image size is %d (height) x %d (width)\n', height, width);

figRef = figure('Color','w');
imagesc(ReferenceImage); axis image off; colormap gray;
title('Reference Image');
saveas(figRef, fullfile(qcDir, 'reference_image.png'));

%% -------------------- SEPARATE ORIENTATIONS --------------------
repeats = numTrials / 4;

dims_on  = [height, width, on_frames, repeats];
dims_off = [height, width, off_frames, repeats];

azi_on_f = zeros(dims_on,  'single');
azi_on_b = zeros(dims_on,  'single');
alt_on_u = zeros(dims_on,  'single');
alt_on_d = zeros(dims_on,  'single');

azi_off_f = zeros(dims_off, 'single');
azi_off_b = zeros(dims_off, 'single');
alt_off_u = zeros(dims_off, 'single');
alt_off_d = zeros(dims_off, 'single');

%% -------------------- LOAD ON-PERIOD IMAGES --------------------
disp('Loading ON-period images...');

parfor rep = 1:repeats
    trial_front = 4*(rep - 1) + 1;
    trial_back  = 4*(rep - 1) + 2;
    trial_up    = 4*(rep - 1) + 3;
    trial_down  = 4*(rep - 1) + 4;

    idxF = on_indices_trial{trial_front};
    idxB = on_indices_trial{trial_back};
    idxU = on_indices_trial{trial_up};
    idxD = on_indices_trial{trial_down};

    tmp_on_f = zeros(height, width, on_frames, 'single');
    tmp_on_b = zeros(height, width, on_frames, 'single');
    tmp_on_u = zeros(height, width, on_frames, 'single');
    tmp_on_d = zeros(height, width, on_frames, 'single');

    for f = 1:on_frames
        tmp_on_f(:, :, f) = single(imread(fullfile(image_files(idxF(f)).folder, image_files(idxF(f)).name)));
        tmp_on_b(:, :, f) = single(imread(fullfile(image_files(idxB(f)).folder, image_files(idxB(f)).name)));
        tmp_on_u(:, :, f) = single(imread(fullfile(image_files(idxU(f)).folder, image_files(idxU(f)).name)));
        tmp_on_d(:, :, f) = single(imread(fullfile(image_files(idxD(f)).folder, image_files(idxD(f)).name)));
    end

    azi_on_f(:, :, :, rep) = tmp_on_f;
    azi_on_b(:, :, :, rep) = tmp_on_b;
    alt_on_u(:, :, :, rep) = tmp_on_u;
    alt_on_d(:, :, :, rep) = tmp_on_d;
end

%% -------------------- LOAD OFF-PERIOD IMAGES --------------------
disp('Loading OFF-period images...');

parfor rep = 1:repeats
    trial_front = 4*(rep - 1) + 1;
    trial_back  = 4*(rep - 1) + 2;
    trial_up    = 4*(rep - 1) + 3;
    trial_down  = 4*(rep - 1) + 4;

    off_idxF = off_indices_trial{trial_front};
    off_idxB = off_indices_trial{trial_back};
    off_idxU = off_indices_trial{trial_up};
    off_idxD = off_indices_trial{trial_down};

    tmp_off_f = zeros(height, width, off_frames, 'single');
    tmp_off_b = zeros(height, width, off_frames, 'single');
    tmp_off_u = zeros(height, width, off_frames, 'single');
    tmp_off_d = zeros(height, width, off_frames, 'single');

    for f = 1:off_frames
        tmp_off_f(:, :, f) = single(imread(fullfile(image_files(off_idxF(f)).folder, image_files(off_idxF(f)).name)));
        tmp_off_b(:, :, f) = single(imread(fullfile(image_files(off_idxB(f)).folder, image_files(off_idxB(f)).name)));
        tmp_off_u(:, :, f) = single(imread(fullfile(image_files(off_idxU(f)).folder, image_files(off_idxU(f)).name)));
        tmp_off_d(:, :, f) = single(imread(fullfile(image_files(off_idxD(f)).folder, image_files(off_idxD(f)).name)));
    end

    azi_off_f(:, :, :, rep) = tmp_off_f;
    azi_off_b(:, :, :, rep) = tmp_off_b;
    alt_off_u(:, :, :, rep) = tmp_off_u;
    alt_off_d(:, :, :, rep) = tmp_off_d;
end

disp('Images loaded.');

%% -------------------- BASELINE SUBTRACT + AVERAGE --------------------
disp('Baseline subtracting and averaging over repeats...');

m_azi_off_f = squeeze(mean(azi_off_f, 3));
m_azi_off_b = squeeze(mean(azi_off_b, 3));
m_alt_off_u = squeeze(mean(alt_off_u, 3));
m_alt_off_d = squeeze(mean(alt_off_d, 3));

azi_f_avg = zeros(height, width, on_frames, 'single');
azi_b_avg = zeros(height, width, on_frames, 'single');
alt_u_avg = zeros(height, width, on_frames, 'single');
alt_d_avg = zeros(height, width, on_frames, 'single');

for rep = 1:repeats
    azi_f_avg = azi_f_avg + (azi_on_f(:,:,:,rep) - m_azi_off_f(:,:,rep));
    azi_b_avg = azi_b_avg + (azi_on_b(:,:,:,rep) - m_azi_off_b(:,:,rep));
    alt_u_avg = alt_u_avg + (alt_on_u(:,:,:,rep) - m_alt_off_u(:,:,rep));
    alt_d_avg = alt_d_avg + (alt_on_d(:,:,:,rep) - m_alt_off_d(:,:,rep));
end

azi_f_avg = azi_f_avg / repeats;
azi_b_avg = azi_b_avg / repeats;
alt_u_avg = alt_u_avg / repeats;
alt_d_avg = alt_d_avg / repeats;

save(fullfile(saveFolder, 'averaged_responses.mat'), ...
    'azi_f_avg', 'azi_b_avg', 'alt_u_avg', 'alt_d_avg', '-v7.3');

%% -------------------- OPTIONAL: SAVE AVERAGED RESPONSE VIDEOS --------------------
if SAVE_AVERAGE_VIDEOS
    averagedVideos = {azi_f_avg, azi_b_avg, alt_u_avg, alt_d_avg};
    videoNames = {'azi_f_avg_video.mp4', 'azi_b_avg_video.mp4', ...
                  'alt_u_avg_video.mp4', 'alt_d_avg_video.mp4'};

    for v = 1:length(averagedVideos)
        writerObj = VideoWriter(fullfile(saveFolder, videoNames{v}), 'MPEG-4');
        writerObj.FrameRate = camera_sampling_rate;
        open(writerObj);

        currentAvg = averagedVideos{v};
        for kf = 1:size(currentAvg, 3)
            frame = im2uint8(mat2gray(currentAvg(:,:,kf)));
            writeVideo(writerObj, frame);
        end
        close(writerObj);
        fprintf('Saved video %s\n', videoNames{v});
    end
end

%% -------------------- FOURIER DATA --------------------
T = on_time;
f_target = 1 / T; %#ok<NASGU>

fft_azi_f = fft(azi_f_avg, [], 3);
fft_azi_b = fft(azi_b_avg, [], 3);
fft_alt_u = fft(alt_u_avg, [], 3);
fft_alt_d = fft(alt_d_avg, [], 3);

fourier_data = zeros(height, width, on_frames, 4, 'like', fft_azi_f);
fourier_data(:,:,:,1) = fft_azi_f;
fourier_data(:,:,:,2) = fft_azi_b;
fourier_data(:,:,:,3) = fft_alt_u;
fourier_data(:,:,:,4) = fft_alt_d;

save(fullfile(saveFolder, 'processing_data.mat'), 'fourier_data', '-v7.3');

%% -------------------- RETINOTOPY MAPS --------------------
sm = SignMapperModifR();
sm.ref_img = ReferenceImage;

figRef2 = figure('Color','w');
imagesc(ReferenceImage); axis image; colormap gray;
title('Reference Image');
saveas(figRef2, fullfile(qcDir, 'reference_image_signmapper.png'));

k = sm.findRetinotopicMap(fourier_data);
[azi, alt] = sm.getRetinotopicMap(fourier_data, k);

figAziAlt = figure('Color','w');
sm.displayMaps(azi, alt);
saveas(figAziAlt, fullfile(qcDir, 'azimuth_elevation_maps.png'));

save(fullfile(saveFolder, 'azi.mat'), 'azi', '-v7.3', '-nocompression');
save(fullfile(saveFolder, 'alt.mat'), 'alt', '-v7.3', '-nocompression');

while true
    goodmap = questdlg('Do your maps look good?', 'Map quality', 'Yes', 'No', 'Yes');
    close(gcf);

    switch goodmap
        case 'No'
            k = sm.manualFindRetinotopicMap(fourier_data);
            [azi, alt] = sm.getRetinotopicMap(fourier_data, k);
            figAziAlt = figure('Color','w');
            sm.displayMaps(azi, alt);
            saveas(figAziAlt, fullfile(qcDir, 'azimuth_elevation_maps_manual_selection.png'));
        case 'Yes'
            break
    end
end

%% -------------------- SIGN MAPS --------------------
maps = sm.Juavinett2017_signMapping(azi, alt);
ReferenceImage = maps.ReferenceImage;

mkdir(fullfile(saveFolder, 'AdditionalSignMapMaterials'));
sm.saveSignMaps(maps);
sm.exportSignMaps(maps);

% Attempt to save common outputs from maps struct if fields exist
VFS_processed  = [];
VFS_boundaries = [];
if isfield(maps, 'VFS_processed')
    VFS_processed = maps.VFS_processed;
end
if isfield(maps, 'VFS_boundaries')
    VFS_boundaries = maps.VFS_boundaries;
end
%% -------------------- QC FIGURES FROM SIGNMAPPER OUTPUTS --------------------
figAzi = figure('Color','w');
imagesc(azi); axis image off; colorbar;
title('Azimuth Map');
saveas(figAzi, fullfile(qcDir, 'azimuth_map.png'));

figAlt = figure('Color','w');
imagesc(alt); axis image off; colorbar;
title('Elevation Map');
saveas(figAlt, fullfile(qcDir, 'elevation_map.png'));

% Try to save the SignMapper-produced overlay directly if available
if isfield(maps, 'VFS_processed') && ~isempty(maps.VFS_processed)
    figSign = figure('Color','w');
    imshow(maps.VFS_processed, []);
    title('SignMapper Overlay');
    saveas(figSign, fullfile(qcDir, 'signmap_overlay.png'));
elseif isfield(maps, 'VFS_boundaries') && ~isempty(maps.VFS_boundaries)
    figSign = figure('Color','w');
    imshow(maps.VFS_boundaries, []);
    title('SignMapper Boundaries');
    saveas(figSign, fullfile(qcDir, 'signmap_overlay.png'));
end
%% -------------------- OPTIONAL V1 MASK --------------------

V1_mask_retino = [];

if DRAW_V1_MASK
    v1MaskPath = fullfile(saveFolder, 'V1_mask_retino.mat');

    if exist(v1MaskPath, 'file') == 2
        tmp = load(v1MaskPath);
        if isfield(tmp, 'V1_mask_retino')
            V1_mask_retino = tmp.V1_mask_retino;
        end
    end

    if isempty(V1_mask_retino)
        figDraw = figure('Name','Draw V1 Mask','Color','w');
        imshow(mat2gray(maps.ReferenceImage), []);
        hold on;

        if isfield(maps,'VFS_boundaries') && ~isempty(maps.VFS_boundaries)
            visboundaries(maps.VFS_boundaries > 0, 'Color', 'r', 'LineWidth', 1);
            title('Reference + SignMapper boundaries. Draw polygon around V1.');
        elseif isfield(maps,'VFS_processed') && ~isempty(maps.VFS_processed)
            ovDisp = makeOverlayForDisplay(maps.VFS_processed);
            h = imshow(ovDisp);
            set(h,'AlphaData',0.35);
            title('Reference + SignMapper overlay. Draw polygon around V1.');
        else
            title('Reference image. Draw polygon around V1.');
        end

        axis image;
        hpoly = drawpolygon('Color','y','LineWidth',2);
        wait(hpoly);

        V1_mask_retino = poly2mask( ...
            hpoly.Position(:,1), ...
            hpoly.Position(:,2), ...
            size(maps.ReferenceImage,1), ...
            size(maps.ReferenceImage,2));

        save(v1MaskPath, 'V1_mask_retino');
        close(figDraw);
    end

    figV1 = figure('Color','w');
    imshow(mat2gray(maps.ReferenceImage), []);
    hold on;
    visboundaries(V1_mask_retino, 'Color', 'y', 'LineWidth', 1.5);
    title('V1 Mask on Reference Image');
    axis image;
    saveas(figV1, fullfile(qcDir, 'V1_mask_overlay.png'));
end

%% -------------------- BUILD CONSOLIDATED OUTPUT STRUCT --------------------
out = struct();

% Core reusable outputs
out.ReferenceImage = ReferenceImage;
out.azi = azi;
out.alt = alt;
out.k = k;
out.maps = maps;
out.VFS_processed = VFS_processed;
out.VFS_boundaries = VFS_boundaries;
out.V1_mask_retino = V1_mask_retino;

% Trial / timing metadata
out.TrialsStart = TrialsStart;
out.TrialsEnd = TrialsEnd;
out.numTrials = numTrials;
out.repeats = repeats;
out.on_indices_trial = on_indices_trial;
out.off_indices_trial = off_indices_trial;
out.on_time = on_time;
out.on_frames = on_frames;
out.off_frames = off_frames;
out.baseline_seconds = BASELINE_SECONDS;
out.camera_sampling_rate = camera_sampling_rate;
out.intan_sampling_rate = Fs;
out.orientation_order = ORIENTATION_ORDER;

% Image / source metadata
out.image_height = height;
out.image_width = width;
out.image_folder = imgFolder;
out.stimulus_mat_file = stimMatPath;
out.image_filenames = {image_files.name};

% Averaged responses / Fourier data
out.azi_f_avg = azi_f_avg;
out.azi_b_avg = azi_b_avg;
out.alt_u_avg = alt_u_avg;
out.alt_d_avg = alt_d_avg;
out.fourier_data = fourier_data;

% QC summary fields
out.num_camera_edges = num_rising_edges;
out.num_images = n_images;
out.peak_locs = locs;
out.peak_values = pks;
out.peak_detection_params = struct( ...
    'MinPeakHeight', PEAK_MIN_HEIGHT, ...
    'MinPeakDistance', PEAK_MIN_DISTANCE);

save(fullfile(saveFolder, 'retino_session_output.mat'), 'out', '-v7.3');

%% -------------------- SAVE A LIGHTWEIGHT REGISTRATION FILE --------------------
registration_ready = struct();
registration_ready.ReferenceImage = ReferenceImage;
registration_ready.V1_mask_retino = V1_mask_retino;
registration_ready.azi = azi;
registration_ready.alt = alt;
registration_ready.maps = maps;
registration_ready.VFS_processed = VFS_processed;
registration_ready.VFS_boundaries = VFS_boundaries;
registration_ready.k = k;

save(fullfile(saveFolder, 'retino_registration_ready.mat'), 'registration_ready', '-v7.3');

fprintf('\nDone.\n');
fprintf('Saved consolidated output: %s\n', fullfile(saveFolder, 'retino_session_output.mat'));
fprintf('Saved registration-ready output: %s\n', fullfile(saveFolder, 'retino_registration_ready.mat'));
fprintf('Saved QC figures in: %s\n', qcDir);

%% -------------------- LOCAL FUNCTION --------------------
function ovDisp = makeOverlayForDisplay(ov)
    if isempty(ov)
        ovDisp = [];
        return;
    end
    if ndims(ov)==2
        ovDisp = repmat(mat2gray(ov), 1,1,3);
    elseif ndims(ov)==3 && size(ov,3)==3
        ovDisp = mat2gray(ov);
    else
        ovDisp = repmat(mat2gray(ov(:,:,1)), 1,1,3);
    end
end


