import numpy as np
from scipy.signal import find_peaks
import os
import matplotlib.pyplot as plt
from pathlib import Path
import pickle


def curate_spikes(sorting, we, save_folder, threshold_percentage=98, height=70,
                  MinPeakDistance=45, MaxPeakWidth=30, MinPeakProminence=50,
                  MinPeakWidth=3, plot_flag=False, midpoint=90):

    pickle_path = Path(save_folder) / "spike_data.pkl"
    if pickle_path.exists():
        with open(pickle_path, "rb") as f:
            print(f"Pickle file found at {pickle_path}")
            loaded_data = pickle.load(f)
            return loaded_data['curated_spike_vector'], loaded_data['spike_vector'], \
                loaded_data['rejected_spike_vector'], loaded_data['good_spikes_dict']

    curated_spike_vector = []
    spike_vector = []
    rejected_spike_vector = []
    good_spikes_dict = {}

    spike_curation_save_dir = Path(save_folder) / 'spike_curation'
    if not os.path.exists(spike_curation_save_dir):
        os.makedirs(spike_curation_save_dir)

    for unit_id in sorting.unit_ids:
        print(f'Curating spikes for unit id {unit_id}...')
        waveforms = we.get_waveforms(unit_id=unit_id)
        spike_times = sorting.get_unit_spike_train(unit_id=unit_id)
        assert(len(waveforms) == len(spike_times))
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

        if plot_flag:
            # Plotting
            fig, axs = plt.subplots(1, 2, figsize=(12, 6))

            # Accepted spikes
            accepted_primary_channel_waveforms = primary_channel_waveforms[good_spikes]
            mean_accepted = np.mean(accepted_primary_channel_waveforms, axis=0)
            std_accepted = np.std(accepted_primary_channel_waveforms, axis=0)
            axs[0].plot(mean_accepted, color='blue',
                        label='Mean Accepted Spike')
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
            axs[1].plot(mean_rejected, color='red',
                        label='Mean Rejected Spike')
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

    spike_curation_dict = {
        "curated_spike_vector": curated_spike_vector,
        "spike_vector": spike_vector,
        "rejected_spike_vector": rejected_spike_vector,
        "good_spikes_dict": good_spikes_dict
    }

    with open(Path(save_folder) / "spike_data.pkl", "wb") as f:
        pickle.dump(spike_curation_dict, f)

    return curated_spike_vector, spike_vector, rejected_spike_vector, good_spikes_dict
