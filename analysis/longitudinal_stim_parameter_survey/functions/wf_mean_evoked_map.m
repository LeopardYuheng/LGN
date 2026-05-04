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