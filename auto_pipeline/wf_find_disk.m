function root = wf_find_disk(cfg)
%WF_FIND_DISK  Locate the portable disk holding the imaging sessions.
%
%   root = WF_FIND_DISK(cfg)
%
% Returns '' when nothing suitable is connected. A drive qualifies if it is
% mounted and contains at least one folder full of numbered TIFFs within
% cfg.scan_max_depth levels - so a random USB stick is not mistaken for the
% imaging disk.

if nargin < 1 || isempty(cfg), cfg = wf_config(); end

root = '';

if ~isempty(cfg.disk_root)
    if exist(cfg.disk_root, 'dir') == 7
        root = cfg.disk_root;
    else
        wf_log('Configured disk_root "%s" is not available.', cfg.disk_root);
    end
    return;
end

for i = 1:numel(cfg.disk_search_letters)
    d = cfg.disk_search_letters{i};
    if exist(d, 'dir') ~= 7, continue; end

    scanRoot = d;
    if ~isempty(cfg.disk_subfolder)
        scanRoot = fullfile(d, cfg.disk_subfolder);
        if exist(scanRoot, 'dir') ~= 7, continue; end
    end

    if wf_has_tiff_folder(scanRoot, cfg.min_tiffs, cfg.scan_max_depth)
        root = d;
        return;
    end
end

end

% =====================================================================
function tf = wf_has_tiff_folder(root, minTiffs, depth)
%WF_HAS_TIFF_FOLDER  Stop at the first folder that looks like image data.

tf = false;
if depth < 0 || exist(root, 'dir') ~= 7, return; end

if numel(dir(fullfile(root, '*.tif'))) >= minTiffs || ...
   numel(dir(fullfile(root, '*.tiff'))) >= minTiffs
    tf = true;
    return;
end

listing = dir(root);
listing = listing([listing.isdir]);
for i = 1:numel(listing)
    n = listing(i).name;
    if any(strcmp(n, {'.', '..'})) || strncmp(n, '$', 1), continue; end
    if wf_has_tiff_folder(fullfile(root, n), minTiffs, depth - 1)
        tf = true;
        return;
    end
end

end
