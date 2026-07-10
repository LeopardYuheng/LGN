# Combined-Session Pipeline — 3×10 Trials in One

This folder is a copy of the current [longitudinal_stim_parameter_survey](../analysis/longitudinal_stim_parameter_survey/)
pipeline, modified for experiments that were split into **multiple
independent acquisition sessions** covering the same channel/current design,
instead of one long session.

**Scenario this covers:** same channels and currents, same randomized
stimulation-trial sequence design as before, but instead of running 30
trials per channel/current combination in one session, you ran 10
trials/combination, three separate times (3 sessions), each with its own
TIFF folder and `.nev` file. Steps 5_A and 5_B here pool all 3×10 = 30
trials per condition together, so the combined result is equivalent to
having run the full 30-trial session directly.

**Step 5_A and step 5_B were changed** to combine sessions, and **step 2
and step 3 were changed** so their output filenames are session-distinguishable
(see below). Every other step (0, 1, TIFF-check/fix, 4, 6, 7, 8) is an
unmodified copy — see [README_brief.md](../README_brief.md) /
[README_detailed.md](../README_detailed.md) at the repo root for what each
step does; nothing below duplicates that.

## What's different here

### Steps 0–3: run once per session

[draw_brain_mask_0.m](longitudinal_stim_parameter_survey/draw_brain_mask_0.m)
is run **once** and reused for all sessions — dF/F from every session is
combined pixel-by-pixel with a single shared brain mask, which requires the
same field of view / camera position across all sessions. If the FOV moved
between sessions, this combined pipeline does not apply (no cross-session
image registration is performed).

[extract_nev_stim_and_camera_1.m](longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m),
the [TIFF-check / TIFF-fix](longitudinal_stim_parameter_survey/Diagnose%26fix_code/)
scripts,
[align_wf_with_nev_extracted_2.m](longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m),
and
[make_container_ripple_3.m](longitudinal_stim_parameter_survey/make_container_ripple_3.m)
are run **once per session** (3 times total), each pointed at that
session's own image folder and `.nev` file.

**Session-distinguishable filenames.** All 3 sessions typically share the
same subject ID and date, but not every step's output filename in the
original pipeline accounts for that:

| Script | Output filename | Session-distinguishable? |
|---|---|---|
| step 1 (`extract_nev_stim_and_camera_1.m`) | `{mouse}_{date}_{base_name}.mat` | Yes — `base_name` is a free-text dialog field (e.g. type `session1_ripple_timing`) |
| TIFF-check (`build_tiff_sma1_correction_map.m`) | `{SESSION_ID}_tiff_correction.mat` | Yes — `SESSION_ID` is free-text console input |
| step 2 (`align_wf_with_nev_extracted_2.m`) | `{subject}_{date}[_{session_label}]_wf_trial_alignment.mat` | **Yes, added here** — new "Session label" prompt (e.g. `session1`); leave blank to keep the original naming |
| step 3 (`make_container_ripple_3.m`) | `{subject}_{date}[_{session_label}]_day_pointer.mat` | **Yes, added here** — automatically inherits step 2's session label from the loaded `wf_trial_alignment.mat`, no need to enter it again |

Type a distinct session label (`session1`, `session2`, `session3`) into
step 2's new prompt for each session — step 3 then tags its own output the
same way automatically. Step 3 also now refuses to run (with a clear error)
if you accidentally point it at a container that already holds a
*different* session's `img_dir`, instead of silently merging trials from
two TIFF folders into one entry list.

Even with distinguishable filenames, it's still good practice to keep each
session's outputs in that session's own folder — step 5 asks for each
session's day pointer one at a time later, so you just browse to the right
place each time.

### Step 4: run once per session

[baseline_drift_analysis_4.m](longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m)
is also run **once per session** (3 times), each against that session's own
day pointer, producing 3 separate `baseline_drift_4.mat` files (one per
session's own output folder). This is required, not optional: the drift
model is fit in that session's own clock time (seconds from that session's
own frame 1), so a drift model from one session is not valid for another.
Method 0 (step 5_A) doesn't use a drift model at all, so this only matters
if you're running Track B/C (Method 1).

### Step 5_A / step 5_B: the combined step

Both scripts now start by asking **how many sessions to combine** (default
3), then prompt for each session's day pointer in turn (Session 1, Session
2, ...); step 5_B additionally asks for each session's own
`baseline_drift_4.mat` right after its day pointer. All sessions must share
the same camera rate and pre/post trial window — this is checked and the
script errors out if they don't match.

After that, everything works exactly like the single-session scripts: pick
the brain mask (once, shared), optional V1 overlay (once, shared), the
display time window, and which channel/current conditions to process. Every
selected condition's trials are pooled across **all** sessions before
averaging.

Output format is unchanged — `mean_dff_ch{N}_{I}uA.mat` /
`mean_dff_m1_ch{N}_{I}uA.mat` still contain exactly the same fields
(`mean_dff_movie`, `t_s`, `final_mask`) as the single-session versions, so
steps 6/7/8 need no changes to consume them. The only visible difference is
per-trial filenames now carry a session tag —
`dff_ch{N}_{I}uA_s{S}_trial{K}.mat` / `dff_m1_ch{N}_{I}uA_s{S}_trial{K}.mat`
— so e.g. session 1's trial 3 and session 2's trial 3 don't overwrite each
other (trial numbering restarts at 1 in each session). This is transparent
to steps 7_C/7_D/7_E, which discover per-trial files by glob pattern and
don't care about the exact numbers.

### Steps 6, 7, 8: unchanged

[retino_alignment_with_brain_mask_6.m](longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)
runs once (shared V1 boundary, same reasoning as the shared brain mask).
Steps 7_A/7_B/7_C/7_D/7_C2/7_E and step 8 all read the step 5_A/5_B output
folders exactly like they do in the single-session pipeline — just point
them at this combined step 5's output. The Python batch drivers
(`run_7A_batch.py` etc.) are copied here too, with `SCRIPT_DIR` already
pointed at this folder's `longitudinal_stim_parameter_survey/`.

## What was intentionally left out of this copy

`ephys/`, `legacy code/`, and `latency_and_baseline_scripts/` from the
original folder were not copied — they're either dataset-specific outputs
from a prior analysis or deprecated scripts, unrelated to the step 0–8
imaging pipeline this folder adapts. Pull anything you need from
[analysis/longitudinal_stim_parameter_survey/](../analysis/longitudinal_stim_parameter_survey/)
directly if you need it.