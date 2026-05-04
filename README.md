# Luan Lab Widefield Post-Experiment Guide

Once you finish an experiment, the most important thing is to keep the data organized and unified before running analysis.

This repository’s scripts pass file paths from one step to the next. Early scripts save bookkeeping files that point to image folders, setup files, CSVs, and session timing files. Later scripts load those saved paths back in and expect the data to still be in the same place.

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

- retinotopy outputs
- TIFF image folders
- stimulation timing extracted from electrophysiology recordings
- stimulation condition CSV files
- downstream analysis outputs

These are not treated as isolated files. They become connected through saved `.mat` files that store metadata and paths. If one piece is moved later, the rest of the pipeline may no longer know where to find it.

Keeping everything unified helps with:

- reproducibility
- easier troubleshooting
- cleaner handoff to the next person
- fewer broken path issues
- easier across-session comparisons

## After The Experiment: Analysis Order

### 1. Run retinotopic mapping first

Run [reference_mask_and_retino_alignment.m](analysis/retinotopic_mapping/reference_mask_and_retino_alignment.m).

This step defines the reference mask and retinotopic alignment information used later by the stimulation-analysis pipeline. Downstream scripts rely on these outputs to define analysis regions such as V1 and to keep comparisons consistent across sessions.

### 2. Run the numbered scripts in longitudinal stim parameter survey

Then run the scripts in numbered order in [analysis/longitudinal_stim_parameter_survey](analysis/longitudinal_stim_parameter_survey).

Canonical order:

1. [extract_nev_stim_and_camera_1.m](analysis/longitudinal_stim_parameter_survey/extract_nev_stim_and_camera_1.m)
2. [align_wf_with_nev_extracted_2.m](analysis/longitudinal_stim_parameter_survey/align_wf_with_nev_extracted_2.m)
3. [make_container_ripple_3.m](analysis/longitudinal_stim_parameter_survey/make_container_ripple_3.m)
4. [current_thresholding_analysis_pixelwise_region_4.m](analysis/longitudinal_stim_parameter_survey/current_thresholding_analysis_pixelwise_region_4.m)
5. [compare_pixelwise_activation_across_sessions_5.m](analysis/longitudinal_stim_parameter_survey/compare_pixelwise_activation_across_sessions_5.m)

## What Each Step Is Doing

### Retinotopy

[reference_mask_and_retino_alignment.m](analysis/retinotopic_mapping/reference_mask_and_retino_alignment.m)

- Defines the reference mask
- Establishes retinotopic alignment
- Produces the mask information used by later stimulation analyses

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

- Runs the single-session pixelwise activation analysis
- Computes threshold and activation-region summaries by channel/current

### Step 5

[compare_pixelwise_activation_across_sessions_5.m](analysis/longitudinal_stim_parameter_survey/compare_pixelwise_activation_across_sessions_5.m)

- Compares matched channel-current activation maps across sessions
- Produces overlap and reproducibility metrics across days

## Important Path Behavior

Several scripts save structures that contain file paths or relative file references. These saved outputs are then reused by later scripts.

That means:

- choose the correct folders when prompted
- make sure the experiment data is already in its final home
- avoid reorganizing the dataset midway through analysis

If you need to reorganize data, do it before running the pipeline, not after.

## Practical Rule

Once the experiment data is in place and you start running the pipeline, treat the folder locations as fixed.

