% combined alt.mat, azi.mat, additional_maps.mat into one input file
retino_dir = '\\10.129.151.108\xieluanlabs\xl_stroke\Xiaorong_PC_OKRData\Mapping\LGN11\LGN11_01162026\retino';

tmp = load(fullfile(retino_dir, 'azi.mat'));           azi = tmp.azi;
tmp = load(fullfile(retino_dir, 'alt.mat'));           alt = tmp.alt;
tmp = load(fullfile(retino_dir, 'additional_maps.mat'));
ReferenceImage  = tmp.maps.ReferenceImage;
VFS_processed   = tmp.maps.VFS_processed;
VFS_boundaries  = tmp.maps.VFS_boundaries;

save(fullfile('C:\Projects\LGN_project\past wide field imaging pipeline and code(before I join)\20260326 experiment on LGN11', 'retino_registration_ready.mat'), ...
    'azi', 'alt', 'ReferenceImage', 'VFS_processed', 'VFS_boundaries', '-v7.3');
disp('Done.')
