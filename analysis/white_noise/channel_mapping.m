clc; clear;

%% Load channelmap file
C = load('C:\Albert Li\LGN\Data\white_noise\02-06-2026-WN\02-06-2026-WN_260206_113817\channelmap.mat');

%% Load Intan -> Ripple mapping file
M = load('C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_channel_mapping\Map_Intan2Ripple.mat');

%% Load Phy CSV
T = readtable('C:\Albert Li\LGN\Data\white_noise\02-06-2026-WN\LGN11_WN_cluster_metrics.csv');

%% Extract variables
chanMap = C.chanMap;

% Adjust this variable name if needed based on what is actually in the mat file
intan_to_Ripple = M.Intan_to_Ripple;

%% Get phy channel indices
phy_ch = T.ch;   % Phy channel column, usually 0-based

%% Convert Phy channel -> Intan channel
intan_ch = chanMap(phy_ch + 1);

%% If chanMap is 0-based, convert to MATLAB 1-based before Ripple lookup
if min(chanMap) == 0
    intan_ch = intan_ch + 1;
end

%% Convert Intan channel -> Ripple channel
ripple_ch = intan_to_Ripple(intan_ch);

%% Add to table
T.intan_ch = intan_ch;
T.ripple_ch = ripple_ch;

%% Save updated table
writetable(T, 'C:\Albert Li\LGN\Data\white_noise\02-06-2026-WN\02-06-2026-WN_260206_113817\cluster_info_with_ripple.csv');

disp(T(1:min(10,height(T)), :))

%% Save table as CSV
output_file = 'C:\Albert Li\LGN\Data\white_noise\02-06-2026-WN\02-06-2026-WN_260206_113817\cluster_info_with_ripple.csv';

writetable(T, output_file);

fprintf('Saved CSV to:\n%s\n', output_file);