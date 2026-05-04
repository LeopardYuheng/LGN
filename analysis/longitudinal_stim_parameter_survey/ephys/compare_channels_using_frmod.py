#!/usr/bin/env python3
"""
Compare stimulation channels based on unit firing-rate responses from
FRmod_2Session_MatchedUnit_Result.mat (MATLAB v7.3 / HDF5).

Outputs (in --out-dir):
- FR_per_unit_per_channel_<Session>.csv
- FR_per_unit_per_channel_combined.csv
- spearman_corr_channels_<Session>.csv
- spearman_corr_channels_combined.csv
- spearman_corr_channels_<Session>.png
- spearman_corr_channels_combined.png
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict

import h5py
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats import spearmanr


SESSIONS = ("Session1", "Session2")


def load_session_tables(mat_path: Path) -> Dict[str, pd.DataFrame]:
    """Load trial-level unit responses per session into DataFrames."""
    session_tables: Dict[str, pd.DataFrame] = {}

    with h5py.File(mat_path, "r") as f:
        for session in SESSIONS:
            base = f[f"Result/{session}"]
            stim_mean = np.array(base["stim_mean_mat"], dtype=float)  # units x trials
            stim_channel = np.array(base["stim_channel"], dtype=float).ravel()
            current = np.array(base["current"], dtype=float).ravel()

            n_units, n_trials = stim_mean.shape
            if stim_channel.size != n_trials or current.size != n_trials:
                raise ValueError(
                    f"{session}: trial metadata mismatch. "
                    f"stim_mean trials={n_trials}, stim_channel={stim_channel.size}, current={current.size}"
                )

            unit_ids = np.repeat(np.arange(1, n_units + 1), n_trials)
            trial_ids = np.tile(np.arange(1, n_trials + 1), n_units)
            channel_rep = np.tile(stim_channel, n_units)
            current_rep = np.tile(current, n_units)
            stim_flat = stim_mean.reshape(-1, order="C")

            session_tables[session] = pd.DataFrame(
                {
                    "session": session,
                    "unit": unit_ids,
                    "trial": trial_ids,
                    "stim_channel": channel_rep,
                    "current_uA": current_rep,
                    "stim_mean_hz": stim_flat,
                }
            )

    return session_tables


def per_unit_per_channel(df: pd.DataFrame) -> pd.DataFrame:
    """Mean firing-rate response per unit per stim channel."""
    pivot = df.pivot_table(
        index="unit",
        columns="stim_channel",
        values="stim_mean_hz",
        aggfunc="mean",
    )
    pivot = pivot.sort_index(axis=0).sort_index(axis=1)
    return pivot


def spearman_channel_corr(per_unit_channel: pd.DataFrame) -> pd.DataFrame:
    """Channel-channel Spearman correlation across units."""

    def _rho(x: pd.Series, y: pd.Series) -> float:
        x_arr = np.asarray(x, dtype=float)
        y_arr = np.asarray(y, dtype=float)
        valid = np.isfinite(x_arr) & np.isfinite(y_arr)
        if valid.sum() < 3:
            return np.nan
        return float(spearmanr(x_arr[valid], y_arr[valid]).correlation)

    return per_unit_channel.corr(method=_rho)


def save_heatmap(corr_df: pd.DataFrame, out_png: Path, title: str) -> None:
    fig, ax = plt.subplots(figsize=(8, 7), dpi=150)
    im = ax.imshow(corr_df.values, vmin=-1, vmax=1, cmap="coolwarm")
    ax.set_title(title)
    ax.set_xlabel("Stim channel")
    ax.set_ylabel("Stim channel")

    labels = [f"{c:g}" for c in corr_df.columns]
    ax.set_xticks(np.arange(len(labels)))
    ax.set_yticks(np.arange(len(labels)))
    ax.set_xticklabels(labels, rotation=45, ha="right")
    ax.set_yticklabels(labels)

    cbar = fig.colorbar(im, ax=ax)
    cbar.set_label("Spearman rho")

    fig.tight_layout()
    fig.savefig(out_png)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare channels by unit firing-rate profile from FRmod MAT file."
    )
    parser.add_argument(
        "--mat",
        type=Path,
        required=True,
        help="Path to FRmod_2Session_MatchedUnit_Result.mat",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Output folder (default: MAT file folder)",
    )
    args = parser.parse_args()

    mat_path = args.mat.expanduser().resolve()
    if not mat_path.exists():
        raise FileNotFoundError(f"MAT file not found: {mat_path}")

    out_dir = args.out_dir.expanduser().resolve() if args.out_dir else mat_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    session_tables = load_session_tables(mat_path)

    per_session_mats: Dict[str, pd.DataFrame] = {}
    corr_mats: Dict[str, pd.DataFrame] = {}

    for session, df in session_tables.items():
        per_unit_chan = per_unit_per_channel(df)
        corr = spearman_channel_corr(per_unit_chan)

        per_session_mats[session] = per_unit_chan
        corr_mats[session] = corr

        per_unit_csv = out_dir / f"FR_per_unit_per_channel_{session}.csv"
        corr_csv = out_dir / f"spearman_corr_channels_{session}.csv"
        corr_png = out_dir / f"spearman_corr_channels_{session}.png"

        per_unit_chan.to_csv(per_unit_csv)
        corr.to_csv(corr_csv)
        save_heatmap(corr, corr_png, f"Channel Similarity ({session})")

    common_channels = sorted(
        set(per_session_mats["Session1"].columns).intersection(per_session_mats["Session2"].columns)
    )
    if len(common_channels) < 2:
        raise RuntimeError("Need at least two common channels across sessions for combined analysis.")

    p1 = per_session_mats["Session1"][common_channels]
    p2 = per_session_mats["Session2"][common_channels]

    common_units = sorted(set(p1.index).intersection(p2.index))
    combined = pd.concat([p1.loc[common_units], p2.loc[common_units]], axis=0).groupby(level=0).mean()

    combined_corr = spearman_channel_corr(combined)

    combined_per_unit_csv = out_dir / "FR_per_unit_per_channel_combined.csv"
    combined_corr_csv = out_dir / "spearman_corr_channels_combined.csv"
    combined_corr_png = out_dir / "spearman_corr_channels_combined.png"

    combined.to_csv(combined_per_unit_csv)
    combined_corr.to_csv(combined_corr_csv)
    save_heatmap(combined_corr, combined_corr_png, "Channel Similarity (Combined Sessions)")

    # Print top non-diagonal channel pairs for quick review.
    flat = combined_corr.unstack().dropna()
    flat = flat[flat.index.get_level_values(0) != flat.index.get_level_values(1)]
    flat = flat.sort_values(ascending=False)

    print(f"Input MAT: {mat_path}")
    print(f"Output dir: {out_dir}")
    print("Top 10 channel-pair Spearman correlations (combined):")
    print(flat.head(10))


if __name__ == "__main__":
    main()
