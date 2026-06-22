# LGN Widefield Pipeline — Run Order

This is the streamlined run order for the **current** pipeline. Two decisions
are already made for you:

- **dF/F uses Method 1** (drift-corrected global baseline). Always run **Step 5_B**.
- **dF/F is computed on the whole-brain mask; V1 is a plot overlay only.**
  Steps 7 (relink day pointer) and 8 (V1-restricted dF/F) are legacy and no
  longer used. Step 6 is still required because it produces the V1 boundary
  that step 7_C / 7_D draw as a contour.

Keep data in its final location before starting — later scripts reload saved
paths and will break if files move.

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

Produces the day pointer that steps 4–7 load.

### Step 4 — Baseline drift analysis *(required)*

[baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m)

Fits a per-pixel linear model `F(x,y) = slope·t + intercept` across all 0 µA
trials (session-clock time). Saves `baseline_drift_4.mat` with `slope_map` and
`intercept_map`, which step 5_B uses directly to build a drift-corrected
per-trial baseline. Also produces diagnostic figures (slope map, R² map,
mean-F scatter).

### Step 5_B — Whole-brain dF/F movies (Method 1) *(required)*

[compute_dff_method1_5B.m](analysis/longitudinal_stim_parameter_survey/compute_dff_method1_5B.m)

Loads `slope_map` and `intercept_map` directly from `baseline_drift_4.mat`.
For each trial with session-clock onset `t_session`:
```
F_baseline(x,y) = intercept_map(x,y) + slope_map(x,y) · t_session
dF/F(x,y,t)    = [F(x,y,t) − F_baseline(x,y)] / F_baseline(x,y)
```
Each trial is normalized by the expected F at its own point in session time,
removing the slow baseline ramp. Saves per-trial movies
`dff_m1_ch{N}_{I}uA_trial{K}.mat` and the trial average under
`method1/ch{N}_{I}uA/`. These per-trial movies are the input to step 7_C / 7_D.

### Step 6 — Retinotopic mapping (V1 boundary) *(required)*

[retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)

Required because steps 7_A–7_D can draw the V1 boundary as an overlay. Saves
the `day_setup` (`..._reference_mask_and_retino_alignment.mat`) containing
`retino_align.V1_mask_stim`. Select this file when prompted in step 7.

### Step 7 — Significance thresholding & stimulation region *(required)*

In every step 7 script, when prompted for an optional V1 boundary, select the
`day_setup` file from step 6. The dF/F result is unchanged; the V1 outline is
drawn (green) on figures only.

**Step 7_C — per-trial signed consensus region *(main analysis)*:**

[consensus_region_method1_7C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_7C.m) (interactive)
or [run_9C_batch.py](run_9C_batch.py) → [run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) (batch)

Point it at one condition folder of per-trial movies from step 5_B
(`method1/ch{N}_{I}uA/`). For each trial it re-centers `dF/F` by that trial's
own pre-stim mean (`baseline_dF/F`) and scores each pixel **directionally** at
time *t*:

- **activated**  when `dF/F(x,y,t) − baseline_dF/F(x,y) >  n_std · σ_pre(x,y)`
- **suppressed** when `dF/F(x,y,t) − baseline_dF/F(x,y) < −n_std · σ_pre(x,y)`

(`n_std` default 3, `σ_pre` = that trial's pre-stim std.) The two directions
are counted separately. A pixel is **consensus-active at time *t*** only if it
agrees in *one* direction — activated in ≥ `min_trials` trials, **or**
suppressed in ≥ `min_trials` trials (default 25). A pixel that is activated in
some trials and suppressed in others is treated as noise and is **not**
consensus. Pixels reaching consensus at any post-stim time form the
stimulation-related region for that channel & current.

Maps are colored by the net count (`activated − suppressed`) on a **jet
(rainbow) scale** spanning `[−N, +N]`: red = activated, blue = suppressed.
A **magenta contour** outlines the consensus pixels. The frame grid covers
**t ∈ [−0.2, 1.2] s**.

Outputs per (condition, `n_std`): consensus `.mat`, signed net-count frame
grid, region/peak figures, summary `.txt`, optional MP4.

Batch notes: `run_9C_batch.py` sweeps `N_STD_LIST` and `MIN_TRIALS_LIST`,
writes each `n_std` to its own folder (`ch{N}_{I}uA_{n}sigma/`), and always
overlays the V1 boundary from `V1_SOURCE_FILE`.

**Step 7_D — time-window consensus region *(latency-robust variant of 7_C)*:**

[consensus_region_window_method1_7D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_7D.m) (interactive)
or [run_9D_batch.py](run_9D_batch.py) → [run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) (batch)

Identical to 7_C, except a pixel counts as activated/suppressed at time *t* in
a trial if it crosses threshold **anywhere in the window
[t − window_s, t + window_s]** (default `window_s = 0.1 s`; ±1 frame at
10 Hz). The window absorbs trial-to-trial latency jitter so a response landing
one frame early or late still counts. Output filenames carry a `win{window_s}s`
tag. In practice 7_D recovers substantially more consensus than 7_C at the same
`n_std`. Use 7_D when latency jitter is a concern; use 7_C for strict
same-frame agreement.

**Step 7_E — sustained and latency-consistent activation region *(optional)*:**

[consensus_7E.m](analysis/longitudinal_stim_parameter_survey/consensus_7E.m)

A pixel qualifies if it meets **two independent criteria**:

1. **Sustained activation** — a consecutive run of ≥ `min_duration_s` s above
   threshold exists in ≥ `min_trials_sustained` trials.
2. **Onset consistency** — among those sustained trials, ≥ `min_trials_window`
   have their run-onset time within a common `onset_window_s`-wide sliding
   window (the window can fall anywhere in the post-stim period).

Thresholding uses the same per-trial `baseline_dF/F ± n_std · σ_pre` logic as
7_C. Activated and suppressed directions are evaluated independently. Outputs
one two-panel figure (activated in red, suppressed in blue) per condition.
Defaults: `n_std = 1`, `min_duration_s = 0.3 s`, `min_trials_sustained = 15`,
`min_trials_window = 12`, `onset_window_s = 0.5 s`.

**Step 7_C2 — directional count threshold on 7_C / 7_D output *(optional)*:**

[consensus_7C2.m](analysis/longitudinal_stim_parameter_survey/consensus_7C2.m) (interactive)
or [run_7C2_batch.py](run_7C2_batch.py) → [run_7C2_batch.m](analysis/longitudinal_stim_parameter_survey/run_7C2_batch.m) (batch)

Post-processing filter that works on the saved `.mat` from **either 7_C or
7_D** — no per-trial movie re-loading. At each timepoint, only pixels whose
*dominant* direction (activated or suppressed) reaches `min_count_display`
are rendered; mixed pixels (e.g. 15 activated + 15 suppressed, net = 0) are
excluded. The region is recomputed with the same direction-preference logic.
Outputs are tagged `_c<K>` (e.g. `_c15`) and saved next to the source `.mat`.
The batch runner (`run_7C2_batch.py`) scans a folder tree for all
`consensus_*_m1.mat` files and skips any already-processed `_c<K>` files.

**Step 7_B — single-movie threshold *(optional)*:**

[threshold_dff_method1_7B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_7B.m)

Run only if you want a thresholded view of a single (usually trial-averaged)
movie. Subtracts the pre-stim mean, then flags pixels where
`|dF/F − baseline_dff| > n_std · pixel_std` (pre-stim std of this movie). No
external baseline file is required. Not required for the consensus region.

**Step 7_A — single-movie threshold for Method 0 dF/F *(optional)*:**

[dff_pixelwise_significance_threshold_7A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_7A.m)

Same as 7_B but for Method 0 movies from step 5_A. Uses the movie's own
pre-stim std as threshold (`|dF/F| > n_std · σ_pre`).

---

## Quick Checklist

```
Pre-B  draw_brain_mask_0                  (required)
1      extract_nev_stim_and_camera        (required)
2      align_wf_with_nev_extracted        (required)
3      make_container_ripple              (required)
4      baseline_drift_analysis            (required — drift model for 5_B)
5_B    compute_dff_method1                (required — drift-corrected dF/F movies)
6      retino_alignment_with_brain_mask   (required — V1 boundary overlay)
7_C    consensus_region_method1           (required — stimulation region, strict same-frame)
7_D    consensus_region_window_method1    (recommended — latency-robust, ±0.1 s window)
7_C2   consensus_7C2 / run_7C2_batch     (optional — count threshold on 7_C or 7_D output)
7_E    consensus_7E                       (optional — sustained + onset-consistent region)
7_B    threshold_dff_method1              (optional — single-movie threshold)
7_A    dff_pixelwise_significance_threshold  (optional — Method 0 single-movie threshold)
```

Steps 5_A, and legacy steps 7 (relink), 8_A, 8_B1, 8_B2 are in
`LGN_lagacy_pipeline/` and are not part of the current workflow.
