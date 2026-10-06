function out = wf_output_dir(e, mode, customRoot, cfg)
%WF_OUTPUT_DIR  Where one experiment's results should be written.
%
%   out = WF_OUTPUT_DIR(e, mode, customRoot, cfg)
%
% mode
%   'result_root'  a folder named {SUBJECT}_{MMDDYYYY} under cfg.output_root
%                  e.g. C:\Projects\LGN\WF_result\LGN24_08272026
%   'with_data'    a new folder inside the experiment's own folder on the
%                  portable disk, named {SUBJECT}_{MMDDYYYY}_analysis:
%                  E:\Yuheng_LGN\LGN24_08212026_postblind_WFimage\
%                      LGN24_08212026_analysis\
%                  The suffix comes from cfg.output_with_data_suffix; set it
%                  empty to write into the experiment folder itself.
%   'custom'       a folder named {SUBJECT}_{MMDDYYYY} under customRoot
%   'ask'          treated as 'result_root' here; the confirmation screen is
%                  what actually asks
%
% Results written next to the data go in their own named folder rather than
% loose in the experiment folder, so the raw img\ and ephys\ folders stay
% untouched and it is obvious at a glance which analysis a folder belongs to.

if nargin < 4 || isempty(cfg), cfg = wf_config(); end
if nargin < 3, customRoot = ''; end
if nargin < 2 || isempty(mode), mode = 'result_root'; end

name = sprintf('%s_%s', e.subject, wf_mdy(e.date));

switch lower(mode)

    case 'with_data'
        base = '';
        if isfield(e, 'data_dir'), base = e.data_dir; end
        if isempty(base)
            % No known data folder: fall back rather than write somewhere
            % unexpected.
            out = fullfile(cfg.output_root, name);
            return;
        end
        suffix = '_analysis';
        if isfield(cfg, 'output_with_data_suffix')
            suffix = cfg.output_with_data_suffix;
        end
        if isempty(suffix)
            out = base;                      % straight into the data folder
        else
            out = fullfile(base, [name suffix]);
        end

    case 'custom'
        if isempty(customRoot)
            out = fullfile(cfg.output_root, name);
        else
            out = fullfile(customRoot, name);
        end

    otherwise      % 'result_root' and 'ask'
        out = fullfile(cfg.output_root, name);
end

end

% =====================================================================
function s = wf_mdy(ymd)
%WF_MDY  20260827 -> 08272026, matching the existing WF_result folders.

if numel(ymd) == 8
    s = [ymd(5:6) ymd(7:8) ymd(1:4)];
else
    s = ymd;
end

end
