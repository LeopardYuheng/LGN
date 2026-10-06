function t = wf_roi_sample_time(mouse, channel)
%WF_ROI_SAMPLE_TIME  Fixed read-out time (s) for a channel's ROI dF/F.
%
%   t = wf_roi_sample_time(mouse, channel)
%
% Figures 2 and 3 report the ROI dF/F at ONE fixed post-stimulus time, not
% the maximum over time. Searching for a per-week maximum would bias the
% comparison: on a week with no response the search finds the largest noise
% excursion instead, which inflates that week's value.
%
% Most channels respond around +0.5 s. Two LGN24 channels peak much earlier,
% so they are read at +0.1 s instead.
%
% Keep this in ONE place: figures 2 and 3 must agree on the read-out time,
% or a channel's contribution to the group average would not match its own
% single-channel figure.

default_time_s = 0.5;

% {mouse, channel, read-out time (s)}
overrides = { ...
    'LGN24',  49, 0.1; ...
    'LGN24',  55, 0.1  ...
};

t = default_time_s;
for i = 1:size(overrides, 1)
    if strcmpi(mouse, overrides{i, 1}) && channel == overrides{i, 2}
        t = overrides{i, 3};
        return;
    end
end
end
