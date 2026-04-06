
def write_zarr(file_name):
    number_of_cores = multiprocessing.cpu_count()
    cores_to_use = number_of_cores - 2
    job_kwargs = dict(n_jobs=cores_to_use, chunk_duration="1s",
                      progress_bar=True)
    full_traces_size_GiB = 10
    large_recording = generate_recording_by_size(
        full_traces_size_GiB=full_traces_size_GiB)
    fs = large_recording.get_sampling_frequency()

    # save recording to folder in binary (default) format
    recording_zarr = large_recording.save(
        folder=Path('G:') / file_name, format="zarr", **job_kwargs)

  # %%
    stim_ts = np.concatenate(all_stim_timestamps)
    plot_ch = np.arange(19)
    # plot_ch = np.arange(6, 14)
    time_range = np.array([30, 35]) * int(fs)
    plot_flag = False
    steps_order1 = ['remove_artifacts1', 'bandpass_filter', 'common_reference',
                    'remove_artifacts2', 'whiten']

    steps_order2 = ['remove_artifacts1', 'bandpass_filter', 'remove_artifacts2',
                    'common_reference', 'remove_artifacts2', 'whiten']

    steps_order3 = ['remove_artifacts1', 'whiten']

    s1 = preprocess_and_plot(rec, stim_ts, time_range, plot_ch,
                             plot_flag, steps_order1, pre_stim_blank_ms=0.5, post_stim_blank_ms=2.5)
    s2 = preprocess_and_plot(rec, stim_ts, time_range, plot_ch,
                             plot_flag, steps_order2, pre_stim_blank_ms=0.5, post_stim_blank_ms=2.5)
    s3 = preprocess_and_plot(rec, stim_ts, time_range, plot_ch,
                             plot_flag, steps_order3, pre_stim_blank_ms=0, post_stim_blank_ms=0)
    # Compare final results
    plt.plot(s1[:, plot_ch], 'red', alpha=1)
    plt.plot(s2[:, plot_ch], 'black', alpha=1)
    # plt.plot(s3[:, plot_ch], 'orange', alpha=0.3)


stim_ts = np.concatenate(all_stim_timestamps)

time_range = [200, 210]
plot_flag = True
pre_stim_blank_ms = 0.5
post_stim_blank_ms = 2.5
stim_ts = np.concatenate(all_stim_timestamps)

rec_art1 = sp.remove_artifacts(
    rec, stim_ts, ms_before=pre_stim_blank_ms, ms_after=post_stim_blank_ms, mode='cubic')
rec_filt = sp.bandpass_filter(rec_art1, freq_min=300, freq_max=5000)
rec_cr = sp.common_reference(
    rec_filt, operator="median", reference="global")
rec_art2 = sp.remove_artifacts(
     rec_cr, stim_ts, ms_before=0, ms_after=post_stim_blank_ms, mode='linear')
 rec_preprocessed = sp.whiten(rec_art2, dtype='float32')

  rec_for_waveform_extraction = rec_art2
   # %%
   if plot_flag:
        fig, axs = plt.subplots(ncols=3, figsize=(14, 7))
        si.plot_traces(rec_art1, backend='matplotlib',
                       time_range=time_range, order_channel_by_depth=True, ax=axs[0])
        axs[0].set_title('Remove artifact')
        si.plot_traces(rec_cr, backend='matplotlib',
                       time_range=time_range, order_channel_by_depth=True, ax=axs[1])
        axs[1].set_title('Post-filt and common ref')
        si.plot_traces(rec_preprocessed, backend='matplotlib',  time_range=time_range,
                       order_channel_by_depth=True, show_channel_ids=True, ax=axs[2])
        axs[2].set_title('Whitening')

    # %% Remove artifacts using cubic interpolation
    time_range = [300, 310]
    si.plot_timeseries({'pre-artifact removal': rec_art1, 'post-artifact removal': rec_filt,
                        'filtered': rec_art2}, backend='matplotlib',  time_range=time_range,
                       order_channel_by_depth=True)

    # %% Plot
    rec1_seg = rec_preprocessed.get_traces(start_frame=60000, end_frame=90000)
    plt.plot(rec1_seg[:, 6:10])

    # %% Spike sort!

    sorting_parameters = ms5.Scheme2SortingParameters(
        phase1_detect_channel_radius=100,
        detect_channel_radius=100,
        training_duration_sec=60*5,
        detect_threshold=4
    )

    sorting = ms5.sorting_scheme2(
        recording=rec_preprocessed,
        sorting_parameters=sorting_parameters
    )

    date_str = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    # Check if the folder exists
    if os.path.exists(base_folder):
        save_folder = Path(f"{base_folder}_{date_str}")
    else:
        save_folder = base_folder
    sorting.save(folder=save_folder)
    file_path = 'sorting_cached.npz'
    se.NpzSortingExtractor.write_sorting(sorting, save_folder / file_path)
    sorting = se.NpzSortingExtractor(save_folder / file_path)

    # %%
    job_kwargs = dict(n_jobs=n_jobs, chunk_duration="1s")
    amplitude_cutoff_thresh = 0.1
    isi_violations_ratio_thresh = 1
    presence_ratio_thresh = 0.8
    we = si.extract_waveforms(
        rec_for_waveform_extraction, sorting, folder=save_folder / 'waveforms',
        overwrite=True, sparse=False)
    _ = compute_spike_amplitudes(we)
    _ = compute_unit_locations(we)
    _ = compute_template_similarity(we)
    _ = compute_correlograms(we)

    our_query = f"(amplitude_cutoff < {amplitude_cutoff_thresh}) & \
      (isi_violations_ratio < {isi_violations_ratio_thresh}) & \
          (presence_ratio > {presence_ratio_thresh})"
    metrics = qm.compute_quality_metrics(we, metric_names=['firing_rate', 'presence_ratio', 'snr',
                                                           'isi_violation', 'amplitude_cutoff'])

    # Apply query
    keep_units = metrics.query(our_query)
    keep_unit_ids = keep_units.index.values
    print(f'Units to keep: {keep_unit_ids}')

    # Extract waveforms from units that meet quality metrics criteria
    we_curated = we.select_units(
        keep_unit_ids, new_folder=save_folder / 'waveforms_curated')
    sorting_curated = sorting.select_units(keep_unit_ids)

    # %%
    si.plot_sorting_summary(we_curated, curation=True, backend='sortingview')

    # %% Post processing
    # available_cores = multiprocessing.cpu_count()
    # n_jobs = 10
    # print(f'Using {n_jobs} cores!')
    # # parallel processing!
    # job_kwargs = dict(n_jobs=n_jobs, chunk_duration="1s")

    # save_folder = Path('G:\\data\\ICMS93\\behavior\\30-Aug-2023\\ChannelVolumetric\\combined_2023-09-28_20-14-26')
    # read sorting object
    if 'sorting' not in globals():
        sorting_file_path = os.path.join(save_folder, 'sorting_cached.npz')
        sorting = se.NpzSortingExtractor(file_path=sorting_file_path)

    amplitude_cutoff_thresh = 0.1
    isi_violations_ratio_thresh = 1
    presence_ratio_thresh = 0.8
    we = si.extract_waveforms(
        rec_for_waveform_extraction, sorting, folder=save_folder / 'waveforms',
        overwrite=True, sparse=False)
    _ = compute_spike_amplitudes(we)
    _ = compute_unit_locations(we)
    _ = compute_template_similarity(we)
    _ = compute_correlograms(we)

    our_query = f"(amplitude_cutoff < {amplitude_cutoff_thresh}) & \
      (isi_violations_ratio < {isi_violations_ratio_thresh}) & \
          (presence_ratio > {presence_ratio_thresh})"
    metrics = qm.compute_quality_metrics(we, metric_names=['firing_rate', 'presence_ratio', 'snr',
                                                           'isi_violation', 'amplitude_cutoff'])

    # Apply query
    keep_units = metrics.query(our_query)
    keep_unit_ids = keep_units.index.values
    print(f'Units to keep: {keep_unit_ids}')

    # Extract waveforms from units that meet quality metrics criteria
    we_curated = we.select_units(
        keep_unit_ids, new_folder=save_folder / 'waveforms_curated')
    sorting_curated = sorting.select_units(keep_unit_ids)

    # %%
    si.plot_sorting_summary(we_curated, curation=True, backend='sortingview')

    # %% Post curation
    uri = 'sha1://8b6d782be18cf17b477df264d994ee570515f74c'
    # json_file = 'curation.json'
    clean_sorting = scur.apply_sortingview_curation(sorting_curated, uri_or_json=uri,
                                                    skip_merge=False)
    keep_idx = np.where(clean_sorting.get_property("accept"))[0]
    unit_ids = clean_sorting.get_unit_ids()
    print(f'Good unit IDs: {unit_ids[keep_idx]}')
    discard_idx = np.where(clean_sorting.get_property("reject"))[0]
    print(f'Bad unit IDs: {unit_ids[discard_idx]}')
    # Extract waveforms from units that meet quality metrics criteria
    we_curated_2 = we.select_units(
        unit_ids[keep_idx], new_folder=save_folder / 'waveforms_curated_2')
    sorting_curated_2 = sorting.select_units(unit_ids[keep_idx])

    sorting_curated_2.save(folder=save_folder / "sorting_curated")
    # %% Export report
    si.export_report(we_curated_2, output_folder=save_folder /
                     'waveforms_curated_2' / 'report', format='png')

    # %% Save so loading waveform extractor can be easier

    # save_folder = Path(
    #     'G:\\data\\ICMS93\\behavior\\30-Aug-2023\\ChannelVolumetric\\combined_2023-09-28_20-14-26')
    EXTRACT_ALL_WVF = True

    processed_folder = Path("processed")
    if EXTRACT_ALL_WVF:
        max_spikes_per_unit = 100000
    else:
        max_spikes_per_unit = 500

    if 'sorting' not in globals():
        sorting_file_path = os.path.join(save_folder, 'sorting_cached.npz')
        sorting_pre1 = se.NpzSortingExtractor(file_path=sorting_file_path)
        sorting_pre2 = scur.apply_sortingview_curation(sorting_pre1, uri_or_json=uri,
                                                       skip_merge=False)
        keep_idx = np.where(sorting_pre2.get_property("accept"))[0]
        unit_ids = sorting_pre2.get_unit_ids()
        good_units = unit_ids[keep_idx]
        sorting = sorting_pre2.select_units(good_units)

        # the "processed" folder is now portable, and the waveform extractor can be reloaded
        # from a different location/machine (without loading the recording)
        we_pre = si.load_waveforms(folder=save_folder / processed_folder / "waveforms_curated",
                                   with_recording=False)
        # we = we_pre.select_units(good_units, new_folder=save_folder / processed_folder/ 'waveforms_curated' )
    else:
        sorting = sorting_curated_2.save(
            folder=save_folder / processed_folder / "sorting")
        # we = si.extract_waveforms(rec_for_waveform_extraction, sorting, folder=save_folder / processed_folder / "waveforms2",
        #                           use_relative_path=True, max_spikes_per_unit=max_spikes_per_unit, **job_kwargs)
        we = si.extract_waveforms(rec_for_waveform_extraction, sorting, folder=save_folder / processed_folder / "waveforms",
                                  use_relative_path=True, max_spikes_per_unit=max_spikes_per_unit)
    # %% Post processing analysis

    idx = 3
    templates = we_curated_2.get_all_templates(
        unit_ids[keep_idx], mode='median')
    plt.plot(templates[idx])

    # %% Plot raw
    post_stim_win = int(0.007 * fs)
    pre_stim_win = int(0.003 * fs)

    def plot_data(current_idx):
        ax1.cla()

        trial_id = trial_ids_with_spikes[current_idx]
        # Use the stim time as the center of the plot
        center_time = stim_ts[trial_id]

        # Calculate the start and end frames for the window around the stim pulse
        start_frame = int(center_time - pre_stim_win)
        end_frame = int(center_time + post_stim_win)
        raw = sp.scale(rec, rec.get_channel_gains())
        final = sp.scale(rec_art2, rec.get_channel_gains())
        record_seg1 = raw.get_traces(
            start_frame=start_frame, end_frame=end_frame)
        record_seg2 = final.get_traces(
            start_frame=start_frame, end_frame=end_frame)

        # Extract spike times within this window and calculate their relative times
        relative_spikes = [(spike - center_time) * 1000.0 / fs for spike in spike_train
                           if start_frame <= spike <= end_frame]

        x = np.arange(start_frame, end_frame) * \
            1000.0 / fs - (center_time * 1000.0 / fs)

        # plt.plot(x, record_seg1, 'r', alpha=0.3)
        # plt.plot(x, record_seg2, 'b', alpha=0.3)

        alpha_plot = 0.3
        # Plot the first curve on the primary y-axis
        ax1.plot(x, record_seg1, color='#1f77b4', alpha=alpha_plot)
        ax1.plot(x, record_seg1[:, primary_ch_idx],
                 '#1f77b4', alpha=1, linewidth=2)
        ax1.set_ylabel('Raw data (uV)', color='#1f77b4')
        ax1.tick_params('y', colors='#1f77b4')

        # Create a secondary y-axis
        ax2.cla()
        ax2.plot(x, record_seg2, '#ff7f0e', alpha=alpha_plot)
        ax2.plot(x, record_seg2[:, primary_ch_idx],
                 '#ff7f0e', alpha=1, linewidth=2)
        ax2.set_ylabel('Scaled filtered data', color='#ff7f0e')
        ax2.tick_params('y', colors='#ff7f0e')
        ax2.set_ylim([-1000, 300])
        ax2.yaxis.set_label_position("right")
        # Add vertical line at the center of the plot for the stim pulse
        plt.axvline(0, color='red', linestyle='--', label="Stim Pulse")

        # Add vertical lines for relative spike times
        for spike_time in relative_spikes:
            plt.axvline(spike_time, color='black', alpha=0.3)

        plt.title(
            f"Raw Data with Stim Pulse and Spikes for Trial ID {trial_id}")
        plt.xlabel("Time Relative to Stim Pulse (ms)")
        plt.ylabel("Amplitude")
        plt.tight_layout()
        plt.draw()

    def on_key(event):
        global current_idx
        if event.key == 'right':
            current_idx = (current_idx + 1) % len(trial_ids_with_spikes)
            plot_data(current_idx)
        elif event.key == 'left':
            current_idx = (current_idx - 1) % len(trial_ids_with_spikes)
            plot_data(current_idx)

    idx = 0
    unit_id = good_units[idx]
    templates = we.get_all_templates(
        unit_ids[keep_idx], mode='median')[idx]
    primary_ch_idx = np.unravel_index(np.argmin(templates), templates.shape)[1]

    spike_train = sorting.get_unit_spike_train(unit_id=unit_id)
    good_spikes = good_spikes_dict[unit_id]
    good_spike_train = spike_train[good_spikes]
    # First, get a sorted version of spike_train for the relevant spikes
    sorted_spike_train = sorted(good_spike_train[0:100000])

    trial_ids_with_spikes = []
    spike_idx = 0

    for i, ts in enumerate(stim_ts):
        start_frame = int(ts - pre_stim_win)
        end_frame = int(ts + post_stim_win)

        # Move the spike_idx pointer until we're in the window
        while spike_idx < len(sorted_spike_train) and sorted_spike_train[spike_idx] < start_frame:
            spike_idx += 1

        # Check if we have any spike in the current window
        if spike_idx < len(sorted_spike_train) and start_frame <= sorted_spike_train[spike_idx] <= end_frame:
            trial_ids_with_spikes.append(i)

    fig, ax1 = plt.subplots()
    ax2 = ax1.twinx()
    fig.canvas.mpl_connect('key_press_event', on_key)
    current_idx = trial_ids_with_spikes[100]
    plot_data(current_idx)
    plt.show()
    # %% Curate individual spikes for each unit
    # read waveform extractor object on disk
    sorting_file_path = os.path.join(save_folder, 'sorting_cached.npz')
    sorting_pre1 = se.NpzSortingExtractor(file_path=sorting_file_path)
    sorting_pre2 = scur.apply_sortingview_curation(sorting_pre1, uri_or_json=uri,
                                                   skip_merge=False)
    keep_idx = np.where(sorting_pre2.get_property("accept"))[0]
    unit_ids = sorting_pre2.get_unit_ids()
    good_units = unit_ids[keep_idx]

    midpoint = 90
    curated_sorting = sorting
    threshold_percentage = 95
    curated_spike_vector = []
    spike_vector = []
    rejected_spike_vector = []
    good_spikes_dict = {}
    # Peak detection criteria
    height = 70  # Adjust as needed
    MinPeakDistance = 45  # 1.5 ms
    MaxPeakWidth = 30
    MinPeakProminence = 50
    MinPeakWidth = 3

    spike_curation_save_dir = save_folder / 'processed' / 'spike_curation'
    if not os.path.exists(spike_curation_save_dir):
        os.makedirs(spike_curation_save_dir)

    for unit_id in we.unit_ids:
        print(f'Curating spikes for unit id {unit_id}...')
        waveforms = we.get_waveforms(unit_id=unit_id)

        # 1. Identify the Primary Channel
        median_waveform = np.median(waveforms, axis=0)
        primary_channel_idx = np.argmin(median_waveform[midpoint, :])

        # 2. Calculate Distances
        primary_channel_waveforms = waveforms[:, :, primary_channel_idx]
        median_primary_channel_waveform = median_waveform[:,
                                                          primary_channel_idx]
        distances = np.linalg.norm(
            primary_channel_waveforms - median_primary_channel_waveform, axis=1)
        threshold_distance = np.percentile(distances, threshold_percentage)
        good_spikes_distance = np.where(distances < threshold_distance)[0]

        # 3. Apply peak detection criteria to each waveform in primary_channel_waveforms
        good_spikes_peak = []
        for waveform in primary_channel_waveforms:
            peaks, _ = find_peaks(-waveform, height=height, width=(MinPeakWidth, MaxPeakWidth),
                                  prominence=MinPeakProminence, distance=MinPeakDistance)
            if len(peaks) > 0:  # If any peaks are detected
                good_spikes_peak.append(True)
            else:
                good_spikes_peak.append(False)
        good_spikes_peak = np.where(good_spikes_peak)[0]

        # 4. Find intersection of good spikes
        good_spikes = np.intersect1d(good_spikes_distance, good_spikes_peak)
        good_spikes_dict[unit_id] = good_spikes

        spike_times = sorting.get_unit_spike_train(unit_id=unit_id)
        curated_spike_times = [spike_times[i] for i in good_spikes]
        for spike_time in spike_times:
            spike_vector.append((spike_time, unit_id))
        for curated_spike_time in curated_spike_times:
            curated_spike_vector.append((curated_spike_time, unit_id))

        # Store rejected spikes
        rejected_spikes = np.setdiff1d(
            np.arange(primary_channel_waveforms.shape[0]), good_spikes)

        rejected_spike_times = [spike_times[i] for i in rejected_spikes]
        for rejected_spike_time in rejected_spike_times:
            rejected_spike_vector.append((rejected_spike_time, unit_id))

        # Plotting
        fig, axs = plt.subplots(1, 2, figsize=(12, 6))

        # Accepted spikes
        accepted_primary_channel_waveforms = primary_channel_waveforms[good_spikes]
        mean_accepted = np.mean(accepted_primary_channel_waveforms, axis=0)
        std_accepted = np.std(accepted_primary_channel_waveforms, axis=0)
        axs[0].plot(mean_accepted, color='blue', label='Mean Accepted Spike')
        axs[0].fill_between(range(len(mean_accepted)), mean_accepted -
                            std_accepted, mean_accepted + std_accepted, color='blue', alpha=0.2)
        axs[0].set_title(f"Accepted Spikes for Unit {unit_id}")
        axs[0].legend()
        axs[0].text(
            0.1, 0.9, f'Number Accepted: {len(good_spikes)}', transform=axs[0].transAxes)

        # Rejected spikes
        rejected_primary_channel_waveforms = primary_channel_waveforms[rejected_spikes]
        mean_rejected = np.mean(rejected_primary_channel_waveforms, axis=0)
        std_rejected = np.std(rejected_primary_channel_waveforms, axis=0)
        axs[1].plot(mean_rejected, color='red', label='Mean Rejected Spike')
        axs[1].fill_between(range(len(mean_rejected)), mean_rejected -
                            std_rejected, mean_rejected + std_rejected, color='red', alpha=0.2)
        axs[1].set_title(f"Rejected Spikes for Unit {unit_id}")
        axs[1].legend()
        axs[1].text(
            0.1, 0.9, f'Number Rejected: {len(rejected_spikes)}', transform=axs[1].transAxes)

        plt.tight_layout()

        # Save the figure
        save_path = os.path.join(spike_curation_save_dir,
                                 f"unit_{unit_id}_comparison.png")
        plt.savefig(save_path)
        plt.close()

    # plt.figure(figsize=(12, 8))
    # plt.plot(primary_channel_waveforms.T, color='lightgray', alpha=0.7)
    # plt.plot(median_primary_channel_waveform, color='red', linewidth=2)
    # plt.title('Waveform Overlays (Primary Channel)')
    # plt.show()

    # Histogram of Distances
    plt.figure(figsize=(12, 8))
    plt.hist(distances, bins=50, label='Distances')
    plt.axvline(threshold_distance, color='red',
                linestyle='--', label='Threshold')
    plt.title('Histogram of Distances to Median Waveform (Primary Channel)')
    plt.xlabel('Distance')
    plt.ylabel('Number of Spikes')
    plt.legend()
    plt.show()
    # %% PSTH
    post_stim_win = int(0.007 * fs)
    pre_stim_win = int(0.003 * fs)
    _ = compute_unit_locations(we)

    psth_save_dir = save_folder / 'processed' / \
        ('psth_curated_spikes' + str(threshold_percentage) + '%')
    if not os.path.exists(psth_save_dir):
        os.makedirs(psth_save_dir)
    plot_raster_and_waveform(we, good_units, good_spikes_dict, curated_spike_vector, psth_save_dir, fs, pre_stim_win,
                             post_stim_win, stim_ts)

    psth_save_dir = save_folder / 'processed' / 'psth'
    if not os.path.exists(psth_save_dir):
        os.makedirs(psth_save_dir)
    plot_raster_and_waveform(we, good_units, good_spikes_dict, spike_vector, psth_save_dir, fs, pre_stim_win,
                             post_stim_win, stim_ts)
    # %%
    psth_save_dir = save_folder / 'processed' / \
        ('psth_curated_spikes' + str(threshold_percentage) + '%_current_and_depth')
    if not os.path.exists(psth_save_dir):
        os.makedirs(psth_save_dir)
    plot_raster_and_waveform_current_and_depth(we, good_units, good_spikes_dict, spike_vector, psth_save_dir,
                                               fs, pre_stim_win, post_stim_win, all_stim_timestamps, all_currents, all_depths,
                                               animalID, date_str)

    psth_save_dir = save_folder / 'processed' / 'psth_current_and_depth'
    if not os.path.exists(psth_save_dir):
        os.makedirs(psth_save_dir)
    plot_raster_and_waveform_current_and_depth(we, good_units, good_spikes_dict, spike_vector, psth_save_dir,
                                               fs, pre_stim_win, post_stim_win, all_stim_timestamps, all_currents,
                                               all_depths, animalID, date_str)
