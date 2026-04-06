%%
addpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Yuxuan_NEW\Summation-since20230612\EPhys-Data\2024 Analysis Code\scripts_self_modified\util\neuroshare/');


%%
[file_name, save_path] = uigetfile('*.nev', 'Select a MATLAB file');

[~, hFile_nev] = ns_OpenFile(fullfile(save_path, file_name)); 

%%
labels = {hFile_nev.Entity.Label}; 
allElectrodeID = [hFile_nev.Entity.ElectrodeID]; 
stim_idxs = find(cellfun(@(s) contains(s,'stim'), labels)==1);

%%
% Read stimulation times 
all_stim_times = double(hFile_nev.FileInfo(1).MemoryMap.Data.TimeStamp);
packetIDs = double(hFile_nev.FileInfo(1).MemoryMap.Data.PacketID);
mask = packetIDs > 5120;
stim_times = all_stim_times(mask);
packetIDs = packetIDs(packetIDs > 5120) - 5120;

stim_ids = allElectrodeID(stim_idxs);
stim_chs = double(stim_ids - 5120);
nSCH = numel(stim_chs);

% Returns cell array with first column being the stimulation channel and 
% the second column containing all the timestamps for that stimulation
% channel 
stim_times_arr = cell(nSCH,2);
for i = 1:nSCH
    stim_times_arr{i,1} = stim_chs(i);
    stim_times_arr{i,2} = stim_times(packetIDs == stim_chs(i));
end

save(fullfile(save_path,'stim_times_arr.mat'), 'stim_times_arr');