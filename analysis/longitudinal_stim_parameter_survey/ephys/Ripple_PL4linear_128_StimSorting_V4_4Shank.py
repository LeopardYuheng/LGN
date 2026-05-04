# -*- coding: utf-8 -*-
"""
Created on Thu Nov  7 16:46:38 2024

@author: xiela
"""

# Standard library imports
import multiprocessing
from datetime import datetime
import sys

import re
import os
from pathlib import Path
import spikeinterface
from spikeinterface import (
    extractors as se, preprocessing as sp, curation as scur,
    full as si, qualitymetrics as qm
)

import spikeinterface.exporters as sexp

from spikeinterface.postprocessing import (
    compute_spike_amplitudes, compute_unit_locations,
    compute_template_similarity, compute_correlograms, compute_template_metrics
)
# External libraries
import numpy as np
import scipy
import scipy.io as sio

sys.path.append('Z:/xl_stimulation/Yuxuan_NEW/Summation-since20230612/TDT-Exp&Data/DataAnaCode/Ephys/EBL4Shank_Ripple&TDT_Yuxuan/util')

from probeinterface import Probe, ProbeGroup, generate_linear_probe
from probeinterface.io import write_probeinterface, read_probeinterface
from probeinterface.plotting import plot_probe, plot_probe_group

import mountainsort5 as ms5
import tdt
import time


import sortingview.views as vv


#%%
# Top-level global variables (do not rename)
_global_traces = None
_global_stim_ts = None
_global_fs = None
_global_n_samples = None
_global_ms_start = None
_global_order = None

def _init_worker(orig_traces, stim_timestamps, fs, n_samples, ms_start, order):
    """
    Pool initializer: set global variables in each child process.
    """
    global _global_traces, _global_stim_ts, _global_fs, _global_n_samples
    global _global_ms_start, _global_order
    _global_traces = orig_traces
    _global_stim_ts  = stim_timestamps
    _global_fs       = fs
    _global_n_samples= n_samples
    _global_ms_start = ms_start
    _global_order    = order

def _worker(ch):
    """
    Accept only a single channel index and use global variables
    to perform polynomial subtraction.
    """
    channel_data = _global_traces[:, ch].copy()
    for ts, next_ts in zip(_global_stim_ts, _global_stim_ts[1:]):
        start_sample = int(ts + (_global_ms_start / 1000) * _global_fs)
        end_sample   = int(next_ts) - 3
        if start_sample < 0 or end_sample > _global_n_samples:
            continue
        seg = channel_data[start_sample:end_sample]
        x = np.arange(len(seg))
        coeffs = np.polyfit(x, seg, _global_order)
        trend  = np.polyval(coeffs, x)
        channel_data[start_sample:end_sample] = seg - trend
    return ch, channel_data

#% Function: polynomial trend subtraction
def remove_polynomial_trend(rec_obj,
                            stim_timestamps,
                            Probe,
                            Bad_Ch_Idx=None,
                            ms_start=1.4,
                            ms_end=10,      # ms_end is currently unused
                            order=3):
    """
    Skip channels listed in Bad_Ch_Idx and perform polynomial
    trend subtraction on the remaining channels in parallel.
    """
    if Bad_Ch_Idx is None:
        Bad_Ch_Idx = []

    fs = rec_obj.sampling_frequency
    traces = rec_obj.get_traces()  # (n_samples, n_channels)
    n_samples, n_channels = traces.shape
    orig_traces = traces.copy()
    good_channels = [ch for ch in range(n_channels) if ch not in Bad_Ch_Idx]

    start_time = time.time()
    total = len(good_channels)

    # Use Pool(initializer=..., initargs=...) to set global variables
    pool = multiprocessing.Pool(
        initializer=_init_worker,
        initargs=(orig_traces, stim_timestamps, fs, n_samples, ms_start, order)
    )

    new_traces = orig_traces.copy()
    for idx, (ch, ch_data) in enumerate(pool.imap(_worker, good_channels), start=1):
        new_traces[:, ch] = ch_data
        print(f"Progress: {idx}/{total} channels processed", end='\r')
    pool.close()
    pool.join()
    print()  # newline

    # Construct a new Recording
    new_rec = si.NumpyRecording(
        new_traces,
        sampling_frequency=fs,
        channel_ids=rec_obj.get_channel_ids()
    )
    new_rec.set_probe(Probe, in_place=True)

    elapsed = time.time() - start_time
    print(f"Trend correction done: {total} good channels "
          f"(skipped {len(Bad_Ch_Idx)}) in {elapsed:.2f}s")

    # Optionally display probe information
    probe_rec = new_rec.get_probe()
    df_probe = probe_rec.to_dataframe(complete=True)[
        ["contact_ids", "device_channel_indices"]
    ]
    print(df_probe)
    print("Probe loaded?", new_rec.has_probe())

    return new_rec



#%% Utilization functions

def remove_polynomial_trend_serial(
    rec_obj,
    stim_timestamps,
    Probe,
    Bad_Ch_Idx=None,
    order=5
):
    """
    Serial version: automatically determines segment bounds, subtracts the
    per-sample median across good channels, then performs per-channel trend
    fitting and removal.

    Workflow for each segment between adjacent stimulation events:
      1) Compute the per-sample median vector `median_vec` from the original
         signal across all good channels.
      2) For each good channel: `centered = raw_segment - median_vec`
      3) Fit a polynomial to `centered` (degree=`order`) and remove the trend
      4) Preserve boundaries by restoring the first/last sample to the
         original centered values
      5) Write the "median-subtracted and detrended" result back to
         `new_traces`
    """
    import numpy as np
    import time
    import spikeinterface as si  # must already be installed

    if Bad_Ch_Idx is None:
        Bad_Ch_Idx = []

    # ---------------------------
    # 0) Basic information
    # ---------------------------
    fs = rec_obj.get_sampling_frequency()
    traces = rec_obj.get_traces()  # (n_samples, n_channels)
    n_samples, n_channels = traces.shape

    orig_traces = traces.copy()    # original baseline used for median/centered calculations
    new_traces  = np.array(orig_traces, copy=True)  # output buffer

    good_channels = [ch for ch in range(n_channels) if ch not in Bad_Ch_Idx]
    total_channels = len(good_channels)

    # ---------------------------
    # A) Clean stim_timestamps
    # ---------------------------
    ts_raw = np.asarray(stim_timestamps).reshape(-1)
    ts_raw = ts_raw[np.isfinite(ts_raw)]
    ts = ts_raw.astype(np.int64, copy=False)
    ts = ts[(ts >= 0) & (ts < n_samples)]
    ts = np.unique(np.sort(ts))

    if ts.size < 2:
        print("[TrendRemoval] WARNING: 有效的刺激时间戳少于 2 个，无法形成相邻片段。将跳过所有扣除步骤。")
        new_rec = si.NumpyRecording(
            new_traces,
            sampling_frequency=fs,
            channel_ids=rec_obj.get_channel_ids()
        )
        new_rec.set_probe(Probe, in_place=True)
        # Optionally display the probe
        probe_rec = new_rec.get_probe()
        df_probe = probe_rec.to_dataframe(complete=True)[
            ["contact_ids", "device_channel_indices"]
        ]
        print(df_probe)
        print("Probe loaded?", new_rec.has_probe())
        return new_rec

    # ---------------------------
    # B) Precompute: locate the zero immediately before the first nonzero sample
    # ---------------------------
    zero_all = np.all(orig_traces == 0, axis=1)  # (n_samples,)
    first_nonzero_idx_from = np.empty(n_samples, dtype=np.int64)
    next_idx = -1
    for i in range(n_samples - 1, -1, -1):
        if not zero_all[i]:
            next_idx = i
        first_nonzero_idx_from[i] = next_idx

    # ---------------------------
    # C) Adjacent event pairs and coarse filtering
    # ---------------------------
    min_points = max(order + 1, 8)
    safety_margin = 3  # keep consistent with the historical logic
    dt = ts[1:] - ts[:-1]
    valid_pair_mask = dt > (min_points + safety_margin)
    num_pairs_total = ts.size - 1
    num_pairs_valid = int(valid_pair_mask.sum())

    skipped_short        = int((~valid_pair_mask).sum())
    skipped_oob          = 0
    skipped_reversed     = 0
    skipped_too_few_pts  = 0
    used_segments_total  = 0

    ts_left  = ts[:-1][valid_pair_mask]
    ts_right = ts[1:][valid_pair_mask]

    # ---------------------------
    # D) Main loop (iterate by segment, then by channel)
    # ---------------------------
    start_time_loop = time.time()
    print(f"[TrendRemoval] Start processing: {total_channels} channels, "
          f"{num_pairs_total} adjacent pairs ({num_pairs_valid} valid by interval).")

    for pair_idx, (ts_l, ts_r) in enumerate(zip(ts_left, ts_right), start=1):
        # End point: next_ts - 3 (right edge not included)
        end_sample = int(ts_r) #- safety_margin
        if end_sample <= 0:
            skipped_oob += 1
            continue
        end_sample = min(n_samples, end_sample)

        # Start point: from ts_l, find the sample immediately before the
        # first nonzero sample (the last all-zero point, inclusive)
        j = first_nonzero_idx_from[ts_l]
        if j == -1 or j >= end_sample:
            start_sample = int(ts_l)
        else:
            start_sample = max(0, j - 1)

        if start_sample >= n_samples:
            skipped_oob += 1
            continue
        start_sample = max(0, start_sample)

        seg_len = end_sample - start_sample
        if seg_len <= 0:
            skipped_reversed += 1
            continue
        if seg_len < min_points or seg_len < (order + 1):
            skipped_too_few_pts += 1
            continue

        # ---- Per-sample median (using the original signal as reference) ----
        # shape: (seg_len,)
        segment_block_raw = orig_traces[start_sample:end_sample, good_channels]  # (m, Cg)
        median_vec = np.median(segment_block_raw, axis=1)  # (m,)

        x = np.arange(seg_len)

        # ---- For each good channel: fit and detrend the centered segment ----
        for ch in good_channels:
            raw_segment = orig_traces[start_sample:end_sample, ch]     # original segment, used for centered values and boundary reference
            centered    = raw_segment - median_vec                     # per request: subtract the median first

            if centered.size < (order + 1):
                skipped_too_few_pts += 1
                continue

            try:
                coeffs = np.polyfit(x, centered, order)
                trend  = np.polyval(coeffs, x)
            except Exception:
                skipped_too_few_pts += 1
                continue

            seg_new = centered - trend

            # Preserve boundaries: restore endpoints to the original
            # median-subtracted values (the endpoints of `centered`)
            seg_new[0]  = centered[0]
            seg_new[-1] = centered[-1]

            # Write back the "median-subtracted and detrended" result
            new_traces[start_sample:end_sample, ch] = seg_new
            used_segments_total += 1

        # Progress print
        if pair_idx % 1000 == 0 or pair_idx == num_pairs_valid:
            print(f"Trend subtraction (serial, centered->fit->remove) "
                  f"pair {pair_idx}/{num_pairs_valid}", end='\r')

    print()
    elapsed = time.time() - start_time_loop

    # ---------------------------
    # E) Summary statistics
    # ---------------------------
    print("[TrendRemoval] Summary (centered->fit->remove):")
    print(f"  Channels processed: {total_channels} (skipped {len(Bad_Ch_Idx)})")
    print(f"  Adjacent pairs total: {num_pairs_total}")
    print(f"    - Valid by interval: {num_pairs_valid}")
    print(f"    - Skipped (interval too short): {skipped_short}")
    print(f"  Segment-level usage (per-channel fits across pairs):")
    print(f"    - Used segments (fitted): {used_segments_total}")
    print(f"    - Skipped out-of-bounds: {skipped_oob}")
    print(f"    - Skipped reversed/zero-length: {skipped_reversed}")
    print(f"    - Skipped too few points (< max(order+1,{min_points})): {skipped_too_few_pts}")
    print(f"  Time elapsed: {elapsed:.2f} s")

    if used_segments_total == 0:
        print("[TrendRemoval] WARNING: 没有任何片段被用于拟合。可能原因："
              "(1) 相邻刺激间隔普遍过短；(2) 事件靠近文件尾；"
              "(3) 时间戳单位不是 '样本'；请检查 stim_timestamps 与 fs 的单位与范围。")

    # ---------------------------
    # F) Construct the new Recording object
    # ---------------------------
    new_rec = si.NumpyRecording(
        new_traces,
        sampling_frequency=fs,
        channel_ids=rec_obj.get_channel_ids()
    )
    new_rec.set_probe(Probe, in_place=True)

    probe_rec = new_rec.get_probe()
    df_probe = probe_rec.to_dataframe(complete=True)[
        ["contact_ids", "device_channel_indices"]
    ]
    print(df_probe)
    print("Probe loaded?", new_rec.has_probe())

    return new_rec


def rec_visualize(rec_obj, start_time, end_time):
    # Customized parameters: select a data segment for visualization checks
    start_time_param = start_time #145.16     # start time (s)
    end_time_param = end_time #145.26      # end time (s)
    channel_start = 6           # starting channel index (0-based)
    channel_end = 12           # ending channel index (inclusive)
    
    rec_obj
    
    # Convert to sample indices
    fs = rec_obj.get_sampling_frequency()
    start_sample = int(start_time_param * fs)
    end_sample = int(end_time_param * fs)
    start_sample = max(0, start_sample)
    end_sample = min(rec_obj.get_num_samples(), end_sample)
    channel_end = min(channel_end, rec_obj.get_num_channels()-1)
    
    # Get the selected channels and data
    segment_channel_ids = rec_obj.get_channel_ids()[channel_start : channel_end+1]
    traces = rec_obj.get_traces(
        channel_ids=segment_channel_ids,
        start_frame=start_sample,
        end_frame=end_sample
    )
    time_axis = np.linspace(start_time_param, end_time_param, traces.shape[0])
    
    # Plot the selected data segment
    fig, axes = plt.subplots(len(segment_channel_ids), 1, 
                             figsize=(12, 2*len(segment_channel_ids)),
                             sharex=True)
    if len(segment_channel_ids) == 1:
        axes = [axes]
    for ax, idx in zip(axes, range(len(segment_channel_ids))):
        ax.plot(time_axis, traces[:, idx]/4, linewidth=0.5)
        ax.set_ylabel(f"Ch {segment_channel_ids[idx]}\n(uV)", rotation=0, ha='right', va='center')
        ax.grid(alpha=0.3)
    axes[-1].set_xlabel("Time (s)")
    fig.suptitle(f"Raw Signals from {start_time_param}s to {end_time_param}s", y=1.02)
    plt.tight_layout()
    plt.show()
    
    return 0



#%
def generate_rec_piece4test(rec_complete, piece_T_start, piece_T_end):
    
    channel_ids = rec_complete.get_channel_ids()
    
    shank_signals = rec_complete.get_traces(
        start_frame=start_sample,
        end_frame=end_sample,
        channel_ids=channel_ids
    )
    
    signals_subset = shank_signals
    fs = rec_complete.get_sampling_frequency()
    
    # Create a new recording object
    rec4test = si.NumpyRecording(
        signals_subset[int(fs*piece_T_start):int(fs*piece_T_end)],
        sampling_frequency=fs,
        channel_ids=channel_ids
    )
        
    print("Recording object for test generated.")
    
    
    # Set probe information
    probe = rec_complete.get_probe()
    rec4test.set_probe(probe, in_place=True)
    probe_rec = rec4test.get_probe()
    # Display probe information (optional)
    df_probe = probe_rec.to_dataframe(complete=True).loc[:, ["contact_ids", "device_channel_indices"]]
    print(df_probe)
    

    return rec4test

#% Define a helper function to plot a short snippet of a recording and save the figure.
def plot_recording_snapshot(rec_obj,
                            title,
                            filename,
                            channel_indices=None,
                            pre_stim=10,
                            post_stim=30,
                            stim_timepoint=1468235,
                            Y_Lim=None):
    """
    Plot a snapshot of the recording for a sanity check.

    Parameters:
        rec_obj: RecordingExtractor object.
        title: Title of the plot.
        filename: File name (with full path) to save the figure.
        channel_indices: List of channel IDs to plot (default: first 16 channels).
        pre_stim: Time before the stimulation event in ms.
        post_stim: Time after the stimulation event in ms.
        stim_timepoint: The frame index corresponding to the stimulation event.
        Y_Lim: list or tuple [y_low, y_high], default None. If provided,
               use as plt.ylim; otherwise do not set y-limits.
    """
    fs = rec_obj.sampling_frequency
    # Determine start and end frames (convert ms to frames)
    start_frame = stim_timepoint - int(pre_stim / 1000 * fs)
    end_frame   = stim_timepoint + int(post_stim  / 1000 * fs)

    if channel_indices is None:
        # Plot up to 16 channels by default
        channel_ids = rec_obj.get_channel_ids()[16:min(32, rec_obj.get_num_channels())]
    else:
        channel_ids = channel_indices

    traces = rec_obj.get_traces(channel_ids=channel_ids,
                                start_frame=start_frame,
                                end_frame=end_frame)
    # Create a time axis in ms
    time_axis = np.linspace(-pre_stim, post_stim, traces.shape[0])

    # Create the figure with increased size and resolution
    plt.figure(figsize=(12, 2 * len(channel_ids)))
    for i, ch in enumerate(channel_ids):
        plt.subplot(len(channel_ids), 1, i + 1)
        plt.plot(time_axis, traces[:, i] / 4, linewidth=1.5)
        plt.ylabel(f"Ch {ch}", fontsize=14)
        # Only set y-limits if Y_Lim is given
        if Y_Lim is not None and len(Y_Lim) == 2:
            plt.ylim(Y_Lim)
        plt.grid(True)
        plt.tick_params(axis='both', which='major', labelsize=12)

    plt.xlabel("Time (ms)", fontsize=14)
    plt.suptitle(title, fontsize=16)
    plt.tight_layout()
    plt.savefig(filename)
    plt.close()

#%
def extract_sorted_ts_from_mat(folder: str,
                               filename: str,
                               cell_var: str = None) -> np.ndarray:
    """
    Read a Cx2 cell array from a .mat file in the specified folder,
    ignore the first-column labels, extract all numeric values from the
    second column, and return them in ascending order.

    Parameters
    ----------
    folder : str
        Path to the folder containing the .mat file.
    filename : str
        Name of the .mat file to read, including the extension.
    cell_var : str, optional
        Name of the cell-array variable in the .mat file. If None,
        automatically use the first variable whose name does not start
        with '__'.

    Returns
    -------
    ts : np.ndarray
        One-dimensional NumPy array containing all extracted values,
        sorted in ascending order.
    """
    # Construct and validate the path
    filepath = os.path.join(folder, filename)
    if not os.path.isfile(filepath):
        raise FileNotFoundError(f".mat 文件未找到: {filepath}")

    # Load the .mat file and remove singleton dimensions
    mat = sio.loadmat(filepath, squeeze_me=True, struct_as_record=False)
    # Automatically choose the variable name
    if cell_var is None:
        vars_in_mat = [k for k in mat.keys() if not k.startswith('__')]
        if not vars_in_mat:
            raise KeyError("在 .mat 文件中未找到任何变量。")
        cell_var = vars_in_mat[0]

    # Extract the cell array
    cell_array = mat[cell_var]
    cell_array = np.asarray(cell_array)
    if cell_array.ndim != 2 or cell_array.shape[1] < 2:
        raise ValueError(f"变量 '{cell_var}' 不是形如 C×2 的 cell 数组。")

    # Extract the second column; each element should be an Nx1 double array
    second_col = cell_array[:, 1]
    # Concatenate and sort
    ts = np.concatenate([np.asarray(arr).flatten() for arr in second_col])
    ts = np.sort(ts)

    return ts


def remove_hpf_trend_serial(
    rec_obj,
    stim_timestamps,
    Probe,
    Bad_Ch_Idx=None,
    *,
    subtract_median: bool = True,
    cutoff_hz: float = 1.0,
    filter_order: int = 3,
    safety_margin: int | None = None,   # New: default None => use the closed interval [ts_l, ts_r]
    sampling_rate: float | None = None, # Explicit sampling rate (Hz); if None, read from rec_obj
):
    """
    Serial version: replace polynomial detrending with a high-pass filter.
    Supports a "closed interval" segment mode and forces segment endpoints
    to zero.

    Segment definition (`ts_l` = current stimulus, `ts_r` = next stimulus):
      - If `safety_margin is None`:
            segment = [ts_l, ts_r] (closed interval; slicing uses
            `end_excl = ts_r + 1`)
            start = `ts_l` (no longer searches for the sample immediately
            before the first nonzero sample)
      - If `safety_margin` is an integer:
            `end_excl = max(0, ts_r - safety_margin)` (right edge excluded)
            start follows the legacy logic: from `ts_l`, find the sample
            immediately before the first nonzero value (the last all-zero
            sample). If everything remains zero before `end_excl`, use `ts_l`.

    Signal processing:
      - Optional `subtract_median=True`: compute the per-sample median across
        all good channels within each segment and subtract it first
      - Apply a Butterworth high-pass filter to each channel segment using
        zero-phase `filtfilt`
      - Endpoint handling (key new requirement):
            regardless of median subtraction, force the first and last sample
            of the filtered segment to 0
            (because physically all channels are 0 at each stimulation point)

    Parameters
    ----------
    subtract_median : Whether to subtract the per-sample median across good
        channels first (so processing happens on the median-subtracted signal)
    cutoff_hz : High-pass cutoff frequency in physical Hz
    filter_order : Butterworth filter order (2-4 recommended)
    safety_margin : `None` for closed-interval mode; integer for the legacy
        mode that leaves a margin before the next stimulus
    sampling_rate : Sampling rate in Hz; if None, use
        `rec_obj.get_sampling_frequency()`

    Returns
    -------
    spikeinterface.NumpyRecording
    """
    import numpy as np
    import time
    import spikeinterface as si
    from scipy.signal import butter, filtfilt

    if Bad_Ch_Idx is None:
        Bad_Ch_Idx = []

    # 0) Sampling rate / basic data
    fs = float(sampling_rate) if sampling_rate is not None else float(rec_obj.get_sampling_frequency())
    if not np.isfinite(fs) or fs <= 0:
        raise ValueError(f"无效采样率 fs={fs}")

    traces = rec_obj.get_traces()  # (n_samples, n_channels)
    n_samples, n_channels = traces.shape
    if n_channels == 0 or n_samples == 0:
        raise ValueError("空 Recording：没有通道或样本。")

    orig_traces = traces.copy()
    new_traces  = np.array(orig_traces, copy=True)

    good_channels = [ch for ch in range(n_channels) if ch not in Bad_Ch_Idx]
    if len(good_channels) == 0:
        print("[HPFTrend] WARNING: 无 good channels；返回原始。")
        new_rec = si.NumpyRecording(new_traces, sampling_frequency=fs,
                                    channel_ids=rec_obj.get_channel_ids())
        new_rec.set_probe(Probe, in_place=True)
        return new_rec
    total_channels = len(good_channels)

    # 1) Clean timestamps
    ts_raw = np.asarray(stim_timestamps).reshape(-1)
    ts_raw = ts_raw[np.isfinite(ts_raw)]
    ts = ts_raw.astype(np.int64, copy=False)
    ts = ts[(ts >= 0) & (ts < n_samples)]
    ts = np.unique(np.sort(ts))
    if ts.size < 2:
        print("[HPFTrend] WARNING: 有效刺激时间戳 < 2，跳过处理。")
        new_rec = si.NumpyRecording(new_traces, sampling_frequency=fs,
                                    channel_ids=rec_obj.get_channel_ids())
        new_rec.set_probe(Probe, in_place=True)
        return new_rec

    # 2) If using the legacy mode (`safety_margin` is an integer),
    #    build the lookup table for the first nonzero sample
    if safety_margin is not None:
        zero_all = np.all(orig_traces == 0, axis=1)  # (n_samples,)
        first_nonzero_idx_from = np.empty(n_samples, dtype=np.int64)
        next_idx = -1
        for i in range(n_samples - 1, -1, -1):
            if not zero_all[i]:
                next_idx = i
            first_nonzero_idx_from[i] = next_idx
    else:
        first_nonzero_idx_from = None  # not used

    # 3) Design the high-pass filter
    nyq = fs / 2.0
    wn = float(cutoff_hz) / nyq
    if not (0 < wn < 1):
        raise ValueError(f"cutoff_hz 必须在 (0, {nyq}) 内，当前 {cutoff_hz}")
    b, a = butter(filter_order, wn, btype="highpass")
    padlen_const = 3 * (max(len(a), len(b)) - 1)  # theoretical minimum length for filtfilt

    # 4) Statistics
    num_pairs_total = ts.size - 1
    skipped_short_coarse = 0
    skipped_oob        = 0
    skipped_reversed   = 0
    skipped_too_short  = 0
    used_segments_total = 0

    start_time = time.time()
    mode_str = "closed [ts_l, ts_r]" if safety_margin is None else f"end=ts_r-{safety_margin} (open)"
    print(f"[HPFTrend] Start: {total_channels} channels, {num_pairs_total} pairs, "
          f"fs={fs:.3f}Hz, cutoff={cutoff_hz}Hz, order={filter_order}, "
          f"subtract_median={subtract_median}, mode={mode_str}")

    # 5) Main loop
    for pair_idx in range(num_pairs_total):
        ts_l = int(ts[pair_idx])
        ts_r = int(ts[pair_idx + 1])

        if safety_margin is None:
            # Closed interval: [ts_l, ts_r] => slicing needs a +1 right edge
            start_sample = ts_l
            end_excl     = ts_r + 1
        else:
            # Legacy mode: leave a right-edge margin; start from the sample
            # immediately before the first nonzero one, or use ts_l if all
            # samples remain zero
            end_excl = int(ts_r) - int(safety_margin)
            if end_excl <= 0:
                skipped_oob += 1
                continue
            end_excl = min(n_samples, end_excl)

            j = first_nonzero_idx_from[ts_l]
            if j == -1 or j >= end_excl:
                start_sample = ts_l
            else:
                start_sample = max(0, j - 1)  # last all-zero sample (inclusive)

        # Basic bounds
        if start_sample < 0:
            start_sample = 0
        if end_excl > n_samples:
            end_excl = n_samples

        seg_len = end_excl - start_sample
        if seg_len <= 0:
            skipped_reversed += 1
            continue

        # Coarse filtering (even in None mode, enforce a minimum length;
        # strict filtering uses padlen)
        if seg_len <= 8:
            skipped_short_coarse += 1
            continue

        # Strict length check: must be long enough for filtfilt
        if seg_len <= padlen_const:
            skipped_too_short += 1
            continue

        # Build the segment matrix (original signal)
        seg_block_raw = orig_traces[start_sample:end_excl, good_channels]  # (m, Cg)

        # Per-sample median (optional)
        if subtract_median:
            median_vec = np.median(seg_block_raw, axis=1)  # (m,)
        else:
            median_vec = 0.0

        # Filtering and endpoint handling
        for ch in good_channels:
            raw_seg = orig_traces[start_sample:end_excl, ch]
            y = raw_seg - median_vec  # if median subtraction is disabled, this is equivalent to y=raw_seg

            try:
                y_hp = filtfilt(b, a, y, padlen=padlen_const)
            except Exception:
                skipped_too_short += 1
                continue

            # Linear shape correction can be skipped because the endpoints
            # will be forced to zero
            # Force the two segment endpoints to zero to match the physical
            # assumption that every stimulation point is zero
            y_hp[0]  = 0.0
            y_hp[-1] = 0.0

            new_traces[start_sample:end_excl, ch] = y_hp
            used_segments_total += 1

        # Progress
        if (pair_idx + 1) % 10 == 0 or (pair_idx + 1) == num_pairs_total:
            print(f"[HPFTrend] pair {pair_idx + 1}/{num_pairs_total}", end='\r')

    print()
    elapsed = time.time() - start_time

    # 6) Summary
    print("[HPFTrend] Summary:")
    print(f"  Channels processed: {total_channels} (skipped {len(Bad_Ch_Idx)})")
    print(f"  Adjacent pairs total: {num_pairs_total}")
    print(f"    - Skipped (coarse too short): {skipped_short_coarse}")
    print(f"  Segment-level:")
    print(f"    - Used segments (filtered): {used_segments_total}")
    print(f"    - Skipped out-of-bounds: {skipped_oob}")
    print(f"    - Skipped reversed/zero-length: {skipped_reversed}")
    print(f"    - Skipped too short for filtfilt (padlen={padlen_const}): {skipped_too_short}")
    print(f"  Time elapsed: {elapsed:.2f} s")

    if used_segments_total == 0:
        print("[HPFTrend] WARNING: 没有任何片段被使用。可能原因：相邻间隔过短、cutoff 过低导致 pad 较大、"
              "或时间戳单位/范围异常。")

    # 7) Return the Recording
    new_rec = si.NumpyRecording(
        new_traces,
        sampling_frequency=fs,
        channel_ids=rec_obj.get_channel_ids()
    )
    new_rec.set_probe(Probe, in_place=True)
    return new_rec


#%%

from typing import Optional

import matplotlib
print(matplotlib.get_backend())

# Use interactive GUI backend only if not already set
if matplotlib.get_backend() not in ['TkAgg', 'Qt5Agg', 'QtAgg']:
    try:
        matplotlib.use('Qt5Agg')  # or use 'TkAgg' depending on your system support
    except Exception as e:
        print("Warning: Could not set interactive backend:", e)

import matplotlib.pyplot as plt
from matplotlib.widgets import CheckButtons, Button

def format_impedance(imp):
    if imp >= 1e6:
        return f"{imp/1e6:.2f} Mohm"
    elif imp >= 1e3:
        return f"{imp/1e3:.0f}k Ω"
    else:
        return f"{imp:.0f} Ω"

def label_bad_ch_from_rec(
    rec_obj,
    fs: float,
    impedance: Optional[np.ndarray] = None
) -> list:
    """
    Manually screen bad channels using an interactive plot.

    Parameters:
        traces: 2D numpy array (T x N), signal traces
        fs: sampling frequency
        impedance: Optional 1D array of impedance values

    Returns:
        List of bad channel indices (as integers)
    """
    
    
    traces = rec_obj.get_traces()  # shape: (n_samples, n_channels)

    show_impedance = impedance is not None
    T, N = traces.shape
    channel_ids = [str(i) for i in range(N)]

    segment_duration   = 5
    n_samples_segment  = int(segment_duration * fs)
    screening_duration = 5
    total_samples      = min(T, int(screening_duration * fs))
    segment_starts     = np.arange(0, total_samples, n_samples_segment)

    bad_channels = set()

    for seg_start in segment_starts:
        seg_end    = min(seg_start + n_samples_segment, total_samples)
        time_axis  = np.arange(seg_start, seg_end) / fs

        fig = plt.figure(figsize=(12, 8))
        ax_anno = fig.add_axes([0.1, 0.1, 0.10, 0.8])
        ax_main = fig.add_axes([0.1, 0.1, 0.75, 0.8])
        rax     = fig.add_axes([0.85, 0.1, 0.12, 0.8])

        seg_stds = np.std(traces[seg_start:seg_end, :], axis=0)
        offset_multiplier = np.median(seg_stds) * 15
        offsets = -np.arange(len(channel_ids)) * offset_multiplier

        for i, cid in enumerate(channel_ids):
            ax_main.plot(time_axis, traces[seg_start:seg_end, i] + offsets[i], color='k', lw=0.8)

        ax_main.set_title(f"Segment {seg_start/fs:.1f}-{seg_end/fs:.1f}s")
        ax_main.set_xlabel("Time (s)")
        ax_main.set_xlim([time_axis[0], time_axis[-1]])
        ax_main.set_ylim([offsets.min() - offset_multiplier, offsets.max() + offset_multiplier])
        ax_main.set_yticks([])

        ax_anno.set_ylim(ax_main.get_ylim())
        ax_anno.set_yticks(offsets)
        if show_impedance:
            anno_labels = [f"{cid}:{format_impedance(impedance[i])}" for i, cid in enumerate(channel_ids)]
        else:
            anno_labels = [str(cid) for cid in channel_ids]
        ax_anno.set_yticklabels(anno_labels, fontsize=8)
        ax_anno.tick_params(axis='x', which='both', bottom=False, top=False, labelbottom=False)
        for spine in ["top", "right", "bottom"]:
            ax_anno.spines[spine].set_visible(False)

        seg_bad_flags = {int(cid): (int(cid) in bad_channels) for cid in channel_ids}
        visibility    = [seg_bad_flags[int(cid)] for cid in channel_ids]
        check         = CheckButtons(rax, channel_ids, visibility)

        def checkbox_callback(label):
            idx = int(label)
            seg_bad_flags[idx] = not seg_bad_flags[idx]
            if seg_bad_flags[idx]:
                print(f"Channel {idx} marked bad.")
            else:
                print(f"Channel {idx} unmarked.")

        check.on_clicked(checkbox_callback)

        finish_ax = fig.add_axes([0.85, 0.9, 0.12, 0.05])
        finish_button = Button(finish_ax, 'Finish')
        finish_button.label.set_fontsize(10)
        exit_loop = {'flag': False}

        def finish_callback(event):
            print("Exiting screening loop.")
            exit_loop['flag'] = True

        finish_button.on_clicked(finish_callback)

        print(f"Reviewing segment {seg_start/fs:.1f}-{seg_end/fs:.1f}s.")
        plt.show()

        for cid, is_bad in seg_bad_flags.items():
            if is_bad:
                bad_channels.add(cid)
            else:
                bad_channels.discard(cid)

        if exit_loop['flag']:
            break

    print(f"Bad channels: {sorted(bad_channels)}")
    return sorted(bad_channels)

def prune_by_spacing(arr: np.ndarray, min_gap: int) -> np.ndarray:
    """
    Remove the smaller element from adjacent entries in a sorted 1D int32
    array whenever their spacing is smaller than `min_gap`.

    Rule: if `x[i] - previous_kept < min_gap`, remove the smaller value
    (the previously kept one) and keep the larger value (the current one).

    Parameters
    ----------
    arr : np.ndarray
        Sorted array of shape (N,); `int32` is recommended.
    min_gap : int
        Minimum allowed spacing. The condition is strict:
        removal happens only when the difference is `< min_gap`;
        `== min_gap` is considered acceptable.

    Returns
    -------
    np.ndarray
        Processed array with the same dtype as the input.
    """
    if arr.ndim != 1:
        raise ValueError("arr 必须是一维数组")
    if len(arr) <= 1:
        return arr.astype(np.int32, copy=True)

    # Use a list as a stack to store results and, when needed,
    # remove the second-to-last element (the smaller one)
    out = []
    for x in arr:
        if not out:
            out.append(int(x))
            continue

        if x - out[-1] >= min_gap:
            # Far enough from the last kept value, so keep it directly
            out.append(int(x))
        else:
            # Spacing is too small: remove the smaller value according to the
            # rule (in the current pair, that smaller value is out[-1])
            # Replace out[-1] with x
            out[-1] = int(x)
            # It may also be too close to earlier values, so keep cleaning backward
            while len(out) >= 2 and (out[-1] - out[-2] < min_gap):
                # Remove the smaller value out[-2] and keep the larger out[-1]
                del out[-2]

    return np.asarray(out, dtype=arr.dtype)


#%%

from concurrent.futures import ThreadPoolExecutor, as_completed


def zero_bridge_filter(
    orig_trace_data,
    Stim_Onset_Ts,
    Bad_Channel_Indexes,
    sampling_rate: float = 30000.0,
    pre_stim_range: float = 1.0,   # ms
    post_stim_range: float = 1.0,  # ms
    Width_Filter_Threshold: int = 10,
    save_folder: str | Path | None = None,
    debug: bool = True,
    Complete_data: bool = True,
    n_jobs: int = 1,               # parallelize by channel
    Sign_Detection: bool = False,  # whether to enable sign-change pseudo-zero logic
):
    """
    Apply "zero-point / sign-change bridging" to a T*N trace array:
      - Channels in `Bad_Channel_Indexes` are left unchanged.
      - For all other channels:
        1) Check whether each `Stim_Onset_Ts` location equals 0; raise an
           error otherwise.
        2) Find all consecutive zero segments and mark those that contain a
           stimulation point.
        3) For zero segments that contain a stimulation point, remove the
           interior zeros and keep only the endpoint zeros (`zero_idx_valid`).
        4) For the pre/post window around each stimulation point:
           - find zero points in the window using `zero_idx_valid`
           - if `Sign_Detection=True`, also find sign-change points in the
             window (signal goes positive-to-negative or negative-to-positive,
             and is not inside a continuous zero segment) and treat them as
             "pseudo-zero" points
        5) Sort all zero/pseudo-zero points; if the spacing between two
           adjacent points is < `Width_Filter_Threshold`, set that interval
           to zero.

    Returns:
      new_trace_data: new array with the same shape as `orig_trace_data`
    """

    # ========== Basic checks ==========
    if not isinstance(orig_trace_data, np.ndarray):
        raise TypeError("orig_trace_data 必须是 numpy.ndarray")

    if orig_trace_data.ndim != 2:
        raise ValueError(f"orig_trace_data 必须是 2D (T, N)，当前形状为 {orig_trace_data.shape}")

    T, N = orig_trace_data.shape

    if sampling_rate <= 0:
        raise ValueError("sampling_rate 必须为正数。")

    if pre_stim_range < 0 or post_stim_range < 0:
        raise ValueError("pre_stim_range 和 post_stim_range 必须为非负。")

    if Width_Filter_Threshold <= 0:
        raise ValueError("Width_Filter_Threshold 必须为正整数。")

    Stim_Onset_Ts = np.asarray(Stim_Onset_Ts).astype(int).ravel()
    if Stim_Onset_Ts.size == 0:
        raise ValueError("Stim_Onset_Ts 为空，无法执行操作。")

    # Handle out-of-range stim indices depending on Complete_data
    if Complete_data:
        if np.any(Stim_Onset_Ts < 0) or np.any(Stim_Onset_Ts >= T):
            raise ValueError(
                f"Stim_Onset_Ts 中存在超出 [0, {T-1}] 的值，"
                f"min={Stim_Onset_Ts.min()}, max={Stim_Onset_Ts.max()}"
            )
        Stim_valid = Stim_Onset_Ts
    else:
        if np.any(Stim_Onset_Ts < 0) or np.any(Stim_Onset_Ts >= T):
            if debug:
                print(
                    "[警告] Complete_data=False：Stim_Onset_Ts 里有越界值，"
                    "将自动忽略所有不在 [0, T-1] 范围内的 Stim 点。"
                )
            Stim_valid = Stim_Onset_Ts[(Stim_Onset_Ts >= 0) & (Stim_Onset_Ts < T)]
            if Stim_valid.size == 0:
                raise ValueError(
                    "Complete_data=False，但所有 Stim_Onset_Ts 都越界，无法进行处理。"
                )
        else:
            Stim_valid = Stim_Onset_Ts

    # Bad channel validation
    Bad_Channel_Indexes = set(int(i) for i in Bad_Channel_Indexes)
    for ch in Bad_Channel_Indexes:
        if ch < 0 or ch >= N:
            raise ValueError(f"Bad_Channel_Indexes 中存在非法通道 index: {ch}, 合法范围为 [0, {N-1}]")

    # ms -> sample
    pre_samples = int(round(pre_stim_range * sampling_rate / 1000.0))
    post_samples = int(round(post_stim_range * sampling_rate / 1000.0))

    if debug:
        print(f"[信息] T={T}, N={N}, S={Stim_valid.size}")
        print(f"[信息] pre_samples={pre_samples}, post_samples={post_samples}, "
              f"Width_Filter_Threshold={Width_Filter_Threshold}, n_jobs={n_jobs}, "
              f"Sign_Detection={Sign_Detection}")

    new_trace_data = orig_trace_data.copy()
    modifications = []  # (ch, seg_start, seg_end)

    # ========== Per-channel processing logic (parallelizable) ==========
    def _process_one_channel(ch: int):
        """
        Returns: (ch_idx, new_trace_ch, channel_mods)
          - new_trace_ch: shape (T,)
          - channel_mods: [(seg_start, seg_end), ...] zeroed segments
            within this channel
        """
        if ch in Bad_Channel_Indexes:
            if debug:
                print(f"[跳过] channel {ch} 在 Bad_Channel_Indexes 中，不做修改。")
            return ch, orig_trace_data[:, ch].copy(), []

        trace = orig_trace_data[:, ch]

        # Step 3: verify that the stim points are zero
        stim_vals = trace[Stim_valid]
        non_zero_mask = stim_vals != 0
        if np.any(non_zero_mask):
            bad_indices = Stim_valid[non_zero_mask]
            example_idx = bad_indices[0]
            example_val = trace[example_idx]
            raise ValueError(
                f"Channel {ch}: Stim_Onset_Ts 中至少有一个位置的值不为 0，"
                f"例如 index={example_idx}, value={example_val}。"
            )

        # All indices where the value is zero
        zero_idx = np.flatnonzero(trace == 0)
        if zero_idx.size == 0:
            if debug:
                print(f"[Channel {ch}] 该通道没有任何 0 点，跳过宽度过滤。")
            return ch, trace.copy(), []

        # === Use zero_idx to find all consecutive zero segments ===
        diff = np.diff(zero_idx)
        seg_zero_start_idx = np.concatenate(([0], np.nonzero(diff > 1)[0] + 1))
        seg_zero_end_idx   = np.concatenate((np.nonzero(diff > 1)[0], [zero_idx.size - 1]))

        seg_start_val = zero_idx[seg_zero_start_idx]  # first zero index of each consecutive zero segment
        seg_end_val   = zero_idx[seg_zero_end_idx]    # last zero index of each consecutive zero segment
        num_segs = seg_start_val.size

        # Mark which zero segments contain at least one stim
        seg_has_stim = np.zeros(num_segs, dtype=bool)
        for stim_idx in Stim_valid:
            if stim_idx < 0 or stim_idx >= T:
                continue
            k = np.searchsorted(seg_start_val, stim_idx, side='right') - 1
            if k >= 0 and stim_idx <= seg_end_val[k]:
                seg_has_stim[k] = True

        # Remove interior zeros from zero segments that contain a stim,
        # while keeping the endpoints
        interior_mask = np.zeros(zero_idx.size, dtype=bool)
        interest_seg_ids = np.nonzero(seg_has_stim)[0]
        for j in interest_seg_ids:
            s_idx = seg_zero_start_idx[j]
            e_idx = seg_zero_end_idx[j]
            if e_idx - s_idx >= 2:
                # s_idx+1 : e_idx-1 is the interior; note that e_idx is the
                # index of the last zero
                interior_mask[s_idx + 1:e_idx] = True

        zero_idx_valid = zero_idx[~interior_mask]

        if debug:
            n_interest = int(seg_has_stim.sum())
            print(f"[Channel {ch}] 全局 0 段数量={num_segs}，包含 stim 的段数量={n_interest}，"
                  f"有效 0 点数={zero_idx_valid.size}")

        if zero_idx_valid.size == 0 and not Sign_Detection:
            if debug:
                print(f"[Channel {ch}] 去掉连续 0 段内部后没有可用 0 点，且未启用 Sign_Detection，跳过该通道。")
            return ch, trace.copy(), []

        # If Sign_Detection is enabled, precompute:
        #   1) in_zero_segment: which samples lie inside any continuous zero
        #      segment (including endpoints)
        #   2) sign_change_idx_all: all positions where the sign changes from
        #      positive to negative or vice versa, with both sides nonzero
        if Sign_Detection:
            in_zero_segment = np.zeros(T, dtype=bool)
            for s_val, e_val in zip(seg_start_val, seg_end_val):
                in_zero_segment[s_val:e_val + 1] = True

            # Store signs as int8 (-1, 0, 1) to avoid the larger memory
            # footprint of int64
            nonzero_mask_trace = trace != 0

            sign_trace = np.zeros(T, dtype=np.int8)
            sign_trace[trace > 0] = 1
            sign_trace[trace < 0] = -1

            # Adjacent sign product < 0 and both endpoints nonzero
            # -> a true sign-change point (nonzero <-> nonzero)
            sign_prod = sign_trace[1:] * sign_trace[:-1]  # int8 即可
            sc_mask = (sign_prod < 0) & nonzero_mask_trace[1:] & nonzero_mask_trace[:-1]
            sign_change_idx_all = np.flatnonzero(sc_mask) + 1

            if debug:
                print(f"[Channel {ch}] Sign_Detection: 全局变号点数量={sign_change_idx_all.size}")
        else:
            in_zero_segment = None
            sign_change_idx_all = None

        # Step 5: for each stim window, collect candidate "zero points"
        # (true zeros or pseudo-zeros)
        zero_positions_set = set()

        for stim_idx in Stim_valid:
            win_start = max(0, stim_idx - pre_samples)
            win_end   = min(T - 1, stim_idx + post_samples)
            if win_end < win_start:
                continue

            # (1) True zero points inside the window (zero_idx_valid)
            if zero_idx_valid.size > 0:
                l = np.searchsorted(zero_idx_valid, win_start, side='left')
                r = np.searchsorted(zero_idx_valid, win_end,   side='right')
                if r > l:
                    for pos in zero_idx_valid[l:r]:
                        zero_positions_set.add(int(pos))

            # (2) If Sign_Detection is enabled, also include sign-change
            # points inside the window as pseudo-zero points
            if Sign_Detection and sign_change_idx_all is not None and sign_change_idx_all.size > 0:
                l2 = np.searchsorted(sign_change_idx_all, win_start, side='left')
                r2 = np.searchsorted(sign_change_idx_all, win_end,   side='right')
                if r2 > l2:
                    sc_in_window = sign_change_idx_all[l2:r2]
                    if in_zero_segment is not None:
                        sc_in_window = sc_in_window[~in_zero_segment[sc_in_window]]
                    for pos in sc_in_window:
                        zero_positions_set.add(int(pos))

        if not zero_positions_set:
            if debug:
                print(f"[Channel {ch}] 在所有 stim 窗口内未找到任何候选零点/变号点，跳过宽度过滤。")
            return ch, trace.copy(), []

        zero_positions = np.array(sorted(zero_positions_set), dtype=int)

        if debug:
            print(f"[Channel {ch}] 用于宽度过滤的候选点数量: {zero_positions.size}")

        # Step 6: if the spacing between adjacent candidate points is below
        # the threshold, zero out the entire interval between them
        new_trace_ch = trace.copy()
        channel_mods = []

        for i in range(len(zero_positions) - 1):
            p1 = zero_positions[i]
            p2 = zero_positions[i + 1]
            width = p2 - p1

            if width < Width_Filter_Threshold:
                new_trace_ch[p1:p2 + 1] = 0
                channel_mods.append((p1, p2))

        if debug:
            print(f"[Channel {ch}] 置 0 片段数: {len(channel_mods)}")

        return ch, new_trace_ch, channel_mods

    # ========== Serial / parallel execution ==========
    if n_jobs is None or n_jobs <= 1:
        for ch in range(N):
            ch_idx, new_ch, ch_mods = _process_one_channel(ch)
            new_trace_data[:, ch_idx] = new_ch
            for (s, e) in ch_mods:
                modifications.append((ch_idx, s, e))
    else:
        n_workers = min(max(1, n_jobs), N)
        if debug:
            print(f"[并行] 使用 ThreadPoolExecutor，workers={n_workers}")

        with ThreadPoolExecutor(max_workers=n_workers) as ex:
            future_to_ch = {ex.submit(_process_one_channel, ch): ch for ch in range(N)}
            for fut in as_completed(future_to_ch):
                ch_idx, new_ch, ch_mods = fut.result()
                new_trace_data[:, ch_idx] = new_ch
                for (s, e) in ch_mods:
                    modifications.append((ch_idx, s, e))

    # ========== Draw debug comparison plots ==========
    if save_folder is not None and len(modifications) > 0:
        save_folder = Path(save_folder)
        subfolder = save_folder / "zero_filter_debug_plots"
        subfolder.mkdir(parents=True, exist_ok=True)

        if debug:
            print(f"[绘图] 总置 0 片段数: {len(modifications)}，保存到: {subfolder}")

        num_to_plot = min(5, len(modifications))
        idx_choices = np.random.choice(len(modifications), size=num_to_plot, replace=False)

        window_ms = 50.0
        window_samples = int(round(window_ms * sampling_rate / 1000.0))
        half_win = max(1, window_samples // 2)

        for i_plot, mod_idx in enumerate(idx_choices, start=1):
            ch, seg_start, seg_end = modifications[mod_idx]
            center = (seg_start + seg_end) // 2

            win_start = max(0, center - half_win)
            win_end   = min(T - 1, center + half_win)
            if win_end <= win_start:
                win_end = min(T - 1, win_start + 1)

            neighbor_channels = [c for c in range(ch - 2, ch + 3) if 0 <= c < N]
            t_axis = (np.arange(win_start, win_end + 1) - center) / sampling_rate * 1000.0

            fig, axes = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
            fig.suptitle(
                f"Channel {ch}, segment [{seg_start}, {seg_end}], "
                f"window ~{window_ms:.1f} ms"
            )

            ax1 = axes[0]
            for idx_n, c in enumerate(neighbor_channels):
                offset = idx_n * 0.5
                ax1.plot(
                    t_axis,
                    orig_trace_data[win_start:win_end + 1, c] + offset,
                    label=f"ch {c}"
                )
            ax1.axvline(0, linestyle="--", alpha=0.6)
            ax1.set_ylabel("orig (offset by ch)")
            ax1.legend(loc="upper right", fontsize=8)

            ax2 = axes[1]
            for idx_n, c in enumerate(neighbor_channels):
                offset = idx_n * 0.5
                ax2.plot(
                    t_axis,
                    new_trace_data[win_start:win_end + 1, c] + offset,
                    label=f"ch {c}"
                )
            ax2.axvline(0, linestyle="--", alpha=0.6)
            ax2.set_xlabel("Time (ms, center=segment middle)")
            ax2.set_ylabel("new (offset by ch)")

            plt.tight_layout(rect=[0, 0, 1, 0.95])

            fname = subfolder / f"zero_filter_ch{ch}_seg{seg_start}_{seg_end}_#{i_plot}.png"
            fig.savefig(fname, dpi=200)
            plt.close(fig)

            if debug:
                print(f"[绘图] 保存: {fname}")

    elif save_folder is not None and len(modifications) == 0 and debug:
        print("[绘图] 未进行任何置 0 操作，不生成对比图。")

    return new_trace_data




#%%


#% Timing start
start_time = time.time()

# ICMS 148 1111
data_folder = 'Z:/xl_stimulation/ICMS148/11-Nov-2025/4Shank128_PoissonPattern_Multi_Lambda'


# ICMS 148 1025
#data_folder = 'Z:/xl_stimulation/ICMS148/24-Oct-2025/4Shank128_PoissonPattern_Multi_Lambda'




file_name = 'ephys'
file_path = os.path.join(data_folder, file_name)

rec_all = se.read_blackrock(file_path=file_path)


# Timing end
end_time = time.time()

elapsed_time = end_time - start_time
print(f"Data loading time：{elapsed_time:.6f} s")


#%

RecPropertyKeys = rec_all.get_property_keys()
TotalDur = rec_all.get_total_duration()
print(TotalDur)

#%%


# Define the Ripple channel lists for each shank
# (ordered by depth along the y-axis from 0 upward)

 
Ripple_id_Shank0 = [104,102,106,97,99,101,103,105,107,109,111,113,115,117,119,
                    121,123,69,73,100,90,95,93,91,89,87,85,83,81,79,77,75]

Ripple_id_Shank1 = [67,	125,71,68,124,98,92,88,82,112,80,114,78,72,122,70,127,
                    65,126,66,128,118,74,96,94,84,110,108,86,76,116,120]

Ripple_id_Shank2 = [63,1,4,64,2,12,56,10,14,34,36,20,46,22,44,54,3,61,57,62,6,
                    60,8,58,52,16,50,32,38,42,48,18]

Ripple_id_Shank3 = [59,5,55,53,51,49,47,45,43,41,39,37,35,30,40,33,7,9,11,13,
                    15,17,19,21,23,25,27,29,31,24,26,28]

# Combine all Ripple lists into one list for easier downstream indexing
#TDT_ids_all = [TDT_id_Shank0, TDT_id_Shank1, TDT_id_Shank2, TDT_id_Shank3]
Ripple_ids_all = [Ripple_id_Shank0, Ripple_id_Shank1, Ripple_id_Shank2, Ripple_id_Shank3]





#% Create a save folder for pipeline outputs
# Create the output folder and define ms5 parameters
current_date_string = datetime.now().strftime('%d-%b-%Y_%H%M')
Mother_save_folder = os.path.join(data_folder, "Processed_" + current_date_string)
os.makedirs(Mother_save_folder, exist_ok=True)
print(f"Save folder created at: {Mother_save_folder}")



#%%
stim_folder   = data_folder
stim_filename = "stim_times_arr.mat"
cell_var = "stim_times_arr"  
stim_ts = extract_sorted_ts_from_mat(stim_folder, stim_filename, cell_var)



#%
stim_ts_sorted_raw = np.unique(stim_ts)
stim_ts_sorted = prune_by_spacing(stim_ts_sorted_raw , min_gap=30)

#%% Broken Channel List

#ICMS148 1111
Bad_Ch_shank_list = [ [0,1,2,3,4,5,13,14],
	    [],
 	    [4,11,12,27,30,31],
	    [28] ]



#ICMS148 1025
#Bad_Ch_shank_list = [ [0,1,2,3,11,13,14],
#	    [1,2,5,6,7,10,30,31],
# 	    [4,11,12,27,30,31],
#	    [27,28] ]

    
    


#%%

url_list = []

#for count in range(0, 1):
for count in range(2,4):
    
    #%%
    count = 0
    shank = count
    
    save_folder = os.path.join(Mother_save_folder, "Shank_" + str(shank))
    os.makedirs(save_folder, exist_ok=True)
        
    print(f"Processing shank {shank} ...")
    # Construct the corresponding probe file path, for example:
    # 'util/EBL4Shank/NET-EBL-4by32-TDT4Py-shank0.json'
    probe_filename = f'Z:/xl_stimulation/Yuxuan_NEW/Summation-since20230612/2025-Exp&Data/DataAnaCode/Ephys/EBL4Shank_Ripple&TDT_Yuxuan/2025_New_Pipeline/ChMap/Linear/NET-PL-4by32linear-Depth4Py-1shank.json'
    
    # Read the probe file
    pi = read_probeinterface(probe_filename)
    probe = pi.probes[0]
    
    
    current_Ripple_ids = Ripple_ids_all[shank]
    shank_channel_indices = [idx for idx in current_Ripple_ids]
    shank_channel_ids = [str(ch) for ch in shank_channel_indices]   
                         
    start_time = 0      # start time (s)
    end_time =  1200 #TotalDur       # end time (s)

    # Convert to sample indices

    #EndFrame = int(fs*TotalDur)
    total_duration = rec_all.get_total_duration()
    sampling_freq = rec_all.sampling_frequency
    start_sample = int(start_time * sampling_freq)
    end_sample = int(end_time * sampling_freq)

    shank_signals = rec_all.get_traces(
        channel_ids=shank_channel_ids,
        start_frame=start_sample,
        end_frame=end_sample
    )
    
    signals_subset = shank_signals
    channel_ids = rec_all.get_channel_ids()
    channel_ids_subset = channel_ids[0:32]
    
    #% Create a new recording object
    rec = si.NumpyRecording(
        signals_subset,
        sampling_frequency=sampling_freq,
        channel_ids=channel_ids_subset
    )
    
    #%
    # Set probe information
    rec.set_probe(probe, in_place=True)
    probe_rec = rec.get_probe()
    # Display probe information (optional)
    df_probe = probe_rec.to_dataframe(complete=True).loc[:, ["contact_ids", "device_channel_indices"]]
    print(df_probe)
    
    fs = rec.get_sampling_frequency()
    
    # Validate the output
    print("== Data Successfully Loaded ==")
    print("If loading probe successful?", rec.has_probe())
    print("Recording object:", rec)
    print("Channel number:", rec.get_num_channels())
    print("Sampling frequency:", rec.sampling_frequency, "Hz")
    print("Duration:", rec.get_total_duration(), "s")
    print("Channel names:", rec.get_channel_ids())
    
    #%
    #label_bad_ch_from_rec(rec, rec.get_sampling_frequency()) 

    Bad_ch_idx = Bad_Ch_shank_list[count] 


    #%
    
    # rec4test = generate_rec_piece4test(rec, 0, 180)
    
    stim_check_point =  1341889
 # ICMS148 1025
#   1821301 # ICMS148 1015

    #11717909 #ICMS 148 1001

    #628248 #ICMS 148 1005


#30681886

    Rec_visT_start = 200.0#147.78
    Rec_visT_end = 202.0#147.84

    # # pre_stim=10,
    # # post_stim=70,
    
    # # print("Does rec object has probe?", rec4test.has_probe())
    
    #% Sanity check: plot the raw recording
    plot_recording_snapshot(rec, "Raw Recording", 
                            os.path.join(save_folder, "0_raw_recording.png"), 
                            stim_timepoint=stim_check_point,
                            pre_stim=20,
                            post_stim=80)
    print("Raw recording snapshot saved.")
    rec_visualize(rec, Rec_visT_start, Rec_visT_end)
    
    
    # rec_trend_removed = remove_hpf_trend_serial(rec,
    #     stim_ts_sorted, 
    #     probe,
    #     Bad_Ch_Idx=Bad_ch_idx,
    #     subtract_median = False,
    #     cutoff_hz = 300.0,
    #     filter_order = 5,
    #     safety_margin = 0   # End point: end_sample = next_ts - safety_margin (right edge excluded)
    #     #sampling_rate: float | None = None,  # Explicitly specify the sampling rate (Hz); if None, read it from rec_obj
    # )
    
    
    #%
    rec_trend_removed = remove_polynomial_trend_serial(rec, stim_ts_sorted, 
                                                probe,
                                                Bad_Ch_Idx=Bad_ch_idx,
                                                order=6)
    
    #%
    plot_recording_snapshot(rec_trend_removed, "Polynomial trend removed", 
                            os.path.join(save_folder, "1_trend_removed.png"), 
                            stim_timepoint=stim_check_point, 
                            pre_stim=20,
                            post_stim=80)
    print("Polynomial trend removed snapshot saved.")
    #%%
    rec_visualize(rec_trend_removed, Rec_visT_start, Rec_visT_end) # Rec_visT_start, Rec_visT_end)
    
    
    
    #%%
    
    orig_traces = rec_trend_removed.get_traces()  # (n_samples, n_channels)
    n_samples, n_channels = orig_traces.shape

    #%
    new_data = zero_bridge_filter(
        orig_trace_data=orig_traces,         # shape (T, N)
        Stim_Onset_Ts=stim_ts_sorted,            # shape (S,)
        Bad_Channel_Indexes=Bad_ch_idx,#[0, 5, 7],          # e.g. bad channels
        sampling_rate=30000,
        pre_stim_range=1.0,                     # ms
        post_stim_range=1.5,                    # ms
        Width_Filter_Threshold=30,              # samples
        save_folder=save_folder,     # will create the zero_filter_debug_plots subfolder
        debug=False,
        Complete_data=False,
        n_jobs=4,               # parallelize by channel
        Sign_Detection = True
    )



    rec_zeroed = si.NumpyRecording(
        new_data,
        sampling_frequency=fs,
        channel_ids=rec_trend_removed.get_channel_ids()
    )
    rec_zeroed.set_probe(probe, in_place=True)

    probe_rec = rec_zeroed.get_probe()
    df_probe = probe_rec.to_dataframe(complete=True)[
        ["contact_ids", "device_channel_indices"]
    ]
    print(df_probe)
    print("Probe loaded?", rec_zeroed.has_probe())

    #%
    plot_recording_snapshot(rec_zeroed, "Sharp peaks zeroed", 
                            os.path.join(save_folder, "2_zero_bridged.png"), 
                            stim_timepoint=stim_check_point, 
                            pre_stim=20,
                            post_stim=80)
    print("Sharp peaks zeroed snapshot saved.")
    rec_visualize(rec_zeroed, Rec_visT_start, Rec_visT_end) # Rec_visT_start, Rec_visT_end)
    



    #%%
    
    bad_channel_ids = [1+x for x in Bad_ch_idx ]
    bad_channel_ids = [str(x) for x in bad_channel_ids]
    
    #%
    
    rec_trend_removed_clean = rec_zeroed.remove_channels(remove_channel_ids=bad_channel_ids)
    #rec_visualize(rec4test, 0,5)
    #rec_visualize(raw_rec_clean, 0,5)
    
    plot_recording_snapshot(rec_trend_removed_clean, "Bad channel removed", 
                            os.path.join(save_folder, "3_bad_ch_removed.png"), 
                            stim_timepoint=stim_check_point, 
                            pre_stim=20,
                            post_stim=80)
    print("Clean ch raw rec snapshot saved.")
    
    #%
    rec_visualize(rec_trend_removed_clean , Rec_visT_start, Rec_visT_end)
    
    print("Does new rec object has probe?", rec_trend_removed_clean.has_probe())
    



    
    
    
    # #%%
    
    # rec_onset_fitted = sp.remove_artifacts(rec_trend_removed_clean, stim_ts_sorted, ms_before=0.05, ms_after=1.3, mode='zeros')
    # plot_recording_snapshot(rec_onset_fitted, "After Onset Artifact Fitting",
    #                     os.path.join(save_folder, "3_rec_onset_fitted.png") ,
    #                     stim_timepoint=stim_check_point, 
    #                     pre_stim = 20,
    #                     post_stim = 80,
    #                     Y_Lim=[-500, 500])
    # print("Clean ch raw rec snapshot saved.")
    # rec_visualize(rec_onset_fitted, Rec_visT_start, Rec_visT_end)
    
    # print("Does new rec object has probe?", rec_onset_fitted.has_probe())
    
    
    
    #%%
    rec_avg_removed = sp.common_reference(rec_trend_removed_clean , operator="average", reference="global")
    plot_recording_snapshot(rec_avg_removed, "Median removed", 
                            os.path.join(save_folder, "4_avg_removed.png"), 
                            stim_timepoint=stim_check_point, 
                            pre_stim=20,
                            post_stim=80)
    print("Median removed snapshot saved.")
    rec_visualize(rec_avg_removed , Rec_visT_start, Rec_visT_end)
    print("Does new rec object has probe?", rec_avg_removed.has_probe())
    
    
    #%
    rec_median_removed = sp.common_reference(rec_avg_removed , operator="median", reference="global")
    plot_recording_snapshot(rec_median_removed, "Median removed", 
                            os.path.join(save_folder, "5_median_removed.png"), 
                            stim_timepoint=stim_check_point, 
                            pre_stim=20,
                            post_stim=80)
    print("Median removed snapshot saved.")
    rec_visualize(rec_median_removed , Rec_visT_start, Rec_visT_end)
    print("Does new rec object has probe?", rec_median_removed.has_probe())
    
    

    
    #%
    rec_filt = sp.bandpass_filter(rec_median_removed, freq_min=300, freq_max=5000, dtype='float32')
    plot_recording_snapshot(rec_filt, "After Bandpass Filtering (rec_filt)",
                        os.path.join(save_folder, "6_rec_filt.png"),
                        stim_timepoint=stim_check_point,
                        pre_stim = 20,
                        post_stim = 80,
                        Y_Lim=[-500, 500])
    print("rec_filt saved.")
    rec_visualize(rec_filt , Rec_visT_start, Rec_visT_end)
    
    
    #%
    # rec_final_zeroed = sp.remove_artifacts(rec_filt, stim_ts_sorted, ms_before=0.5, ms_after=2, mode='zeros')
    # plot_recording_snapshot(rec_final_zeroed , "After Onset Artifact Zeroed",
    #                     os.path.join(save_folder, "4.5_rec_onset_zeroed.png") ,
    #                     stim_timepoint=stim_check_point, 
    #                     pre_stim = 20,
    #                     post_stim = 80,
    #                     Y_Lim=[-300, 300])
    # print("rec_onset_zeroed saved.")
    # rec_visualize(rec_final_zeroed , Rec_visT_start, Rec_visT_end)
    
    # print("Does new rec object has probe?", rec_final_zeroed.has_probe())
    
    
    # #%%
    # rec_cr = sp.common_reference(rec_filt, operator="average", reference="global")
    # plot_recording_snapshot(rec_cr, "After First Common Reference (rec_cr)",
    #                     os.path.join(save_folder, "5_rec_common_reference.png"),
    #                     stim_timepoint=stim_check_point,
    #                     pre_stim = 1.5,
    #                     post_stim = 100,
    #                     Y_Lim=[-500, 500])
    # print("rec_cr saved.")
    # rec_visualize(rec_cr , Rec_visT_start, Rec_visT_end)


#%
    rec_preprocessed = rec_filt #rec_final_zeroed #sp.whiten(rec_cr, dtype='float32')
    
    rec_folder = os.path.join(save_folder, "Recording")
    
    rec_preprocessed.save(format="binary", folder=rec_folder)

    
    
    # Save the recording used for waveform extraction
    # (here we use the common-referenced recording)
    rec_for_wvf_extraction = rec_preprocessed#rec_final_zeroed#rec7#rec_filt
    
    
    #%

    from spikeinterface.sorters import run_sorter_jobs
    
    # --- Your preprocessed `rec_preprocessed` is ready ---
    # Assume `rec_preprocessed` is a RecordingExtractor object
    
    
    
    # Mountainsort5 parameters
    ms5_params = {
        'scheme': '2',
        'detect_threshold': 5,
        'npca_per_channel': 5, #default and previous: 3
        'npca_per_subdivision': 15, #default and previous: 10,
        'snippet_mask_radius': 0,
        'scheme2_detect_channel_radius': 125,
        'scheme2_training_duration_sec': 300,
        'filter': False,
        'whiten': True
    }
    
    # Save in a sorter-compatible binary format
    start = time.time()
    rec_bi_preprocessed = rec_preprocessed.save()
    print(f"Converted to sorter-compatible binary in {time.time() - start:.1f} s")
    
    
    #%
    # Build a "job list"; even with only one recording, this keeps the
    # interface compatible with parallel job execution
    job_list = [{
        'sorter_name': 'mountainsort5',
        'recording': rec_bi_preprocessed,
        #'output_folder': Path(save_folder) / 'sorting',
        'remove_existing_folder': True,
        'verbose': True,
        **ms5_params
    }]
    
    # Run in parallel
    start = time.time()
    sortings = run_sorter_jobs(
        job_list=job_list,
        engine='joblib',
        engine_kwargs={
            'n_jobs': 40,         # use 40 cores
            'mp_context': 'spawn',
            'prefer': 'processes'
        },
        return_output=True
    )
    print(f"Total sorting time: {time.time() - start:.1f} s")
    
    # run_sorter_jobs returns a list; take the first element
    sorting = sortings[0]
    
    #sorting.save(folder=Path(save_folder) / 'sorting2')
    

        
    
    #%
    #% Create the sorting analyzer
    start_time_analyzer = time.time()
    analyzer_folder = os.path.join(save_folder, "Analyzer_raw")
    analyzer = si.create_sorting_analyzer(sorting=sorting, 
                                          recording=rec_for_wvf_extraction, 
                                          format="binary_folder",
                                          folder=analyzer_folder)
    end_time_analyzer = time.time()
    print("Create sorting analyzer takes time (s):", end_time_analyzer - start_time_analyzer)
    
    # Compute various metrics
    analyzer.compute("random_spikes", method="uniform", max_spikes_per_unit=500)
    start_time_compute = time.time()
    analyzer.compute("waveforms", ms_before=1.0, ms_after=2.0)
    end_time_compute = time.time()
    print("Computing waveforms takes time (s):", end_time_compute - start_time_compute)
    
    noise = analyzer.compute("noise_levels")
    noise_data = noise.get_data()
    print("Noise levels:", noise_data)
    
    analyzer.compute(["principal_components", "templates"])
    analyzer.compute("templates", operators=["average", "median", "std"])
    analyzer.compute(input="principal_components", n_components=3, mode="by_channel_local")
    analyzer.compute(input="template_metrics", include_multi_channel_metrics=True)
    analyzer.compute(input="template_similarity", method='cosine_similarity')
    analyzer.compute(input="spike_amplitudes", peak_sign="neg")
    analyzer.compute(input="unit_locations", method="monopolar_triangulation")
    analyzer.compute(input="correlograms", window_ms=50.0, bin_ms=1.0, method="auto")
    analyzer.compute(input="isi_histograms", window_ms=50.0, bin_ms=1.0, method="auto")
    
    start_time_qm = time.time()
    spikeinterface.qualitymetrics.compute_quality_metrics(analyzer)
    end_time_qm = time.time()
    print("Calculating PC_Metrics takes time (s):", end_time_qm - start_time_qm)
    
    available_extension_names = analyzer.get_loaded_extension_names()
    print("Loaded extension names:", available_extension_names)
    
    # Generate the SortingView URL and store it in the list outside the loop
    w_ss = spikeinterface.widgets.plot_sorting_summary(analyzer, 
                        min_similarity_for_correlograms=0.2, 
                        curation=True, 
                        backend='sortingview')
    v_ss = w_ss.view
    v_summary = vv.TabLayout(
                    items=[ vv.TabLayoutItem(
                            label='Sorting Summary',
                            view=v_ss
                        )
                    ]
                )
    current_url = v_summary.url(label="Example multiple tabs")
    url_list.append(current_url)
    

    
    print(f"Finished processing shank {shank}.\n{'-'*50}\n")
    
    print(current_url)
    

    #%
    # # Export sorting results to Phy format
    # start_time_phy = time.time()
    # phy_folder = os.path.join(save_folder, "Phy_raw")
    # #os.makedirs(phy_folder, exist_ok=True)
    # sexp.export_to_phy(analyzer, output_folder=phy_folder)

    # end_time_phy = time.time()
    # print("Exporting to PHY takes time (s):", end_time_phy - start_time_phy)




#%%
# After the loop finishes, print all generated URLs
print("Generated URLs for all shanks:")
for url in url_list:
    print(url)

