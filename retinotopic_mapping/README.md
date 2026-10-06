# analysis_code

Notes for running the retinotopic mapping pipeline. Read this before running, especially if something looks off.

running sequence (07/20/2026 version)
1. run draw_brain_mask.m
2. run retinotopic_mapping_masked_output.m

Don't run retinotopic_mapping_save_to_output_path(old_code_no_brainmask).m unless you want to compare the old result with the new, more correct result.

## Scripts in this folder

| Script | What it does |
| --- | --- |
| `retinotopic_mapping_save_to_output_path(old_code_no_brainmask).m` | Original pipeline. **No brain mask** — azi/alt/VFS cover the whole frame, including cement. |
| `draw_brain_mask.m` | Standalone. Draw the brain area on a reference image; saves `brain_mask.mat`. Run this first. |
| `retinotopic_mapping_masked_output.m` | Same pipeline, but masks both the **inputs** to sign-mapping (cement flat-filled) **and** the outputs, **and** uses a weighted (masked) phase-unwrap via `SignMapperModifR_masked`. |
| `SignMapperModifR_masked.m` | Local subclass of the toolbox `SignMapperModifR`. Adds a `brain_mask` property so the phase-unwrap inside `getRetinotopicMap` is weighted by the mask. Used only by the input+output script; the shared network toolbox is untouched. |


## 1. Data folder must directly contain the .rhd files

The script finds Intan recordings with:

```matlab
DIR = dir('*.rhd');   % line 35
```

This only looks in MATLAB's **current working directory** — it does **not** search subfolders. Before running the script, make sure you `cd` (or select, if the folder-selection step is enabled) directly into the folder that contains the `.rhd` files, e.g.:

```
.../data/ephys/lgn26_260713_174031/
```

not a parent folder like `.../data/ephys/` or `.../result/07132026_LGN26_retinomap/`.

If the current directory doesn't contain any `.rhd` files, `numFiles` will silently be `0`, the Intan-reading loop never runs, and later steps fail with confusing errors (e.g. `Variable "frequency_parameters" not found`) instead of a clear "no files found" message.

## 2. PD (photodiode) channel number must match the Intan digital input wiring

```matlab
t_rising_edge_diode = find(diff(recFile(4, :)) > 0); % row 4 is the PD digital input in INTAN   -- line 58
```

The `4` here is the row of `recFile` that corresponds to the **photodiode (PD) signal**, based on which digital input channel it's wired into on the INTAN board. If the PD signal is ever plugged into a different digital input channel, update this row index to match, otherwise you'll be thresholding the wrong signal entirely.

(For reference, camera sync is read from row 3 later in the script — `Validate Image Count Versus Rising Edges` section — so row indices are recording/wiring-specific, not arbitrary.)

## 3. Choosing `pdThreshold` in the "Detect Screen Flashing Points" section

The threshold used to binarize the PD interval signal is set at:

```matlab
pdThreshold = -80;   % line 154
bw = x > pdThreshold;
```

This value is **not universal** — it depends on the amplitude of the inter-pulse-interval signal (`pd`) for the current recording. Workflow:

1. Run the section once with whatever threshold is currently there (or any placeholder value). This produces `figOriginalPD` (`original_pd_signal.png`/`.fig`), which plots the raw `pd` vs `pd_t` trace.
2. Inspect that plot to find the right cutoff — pick a `pdThreshold` value that cleanly separates the stimulus-marker state from baseline noise.
3. Edit line 154 with the value you found, then re-run the "Detect Screen Flashing Points" section.
4. Check `disp('Number of binary rising edges detected: ...')` in the command window (or `numel(locs)`). **With the correct threshold, this should equal 162.** If it's not 162, the threshold is likely still wrong (too strict/too loose, picking up noise, or merging/splitting real stimulus blocks) — adjust `pdThreshold` and re-run until it matches.

Downstream trial-alignment logic (`locs = locs(2:161);` etc.) assumes this 162-edge count, so getting the threshold right here matters for everything after it.

## 4. Brain mask and the two masked variants

The original script never restricts analysis to the brain, so `azi`, `alt`, and the VFS map are computed over the whole frame — most of which is cement/skull. Everything outside the true brain area is meaningless and, worse, can leak into the brain results through the global operations inside `SignMapperModifR` (phase unwrap, FFT smoothing, watershed, eccentricity referenced to V1's center-of-mass).

### Workflow

1. **Draw the mask once:** run `draw_brain_mask.m`. Select the `.tif` image folder, draw a circle around the brain (and optional exclusion polygons over cement/vessels/shank shadows), verify, and save. It writes `brain_mask.mat` (variable `brain_mask`, a logical mask in raw image space).
2. **Run a masked pipeline:** run either `retinotopic_mapping_mask_output.m` or `retinotopic_mapping_mask_inputoutput.m`. Each prompts you to select the `brain_mask.mat` from step 1 and applies it automatically.
3. **Verify alignment:** both scripts save `Figures/mask_alignment_check.png` — the masked azimuth map with the mask boundary drawn on top. Confirm the brain (not the cement) is what's kept. If it looks rotated/misaligned, tell the maintainer (see the orientation note below).

### Output-only vs. input+output

- **`_mask_output`** — sign-mapping runs on the unmasked maps; the mask is applied only to the saved/displayed `azi`/`alt` and to the VFS products afterward. Safest; never destabilizes the sign-map algorithm.
- **`_mask_inputoutput`** — does three things: (1) uses `SignMapperModifR_masked` so the phase-unwrap inside `getRetinotopicMap` is **weighted** by the mask (cement gets weight 0 and drops out of the global Poisson solve, so it no longer leaks into the brain interior); (2) flat-fills cement with the in-brain mean before sign-mapping so it can't drive the gradients/watershed; (3) masks the saved/displayed outputs. This is the most correct version this pipeline can produce for the pixels **inside** the mask.

  The `SignMapperModifR_masked` subclass leaves the shared network toolbox untouched — it only adds a `brain_mask` property and overrides `getRetinotopicMap`. Delete the file to revert. When `brain_mask` is empty it behaves identically to the stock class.

  What "correct inside the mask" does and does **not** mean: the weighted unwrap removes the *cement leak* we identified, but retinotopy accuracy inside the brain still depends on signal SNR, harmonic selection, the delay correction, the degree-conversion constants (`horz_factor`, `vert_factor`, `pixpermm`), and correct trial/frame alignment — none of which the mask touches. There can also be minor residual edge effects just inside the mask boundary. So: more correct, and free of the cement leak — but not a guarantee of ground truth. Run both variants and compare.

### Orientation and size notes (important)

- **Coordinate space:** `brain_mask` is saved in **raw image space** (same H×W as the `.tif` frames / `first_img`). But `getRetinotopicMap` internally `rot90`'s the phase maps, so `azi`/`alt` are rotated 90° relative to the raw image. The masked scripts handle this with `mask_map = rot90(brain_mask_raw)` before applying to `azi`/`alt`. The `mask_alignment_check` figure exists to confirm this is right.
- **Why `azi`/`alt` are 512×512 but VFS is 400×400:** `azi`/`alt` are saved straight out of `getRetinotopicMap` at the native image resolution (= size of `fourier_data` = your TIFF size, e.g. 512×512). The **VFS map is produced inside `Juavinett2017_signMapping`, which resamples the maps (`resample(...,2,5)`, a ×2/5 downsample) and — in the version on the network `TOOLBOX_YC` path — saves the result on a fixed **400×400** grid. So VFS and azi/alt are *not* on the same grid or orientation.
  - The local class copy at `...\data analysis pipeline\analysis\retinotopic_mapping\rm_functions\SignMapperModifR.m` has a patch (the "store outputs in ONE CONSISTENT SPACE" block) that resizes the VFS products back to the reference-image size. If you point the script's `addpath` (line 5) at that folder instead of the network `TOOLBOX_YC` copy, VFS comes out at the raw image size, which makes overlays and mask application cleaner.
  - The masked scripts resize the mask to whatever grid the VFS happens to be on (`imresize(mask_map, size(VFS_raw))`), so VFS masking works either way — but always confirm alignment via `overlay_map.jpg`.