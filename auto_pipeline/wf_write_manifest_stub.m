function wf_write_manifest_stub(outPath, sessions, problems)
%WF_WRITE_MANIFEST_STUB  Write a sessions.csv skeleton for unresolved data.
%
%   WF_WRITE_MANIFEST_STUB(outPath, sessions, problems)
%
% Called when the scanner cannot work something out on its own. Everything it
% did manage to resolve is pre-filled, so the fix is usually typing one path.
% Rename the file to sessions.csv and the next run reads it instead of
% guessing.

fid = fopen(outPath, 'w');
if fid < 0
    warning('wf_manifest:writeFailed', 'Could not write %s', outPath);
    return;
end

fprintf(fid, '# Sessions the scanner could not fully resolve.\r\n');
fprintf(fid, '# Fill in the blanks, delete rows you do not want analysed,\r\n');
fprintf(fid, '# then rename this file to  sessions.csv  in the same folder.\r\n');
fprintf(fid, '#\r\n');
for i = 1:numel(problems)
    fprintf(fid, '# %s\r\n', problems{i});
end
fprintf(fid, '#\r\n');
fprintf(fid, '# date: YYYYMMDD.  session_label: blank for a single-session\r\n');
fprintf(fid, '# experiment, otherwise session1 / session2 / session3.\r\n');
fprintf(fid, 'subject,date,session_label,tiff_dir,nev_file,csv_file\r\n');

for i = 1:numel(sessions)
    s = sessions(i);
    if ~isempty(s.subject) && ~isempty(s.date) && ~isempty(s.nev) && ~isempty(s.csv)
        continue;   % fully resolved, nothing for the user to do
    end
    fprintf(fid, '%s,%s,%s,%s,%s,%s\r\n', ...
        wf_q(s.subject), wf_q(s.date), wf_q(s.label), ...
        wf_q(s.img_dir), wf_q(s.nev), wf_q(s.csv));
end

fclose(fid);

end

% =====================================================================
function out = wf_q(v)
%WF_Q  Quote a field only when it contains a comma.

v = char(string(v));
if isempty(v)
    out = '';
elseif any(v == ',')
    out = ['"' v '"'];
else
    out = v;
end

end
