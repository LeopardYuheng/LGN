function txt = wf_stub_text(args, titleIdx)
%WF_STUB_TEXT  Build the string a stub matches its answer patterns against.
%
% Concatenates the dialog's filter/start argument and its title so patterns
% can key off either one (e.g. '\.nev' or 'Select day pointer').

parts = {};

for i = 1:min(numel(args), max(titleIdx, 2))
    a = args{i};
    if ischar(a) || isstring(a)
        parts{end+1} = char(string(a)); %#ok<AGROW>
    elseif iscell(a)
        flat = a(:)';
        for k = 1:numel(flat)
            if ischar(flat{k}) || isstring(flat{k})
                parts{end+1} = char(string(flat{k})); %#ok<AGROW>
            end
        end
    end
end

txt = strtrim(strjoin(parts, ' | '));

end
