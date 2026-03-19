day_dir = 'C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-1-30';

cfg = struct();
cfg.stimDI = 5;
cfg.camDI  = 2;
cfg.pre_sec  = 1;
cfg.post_sec = 3;
cfg.expected_n_trials = 1800;

container_path = make_container_intan(day_dir, cfg);