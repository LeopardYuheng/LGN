%% read_tiff_timestamp.m
% Select one or more TIFF files and print their embedded timestamps.

[names, folder] = uigetfile('*.tif', 'Select TIFF file(s)', 'MultiSelect', 'on');
if isequal(names, 0), return; end
if ischar(names), names = {names}; end

fprintf('%-6s  %-40s  %s\n', 'Index', 'File', 'Time_From_Start (s)');
fprintf('%s\n', repmat('-', 1, 70));

for k = 1:numel(names)
    fpath = fullfile(folder, names{k});
    t_s   = nan;
    try
        tf   = Tiff(fpath, 'r');
        desc = tf.getTag('ImageDescription');
        tf.close();
        tok = regexp(desc, 'Time_From_Start\s*=\s*(\d+):(\d+):([\d.]+)', 'tokens', 'once');
        if ~isempty(tok)
            t_s = str2double(tok{1})*3600 + str2double(tok{2})*60 + str2double(tok{3});
        end
    catch
    end

    if isnan(t_s)
        fprintf('%-6d  %-40s  (no timestamp)\n', k, names{k});
    else
        fprintf('%-6d  %-40s  %.4f\n', k, names{k}, t_s);
    end
end