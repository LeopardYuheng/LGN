%% WF + Ripple LGN stim survey + PulsePal camera start
% - Trial structure fully in this script (generates CSV)
% - Reads CSV back in to determine total number of trials
% - No IBLrig paths, no external trigger gating, no Intan triggers
% - Per trial: stimulate for X seconds, then ITI = 2.5 s (off)

clear; clc; close all;

addpath(genpath('C:\Albert Li\Luan_lab_retinomap-pipeline\acquisition\stim_parameter_survey\util\'));
% addpath('C:\Program Files (x86)\Ripple\Trellis\Tools\xippmex\');
addpath('C:\Albert Li\LGN\experiment\matlab\lib\xippmex\');

load('beep.mat','y');
% addpath('Z:\xl_LGN\LGN_ALBERT\wf_stim_ephys_code\Experiment');


%% ---------------- USER PARAMETERS ----------------
% --- PulsePal camera trigger (free-running) ---
camChan       = 1;       % PulsePal output channel wired to camera trigger input
ttl_high_s    = 0.010;   % 10 ms high
ttl_low_s     = 0.090;   % 90 ms low  -> 10 Hz frame triggers

% ttl_high_s    = 0.010;   % 10 ms high
% ttl_low_s     = 0.115;   % 115 ms low  -> 8 Hz frame triggers
cam_settle_s  = 2.0;     % time to let camera start after triggers begin

% --- Ripple stim fixed waveform parameters ---
pulse_width_us         = 167;   % us per phase
interphase_interval_us = 67;    % us
stim_freq_hz           = 50;    % Hz

% Stimulation duration "X seconds" (default unless CSV overrides)
default_stim_duration_s = 0.5;  % X

% ITI after EACH stimulation
ITI_s = 3;

% --- Trial list parameters (vary by trial) ---
currents_uA = [0 2 3 4 5 7];
% currents_uA = [0 7];


channels    = [16 18 28 32 50 84 86 87 96 114 122];
% channels    = [16];

num_trials_per_parameter = 30;

% --- Saving ---
parent_dir = 'C:\Users\xiela\OneDrive\Desktop\Albert';  % change to your lab root
base_name  = 'wf_stim_trials';
animal_dir = uigetdir(parent_dir,'Select animal folder');
date_str   = datestr(now, 'yyyy-mm-dd');
save_path  = fullfile(animal_dir, date_str, 'wf_stim_survey');


% ---------------- Build trial list CSV (trial structure lives here) ----------------
% This writes the CSV AND returns the in-memory table.
[csv_path, trial_table_written] = write_trials_to_csv_wf_stim( ...
    currents_uA, channels, num_trials_per_parameter, save_path, base_name);

fprintf('Wrote trial CSV:\n%s\n', csv_path);


%% ---------------- Ripple: init + verify + set stim resolution ----------------
ripple;  % Trek hardware init (takes a minute)

% status = xippmex;
% if status ~= 1
%     AbortPulsePal; EndPulsePal();
%     error('Xippmex did not initialize.');
% end
% pause(0.5);
% 
% elecs = xippmex('elec','micro');
% xippmex('stim','enable',0);
% xippmex('stim','res', elecs, 1);   % 1 uA resolution
% xippmex('stim','enable',1);

%% ---------------- Create save folder + start ephys recording ----------------

if ~exist(save_path, 'dir'); mkdir(save_path); end
fprintf('Data will be saved in %s\n', save_path);

time_str = datestr(datetime, 'HHMMSS');
ephys_filename = fullfile(save_path, ['ephys_' time_str]);
fprintf('Ephys file name: %s\n', ephys_filename);

xippmex('trial','recording', ephys_filename);
pause(1);
fprintf('Recording started.\n');

%% ---------------- PulsePal: start camera trigger train ----------------
PulsePal;

ProgramPulsePalParam(camChan, 'CustomTrainID', 0);
ProgramPulsePalParam(camChan, 'IsBiphasic', 0);
ProgramPulsePalParam(camChan, 'Phase1Duration', ttl_high_s);
ProgramPulsePalParam(camChan, 'InterPulseInterval', ttl_low_s);

SetContinuousLoop(camChan, 1);

% Depending on your PulsePal install, you may need an explicit start/trigger.
% % If TriggerPulsePal exists, it will start the output; otherwise continuous loop may already run.
% try
%     TriggerPulsePal(camChan);
% catch
%     % no-op
% end
pause(cam_settle_s);

%% --- Pre-stimulation baseline recording ---
baseline_record_s = 5 * 60;   % 5 minutes

pause(cam_settle_s);

fprintf('Recording baseline widefield activity for %.1f minutes with no stimulation...\n', ...
    baseline_record_s/60);
pause(baseline_record_s);
fprintf('Baseline recording complete. Starting stimulation trials.\n');

%% ---------------- Read CSV back in (source of truth for total trials) ----------------
trial_table = readtable(csv_path);
total_trials = height(trial_table);
fprintf('Total trials (from CSV): %d\n\n', total_trials);

% Optional CSV override: if you add a column named stim_duration_s, we use it per-trial.
has_duration_col = ismember('stim_duration_s', trial_table.Properties.VariableNames);

%% ---------------- Run stimulation trials ----------------
stim_call_time   = nan(total_trials,1);
trial_wallclock  = strings(total_trials,1);

tick_us = 33.33;  % 30 kHz clock => 33.33 us/tick

try
    for i = 1:total_trials

        stim_channel = trial_table.stim_channel(i);
        current_uA   = trial_table.current_uA(i);

        if has_duration_col
            stim_duration_s = trial_table.stim_duration_s(i);
        else
            stim_duration_s = default_stim_duration_s;
        end

        % Convert into Ripple units
        phase_len    = round(pulse_width_us / tick_us);
        ipi_len      = round(interphase_interval_us / tick_us);
        pulse_period = 30000 / stim_freq_hz;
        n_pulses     = round(stim_duration_s * stim_freq_hz);

        if exist('step_factor','var')
            current_steps = current_uA * step_factor;
        else
            current_steps = current_uA;  % with stim res=1 uA, this is typically correct
        end

        % Build biphasic stimulation command
        cmd = struct('elec', stim_channel, ...
                     'period', pulse_period, ...
                     'repeats', n_pulses);

        cmd.seq(1) = struct('length', phase_len, 'ampl', current_steps, 'pol', 0, ...
                            'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

        cmd.seq(2) = struct('length', ipi_len, 'ampl', 0, 'pol', 0, ...
                            'fs', 0, 'enable', 0, 'delay', 0, 'ampSelect', 1);

        cmd.seq(3) = struct('length', phase_len, 'ampl', current_steps, 'pol', 1, ...
                            'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

        fprintf('Trial %d/%d: %g uA, %d Hz, ch %d, stim %.3f s, ITI %.2f s\n', ...
                i, total_trials, current_uA, stim_freq_hz, stim_channel, stim_duration_s, ITI_s);

        % Send stim
        t_start = tic;
        xippmex('stimseq', cmd);
        stim_call_time(i)  = toc(t_start);
        trial_wallclock(i) = string(datetime('now'));
        pause(stim_duration_s);
        % xippmex('stim', 'enable', 0);
        % pause(0.2);
        % xippmex('stim', 'enable', 1);

        % ITI (OFF period) after stimulation
        pause(ITI_s);
    end

catch ME
    fprintf('\nERROR/STOP: %s\n', ME.message);
end
pause(2);
%% ---------------- Stop ephys recording ----------------
pause(2);

stop_warn = "";
try
    xippmex('trial','stopped');
    fprintf('Recording stopped.\n');
catch ME
    stop_warn = string(ME.message);
    fprintf('Stop command returned warning/error: %s\n', ME.message);
    fprintf('If Trellis shows recording has stopped, continuing anyway.\n');
end

%% ---------------- Stop PulsePal camera trigger ----------------

% This needs to get moveec higher
try
    AbortPulsePal;
    EndPulsePal();
catch
    % no-op
end
pause(2);

fprintf('Pulsepal stopped.\n');




%% ---------------- Save run log ----------------
RunLog.csv_path                   = csv_path;
RunLog.ephys_filename             = ephys_filename;
RunLog.stim_call_time             = stim_call_time;
RunLog.trial_wallclock            = trial_wallclock;

RunLog.stim_freq_hz               = stim_freq_hz;
RunLog.default_stim_duration_s     = default_stim_duration_s;
RunLog.pulse_width_us             = pulse_width_us;
RunLog.interphase_interval_us      = interphase_interval_us;
RunLog.ITI_s                      = ITI_s;

RunLog.currents_uA                = currents_uA;
RunLog.channels                   = channels;
RunLog.num_trials_per_parameter   = num_trials_per_parameter;

save(fullfile(save_path, ['runlog_' time_str '.mat']), 'RunLog');
fprintf('Saved run log to %s\n', save_path);


