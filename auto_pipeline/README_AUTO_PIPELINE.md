# Automated widefield pipeline — step 0 through step 5_A

One button. Connect the portable disk, double-click **Run WF Pipeline** on the
desktop, confirm what it found, approve the brain mask and the retinotopic
alignment, walk away. Results land in `C:\Projects\LGN\WF_result`.

## This folder is separate from your analysis code, on purpose

```
C:\Projects\LGN\
    data analysis pipeline\    your original scripts — READ ONLY to this tool
    WF_auto_pipeline\          this folder, all the automation
    WF_result\                 output
```

Nothing here is ever written into `data analysis pipeline`. Scripts are
executed where they sit; the two that need a source tweak are copied to the
Windows temp folder first and edited there. `wf_check_paths` refuses to run if
this folder or the output folder ends up inside the analysis repository, so the
separation cannot be lost by accident.

If you move the analysis repository, change `cfg.pipeline_root` in
`wf_config.m` — that is the only link between the two folders.

## Expected disk layout

```
<disk>\Yuheng_LGN\LGN24_08272026_postblind_WFimage\   three-session experiment
    data\session1\img\      *.tif
    data\session1\ephys\    *.nev + *.ns5 + trial *.csv
    data\session2\ ...      data\session3\ ...

<disk>\yuheng\lgn24_stim_WF_07242026\                three-session, no data\ level
    session1\img\  session1\ephys\  session2\ ...  session3\ ...

<disk>\yuheng\lgn24_stim_WF_07162026\                single-session experiment
    img\               *.tif
    ephys\             *.nev + trial *.csv
```

All of these work, and so does a single session under `data\`. The number of
folders between the experiment folder and the TIFFs does not matter: the
experiment is identified by the folder whose **name** carries the subject and
date, not by counting levels. That folder is also where `Next to data` puts
the analysis folder, so it lands beside `data\` rather than inside it.

Subject and date come from the experiment folder name: `lgn24` and
`07242026` (MMDDYYYY). `20260724` (YYYYMMDD) is recognised too, so old and
new naming both work. Sessions sharing a subject and date become one
experiment, and the output folder is `WF_result\LGN24_07242026`.

The `.nev` and CSV may sit directly in `ephys\`, or one or two levels deeper
in a subfolder the acquisition software made:

```
session1\ephys\datafile0001\*.nev + *.ns5 + *.csv     also fine
```

The `.ns5` beside the `.nev` is ignored. Step 1 already guards against it:
`extract_nev_stim_and_camera_1.m` copies the `.nev` alone into a temp folder
before opening it, so Neuroshare never indexes the multi-gigabyte continuous
file. That temp copy is removed when the next step starts.

A level is only followed when it holds **exactly one** subfolder. Two or more
is ambiguous, so rather than guess, that session is reported as unresolved and
lands in `sessions_unresolved.csv` where you can point at the right folder.
Raise `cfg.ephys_descend_depth` if the nesting is ever deeper than two.

Each session's `.nev` and CSV are looked for in its own folder only — the
TIFF folder, then its siblings with `ephys` first, following single-subfolder
chains. The search deliberately never descends into a *different* session's
folders: if `session2\ephys` is empty, session2 is reported as unresolved
rather than quietly picking up session1's recording.

## Install (once)

Run `Create_Desktop_Shortcut.bat`. That puts *Run WF Pipeline* on the desktop
pointing at `Run_WF_Pipeline.bat` in this folder.

Then, in MATLAB, run `selftest_wf_pipeline` once. It takes a few seconds, needs
no data, and confirms the automation works on this MATLAB version. If anything
fails there it will fail on real data too, so fix it before the first run.

If MATLAB is installed somewhere unusual, open `Run_WF_Pipeline.bat` in Notepad
and set `MATLAB_EXE` at the top to the full path of `matlab.exe`.

## What happens when you press Run

The run has two phases. **Everything that needs you happens in phase 1, for
every experiment you selected.** Pick five experiments and you answer five sets
of windows back to back at the start, then the machine works through all five
without interrupting you again.

### Phase 1 — setup, one experiment at a time

**Pre-step A, retinotopy input.** Step 6 needs a
`retino_registration_ready.mat`. If one already exists for that subject it is
reused; otherwise `retino_inputcombine.m` builds it from `azi.mat`, `alt.mat`
and `additional_maps.mat`. The pipeline looks on the portable disk for a folder
holding all three **whose path names this subject** — it will not guess even
when there is only one retinotopy folder on the disk, because a map from the
wrong animal produces a V1 boundary that is wrong everywhere while looking
entirely ordinary. If none names the subject, a folder picker opens.

**Then you confirm the map.** Whatever it found, the reference image with
visual-area boundaries, the azimuth map and the altitude map are shown side by
side with the file path, and you answer *Yes, use this map* / *No, pick a
different folder* / *Skip step 6*. Picking a different folder rebuilds and asks
again. This is the check that catches a reused file belonging to another animal
or another field of view.

**Step 0, brain mask.** The reference image (average of the first 200 TIFFs) is
segmented with Otsu thresholding plus morphological cleanup. Both polarities are
tried and scored on area, convexity and centrality, so it works whether the
cranial window is brighter or darker than its surroundings. You get a window
showing the proposed boundary with Accept, Grow 4 px, Shrink 4 px, and *Draw it
myself*, which hands over to the original `draw_brain_mask_0.m` unchanged.

**Step 6, retinotopic alignment.** `cpselect` opens and you pick matching
landmarks on the retinotopy reference and the stimulation-day image, exactly as
you do by hand today. When it finishes, the warped visual-area boundaries and
the V1 outline are drawn over the stimulation image next to the bare image, and
you decide:

- **Looks right, keep it** — the alignment is committed
- **Re-align** — that attempt is deleted and cpselect reopens, repeat as often
  as you like; only the accepted attempt is ever saved
- **Skip step 6** — step 5_A runs without the V1 contour

V1 itself is drawn once per subject and cached, so re-aligning only repeats the
landmark picking, never the polygon. Setting `cfg.retino.auto_register = true`
switches to `imregtform` plus your nudge GUI, with the same accept/re-align loop
around it.

If no retinotopy is available, step 6 is skipped and step 5_A simply runs
without the V1 contour — the dF/F values are identical either way, V1 is drawn
for display only.

### Phase 2 — analysis, unattended

Only once every selected experiment has been set up does any analysis start.
Step 1, TIFF-check, step 2, step 3, TIFF-fix and step 4 run once per session;
step 5_A runs once, pooling all sessions when the experiment has three of them.

No window opens during this phase, with one exception: if a step fails and
`cfg.on_error` is `'ask'`, you are asked whether to retry, skip or stop. An
experiment whose setup failed or was skipped is simply left out, and the log
says which and why before the analysis begins.

## Watching progress, stopping, and errors

**The progress pane** shows the tail of the log file in the output folder of
the experiment currently running. That file carries everything the original
scripts print — which condition, which trial, frame counts — not just this
tool's own messages, because `diary` is on for the whole experiment.

There is one honest limitation. MATLAB runs the analysis and the window on a
single thread, so the pane cannot repaint while a step is inside a loop over
TIFF frames; it catches up at the end of each step. The **log file itself is
written continuously**, so to watch a long step in real time press **Open log
file** and leave that window open, or tail it in any editor.

**Stop** takes effect at the next step boundary, for the same reason — a click
cannot be processed while a step is computing. It is checked before every step,
every session and every experiment. For an immediate stop press **Ctrl+C in the
MATLAB command window**: that is caught and reported as a clean stop rather than
a crash, and because finished steps are skipped on the next run, nothing is
wasted.

**When a step fails**, the run stops and asks:

- **Retry this experiment** — re-enters it with finished steps skipped, so it
  resumes at the step that failed. Right after fixing a missing file or a
  disconnected disk.
- **Skip it and continue** — abandon this experiment, move to the next
- **Stop everything** — end the batch

Untick *Ask me when a step fails* to skip failures silently instead, or set
`cfg.on_error` to `'continue'` or `'stop'`.

## Where results go

The confirmation table has a **Results to** column, set per experiment:

| Choice | Where results land |
|---|---|
| `WF_result` | `C:\Projects\LGN\WF_result\LGN24_08212026\` |
| `Next to data` | `E:\Yuheng_LGN\LGN24_08212026_postblind_WFimage\LGN24_08212026_analysis\` — a named folder inside the experiment's own folder on the disk, so `img\` and `ephys\` stay untouched |
| `Choose folder...` | a folder you pick, with `LGN24_08212026\` created inside it |

The resolved path is shown in the next column and can also be typed directly;
doing so marks that row Custom. With several experiments there are buttons to
set them all at once, but each row's folder is still shown for you to check
before anything runs.

Two experiments pointing at the same folder is refused rather than allowed —
their `prep_steps\` and `Step5A_method0\` would overwrite each other, and the
damage would only surface later as results that do not match the data.

Writing next to the data does not confuse the scanner on later runs: a folder
only counts as a session when it holds a few hundred numbered TIFFs, and the
`.nev` search always tries `ephys\` before any other sibling. Re-scanning a
disk that already holds analysis folders finds the same experiments as before.

Set `cfg.output_location` to `'result_root'` or `'with_data'` to change which
choice the table starts on. `cfg.output_with_data_suffix` names the analysis
folder — `'_analysis'` by default, or empty to write straight into the
experiment folder.

## Output layout

```
WF_result\LGN26_06302026\
    LGN26_20260630_brain_mask.mat
    prep_steps\                  intermediates (per session on the combined track)
    step6_V1overlay\             retino_registration_ready.mat + day_setup
    Step4_baseline_drift\        drift model + QC figures
    Step5A_method0\              the result: one folder per channel/current
    logs\                        full transcript of every run
```

A one-line-per-run summary is appended to `WF_result\pipeline_runs.csv`.

## Single vs three-session

Sessions sharing a subject and date are grouped into one experiment. One session
uses `analysis\longitudinal_stim_parameter_survey`; two or more use
`analysis for combining three 10_trials in one`, which pools the trials so the
result is equivalent to one long session. The confirmation screen shows which
track each experiment will take and lets you override it before running.

## How it works, and why nothing was rewritten

Your pipeline scripts are **not modified and not duplicated**. They stay the
single source of truth and keep behaving exactly as they do when you press Run
in the editor.

The automation works by shadowing the five dialog functions — `uigetfile`,
`uigetdir`, `inputdlg`, `listdlg`, `questdlg` — with stubs in `uistub\`. Before
each script runs, `wf_run_script` loads a table of answers keyed by the dialog's
prompt text, puts `uistub` at the front of the MATLAB path, and executes the
script in the base workspace. Each stub looks up its answer instead of opening
a window. Afterwards the path is restored.

Two places a stub cannot reach are handled by rewriting a **temporary copy** of
the script, never the original: the console `input()` call that asks
`build_tiff_sma1_correction_map` for a session ID, and the `RUN_OPTION_A/B`
literals that choose step 6's registration method.

Two consequences worth knowing. If a script stops asking for something, you get
a warning naming the unused answer rather than silent wrong behaviour. If a
script starts asking for something new, strict mode raises an error naming the
exact prompt, and adding one line to that step's wrapper fixes it.

## Settings

Everything lives in `wf_config.m`. The ones you are most likely to touch:

`pipeline_root` (where your original scripts live), `output_root` and
`disk_root` (pin the drive letter instead of searching for it),
`conditions` (`'all'` or an n-by-2 list of `{channel, current}`), `display_tmin`
and `display_tmax` for the frame grid, `run_step4` (off saves time on a 5_A-only
run, but Method 1 needs it), `resume` (skip steps whose output already exists —
this is what makes re-running after a crash cheap), and `strict_dialogs` (turn
off to have unanticipated dialogs appear for you to answer, useful when the disk
layout changes).

`id_patterns` and `session_patterns` are the two knobs that teach the scanner
your folder naming. They are regexps with `<subj>` and `<date>` tokens, tried in
order.

## When the scanner cannot work something out

It writes `sessions_unresolved.csv` at the disk root, pre-filled with everything
it did resolve. Fill in the blanks, rename it to `sessions.csv`, and the next run
reads it instead of guessing. The columns are `subject, date, session_label,
tiff_dir, nev_file, csv_file`; paths may be absolute or relative to the disk
root, and `session_label` is blank for a single-session experiment.

## One thing to be aware of in step 1

`extract_nev_stim_and_camera_1.m` reads its metadata dialog fields in a
different order than it labels them:

```matlab
mouse_id      = answ{1};
date_str      = answ{3};   % field labelled "Experiment ID"
experiment_id = answ{2};   % field labelled "Date (YYYYMMDD)"
```

Fields 2 and 3 are swapped. Running by hand, this means the date has to be typed
into the box labelled *Experiment ID* or the filename comes out wrong. The
automation supplies the answers in the order the script actually reads them, so
it produces correct filenames as-is. If you ever fix that script, swap the middle
two entries in `wf_step1_ripple.m` to match — `selftest_wf_pipeline` will not
catch this one, since it is a semantic mismatch rather than a broken call.

## Files

| File | Role |
|---|---|
| `Run_WF_Pipeline.bat` | double-click launcher |
| `wf_pipeline_app.m` | the window: scan, confirm, run, live log |
| `wf_auto_run.m` | driver: setup phase, then analysis phase |
| `wf_prepare_experiment.m` | phase 1 for one experiment |
| `wf_run_experiment.m` | phase 2 for one experiment |
| `wf_verify_retino_map.m` | the "is this the right retinotopy?" window |
| `wf_scan_disk.m` | finds experiments on the disk |
| `wf_config.m` | every setting, including `pipeline_root` |
| `wf_step_retino_combine.m` | pre-step A: builds the retinotopy input |
| `wf_step*.m` | one wrapper per pipeline step |
| `wf_stop.m` | the cooperative stop signal |
| `wf_run_script.m`, `wf_ui.m`, `uistub\` | the dialog-answering layer |
| `selftest_wf_pipeline.m` | installation check, no data needed |

## Requirements

MATLAB R2018b or newer with the Image Processing Toolbox. Steps beyond 5_A
(7_A, 7_C, 7_D and so on) are unchanged and still run the way they always have.
