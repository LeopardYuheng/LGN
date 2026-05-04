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