function files = wf_sort_tiffs(img_dir)
%WF_SORT_TIFFS Sort .tif files in img_dir by trailing numeric index.
% Returns dir() struct array sorted in ascending order.

    files = dir(fullfile(img_dir, '*.tif'));
    assert(~isempty(files), 'No .tif files found in %s', img_dir);

    n = numel(files);
    nums = nan(n,1);
    for i = 1:n
        tok = regexp(files(i).name, '(\d+)\.tif$', 'tokens', 'once');
        assert(~isempty(tok), 'Filename "%s" has no trailing numeric index.', files(i).name);
        nums(i) = str2double(tok{1});
    end

    [~, ord] = sort(nums);
    files = files(ord);
end
