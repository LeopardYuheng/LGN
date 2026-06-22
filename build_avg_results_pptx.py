
"""
build_avg_results_pptx.py
--------------------------
Opens a folder picker, scans all subfolders for result PNGs produced by any
pipeline step, and assembles a PowerPoint deck.

Layout: one slide per (step type, channel), showing all current levels as a
3-column × 2-row grid (or smaller if fewer than 6 currents are present).
Each cell is labelled with its current level.

Recognises outputs from:
  Step 5A  : mean_dff_ch{N}_{I}uA_frame_grid.png
  Step 5B  : mean_dff_m1_ch{N}_{I}uA_frame_grid.png
  Step 7A  : thresh_*_frame_grid.png                    (Method-0 threshold)
  Step 7B  : thresh_*_m1_frame_grid.png                 (Method-1 threshold)
  Step 7C  : consensus_*_m1_frame_grid.png, consensus_*_m1_region.png
  Step 7D  : consensus_*win*_m1_frame_grid.png, consensus_*win*_m1_region.png
  Step 7C2 : consensus_*_c<K>_frame_grid.png, consensus_*_c<K>_region.png
             (thresholded outputs from step_7C_result_thresholded or
              step_7D_result_thresholded; recognised by the _c<digits> tag)
  raw-F    : rawF_ch{N}_{I}uA_AVERAGE.png

Usage:
    pip install python-pptx pillow
    python build_avg_results_pptx.py
"""

import os
import re
import math
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN


# ---------------------------------------------------------------------------
# PNG discovery
# ---------------------------------------------------------------------------

INCLUDE_RE = [
    re.compile(r'mean_dff_ch\d+_[\d.]+uA_frame_grid\.png$', re.I),       # step 5A
    re.compile(r'mean_dff_m1_ch\d+_[\d.]+uA_frame_grid\.png$', re.I),    # step 5B
    re.compile(r'thresh_.*_frame_grid\.png$', re.I),
    re.compile(r'consensus_.*_frame_grid\.png$', re.I),
    re.compile(r'consensus_.*_region\.png$', re.I),
    re.compile(r'rawF_ch\d+_[\d.]+uA_AVERAGE\.png$', re.I),
]

EXCLUDE_RE = [
    re.compile(r'pixel_r\d+_c\d+', re.I),
    re.compile(r'sma_alignment', re.I),
    re.compile(r'baseline_drift', re.I),
]


def _is_included(name):
    if any(p.search(name) for p in EXCLUDE_RE):
        return False
    return any(p.search(name) for p in INCLUDE_RE)


def collect_pngs(root):
    found = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith('.png') and _is_included(fn):
                found.append(os.path.join(dirpath, fn))
    return found


# ---------------------------------------------------------------------------
# Channel / current extraction
# ---------------------------------------------------------------------------

_CH_CUR_RE = re.compile(r'ch(\d+)_([\d.]+)uA', re.I)


def extract_ch_cur(path):
    """Return (channel: int, current: float) from any path component, or (None, None)."""
    for part in reversed(Path(path).parts):
        m = _CH_CUR_RE.search(part)
        if m:
            return int(m.group(1)), float(m.group(2))
    return None, None


# ---------------------------------------------------------------------------
# Step classification
# ---------------------------------------------------------------------------

_C2_TAG_RE = re.compile(r'_c\d+_(frame_grid|region)\.png$', re.I)


def _classify(fname):
    """Return (sort_order: int, label: str) for a PNG filename."""
    n = os.path.basename(fname).lower()
    if n.startswith('mean_dff_m1'):
        return (0, '5B – mean dF/F (Method 1)')
    if n.startswith('mean_dff'):
        return (1, '5A – mean dF/F (Method 0)')
    if n.startswith('rawf') and 'average' in n:
        return (2, 'raw-F (0 µA avg)')
    if n.startswith('thresh') and '_m1' not in n:
        return (3, '7A – thresh (Method 0)')
    if n.startswith('thresh') and '_m1' in n:
        return (4, '7B – thresh (Method 1)')
    if 'consensus' in n and _C2_TAG_RE.search(n) and 'frame_grid' in n:
        return (5, '7C2 – thresholded frame-grid')
    if 'consensus' in n and _C2_TAG_RE.search(n) and 'region' in n:
        return (6, '7C2 – thresholded region')
    if 'consensus' in n and 'frame_grid' in n:
        return (7, '7C/D – consensus frame-grid')
    if 'consensus' in n and 'region' in n:
        return (8, '7C/D – consensus region')
    return (9, 'result')


# ---------------------------------------------------------------------------
# PPTX slide builder — one slide, N images in a grid
# ---------------------------------------------------------------------------

# Slide constants (inches)
_SLIDE_W   = 13.333
_SLIDE_H   = 7.5
_TITLE_H   = 0.55   # height reserved for the slide title at top
_MARGIN    = 0.10   # left/right outer margin
_H_GAP     = 0.10   # horizontal gap between columns
_V_GAP     = 0.10   # vertical gap between rows
_LABEL_H   = 0.28   # height of the per-image current label
_N_COLS    = 3      # fixed column count


def _image_ar(png):
    """Return width/height aspect ratio of a PNG (falls back to 16/9)."""
    try:
        from PIL import Image as PILImage
        w, h = PILImage.open(png).size
        return w / h
    except Exception:
        return 16 / 9


def add_grid_slide(prs, slide_title, images_with_labels):
    """
    Add one slide containing multiple images arranged in a 3-column grid.

    images_with_labels : list of (label_str, png_path) sorted by current
    """
    n = len(images_with_labels)
    if n == 0:
        return

    n_cols = min(_N_COLS, n)
    n_rows = math.ceil(n / n_cols)

    grid_w = _SLIDE_W - 2 * _MARGIN
    grid_h = _SLIDE_H - _TITLE_H - _MARGIN
    cell_w = (grid_w - (n_cols - 1) * _H_GAP) / n_cols
    cell_h = (grid_h - (n_rows - 1) * _V_GAP) / n_rows
    img_h  = cell_h - _LABEL_H   # image area height within each cell

    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Slide title
    tb = slide.shapes.add_textbox(
        Inches(_MARGIN), Inches(0.05),
        Inches(_SLIDE_W - 2 * _MARGIN), Inches(_TITLE_H - 0.05),
    )
    para = tb.text_frame.paragraphs[0]
    para.alignment = PP_ALIGN.LEFT
    run = para.add_run()
    run.text = slide_title
    run.font.size = Pt(20)
    run.font.bold = True
    run.font.color.rgb = RGBColor(0x20, 0x20, 0x20)

    for idx, (cur_label, png) in enumerate(images_with_labels):
        row = idx // n_cols
        col = idx % n_cols

        cell_x = _MARGIN + col * (cell_w + _H_GAP)
        cell_y = _TITLE_H + row * (cell_h + _V_GAP)

        # Current label above the image
        lbl_tb = slide.shapes.add_textbox(
            Inches(cell_x), Inches(cell_y),
            Inches(cell_w), Inches(_LABEL_H),
        )
        lp = lbl_tb.text_frame.paragraphs[0]
        lp.alignment = PP_ALIGN.CENTER
        lr = lp.add_run()
        lr.text = cur_label
        lr.font.size = Pt(13)
        lr.font.bold = True
        lr.font.color.rgb = RGBColor(0x33, 0x33, 0x33)

        # Image — fit inside cell image area, preserve aspect ratio, centred
        ar = _image_ar(png)
        w = Inches(cell_w)
        h = w / ar
        if h > Inches(img_h):
            h = Inches(img_h)
            w = h * ar
        x = Inches(cell_x) + (Inches(cell_w) - w) // 2
        y = Inches(cell_y + _LABEL_H) + (Inches(img_h) - h) // 2
        slide.shapes.add_picture(png, x, y, width=w, height=h)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    tk.Tk().withdraw()

    root = filedialog.askdirectory(title='Select folder containing step-result subfolders')
    if not root:
        print('No folder selected. Exiting.')
        return

    print(f'Scanning: {root}')
    pngs = collect_pngs(root)

    if not pngs:
        messagebox.showerror(
            'No images found',
            f'No recognised result PNGs found under:\n{root}\n\n'
            'Expected outputs from steps 5A, 9A, 9B, 9C, or 9D.',
        )
        return

    # Parse every PNG → (step_sort, step_label, channel, current)
    parsed = []
    skipped = []
    for p in pngs:
        ch, cur = extract_ch_cur(p)
        if ch is None:
            skipped.append(p)
            continue
        s_ord, s_lbl = _classify(p)
        parsed.append((s_ord, s_lbl, ch, cur, p))

    if skipped:
        print(f'Skipped {len(skipped)} PNG(s) — could not parse channel/current:')
        for u in skipped[:20]:
            print(f'  {u}')

    if not parsed:
        messagebox.showerror(
            'Cannot parse channel/current',
            'Found PNGs but could not extract channel/current from any path.\n'
            'Check that subfolders contain "ch{N}_{I}uA" in their name.',
        )
        return

    # Group by (step_sort, step_label, channel); within each group sort by current
    from collections import defaultdict
    groups = defaultdict(list)
    for s_ord, s_lbl, ch, cur, p in parsed:
        groups[(s_ord, s_lbl, ch)].append((cur, p))

    for key in groups:
        groups[key].sort(key=lambda x: x[0])   # sort by current

    prs = Presentation()
    prs.slide_width  = Inches(_SLIDE_W)
    prs.slide_height = Inches(_SLIDE_H)

    n_slides = 0
    for (s_ord, s_lbl, ch) in sorted(groups, key=lambda k: (k[0], k[2])):
        entries = groups[(s_ord, s_lbl, ch)]   # list of (current, png_path)
        slide_title = f'Channel {ch}  |  {s_lbl}'
        images_with_labels = [(f'{cur:g} µA', p) for cur, p in entries]

        add_grid_slide(prs, slide_title, images_with_labels)
        n_slides += 1
        currents_str = ', '.join(f'{c:g}' for c, _ in entries)
        print(f'  [slide {n_slides:3d}]  {slide_title}  ({currents_str} µA)')

    out_path = os.path.join(root, 'avg_results_summary.pptx')
    prs.save(out_path)
    print(f'\nSaved {n_slides} slides → {out_path}')
    messagebox.showinfo('Done', f'Saved {n_slides} slides to:\n{out_path}')


if __name__ == '__main__':
    main()
