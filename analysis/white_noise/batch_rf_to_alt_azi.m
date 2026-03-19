clc; clear; close all;

%% -------------------------
% USER SETTINGS
% -------------------------
mat_folder = uigetdir(pwd, 'Select folder containing unit_*_results.mat files');
if isequal(mat_folder, 0)
    error('No RF folder selected.');
end

% csv_file = uigetfile('*.csv', 'Select CSV containing ripple channel info');
% if isequal(csv_file, 0)
%     error('No CSV selected.');
% end
% [csv_name, csv_path] = deal(csv_file, fileparts(fullfile(pwd, csv_file)));
% if isempty(csv_path)
%     [csv_name, csv_path] = uigetfile('*.csv', 'Select CSV containing ripple channel info');
% end

% If above path handling is awkward on your setup, replace with a fixed path:
csv_fullpath = 'C:\Albert Li\LGN\Data\white_noise\02-06-2026-WN\02-06-2026-WN_260206_113817\cluster_info_with_ripple.csv';
% csv_fullpath = fullfile(csv_path, csv_name);

screenWidth_cm  = 59.7;
screenHeight_cm = 33.6;
distance_cm     = 20;

peak_mode = 'abs';          % 'min', 'max', or 'abs'
use_centroid_refine = true;
centroid_radius_px = 2;

label_points = true;        % label each point with ripple channel
marker_size = 70;

%% -------------------------
% SUBSET OPTION
% -------------------------
use_subset = questdlg('Plot all Ripple channels or a selected subset?', ...
    'Channel Selection', ...
    'All', 'Subset', 'All');

selected_ripple_channels = [];
if strcmpi(use_subset, 'Subset')
    answer = inputdlg( ...
        {'Enter Ripple channels to plot (example: [32 45 78] or 32 45 78):'}, ...
        'Subset Ripple Channels', ...
        [1 80], ...
        {''});
    
    if isempty(answer)
        error('Subset selection cancelled.');
    end
    
    selected_ripple_channels = str2num(answer{1}); %#ok<ST2NM>
    if isempty(selected_ripple_channels)
        error('No valid Ripple channels entered.');
    end
end

%% -------------------------
% LOAD CSV
% -------------------------
T = readtable(csv_fullpath);

assert(ismember('ripple_ch', T.Properties.VariableNames), ...
    'CSV must contain a column named "ripple_ch".');

% Try to identify unit column
if ismember('cluster_id', T.Properties.VariableNames)
    unit_ids = T.cluster_id;
elseif ismember('unit_id', T.Properties.VariableNames)
    unit_ids = T.unit_id;
else
    error('CSV must contain either "cluster_id" or "unit_id" to match unit files.');
end

ripple_channels = T.ripple_ch;

%% -------------------------
% FIND RF FILES
% -------------------------
files = dir(fullfile(mat_folder, '*.mat'));
if isempty(files)
    error('No .mat files found in selected RF folder.');
end

results = struct( ...
    'file', {}, ...
    'unit_id', {}, ...
    'ripple_ch', {}, ...
    'peak_row', {}, ...
    'peak_col', {}, ...
    'azimuth_deg', {}, ...
    'altitude_deg', {}, ...
    'peak_value', {} );

%% -------------------------
% PROCESS EACH RF FILE
% -------------------------
for k = 1:numel(files)
    fname = files(k).name;
    fpath = fullfile(files(k).folder, fname);

    % Parse unit ID from file name like "unit_0_results.mat"
    tok = regexp(fname, 'unit_(\d+)_results\.mat$', 'tokens', 'once');
    if isempty(tok)
        warning('Skipping %s: filename does not match unit_<id>_results.mat', fname);
        continue;
    end
    this_unit_id = str2double(tok{1});

    % Match to CSV row
    idx_match = find(unit_ids == this_unit_id, 1);
    if isempty(idx_match)
        warning('Skipping %s: no matching unit ID found in CSV.', fname);
        continue;
    end

    this_ripple_ch = ripple_channels(idx_match);

    % Apply subset filter if requested
    if ~isempty(selected_ripple_channels) && ~ismember(this_ripple_ch, selected_ripple_channels)
        continue;
    end

    S = load(fpath);
    if ~isfield(S, 'RF_spatial')
        warning('Skipping %s: RF_spatial not found.', fname);
        continue;
    end

    RF = S.RF_spatial;
    if ~ismatrix(RF) || isempty(RF)
        warning('Skipping %s: invalid RF_spatial.', fname);
        continue;
    end

    [nRows, nCols] = size(RF);

    %% Build axes in screen cm
    x_cm = linspace(-screenWidth_cm/2, screenWidth_cm/2, nCols+1);
    x_cm = (x_cm(1:end-1) + x_cm(2:end))/2;

    y_cm = linspace(screenHeight_cm/2, -screenHeight_cm/2, nRows+1);
    y_cm = (y_cm(1:end-1) + y_cm(2:end))/2;

    %% Convert to visual angle
    azimuth_axis_deg  = atan2d(x_cm, distance_cm);
    altitude_axis_deg = atan2d(y_cm, distance_cm);

    %% Find peak
    switch lower(peak_mode)
        case 'min'
            [peak_value, idx] = min(RF(:));
        case 'max'
            [peak_value, idx] = max(RF(:));
        case 'abs'
            [~, idx] = max(abs(RF(:)));
            peak_value = RF(idx);
        otherwise
            error('Unknown peak_mode.');
    end

    [peak_row, peak_col] = ind2sub(size(RF), idx);

    %% Optional centroid refinement
    if use_centroid_refine
        r1 = max(1, peak_row - centroid_radius_px);
        r2 = min(nRows, peak_row + centroid_radius_px);
        c1 = max(1, peak_col - centroid_radius_px);
        c2 = min(nCols, peak_col + centroid_radius_px);

        RF_local = RF(r1:r2, c1:c2);

        if peak_value < 0
            W = -RF_local;
        else
            W = RF_local;
        end
        W(W < 0) = 0;

        if any(W(:) > 0)
            [RR, CC] = ndgrid(r1:r2, c1:c2);
            peak_row = sum(RR(:).*W(:)) / sum(W(:));
            peak_col = sum(CC(:).*W(:)) / sum(W(:));
        end
    end

    %% Convert row/col to azimuth/altitude
    azimuth_deg  = interp1(1:nCols, azimuth_axis_deg, peak_col, 'linear', 'extrap');
    altitude_deg = interp1(1:nRows, altitude_axis_deg, peak_row, 'linear', 'extrap');

    %% Store
    results(end+1).file = fname; %#ok<SAGROW>
    results(end).unit_id = this_unit_id;
    results(end).ripple_ch = this_ripple_ch;
    results(end).peak_row = peak_row;
    results(end).peak_col = peak_col;
    results(end).azimuth_deg = azimuth_deg;
    results(end).altitude_deg = altitude_deg;
    results(end).peak_value = peak_value;
end

if isempty(results)
    error('No valid RF files were processed after filtering.');
end

R = struct2table(results);

%% -------------------------
% PLOT AZIMUTH-ALTITUDE SPACE
% -------------------------
figure('Color', 'w');
scatter(R.azimuth_deg, R.altitude_deg, marker_size, 'filled');
xlabel('Azimuth (deg)');
ylabel('Altitude (deg)');
title('RF centers in azimuth-altitude space');
grid on;
axis equal;
hold on;

if label_points
    for i = 1:height(R)
        text(R.azimuth_deg(i) + 0.5, ...
             R.altitude_deg(i), ...
             num2str(R.ripple_ch(i)), ...
             'FontSize', 9);
    end
end

%% -------------------------
% SAVE RESULTS
% -------------------------
out_csv = fullfile(mat_folder, 'rf_centers_azimuth_altitude_ripple.csv');
writetable(R, out_csv);

fprintf('Saved RF center table to:\n%s\n', out_csv);