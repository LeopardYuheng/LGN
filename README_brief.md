# LGN Widefield Pipeline — Run Order

After the common data-preparation steps (Pre-B through Step 4), the pipeline
branches into **three parallel analysis tracks**. Run whichever tracks you
need — they are independent of each other once Step 5 outputs exist.

```
Pre-B  →  1  →  TIFF-check*  →  2  →  3  →  TIFF-fix*  →  4  →  6 (V1, optional)
                                                    │
               ┌────────────────────────────────────┼──────────────────────┐
               │                                    │                       │
           TRACK A                             TRACK B                TRACK C
      Local baseline                       Global baseline          Consistency
     dF/F analysis                        dF/F analysis            analysis
       (Method 0)                           (Method 1)           (Method 1)
               │                                    │                       │
             5_A                                  5_B                     5_B
               │                                    │                       │
             7_A                                  7_B               7_C / 7_D
                                                                        │
                                                                 7_C2 (optional)
                                                                 7_E  (optional)
```

**\* TIFF-check / TIFF-fix** are required for every session — see
[TIFF–SMA1 Frame Alignment Check](#tiff-sma1-frame-alignment-check-required) below.

**Step 8** is optional and not shown above — it works directly off Step 5_A
or 5_B output, letting you pick either Method and compare one pixel's
dF/F(t) across every current level of a chosen channel. See
[Step 8](#step-8--pixel-dfft-comparison-across-currents-optional) below.

Keep data in its final location before starting — later scripts reload
saved paths and will break if files move.

---

## Common Pre-Steps

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

### TIFF-check — Build TIFF–SMA1 correction map *(required, after Step 1)*

[Diagnose&fix_code/build_tiff_sma1_correction_map.m](analysis/longitudinal_stim_parameter_survey/Diagnose&fix_code/build_tiff_sma1_correction_map.m)

Cross-references embedded TIFF timestamps against SMA1 trigger times to detect
dropped frames and SMA1 channel dropouts. Produces `tiff_correction.mat`.
Run this for every session — even with no mismatches it serves as a QC check.
See [README_detailed.md](README_detailed.md#tiffsma1-frame-alignment-check) for the algorithm and failure modes.

*Optional diagnostic:* [diagnose_late_segment_matching.m](analysis/longitudinal_stim_parameter_survey/Diagnose&fix_code/diagnose_late_segment_matching.m)
plots `delta_t` and inter-frame intervals to visualise any misalignment before
running the correction.

### Step 2 — Align widefield frames to stim timing *(required)*

[align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)

### Step 3 — Build the day pointer container *(required)*

[make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)

Produces the day pointer that all downstream steps load.

### TIFF-fix — Apply correction to day pointer *(required, after Step 3)*

[Diagnose&fix_code/apply_tiff_correction_to_day_pointer.m](analysis/longitudinal_stim_parameter_survey/Diagnose&fix_code/apply_tiff_correction_to_day_pointer.m)

Applies `tiff_correction.mat` to the Step 3 day pointer. Converts onset indices
to corrected TIFF positions and excludes any trial whose window contains a
dropped frame. Saves `<name>_tiff_corrected.mat` — **use this file in Steps
5_A and 5_B instead of the original day pointer.**

### Step 4 — Baseline drift analysis *(required for Track B/C; recommended QC for Track A)*

[baseline_drift_analysis_4.m](analysis/longitudinal_stim_parameter_survey/baseline_drift_analysis_4.m)

Fits a per-pixel linear model `F(x,y) = slope·t + intercept` across all
0 µA trials (session-clock time). Saves `baseline_drift_4.mat` with
`slope_map` and `intercept_map`, which step 5_B uses for drift-corrected
normalization. Also produces diagnostic figures (slope map, R² map, mean-F
scatter) that inform which track to use.

### Step 6 — Retinotopic mapping (V1 boundary) *(optional overlay for all tracks)*

[retino_alignment_with_brain_mask_6.m](analysis/longitudinal_stim_parameter_survey/retino_alignment_with_brain_mask_6.m)

Produces the `day_setup` file containing `retino_align.V1_mask_stim`. When
selected in any step 7 script, the V1 boundary is drawn as a green contour
on all figures. The dF/F result is never altered; V1 is display-only.

---

## Track A — Local Baseline dF/F Change Analysis (Method 0)

**Use when:** you want per-trial normalization using each trial's own
pre-stim frames as the baseline. Simple and does not require a drift model.
Best when the raw fluorescence is stable across the session (confirmed by
step 4 showing a flat slope map).

### Step 5_A — Whole-brain dF/F movies, per-trial baseline

[current_thresholding_analysis_pixelwise_region_5A.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_5A.m)

For each trial: `dF/F(x,y,t) = [F(x,y,t) − F_pre(x,y)] / F_pre(x,y)` where
`F_pre` is the mean over that trial's own pre-stim frames. Conditions are
listed sorted by channel then current. Interactive display time window (default
-0.2 to 1.2 s); optional V1 overlay. Saves per-trial movies
`dff_ch{N}_{I}uA_trial{K}.mat` and trial averages under `ch{N}_{I}uA/`.

### Step 7_A — Per-pixel significance threshold on Method-0 movies

[dff_pixelwise_significance_threshold_7A.m](analysis/longitudinal_stim_parameter_survey/dff_pixelwise_significance_threshold_7A.m) (interactive)
or [run_7A_batch.py](run_7A_batch.py) → [run_threshold_m0_batch.m](analysis/longitudinal_stim_parameter_survey/run_threshold_m0_batch.m) (batch)

Scans the step-5_A output folder, lets you select channel-current conditions
from a sorted list, then for each: flags `|dF/F(x,y,t)| > n_std · σ_pre(x,y)`
(pre-stim std of that movie) as suprathreshold. Saves thresholded `.mat` and
frame-grid figures. Interactive pixel-picking viewer available for single-condition
runs. Optional V1 overlay; display time window matches step 5_A selection.

---

## Track B — Global Baseline dF/F Change Analysis (Method 1)

**Use when:** you want to visualize the trial-averaged dF/F response using the
drift-corrected global baseline, for a single (averaged) movie. Useful as a
quick visual check before running the more computationally intensive Track C.

> Both Track B and Track C start from the same **step 5_B** output.
> Run step 5_B once; then run Track B and/or Track C on those movies.

### Step 5_B — Whole-brain dF/F movies, drift-corrected global baseline

[compute_dff_method1_5B.m](analysis/longitudinal_stim_parameter_survey/compute_dff_method1_5B.m)

Loads `slope_map` and `intercept_map` from `baseline_drift_4.mat` (step 4).
For each trial at session-clock onset `t_session`:
```
F_baseline(x,y) = intercept_map(x,y) + slope_map(x,y) · t_session
dF/F(x,y,t)    = [F(x,y,t) − F_baseline(x,y)] / F_baseline(x,y)
```
Each trial is normalized by the expected F at its own point in session time,
removing the slow baseline ramp. Saves per-trial movies
`dff_m1_ch{N}_{I}uA_trial{K}.mat` and trial averages under
`method1/ch{N}_{I}uA/`. These outputs feed **both** Track B and Track C.

### Step 7_B — Per-pixel significance threshold on Method-1 trial average

[threshold_dff_method1_7B.m](analysis/longitudinal_stim_parameter_survey/threshold_dff_method1_7B.m)

Loads a single trial-averaged dF/F movie from step 5_B. Subtracts the
pre-stim mean, then flags pixels where
`|dF/F − baseline_dff| > n_std · pixel_std` (pre-stim std of this movie).
No external baseline file required. Saves thresholded `.mat` and frame-grid
figure; optional video and V1 overlay.

---

## Track C — dF/F Change Consistency Analysis (Method 1)

**Use when:** you want to identify pixels that *consistently* respond across
trials, rather than just responding on average. This is the primary analysis
for mapping stimulation-related regions. Requires the per-trial movies from
step 5_B (same output as Track B).

### Step 7_C — Per-trial cross-trial consensus region *(strict same-frame)*

[consensus_region_method1_7C.m](analysis/longitudinal_stim_parameter_survey/consensus_region_method1_7C.m) (interactive)
or [run_7C_batch.py](run_7C_batch.py) → [run_consensus_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_m1_batch.m) (batch)

For each trial, subtracts that trial's pre-stim mean and thresholds at
`n_std · σ_pre`. Scores each pixel directionally at each timepoint — a pixel
is **consensus-active** only if ≥ `min_trials` trials agree on the *same*
direction (all activated, or all suppressed). Mixed activation/suppression is
treated as noise. Pixels consensus-active at any post-stim time form the
stimulation-related region.

Maps are colored by signed net count (`activated − suppressed`) on a jet
scale: red = activated, blue = suppressed. Frame grid covers
**t ∈ [−0.2, 1.2] s**. Outputs: consensus `.mat`, frame-grid PNG, region
PNG, summary `.txt`, optional MP4.

### Step 7_D — Time-window consensus region *(latency-robust variant of 7_C)*

[consensus_region_window_method1_7D.m](analysis/longitudinal_stim_parameter_survey/consensus_region_window_method1_7D.m) (interactive)
or [run_7D_batch.py](run_7D_batch.py) → [run_consensus_window_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_consensus_window_m1_batch.m) (batch)

Identical to 7_C, except a pixel counts as activated/suppressed at time *t*
if it crosses threshold **anywhere in [t − window_s, t + window_s]** (default
`window_s = 0.1 s`; ±1 frame at 10 Hz). Absorbs trial-to-trial latency
jitter. In practice recovers substantially more consensus than 7_C at the
same `n_std`. Output filenames carry a `win{window_s}s` tag.

> **Use 7_C** for the strictest same-frame agreement.
> **Use 7_D** when trial latency jitter is a concern (recommended by default).

### Step 7_C2 — Directional count threshold filter *(optional post-filter)*

[consensus_7C2.m](analysis/longitudinal_stim_parameter_survey/consensus_7C2.m) (interactive)
or [run_7C2_batch.py](run_7C2_batch.py) → [run_7C2_batch.m](analysis/longitudinal_stim_parameter_survey/run_7C2_batch.m) (batch)

Loads a saved 7_C or 7_D `.mat` (no per-trial movie re-loading) and applies a
stricter directional count threshold: at each timepoint, only pixels whose
*dominant* direction reaches `min_count_display` are shown; mixed pixels
(e.g. 15 activated + 15 suppressed, net = 0) are excluded. Outputs tagged
`_c<K>` next to the source `.mat`. Batch runner scans a folder tree and skips
already-processed files.

### Step 7_E — Sustained + latency-consistent region *(optional)*

[consensus_7E.m](analysis/longitudinal_stim_parameter_survey/consensus_7E.m) (interactive)
or [run_7E_batch.py](run_7E_batch.py) → [run_sustained_m1_batch.m](analysis/longitudinal_stim_parameter_survey/run_sustained_m1_batch.m) (batch)

A pixel qualifies if it meets **two independent criteria**:
1. **Sustained** — a consecutive activation run of ≥ `min_duration_s` s
   exists in ≥ `min_trials_sustained` trials.
2. **Onset consistency** — among those sustained trials, ≥ `min_trials_window`
   have their run-onset within a common `onset_window_s`-wide sliding window.

Evaluated separately for activation and suppression. Outputs a two-panel
region figure (red = activated, blue = suppressed) per condition.
Defaults: `n_std = 1`, `min_duration_s = 0.3 s`, `min_trials_sustained = 15`,
`min_trials_window = 12`, `onset_window_s = 0.5 s`.

---

## Step 8 — Pixel dF/F(t) Comparison Across Currents (optional)

[pixel_temporal_comparison_8.m](analysis/longitudinal_stim_parameter_survey/pixel_temporal_comparison_8.m)

Works directly off the **mean dF/F movies from step 5_A or 5_B** (not step
7's thresholded output). Choose Method 0 or Method 1, then pick one channel —
every current level available for that channel is auto-loaded. Click pixel(s)
on a reference dF/F map (autoscaled, optional V1 overlay, time slider) and
get one two-panel figure per picked pixel: the reference dF/F map with that
pixel marked (left) next to `dF/F(t)` overlaid for every current of that
channel (right, one color per current in ascending order, e.g. 0 µA green,
2 µA red, 3 µA blue, ... 7 µA). Saves the figure plus the raw per-current
traces as a `.mat`.

---

## Quick Checklist

```
COMMON (required for every session)
  Pre-B       draw_brain_mask_0
  1           extract_nev_stim_and_camera
  TIFF-check  build_tiff_sma1_correction_map     ← after Step 1
              [optional: diagnose_late_segment_matching  (visual QC)]
  2           align_wf_with_nev_extracted
  3           make_container_ripple
  TIFF-fix    apply_tiff_correction_to_day_pointer  ← after Step 3
  4           baseline_drift_analysis              (required for B/C; QC for A)
  6           retino_alignment_with_brain_mask     (optional V1 overlay)

TRACK A — Local baseline (Method 0)
  5_A    current_thresholding_analysis_pixelwise_region_5A  [use tiff_corrected day pointer]
  7_A    dff_pixelwise_significance_threshold_7A  (or run_7A_batch.py)

TRACK B — Global baseline (Method 1, single movie)
  5_B    compute_dff_method1_5B         [use tiff_corrected day pointer] (shared with Track C)
  7_B    threshold_dff_method1_7B

TRACK C — Consistency (Method 1, cross-trial)
  5_B    compute_dff_method1_5B         [use tiff_corrected day pointer] (shared with Track B)
  7_C    consensus_region_method1_7C    (or run_7C_batch.py)
  7_D    consensus_region_window_method1_7D  (or run_7D_batch.py)  [recommended]
  7_C2   consensus_7C2 / run_7C2_batch      [optional post-filter]
  7_E    consensus_7E  / run_7E_batch        [optional]

STEP 8 — cross-current pixel comparison (optional, reads Track A or B step 5 output)
  8      pixel_temporal_comparison_8   [choose Method 0 (5_A) or Method 1 (5_B) source]
```

Legacy scripts (steps 5_B1, 7-relink, 8_A, 8_B1, 8_B2) are in
`LGN_lagacy_pipeline/` and are not part of the current workflow.