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
- retinotopy outputs (applied at the end, after dF/F analysis)

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

This script loads a reference image averaged from the stimulation-day TIFFs and lets you draw a polygon around the brain (to exclude scalp, skull edges, and artifacts). It saves a `brain_mask.mat` file that is used by step 4 to restrict analysis to in-brain pixels.

This is a lightweight script derived from `reference_mask_and_retino_alignment.m`. It does **not** require retinotopy data and does **not** draw any V1 boundary — it only defines what is brain vs. non-brain in the image.

### Steps 1–3: Electrophysiology and widefield alignment

Run in numbered order:

1. [extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)
2. [align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)
3. [make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

### Step 4: Compute pixelwise dF/F(x,y,t) movies

Run [current_thresholding_analysis_pixelwise_region_4.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_4.m).

This step computes the full time-varying dF/F trace for every pixel, for every channel-current stimulation condition. It does **not** require retinotopic mapping or a V1 boundary — only the brain boundary mask from pre-step B.

### Step 5: Retinotopic mapping and region labeling

Run [reference_mask_and_retino_alignment.m](analysis/retinotopic_mapping/reference_mask_and_retino_alignment.m).

After inspecting the dF/F results, this step aligns the retinotopic map to the stimulation-day image and labels which pixels belong to V1 and other visual areas. It saves a new `day_setup` file containing both the brain mask and the retinotopic alignment (including `retino_align.V1_mask_stim`).

This step is intentionally placed after step 4: you do not need to commit to a V1 boundary before you have seen the dF/F activation patterns.

### Step 6 (Optional): Relink the day pointer to the V1-aware day_setup

Run [relink_day_pointer_to_day_setup_6.m](analysis/longitudinal_stim_parameter_survey/relink_day_pointer_to_day_setup_6.m).

The day pointer/container built in step 3 stores a reference to whichever `day_setup` file existed at that time (typically the brain-mask-only `day_setup` from pre-step B, since step 5 normally hasn't run yet). Once step 5 produces a *new* `day_setup` file containing the V1 mask, the day pointer's stored reference is stale and does not point at it.

This one-off utility:

- Prompts you to select an existing `day_pointer.mat`
- Prompts you to select the new `day_setup.mat` produced by step 5 (and verifies it contains a non-empty `retino_align.V1_mask_stim`)
- Updates the day pointer's stored `day_setup` reference and re-saves the container

Run this once after step 5, before running step 7 (or any other V1-aware script) on data whose day pointer was created before step 5.

### Step 7 (Optional): V1-restricted pixelwise dF/F analysis

Run [current_thresholding_analysis_pixelwise_v1_7.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_v1_7.m).

This is the V1-restricted counterpart of step 4. Instead of analyzing the whole brain mask, it crops to the V1 bounding box and computes dF/F only for pixels inside the V1 boundary (`retino_align.V1_mask_stim` from the `day_setup` saved in step 5). It requires a day pointer that already points at a V1-aware `day_setup` — run step 6 first if needed.

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

### Step 4

[current_thresholding_analysis_pixelwise_region_4.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_4.m)

For each channel-current stimulation condition:

- Computes `dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)` for every frame and pixel in the trial window, where `F_baseline(x,y)` is the mean pixel intensity over all pre-stimulation frames of that trial
- Saves the individual dF/F movie for every trial, named `dff_ch{N}_{I}uA_trial{K}` (e.g. `dff_ch1_1uA_trial1`, `dff_ch1_1uA_trial2`, …)
- Averages across all trials of each condition to produce a `mean_dff_movie` (H × W × T)
- Generates frame-grid figures showing the spatial dF/F map at each post-stimulation timepoint
- Optionally exports per-trial and/or trial-averaged dF/F movies as `.mp4` videos (you choose which, via an interactive dialog). Pixels outside the brain mask are rendered as a single solid color rather than raw (NaN) noise, so the surrounding region doesn't flicker

**Key difference from the previous approach:** the old pipeline collapsed dF/F to a single scalar per pixel per trial using a fixed response window (e.g. 0.4–0.6 s post-stim). The new approach preserves the full temporal trace so you can see how activation evolves over time without committing to a response window upfront.

### Step 5 — Retinotopic mapping and region labeling

[reference_mask_and_retino_alignment.m](analysis/retinotopic_mapping/reference_mask_and_retino_alignment.m)

- Loads retinotopy output (azi, alt, VFS maps)
- Aligns the retinotopic map to the stimulation-day image using affine registration (manual cpselect or auto + nudge)
- Defines V1 and other visual area boundaries in stimulation-day pixel coordinates
- Saves a unified `day_setup` struct including both the brain mask and the retinotopic alignment

Once this is done, the V1 boundary and retinotopic coordinates can be overlaid on the step 4 dF/F movie outputs for region-specific interpretation, or used directly for V1-restricted analysis (steps 6–7 below).

### Step 6 — Relink day pointer to V1-aware day_setup

[relink_day_pointer_to_day_setup_6.m](analysis/longitudinal_stim_parameter_survey/relink_day_pointer_to_day_setup_6.m)

- Prompts for an existing day pointer/container and the new `day_setup.mat` produced by step 5
- Verifies the selected `day_setup` contains a non-empty `retino_align.V1_mask_stim`
- Updates the day pointer's stored `day_setup` reference and re-saves it

This is needed because the day pointer (built in step 3) stores a reference to whichever `day_setup` existed at that time — almost always the brain-mask-only version from pre-step B, since step 5 normally runs afterward. Without relinking, V1-aware scripts like step 7 cannot find the V1 mask.

### Step 7 — V1-restricted pixelwise dF/F analysis

[current_thresholding_analysis_pixelwise_v1_7.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_v1_7.m)

The V1-restricted counterpart of step 4. For each channel-current stimulation condition:

- Loads the `day_setup` (via the day pointer's, now-relinked, reference) and crops to the V1 bounding box
- Computes `dF/F(x,y,t)` for every frame, restricted to pixels inside `retino_align.V1_mask_stim` (pixels outside V1 are set to NaN)
- Saves per-trial movies (`v1_dff_ch{N}_{I}uA_trial{K}.mat`) and the trial-averaged movie (`v1_mean_dff_ch{N}_{I}uA.mat`)
- Generates frame-grid figures with both the V1 boundary (white) and the whole-brain boundary (gray) overlaid
- Optionally exports per-trial and/or mean dF/F videos (`v1_mean_dff_ch{N}_{I}uA.mp4`, etc.) with the same solid-color out-of-mask rendering as step 4

Run step 6 first if the day pointer was created before step 5 produced the V1-aware `day_setup`.

## Important Path Behavior

Several scripts save structures that contain file paths or relative file references. These saved outputs are then reused by later scripts.

That means:

- choose the correct folders when prompted
- make sure the experiment data is already in its final home
- avoid reorganizing the dataset midway through analysis

If you need to reorganize data, do it before running the pipeline, not after.

## Practical Rule

Once the experiment data is in place and you start running the pipeline, treat the folder locations as fixed.
