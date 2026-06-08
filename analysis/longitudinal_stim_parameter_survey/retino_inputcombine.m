% combined alt.mat, azi.mat, additional_maps.mat into one input file
retino_dir = '\\10.129.151.108\xieluanlabs\xl_stroke\Xiaorong_PC_OKRData\Mapping\LGN11\LGN11_01162026\retino';

tmp = load(fullfile(retino_dir, 'azi.mat'));           azi = tmp.azi;
tmp = load(fullfile(retino_dir, 'alt.mat'));           alt = tmp.alt;
tmp = load(fullfile(retino_dir, 'additional_maps.mat'));
ReferenceImage  = tmp.maps.ReferenceImage;
VFS_processed   = tmp.maps.VFS_processed;
VFS_boundaries  = tmp.maps.VFS_boundaries;

save_dir = uigetdir(pwd, 'Select output folder for retino_registration_ready.mat');
if isequal(save_dir, 0), error('No output folder selected.'); end
save(fullfile(save_dir, 'retino_registration_ready.mat'), ...
    'azi', 'alt', 'ReferenceImage', 'VFS_processed', 'VFS_boundaries', '-v7.3');
disp('Done.')
