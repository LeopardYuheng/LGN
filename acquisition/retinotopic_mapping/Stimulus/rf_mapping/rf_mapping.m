n_col = 16;
n_row = 10;
bg_black_dot = 255;
point_black_dot = 0;
bg_white_dot = 0;
point_white_dot = 255;
n_trial = 60;
t_trial = 0.2; %s

file_save = input('Give the path for the folder you want the time_stamps to be saved in: ', 's');

[stimOnsetTimes_black_dot, stimOffsetTimes_black_dot] = rf_mapping_60Hz(n_col, n_row, bg_black_dot, point_black_dot, t_trial, n_trial);
[stimOnsetTimes_white_dot, stimOffsetTimes_white_dot] = rf_mapping_60Hz(n_col, n_row, bg_white_dot, point_white_dot, t_trial, n_trial);

Stimdata.black_on = stimOnsetTimes_black_dot;
Stimdata.black_off = stimOffsetTimes_black_dot;
Stimdata.white_on = stimOnsetTimes_white_dot;
Stimdata.white_off = stimOffsetTimes_white_dot;
Stimdata.n_col = n_col;
Stimdata.n_row = n_row;
Stimdata.n_trial = n_trial;
Stimdata.t_trial = t_trial;

cd(file_save);
filename = ['receptive_field_', replace(char(datetime('now')), {':', ' '}, '-')];
save([filename, '.mat'], 'Stimdata', '-v7.3');