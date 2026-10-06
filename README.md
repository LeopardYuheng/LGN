# LGN widefield stimulation analysis

| Folder / file | What it is |
|---|---|
| `analysis/`, `acquisition/`, `run_7*_batch.py`, `build_*_pptx.py` | Manual data analysis pipeline (steps 0–9). See [README_brief.md](README_brief.md) and [README_detailed.md](README_detailed.md). |
| `analysis for combining three 10_trials in one/` | Manual pipeline variant for combined 3×10-trial sessions. |
| `auto_pipeline/` | Automated pipeline (steps 0 → 5_A) that drives the manual scripts. See [auto_pipeline/README_AUTO_PIPELINE.md](auto_pipeline/README_AUTO_PIPELINE.md). |
| `retinotopic_mapping/` | Updated retinotopic mapping analysis with brain-mask support. See [retinotopic_mapping/README.md](retinotopic_mapping/README.md). |

The automated pipeline is meant to be checked out in its **own folder**, separate from the manual
pipeline (e.g. `C:\Projects\LGN\WF_auto_pipeline` next to `C:\Projects\LGN\WF_data analysis pipeline`);
`wf_check_paths` refuses to run if it sits inside the analysis repository. Set `cfg.pipeline_root`
and `cfg.retino_root` in `auto_pipeline/wf_config.m` to match your machine.
