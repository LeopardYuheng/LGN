import os
import re
import scipy.io as sio
import numpy as np
from spikeinterface import full as si, extractors as se
import datetime
from pathlib import Path
from util.impedance_analyzer import ImpedanceAnalyzer


class DataLoader:

    def __init__(self, debug=False):
        self._initialize_drives()
        if not self.data_drive or not self.server_drive:
            raise ValueError("Required drives not found.")
        if debug:
            self.num_files = 1
        else:
            self.num_files = 4

    def run_workflow(self, animalID, load_from_checkpoint, checkpoint_folder):
        """Main workflow to execute the necessary methods in order."""
        self.choose_data_folder(
            animalID, load_from_checkpoint, checkpoint_folder)
        self.get_base_server_folder()
        self.get_date_string()
        self.get_ns5_files()
        self.append_recordings()
        self.get_key_files()
        self.get_concatenated_recording()
        # ... you can add other necessary methods here as the workflow continues

    def _initialize_drives(self):
        """Helper method to initialize the drives."""
        data_drives = ['G:/data', 'C:/data']
        server_drives = ['Z:/', 'S:/']
        self.data_drive = next(
            (drive for drive in data_drives if os.path.exists(drive)), None)
        self.server_drive = next(
            (drive for drive in server_drives if os.path.exists(Path(drive) / "ICMS")), None)

    def choose_data_folder(self, animalID, load_from_checkpoint, checkpoint_folder):
        """Choose the data folder based on the given animalID."""
        self.animalID = animalID
        if load_from_checkpoint:
            self.save_folder = checkpoint_folder
            print(f"Checkpoint folder at: {self.save_folder}")
            parent_folder = self.save_folder.parent
            self.data_folder = os.path.join(parent_folder, "ChannelVolumetric")
        else:
            animalID_path = self._get_animalID_path(animalID)
            folders = self._get_valid_date_folders(animalID_path)
            selected_folder = self._user_select_folder(folders)
            # make save folder as well
            current_date_string = datetime.datetime.now().strftime('%d-%b-%Y_%H%M%S')
            self.save_folder = os.path.join(
                selected_folder, "Processed_" + current_date_string)
            os.makedirs(self.save_folder)
            print(f"Save folder created at: {self.save_folder}")
            self.data_folder = os.path.join(
                selected_folder, "ChannelVolumetric")

    def _get_animalID_path(self):
        """Helper to get the path for the given animalID."""
        behavior_path = os.path.join(
            self.data_drive, self.animalID, 'behavior')
        Behavior_path = os.path.join(
            self.data_drive, self.animalID, 'Behavior')
        if os.path.exists(behavior_path):
            return behavior_path
        elif os.path.exists(Behavior_path):
            return Behavior_path
        else:
            raise FileNotFoundError(
                f"No 'behavior' or 'Behavior' directory found for {self.animalID}.")

    def _get_valid_date_folders(self, path):
        """Helper to get valid date folders from a given path."""
        return [os.path.join(path, date) for date in os.listdir(path)
                if re.match(r'\d{2}-\w{3}-\d{4}', date) and
                "ChannelVolumetric" in os.listdir(os.path.join(path, date))]

    def _user_select_folder(self, folders):
        """Helper to allow the user to select a folder."""
        for idx, folder in enumerate(folders, 1):
            print(f"{idx}. {folder}")
        while True:
            try:
                choice = int(
                    input("Choose a folder to process (enter the number): "))
                return folders[choice-1]
            except (ValueError, IndexError):
                print("Invalid choice. Please try again.")

    def get_base_server_folder(self):
        """Determine the base server folder from the data folder."""
        parts = os.path.normpath(self.data_folder).split(os.sep)
        icms_id = self._get_part_matching(parts, "ICMS")
        date = self._get_part_matching(parts, r'\d{2}-\w{3}-\d{4}')
        subfolder = "ChannelVolumetric"
        self.base_server_folder = os.path.join(
            icms_id, "Keys", date, subfolder)

    def _get_part_matching(self, parts, pattern):
        """Helper to get a part of the path matching a given pattern."""
        return next(part for part in parts if re.match(pattern, part))

    def get_date_string(self):
        """Extract the date string from the data folder."""
        path_parts = os.path.normpath(self.data_folder).split(os.sep)
        self.date_string = self._get_part_matching(
            path_parts, r'\d{2}-[A-Za-z]{3}-\d{4}')

    def get_ns5_files(self):
        """Extract NS5 and MAT files from the data folder."""
        all_files = os.listdir(self.data_folder)
        self.mat_files = [f for f in all_files if re.match(
            r'block\d+_H\d+M\d+_behavior.mat', f)]
        base_names = [re.match(
            r'(block\d+_H\d+M\d+)_behavior.mat', f).group(1) for f in self.mat_files]
        self.ns5_files = [self._get_ns5_file_matching_base(
            base_name, all_files) for base_name in base_names]

    def _get_ns5_file_matching_base(self, base_name, all_files):
        """Helper to get the NS5 file that matches a given base name."""
        return next((f for f in all_files if f.startswith(base_name) and f.endswith('.ns5')), None)

    def get_key_files(self):
        """Extract key information from server folder."""
        key_paths = [os.path.join(self.server_drive, self.base_server_folder,
                                  f.replace('_behavior', '_key')) for f in self.mat_files]
        self.all_currents, self.all_depths, self.all_stim_timestamps, \
            self.all_stim_start_stop, self.all_image_start_stop = [], [], [], [], []
        for i, key_path in enumerate(key_paths[:self.num_files]):
            mat_data = sio.loadmat(key_path, simplify_cells=True)
            self._extract_key_data_from_mat(mat_data, i)
        self._correct_depths()

    def _extract_key_data_from_mat(self, mat_data, index):
        """Helper to extract specific key data from the MAT file."""

        trial_array = mat_data['trialDataStruct']
        currents = [trial['Current'] for trial in trial_array]
        depths = [trial['Depth'] for trial in trial_array]
        stim_timestamps = [(np.array(trial['StimTimestamps']) * self.fs
                            + self.start_times[index]).tolist() for trial in trial_array]
        stim_start_stop = [(np.array(trial['StimStartStop']) * self.fs
                            + self.start_times[index]).tolist() for trial in trial_array]
        img_start_stop = [(np.array(trial['ImageStartStop']) * self.fs
                           + self.start_times[index]).tolist() for trial in trial_array]

        if type(img_start_stop[-1]) != list:
            img_start_stop[-1] = [img_start_stop[-1],
                                  img_start_stop[-1] + 30000 * 5]
        self.all_currents.extend(currents)
        self.all_depths.extend(depths)
        self.all_stim_timestamps.extend(stim_timestamps)
        self.all_stim_start_stop.extend(stim_start_stop)
        self.all_image_start_stop.extend(img_start_stop)

    def _correct_depths(self):
        # older sessions don't use depth but ripple_id
        ia = ImpedanceAnalyzer()
        if any(depth > 20 for depth in self.all_depths):
            # assume intan channels and convert to depth
            ripple_ids = np.unique(self.all_depths)
            ripple_ids = [
                ripple_id for ripple_id in ripple_ids if ripple_id != 0]
            depth_idx = ia.ripple_to_depth2(ripple_ids)
            mapping = dict(zip(ripple_ids + [0], depth_idx + [0]))
            self.all_depths = [mapping.get(val, val)
                               for val in self.all_depths]

    def get_time_vector(self, subrecording):
        """Return a time vector for the given recording, starting from 0."""
        fs = subrecording.get_sampling_frequency()
        num_samples = subrecording.get_num_frames()
        return np.arange(0, num_samples) / fs

    def append_recordings(self):
        """Append all the sub-recordings."""
        self.recordings_list = []
        # for i in range(len(self.ns5_files)):
        for i in range(self.num_files):
            file_path = os.path.join(self.data_folder, self.ns5_files[i])
            rec_i = se.read_blackrock(
                file_path=file_path, stream_id='5', block_index=1)
            self.recordings_list.append(rec_i)
        recording = si.append_recordings(self.recordings_list)

        durations = [recording.get_num_samples(segment_index=i)
                     for i in range(self.num_files)]  # hard-coded!!!
        self.fs = recording.get_sampling_frequency()
        self.start_times = [0] + np.cumsum(durations[: -1]).tolist()
        self._generate_time_vectors()

    def _generate_time_vectors(self):
        """Generate time vectors for each recording."""
        self.time_vectors = []
        for i, recording_i in enumerate(self.recordings_list):
            time_vector = self.get_time_vector(
                recording_i) + self.start_times[i]
            self.time_vectors.append(time_vector)

    def get_concatenated_recording(self):
        """Concatenate all the recordings and slice."""
        recording = si.concatenate_recordings(self.recordings_list)
        self.channel_ids = recording.get_channel_ids()
        self.recording = recording.channel_slice(self.channel_ids[0:32])
