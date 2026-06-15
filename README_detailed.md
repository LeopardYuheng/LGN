# Luan Lab Widefield Post-Experiment Guide

Once you finish an experiment, the most important thing is to keep the data organized and unified before running analysis.

This repository's scripts pass file paths from one step to the next. Early scripts save bookkeeping files that point to image folders, setup files, CSVs, and session timing files. Later scripts load those saved paths back in and expect the data to still be in the same place.

Because of that:

- Put the data in its final location before running the pipeline.
- Keep one consistent folder structure across subjects and sessions.
- Do not move or rename image folders, ephys folders, or session files after analysis files have been generated.
- If data is moved after bookkeeping files are created, later scripts may fail because they still point to the original locations.

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

The key point is consistency. The scripts are easier to use when every experiment follows the same structure, and future users can trace the pipeline much more easily when imaging and ephys data live in the same predictable layout.

## Why Keeping Everything Unified Matters

The pipeline links several data sources together:

- TIFF image folders
- stimulation timing extracted from electrophysiology recordings
- stimulation condition CSV files
- downstream analysis outputs
- retinotopy outputs (applied after dF/F analysis if V1-specific work is needed)

These are not treated as isolated files. They become connected through saved `.mat` files that store metadata and paths. If one piece is moved later, the rest of the pipeline may no longer know where to find it.

Keeping everything unified helps with:

- reproducibility
- easier troubleshooting
- cleaner handoff to the next person
- fewer broken path issues
- easier across-session comparisons

## After The Experiment: Analysis Order

### Pre-step A (Optional): Prepare retinotopy inputs

Run [retino_inputcombine.m](analysis/retinotopic_mapping/retino_inputcombine.m) to combine `azi.mat`, `alt.mat`, and `additional_maps.mat` into one input file (`retino_registration_ready.mat`). Only needed if those files were saved separately by the acquisition system.

### Pre-step B: Draw brain boundary mask

Run [draw_brain_mask_0.m](analysis/retinotopic_mapping/draw_brain_mask_0.m).

This script loads a reference image averaged from the stimulation-day TIFFs and lets you draw a polygon around the brain (to exclude scalp, skull edges, and artifacts). It saves a `brain_mask.mat` file that is used by downstream scripts to restrict analysis to in-brain pixels.

This is a lightweight script derived from `reference_mask_and_retino_alignment.m`. It does **not** require retinotopy data and does **not** draw any V1 boundary — it only defines what is brain vs. non-brain in the image.

### Steps 1–3: Electrophysiology and widefield alignment

Run in numbered order:

1. [extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)
2. [align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)
3. [make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

### Step 4: Pixelwise fluorescence drift analysis

Run [baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m).

Before computing dF/F, run this step to verify that raw fluorescence F(x,y) is stable across the session. It uses all 0 uA (no-stimulation) trials and fits a per-pixel linear model `F(x,y) = slope·t + intercept` where `t` is global session time. The slope map and R² map tell you whether the raw baseline is drifting, which informs which dF/F baseline method to use in step 5.

**Whole-brain version**: run immediately after step 3, using the brain mask from pre-step B.

**V1-restricted version**: run again after completing steps 6 and 7. At that point the day pointer contains the V1-aware `day_setup`, so the script can restrict the drift analysis to V1 pixels and produce V1-specific slope and R² maps. Note that steps 6 and 7 must be completed first to obtain the V1 boundary.

### Step 5 (Only run for whole-brain analysis): Compute whole-brain pixelwise dF/F(x,y,t) movies

If you only need V1-restricted analysis, skip this step and go directly to step 6.

Step 5 has two parallel branches depending on which baseline normalization method you use. Both branches produce equivalent output formats so step 9 works the same way regardless.

#### Step 5_A (Method 0 — per-trial baseline)

Run [current_thresholding_analysis_pixelwise_region_5A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_5A.m).

Each trial's dF/F is normalized by that trial's own pre-stimulation mean: `dF/F = (F − F_pre_trial) / F_pre_trial`. Standard approach; does not require step 4's output.

#### Step 5_B1 (Method 1, part 1 — compute global baseline and std)

Run `compute_global_baseline_5B1.m` *(script to be added)*.

Uses all 0 uA trials to compute two per-pixel maps from raw fluorescence:
- `F_global(x,y)` — grand mean F across all frames of all 0 uA trials; used as the common baseline denominator in step 5_B2
- `std_dff_m1(x,y)` — per-pixel std of `(F − F_global) / F_global` across those same frames; used as the significance threshold in step 9_B

Run step 5_B1 before step 5_B2. Its output is also reused by step 9_B.

#### Step 5_B2 (Method 1, part 2 — compute dF/F with global baseline)

Run `compute_dff_method1_5B2.m` *(script to be added)*.

Computes dF/F for every stimulated condition using `F_global` from step 5_B1: `dF/F = (F − F_global) / F_global`. Saves per-trial and trial-averaged dF/F movies in the same format as step 5_A, under a `method1/` subfolder.

### Step 6 (Only run for V1 analysis): Retinotopic mapping and region labeling

Run [retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m).

Aligns the retinotopic map to the stimulation-day image and labels which pixels belong to V1 and other visual areas. Saves a new `day_setup` file containing both the brain mask and the retinotopic alignment (named as `reference_mask_and_retino_alignment` in retino_map_alignment folder).

This step is intentionally placed after step 5: you can inspect whole-brain dF/F activation before committing to a V1 boundary.

### Step 7 (Only run for V1 analysis): Relink the day pointer to the V1-aware day_setup

Run [relink_day_pointer_to_day_setup_7.m](analysis/longitudinal_stim_parameter_survey/relink_day_pointer_to_day_setup_7.m).

The day pointer/container built in step 3 stores a reference to the brain-mask-only `day_setup` from pre-step B. Once step 6 produces a new `day_setup` containing the V1 mask, this utility updates the day pointer's stored reference. Run once after step 6, before step 8.

After relinking, you can also run the V1-restricted version of step 4 (see above) to check baseline stability within V1.

### Step 8 (Optional / legacy — V1-restricted dF/F): cropping the computation to V1

> **Note — recommended workflow.** The pipeline now keeps dF/F on the whole-brain mask and shows V1 only as a boundary overlay at step 9 (see "V1 handling" under Step 9). You generally do **not** need to recompute dF/F restricted to V1. Step 8 is retained for backward compatibility and for cases where you specifically want the computation cropped to the V1 bounding box. For the standard analysis, run the whole-brain steps 5_B1 / 5_B2, then overlay the V1 boundary in step 9. You still need step 6 to produce the V1 boundary used by that overlay.

Step 8 mirrors step 5 but restricted to the V1 region. Run steps 6 and 7 first to make the V1 mask available via the day pointer.

#### Step 8_A (Method 0 — per-trial baseline, V1)

Run [current_thresholding_analysis_pixelwise_v1_8A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_v1_8A.m).

The V1-restricted counterpart of step 5_A. Crops to the V1 bounding box and computes per-trial-normalized dF/F for pixels inside `retino_align.V1_mask_stim`.

#### Step 8_B1 (Method 1, part 1 — compute V1 global baseline and std)

Run `compute_global_baseline_v1_8B1.m` *(script to be added)*.

Same as step 5_B1 but restricted to the V1 region: computes `F_global_v1(x,y)` and `std_dff_m1_v1(x,y)` from all 0 uA trials within the V1 mask. Saves `global_baseline_m1_v1.mat`. Run before step 8_B2 and step 9_B (V1 path).

#### Step 8_B2 (Method 1, part 2 — compute V1 dF/F with global baseline)

Run `compute_dff_method1_v1_8B2.m` *(script to be added)*.

The V1-restricted counterpart of step 5_B2. Computes dF/F using `F_global_v1` from step 8_B1, saving results under a `method1_v1/ch{N}_{I}uA/` subfolder structure.

### Step 9: Per-pixel significance thresholding

This step is required for all analysis paths. It applies a per-pixel significance threshold to a dF/F movie and produces thresholded visualizations. Three variants are available: 9_A and 9_B threshold a single (usually trial-averaged) movie; 9_C analyzes every trial of a condition individually and takes a cross-trial consensus.

**V1 handling (all of step 9).** dF/F is always computed on the whole-brain mask — the pipeline no longer crops or masks the computation to V1. When you want V1 context, point any step 9 script at a `day_setup` file that contains a V1 boundary (`retino_align.V1_mask_stim`, from step 6) when prompted, and the V1 outline is drawn on every figure and video as a green contour. The numerical result is unchanged; V1 is purely an overlay. The legacy V1-restricted dF/F scripts (steps 8_A / 8_B1 / 8_B2) are therefore optional — the recommended workflow is whole-brain dF/F (steps 5_B1 / 5_B2) with a V1 boundary overlay at step 9.

#### Step 9_A (Method 0 — within-trial pre-stim std threshold)

Run [dff_pixelwise_significance_threshold_9A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_9A.m).

Works on any dF/F movie from step 5_A or step 8_A. Computes the per-pixel significance threshold from the movie's own pre-stimulation frames (`t_s < 0`), prompts for an `n_std` multiplier (default 3), and produces thresholded output tagged with the chosen multiplier (e.g. `thresh_mean_dff_ch16_7uA_3σ`). Now also prompts (optionally) for a V1 boundary file to overlay.

#### Step 9_B (Method 1 — global std threshold)

Run [threshold_dff_method1_9B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_9B.m).

Works on dF/F movies from step 5_B2 (or the legacy 8_B2). Loads the precomputed `std_dff_m1` from step 5_B1 as the per-pixel threshold, derived from ~12,000 frames of 0 uA null-condition data rather than ~10 pre-stim frames. Also prompts (optionally) for a V1 boundary file to overlay.

#### Step 9_C (Method 1 — per-trial cross-trial consensus region)

Run [consensus_region_method1_9C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_9C.m) (interactive) or, for headless batching, [run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) driven by [run_9C_batch.py](run_9C_batch.py).

This is the per-trial counterpart of 9_A / 9_B. Instead of thresholding one averaged movie, it re-centers each trial by that trial's own pre-stim mean and thresholds at `n_std ×` the trial's own pre-stim std, then asks — at every timepoint — how many trials agree a pixel is active. See the dedicated section below for the exact definitions. You pick `n_std` (default 3) and a consensus count `min_trials` (default 25); pixels active in ≥ `min_trials` trials at a timepoint are consensus-active, and pixels consensus-active at any post-stim time form the stimulation-related region for that channel-current condition. Input is the per-trial Method 1 movies in a condition folder (`method1/ch{N}_{I}uA/`).

---

## What Each Step Is Doing

### Pre-step B — Draw brain boundary mask

[draw_brain_mask_0.m](analysis/retinotopic_mapping/draw_brain_mask_0.m)

- Averages a set of TIFF frames to build a clean reference image
- Lets the user draw a polygon over the brain area interactively
- Saves a `brain_mask.mat` containing `final_mask` (logical H×W)

### Step 1

[extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)

- Extracts stimulation and camera timing from the ephys recording
- Produces a timing file used for widefield/ephys alignment

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

Uses all 0 uA trials to model slow fluorescence drift through the session, independent of stimulation:

- Prompts for a day pointer, brain mask (or V1-aware day_setup for the V1 version), and output folder
- For each 0 uA trial (all channels pooled), loads the raw TIFF stack for the full trial window and reduces it to a single mean image — one H×W data point per trial; the full stack is discarded immediately after
- Uses the trial onset time `t_onset = (onset_frame − 1) / Fs` as the x-axis coordinate
- Fits `F(x,y) = slope·t_onset + intercept` per pixel in closed form from accumulated sufficient statistics; computes R² as `(Sxy_c)² / (Sxx_c · Syy_c)` without a second pass
- Saves `baseline_drift_4.mat` containing `slope_map` (H×W, ΔF/s), `intercept_map`, `r2_map`, trial onset times, and trial count
- Generates `baseline_drift_slope_r2.png`: slope map (bwr, centred at zero) and R² map (parula, [0, 1]) side by side
- Generates `baseline_drift_summary_scatter.png`: mean in-mask F per trial vs onset time with the fitted line (left), and residuals (right) to reveal nonlinear drift

If the slope map is flat and the summary scatter shows no trend, the session baseline is stable. If significant drift is present, consider drift correction or prefer Method 1 (F_global normalization) in steps 5/8.

Run twice if doing both whole-brain and V1 analysis: once after step 3 with the brain mask, and once after step 7 with the V1-aware day pointer.

### Step 5_A — Whole-brain pixelwise dF/F, Method 0 (per-trial baseline)

[current_thresholding_analysis_pixelwise_region_5A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_5A.m)

For each channel-current stimulation condition:

- Computes `dF/F(x,y,t) = [F(x,y,t) − F_baseline(x,y)] / F_baseline(x,y)` for every frame and pixel in the trial window, where `F_baseline(x,y)` is the mean pixel intensity over all pre-stimulation frames of that specific trial
- Saves the individual dF/F movie for every trial, named `dff_ch{N}_{I}uA_trial{K}` (e.g. `dff_ch1_1uA_trial1`, `dff_ch1_1uA_trial2`, …)
- Averages across all trials of each condition to produce a `mean_dff_movie` (H × W × T)
- Generates frame-grid figures showing the spatial dF/F map at each post-stimulation timepoint. Color limits are **autoscaled per figure/movie to that data's in-mask dF/F min/max** (no fixed clipping, so strong responses no longer saturate), rendered with a **jet** colormap. (This also applies to the Method 1 dF/F in step 5_B2.)
- Optionally exports per-trial and/or trial-averaged dF/F movies as `.mp4` videos (you choose which, via an interactive dialog). Pixels outside the brain mask are rendered as a single solid color rather than raw (NaN) noise, so the surrounding region doesn't flicker
- All outputs for a given channel-current condition are grouped into their own subfolder `save_dir/ch{N}_{I}uA/`

**Key difference from the previous approach:** the old pipeline collapsed dF/F to a single scalar per pixel per trial using a fixed response window (e.g. 0.4–0.6 s post-stim). The new approach preserves the full temporal trace so you can see how activation evolves over time without committing to a response window upfront.

### Step 5_B1 — Whole-brain global baseline and noise std from 0 uA trials (Method 1, part 1)

`compute_global_baseline_5B1.m` *(script to be added)*

Computes two per-pixel maps from all 0 uA trials using a one-pass sufficient-statistics accumulation over all raw TIFF frames:

- `F_global(x,y)` — grand mean raw fluorescence across all frames of all 0 uA trials; serves as a stable, session-wide baseline with ~12,000 data points per pixel rather than ~10
- `std_dff_m1(x,y)` — std of `(F − F_global) / F_global` across the same frames; serves as the per-pixel noise threshold for step 9_B, derived from an empirical null distribution

Saves `global_baseline_m1.mat`. Run once before step 5_B2 and step 9_B.

### Step 5_B2 — Whole-brain pixelwise dF/F, Method 1 (global baseline)

`compute_dff_method1_5B2.m` *(script to be added)*

Same looping structure as step 5_A but uses `F_global` from step 5_B1 as the common denominator for all trials and conditions:

- `dF/F(x,y,t) = [F(x,y,t) − F_global(x,y)] / F_global(x,y)`
- Saves per-trial and trial-averaged dF/F movies in the same format as step 5_A, under a `method1/ch{N}_{I}uA/` subfolder structure

### Step 6 — Retinotopic mapping and region labeling

[retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)

- Loads retinotopy output (azi, alt, VFS maps)
- Aligns the retinotopic map to the stimulation-day image using affine registration (manual cpselect or auto + nudge)
- Defines V1 and other visual area boundaries in stimulation-day pixel coordinates
- Saves a unified `day_setup` struct: `reference_mask_and_retino_alignment` including both the brain mask and the retinotopic alignment

Once this is done, the V1 boundary and retinotopic coordinates can be overlaid on step 5 dF/F outputs for region-specific interpretation, or used directly for V1-restricted analysis in steps 7–8.

### Step 7 — Relink day pointer to V1-aware day_setup

[relink_day_pointer_to_day_setup_7.m](analysis/longitudinal_stim_parameter_survey/relink_day_pointer_to_day_setup_7.m)

- Prompts for an existing day pointer/container and the new `day_setup.mat` produced by step 6
- Verifies the selected `day_setup` contains a non-empty `retino_align.V1_mask_stim`
- Updates the day pointer's stored `day_setup` reference and re-saves it

This is needed because the day pointer (built in step 3) stores a reference to whichever `day_setup` existed at that time — almost always the brain-mask-only version from pre-step B, since step 6 normally runs afterward. Without relinking, V1-aware scripts like step 8 and the V1-restricted drift analysis (second run of step 4) cannot find the V1 mask.

### Step 8_A — V1-restricted pixelwise dF/F, Method 0 (per-trial baseline)

[current_thresholding_analysis_pixelwise_v1_8A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_v1_8A.m)

The V1-restricted counterpart of step 5_A. For each channel-current stimulation condition:

- Loads the `day_setup` (via the relinked day pointer from step 7) and crops to the V1 bounding box
- Computes `dF/F(x,y,t)` for every frame, restricted to pixels inside `retino_align.V1_mask_stim` (pixels outside V1 are set to NaN)
- Saves per-trial movies (`v1_dff_ch{N}_{I}uA_trial{K}.mat`) and the trial-averaged movie (`v1_mean_dff_ch{N}_{I}uA.mat`)
- Generates frame-grid figures with both the V1 boundary (white) and the whole-brain boundary (gray) overlaid
- Optionally exports per-trial and/or mean dF/F videos with the same solid-color out-of-mask rendering as step 5_A
- All outputs for a given channel-current condition are grouped into their own subfolder `save_dir/v1_ch{N}_{I}uA/`

### Step 8_B1 — V1 global baseline and noise std (Method 1, part 1)

`compute_global_baseline_v1_8B1.m` *(script to be added)*

The V1-restricted counterpart of step 5_B1. Computes `F_global_v1(x,y)` and `std_dff_m1_v1(x,y)` from all 0 uA trials, restricted to the V1 pixel mask from the `day_setup`. Saves `global_baseline_m1_v1.mat`. Run before step 8_B2 and step 9_B when working with V1-restricted data.

### Step 8_B2 — V1-restricted pixelwise dF/F, Method 1 (global baseline)

`compute_dff_method1_v1_8B2.m` *(script to be added)*

The V1-restricted counterpart of step 5_B2. Computes dF/F using `F_global_v1` from step 8_B1, saving results under a `method1_v1/ch{N}_{I}uA/` subfolder structure.

### Step 9_A — Per-pixel significance thresholding, Method 0

[dff_pixelwise_significance_threshold_9A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_9A.m)

A generic, single-movie utility — works on any dF/F movie from step 5_A or step 8_A, whether a single trial or trial-averaged movie:

- Prompts for one dF/F movie `.mat` file
- Computes `std(x,y)` of each pixel's dF/F trace over the pre-stimulation baseline (`t_s < 0`), ignoring NaNs; prompts for an `n_std` multiplier (default 3). For roughly-Gaussian baseline noise, `±1·std` is crossed by chance on ~32% of baseline samples, `±2·std` by ~5%, and `±3·std` by only ~0.3%
- Builds a thresholded movie rendering: always-NaN (out-of-mask) pixels in one solid color; in-mask sub-threshold pixels in a second solid color; suprathreshold pixels (`|dF/F(x,y,t)| > n_std·std(x,y)`) with their true dF/F value
- Saves the thresholded movie + per-pixel std map as `.mat`, tagged with the chosen multiplier (e.g. `thresh_mean_dff_ch16_7uA_3σ.mat`)
- Generates a frame-grid figure and optionally exports the movie as `.mp4`
- Opens an interactive time-slider viewer plus a static peak-response map; lets you click pixels to generate individual `dF/F(t)` plots with the `±n_std·std` band shown
- Optionally prompts for a `day_setup` with a V1 boundary; when given, the V1 outline is drawn (green) on the frame grid, video, and viewer. The threshold and computation are unchanged — V1 is overlay-only. The overlay is skipped automatically if the V1 mask size does not match the movie (e.g. a V1-cropped movie)

### Step 9_B — Per-pixel significance thresholding, Method 1

[threshold_dff_method1_9B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_9B.m)

Works on dF/F movies from step 5_B2 (or the legacy 8_B2). Identical output and interactive interface to step 9_A, but the per-pixel significance threshold is loaded from `global_baseline_m1.mat` (step 5_B1) rather than computed from the movie's own pre-stim frames. This gives a threshold derived from ~12,000 frames of null-condition data per pixel, making it far more robust than the ~10-frame within-trial estimate used in step 9_A. Like 9_A, it now also offers an optional V1 boundary overlay.

### Step 9_C — Per-trial cross-trial consensus region, Method 1

[consensus_region_method1_9C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_9C.m) — interactive
[run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) — headless batch, driven by [run_9C_batch.py](run_9C_batch.py)

Where 9_A and 9_B threshold a single movie (typically the trial average), step 9_C analyzes **every trial of a channel-current condition individually** and combines them by per-timepoint voting. It consumes the per-trial Method 1 movies in one condition folder (`method1/ch{N}_{I}uA/dff_m1_*_trial*.mat` from step 5_B2).

**dF/F and the per-trial baseline.** dF/F still uses the Method 1 global baseline:

```
dF/F(x,y,t) = [F(x,y,t) − F_global(x,y)] / F_global(x,y)
```

For each trial, `baseline_dF/F(x,y)` is defined as that trial's own pre-stim mean of `dF/F(x,y,t)` (mean over `t_s < 0`). Rather than thresholding `|dF/F(x,y,t)|`, step 9_C thresholds the per-trial-baseline-corrected value:

```
| dF/F(x,y,t) − baseline_dF/F(x,y) |  >  n_std × σ_pre(x,y)
```

where `σ_pre(x,y)` is the std of that trial's pre-stim `dF/F(x,y,t)` and `n_std` is user-chosen (default 3). Because the band is centered on the pre-stim mean, `σ_pre` is exactly the std of the baseline-corrected pre-stim trace.

**Cross-trial consensus (per timepoint).** Each trial yields a logical activation map `active(x,y,t)`. For every timepoint `t` (the full window, e.g. −0.9 to +2.6 s), the script counts how many of the N trials flag each pixel as active. A pixel is **consensus-active at time t** when that count `≥ min_trials` (default 25, user-changeable, e.g. 25 of 30). The **stimulation-related region** for the condition is the set of pixels that are consensus-active at one or more post-stim timepoints (`t_s ≥ 0`).

Outputs (per `n_std` × `min_trials` combination), written with the tag `consensus_<cond>_<n>σ_min<M>of<N>_m1`:

- `…​.mat` — `count_activated_u16` and `count_suppressed_u16` (H×W×T direction-split trial counts), `consensus` (H×W×T logical), `region_mask` and `region_signed` (H×W), `n_std`, `min_trials`, `n_used`, `t_s`, `always_nan_mask`, `V1_mask`
- `…_frame_grid.png` — signed net-count map (net = activated − suppressed) on a rainbow (jet) scale over [−N, +N] at selected timepoints in t ∈ [−0.2, 1.2] s: red = activated, green ≈ no/balanced consensus, blue = suppressed; with the magenta consensus contour, brain outline, and optional V1 outline
- `…_region.png` — the stimulation-related region next to the peak-consensus frame (same rainbow/contour rendering)
- `…_summary.txt` — region pixel count (split into activated vs suppressed), peak timepoint, peak consensus pixel count, settings
- `…_m1.mp4` — optional signed net-count movie
- Interactive viewer (single-condition script): time slider over the net-count movie + static region map; click pixels to plot their activated (up) and suppressed (down) trial counts over time, with the `min_trials` cutoff lines

Like 9_A/9_B, it accepts an optional V1 boundary overlay (whole-brain result; V1 drawn only as a contour). The batch runner sweeps lists of `n_std` and `min_trials`, computing the per-trial pass once per `n_std` and reusing it across `min_trials` values.

> Note: the current 9_C scores activation **directionally** — it keeps separate `count_activated` (`corrected > n_std·σ_pre`) and `count_suppressed` (`corrected < −n_std·σ_pre`) tallies, and a pixel reaches consensus only if it is driven the *same* way in `≥ min_trials` trials (a mixed up/down split is treated as noise). Maps are colored by the signed net count `activated − suppressed` on a rainbow scale (red = activated, green ≈ neutral, blue = suppressed), and the saved `.mat` carries `count_activated_u16` / `count_suppressed_u16`.

### Step 9_D — Time-window consensus region, Method 1 (latency-robust 9_C)

[consensus_region_window_method1_9D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_9D.m) — interactive
[run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) — headless batch, driven by [run_9D_batch.py](run_9D_batch.py)

Step 9_D is identical to 9_C in every respect — directional consensus, `min_trials`, signed rainbow net-count maps, magenta consensus contour, optional V1 overlay — with one change to the per-trial activation rule. A pixel counts as activated/suppressed at time `t` in a trial if it crosses threshold **anywhere in the window `[t − window_s, t + window_s]`** (default `window_s = 0.1 s`; at a 10 Hz frame rate that is ±1 frame), instead of only in the single frame `t`:

```
activated at t   ⟺   dF/F(x,y,τ) − baseline_dF/F(x,y) >  n_std·σ_pre(x,y)   for some τ ∈ [t−window_s, t+window_s]
suppressed at t  ⟺   dF/F(x,y,τ) − baseline_dF/F(x,y) < −n_std·σ_pre(x,y)   for some τ ∈ [t−window_s, t+window_s]
```

Because trials respond with slightly different latencies, the strict single-frame 9_C can lose cross-trial agreement when the response lands a frame early or late; the window absorbs that jitter. Implemented as a temporal max-dilation of the per-trial activation maps by `window_frames = round(window_s / dt)` before counting. Output filenames carry a `win{window_s}s` tag; the interactive setting is `window_s` and the batch argument / driver constant is `WINDOW_S` (default 0.1). In practice 9_D recovers substantially more consensus than 9_C at the same `n_std`. Use 9_D when latency jitter matters; use 9_C for the strictest same-frame agreement.

---

#