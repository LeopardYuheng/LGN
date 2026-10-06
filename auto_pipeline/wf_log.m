function wf_log(varargin)
%WF_LOG  Timestamped progress line, to the console and to the run log file.
%
%   WF_LOG(fmt, ...)                  write a line
%   WF_LOG('open',  logFilePath)      also append lines to this file
%   WF_LOG('close')                   stop writing to the file
%   WF_LOG('sink',  fcnHandle)        also send lines to a callback, which is
%                                     how the GUI mirrors progress into its
%                                     log pane. Pass [] to remove.
%
% The log file is opened and closed around every single line rather than
% held open. Every pipeline script starts with fclose('all'), which would
% invalidate a long-lived file identifier the first time a step ran.

persistent logPath sink

if nargin == 0, return; end

first = varargin{1};

if ischar(first) && strcmp(first, 'open')
    logPath = varargin{2};
    if isempty(logPath)
        % Empty path means "do not write the file here". Used when DIARY is
        % capturing the console instead, which already records these lines
        % and would otherwise duplicate every one of them.
        return;
    end
    d = fileparts(logPath);
    if ~isempty(d) && exist(d, 'dir') ~= 7, mkdir(d); end
    return;
end

if ischar(first) && strcmp(first, 'close')
    logPath = '';
    return;
end

if ischar(first) && strcmp(first, 'sink')
    sink = varargin{2};
    return;
end

msg  = sprintf(varargin{:});
line = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), msg);

fprintf('%s\n', line);

if ~isempty(logPath)
    fid = fopen(logPath, 'a');
    if fid > 2
        fprintf(fid, '%s\r\n', line);
        fclose(fid);
    end
end

if ~isempty(sink)
    try
        sink(line);
    catch
        % A dead GUI must never take the analysis down with it.
        sink = [];
    end
end

end
