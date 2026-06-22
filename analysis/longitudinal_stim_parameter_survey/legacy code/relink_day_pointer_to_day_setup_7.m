%% relink_day_pointer_to_day_setup.m
% One-off utility: repoint an existing day pointer container at a new
% day_setup .mat file (e.g., the V1-containing day_setup produced by
% step 5, reference_mask_and_retino_alignment.m).
%
% Why this is needed:
%   Step 3 (make_container_ripple_3.m) stores day_pointer.meta.day_setup_file_rel
%   from whatever setup file was selected back in step 2 — typically
%   brain_mask.mat (no V1 mask), since step 5 runs last. V1 scripts
%   (e.g., make_v1_trial_response_videos.m) load day_setup via that stored
%   path and require day_setup.retino_align.V1_mask_stim to exist.
%
% This script loads the day pointer, lets you pick the new day_setup .mat,
% verifies it contains a V1 mask, updates day_pointer.meta.day_setup_file_rel,
% and re-saves the container in place.
%
% Run once per day pointer after step 5 — not needed on every run.

clc; clear; close all; fclose('all');

%% -------------------------
% SELECT DAY POINTER
% -------------------------
[pointer_name, pointer_path] = uigetfile('*.mat', 'Select day pointer .mat (from step 3)');
if isequal(pointer_name, 0), error('No day pointer selected.'); end
day_pointer_file = fullfile(pointer_path, pointer_name);

S = load(day_pointer_file);
assert(isfield(S, 'day_pointer'), 'Selected file does not contain a "day_pointer" struct.');
day_pointer = S.day_pointer;

fprintf('Loaded day pointer:\n  %s\n', day_pointer_file);
fprintf('Current day_setup_file_rel:\n  %s\n', day_pointer.meta.day_setup_file_rel);

%% -------------------------
% SELECT NEW DAY SETUP (must contain V1 mask)
% -------------------------
[setup_name, setup_path] = uigetfile('*.mat', ...
    'Select NEW reference_mask_and_retino_alignment.mat with V1 mask (from step 5)');
if isequal(setup_name, 0), error('No day setup file selected.'); end
new_day_setup_file = fullfile(setup_path, setup_name);

D = load(new_day_setup_file);
assert(isfield(D, 'day_setup'), 'Selected file does not contain a "day_setup" struct.');
assert(isfield(D.day_setup, 'retino_align') && ...
       isfield(D.day_setup.retino_align, 'V1_mask_stim') && ...
       any(D.day_setup.retino_align.V1_mask_stim(:)), ...
       'Selected day_setup has no non-empty retino_align.V1_mask_stim — wrong file?');

%% -------------------------
% UPDATE + RE-SAVE
% -------------------------
day_pointer.meta.day_setup_file_rel = new_day_setup_file;
save(day_pointer_file, 'day_pointer', '-v7.3');

fprintf('\nUpdated day_setup_file_rel to:\n  %s\n', new_day_setup_file);
fprintf('Re-saved day pointer:\n  %s\n', day_pointer_file);
