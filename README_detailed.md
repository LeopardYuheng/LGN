# Luan Lab Widefield Post-Experiment Guide

Once you finish an experiment, the most important thing is to keep the data
organized and unified before running analysis.

This repository's scripts pass file paths from one step to the next. Early
scripts save bookkeeping files that point to image folders, setup files, CSVs,
and session timing files. Later scripts load those saved paths back in and
expect the data to still be in the same place.

Because of that:

- Put the data in its final location before running the pipeline.
- Keep one consistent folder structure across subjects and sessions.
- Do not move or rename image folders, ephys folders, or session files after
  analysis files have been generated.
- If data is moved after bookkeeping files are created, later scripts may fail
  because they still point to the original locations.

## First Thing To Do

Set up the file structure clearly and consistently.

Recommended structure:

```text
SubjectName/
  img/
  ephys/
```

Where:

- `SubjectName` is the subject folder for that experiment or session grouping.
- `img` contains the widefield TIFF data and related imaging outputs.
- `ephys` contains the electrophysiology data generated from the experiment.

The key point is consistency. The scripts are easier to use when every
experiment follows the same structure, and future users can trace the pipeline
much more easily when imaging and ephys data live in the same predictable
layout.

## Why Keeping Everything Unified Matters

The pipeline links several data sources together:

- TIFF image folders
- stimulation timing extracted from electrophysiology recordings
- stimulation condition CSV files
- downstream analysis outputs
- retinotopy outputs (applied after dF/F analysis for V1 boundary overlay)

These are not treated as isolated files. They become connected through saved
`.mat` files that store metadata and paths. If one piece is moved later, the
rest of the pipeline may no longer know where to find it.

Keeping everything unified helps with:

- reproducibility
- easier troubleshooting
- cleaner handoff to the next person
- fewer broken path issues
- easier across-session comparisons

## After The Experiment: Analysis Order

### Pre-step A (Optional): Prepare retinotopy inputs

Run [retino_inputcombine.m](analysis/longitudinal_stim_parameter_survey/retino_inputcombine.m)
to combine `azi.mat`, `alt.mat`, and `additional_maps.mat` into one input file
(`retino_registration_ready.mat`). Only needed if those files were saved
separately by the acquisition system.

### Pre-step B: Draw brain boundary mask

Run [draw_brain_mask_0.m](analysis/longitudinal_stim_parameter_survey/draw_brain_mask_0.m).

This script loads a reference image averaged from the stimulation-day TIFFs
and lets you draw a polygon around the brain (to exclude scalp, skull edges,
and artifacts). It saves a `brain_mask.mat` file used by downstream scripts
to restrict analysis to in-brain pixels.

### Steps 1–3: Electrophysiology and widefield alignment

Run in numbered order:

1. [extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)
2. [align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)
3. [make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

### Step 4: Pixelwise fluorescence drift analysis

Run [baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m).

Fits a per-pixel linear model `F(x,y) = slope(x,y)·t + intercept(x,y)` across
all 0 µA (no-stimulation) trials, where `t = (onset_frame − 1) / Fs` is the
session-clock time of each trial. Saves `baseline_drift_4.mat` containing
`slope_map`, `intercept_map`, and `r2_map`, plus diagnostic figures (slope map,
R² map, mean-F scatter with linear fit).

**Step 4 is required before step 5_B.** The slope and intercept maps are the
drift model that 5_B uses to compute a per-trial, time-varying baseline.

### Step 5: Compute whole-brain pixelwise dF/F(x,y,t) movies

Step 5 has two branches. **Run 5_B** (Method 1, drift-corrected) for the
standard analysis. Step 5_A (Method 0) is kept for reference or comparison.

#### Step 5_A (Method 0 — per-trial baseline)

Run [current_thresholding_analysis_pixelwise_region_5A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_5A.m).

Each trial's dF/F is normalized by that trial's own pre-stimulation mean:
`dF/F = (F − F_pre_trial) / F_pre_trial`. Does not use step 4's drift model.
Outputs go into `save_dir/ch{N}_{I}uA/`.

#### Step 5_B (Method 1 — drift-corrected dF/F movies)

Run [compute_dff_method1_5B.m](analysis/longitudinal_stim_parameter_survey/compute_dff_method1_5B.m).

Loads `slope_map` and `intercept_map` directly from `baseline_drift_4.mat`
(step 4). For each trial with session-clock onset
`t_session = (onset_frame − 1) / Fs`:

```
F_baseline(x,y) = intercept_map(x,y) + slope_map(x,y) · t_session
dF/F(x,y,t)    = [ F(x,y,t) − F_baseline(x,y) ] / F_baseline(x,y)
```

Because the baseline tracks the slow session-wide fluorescence ramp, each
trial is normalized by the expected F at its own point in time — later trials
are not over-corrected relative to earlier ones. Saves per-trial movies
`dff_m1_ch{N}_{I}uA_trial{K}.mat` and trial averages under
`method1/ch{N}_{I}uA/`. These per-trial movies are the input to step 7_C / 7_D.

### Step 6: Retinotopic mapping and V1 boundary

Run [retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m).

- Loads retinotopy output (azi, alt, VFS maps)
- Aligns the retinotopic map to the stimulation-day image using affine
  registration (manual `cpselect` or auto + nudge)
- Defines V1 and other visual area boundaries in stimulation-day pixel
  coordinates
- Saves a unified `day_setup` struct (`reference_mask_and_retino_alignment.mat`)
  including both the brain mask and the retinotopic alignment

The V1 boundary (`retino_align.V1_mask_stim`) from this file is used as an
optional overlay in all step 7 scripts. dF/F computation is whole-brain and
is never cropped to V1; the boundary is display-only.

### Step 7: Per-pixel significance thresholding and stimulation region

Step 7 applies significance thresholding to the dF/F movies from step 5. All
step 7 scripts optionally accept a `day_setup` file from step 6 to draw the
V1 boundary as a green contour — the threshold and numerical result are
unchanged.

**V1 handling.** dF/F is always on the whole-brain mask. When prompted for a
V1 boundary file, select the `day_setup` from step 6. The overlay is
display-only and can be skipped (Cancel = none).

#### Step 7_C — Per-trial cross-trial consensus region *(main analysis)*

[consensus_region_method1_7C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_7C.m) — interactive
[run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) — headless batch, driven by [run_9C_batch.py](run_9C_batch.py)

Analyzes **every trial of a channel-current condition individually** and
combines them by per-timepoint voting. Consumes the per-trial Method 1 movies
in one condition folder (`method1/ch{N}_{I}uA/dff_m1_*_trial*.mat` from step
5_B).

**Per-trial thresholding.** For each trial, `baseline_dF/F(x,y)` is the
pre-stim mean of `dF/F(x,y,t)` (mean over `t_s < 0`). A pixel is flagged
directionally:

```
activated   ⟺   dF/F(x,y,t) − baseline_dF/F(x,y)  >  n_std × σ_pre(x,y)
suppressed  ⟺   dF/F(x,y,t) − baseline_dF/F(x,y)  < −n_std × σ_pre(x,y)
```

where `σ_pre(x,y)` is the std of that trial's pre-stim `dF/F` and `n_std` is
user-chosen (default 3). Activated and suppressed counts are kept separate. A
pixel reaches consensus only if it is driven the *same* way in ≥ `min_trials`
trials (a mixed activation/suppression split is treated as noise). Pixels
consensus-active at any post-stim timepoint form the stimulation-related region.

Maps are colored by the signed net count (`activated − suppressed`) on a jet
(rainbow) scale `[−N, +N]`: red = activated, green ≈ neutral, blue =
suppressed. A **magenta contour** outlines consensus pixels. Frame grid covers
**t ∈ [−0.2, 1.2] s**.

Outputs per `(n_std, min_trials)`, tagged
`consensus_<cond>_<n>σ_min<M>of<N>_m1`:

- `.mat` — `count_activated_u16`, `count_suppressed_u16` (H×W×T), `consensus`,
  `region_mask`, `region_signed` (H×W), `n_std`, `min_trials`, `n_used`,
  `t_s`, `always_nan_mask`, `V1_mask`
- `_frame_grid.png` — signed net-count map at selected timepoints
- `_region.png` — stimulation-related region + peak-consensus frame
- `_summary.txt` — region pixel count (split activated/suppressed), peak
  timepoint, settings
- `_m1.mp4` — optional signed net-count movie
- Interactive viewer (single-condition script): time slider + static region
  map; click pixels to plot activated / suppressed trial counts over time

Batch runner (`run_9C_batch.py`) sweeps `N_STD_LIST` and `MIN_TRIALS_LIST`,
writes each `n_std` to its own folder (`ch{N}_{I}uA_{n}sigma/`), overlays the
V1 boundary from `V1_SOURCE_FILE`.

#### Step 7_D — Time-window consensus region *(latency-robust variant of 7_C)*

[consensus_region_window_method1_7D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_7D.m) — interactive
[run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) — headless batch, driven by [run_9D_batch.py](run_9D_batch.py)

Identical to 7_C with one change to the per-trial activation rule. A pixel
counts as activated/suppressed at time `t` if it crosses threshold **anywhere
in the window `[t − window_s, t + window_s]`** (default `window_s = 0.1 s`;
±1 frame at 10 Hz):

```
activated at t   ⟺   dF/F(x,y,τ) − baseline > +n_std·σ_pre   for some τ ∈ [t−ws, t+ws]
suppressed at t  ⟺   dF/F(x,y,τ) − baseline < −n_std·σ_pre   for some τ ∈ [t−ws, t+ws]
```

The window absorbs trial-to-trial latency jitter so a response landing one
frame early or late still counts. Output filenames carry a `win{window_s}s`
tag. In practice 7_D recovers substantially more consensus than 7_C at the
same `n_std`. Use 7_D when latency jitter matters; use 7_C for strict
same-frame agreement.

#### Step 7_C2 — Directional count threshold on 7_C / 7_D output *(optional)*

[consensus_7C2.m](analysis/longitudinal_stim_parameter_survey/consensus_7C2.m) (interactive)
or [run_7C2_batch.py](run_7C2_batch.py) → [run_7C2_batch.m](analysis/longitudinal_stim_parameter_survey/run_7C2_batch.m) (batch)

A lightweight post-processing filter that reads a saved `.mat` from **step
7_C or step 7_D** (no per-trial movie re-loading) and applies a stricter
directional count threshold for display. At each timepoint t, a pixel is
only rendered when its *dominant* direction reaches `min_count_display`:

```
shown as activated  ⟺  count_act(x,y,t) >= min_count_display  AND  count_act >= count_sup
shown as suppressed ⟺  count_sup(x,y,t) >= min_count_display  AND  count_sup >  count_act
```

This prevents mixed pixels (e.g. 15 activated + 15 suppressed, net = 0
→ spurious neutral green) from appearing. All other in-brain pixels are
shown as inactive gray. The region is recomputed with the same
direction-preference logic. Outputs are tagged `_c<K>` (e.g.
`consensus_ch16_5uA_1sigma_min20of30_m1_c15`) and written next to the
source `.mat`. The batch runner (`run_7C2_batch.py`) scans `SOURCE_ROOT`
recursively for all `consensus_*_m1.mat` files and skips any `_c<K>` files
already produced by a prior 7_C2 run.

#### Step 7_E — Sustained and latency-consistent activation region *(optional)*

[consensus_7E.m](analysis/longitudinal_stim_parameter_survey/consensus_7E.m)

Identifies pixels that are **activated (or suppressed) for a sustained
consecutive duration** in enough trials, and whose activation **onset time
clusters within a narrow latency window** across those trials. Complementary
to 7_C / 7_D: where 7_C asks "does this pixel cross threshold at this
timepoint in enough trials?", 7_E asks "does this pixel stay active long
enough, and does that activation start at a reproducible latency?"

**Step 1 — per-trial sustained activation.** For each trial k, the same
baseline subtraction and threshold as 7_C is applied (pre-stim mean
subtracted, threshold = `n_std × σ_pre`). The post-stim activation sequence
is then scanned for **consecutive runs** of activated (or suppressed) frames.
A trial is flagged as **sustained** for pixel (x,y) if at least one
consecutive run lasts ≥ `min_duration_s` seconds. The onset time `t_onset_k`
is the time of the first frame of the *first qualifying run* in that trial.

**Step 2 — onset consistency check.** Among all sustained trials, a sliding
window of width `onset_window_s` is swept over the sorted `t_onset_k` values.
The window position that captures the most onsets defines the **peak onset
count**. A pixel is marked as **consecutively and consistently activated** only
when both criteria are met:

1. `n_sustained ≥ min_trials_sustained` — enough trials have a qualifying
   sustained run
2. `peak onset count ≥ min_trials_window` — enough of those onsets cluster
   within one `onset_window_s`-wide latency band (the band is found
   automatically; it can fall anywhere in the post-stim period)

Activated and suppressed directions are evaluated separately — a pixel must
meet both criteria in the *same* direction (mixed activation/suppression
across trials does not qualify).

**Example.** Pixel (x,y) has a sustained run in 20 of 30 trials. The onset
times are spread, but 13 fall between 0.3 s and 0.8 s (a 0.5 s window). With
`min_trials_window = 12`, this pixel qualifies (`13 ≥ 12`). If instead no
0.5 s window captures ≥ 12 onsets, the pixel does **not** qualify even though
20 trials show sustained activation.

**Parameters** (entered interactively via dialog):

| Parameter | Default | Meaning |
|---|---|---|
| `n_std` | 1 | threshold multiplier (same as 7_C) |
| `min_duration_s` | 0.3 s | minimum consecutive activation duration per trial |
| `min_trials_sustained` | 15 | trials that must show a qualifying sustained run |
| `min_trials_window` | 12 | sustained trials whose onset must fall in one window |
| `onset_window_s` | 0.5 s | width of the sliding onset-consistency window |

**Outputs** per condition, tagged
`sustained_<cond>_<n>σ_dur<D>s_minT<M>_win<W>s_m1`:

- `_region.png` — spatial map of consistently activated / suppressed pixels
  (activated in red, suppressed in blue), with brain boundary and optional V1
  contour
- `.mat` — `activated_region` and `suppressed_region` (H×W logical),
  `n_sustained_act` and `n_sustained_sup` (H×W, trial count with a qualifying
  run), `peak_onset_count_act` and `peak_onset_count_sup` (H×W, max trials in
  best onset window), `best_onset_window_act` and `best_onset_window_sup`
  (H×W×2, `[t_start, t_end]` of the best window per pixel), all parameters,
  `t_s`

#### Step 7_B — Single-movie threshold, Method 1 *(optional)*

[threshold_dff_method1_7B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_7B.m)

Works on a single dF/F movie from step 5_B (per-trial or trial-averaged). Uses
the same logic as 7_C: subtracts the pre-stim mean of the loaded movie from
each frame, then flags pixels where
`|dF/F − baseline_dff| > n_std · pixel_std` (pre-stim std of that movie). No
external baseline file is required. Produces a thresholded frame-grid figure,
optional MP4, and interactive pixel-picking viewer.

#### Step 7_A — Single-movie threshold, Method 0 *(optional)*

[dff_pixelwise_significance_threshold_7A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_7A.m)

Works on any dF/F movie from step 5_A (per-trial or trial-averaged). Computes
the per-pixel threshold from the movie's own pre-stimulation frames (`t_s < 0`)
and flags `|dF/F(x,y,t)| > n_std · σ_pre(x,y)`. Produces the same output
types as 7_B plus an interactive time-slider viewer.

---

## What Each Step Is Doing

### Pre-step B — Draw brain boundary mask

[draw_brain_mask_0.m](analysis/longitudinal_stim_parameter_survey/draw_brain_mask_0.m)

- Averages a set of TIFF frames to build a clean reference image
- Lets the user draw a polygon over the brain area interactively
- Saves a `brain_mask.mat` containing `final_mask` (logical H×W)

### Step 1

[extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)

- Extracts stimulation and camera timing from the ephys recording (.nev file)
- SMA 1 → camera frame timestamps; SMA 2 → PulsePal sync; SMA 3 → camera-ready gate
- Saves `ripple_timing.mat` used for widefield/ephys alignment in step 2

### Step 2

[align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)

- Aligns the widefield TIFF sequence with extracted stimulation timing
- Combines imaging, timing, setup, and stimulation-condition information

### Step 3

[make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

- Builds the day pointer/container used by downstream scripts
- Stores references to the relevant files and grouped trial information

### Step 4 — Pixelwise fluorescence drift analysis

[baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m)

Uses all 0 µA trials to model slow fluorescence drift across the session:

- Loads the day pointer and brain mask; prompts for an output folder
- For each 0 µA trial, loads the raw TIFF stack for the full trial window and
  reduces it to a single mean image (one H×W data point per trial)
- Fits `F(x,y) = slope·t_onset + intercept` per pixel in closed form;
  `t_onset = (onset_frame − 1) / Fs` (seconds from session start)
- Saves `baseline_drift_4.mat`: `slope_map` (H×W, ΔF/s), `intercept_map`,
  `r2_map`, `t_onset_vec`, trial count
- Saves `baseline_drift_slope_r2.png`: slope map (bwr, centred at zero) and
  R² map (parula)
- Saves `baseline_drift_summary_scatter.png`: mean in-mask F per trial vs
  onset time with fitted line (left), and residuals (right)

A flat slope map and trendless scatter means the session baseline is stable.
Significant drift makes drift correction in step 5_B necessary.

### Step 5_A — Whole-brain pixelwise dF/F, Method 0 (per-trial baseline)

[current_thresholding_analysis_pixelwise_region_5A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_5A.m)

For each channel-current stimulation condition:

- Computes `dF/F(x,y,t) = [F(x,y,t) − F_pre_trial(x,y)] / F_pre_trial(x,y)`
  where `F_pre_trial(x,y)` is the mean pixel intensity over the pre-stim frames
  of that specific trial
- Saves per-trial movies `dff_ch{N}_{I}uA_trial{K}.mat` and the trial-averaged
  `mean_dff_ch{N}_{I}uA.mat`
- Generates frame-grid figures (jet colormap, autoscaled per figure)
- Optionally exports per-trial and/or mean dF/F movies as MP4
- Outputs grouped into `save_dir/ch{N}_{I}uA/`

### Step 5_B — Whole-brain pixelwise dF/F, Method 1 (drift-corrected baseline)

[compute_dff_method1_5B.m](analysis/longitudinal_stim_parameter_survey/compute_dff_method1_5B.m)

- Loads `slope_map` and `intercept_map` from `baseline_drift_4.mat` (step 4)
- For each trial at session-clock time `t_session = (onset_frame − 1) / Fs`:
  - Computes `F_baseline(x,y) = intercept_map + slope_map · t_session`
  - Computes `dF/F(x,y,t) = [F(x,y,t) − F_baseline(x,y)] / F_baseline(x,y)`
- Saves per-trial movies `dff_m1_ch{N}_{I}uA_trial{K}.mat` and the
  trial-averaged `mean_dff_m1_ch{N}_{I}uA.mat`
- Generates frame-grid figures (jet colormap, autoscaled per figure)
- Optionally exports per-trial and/or mean dF/F movies as MP4
- Outputs grouped into `save_dir/method1/ch{N}_{I}uA/`

### Step 6 — Retinotopic mapping and region labeling

[retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)

- Loads retinotopy output (azi, alt, VFS maps)
- Aligns the retinotopic map to the stimulation-day image using affine
  registration
- Defines V1 and other visual area boundaries in stimulation-day pixel
  coordinates
- Saves a unified `day_setup` struct: `reference_mask_and_retino_alignment.mat`
  including both the brain mask and the retinotopic alignment

Once this is done, the V1 boundary (`retino_align.V1_mask_stim`) is available
as an optional overlay for all step 7 scripts. dF/F computation stays
whole-brain; V1 is drawn only as a contour.

### Step 7_C — Per-trial cross-trial consensus region, Method 1

[consensus_region_method1_7C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_7C.m) — interactive
[run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) — headless batch, driven by [run_9C_batch.py](run_9C_batch.py)

Analyzes every trial of a channel-current condition individually and combines
them by per-timepoint voting. Consumes the per-trial Method 1 movies from step
5_B (`method1/ch{N}_{I}uA/`).

**dF/F and the per-trial baseline.** The per-trial movies already carry the
drift-corrected `dF/F` from step 5_B. For each trial, step 7_C additionally
subtracts that trial's pre-stim mean:

```
baseline_dF/F(x,y)  = mean( dF/F(x,y, t<0) )   [this trial]
σ_pre(x,y)          = std(  dF/F(x,y, t<0) )   [this trial]
```

A pixel is flagged directionally:

```
activated   ⟺   dF/F(x,y,t) − baseline_dF/F(x,y)  >  n_std × σ_pre(x,y)
suppressed  ⟺   dF/F(x,y,t) − baseline_dF/F(x,y)  < −n_std × σ_pre(x,y)
```

Activated and suppressed counts are tracked separately across trials. A pixel
reaches consensus only when driven the *same* direction in ≥ `min_trials`
trials (default 25). Mixed activation/suppression is treated as noise.

Outputs per `(n_std, min_trials)`, tagged
`consensus_<cond>_<n>σ_min<M>of<N>_m1`:

- `.mat` — `count_activated_u16`, `count_suppressed_u16` (H×W×T),
  `consensus`, `region_mask`, `region_signed` (H×W)
- `_frame_grid.png` — signed net-count map (jet scale) with magenta consensus
  contour and optional V1 overlay
- `_region.png` — stimulation-related region + peak-consensus frame
- `_summary.txt` — pixel count, peak timepoint, settings
- `_m1.mp4` — optional movie

Batch runner sweeps `N_STD_LIST` × `MIN_TRIALS_LIST`, reusing the per-trial
pass across `min_trials` values.

### Step 7_D — Time-window consensus region, Method 1 (latency-robust 7_C)

[consensus_region_window_method1_7D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_7D.m) — interactive
[run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) — headless batch, driven by [run_9D_batch.py](run_9D_batch.py)

Identical to 7_C with one change to the per-trial activation rule. A pixel
counts as activated/suppressed at time `t` if it crosses threshold **anywhere
in the window `[t − window_s, t + window_s]`** (default `window_s = 0.1 s`):

```
activated at t   ⟺   dF/F(x,y,τ) − baseline > +n_std·σ_pre   for some τ ∈ [t−ws, t+ws]
suppressed at t  ⟺   dF/F(x,y,τ) − baseline < −n_std·σ_pre   for some τ ∈ [t−ws, t+ws]
```

Implemented as a temporal max-dilation of per-trial activation maps by
`window_frames = round(window_s / dt)` before voting. Output filenames carry a
`win{window_s}s` tag. In practice 7_D recovers substantially more consensus
than 7_C at the same `n_std`. Use 7_D when latency jitter matters; use 7_C
for strict same-frame agreement.

### Step 7_C2 — Directional count threshold filter on 7_C / 7_D output

[consensus_7C2.m](analysis/longitudinal_stim_parameter_survey/consensus_7C2.m) (interactive)
[run_7C2_batch.m](analysis/longitudinal_stim_parameter_survey/run_7C2_batch.m) — headless batch, driven by [run_7C2_batch.py](run_7C2_batch.py)

Works on the saved `.mat` from step 7_C **or** step 7_D — no per-trial movie
re-loading required:

- Loads `count_activated_u16` and `count_suppressed_u16` (H×W×T) from the
  source `.mat`
- At each timepoint t applies a directional dominance test:
  `act_dom = count_act >= K AND count_act >= count_sup` (activated display)
  `sup_dom = count_sup >= K AND count_sup > count_act` (suppressed display)
  where K = `min_count_display`. Only `act_dom | sup_dom` pixels are colored;
  all other in-brain pixels are shown as inactive gray
- Recomputes the stimulation-related region using the same dominance test
  applied to per-pixel max counts across post-stim frames
- Saves `_c<K>_frame_grid.png`, `_c<K>_region.png`, and `_c<K>.mat` next to
  the source `.mat` (no separate SAVE_DIR needed)

**Batch runner** (`run_7C2_batch.py`): set `SOURCE_ROOT` to the 7_C or 7_D
result folder. The script recursively finds all `consensus_*_m1.mat` files
and skips any `_c<K>` files already produced by a prior run. Each source file
is processed in a separate MATLAB `-batch` call.

### Step 7_E — Sustained and latency-consistent activation region

[consensus_7E.m](analysis/longitudinal_stim_parameter_survey/consensus_7E.m)

- Loads the per-trial Method 1 dF/F movies from one condition folder
  (`method1/ch{N}_{I}uA/`) from step 5_B
- For each trial, subtracts the pre-stim mean and thresholds at
  `n_std × σ_pre` (same as 7_C); scans post-stim frames for consecutive
  activated / suppressed runs; records a trial as **sustained** if any run
  lasts ≥ `min_duration_s` s, and records `t_onset_k` = start of the first
  qualifying run
- Sweeps a sliding window of width `onset_window_s` over the sorted
  `t_onset_k` values of the sustained trials; the window position capturing
  the most onsets gives the **peak onset count** per pixel
- A pixel is in the output region if `n_sustained ≥ min_trials_sustained` AND
  `peak onset count ≥ min_trials_window`, evaluated separately for activation
  and suppression
- Saves `_region.png` and `.mat` per condition (see parameter table in the
  Analysis Order section above for variable names and defaults)
- Optional V1 boundary overlay

### Step 7_B — Per-pixel significance thresholding, Method 1 (optional)

[threshold_dff_method1_7B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_7B.m)

A single-movie utility for Method 1 dF/F movies from step 5_B:

- Computes `baseline_dff(x,y) = mean(dF/F, t<0)` and
  `pixel_std(x,y) = std(dF/F, t<0)` from the movie's own pre-stim frames
- Flags `|dF/F(x,y,t) − baseline_dff(x,y)| > n_std · pixel_std(x,y)`
- Produces a thresholded frame-grid figure, optional MP4, and interactive
  pixel-picking viewer with per-pixel `dF/F(t)` plots
- No external baseline file required; optional V1 boundary overlay

### Step 7_A — Per-pixel significance thresholding, Method 0 (optional)

[dff_pixelwise_significance_threshold_7A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_7A.m)

A generic single-movie utility for Method 0 dF/F movies from step 5_A:

- Computes `σ_pre(x,y) = std(dF/F, t<0)` from the movie's own pre-stim frames
- Flags `|dF/F(x,y,t)| > n_std · σ_pre(x,y)`
- Saves thresholded movie + per-pixel std map as `.mat`, frame-grid figure,
  optional MP4, and interactive time-slider viewer with pixel picking
- Optional V1 boundary overlay

---

## Important Path Behavior

Several scripts save structures that contain file paths or relative file
references. These saved outputs are then reused by later scripts.

That means:

- choose the correct folders when prompted
- make sure the experiment data is already in its final home
- avoid reorganizing the dataset midway through analysis

If you need to reorganize data, do it before running the pipeline, not after.

## Practical Rule

Once the experiment data is in place and you start running the pipeline, treat
the folder locations as fixed.
