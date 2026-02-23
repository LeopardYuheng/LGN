%% Trek Hardware Initialization 
disp('Initializing Ripple Neural Interface Processor...'); fprintf('\n');
% Initialize xippmex
status = xippmex;
if status ~= 1; error('Xippmex Did Not Initialize'); end
% Give the Trek some time to process any commands we have sent
pause(0.5)
elecs = xippmex('elec', 'micro');

for i = 1:32:128
    % enabling/disabling specific signal streams (LFP, raw) on
    % single channel on FE enables/disables entire FE
    xippmex('signal', elecs(i), 'lfp', 0) 
    xippmex('signal', elecs(i), 'raw', 1)
end
fprintf('LFP data stream disabled...\n');
fprintf('Raw data stream enabled...\n');

xippmex('signal', elecs, 'spk', 1);
fprintf('Spike data stream enabled...\n');
xippmex('signal', elecs, 'stim', 1)
fprintf('Stim enabled...\n\n');


%% Stim resolution and impedance measurement (run after front end attached)
% Important!!! Set correct stim step size. For 0.5 uA step size, resolution must be index 5. 
% xippmex('stim', 'enable', 0); % Enable 0 to start impedances 
% disp("Running pre-stimulation impedance test..."); fprintf('\n');
% prestim_impedances = xippmex('impedance', elecs(1:32));
% xippmex('stim', 'enable', 0);
% xippmex('stim', 'res', elecs, 1); % step size of 1 uA
% xippmex('stim', 'enable', 1);

sessionDate = datetime("today");
% server_impedance_path = fullfile('\\10.129.151.108\xieluanlabs\xl_stimulation',animalID,'Impedance');
% save(fullfile(server_impedance_path,strcat(char(sessionDate),'.mat')),'prestim_impedances'); % save in server 
% generateImpedancePlot2P(fullfile(server_impedance_path,strcat(char(sessionDate),'.mat')),subFolder)
% fprintf('Impedance test complete!\n')

% disp("Pre-stimulation impedance test complete!"); fprintf('\n');
% cd('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\Behavioral\2P+Behavior\MoCS\randomized blocks');

% If resolution is 5, then current step size is 0.5 uA. 
% Current steps = stepFactor x nominalCurrent
if xippmex('stim', 'res', elecs) == 5
    step_factor = 2;
    fprintf('Using step size of 0.5 uA!\n');
else
    step_factor = 1;
    fprintf('Using step size of 1 uA!\n');
end