"""
run_7A_batch.py
---------------
Runs step 7_A (Method 0 significance thresholding) for every mean_dff_ch*.mat
file found under COND_ROOT, without any MATLAB UI dialogs.

Auto-discovers all mean_dff_ch{N}_{I}uA.mat files in COND_ROOT and
processes them sorted by channel then current, matching the order shown
in the step-7_A interactive condition list.

Configure the paths and settings in the USER CONFIGURATION section, then:
    python run_7A_batch.py

Outputs land in a dedicated subfolder of SAVE_DIR per movie:
    SAVE_DIR/
      {movie_stem}/
        thresh_{cond}_{n}sigma.mat
        thresh_{cond}_{n}sigma_frame_grid.png
        thresh_{cond}_{n}sigma.mp4   (if EXPORT_VIDEO = True)
"""

import re
import subprocess
import sys
import time
from pathlib import Path

# ==============================================================
# USER CONFIGURATION -- edit these before running
# ==============================================================

# Full path to your MATLAB executable.
MATLAB_EXE = r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"

# Folder containing run_threshold_m0_batch.m and other pipeline scripts.
SCRIPT_DIR = r"C:\Projects\LGN\data analysis pipeline\analysis\longitudinal_stim_parameter_survey"

# Root folder containing ch{N}_{I}uA/ subfolders with mean_dff_ch*.mat files
# (i.e. the output root of step 5_A).
COND_ROOT = r"C:\Projects\LGN\result\LGN24_06172026\dFFresult_method0"

# Root output folder. Each movie gets its own subfolder inside.
SAVE_DIR = r"C:\Projects\LGN\result\LGN24_06172026\step_7A_result"

# List of n_std multipliers. One complete set of outputs per value.
N_STD_LIST = [3]

# Optional V1 boundary overlay. Set to '' to skip.
V1_SOURCE_FILE = r"C:\Projects\LGN\result\LGN24_06172026\LGN24_20260617_day_setup.mat"

# Frame-grid display window (seconds). Matches the dialog defaults in 7_A interactive.
DISPLAY_TMIN = -0.2
DISPLAY_TMAX =  1.2

# Set to True to also export each thresholded movie as an MP4 video.
EXPORT_VIDEO = False

# ==============================================================
# END OF CONFIGURATION
# ==============================================================

_CH_CUR_RE = re.compile(r'ch(\d+)_([\d.]+)uA', re.I)


def _ch_cur(path: Path):
    m = _CH_CUR_RE.search(path.name)
    return (int(m.group(1)), float(m.group(2))) if m else (10**9, 0.0)


def find_movie_files(root: str) -> list[str]:
    """Return mean_dff_ch*.mat files sorted by channel then current."""
    files = list(Path(root).rglob('mean_dff_ch*uA.mat'))
    return [str(p) for p in sorted(files, key=_ch_cur)]


def matlab_path(p: str) -> str:
    return str(Path(p)).replace('\\', '/')


def matlab_vec(values) -> str:
    return '[' + ' '.join(str(v) for v in values) + ']'


def build_matlab_expr(movie_file: str, save_dir: str) -> str:
    n_std_vec  = matlab_vec(N_STD_LIST)
    export_str = 'true' if EXPORT_VIDEO else 'false'
    v1_str     = f"'{matlab_path(V1_SOURCE_FILE)}'" if V1_SOURCE_FILE else "''"
    return (
        f"addpath('{matlab_path(SCRIPT_DIR)}'); "
        f"run_threshold_m0_batch("
        f"'{matlab_path(movie_file)}', "
        f"'{matlab_path(save_dir)}', "
        f"{n_std_vec}, "
        f"{export_str}, "
        f"{v1_str}, "
        f"{DISPLAY_TMIN}, "
        f"{DISPLAY_TMAX}"
        f")"
    )


def check_config(movie_files: list[str]) -> list[str]:
    errors = []
    if not Path(MATLAB_EXE).is_file():
        errors.append(f"MATLAB executable not found:\n    {MATLAB_EXE}")
    if not Path(SCRIPT_DIR).is_dir():
        errors.append(f"SCRIPT_DIR not found:\n    {SCRIPT_DIR}")
    if not Path(COND_ROOT).is_dir():
        errors.append(f"COND_ROOT not found:\n    {COND_ROOT}")
    if not movie_files:
        errors.append(
            f"No mean_dff_ch*.mat files found under:\n    {COND_ROOT}\n"
            "    (Run step 5_A first, or check COND_ROOT.)"
        )
    if not N_STD_LIST:
        errors.append("N_STD_LIST is empty.")
    for n in N_STD_LIST:
        if not (isinstance(n, (int, float)) and n > 0):
            errors.append(f"Invalid n_std value: {n!r} (must be positive)")
    if V1_SOURCE_FILE and not Path(V1_SOURCE_FILE).is_file():
        errors.append(f"V1_SOURCE_FILE not found:\n    {V1_SOURCE_FILE}")
    if not (DISPLAY_TMIN < DISPLAY_TMAX):
        errors.append(f"DISPLAY_TMIN ({DISPLAY_TMIN}) must be < DISPLAY_TMAX ({DISPLAY_TMAX})")
    return errors


def run_one(movie_file: str, index: int, n_total: int) -> tuple[bool, float]:
    movie_stem    = Path(movie_file).stem
    movie_save    = Path(SAVE_DIR) / movie_stem
    movie_save.mkdir(parents=True, exist_ok=True)

    print(f"\n{'=' * 60}")
    print(f"  [{index}/{n_total}]  {Path(movie_file).name}")
    print(f"  Output: {movie_save}")
    print(f"{'=' * 60}")

    expr = build_matlab_expr(movie_file, str(movie_save))
    print(f"  Expression: {expr}\n")

    t0     = time.time()
    result = subprocess.run([MATLAB_EXE, '-batch', expr], text=True, capture_output=False)
    elapsed = time.time() - t0

    ok = result.returncode == 0
    print(f"\n  {'[OK]' if ok else '[FAIL]'} Done in {elapsed:.1f} s")
    return ok, elapsed


def main():
    print('=' * 60)
    print('  Step 7_A batch runner — Method 0 significance threshold')
    print('=' * 60)

    movie_files = find_movie_files(COND_ROOT)

    errors = check_config(movie_files)
    if errors:
        print('\nConfiguration errors — fix before running:\n')
        for e in errors:
            print(f'  [FAIL]  {e}')
        sys.exit(1)

    n_movies = len(movie_files)
    print(f'\nCOND_ROOT:      {COND_ROOT}')
    print(f'SAVE_DIR:       {SAVE_DIR}')
    print(f'n_std:          {N_STD_LIST}')
    print(f'Display window: {DISPLAY_TMIN} to {DISPLAY_TMAX} s')
    print(f'V1 overlay:     {V1_SOURCE_FILE or "none"}')
    print(f'Video:          {EXPORT_VIDEO}')
    print(f'Movies found:   {n_movies}')
    for i, f in enumerate(movie_files, 1):
        print(f'  [{i}] {Path(f).parent.name}/{Path(f).name}')

    results    = []
    total_t0   = time.time()
    for i, f in enumerate(movie_files, 1):
        ok, elapsed = run_one(f, i, n_movies)
        results.append((Path(f).name, ok, elapsed))
    total_elapsed = time.time() - total_t0

    n_ok   = sum(1 for _, ok, _ in results if ok)
    n_fail = n_movies - n_ok
    print(f"\n{'=' * 60}")
    print(f"  Summary  ({n_movies} movie(s)  |  total {total_elapsed:.1f} s)")
    print(f"{'=' * 60}")
    for name, ok, elapsed in results:
        print(f"  {'[OK]  ' if ok else '[FAIL]'}  {name}  ({elapsed:.1f} s)")
    print()
    if n_fail == 0:
        print(f"All {n_ok} movie(s) processed successfully.")
        print(f"Outputs are in subfolders of:\n  {SAVE_DIR}")
    else:
        print(f"{n_ok} succeeded, {n_fail} failed.  Check MATLAB output above.")
        sys.exit(1)


if __name__ == '__main__':
    main()