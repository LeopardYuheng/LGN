"""
run_9D_batch.py
---------------
Runs step 9_D (Method 1 per-trial cross-trial CONSENSUS thresholding) for
multiple channel-current condition folders, and for multiple n_std /
min_trials values, without any MATLAB UI dialogs or interactive viewer.

Step 9_D is the TIME-WINDOW variant of 9_C: a pixel counts as activated /
suppressed at time t in a trial if it crosses threshold anywhere in the window
[t - WINDOW_S, t + WINDOW_S] (default +/-0.1 s), not only in the single frame t.
This absorbs small trial-to-trial latency offsets. For each trial a pixel is
flagged active at time t when

    dF/F(x,y,tau) - baseline_dF/F(x,y) > n_std * sigma_pre(x,y)
    for some tau in [t - WINDOW_S, t + WINDOW_S]   (and the mirror for suppressed)

where dF/F uses the Method 1 global baseline (F_global), baseline_dF/F is the
trial's own pre-stim mean, and sigma_pre is the trial's pre-stim std. A pixel
is "consensus-active" at time t for the condition when at least MIN_TRIALS of
the N trials agree (e.g. 25 of 30). Pixels consensus-active at any post-stim
time form the stimulation-related region for that channel-current condition.

Configure the paths/settings below, then run:
    python run_9D_batch.py

Each (condition, n_std) pair gets its own subfolder of SAVE_DIR, named with the
n_std value:
    SAVE_DIR/
      {cond_folder_name}_{n}sigma/
        consensus_{cond}_{n}sigma_min{M}of{N}_m1.mat
        consensus_{cond}_{n}sigma_min{M}of{N}_m1_frame_grid.png   (t in [-0.2, 1.2] s)
        consensus_{cond}_{n}sigma_min{M}of{N}_m1_region.png
        consensus_{cond}_{n}sigma_min{M}of{N}_m1_summary.txt
        consensus_{cond}_{n}sigma_min{M}of{N}_m1.mp4   (if EXPORT_VIDEO = True)

Activation is directional: a pixel counts as consensus only if it is driven the
SAME way (up = activated, or down = suppressed) in >= MIN_TRIALS trials. Maps are
colored by net count (activated - suppressed): red = activated, blue = suppressed,
white/grey = no/balanced consensus.
"""

import subprocess
import sys
import time
from pathlib import Path

# ==============================================================
# USER CONFIGURATION -- edit these before running
# ==============================================================

# Full path to your MATLAB executable.
#   Windows: r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
#   Mac:     "/Applications/MATLAB_R2026a.app/bin/matlab"
MATLAB_EXE = r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"

# Folder containing run_consensus_m1_batch.m, get_v1_boundary.m, etc.
SCRIPT_DIR = r"C:\Projects\LGN\data analysis pipeline\analysis for combining three 10_trials in one\longitudinal_stim_parameter_survey"

# Condition folders, each holding per-trial Method 1 movies from step 5_B2:
#   .../method1/ch{N}_{I}uA/dff_m1_ch{N}_{I}uA_trial{K}.mat
# All channel-current condition subfolders under COND_ROOT are analysed.
COND_ROOT = r"C:\Projects\LGN\result\LGN24_06172026\method1 prethreshold analysis\method1"
COND_DIRS = sorted(
    str(p) for p in Path(COND_ROOT).iterdir()
    if p.is_dir() and (list(p.glob("dff_m1_*_trial*.mat")) or list(p.glob("v1_dff_m1_*_trial*.mat")))
)

# Root output folder. Each condition gets its own subfolder inside this root.
SAVE_DIR = r"C:\Projects\LGN\result\LGN24_06172026\step_7D_result"

# Significance multipliers (threshold = n_std * each trial's pre-stim std).
N_STD_LIST = [1]

# Consensus counts: a pixel is consensus-active at time t if active in at
# least this many trials. Default 25 (of e.g. 30). Each value produces its
# own set of outputs; the value is clamped to the number of trials available.
MIN_TRIALS_LIST = [20]

# Step 9_D ONLY: time-window half-width (seconds). A pixel counts as activated/
# suppressed at time t if it crosses threshold anywhere in [t-WINDOW_S, t+WINDOW_S].
# Absorbs trial-to-trial latency jitter. At 10 Hz, 0.1 s = +/-1 frame.
WINDOW_S = 0.1

# V1 boundary overlay (always on). Point this at the day_setup .mat containing
# retino_align.V1_mask_stim (from step 6). The whole-brain consensus result is
# unchanged; the V1 boundary is only drawn on the figures/videos.
V1_SOURCE_FILE = r"C:\Projects\LGN\result\LGN24_06172026\LGN24_20260617_day_setup.mat"

# Set True to also export each consensus-count movie as an MP4 (slow).
EXPORT_VIDEO = False

# ==============================================================
# END OF CONFIGURATION
# ==============================================================


def matlab_path(p: str) -> str:
    """Convert a Windows path to forward slashes for use inside a MATLAB string."""
    return str(Path(p)).replace("\\", "/")


def matlab_vec(values) -> str:
    return "[" + " ".join(str(v) for v in values) + "]"


def build_matlab_expr(script_dir, cond_dir, save_dir, n_std_list,
                      min_trials_list, v1_source_file, export_video):
    """Build the MATLAB -batch expression string."""
    export_str = "true" if export_video else "false"
    v1_str = "''" if not v1_source_file else f"'{matlab_path(v1_source_file)}'"
    return (
        f"addpath('{matlab_path(script_dir)}'); "
        f"run_consensus_window_m1_batch("
        f"'{matlab_path(cond_dir)}', "
        f"'{matlab_path(save_dir)}', "
        f"{matlab_vec(n_std_list)}, "
        f"{matlab_vec(min_trials_list)}, "
        f"{v1_str}, "
        f"{export_str}, "
        f"{WINDOW_S}"
        f")"
    )


def check_paths():
    """Verify configured paths exist before launching MATLAB."""
    errors = []
    if not Path(MATLAB_EXE).is_file():
        errors.append(f"MATLAB executable not found:\n    {MATLAB_EXE}")
    if not Path(SCRIPT_DIR).is_dir():
        errors.append(f"SCRIPT_DIR not found:\n    {SCRIPT_DIR}")
    if not COND_DIRS:
        errors.append("COND_DIRS is empty -- add at least one condition folder.")
    for i, cd in enumerate(COND_DIRS):
        if not Path(cd).is_dir():
            errors.append(f"COND_DIRS[{i}] not found:\n    {cd}")
        else:
            trials = list(Path(cd).glob("dff_m1_*_trial*.mat")) + \
                     list(Path(cd).glob("v1_dff_m1_*_trial*.mat"))
            if not trials:
                errors.append(f"COND_DIRS[{i}] has no per-trial movies:\n    {cd}")
    if not N_STD_LIST:
        errors.append("N_STD_LIST is empty.")
    for n in N_STD_LIST:
        if not (isinstance(n, (int, float)) and n > 0):
            errors.append(f"Invalid n_std value: {n!r} (must be a positive number)")
    if not MIN_TRIALS_LIST:
        errors.append("MIN_TRIALS_LIST is empty.")
    for m in MIN_TRIALS_LIST:
        if not (isinstance(m, int) and m >= 1):
            errors.append(f"Invalid min_trials value: {m!r} (must be an integer >= 1)")
    if V1_SOURCE_FILE:
        if not Path(V1_SOURCE_FILE).is_file():
            errors.append(f"V1_SOURCE_FILE not found:\n    {V1_SOURCE_FILE}")
    return errors


def nstd_tag(n_std):
    """Folder-safe label for an n_std value (e.g. 1 -> '1sigma', 1.5 -> '1p5sigma')."""
    return f"{n_std:g}".replace(".", "p") + "sigma"


def run_one_condition(cond_dir, n_std, index, n_total):
    """Launch MATLAB for one (condition, n_std). Returns (success, elapsed_s).

    Output folder name includes the n_std value, e.g. ch16_0uA_1sigma/.
    """
    cond_name = Path(cond_dir).name
    cond_save_dir = Path(SAVE_DIR) / f"{cond_name}_{nstd_tag(n_std)}"
    cond_save_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'=' * 60}")
    print(f"  Run {index}/{n_total}: {cond_name}  |  n_std = {n_std}")
    print(f"  Output: {cond_save_dir}")
    print(f"{'=' * 60}")

    matlab_expr = build_matlab_expr(
        SCRIPT_DIR, cond_dir, str(cond_save_dir),
        [n_std], MIN_TRIALS_LIST, V1_SOURCE_FILE, EXPORT_VIDEO
    )
    print(f"  Expression: {matlab_expr}\n")

    t0 = time.time()
    result = subprocess.run(
        [MATLAB_EXE, "-batch", matlab_expr],
        text=True,
        capture_output=False,
    )
    elapsed = time.time() - t0

    if result.returncode == 0:
        print(f"\n  [OK] Done in {elapsed:.1f} s")
    else:
        print(f"\n  [FAIL] MATLAB exited with code {result.returncode} after {elapsed:.1f} s")
    return result.returncode == 0, elapsed


def main():
    print("=" * 60)
    print("  Step 9_D batch runner - Method 1 time-windowed cross-trial consensus")
    print("=" * 60)

    errors = check_paths()
    if errors:
        print("\nConfiguration errors - fix before running:\n")
        for e in errors:
            print(f"  [FAIL]  {e}")
        sys.exit(1)

    n_cond = len(COND_DIRS)
    print(f"\nRoot out:    {SAVE_DIR}")
    print(f"n_std:       {N_STD_LIST}")
    print(f"min_trials:  {MIN_TRIALS_LIST}")
    print(f"V1 overlay:  {V1_SOURCE_FILE if V1_SOURCE_FILE else 'none'}")
    print(f"Video:       {EXPORT_VIDEO}")
    print(f"Conditions:  {n_cond}")
    for i, cd in enumerate(COND_DIRS, 1):
        print(f"  [{i}] {cd}")

    # One run per (condition, n_std) so each n_std gets its own output folder.
    combos = [(cd, n) for cd in COND_DIRS for n in N_STD_LIST]
    n_runs = len(combos)

    results = []
    total_start = time.time()
    for i, (cond_dir, n_std) in enumerate(combos, 1):
        success, elapsed = run_one_condition(cond_dir, n_std, i, n_runs)
        results.append((f"{Path(cond_dir).name} | {nstd_tag(n_std)}", success, elapsed))
    total_elapsed = time.time() - total_start

    n_ok   = sum(1 for _, ok, _ in results if ok)
    n_fail = n_runs - n_ok
    print(f"\n{'=' * 60}")
    print(f"  Summary  ({n_runs} run(s) over {n_cond} condition(s)  |  total {total_elapsed:.1f} s)")
    print(f"{'=' * 60}")
    for name, ok, elapsed in results:
        status = "[OK]  " if ok else "[FAIL]"
        print(f"  {status}  {name}  ({elapsed:.1f} s)")
    print()
    if n_fail == 0:
        print(f"All {n_ok} run(s) processed successfully.")
        print(f"Outputs are in subfolders of:\n  {SAVE_DIR}")
    else:
        print(f"{n_ok} succeeded, {n_fail} failed.  Check MATLAB output above for details.")
        sys.exit(1)


if __name__ == "__main__":
    main()
