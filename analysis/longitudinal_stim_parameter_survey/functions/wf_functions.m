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


function img = wf_read_tiff_frame(img_dir, files, frame_idx, crop_rect)
%WF_READ_TIFF_FRAME Read one TIFF frame by index (1-based into files array).
% crop_rect can be [] or [x y w h].

    assert(frame_idx >= 1 && frame_idx <= numel(files), 'frame_idx out of range.');
    img = imread(fullfile(img_dir, files(frame_idx).name));
    if ~isempty(crop_rect)
        img = imcrop(img, crop_rect);
    end
    img = single(img);
end


function trial_map = wf_trial_evoked_map(onset_frame_idx, img_dir, files, crop_rect, ...
    preFrames, postFrames, base_idx, resp_idx, analysis_mask)
%WF_TRIAL_EVOKED_MAP Build a single trial evoked map (resp-win averaged ΔF/F map).
%
% onset_frame_idx : onset frame index (1-based into TIFF sequence)
% preFrames/postFrames define window [f0-preFrames : f0+postFrames]
% base_idx, resp_idx are indices in the trial window (1..L)
% analysis_mask (HxW logical) is applied as NaN outside.

    f0 = double(onset_frame_idx);
    L = preFrames + postFrames + 1;

    f_start = f0 - preFrames;
    f_end   = f0 + postFrames;

    if f_start < 1 || f_end > numel(files)
        trial_map = [];
        return;
    end

    % Read first frame to get dims quickly
    img0 = wf_read_tiff_frame(img_dir, files, f_start, crop_rect);
    [H,W] = size(img0);

    movie = zeros(H,W,L,'single');

    kk = 0;
    for f = f_start:f_end
        kk = kk + 1;
        movie(:,:,kk) = wf_read_tiff_frame(img_dir, files, f, crop_rect);
    end

    F0  = mean(movie(:,:,base_idx), 3);
    dff = (movie - F0) ./ F0;

    % Mask outside analysis ROI
    for k = 1:L
        frame = dff(:,:,k);
        frame(~analysis_mask) = NaN;
        dff(:,:,k) = frame;
    end

    trial_map = mean(dff(:,:,resp_idx), 3, 'omitnan');
end


function mean_map = wf_mean_evoked_map(onset_frames, img_dir, files, crop_rect, ...
    preFrames, postFrames, base_idx, resp_idx, analysis_mask)
%WF_MEAN_EVOKED_MAP Mean of trial evoked maps across multiple onset frames.
% Skips trials that are out-of-bounds.

    onset_frames = double(onset_frames(:));
    assert(~isempty(onset_frames), 'No onset frames provided.');

    % Determine H,W from first readable onset (or from first file)
    % We'll just use the first file for dims.
    img1 = wf_read_tiff_frame(img_dir, files, 1, crop_rect);
    [H,W] = size(img1);

    acc = zeros(H,W,'double');
    n_ok = 0;

    for i = 1:numel(onset_frames)
        tm = wf_trial_evoked_map(onset_frames(i), img_dir, files, crop_rect, ...
            preFrames, postFrames, base_idx, resp_idx, analysis_mask);
        if isempty(tm), continue; end
        acc = acc + double(tm);
        n_ok = n_ok + 1;
    end

    assert(n_ok > 0, 'All trials were out-of-bounds when building mean evoked map.');
    mean_map = acc / n_ok;
end