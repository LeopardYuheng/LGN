function v = wf_stub_param(args, name, default)
%WF_STUB_PARAM  Fetch a name-value argument from a captured argument list.
%
% Used by the listdlg stub, whose arguments arrive as ('Name', value, ...)
% pairs in arbitrary order.

v = default;

for i = 1:2:numel(args)-1
    k = args{i};
    if (ischar(k) || isstring(k)) && strcmpi(char(string(k)), name)
        v = args{i+1};
        return;
    end
end

end
