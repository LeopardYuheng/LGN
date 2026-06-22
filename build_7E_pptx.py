"""
build_7E_pptx.py
-----------------
Folder picker → scans for sustained_*_region.png files produced by step 7_E,
groups them by channel, and assembles one PowerPoint deck.

Layout: one slide per channel, showing all current levels as a 3-column ×
2-row grid. Each cell is labelled with the current level.

Usage:
    pip install python-pptx pillow
    python build_7E_pptx.py
"""

import os
import re
import math
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN


# ---------------------------------------------------------------------------
# PNG discovery
# ---------------------------------------------------------------------------

_REGION_RE = re.compile(r'^sustained_.*_region\.png$', re.I)
_CH_CUR_RE = re.compile(r'ch(\d+)_([\d.]+)uA', re.I)


def collect_pngs(root: str):
    found = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if _REGION_RE.match(fn):
                found.append(os.path.join(dirpath, fn))
    return found


def extract_ch_cur(path: str):
    """Return (channel: int, current: float) from any path component."""
    for part in reversed(Path(path).parts):
        m = _CH_CUR_RE.search(part)
        if m:
            return int(m.group(1)), float(m.group(2))
    return None, None


# ---------------------------------------------------------------------------
# Slide layout constants (inches)
# ---------------------------------------------------------------------------

_SLIDE_W  = 13.333
_SLIDE_H  = 7.5
_TITLE_H  = 0.55
_MARGIN   = 0.10
_H_GAP    = 0.10
_V_GAP    = 0.10
_LABEL_H  = 0.28
_N_COLS   = 3


def _image_ar(png: str) -> float:
    try:
        from PIL import Image as PILImage
        w, h = PILImage.open(png).size
        return w / h
    except Exception:
        return 16 / 9


def add_grid_slide(prs, slide_title: str, images_with_labels: list):
    """One slide with images in a 3-column grid, each labelled."""
    n = len(images_with_labels)
    if n == 0:
        return

    n_cols = min(_N_COLS, n)
    n_rows = math.ceil(n / n_cols)

    grid_w = _SLIDE_W - 2 * _MARGIN
    grid_h = _SLIDE_H - _TITLE_H - _MARGIN
    cell_w = (grid_w - (n_cols - 1) * _H_GAP) / n_cols
    cell_h = (grid_h - (n_rows - 1) * _V_GAP) / n_rows
    img_h  = cell_h - _LABEL_H

    slide = prs.slides.add_slide(prs.slide_layouts[6])

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

    for idx, (label, png) in enumerate(images_with_labels):
        row = idx // n_cols
        col = idx % n_cols

        cell_x = _MARGIN + col * (cell_w + _H_GAP)
        cell_y = _TITLE_H + row * (cell_h + _V_GAP)

        lbl_tb = slide.shapes.add_textbox(
            Inches(cell_x), Inches(cell_y),
            Inches(cell_w), Inches(_LABEL_H),
        )
        lp = lbl_tb.text_frame.paragraphs[0]
        lp.alignment = PP_ALIGN.CENTER
        lr = lp.add_run()
        lr.text = label
        lr.font.size = Pt(13)
        lr.font.bold = True
        lr.font.color.rgb = RGBColor(0x33, 0x33, 0x33)

        ar = _image_ar(png)
        w  = Inches(cell_w)
        h  = w / ar
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

    root = filedialog.askdirectory(title='Select folder containing step 7_E result subfolders')
    if not root:
        print('No folder selected. Exiting.')
        return

    print(f'Scanning: {root}')
    pngs = collect_pngs(root)

    if not pngs:
        messagebox.showerror(
            'No images found',
            f'No sustained_*_region.png files found under:\n{root}\n\n'
            'Run run_7E_batch.py first to generate the results.',
        )
        return

    # Group by channel; within each channel sort by current
    groups: dict[int, list] = {}
    skipped = []
    for p in pngs:
        ch, cur = extract_ch_cur(p)
        if ch is None:
            skipped.append(p)
            continue
        groups.setdefault(ch, []).append((cur, p))

    if skipped:
        print(f'Skipped {len(skipped)} PNG(s) — could not parse channel/current:')
        for u in skipped[:10]:
            print(f'  {u}')

    if not groups:
        messagebox.showerror(
            'Cannot parse channel/current',
            'Found PNGs but could not extract channel/current from any path.',
        )
        return

    prs = Presentation()
    prs.slide_width  = Inches(_SLIDE_W)
    prs.slide_height = Inches(_SLIDE_H)

    n_slides = 0
    for ch in sorted(groups):
        entries = sorted(groups[ch], key=lambda x: x[0])   # sort by current
        slide_title = f'Channel {ch}  |  Step 7_E — Sustained & latency-consistent region'
        images_with_labels = [(f'{cur:g} µA', p) for cur, p in entries]

        add_grid_slide(prs, slide_title, images_with_labels)
        n_slides += 1
        currents_str = ', '.join(f'{c:g}' for c, _ in entries)
        print(f'  [slide {n_slides:3d}]  Ch {ch}  ({currents_str} µA)')

    out_path = os.path.join(root, '7E_sustained_region_summary.pptx')
    prs.save(out_path)
    print(f'\nSaved {n_slides} slides → {out_path}')
    messagebox.showinfo('Done', f'Saved {n_slides} slides to:\n{out_path}')


if __name__ == '__main__':
    main()