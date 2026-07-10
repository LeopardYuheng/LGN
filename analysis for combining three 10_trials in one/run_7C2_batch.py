"""
run_7C2_batch.py
-----------------
Applies step 7_C2 (directional count threshold) to every consensus .mat file
produced by step 7_C or 7_D, without any MATLAB UI dialogs.

Scans SOURCE_ROOT recursively for files matching consensus_*_m1.mat (skipping
any that already carry a _c<N> suffix, which are prior 7_C2 outputs). For
each file, calls run_7C2_batch.m with the configured threshold and writes
outputs into SAVE_DIR, mirroring the subfolder structure of SOURCE_ROOT:

    SAVE_DIR/
      <cond_folder>/
        consensus_<tag>_c<K>_frame_grid.png
        consensus_<tag>_c<K>_region.png
        consensus_<tag>_c<K>.mat

Configure the paths and parameters below, then run:
    python run_7C2_batch.py
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

# Folder containing run_7C2_batch.m.
SCRIPT_DIR = r"C:\Projects\LGN\data analysis pipeline\analysis for combining three 10_trials in one\longitudinal_stim_parameter_survey"

# Root folder to search for consensus_*_m1.mat files (output from 7_C or 7_D).
# All matching files in any subfolder are processed.
SOURCE_ROOT = r"C:\Projects\LGN\result\LGN24_06172026\step_7D_result"

# Output root folder. The subfolder structure under SOURCE_ROOT is mirrored
# here, so each condition's outputs land in SAVE_DIR/<cond_folder>/.
SAVE_DIR = r"C:\Projects\LGN\result\LGN24_06172026\step_7D_result_thresholded"

# Directional count threshold.
# A pixel is shown at timepoint t only when its DOMINANT direction reaches
# this count (count_act >= K and count_act >= count_sup, or vice versa).
MIN_COUNT_DISPLAY = 20

# ==============================================================
# END OF CONFIGURATION
# ==============================================================

# Match consensus_*_m1.mat but NOT files that already have _c<digits> suffix
# (those are prior 7_C2 outputs and should not be re-processed).
_SOURCE_RE = re.compile(r'^consensus_.*_m1\.mat$', re.I)
_C2_RE     = re.compile(r'_c\d+\.mat$', re.I)


def find_source_mats(root: str) -> list[str]:
    found = []
    for p in Path(root).rglob('*.mat'):
        if _SOURCE_RE.match(p.name) and not _C2_RE.search(p.name):
            found.append(str(p))
    return sorted(found)


def matlab_path(p: str) -> str:
    return str(Path(p)).replace('\\', '/')


def build_matlab_expr(mat_file: str, save_dir: str) -> str:
    return (
        f"addpath('{matlab_path(SCRIPT_DIR)}'); "
        f"run_7C2_batch("
        f"'{matlab_path(mat_file)}', "
        f"'{matlab_path(save_dir)}', "
        f"{MIN_COUNT_DISPLAY}"
        f")"
    )


def dest_dir(mat_file: str) -> str:
    """Mirror the source file's subfolder under SAVE_DIR."""
    rel = Path(mat_file).parent.relative_to(SOURCE_ROOT)
    return str(Path(SAVE_DIR) / rel)


def check_config(mat_files: list[str]) -> list[str]:
    errors = []
    if not Path(MATLAB_EXE).is_file():
        errors.append(f"MATLAB executable not found:\n    {MATLAB_EXE}")
    if not Path(SCRIPT_DIR).is_dir():
        errors.append(f"SCRIPT_DIR not found:\n    {SCRIPT_DIR}")
    if not Path(SOURCE_ROOT).is_dir():
        errors.append(f"SOURCE_ROOT not found:\n    {SOURCE_ROOT}")
    if not mat_files:
        errors.append(
            f"No consensus_*_m1.mat files found under:\n    {SOURCE_ROOT}\n"
            "    (Run step 7_C or 7_D first, or check SOURCE_ROOT.)"
        )
    if not (isinstance(MIN_COUNT_DISPLAY, int) and MIN_COUNT_DISPLAY >= 1):
        errors.append(f"MIN_COUNT_DISPLAY must be an integer >= 1, got {MIN_COUNT_DISPLAY!r}")
    return errors


def run_one(mat_file: str, index: int, n_total: int) -> tuple[bool, float]:
    save_dir = dest_dir(mat_file)
    Path(save_dir).mkdir(parents=True, exist_ok=True)

    print(f"\n{'=' * 60}")
    print(f"  [{index}/{n_total}]  {Path(mat_file).name}")
    print(f"  Output: {save_dir}")
    print(f"{'=' * 60}")

    expr = build_matlab_expr(mat_file, save_dir)
    print(f"  Expression: {expr}\n")

    t0     = time.time()
    result = subprocess.run([MATLAB_EXE, '-batch', expr], text=True, capture_output=False)
    elapsed = time.time() - t0

    ok = result.returncode == 0
    print(f"\n  {'[OK]' if ok else '[FAIL]'} Done in {elapsed:.1f} s")
    return ok, elapsed


def main():
    print('=' * 60)
    print('  Step 7_C2 batch runner — directional count threshold filter')
    print('=' * 60)

    mat_files = find_source_mats(SOURCE_ROOT)

    errors = check_config(mat_files)
    if errors:
        print('\nConfiguration errors — fix before running:\n')
        for e in errors:
            print(f'  [FAIL]  {e}')
        sys.exit(1)

    n_total = len(mat_files)
    print(f'\nSource root:       {SOURCE_ROOT}')
    print(f'Save root:         {SAVE_DIR}')
    print(f'MIN_COUNT_DISPLAY: {MIN_COUNT_DISPLAY}')
    print(f'Files found:       {n_total}')
    for i, f in enumerate(mat_files, 1):
        print(f'  [{i}] {Path(f).parent.name}/{Path(f).name}')

    results    = []
    total_t0   = time.time()
    for i, f in enumerate(mat_files, 1):
        ok, elapsed = run_one(f, i, n_total)
        results.append((Path(f).name, ok, elapsed))
    total_elapsed = time.time() - total_t0

    n_ok   = sum(1 for _, ok, _ in results if ok)
    n_fail = n_total - n_ok
    print(f"\n{'=' * 60}")
    print(f"  Summary  ({n_total} file(s)  |  total {total_elapsed:.1f} s)")
    print(f"{'=' * 60}")
    for name, ok, elapsed in results:
        print(f"  {'[OK]  ' if ok else '[FAIL]'}  {name}  ({elapsed:.1f} s)")
    print()
    if n_fail == 0:
        print(f"All {n_ok} file(s) processed successfully.")
        print(f"Outputs are in subfolders of:\n  {SAVE_DIR}")
    else:
        print(f"{n_ok} succeeded, {n_fail} failed. Check MATLAB output above.")
        sys.exit(1)


if __name__ == '__main__':
    main()
