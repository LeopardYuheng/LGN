# Longitudinal Widefield Pipeline

This folder contains the current longitudinal widefield stimulation pipeline.
The canonical workflow is the five numbered scripts below.

The `legacy code` folder is exploratory or archival code and should not be treated as the current pipeline unless you are explicitly reproducing an older analysis.

## Recommended Run Order

1. [1_extract_nev_stim_and_camera.m](//Luan_lab_retinomap-pipeline/analysis/longitudinal/1_extract_nev_stim_and_camera.m)
2. [2_align_wf_with_nev_extracted.m](//Luan_lab_retinomap-pipeline/analysis/longitudinal/2_align_wf_with_nev_extracted.m)
3. [3_make_container_ripple.m](//Luan_lab_retinomap-pipeline/analysis/longitudinal/3_make_container_ripple.m)
4. [4_current_thresholding_analysis_pixelwise_region.m](//Luan_lab_retinomap-pipeline/analysis/longitudinal/4_current_thresholding_analysis_pixelwise_region.m)
5. [5_compare_pixelwise_activation_across_sessions.m](//Luan_lab_retinomap-pipeline/analysis/longitudinal/5_compare_pixelwise_activation_across_sessions.m)

## Script Summary

### 1. Extract Ripple timing and camera triggers

Script: [1_extract_nev_stim_and_camera.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/1_extract_nev_stim_and_camera.m)

Purpose:
Reads a Ripple `.nev` file and extracts the timing streams needed for later widefield alignment, including camera TTLs and stimulation-related digital inputs.

Main inputs:
- Ripple `.nev` file
- User-entered session metadata
- Output folder for the saved timing `.mat`

Main output:
- Session timing `.mat` containing the extracted Ripple timing structure

Notes:
- This is the first step in the pipeline.
- It does not use TIFF data or compute imaging responses.

### 2. Align widefield frames to extracted stimulation timing

 Script: [2_align_wf_with_nev_extracted.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/2_align_wf_with_nev_extracted.m)

Purpose:
Combines TIFF frame timing, Ripple timing, the retinotopy/reference-mask setup file, and the stimulation CSV into a single trial-alignment structure.

Main inputs:
- TIFF image folder
- `{subject}_{date}_reference_mask_and_retino_alignment.mat`
- `{subject}_{date}_ripple_timing.mat`
- CSV with `trial_index`, `stim_chan`, and `current_uA`

Main output:
- `analysis/{subject}_{date}_wf_trial_alignment.mat`

Notes:
- This step performs bookkeeping and alignment only.
- It does not compute trialwise `dF/F` maps or significance maps.

### 3. Build the day pointer container

Script: [3_make_container_ripple.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/3_make_container_ripple.m)

Purpose:
Converts the widefield trial-alignment file into a compact day pointer container used by downstream analysis scripts.

Main inputs:
- `{subject}_{date}_wf_trial_alignment.mat`
- Analysis window settings such as `pre_sec` and `post_sec`

Main output:
- `{subject}_{date}_day_pointer.mat`

Notes:
- The day pointer groups trials by stimulation channel and current.
- Downstream scripts expect either `day_pointer` or the legacy variable name `C`.
- In the current script, some paths are still hard-coded and should be checked before reuse on a new dataset or machine.

### 4. Compute single-session pixelwise activation thresholds

Script: [4_current_thresholding_analysis_pixelwise_region.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/4_current_thresholding_analysis_pixelwise_region.m)

Purpose:
Runs the main single-session pixelwise activation analysis. For each channel and current, it computes mean evoked `dF/F`, compares stimulation trials against `0 uA` baseline trials, finds significant clusters, applies a consistency filter, and determines the threshold current for that channel.

Main inputs:
- A day pointer `.mat`
- TIFF frames referenced by the day pointer
- The associated day setup file containing `final_mask`, `V1_mask_stim`, and retinotopy maps

Main outputs:
- `pixelwise_threshold_region_results.mat`
- `pixelwise_activation_consistency_summary.csv`
- Per-channel summary figures and aggregate activation summary figures

Notes:
- This is the main script for within-session threshold analysis.
- The primary user-adjustable parameters are near the top of the script.
- The analysis region is currently `final_mask & V1_mask`.

### 5. Compare pixelwise activations across sessions

Script: [5_compare_pixelwise_activation_across_sessions.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/5_compare_pixelwise_activation_across_sessions.m)

Purpose:
Runs the same core pixelwise activation logic across multiple day pointers, then matches the same channel-current conditions across sessions and quantifies reproducibility.

Main inputs:
- Two or more day pointer `.mat` files
- TIFF frames and day setup files referenced by those day pointers

Main outputs:
- `multi_session_activation_comparison.mat`
- `session_condition_summary.csv`
- `significant_session_conditions.csv`
- `conditions_significant_across_days.csv`
- `pairwise_condition_comparison.csv`
- `all_days_condition_overlap_summary.csv`
- Pairwise overlap figures and all-days overlap figures

Notes:
- This is the main multi-session comparison script.
- It computes overlap and similarity metrics such as Dice, IoU, centroid distance, peak distance, and pixelwise correlation.
- It includes options for `analysis_region_mode` and simple session registration using final-mask centroid translation.

## Data Flow

`1_extract_nev_stim_and_camera.m`
produces Ripple timing metadata.

`2_align_wf_with_nev_extracted.m`
combines that timing with TIFFs, masks, and the stimulation CSV to build trial alignment.

`3_make_container_ripple.m`
turns the trial alignment into a reusable day pointer container.

`4_current_thresholding_analysis_pixelwise_region.m`
uses one day pointer to measure within-session thresholds and activation regions.

`5_compare_pixelwise_activation_across_sessions.m`
uses multiple day pointers to compare matched activation maps across days.

## Important Structures

`day_setup`
- Contains the reference mask and retinotopy alignment outputs.
- Important fields used downstream include `reference_mask.final_mask` and `retino_align.V1_mask_stim`.

`wf_trial_alignment`
- Produced by step 2.
- Stores TIFF/frame alignment, stimulation bookkeeping, and trial timing information.

`day_pointer`
- Produced by step 3.
- Stores dataset-relative paths, analysis timing configuration, and grouped trial entries for downstream analysis.

## Practical Handoff Notes

- Start with the numbered scripts in this folder.
- Treat `legacy code` as archival unless there is a specific reason to revisit an older analysis.
- Treat `latency_and_baseline_scripts` as downstream helper analyses rather than part of the core five-step pipeline.
- Before rerunning on a new machine or dataset, review hard-coded paths in [3_make_container_ripple.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/3_make_container_ripple.m) and any `addpath(...)` usage in [1_extract_nev_stim_and_camera.m](/ /Luan_lab_retinomap-pipeline/analysis/longitudinal/1_extract_nev_stim_and_camera.m).
