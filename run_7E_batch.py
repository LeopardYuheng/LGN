"""
run_7E_batch.py
---------------
Runs step 7_E (sustained + latency-consistent activation) for every
channel-current condition folder under COND_ROOT, without any MATLAB UI
dialogs.

Configure the paths and parameters in the USER CONFIGURATION section, then:
    python run_7E_batch.py

Each condition gets its own subfolder inside SAVE_DIR:
    SAVE_DIR/
      ch{N}_{I}uA/
        sustained_ch{N}_{I}uA_<params>_m1.mat
        sustained_ch{N}_{I}uA_<params>_m1_region.png
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
MATLAB_EXE = r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"

# Folder containing run_sustained_m1_batch.m and consensus_7E.m.
SCRIPT_DIR = r"C:\Projects\LGN\data analysis pipeline\analysis\longitudinal_stim_parameter_survey"

# Root folder whose subfolders are the per-condition movie folders
# (each must contain dff_m1_*_trial*.mat files from step 5_B).
COND_ROOT = r"C:\Projects\LGN\result\LGN24_06172026\method1 prethreshold analysis\method1"
COND_DIRS = sorted(
    str(p) for p in Path(COND_ROOT).iterdir()
    if p.is_dir() and list(p.glob("dff_m1_*_trial*.mat"))
)

# Root output folder. Each condition gets its own subfolder inside.
SAVE_DIR = r"C:\Projects\LGN\result\LGN24_06172026\step_7E_result"

# Path to brain_mask.mat (from pre-step B).
BRAIN_MASK_FILE = r"C:\Projects\LGN\result\LGN24_06172026\LGN24_20260617_brain_mask.mat"

# Step 7_E parameters.
N_STD          = 1      # threshold multiplier
MIN_DURATION_S = 0.3    # minimum consecutive activation duration (seconds)
MIN_TRIALS_SUST = 18    # trials that must have a sustained run
MIN_TRIALS_WIN  = 15    # sustained trials whose onset must cluster in one window
ONSET_WINDOW_S  = 0.5   # sliding window width for onset consistency (seconds)

# Optional V1 boundary overlay. Set to '' to skip.
V1_SOURCE_FILE = r"C:\Projects\LGN\result\LGN24_06172026\LGN24_20260617_day_setup.mat"

# ==============================================================
# END OF CONFIGURATION
# ==============================================================


def matlab_path(p: str) -> str:
    return str(Path(p)).replace("\\", "/")


def build_matlab_expr(cond_dir: str, save_dir: str) -> str:
    v1_str = f"'{matlab_path(V1_SOURCE_FILE)}'" if V1_SOURCE_FILE else "''"
    return (
        f"addpath('{matlab_path(SCRIPT_DIR)}'); "
        f"run_sustained_m1_batch("
        f"'{matlab_path(cond_dir)}', "
        f"'{matlab_path(save_dir)}', "
        f"'{matlab_path(BRAIN_MASK_FILE)}', "
        f"{N_STD}, "
        f"{MIN_DURATION_S}, "
        f"{MIN_TRIALS_SUST}, "
        f"{MIN_TRIALS_WIN}, "
        f"{ONSET_WINDOW_S}, "
        f"{v1_str}"
        f")"
    )


def check_paths():
    errors = []
    if not Path(MATLAB_EXE).is_file():
        errors.append(f"MATLAB executable not found:\n    {MATLAB_EXE}")
    if not Path(SCRIPT_DIR).is_dir():
        errors.append(f"SCRIPT_DIR not found:\n    {SCRIPT_DIR}")
    if not Path(BRAIN_MASK_FILE).is_file():
        errors.append(f"BRAIN_MASK_FILE not found:\n    {BRAIN_MASK_FILE}")
    if not COND_DIRS:
        errors.append(f"No condition folders found under:\n    {COND_ROOT}")
    for i, cd in enumerate(COND_DIRS):
        if not Path(cd).is_dir():
            errors.append(f"COND_DIRS[{i}] not found:\n    {cd}")
        elif not list(Path(cd).glob("dff_m1_*_trial*.mat")):
            errors.append(f"COND_DIRS[{i}] has no per-trial movies:\n    {cd}")
    if V1_SOURCE_FILE and not Path(V1_SOURCE_FILE).is_file():
        errors.append(f"V1_SOURCE_FILE not found:\n    {V1_SOURCE_FILE}")
    for name, val in [("N_STD", N_STD), ("MIN_DURATION_S", MIN_DURATION_S),
                      ("MIN_TRIALS_SUST", MIN_TRIALS_SUST),
                      ("MIN_TRIALS_WIN", MIN_TRIALS_WIN),
                      ("ONSET_WINDOW_S", ONSET_WINDOW_S)]:
        if not (isinstance(val, (int, float)) and val > 0):
            errors.append(f"{name} must be a positive number, got {val!r}")
    return errors


def run_one_condition(cond_dir: str, index: int, n_total: int):
    cond_name  = Path(cond_dir).name
    cond_save  = Path(SAVE_DIR) / cond_name
    cond_save.mkdir(parents=True, exist_ok=True)

    print(f"\n{'=' * 60}")
    print(f"  [{index}/{n_total}]  {cond_name}")
    print(f"  Output: {cond_save}")
    print(f"{'=' * 60}")

    expr = build_matlab_expr(cond_dir, str(cond_save))
    print(f"  Expression: {expr}\n")

    t0     = time.time()
    result = subprocess.run([MATLAB_EXE, "-batch", expr], text=True, capture_output=False)
    elapsed = time.time() - t0

    ok = result.returncode == 0
    print(f"\n  {'[OK]' if ok else '[FAIL]'} Done in {elapsed:.1f} s")
    return ok, elapsed


def main():
    print("=" * 60)
    print("  Step 7_E batch runner — sustained + latency-consistent region")
    print("=" * 60)

    errors = check_paths()
    if errors:
        print("\nConfiguration errors — fix before running:\n")
        for e in errors:
            print(f"  [FAIL]  {e}")
        sys.exit(1)

    n_cond = len(COND_DIRS)
    print(f"\nRoot out:       {SAVE_DIR}")
    print(f"Brain mask:     {BRAIN_MASK_FILE}")
    print(f"V1 overlay:     {V1_SOURCE_FILE or 'none'}")
    print(f"n_std:          {N_STD}")
    print(f"min_duration_s: {MIN_DURATION_S} s")
    print(f"min_trials_sust:{MIN_TRIALS_SUST}")
    print(f"min_trials_win: {MIN_TRIALS_WIN}")
    print(f"onset_window_s: {ONSET_WINDOW_S} s")
    print(f"Conditions:     {n_cond}")
    for i, cd in enumerate(COND_DIRS, 1):
        print(f"  [{i}] {cd}")

    results    = []
    total_t0   = time.time()
    for i, cd in enumerate(COND_DIRS, 1):
        ok, elapsed = run_one_condition(cd, i, n_cond)
        results.append((Path(cd).name, ok, elapsed))
    total_elapsed = time.time() - total_t0

    n_ok   = sum(1 for _, ok, _ in results if ok)
    n_fail = n_cond - n_ok
    print(f"\n{'=' * 60}")
    print(f"  Summary  ({n_cond} condition(s)  |  total {total_elapsed:.1f} s)")
    print(f"{'=' * 60}")
    for name, ok, elapsed in results:
        print(f"  {'[OK]  ' if ok else '[FAIL]'}  {name}  ({elapsed:.1f} s)")
    print()
    if n_fail == 0:
        print(f"All {n_ok} condition(s) processed successfully.")
        print(f"Outputs are in subfolders of:\n  {SAVE_DIR}")
    else:
        print(f"{n_ok} succeeded, {n_fail} failed. Check MATLAB output above.")
        sys.exit(1)


if __name__ == "__main__":
    main()