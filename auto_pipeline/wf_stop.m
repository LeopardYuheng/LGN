function out = wf_stop(cmd, arg)
%WF_STOP  Cooperative stop signal for a running pipeline batch.
%
%   wf_stop('arm', outputRoot)   start a run: clear any stale signal
%   wf_stop('request', reason)   ask the run to stop (the GUI's Stop button)
%   tf = wf_stop('check')        has a stop been requested?
%   wf_stop('clear')             forget the signal
%   r  = wf_stop('reason')       why it was stopped
%
% HOW FAR THIS CAN GO
% -------------------
% MATLAB runs the analysis and the interface on one thread, so a button
% click is not seen while a step is inside a loop over TIFF frames. The
% click is queued and handled at the next DRAWNOW, and this flag is then
% checked at every step, session and experiment boundary. In practice that
% means the run stops after the step that is currently going.
%
% To stop immediately, press Ctrl+C in the MATLAB command window. The driver
% catches that and reports it as a clean stop rather than a crash, and
% because finished steps are skipped on the next run, nothing is lost.
%
% The signal lives both in the graphics root's app data and in a sentinel
% file under the output root, so it survives the CLEAR that every pipeline
% script runs on entry.

if nargin < 2, arg = ''; end
out = false;

persistent sentinelFile

switch lower(cmd)

    case 'arm'
        if ~isempty(arg)
            if exist(arg, 'dir') ~= 7, mkdir(arg); end
            sentinelFile = fullfile(arg, '.wf_stop_requested');
        end
        wf_stop('clear');

    case 'request'
        setappdata(0, 'WF_STOP_FLAG',   true);
        setappdata(0, 'WF_STOP_REASON', arg);
        if ~isempty(sentinelFile)
            fid = fopen(sentinelFile, 'w');
            if fid > 2
                fprintf(fid, '%s\r\n', arg);
                fclose(fid);
            end
        end

    case 'check'
        % Flush any queued button clicks before testing, so a Stop pressed
        % during the step that just finished is seen now rather than later.
        drawnow;
        out = isappdata(0, 'WF_STOP_FLAG') && getappdata(0, 'WF_STOP_FLAG');
        if ~out && ~isempty(sentinelFile) && exist(sentinelFile, 'file') == 2
            out = true;
            setappdata(0, 'WF_STOP_FLAG', true);
            setappdata(0, 'WF_STOP_REASON', 'stop file found');
        end

    case 'clear'
        setappdata(0, 'WF_STOP_FLAG',   false);
        setappdata(0, 'WF_STOP_REASON', '');
        if ~isempty(sentinelFile) && exist(sentinelFile, 'file') == 2
            delete(sentinelFile);
        end

    case 'reason'
        if isappdata(0, 'WF_STOP_REASON')
            out = getappdata(0, 'WF_STOP_REASON');
        else
            out = '';
        end

    otherwise
        error('wf_stop:badCommand', 'Unknown command "%s".', cmd);
end

end
