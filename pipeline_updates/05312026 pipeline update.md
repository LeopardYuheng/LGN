# Pipeline Update — 05/31/2026

## Overview

Major reorganization of the widefield imaging analysis pipeline. The core change is decoupling the dF/F computation from retinotopic mapping: dF/F is now computed across the whole brain first, and V1 labeling is applied afterward once you have seen the data. The dF/F method itself was also changed from a scalar response-window approach to a full time-varying movie.

---

## New Files Added

### `analysis/retinotopic_mapping/draw_brain_mask_0.m` — Pre-step B

A new lightweight script that draws only the brain boundary mask, with no retinotopy required.

- Averages TIFF frames into a reference image
- User draws a circle around the brain and optional exclusion polygons (e.g. electrode shank shadows)
- Interactive redo loop with verification figure
- Saves `{subject}_{date}_brain_mask.mat` containing `reference_mask_struct` and `final_mask`

### `analysis/retinotopic_mapping/retino_alignment_with_brain_mask.m` — Step 5

New step 5 script that performs retinotopic alignment and V1 labeling. Replaces the combined mask+retino script for the new pipeline order.

- Loads `brain_mask.mat` from pre-step B instead of redrawing the brain boundary
- Performs full retinotopic alignment (manual cpselect affine or auto + nudge GUI)
- Defines V1 boundary on the retinotopic reference image; reuses saved V1 mask across sessions
- Saves `{subject}_{date}_day_setup.mat` in the same format as before (fully backward-compatible)

---

## Pipeline Order Change

| Old order | New order |
|-----------|-----------|
| 1. `reference_mask_and_retino_alignment.m` | **Pre-B.** `draw_brain_mask_0.m` (brain mask only) |
| 2. `extract_nev_stim_and_camera_1.m` | 1. `extract_nev_stim_and_camera_1.m` *(unchanged)* |
| 3. `align_wf_with_nev_extracted_2.m` | 2. `align_wf_with_nev_extracted_2.m` *(minor changes)* |
| 4. `make_container_ripple_3.m` | 3. `make_container_ripple_3.m` *(minor changes)* |
| 5. `current_thresholding_analysis_pixelwise_region_4.m` | 4. `current_thresholding_analysis_pixelwise_region_4.m` *(rewritten)* |
| — | **5.** `retino_alignment_with_brain_mask.m` (V1 labeling, after seeing dF/F) |

**Rationale:** The old pipeline required drawing a V1 boundary before any dF/F had been computed, which meant committing to a region of interest blind. The new pipeline computes dF/F across the whole brain first, then applies V1 labeling afterward once the activation patterns are visible.

---

## Changes to Existing Scripts

### Step 2 — `align_wf_with_nev_extracted_2.m`

- Now accepts **either** `brain_mask.mat` (new format) or the old `day_setup.mat` — dialog prompt updated accordingly
- Retino alignment fields are **optional**: if the input file has no retino data, `out.retino_align` is stored as an empty struct instead of crashing
- Retino sanity checks guarded so they only run when retino data is present

### Step 3 — `make_container_ripple_3.m`

- **All hardcoded paths removed** — `wf_trial_alignment.mat` is now selected via `uigetfile`
- **`dataset_root` removed** — all paths stored as absolute rather than relative, so data on a network server and local analysis results work correctly without a shared root folder
- The hard assertion that `day_setup_file` must exist changed to a **warning**, so step 3 runs correctly before retinotopic alignment has been done

### Step 4 — `current_thresholding_analysis_pixelwise_region_4.m` (full rewrite)

#### Removed

- All threshold and cluster significance analysis
- V1 mask dependency (`analysis_mask = final_mask & V1_mask`) — step 4 no longer needs retino to have been run
- Retinotopy fields (azi, alt, VFS)
- Fixed response-window scalar dF/F (the old 0.4–0.6 s average per pixel per trial)

#### Added

- Loads `brain_mask.mat` directly — only the brain boundary is needed, not V1
- **Interactive condition selector** — lists all (channel, current) pairs found in the day pointer via a `listdlg` dialog; user selects which conditions to analyze before anything runs
- **Full time-varying dF/F(x,y,t)**:

  ```
  dF/F(x,y,t) = [F(x,y,t) - F_baseline(x,y)] / F_baseline(x,y)
  ```

  where `F_baseline(x,y)` = mean pixel intensity over all pre-stimulus frames of that trial

- **Individual trial movies** saved as `dff_ch{N}_{I}uA_trial{K}.mat` (H × W × T array with `t_s`). The pre-stimulus portion is `dff_movie(:,:, t_s < 0)` — no separate file needed.
- **Trial-averaged mean movie** saved as `mean_dff_ch{N}_{I}uA.mat` (same format, outside-brain pixels set to NaN)
- **Summary file** `dff_results_summary.mat` with the full `results` struct, `final_mask`, `t_s`, `baseline_idx`, `Fs`
- **Frame-grid figures** using a blue-white-red diverging colormap; color limits auto-scaled from the 1st/99th percentile of the data; shows pre-stim frames (t = −0.9, −0.6, −0.3 s) followed by post-stim frames (t = 0, 0.3, 0.6, … s)
- Fixed output folder: `C:\Projects\LGN_project\wide field analysis result\LGN11_20260326_experiment\analysis\dff_movies`

---

## Output File Reference (Step 4)

| File | Contents |
|------|----------|
| `dff_ch{N}_{I}uA_trial{K}.mat` | `dff_movie` (H×W×T), `t_s` |
| `mean_dff_ch{N}_{I}uA.mat` | `mean_dff_movie` (H×W×T, NaN outside brain), `t_s`, `final_mask` |
| `mean_dff_ch{N}_{I}uA_frame_grid.png` | Frame grid figure |
| `dff_results_summary.mat` | `results` struct, `final_mask`, `t_s`, `baseline_idx`, `Fs`, `pre_sec`, `post_sec` |

To extract the pre-stimulus portion from any saved file: `dff_movie(:,:, t_s < 0)`

---

## Key User Settings in Step 4

| Setting | Default | Description |
|---------|---------|-------------|
| `save_dir` | local analysis folder | Output folder for all .mat files and figures |
| `display_step_s` | `0.3` | Spacing between subplots in the frame-grid figure (seconds) |
| `n_prestim_display` | `3` | Number of pre-stim subplots shown (at `display_step_s` intervals before t=0) |
| `use_auto_clim` | `true` | Auto-scale color limits from data; set `false` to use `manual_clim` |
| `manual_clim` | `[-0.02 0.02]` | Fixed color limits used when `use_auto_clim = false` |
