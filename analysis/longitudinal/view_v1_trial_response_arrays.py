"""
View trial-wise V1 response maps exported by export_v1_trial_response_arrays_h5.m.

Edit the user options below, then run this file directly from your IDE.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np


FILE_PATH = Path(r"C:\Albert Li\LGN\LGN_wf_longitudinal\LGN11_longitudinal\2026-03-29\analysis\python_export_v1_trial_response_arrays\LGN11_20260328_day_pointer_v1_trial_response_arrays.h5")
CHANNEL_TO_PLOT = None
MAKE_PER_CHANNEL_MAP_FIGURES = True
MAKE_RESPONSE_CURVE_FIGURES = True
MAP_COLS = 5
SUMMARY_METRIC = "mean_v1"
OVERLAY_V1_BOUNDARY = True
OVERLAY_FINAL_MASK_BOUNDARY = True
MAP_CMAP = "viridis"


@dataclass
class TrialData:
    path: Path
    channel: np.ndarray
    current_uA: np.ndarray
    v1_response_values: np.ndarray
    v1_response_grid: np.ndarray
    v1_mask: np.ndarray | None
    final_mask: np.ndarray | None


def align_mask_to_grid(mask: np.ndarray | None, grid_shape: tuple[int, int]) -> np.ndarray | None:
    if mask is None:
        return None

    mask = np.asarray(mask).astype(bool)
    if mask.shape == grid_shape:
        return mask

    if mask.T.shape == grid_shape:
        return mask.T

    raise ValueError(f"Could not align mask shape {mask.shape} to grid shape {grid_shape}.")


def load_trial_file(path: str | Path) -> TrialData:
    path = Path(path)
    with h5py.File(path, "r") as f:
        channel = np.asarray(f["/channel"]).astype(int).reshape(-1)
        current_uA = np.asarray(f["/current_uA"]).astype(float).reshape(-1)
        v1_response_values = np.asarray(f["/v1_response_values"], dtype=float)
        v1_response_grid = np.asarray(f["/v1_response_grid"], dtype=float)
        v1_mask = np.asarray(f["/v1_mask"]).astype(bool) if "/v1_mask" in f else None
        final_mask = np.asarray(f["/final_mask"]).astype(bool) if "/final_mask" in f else None

    if v1_response_grid.ndim != 3:
        raise ValueError(f"Expected /v1_response_grid to be 3D, got shape {v1_response_grid.shape}.")

    if v1_response_grid.shape[0] != channel.size:
        if v1_response_grid.shape[-1] == channel.size:
            v1_response_grid = np.transpose(v1_response_grid, (2, 1, 0))
        else:
            raise ValueError(
                "Could not align /v1_response_grid with /channel. "
                f"grid shape={v1_response_grid.shape}, n_trials={channel.size}"
            )

    if v1_response_values.ndim != 2:
        raise ValueError(f"Expected /v1_response_values to be 2D, got shape {v1_response_values.shape}.")

    if v1_response_values.shape[0] != channel.size:
        if v1_response_values.shape[1] == channel.size:
            v1_response_values = v1_response_values.T
        else:
            raise ValueError(
                "Could not align /v1_response_values with /channel. "
                f"value shape={v1_response_values.shape}, n_trials={channel.size}"
            )

    grid_shape = tuple(v1_response_grid.shape[1:3])
    v1_mask = align_mask_to_grid(v1_mask, grid_shape)
    final_mask = align_mask_to_grid(final_mask, grid_shape)

    return TrialData(
        path=path,
        channel=channel,
        current_uA=current_uA,
        v1_response_values=v1_response_values,
        v1_response_grid=v1_response_grid,
        v1_mask=v1_mask,
        final_mask=final_mask,
    )


def compute_display_limits(maps: np.ndarray) -> tuple[float, float]:
    finite = maps[np.isfinite(maps)]
    if finite.size == 0:
        return (-1.0, 1.0)

    lo, hi = np.quantile(finite, [0.02, 0.98])
    m = max(abs(lo), abs(hi))
    if not np.isfinite(m) or m == 0:
        m = 1.0
    return (-m, m)


def summarize_trials(data: TrialData, metric: str) -> np.ndarray:
    if metric != "mean_v1":
        raise ValueError(f"Unsupported SUMMARY_METRIC: {metric}")
    return np.nanmean(data.v1_response_values, axis=1)


def select_channel_indices(data: TrialData, channel_to_plot: int | None) -> dict[int, np.ndarray]:
    if channel_to_plot is None:
        channels = np.unique(data.channel)
    else:
        channels = np.array([channel_to_plot], dtype=int)

    out: dict[int, np.ndarray] = {}
    for ch in channels:
        idx = np.flatnonzero(data.channel == ch)
        if idx.size:
            out[int(ch)] = idx
    return out


def split_trials_by_current(data: TrialData, trial_rows: np.ndarray) -> dict[float, np.ndarray]:
    currents = data.current_uA[trial_rows]
    out: dict[float, np.ndarray] = {}
    for cur in np.sort(np.unique(currents[np.isfinite(currents)])):
        keep = np.isclose(currents, cur)
        rows = trial_rows[keep]
        if rows.size:
            out[float(cur)] = rows
    return out


def overlay_boundaries(ax: plt.Axes, data: TrialData) -> None:
    if OVERLAY_V1_BOUNDARY and data.v1_mask is not None:
        ax.contour(data.v1_mask.astype(float), levels=[0.5], colors="w", linewidths=1.0)
    if OVERLAY_FINAL_MASK_BOUNDARY and data.final_mask is not None:
        ax.contour(data.final_mask.astype(float), levels=[0.5], colors="y", linewidths=0.9)


def plot_map_panel(ax: plt.Axes, img: np.ndarray, data: TrialData, clim: tuple[float, float]) -> plt.AxesImage:
    im = ax.imshow(img, cmap=MAP_CMAP, vmin=clim[0], vmax=clim[1], interpolation="nearest", origin="upper")
    overlay_boundaries(ax, data)
    ax.axis("off")
    return im


def plot_condition_maps(
    data: TrialData,
    trial_scalar: np.ndarray,
    trial_rows: np.ndarray,
    channel: int,
    current_uA: float,
    cols: int,
) -> None:
    n_trials = trial_rows.size
    n_panels = n_trials + 1
    cols = max(1, cols)
    cols = min(cols, n_panels)
    rows = int(np.ceil(n_panels / cols))

    mean_map = np.nanmean(data.v1_response_grid[trial_rows], axis=0)
    maps_for_clim = np.concatenate([data.v1_response_grid[trial_rows], mean_map[None, :, :]], axis=0)
    clim = compute_display_limits(maps_for_clim)

    fig, axes = plt.subplots(rows, cols, figsize=(3.9 * cols, 3.4 * rows), facecolor="w")
    axes = np.atleast_1d(axes).ravel()
    last_im = None

    for panel_i, trial_row in enumerate(trial_rows):
        ax = axes[panel_i]
        img = data.v1_response_grid[trial_row]
        last_im = plot_map_panel(ax, img, data, clim)
        ax.set_title(
            f"trial={trial_row} | {data.current_uA[trial_row]:g} uA\nmean={trial_scalar[trial_row]:.4f}",
            fontsize=9,
        )

    ax_mean = axes[n_trials]
    last_im = plot_map_panel(ax_mean, mean_map, data, clim)
    ax_mean.set_title(f"Mean map\nCh {channel} | {current_uA:g} uA | n={n_trials}", fontsize=10)

    for ax in axes[n_panels:]:
        ax.axis("off")

    fig.colorbar(last_im, ax=axes.tolist(), shrink=0.85, label="dF/F")
    fig.suptitle(f"Evoked maps | Channel {channel} | {current_uA:g} uA", fontsize=14, fontweight="bold")
    plt.tight_layout()
    plt.show()


def make_jitter(x_center: float, n: int, width: float = 0.08) -> np.ndarray:
    if n <= 0:
        return np.array([], dtype=float)
    return x_center + (np.random.rand(n) - 0.5) * 2.0 * width


def plot_response_curve(data: TrialData, trial_scalar: np.ndarray, trial_rows: np.ndarray, channel: int) -> None:
    currents = data.current_uA[trial_rows]
    scalar = trial_scalar[trial_rows]
    unique_currents = np.unique(currents[np.isfinite(currents)])
    unique_currents = np.sort(unique_currents)

    fig, ax = plt.subplots(figsize=(7.5, 5.2), facecolor="w")

    means = []
    stds = []
    for cur in unique_currents:
        cur_mask = np.isclose(currents, cur)
        y = scalar[cur_mask]
        y = y[np.isfinite(y)]
        if y.size == 0:
            means.append(np.nan)
            stds.append(np.nan)
            continue
        x_jit = make_jitter(float(cur), y.size)
        ax.plot(x_jit, y, ".", color="#1f77b4", markersize=10)
        means.append(np.nanmean(y))
        stds.append(np.nanstd(y))

    means = np.asarray(means, dtype=float)
    stds = np.asarray(stds, dtype=float)
    ax.errorbar(
        unique_currents,
        means,
        stds,
        fmt="o-",
        color="#d62728",
        linewidth=1.8,
        markersize=5,
        capsize=3,
    )

    ax.set_xlabel("Current (uA)")
    ax.set_ylabel("Mean V1 response")
    ax.set_title(f"ch{channel:03d} | trial-wise V1 response summary", fontsize=13)
    ax.grid(True, alpha=0.35)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    plt.tight_layout()
    plt.show()


def main() -> None:
    if not FILE_PATH.exists():
        raise FileNotFoundError(f"Update FILE_PATH at the top of the script. File not found: {FILE_PATH}")

    data = load_trial_file(FILE_PATH)
    trial_scalar = summarize_trials(data, SUMMARY_METRIC)
    channel_indices = select_channel_indices(data, CHANNEL_TO_PLOT)

    print(f"Loaded: {data.path}")
    print(f"n_trials: {data.v1_response_grid.shape[0]}")
    print(f"grid shape: {data.v1_response_grid.shape}")
    print(f"value shape: {data.v1_response_values.shape}")
    print(f"channels: {sorted(channel_indices)}")
    print(f"has v1_mask: {data.v1_mask is not None}")
    print(f"has final_mask: {data.final_mask is not None}")

    if not channel_indices:
        raise ValueError("No trials found for CHANNEL_TO_PLOT.")

    for channel, trial_rows in channel_indices.items():
        if MAKE_RESPONSE_CURVE_FIGURES:
            plot_response_curve(data, trial_scalar, trial_rows, channel)
        if MAKE_PER_CHANNEL_MAP_FIGURES:
            condition_rows = split_trials_by_current(data, trial_rows)
            for current_uA, rows in condition_rows.items():
                plot_condition_maps(data, trial_scalar, rows, channel, current_uA, cols=MAP_COLS)


if __name__ == "__main__":
    main()
