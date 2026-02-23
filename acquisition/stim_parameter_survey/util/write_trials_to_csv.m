function write_trials_to_csv(p_go, n_trials, ripple_ch_GO, ripple_ch_NOGO)
    arguments
        p_go (1,1) double
        n_trials (1,1) int32
        ripple_ch_GO (1,1) double 
        ripple_ch_NOGO (1,1) double 
    end

    output_file = 'C:/Users/xiela/OneDrive/Desktop/precomputed_trials.csv'; 

    if p_go < 0 || p_go > 1
        error('p_go must be between 0 and 1');
    end

    stim_angles = zeros(1, n_trials);
    trial_types = strings(1, n_trials);

    for trial = 1:n_trials
        is_go_trial = rand() < p_go;

        if is_go_trial
            stim_angle = 90;
            trial_type = "go";
            stim_channel = ripple_ch_GO;
        else
            stim_angle = 0;
            trial_type = "no-go";
            stim_channel = ripple_ch_NOGO;
        end

        stim_angles(trial) = stim_angle;
        trial_types(trial) = trial_type;
        stim_channels(trial) = stim_channel;
    end

    fileID = fopen(output_file, 'w');
    if fileID == -1
        error('Failed to open file for writing: %s', output_file);
    end

    fprintf(fileID, 'trial,stim_angle,trial_type,stim_channel\n');
    for i = 1:n_trials
        fprintf(fileID, '%d,%d,%s,%d\n', i, stim_angles(i), trial_types(i), stim_channels(i));
    end

    fclose(fileID);
    disp(['Wrote ', num2str(n_trials), ' trials to ', output_file]);
end
