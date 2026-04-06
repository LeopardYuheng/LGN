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
# —— 顶层全局变量（不要改名） ——
_global_traces = None
_global_stim_ts = None
_global_fs = None
_global_n_samples = None
_global_ms_start = None
_global_order = None

def _init_worker(orig_traces, stim_timestamps, fs, n_samples, ms_start, order):
    """
    Pool initializer: 在每个子进程里设置全局变量
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
    只接受一个通道号，使用全局变量做多项式扣除
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
                            ms_end=10,      # 目前不再用 ms_end
                            order=3):
    """
    跳过 Bad_Ch_Idx 里的通道，对其他通道并行做多项式趋势扣除。
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

    # 用 Pool(initializer=..., initargs=...) 设置全局变量
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
    print()  # 换行

    # 构造新的 Recording
    new_rec = si.NumpyRecording(
        new_traces,
        sampling_frequency=fs,
        channel_ids=rec_obj.get_channel_ids()
    )
    new_rec.set_probe(Probe, in_place=True)

    elapsed = time.time() - start_time
    print(f"Trend correction done: {total} good channels "
          f"(skipped {len(Bad_Ch_Idx)}) in {elapsed:.2f}s")

    # 可选地显示 probe 信息
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
    串行：自动起止 + 跨 good channels 的逐样本中位数扣除 + 单通道拟合去趋势。
    流程（每个相邻刺激对的片段）：
      1) 用原始信号在所有 good channels 上计算该段的逐样本中位数 median_vec
      2) 对每个 good channel：centered = raw_segment - median_vec
      3) 用 centered 做 polyfit（阶数=order），trend removal: centered - trend
      4) 边界保持：段首/段尾恢复为 centered 的原值
      5) 写回 new_traces（保存的是“已扣中位数且去趋势”的结果）
    """
    import numpy as np
    import time
    import spikeinterface as si  # 需已安装

    if Bad_Ch_Idx is None:
        Bad_Ch_Idx = []

    # ---------------------------
    # 0) 基本信息
    # ---------------------------
    fs = rec_obj.get_sampling_frequency()
    traces = rec_obj.get_traces()  # (n_samples, n_channels)
    n_samples, n_channels = traces.shape

    orig_traces = traces.copy()    # 用于计算 median 和 centered 的“原始基准”
    new_traces  = np.array(orig_traces, copy=True)  # 写输出

    good_channels = [ch for ch in range(n_channels) if ch not in Bad_Ch_Idx]
    total_channels = len(good_channels)

    # ---------------------------
    # A) 清洗 stim_timestamps
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
        # 可选展示 probe
        probe_rec = new_rec.get_probe()
        df_probe = probe_rec.to_dataframe(complete=True)[
            ["contact_ids", "device_channel_indices"]
        ]
        print(df_probe)
        print("Probe loaded?", new_rec.has_probe())
        return new_rec

    # ---------------------------
    # B) 预计算：定位“第一个非零”的前一处全零
    # ---------------------------
    zero_all = np.all(orig_traces == 0, axis=1)  # (n_samples,)
    first_nonzero_idx_from = np.empty(n_samples, dtype=np.int64)
    next_idx = -1
    for i in range(n_samples - 1, -1, -1):
        if not zero_all[i]:
            next_idx = i
        first_nonzero_idx_from[i] = next_idx

    # ---------------------------
    # C) 相邻事件对与粗过滤
    # ---------------------------
    min_points = max(order + 1, 8)
    safety_margin = 3  # 与历史逻辑保持一致
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
    # D) 主循环（按片段，再按通道）
    # ---------------------------
    start_time_loop = time.time()
    print(f"[TrendRemoval] Start processing: {total_channels} channels, "
          f"{num_pairs_total} adjacent pairs ({num_pairs_valid} valid by interval).")

    for pair_idx, (ts_l, ts_r) in enumerate(zip(ts_left, ts_right), start=1):
        # 终点：next_ts - 3（右端不包含）
        end_sample = int(ts_r) #- safety_margin
        if end_sample <= 0:
            skipped_oob += 1
            continue
        end_sample = min(n_samples, end_sample)

        # 起点：从 ts_l 起向后找到第一个非零样本的前一位（最后一个全零点，且包含）
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

        # ---- 逐样本中位数（以原始信号为基准）----
        # shape: (seg_len,)
        segment_block_raw = orig_traces[start_sample:end_sample, good_channels]  # (m, Cg)
        median_vec = np.median(segment_block_raw, axis=1)  # (m,)

        x = np.arange(seg_len)

        # ---- 每个 good channel：centered 拟合并去趋势 ----
        for ch in good_channels:
            raw_segment = orig_traces[start_sample:end_sample, ch]     # 原始段（仅用于构造 centered 与边界参照）
            centered    = raw_segment - median_vec                     # 按你的要求：先扣中位数

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

            # 边界保持：端点恢复为“扣中位数后的原值”（即 centered 的端点）
            seg_new[0]  = centered[0]
            seg_new[-1] = centered[-1]

            # 写回输出（保存的是“已扣中位数且去趋势”的结果）
            new_traces[start_sample:end_sample, ch] = seg_new
            used_segments_total += 1

        # 进度打印
        if pair_idx % 1000 == 0 or pair_idx == num_pairs_valid:
            print(f"Trend subtraction (serial, centered->fit->remove) "
                  f"pair {pair_idx}/{num_pairs_valid}", end='\r')

    print()
    elapsed = time.time() - start_time_loop

    # ---------------------------
    # E) 统计总结
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
    # F) 构造新的 Recording 对象
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
    # Customized parameters：选择一段数据进行可视化验证
    start_time_param = start_time #145.16     # 起始时间（秒）
    end_time_param = end_time #145.26      # 结束时间（秒）
    channel_start = 6           # 起始通道索引（从0开始）
    channel_end = 12           # 结束通道索引（包含）
    
    rec_obj
    
    # 转换为样本索引
    fs = rec_obj.get_sampling_frequency()
    start_sample = int(start_time_param * fs)
    end_sample = int(end_time_param * fs)
    start_sample = max(0, start_sample)
    end_sample = min(rec_obj.get_num_samples(), end_sample)
    channel_end = min(channel_end, rec_obj.get_num_channels()-1)
    
    # 获取选定通道及数据
    segment_channel_ids = rec_obj.get_channel_ids()[channel_start : channel_end+1]
    traces = rec_obj.get_traces(
        channel_ids=segment_channel_ids,
        start_frame=start_sample,
        end_frame=end_sample
    )
    time_axis = np.linspace(start_time_param, end_time_param, traces.shape[0])
    
    # 绘图展示选定数据段
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
    
    # 创建新的 rec 对象
    rec4test = si.NumpyRecording(
        signals_subset[int(fs*piece_T_start):int(fs*piece_T_end)],
        sampling_frequency=fs,
        channel_ids=channel_ids
    )
        
    print("Recording object for test generated.")
    
    
    # 设置 probe 信息
    probe = rec_complete.get_probe()
    rec4test.set_probe(probe, in_place=True)
    probe_rec = rec4test.get_probe()
    # 显示 probe 信息（可选）
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
    从指定文件夹中的 .mat 文件读取一个 C×2 的 cell 数组，
    忽略第一列标签，提取第二列的所有数值并按升序排序返回。

    Parameters
    ----------
    folder : str
        存放 .mat 文件的文件夹路径
    filename : str
        要读取的 .mat 文件名（含扩展名）
    cell_var : str, optional
        .mat 文件中 cell 数组变量的名称。如果为 None，则自动
        使用文件里第一个非 '___' 开头的变量名。

    Returns
    -------
    ts : np.ndarray
        排序后的所有值组成的一维 NumPy 数组
    """
    # 构造并检查路径
    filepath = os.path.join(folder, filename)
    if not os.path.isfile(filepath):
        raise FileNotFoundError(f".mat 文件未找到: {filepath}")

    # 加载 .mat，去掉单维度包装
    mat = sio.loadmat(filepath, squeeze_me=True, struct_as_record=False)
    # 自动选取变量名
    if cell_var is None:
        vars_in_mat = [k for k in mat.keys() if not k.startswith('__')]
        if not vars_in_mat:
            raise KeyError("在 .mat 文件中未找到任何变量。")
        cell_var = vars_in_mat[0]

    # 提取 cell 数组
    cell_array = mat[cell_var]
    cell_array = np.asarray(cell_array)
    if cell_array.ndim != 2 or cell_array.shape[1] < 2:
        raise ValueError(f"变量 '{cell_var}' 不是形如 C×2 的 cell 数组。")

    # 抽取第二列，每个元素应是 N×1 的 double 数组
    second_col = cell_array[:, 1]
    # 合并并排序
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
    safety_margin: int | None = None,   # 新：默认 None => 用 [ts_l, ts_r] 闭区间
    sampling_rate: float | None = None, # 显式采样率（Hz）；None 则从 rec_obj 获取
):
    """
    串行：用高通滤波替代 polynomial 去趋势；支持“闭区间”片段模式与端点强制为 0。

    片段定义（ts_l = 当前刺激，ts_r = 下一个刺激）：
      - 若 safety_margin is None:
            segment = [ts_l, ts_r] （闭区间；切片需用 end_excl = ts_r + 1）
            起点=ts_l（不再做“第一个非零的前一位”探测）
      - 若 safety_margin 是整数:
            end_excl = max(0, ts_r - safety_margin)（右端不含）
            起点按旧逻辑：从 ts_l 向后找到“第一个非零”的**前一位**（最后一个全零），若直到 end_excl 前都为零则用 ts_l

    信号处理：
      - 可选 subtract_median=True：段内对所有 good channels 逐样本取中位并先扣除
      - 对每个通道片段做 Butterworth 高通（零相位 filtfilt）
      - 端点处理（关键新要求）：
            不论是否扣中位，滤波完成后把该片段的首样本与尾样本 **强制置为 0**
            （因为物理上每个刺激点处所有通道都是 0）

    参数
    ----
    subtract_median : 是否先做跨 good channels 的逐样本中位数扣除（工作域变为“扣中位后的信号”）
    cutoff_hz       : 高通截止频率（物理 Hz）
    filter_order    : Butterworth 阶数（建议 2–4）
    safety_margin   : None=闭区间；整数=相对下个刺激点保留 margin 的旧模式
    sampling_rate   : 采样率 Hz；None 则用 rec_obj.get_sampling_frequency()

    返回
    ----
    spikeinterface.NumpyRecording
    """
    import numpy as np
    import time
    import spikeinterface as si
    from scipy.signal import butter, filtfilt

    if Bad_Ch_Idx is None:
        Bad_Ch_Idx = []

    # 0) 采样率 / 基本数据
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

    # 1) 清洗时间戳
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

    # 2) 若使用“旧模式”（safety_margin 为整数），需要“第一个非零”的辅助表
    if safety_margin is not None:
        zero_all = np.all(orig_traces == 0, axis=1)  # (n_samples,)
        first_nonzero_idx_from = np.empty(n_samples, dtype=np.int64)
        next_idx = -1
        for i in range(n_samples - 1, -1, -1):
            if not zero_all[i]:
                next_idx = i
            first_nonzero_idx_from[i] = next_idx
    else:
        first_nonzero_idx_from = None  # 不使用

    # 3) 设计高通滤波器
    nyq = fs / 2.0
    wn = float(cutoff_hz) / nyq
    if not (0 < wn < 1):
        raise ValueError(f"cutoff_hz 必须在 (0, {nyq}) 内，当前 {cutoff_hz}")
    b, a = butter(filter_order, wn, btype="highpass")
    padlen_const = 3 * (max(len(a), len(b)) - 1)  # filtfilt 的理论最小长度

    # 4) 统计
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

    # 5) 主循环
    for pair_idx in range(num_pairs_total):
        ts_l = int(ts[pair_idx])
        ts_r = int(ts[pair_idx + 1])

        if safety_margin is None:
            # 闭区间：[ts_l, ts_r] => 切片右端需要 +1
            start_sample = ts_l
            end_excl     = ts_r + 1
        else:
            # 旧模式：右端留 margin；起点为“第一个非零的前一位”，若一直为零则用 ts_l
            end_excl = int(ts_r) - int(safety_margin)
            if end_excl <= 0:
                skipped_oob += 1
                continue
            end_excl = min(n_samples, end_excl)

            j = first_nonzero_idx_from[ts_l]
            if j == -1 or j >= end_excl:
                start_sample = ts_l
            else:
                start_sample = max(0, j - 1)  # 最后一个全零（包含）

        # 基本边界
        if start_sample < 0:
            start_sample = 0
        if end_excl > n_samples:
            end_excl = n_samples

        seg_len = end_excl - start_sample
        if seg_len <= 0:
            skipped_reversed += 1
            continue

        # 粗过滤（仅在 None 模式下也给个最小长度门槛；严格门槛用 padlen）
        if seg_len <= 8:
            skipped_short_coarse += 1
            continue

        # 严格长度检查：必须能 filtfilt
        if seg_len <= padlen_const:
            skipped_too_short += 1
            continue

        # 构造段矩阵（原始）
        seg_block_raw = orig_traces[start_sample:end_excl, good_channels]  # (m, Cg)

        # 逐样本中位数（可选）
        if subtract_median:
            median_vec = np.median(seg_block_raw, axis=1)  # (m,)
        else:
            median_vec = 0.0

        # 滤波与端点处理
        for ch in good_channels:
            raw_seg = orig_traces[start_sample:end_excl, ch]
            y = raw_seg - median_vec  # 若未扣中位，相当于 y=raw_seg

            try:
                y_hp = filtfilt(b, a, y, padlen=padlen_const)
            except Exception:
                skipped_too_short += 1
                continue

            # 线性“形状修正”可省略（端点将被强制置 0）
            # 把片段两端样本强制置为 0（满足物理假设：每个刺激点处为 0）
            y_hp[0]  = 0.0
            y_hp[-1] = 0.0

            new_traces[start_sample:end_excl, ch] = y_hp
            used_segments_total += 1

        # 进度
        if (pair_idx + 1) % 10 == 0 or (pair_idx + 1) == num_pairs_total:
            print(f"[HPFTrend] pair {pair_idx + 1}/{num_pairs_total}", end='\r')

    print()
    elapsed = time.time() - start_time

    # 6) 总结
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

    # 7) 返回 Recording
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
        matplotlib.use('Qt5Agg')  # 或根据你系统支持设置 'TkAgg'
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
    从已排序的一维 int32 数组中删除相邻间距不足 min_gap 的较小元素。
    规则：若 x[i] 与前一个保留元素的差 < min_gap，则删除较小者（即前一个），保留较大者（当前）。
    
    参数
    ----
    arr : np.ndarray
        形状为 (N,) 的已升序排序数组；建议 dtype 为 int32。
    min_gap : int
        最小允许间距（严格：仅当差值 < min_gap 时触发删除；== min_gap 视为合格）。

    返回
    ----
    np.ndarray
        处理后的数组，dtype 与输入一致。
    """
    if arr.ndim != 1:
        raise ValueError("arr 必须是一维数组")
    if len(arr) <= 1:
        return arr.astype(np.int32, copy=True)

    # 用 list 做栈保存结果，必要时删除倒数第二个元素（较小者）
    out = []
    for x in arr:
        if not out:
            out.append(int(x))
            continue

        if x - out[-1] >= min_gap:
            # 与最后一个保留值间距足够，直接保留
            out.append(int(x))
        else:
            # 间距不足：按规则删除较小者（当前 pair 中的较小是 out[-1]）
            # 用 x 替换 out[-1]
            out[-1] = int(x)
            # 可能与更早的值也间距不足，需要继续向前清理
            while len(out) >= 2 and (out[-1] - out[-2] < min_gap):
                # 删除较小者 out[-2]，保留较大者 out[-1]
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
    n_jobs: int = 1,               # 按 channel 并行
    Sign_Detection: bool = False,  # 是否启用“变号点”伪零点逻辑
):
    """
    对 T*N 的 trace 做“零点 / 变号桥接”操作：
      - Bad_Channel_Indexes 中的 channel 不做任何修改。
      - 对其它 channel:
        1) 检查 Stim_Onset_Ts 位置是否为 0，不是则报错。
        2) 找出所有连续 0 段，并标记其中“包含 stim”的 0 段。
        3) 对包含 stim 的 0 段，去掉其内部 0，只保留端点 0（zero_idx_valid）。
        4) 对每个 stim 的 pre/post 窗口：
           - 基于 zero_idx_valid 找窗口内 0 点；
           - 若 Sign_Detection=True，则额外在窗口内找“变号点”（信号从正到负或负到正，
             且不在连续零段内），也当作“伪零点”。
        5) 将所有零点/伪零点排序，相邻两个点间距 < Width_Filter_Threshold，则在该区间内置 0。

    返回：
      new_trace_data: 形状与 orig_trace_data 相同的新数组
    """

    # ========== 基本检查 ==========
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

    # 处理 Complete_data 情况下的越界 stim
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

    # Bad channel 检查
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

    # ========== 单个 channel 的处理逻辑（可并行） ==========
    def _process_one_channel(ch: int):
        """
        返回: (ch_idx, new_trace_ch, channel_mods)
          - new_trace_ch: shape (T,)
          - channel_mods: [(seg_start, seg_end), ...] 该 channel 内的置 0 片段
        """
        if ch in Bad_Channel_Indexes:
            if debug:
                print(f"[跳过] channel {ch} 在 Bad_Channel_Indexes 中，不做修改。")
            return ch, orig_trace_data[:, ch].copy(), []

        trace = orig_trace_data[:, ch]

        # Step 3: 检查 Stim 点是否为 0
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

        # 所有为 0 的索引
        zero_idx = np.flatnonzero(trace == 0)
        if zero_idx.size == 0:
            if debug:
                print(f"[Channel {ch}] 该通道没有任何 0 点，跳过宽度过滤。")
            return ch, trace.copy(), []

        # === 使用 zero_idx 找所有连续 0 段 ===
        diff = np.diff(zero_idx)
        seg_zero_start_idx = np.concatenate(([0], np.nonzero(diff > 1)[0] + 1))
        seg_zero_end_idx   = np.concatenate((np.nonzero(diff > 1)[0], [zero_idx.size - 1]))

        seg_start_val = zero_idx[seg_zero_start_idx]  # 每段连续 0 的第一个 0 索引
        seg_end_val   = zero_idx[seg_zero_end_idx]    # 每段连续 0 的最后一个 0 索引
        num_segs = seg_start_val.size

        # 标记哪些 0 段包含至少一个 stim
        seg_has_stim = np.zeros(num_segs, dtype=bool)
        for stim_idx in Stim_valid:
            if stim_idx < 0 or stim_idx >= T:
                continue
            k = np.searchsorted(seg_start_val, stim_idx, side='right') - 1
            if k >= 0 and stim_idx <= seg_end_val[k]:
                seg_has_stim[k] = True

        # 去掉“包含 stim 的 0 段”的内部 0（保留端点）
        interior_mask = np.zeros(zero_idx.size, dtype=bool)
        interest_seg_ids = np.nonzero(seg_has_stim)[0]
        for j in interest_seg_ids:
            s_idx = seg_zero_start_idx[j]
            e_idx = seg_zero_end_idx[j]
            if e_idx - s_idx >= 2:
                # s_idx+1 : e_idx-1 是内部；注意 e_idx 是最后一个 zero 的索引
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

        # 若启用 Sign_Detection，则预先计算：
        #   1) in_zero_segment: 哪些 sample 在任何连续零段内（包括端点）
        #   2) sign_change_idx_all: 所有“符号从正变负或负变正”的位置（且两侧都非 0）
        if Sign_Detection:
            in_zero_segment = np.zeros(T, dtype=bool)
            for s_val, e_val in zip(seg_start_val, seg_end_val):
                in_zero_segment[s_val:e_val + 1] = True

            # 用 int8 存符号：-1, 0, 1，避免 int64 的巨大内存
            nonzero_mask_trace = trace != 0

            sign_trace = np.zeros(T, dtype=np.int8)
            sign_trace[trace > 0] = 1
            sign_trace[trace < 0] = -1

            # 相邻符号乘积 < 0 且两端都非 0 → 真正变号点（非 0 ↔ 非 0）
            sign_prod = sign_trace[1:] * sign_trace[:-1]  # int8 即可
            sc_mask = (sign_prod < 0) & nonzero_mask_trace[1:] & nonzero_mask_trace[:-1]
            sign_change_idx_all = np.flatnonzero(sc_mask) + 1

            if debug:
                print(f"[Channel {ch}] Sign_Detection: 全局变号点数量={sign_change_idx_all.size}")
        else:
            in_zero_segment = None
            sign_change_idx_all = None

        # Step 5: 对每个 stim 的窗口，收集候选“零点”（真实 0 或伪零点）
        zero_positions_set = set()

        for stim_idx in Stim_valid:
            win_start = max(0, stim_idx - pre_samples)
            win_end   = min(T - 1, stim_idx + post_samples)
            if win_end < win_start:
                continue

            # (1) 窗口内的真实 0 点（zero_idx_valid）
            if zero_idx_valid.size > 0:
                l = np.searchsorted(zero_idx_valid, win_start, side='left')
                r = np.searchsorted(zero_idx_valid, win_end,   side='right')
                if r > l:
                    for pos in zero_idx_valid[l:r]:
                        zero_positions_set.add(int(pos))

            # (2) 若开启 Sign_Detection，再加入窗口内的“变号点”（视为伪零点）
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

        # Step 6: 相邻候选点间距 < 阈值 → 中间全置 0
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

    # ========== 串行 / 并行执行 ==========
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

    # ========== 画 debug 对比图 ==========
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


# 定义各shank对应的Ripple通道号列表（按照深度y轴从0到高）

 
Ripple_id_Shank0 = [104,102,106,97,99,101,103,105,107,109,111,113,115,117,119,
                    121,123,69,73,100,90,95,93,91,89,87,85,83,81,79,77,75]

Ripple_id_Shank1 = [67,	125,71,68,124,98,92,88,82,112,80,114,78,72,122,70,127,
                    65,126,66,128,118,74,96,94,84,110,108,86,76,116,120]

Ripple_id_Shank2 = [63,1,4,64,2,12,56,10,14,34,36,20,46,22,44,54,3,61,57,62,6,
                    60,8,58,52,16,50,32,38,42,48,18]

Ripple_id_Shank3 = [59,5,55,53,51,49,47,45,43,41,39,37,35,30,40,33,7,9,11,13,
                    15,17,19,21,23,25,27,29,31,24,26,28]

# 将所有TDT列表汇总到一个列表中，便于后续索引
#TDT_ids_all = [TDT_id_Shank0, TDT_id_Shank1, TDT_id_Shank2, TDT_id_Shank3]
Ripple_ids_all = [Ripple_id_Shank0, Ripple_id_Shank1, Ripple_id_Shank2, Ripple_id_Shank3]





#% Create a save folder for pipeline outputs
# 创建保存文件夹并定义 ms5 参数
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
    # 构造对应的 probe 文件路径，例如：'util/EBL4Shank/NET-EBL-4by32-TDT4Py-shank0.json'
    probe_filename = f'Z:/xl_stimulation/Yuxuan_NEW/Summation-since20230612/2025-Exp&Data/DataAnaCode/Ephys/EBL4Shank_Ripple&TDT_Yuxuan/2025_New_Pipeline/ChMap/Linear/NET-PL-4by32linear-Depth4Py-1shank.json'
    
    # 读取 probe 文件
    pi = read_probeinterface(probe_filename)
    probe = pi.probes[0]
    
    
    current_Ripple_ids = Ripple_ids_all[shank]
    shank_channel_indices = [idx for idx in current_Ripple_ids]
    shank_channel_ids = [str(ch) for ch in shank_channel_indices]   
                         
    start_time = 0      # 起始时间（秒）
    end_time =  1200 #TotalDur       # 结束时间（秒）

    # 转换为样本索引

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
    
    #% 创建新的 rec 对象
    rec = si.NumpyRecording(
        signals_subset,
        sampling_frequency=sampling_freq,
        channel_ids=channel_ids_subset
    )
    
    #%
    # 设置 probe 信息
    rec.set_probe(probe, in_place=True)
    probe_rec = rec.get_probe()
    # 显示 probe 信息（可选）
    df_probe = probe_rec.to_dataframe(complete=True).loc[:, ["contact_ids", "device_channel_indices"]]
    print(df_probe)
    
    fs = rec.get_sampling_frequency()
    
    # 验证输出
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
    #     safety_margin = 0   # 终点：end_sample = next_ts - safety_margin（右端不含）
    #     #sampling_rate: float | None = None,  # 显式指定采样率（Hz）；None 则从 rec_obj 获取
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
        orig_trace_data=orig_traces,         # 形状 (T, N)
        Stim_Onset_Ts=stim_ts_sorted,            # 形状 (S,)
        Bad_Channel_Indexes=Bad_ch_idx,#[0, 5, 7],          # 例如坏道
        sampling_rate=30000,
        pre_stim_range=1.0,                     # ms
        post_stim_range=1.5,                    # ms
        Width_Filter_Threshold=30,              # samples
        save_folder=save_folder,     # 会创建 zero_filter_debug_plots 子文件夹
        debug=False,
        Complete_data=False,
        n_jobs=4,               # 按 channel 并行
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

    
    
    # 保存用于 waveform 提取的 rec（这里使用 common reference 后的 rec）
    rec_for_wvf_extraction = rec_preprocessed#rec_final_zeroed#rec7#rec_filt
    
    
    #%

    from spikeinterface.sorters import run_sorter_jobs
    
    # --- 你的预处理 rec_preprocessed 已经准备好 ---
    # 假设 rec_preprocessed 是一个 RecordingExtractor 对象
    
    
    
    # Mountainsort5 的参数
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
    
    # 保存为 sorter 兼容的二进制格式
    start = time.time()
    rec_bi_preprocessed = rec_preprocessed.save()
    print(f"Converted to sorter-compatible binary in {time.time() - start:.1f} s")
    
    
    #%
    # 构建一个“作业列表”，即使只有一条 recording，也能并行拆任务
    job_list = [{
        'sorter_name': 'mountainsort5',
        'recording': rec_bi_preprocessed,
        #'output_folder': Path(save_folder) / 'sorting',
        'remove_existing_folder': True,
        'verbose': True,
        **ms5_params
    }]
    
    # 并行运行
    start = time.time()
    sortings = run_sorter_jobs(
        job_list=job_list,
        engine='joblib',
        engine_kwargs={
            'n_jobs': 40,         # 使用 40 核
            'mp_context': 'spawn',
            'prefer': 'processes'
        },
        return_output=True
    )
    print(f"Total sorting time: {time.time() - start:.1f} s")
    
    # run_sorter_jobs 返回一个列表，我们取第一个元素
    sorting = sortings[0]
    
    #sorting.save(folder=Path(save_folder) / 'sorting2')
    

        
    
    #%
    #% 创建 sorting analyzer
    start_time_analyzer = time.time()
    analyzer_folder = os.path.join(save_folder, "Analyzer_raw")
    analyzer = si.create_sorting_analyzer(sorting=sorting, 
                                          recording=rec_for_wvf_extraction, 
                                          format="binary_folder",
                                          folder=analyzer_folder)
    end_time_analyzer = time.time()
    print("Create sorting analyzer takes time (s):", end_time_analyzer - start_time_analyzer)
    
    # 计算各种指标
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
    
    # 生成 SortingView 的 URL，并存入循环外的列表中
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
# 循环结束后，依次打印所有生成的 URL
print("Generated URLs for all shanks:")
for url in url_list:
    print(url)

