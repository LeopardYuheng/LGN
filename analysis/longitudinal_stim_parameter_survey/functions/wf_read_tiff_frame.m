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
