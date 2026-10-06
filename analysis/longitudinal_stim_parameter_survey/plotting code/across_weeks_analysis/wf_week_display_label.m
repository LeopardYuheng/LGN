function lbl = wf_week_display_label(week_index)
%WF_WEEK_DISPLAY_LABEL  Spelled-out week label for figures.
%
%   lbl = wf_week_display_label(week_index)
%
% wf_scan_longitudinal uses the compact "pre W4" / "post W5" form internally.
% Figures spell it out — "pre week 4", "post week 5" — so slides read
% properly. Keep display wording here so every figure agrees.
%
% Remember week_index is the TRUE relative week: LGN24's high-current
% session is post week 6, LGN26's is post week 5, though both live in a
% folder named postblind_WEEK5.

if week_index < 0
    lbl = sprintf('pre week %d', week_index + 5);
else
    lbl = sprintf('post week %d', week_index);
end
end
