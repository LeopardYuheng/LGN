# LGN Widefield Pipeline — New Workflow (Required Steps Only)

This is the streamlined run order for the **current** pipeline. It lists only
the steps you need to run. Two decisions are already made for you:

- **dF/F uses Method 1** (global-baseline normalization). Always run the
  **5_B** branch — never 5_A.
- **dF/F is computed on the whole-brain mask; V1 is only a plot overlay.**
  There is no V1-restricted dF/F computation, so **step 8 is skipped**. Step 6
  is still required, because it produces the V1 boundary that step 9 overlays.

Keep the data in its final location before starting — later scripts reload
saved paths and will break if files move.

---

## Run Order

### Pre-step A — Combine retinotopy inputs *(only if needed)*

[retino_inputcombine.m](analysis/longitudinal_stim_parameter_survey/retino_inputcombine.m)

Run only if `azi.mat`, `alt.mat`, and `additional_maps.mat` were saved
separately. Produces the single retinotopy input file that step 6 needs.

### Pre-step B — Draw brain boundary mask *(required)*

[draw_brain_mask_0.m](analysis/longitudinal_stim_parameter_survey/draw_brain_mask_0.m)

Draw the brain polygon and save `brain_mask.mat`. This mask defines in-brain
pixels for every downstream step.

### Step 1 — Extract Ripple stim & camera timing *(required)*

[extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)

### Step 2 — Align widefield frames to stim timing *(required)*

[align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)

### Step 3 — Build the day pointer container *(required)*

[make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

Produces the day pointer that steps 4–9 load.

### Step 4 — Baseline drift check *(recommended QC, optional)*

[baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m)

A sanity check on raw-fluorescence stability. Method 1 already normalizes by a
session-wide `F_global`, so this step is not required to produce results — run
it once if you want to confirm the baseline before trusting the dF/F.

### Step 5_B1 — Global baseline & noise std *(required)*

[compute_global_baseline_5B1.m](analysis/longitudinal_stim_parameter_survey/compute_global_baseline_5B1.m)

From all 0 µA trials, computes `F_global(x,y)` (the common dF/F denominator)
and `std_dff_m1(x,y)` (the step 9_B threshold). Saves `global_baseline_m1.mat`.
Run before 5_B2.

### Step 5_B2 — Whole-brain dF/F movies (Method 1) *(required)*

[compute_dff_method1_5B2.m](analysis/longitudinal_stim_parameter_survey/compute_dff_method1_5B2.m)

`dF/F(x,y,t) = [F(x,y,t) − F_global(x,y)] / F_global(x,y)` for every trial and
condition. Saves per-trial movies `dff_m1_ch{N}_{I}uA_trial{K}.mat` and the
trial average under `method1/ch{N}_{I}uA/`. These per-trial movies are the
input to step 9_C.

### Step 6 — Retinotopic mapping (V1 boundary) *(required)*

[retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)

Required because step 9 draws the V1 boundary as an overlay. This produces the
`day_setup` (`..._reference_mask_and_retino_alignment.mat`) containing
`retino_align.V1_mask_stim`. You will select this file when prompted in step 9.

> **Skip step 7 and step 8.** Step 7 (relink day pointer) and step 8
> (V1-restricted dF/F) belong to the legacy V1-cropping path. The new pipeline
> keeps the computation whole-brain and only overlays the V1 boundary, so they
> are not needed.

### Step 9 — Significance thresholding & stimulation region *(required)*

In every step 9 script, when prompted for an optional V1 boundary, select the
`day_setup` file from step 6. dF/F results are unchanged; the V1 outline is
drawn (green) on the figures only.

**Step 9_C — per-trial signed consensus region (the main analysis):**

[consensus_region_method1_9C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_9C.m) (interactive)
or [run_9C_batch.py](run_9C_batch.py) → [run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) (batch)

Point it at one condition folder of per-trial movies from step 5_B2
(`method1/ch{N}_{I}uA/`). For each trial it re-centers `dF/F` by that trial's
own pre-stim mean (`baseline_dF/F`) and scores each pixel **directionally** at
time *t*:

- **activated**  when `dF/F(x,y,t) − baseline_dF/F(x,y) >  n_std · σ_pre(x,y)`
- **suppressed** when `dF/F(x,y,t) − baseline_dF/F(x,y) < −n_std · σ_pre(x,y)`

(`n_std` default 3, `σ_pre` = that trial's pre-stim std.) The two directions
are counted separately. A pixel is **consensus-active at time *t*** only if it
agrees in *one* direction — activated in ≥ `min_trials` trials, **or**
suppressed in ≥ `min_trials` trials (default 25, you can change it). A pixel
that is activated in some trials and suppressed in others (e.g. 15/15) is
treated as noise and is **not** consensus. Pixels reaching consensus at any
post-stim time form the stimulation-related region for that channel & current.

Maps are colored by the net count (`activated − suppressed`) on a **rainbow
(jet) scale** spanning `[−N, +N]`: red = activated, green ≈ no/balanced
consensus, blue = suppressed (the rainbow sweep makes magnitude easy to read).
A **magenta contour** outlines the consensus pixels on each panel — the
consensus pixels per frame in the frame grid, the region boundary on the
left region panel, and the peak-frame consensus on the right. The frame grid
shows frames in **t ∈ [−0.2, 1.2] s**.
Outputs per (condition, `n_std`): consensus `.mat` (`count_activated_u16`,
`count_suppressed_u16`, `consensus`, `region_mask`, `region_signed`), the
signed net-count frame grid, region/peak figures, a summary `.txt` (region
split into activated vs suppressed), and an optional MP4.

Batch notes: `run_9C_batch.py` sweeps `N_STD_LIST` and `MIN_TRIALS_LIST`,
writes each `n_std` to its own folder (`ch{N}_{I}uA_{n}sigma/`), and always
overlays the V1 boundary from the `day_setup` set in `V1_SOURCE_FILE`.

**Step 9_D — time-window consensus region *(latency-robust variant of 9_C)*:**

[consensus_region_window_method1_9D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_9D.m) (interactive)
or [run_9D_batch.py](run_9D_batch.py) → [run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) (batch)

Identical to 9_C, except a pixel counts as activated/suppressed at time *t* in a
trial if it crosses threshold **anywhere in the window [t − window_s, t + window_s]**
(default `window_s = 0.1 s`; at 10 Hz that is ±1 frame), rather than only in the
single frame *t*. Because individual trials respond with slightly different
latencies, the strict single-frame 9_C can lose the cross-trial agreement; the
window absorbs that jitter so a response that lands one frame early or late
still counts. Everything else — directional consensus, `min_trials`, rainbow
net-count maps, magenta contour, V1 overlay, outputs — is the same as 9_C. The
window half-width is the `window_s` setting (interactive) / `WINDOW_S` (batch),
and output filenames carry a `win{window_s}s` tag. In practice 9_D recovers
substantially more consensus than 9_C at the same `n_std` (e.g. on LGN11 the
mean region at 3σ was ~2,500 px vs ~360 px for 9_C). Use 9_D when trial latency
jitter is a concern; use 9_C for the strictest same-frame agreement.

**Step 9_B — single-movie threshold *(optional)*:**

[threshold_dff_method1_9B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_9B.m)

Run only if you also want a thresholded view of a single (usually
trial-averaged) movie, using the global `std_dff_m1` from step 5_B1. Not
required for the consensus region.

---

## Quick Checklist

```
Pre-B  draw_brain_mask_0            (required)
1      extract_nev_stim_and_camera  (required)
2      align_wf_with_nev_extracted  (required)
3      make_container_ripple        (required)
4      baseline_drift_analysis      (optional QC)
5_B1   compute_global_baseline      (required)
5_B2   compute_dff_method1          (required)
6      retino_alignment_with_brain_mask  (required — gives V1 boundary)
9_C    consensus_region_method1         (required — stimulation region, strict same-frame)
9_D    consensus_region_window_method1  (recommended — latency-robust, ±0.1s time window)
9_B    threshold_dff_method1            (optional)
```

Skip 5_A, 7, and 8 — they belong to the older Method 0 / V1-cropping path.
