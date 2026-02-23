# Neurostim Mapping MATLAB Pipeline

This repository contains MATLAB scripts for running widefield imaging experiments, retinotopic mapping, stimulation parameter surveys, and downstream analysis of cortical responses.

The pipeline is organized into sequential stages: stimulus presentation, data extraction, spatial alignment, and analysis.

---

## Pipeline Overview

The typical workflow is:

1. **Flash Test (System Validation)**
2. **Retinotopic Mapping (Define V1)**
3. **Stimulation Parameter Survey (Data Collection)**
4. **Analysis (Dose–Response and Temporal Dynamics)**

Each stage is described below.

---

## 1. Flash Test (System Validation)

Used to verify that the imaging system, stimulus display, and trigger synchronization are functioning correctly.

### Scripts

- **`run_flash_test_visuals.m`**  
  Presents a full-field white flash stimulus while sending triggers to the acquisition system. Used to confirm correct stimulus delivery and camera synchronization.

- **`white_flash_analysis.m`**  
  Computes ΔF/F responses from the flash test and generates basic response maps and time courses for quality control.

---

## 2. Retinotopic Mapping (Define V1)

Used to identify visual cortical areas and define a V1 mask for subsequent analyses.

### Scripts

- **`run_retinotopic_mapping_stimulus.m`**  
  Runs a retinotopic mapping stimulus (e.g., drifting bars or phase-encoded stimuli) and records timing signals.

- **`compute_retino_maps.m`**  
  Processes the retinotopy dataset to compute spatial maps (e.g., phase maps, visual field sign), producing a processed `.mat` file.

- **`generate_retino_mask.m`**  
  Interactive tool for drawing and saving a V1 mask (or visual area boundaries) based on retinotopic maps.

  *Note:* This step can be repeated to refine the mask after reviewing results.

---

## 3. Stimulation Parameter Survey (Widefield + Ephys)

Used to measure cortical responses to thalamic (LGN) stimulation across different stimulation parameters.

### Scripts

- **`run_wf_ephys_stim_param_survey.m`**  
  Runs the stimulation protocol, delivering electrical stimulation across conditions (e.g., current levels, frequencies, durations) while recording widefield imaging and electrophysiology.

- **`extract_nev_stim_and_camera.m`**  
  Extracts stimulation timestamps and camera trigger signals from recorded data files (e.g., NEV), aligning neural and imaging data.

---

## 4. Analysis (Response Characterization)

Used to quantify spatial and temporal response properties.

### Scripts

- **`current_thresholding_analysis.m`**  
  Computes dose–response relationships and estimates activation thresholds for each stimulation channel.

- **`dff_over_time_analysis.m`**  
  Computes ΔF/F time courses aligned to stimulation events and visualizes temporal dynamics across conditions.

---

## Notes

- Most scripts require manual interaction (e.g., ROI drawing, control point selection).
- Data files are not included in this repository; users must provide their own datasets following the expected structure.
- Outputs are saved locally (e.g., `.mat` files, figures) for downstream analysis.

---

## Summary

This pipeline enables:

- Validation of imaging and stimulus timing
- Identification of visual cortical regions (V1)
- Quantification of cortical responses to thalamic stimulation
- Analysis of spatial organization and response magnitude

---
