function V1_mask = get_v1_boundary(v1_source_file, expected_size)
% get_v1_boundary  Load a full-frame V1 logical mask for plot overlays.
%
% Returns the full-frame (un-cropped) V1 mask so it can be drawn as a
% boundary contour on whole-brain dF/F / threshold / consensus figures.
% Per the current pipeline philosophy, dF/F is always computed on the whole
% brain mask; V1 is shown only as an overlay, never used to crop or mask the
% computation.
%
% Usage:
%   V1_mask = get_v1_boundary(v1_source_file)
%   V1_mask = get_v1_boundary(v1_source_file, [H W])   % also size-check
%
% Input:
%   v1_source_file  path to a .mat that contains the V1 mask. Accepted forms
%                   (searched in this order):
%                     - day_setup.retino_align.V1_mask_stim
%                     - reference_mask_and_retino_alignment.retino_align.V1_mask_stim
%                     - retino_align.V1_mask_stim   (top-level struct)
%                     - V1_mask_stim                (top-level variable)
%                     - V1_mask                     (top-level variable)
%   expected_size   optional [H W]; if given, the returned mask must match.
%
% Output:
%   V1_mask         logical H x W full-frame V1 mask, or [] if the file could
%                   not be loaded / no V1 field was found.

    V1_mask = [];

    if nargin < 1 || isempty(v1_source_file)
        return;
    end
    if ischar(v1_source_file) || isstring(v1_source_file)
        if ~isfile(v1_source_file)
            warning('get_v1_boundary:fileNotFound', ...
                'V1 source file not found:\n  %s', char(v1_source_file));
            return;
        end
        S = load(char(v1_source_file));
    elseif isstruct(v1_source_file)
        S = v1_source_file;   % already-loaded struct
    else
        warning('get_v1_boundary:badInput', 'Unsupported v1_source_file type.');
        return;
    end

    % --- search the common nesting patterns -----------------------------
    cand = [];
    if isfield(S, 'day_setup')
        cand = dig_v1(S.day_setup);
    end
    if isempty(cand) && isfield(S, 'reference_mask_and_retino_alignment')
        cand = dig_v1(S.reference_mask_and_retino_alignment);
    end
    if isempty(cand)
        cand = dig_v1(S);
    end

    if isempty(cand)
        warning('get_v1_boundary:noV1', ...
            'No V1 mask field found in:\n  %s', describe_source(v1_source_file));
        return;
    end

    V1_mask = logical(cand);

    if nargin >= 2 && ~isempty(expected_size)
        if ~isequal(size(V1_mask), expected_size(:)')
            warning('get_v1_boundary:sizeMismatch', ...
                ['V1 mask size (%dx%d) does not match the movie (%dx%d). ' ...
                 'Overlay skipped — is this a whole-brain (un-cropped) movie?'], ...
                size(V1_mask,1), size(V1_mask,2), expected_size(1), expected_size(2));
            V1_mask = [];
            return;
        end
    end

    if ~any(V1_mask(:))
        warning('get_v1_boundary:emptyMask', 'Loaded V1 mask is empty.');
        V1_mask = [];
    end
end

% =========================================================================
function m = dig_v1(s)
% Try to pull a V1 mask out of a struct using the known field names.
    m = [];
    if ~isstruct(s), return; end

    if isfield(s, 'retino_align') && isstruct(s.retino_align) ...
            && isfield(s.retino_align, 'V1_mask_stim')
        m = s.retino_align.V1_mask_stim; return;
    end
    if isfield(s, 'V1_mask_stim')
        m = s.V1_mask_stim; return;
    end
    if isfield(s, 'V1_mask')
        m = s.V1_mask; return;
    end
end

% =========================================================================
function txt = describe_source(src)
    if ischar(src) || isstring(src)
        txt = char(src);
    else
        txt = '<in-memory struct>';
    end
end
