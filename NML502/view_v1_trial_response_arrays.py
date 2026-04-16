"""
View trial-wise V1 response maps exported by export_v1_trial_response_arrays_h5.m.

Example:
    python analysis/longitudinal/view_v1_trial_response_arrays.py ^
        --file-1x "C:\\path\\session_v1_trial_response_arrays_1x.h5" ^
        --file-2x "C:\\path\\session_v1_trial_response_arrays_2x.h5" ^
        --file-4x "C:\\path\\session_v1_trial_response_arrays_4x.h5" ^
        --trial-row 0

Or filter by condition:
    python analysis/longitudinal/view_v1_trial_response_arrays.py ^
        --file-1x "C:\\path\\session_v1_trial_response_arrays_1x.h5" ^
        --file-2x "C:\\path\\session_v1_trial_response_arrays_2x.h5" ^
        --file-4x "C:\\path\\session_v1_trial_response_arrays_4x.h5" ^
        --channel 144 --current 7 --condition-trial-index 0
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np


@dataclass
class ScaleData:
    path: Path
    scale_factor: int
    response_maps: np.ndarray
    v1_mask: np.ndarray
    analysis_mask: np.ndarray
    channel: np.ndarray
    current_uA: np.ndarray
    trial_index: np.ndarray
    frame_idx: np.ndarray


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="View exported V1 trial response maps.")
    parser.add_argument("--file-1x", required=True, help="Path to *_1x.h5")
    parser.add_argument("--file-2x", required=True, help="Path to *_2x.h5")
    parser.add_argument("--file-4x", required=True, help="Path to *_4x.h5")
    parser.add_argument("--trial-row", type=int, default=None, help="Zero-based trial row shared across exports")
    parser.add_argument("--channel", type=int, default=None, help="Stim channel to filter")
    parser.add_argument("--current", type=float, default=None, help="Current in uA to filter")
    parser.add_argument(
        "--condition-trial-index",
        type=int,
        default=0,
        help="Zero-based trial index after filtering by channel/current",
    )
    parser.add_argument(
        "--hide-masks",
        action="store_true",
        help="Do not overlay the analysis mask boundary.",
    )
    return parser.parse_args()


def load_scale_file(path: str | Path) -> ScaleData:
    path = Path(path)
    with h5py.File(path, "r") as f:
        scale_factor = int(np.asarray(f["/meta/scale_factor"]).squeeze())
        response_maps = np.asarray(f["/response_maps"])
        v1_mask = np.asarray(f["/v1_mask"]).astype(bool)
        analysis_mask = np.asarray(f["/analysis_mask"]).astype(bool)
        channel = np.asarray(f["/meta/channel"]).astype(int).reshape(-1)
        current_uA = np.asarray(f["/meta/current_uA"]).astype(float).reshape(-1)
        trial_index = np.asarray(f["/meta/trial_index"]).astype(float).reshape(-1)
        frame_idx = np.asarray(f["/meta/frame_idx"]).astype(int).reshape(-1)

    return ScaleData(
        path=path,
        scale_factor=scale_factor,
        response_maps=response_maps,
        v1_mask=v1_mask,
        analysis_mask=analysis_mask,
        channel=channel,
        current_uA=current_uA,
        trial_index=trial_index,
        frame_idx=frame_idx,
    )


def validate_alignment(scales: list[ScaleData]) -> None:
    ref = scales[0]
    for scale in scales[1:]:
        if scale.response_maps.shape[0] != ref.response_maps.shape[0]:
            raise ValueError("The HDF5 files do not have the same number of trials.")
        if not np.array_equal(scale.channel, ref.channel):
            raise ValueError("Channel metadata does not match across scale files.")
        if not np.allclose(scale.current_uA, ref.current_uA):
            raise ValueError("Current metadata does not match across scale files.")
        if not np.allclose(scale.trial_index, ref.trial_index, equal_nan=True):
            raise ValueError("Trial index metadata does not match across scale files.")
        if not np.array_equal(scale.frame_idx, ref.frame_idx):
            raise ValueError("Frame index metadata does not match across scale files.")


def choose_trial_row(args: argparse.Namespace, ref: ScaleData) -> int:
    if args.trial_row is not None:
        trial_row = args.trial_row
    else:
        if args.channel is None or args.current is None:
            raise ValueError("Provide either --trial-row or both --channel and --current.")

        keep = (ref.channel == args.channel) & np.isclose(ref.current_uA, args.current)
        matches = np.flatnonzero(keep)
        if matches.size == 0:
            raise ValueError(
                f"No trials found for channel={args.channel}, current={args.current}."
            )
        if args.condition_trial_index < 0 or args.condition_trial_index >= matches.size:
            raise IndexError(
                f"--condition-trial-index must be between 0 and {matches.size - 1}."
            )
        trial_row = int(matches[args.condition_trial_index])

    if trial_row < 0 or trial_row >= ref.response_maps.shape[0]:
        raise IndexError(
            f"--trial-row must be between 0 and {ref.response_maps.shape[0] - 1}."
        )
    return trial_row


def compute_display_limits(scales: list[ScaleData], trial_row: int) -> tuple[float, float]:
    vals = []
    for scale in scales:
        img = np.asarray(scale.response_maps[trial_row], dtype=float)
        finite = img[np.isfinite(img)]
        if finite.size:
            vals.append(finite)

    if not vals:
        return (-1.0, 1.0)

    merged = np.concatenate(vals)
    lo, hi = np.quantile(merged, [0.02, 0.98])
    m = max(abs(lo), abs(hi))
    if not np.isfinite(m) or m == 0:
        m = 1.0
    return (-m, m)


def print_matching_conditions(ref: ScaleData, max_rows: int = 20) -> None:
    pairs = {}
    for ch, cur in zip(ref.channel, ref.current_uA):
        key = (int(ch), float(cur))
        pairs[key] = pairs.get(key, 0) + 1

    print("Available conditions:")
    for i, ((ch, cur), count) in enumerate(sorted(pairs.items())):
        if i >= max_rows:
            print(f"... and {len(pairs) - max_rows} more")
            break
        print(f"  channel={ch:>3d} | current_uA={cur:>6g} | n_trials={count}")


def main() -> None:
    args = parse_args()

    scales = [
        load_scale_file(args.file_1x),
        load_scale_file(args.file_2x),
        load_scale_file(args.file_4x),
    ]
    validate_alignment(scales)

    ref = scales[0]
    print_matching_conditions(ref)

    trial_row = choose_trial_row(args, ref)
    clim = compute_display_limits(scales, trial_row)

    print("")
    print(f"Selected trial_row: {trial_row}")
    print(f"Channel: {ref.channel[trial_row]}")
    print(f"Current (uA): {ref.current_uA[trial_row]}")
    print(f"Frame index: {ref.frame_idx[trial_row]}")
    print(f"Trial index: {ref.trial_index[trial_row]}")

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    last_im = None

    for ax, scale in zip(axes, scales):
        img = np.asarray(scale.response_maps[trial_row], dtype=float)
        last_im = ax.imshow(img, cmap="bwr", vmin=clim[0], vmax=clim[1], interpolation="nearest")
        if not args.hide_masks:
            ax.contour(scale.analysis_mask.astype(float), levels=[0.5], colors="k", linewidths=0.8)
        ax.set_title(f"{scale.scale_factor}x")
        ax.axis("off")

    fig.colorbar(last_im, ax=axes.ravel().tolist(), shrink=0.85, label="dF/F")
    fig.suptitle(
        f"trial_row={trial_row} | channel={ref.channel[trial_row]} | current={ref.current_uA[trial_row]:g} uA",
        fontsize=13,
    )
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
