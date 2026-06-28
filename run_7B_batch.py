"""
run_9B_batch.py
---------------
Runs step 9_B (Method 1 significance thresholding) for multiple dF/F movie
files and multiple n_std values without any MATLAB UI dialogs.

Configure the paths and settings in the USER CONFIGURATION section below,
then run:
    python run_9B_batch.py

For each movie file, outputs land in a dedicated subfolder of SAVE_DIR:
    SAVE_DIR/
      {movie_stem}/
        thresh_{cond}_{n}sigma_m1.mat
        thresh_{cond}_{n}sigma_m1_frame_grid.png
        thresh_{cond}_{n}sigma_m1.mp4   (if EXPORT_VIDEO = True)
"""

import subprocess
import sys
import time
from pathlib import Path

# ==============================================================
# USER CONFIGURATION -- edit these before running
# ==============================================================

# Full path to your MATLAB executable.
# Examples:
#   Windows: r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
#   Mac:     "/Applications/MATLAB_R2026a.app/bin/matlab"
MATLAB_EXE = r"C:\Program Files\MATLAB\R2026a\bin\matlab.exe"

# Folder containing run_threshold_m1_batch.m (and all other pipeline scripts).
SCRIPT_DIR = r"C:\Project\LGN\analysis\longitudinal_stim_parameter_survey"

# dF/F movie files to threshold -- from step 5_B2 or 8_B2.
# Add as many paths as you want; they are processed one by one.
# Each movie must have the same spatial dimensions as the baseline file.
# Examples:
#   Whole-brain mean:  r"...\method1\ch16_5uA\mean_dff_m1_ch16_5uA.mat"
#   V1 mean:          r"...\method1_v1\ch16_7uA\v1_mean_dff_m1_ch16_7uA.mat"
MOVIE_FILES = [
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_0uA\v1_mean_dff_m1_ch16_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_2uA\v1_mean_dff_m1_ch16_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_3uA\v1_mean_dff_m1_ch16_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_4uA\v1_mean_dff_m1_ch16_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_5uA\v1_mean_dff_m1_ch16_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch16_7uA\v1_mean_dff_m1_ch16_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_0uA\v1_mean_dff_m1_ch18_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_2uA\v1_mean_dff_m1_ch18_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_3uA\v1_mean_dff_m1_ch18_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_4uA\v1_mean_dff_m1_ch18_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_5uA\v1_mean_dff_m1_ch18_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch18_7uA\v1_mean_dff_m1_ch18_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_0uA\v1_mean_dff_m1_ch28_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_2uA\v1_mean_dff_m1_ch28_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_3uA\v1_mean_dff_m1_ch28_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_4uA\v1_mean_dff_m1_ch28_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_5uA\v1_mean_dff_m1_ch28_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch28_7uA\v1_mean_dff_m1_ch28_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_0uA\v1_mean_dff_m1_ch32_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_2uA\v1_mean_dff_m1_ch32_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_3uA\v1_mean_dff_m1_ch32_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_4uA\v1_mean_dff_m1_ch32_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_5uA\v1_mean_dff_m1_ch32_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch32_7uA\v1_mean_dff_m1_ch32_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_0uA\v1_mean_dff_m1_ch50_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_2uA\v1_mean_dff_m1_ch50_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_3uA\v1_mean_dff_m1_ch50_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_4uA\v1_mean_dff_m1_ch50_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_5uA\v1_mean_dff_m1_ch50_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch50_7uA\v1_mean_dff_m1_ch50_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_0uA\v1_mean_dff_m1_ch84_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_2uA\v1_mean_dff_m1_ch84_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_3uA\v1_mean_dff_m1_ch84_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_4uA\v1_mean_dff_m1_ch84_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_5uA\v1_mean_dff_m1_ch84_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch84_7uA\v1_mean_dff_m1_ch84_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_0uA\v1_mean_dff_m1_ch86_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_2uA\v1_mean_dff_m1_ch86_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_3uA\v1_mean_dff_m1_ch86_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_4uA\v1_mean_dff_m1_ch86_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_5uA\v1_mean_dff_m1_ch86_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch86_7uA\v1_mean_dff_m1_ch86_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_0uA\v1_mean_dff_m1_ch87_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_2uA\v1_mean_dff_m1_ch87_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_3uA\v1_mean_dff_m1_ch87_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_4uA\v1_mean_dff_m1_ch87_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_5uA\v1_mean_dff_m1_ch87_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch87_7uA\v1_mean_dff_m1_ch87_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_0uA\v1_mean_dff_m1_ch96_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_2uA\v1_mean_dff_m1_ch96_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_3uA\v1_mean_dff_m1_ch96_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_4uA\v1_mean_dff_m1_ch96_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_5uA\v1_mean_dff_m1_ch96_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch96_7uA\v1_mean_dff_m1_ch96_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_0uA\v1_mean_dff_m1_ch114_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_2uA\v1_mean_dff_m1_ch114_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_3uA\v1_mean_dff_m1_ch114_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_4uA\v1_mean_dff_m1_ch114_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_5uA\v1_mean_dff_m1_ch114_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch114_7uA\v1_mean_dff_m1_ch114_7uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_0uA\v1_mean_dff_m1_ch122_0uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_2uA\v1_mean_dff_m1_ch122_2uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_3uA\v1_mean_dff_m1_ch122_3uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_4uA\v1_mean_dff_m1_ch122_4uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_5uA\v1_mean_dff_m1_ch122_5uA.mat",
    r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\dFFresult_method1\V1_region\method1_v1\ch122_7uA\v1_mean_dff_m1_ch122_7uA.mat",


]

# Global baseline file -- from step 5_B1 or 8_B1.
#   Whole-brain: global_baseline_m1.mat
#   V1:          global_baseline_m1_v1.mat
BASELINE_FILE = r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\global_baseline_m1_v1.mat"

# Root output folder.  Each movie gets its own subfolder inside this root.
# Subfolders are created automatically.
SAVE_DIR = r"C:\Project\LGN_analysis_results\LGN11_20260326_experiment\thresholded_dFFresult_method1"

# List of n_std multipliers to run.  One complete set of outputs per value.
N_STD_LIST = [0.2, 0.3, 0.4, 0.5, 0.6]

# Set to True to also export each thresholded movie as an MP4 video.
# Videos are slow to write; leave False for a quick first look.
EXPORT_VIDEO = False

# ==============================================================
# END OF CONFIGURATION
# ==============================================================


def matlab_path(p: str) -> str:
    """Convert a Windows path to forward slashes for use inside a MATLAB string."""
    return str(Path(p)).replace("\\", "/")


def build_matlab_expr(script_dir, movie_file, baseline_file, save_dir,
                      n_std_list, export_video):
    """Build the MATLAB -batch expression string."""
    n_std_vec = "[" + " ".join(str(n) for n in n_std_list) + "]"
    export_str = "true" if export_video else "false"

    return (
        f"addpath('{matlab_path(script_dir)}'); "
        f"run_threshold_m1_batch("
        f"'{matlab_path(movie_file)}', "
        f"'{matlab_path(baseline_file)}', "
        f"'{matlab_path(save_dir)}', "
        f"{n_std_vec}, "
        f"{export_str}"
        f")"
    )


def check_paths():
    """Verify configured paths exist before launching MATLAB."""
    errors = []
    if not Path(MATLAB_EXE).is_file():
        errors.append(f"MATLAB executable not found:\n    {MATLAB_EXE}")
    if not Path(SCRIPT_DIR).is_dir():
        errors.append(f"SCRIPT_DIR not found:\n    {SCRIPT_DIR}")
    if not MOVIE_FILES:
        errors.append("MOVIE_FILES is empty -- add at least one path.")
    for i, mf in enumerate(MOVIE_FILES):
        if not Path(mf).is_file():
            errors.append(f"MOVIE_FILES[{i}] not found:\n    {mf}")
    if not Path(BASELINE_FILE).is_file():
        errors.append(f"BASELINE_FILE not found:\n    {BASELINE_FILE}")
    if not N_STD_LIST:
        errors.append("N_STD_LIST is empty.")
    for n in N_STD_LIST:
        if not (isinstance(n, (int, float)) and n > 0):
            errors.append(f"Invalid n_std value: {n!r}  (must be a positive number)")
    return errors


def run_one_movie(movie_file, movie_index, n_total):
    """Launch MATLAB for a single movie file.  Returns (success, elapsed_s)."""
    movie_stem = Path(movie_file).stem
    movie_save_dir = Path(SAVE_DIR) / movie_stem
    movie_save_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'=' * 60}")
    print(f"  Movie {movie_index}/{n_total}: {Path(movie_file).name}")
    print(f"  Output: {movie_save_dir}")
    print(f"{'=' * 60}")

    matlab_expr = build_matlab_expr(
        SCRIPT_DIR, movie_file, BASELINE_FILE, str(movie_save_dir),
        N_STD_LIST, EXPORT_VIDEO
    )
    print(f"  Expression: {matlab_expr}\n")

    t0 = time.time()
    result = subprocess.run(
        [MATLAB_EXE, "-batch", matlab_expr],
        text=True,
        capture_output=False,   # let MATLAB print directly to this terminal
    )
    elapsed = time.time() - t0

    if result.returncode == 0:
        print(f"\n  [OK] Done in {elapsed:.1f} s")
    else:
        print(f"\n  [FAIL] MATLAB exited with code {result.returncode} after {elapsed:.1f} s")

    return result.returncode == 0, elapsed


def main():
    print("=" * 60)
    print("  Step 9_B batch runner - Method 1 significance threshold")
    print("=" * 60)

    # --- pre-flight checks ---
    errors = check_paths()
    if errors:
        print("\nConfiguration errors - fix before running:\n")
        for e in errors:
            print(f"  [FAIL]  {e}")
        sys.exit(1)

    n_movies = len(MOVIE_FILES)
    print(f"\nBaseline:  {BASELINE_FILE}")
    print(f"Root out:  {SAVE_DIR}")
    print(f"n_std:     {N_STD_LIST}")
    print(f"Video:     {EXPORT_VIDEO}")
    print(f"Movies:    {n_movies}")
    for i, mf in enumerate(MOVIE_FILES, 1):
        print(f"  [{i}] {mf}")

    results = []
    total_start = time.time()

    for i, movie_file in enumerate(MOVIE_FILES, 1):
        success, elapsed = run_one_movie(movie_file, i, n_movies)
        results.append((Path(movie_file).name, success, elapsed))

    total_elapsed = time.time() - total_start

    # --- summary ---
    n_ok   = sum(1 for _, ok, _ in results if ok)
    n_fail = n_movies - n_ok
    print(f"\n{'=' * 60}")
    print(f"  Summary  ({n_movies} movie(s)  |  total {total_elapsed:.1f} s)")
    print(f"{'=' * 60}")
    for name, ok, elapsed in results:
        status = "[OK]  " if ok else "[FAIL]"
        print(f"  {status}  {name}  ({elapsed:.1f} s)")
    print()
    if n_fail == 0:
        print(f"All {n_ok} movie(s) processed successfully.")
        print(f"Outputs are in subfolders of:\n  {SAVE_DIR}")
    else:
        print(f"{n_ok} succeeded, {n_fail} failed.  Check MATLAB output above for details.")
        sys.exit(1)


if __name__ == "__main__":
    main()