"""
make_pipeline_pptx.py
----------------------
Generates LGN_pipeline_overview.pptx from the structure described in README.md:

  Slide 1: Whole pipeline overview (flowchart of steps 1-9)
  Slide 2: Step 4 - Pixelwise fluorescence drift analysis
  Slide 3: Step 5 - Whole-brain dF/F (Method 0 vs Method 1)
  Slide 4: Step 9 - Per-pixel significance thresholding (Method 0 vs Method 1)

Run:
    python make_pipeline_pptx.py
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR

# ==============================================================
# Colors
# ==============================================================
NAVY      = RGBColor(0x1F, 0x3A, 0x5F)
BLUE      = RGBColor(0x2E, 0x75, 0xB6)
LIGHT_BLUE= RGBColor(0xDD, 0xEB, 0xF7)
GREEN     = RGBColor(0x70, 0xAD, 0x47)
LIGHT_GRN = RGBColor(0xE2, 0xEF, 0xDA)
ORANGE    = RGBColor(0xED, 0x7D, 0x31)
LIGHT_ORG = RGBColor(0xFC, 0xE4, 0xD6)
GRAY      = RGBColor(0x7F, 0x7F, 0x7F)
LIGHT_GRY = RGBColor(0xF2, 0xF2, 0xF2)
WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
DARK      = RGBColor(0x33, 0x33, 0x33)

# ==============================================================
# Setup
# ==============================================================
prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)
BLANK = prs.slide_layouts[6]


def add_title(slide, text, subtitle=None):
    box = slide.shapes.add_textbox(Inches(0.4), Inches(0.2), Inches(12.5), Inches(0.9))
    tf = box.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    run = p.add_run()
    run.text = text
    run.font.size = Pt(30)
    run.font.bold = True
    run.font.color.rgb = NAVY
    if subtitle:
        p2 = tf.add_paragraph()
        run2 = p2.add_run()
        run2.text = subtitle
        run2.font.size = Pt(14)
        run2.font.color.rgb = GRAY
    return box


def add_box(slide, x, y, w, h, text, fill, line_color=None, font_size=12,
             bold=False, font_color=DARK, align=PP_ALIGN.CENTER):
    shp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    shp.fill.solid()
    shp.fill.fore_color.rgb = fill
    if line_color:
        shp.line.color.rgb = line_color
        shp.line.width = Pt(1.25)
    else:
        shp.line.fill.background()
    tf = shp.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.06)
    tf.margin_right = Inches(0.06)
    tf.margin_top = Inches(0.03)
    tf.margin_bottom = Inches(0.03)
    lines = text.split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        run = p.add_run()
        run.text = line
        run.font.size = Pt(font_size)
        run.font.bold = bold if i == 0 else False
        run.font.color.rgb = font_color
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    return shp


def add_arrow(slide, x1, y1, x2, y2, color=GRAY):
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    conn.line.color.rgb = color
    conn.line.width = Pt(1.5)
    conn.line.end_arrowhead = True if hasattr(conn.line, "end_arrowhead") else None
    # python-pptx doesn't directly support arrowheads via high-level API; set via XML
    from pptx.oxml.ns import qn
    ln = conn.line._get_or_add_ln()
    head = ln.makeelement(qn('a:tailEnd'), {'type': 'triangle'})
    ln.append(head)
    return conn


def add_bullets(slide, x, y, w, h, items, font_size=15, color=DARK):
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = "•  " + item
        p.font.size = Pt(font_size)
        p.font.color.rgb = color
        p.space_after = Pt(6)
    return box


# ==============================================================
# SLIDE 1 - Pipeline overview
# ==============================================================
s1 = prs.slides.add_slide(BLANK)
add_title(s1, "Widefield + Ephys Analysis Pipeline", "Overview of steps 1-9")

# Steps 1-3 (linear, top-left)
add_box(s1, 0.4, 1.2, 1.7, 0.9, "Step 1\nExtract NEV stim\n+ camera timing", LIGHT_GRY, GRAY, 11)
add_box(s1, 2.3, 1.2, 1.7, 0.9, "Step 2\nAlign widefield\nwith NEV", LIGHT_GRY, GRAY, 11)
add_box(s1, 4.2, 1.2, 1.7, 0.9, "Step 3\nBuild day\npointer/container", LIGHT_GRY, GRAY, 11)
add_arrow(s1, 2.1, 1.65, 2.3, 1.65)
add_arrow(s1, 4.0, 1.65, 4.2, 1.65)

# Step 4
add_box(s1, 6.1, 1.2, 2.0, 0.9, "Step 4\nPixelwise fluorescence\ndrift analysis", LIGHT_BLUE, BLUE, 11, bold=True)
add_arrow(s1, 5.9, 1.65, 6.1, 1.65)

# Pre-step B (brain mask) - feeds step 4 & 5
add_box(s1, 6.1, 0.05, 2.0, 0.85, "Pre-step B\nDraw brain mask\n(brain_mask.mat)", LIGHT_GRY, GRAY, 10)
add_arrow(s1, 7.1, 0.9, 7.1, 1.2)

# Branch down into Step 5 (whole brain, optional) and V1 path (6-7-8)
add_arrow(s1, 7.1, 2.1, 7.1, 2.5)
add_arrow(s1, 7.1, 2.5, 3.6, 2.5)
add_arrow(s1, 7.1, 2.5, 9.6, 2.5)
add_arrow(s1, 3.6, 2.5, 3.6, 2.7)
add_arrow(s1, 9.6, 2.5, 9.6, 2.7)

# Step 5 box (whole brain, optional)
add_box(s1, 0.7, 2.7, 5.8, 0.55, "Step 5 (optional - whole-brain analysis)\nCompute whole-brain pixelwise dF/F(x,y,t)", LIGHT_GRN, GREEN, 12, bold=True)
add_box(s1, 0.9, 3.35, 2.7, 0.85, "5_A - Method 0\nPer-trial baseline\ndF/F = (F-F_pre_trial)/F_pre_trial", WHITE, GREEN, 9.5)
add_box(s1, 3.7, 3.35, 2.7, 0.85, "5_B1 -> 5_B2 - Method 1\nGlobal baseline (F_global)\ndF/F = (F-F_global)/F_global", WHITE, GREEN, 9.5)

# V1 path: steps 6,7,8
add_box(s1, 8.6, 2.7, 4.2, 0.55, "Steps 6-7-8 (optional - V1 analysis)\nRetinotopy, relink, V1-restricted dF/F", LIGHT_ORG, ORANGE, 12, bold=True)
add_box(s1, 8.7, 3.35, 1.95, 0.85, "Step 6\nRetino align,\ndefine V1 mask", WHITE, ORANGE, 9.5)
add_box(s1, 10.75, 3.35, 1.95, 0.85, "Step 7\nRelink day pointer\nto V1 day_setup", WHITE, ORANGE, 9.5)
add_arrow(s1, 10.65, 3.775, 10.75, 3.775)

add_box(s1, 8.7, 4.3, 1.95, 0.85, "8_A - Method 0\nPer-trial baseline\n(V1-restricted)", WHITE, ORANGE, 9.5)
add_box(s1, 10.75, 4.3, 1.95, 0.85, "8_B1 -> 8_B2 - Method 1\nGlobal baseline\n(V1-restricted)", WHITE, ORANGE, 9.5)
add_arrow(s1, 9.675, 4.2, 9.675, 4.3)
add_arrow(s1, 11.725, 4.2, 11.725, 4.3)

# Step 4 (V1 version) note - dashed back arrow
add_box(s1, 6.1, 4.85, 2.0, 0.65, "Step 4 (V1 version)\nRe-run after steps 6+7", LIGHT_BLUE, BLUE, 9.5)
add_arrow(s1, 9.6, 4.85, 8.1, 5.15)

# Converge into Step 9
add_arrow(s1, 2.25, 4.2, 2.25, 5.9)
add_arrow(s1, 5.05, 4.2, 5.05, 5.9)
add_arrow(s1, 9.675, 5.15, 9.675, 5.9)
add_arrow(s1, 11.725, 5.15, 11.725, 5.9)
add_arrow(s1, 2.25, 5.9, 6.1, 5.9)
add_arrow(s1, 11.725, 5.9, 6.6, 5.9)

add_box(s1, 3.4, 5.9, 6.5, 0.55, "Step 9 (required)\nPer-pixel significance thresholding", RGBColor(0xFF, 0xF2, 0xCC), RGBColor(0xBF, 0x8F, 0x00), 13, bold=True)
add_box(s1, 3.6, 6.55, 2.9, 0.7, "9_A - Method 0\nThreshold from movie's\nown pre-stim std", WHITE, RGBColor(0xBF, 0x8F, 0x00), 10)
add_box(s1, 6.7, 6.55, 2.9, 0.7, "9_B - Method 1\nThreshold from global\nstd_dff_m1 (5_B1/8_B1)", WHITE, RGBColor(0xBF, 0x8F, 0x00), 10)
add_arrow(s1, 5.05, 6.45, 5.05, 6.55)
add_arrow(s1, 8.15, 6.45, 8.15, 6.55)

# ==============================================================
# SLIDE 2 - Step 4
# ==============================================================
s2 = prs.slides.add_slide(BLANK)
add_title(s2, "Step 4: Pixelwise Fluorescence Drift Analysis",
          "baseline_drift_analysis_4.m")

add_bullets(s2, 0.5, 1.3, 12.3, 3.0, [
    "Goal: check whether raw fluorescence F(x,y) is stable across the session, before choosing a dF/F baseline method in step 5/8.",
    "Uses every 0 uA (no-stimulation) trial, all channels pooled.",
    "For each trial, the full TIFF stack is reduced to a single mean image (one H×W data point per trial), then discarded.",
    "Per pixel, fits a linear model:  F(x,y) = slope · t_onset + intercept,  where t_onset is the trial's onset time in session-clock seconds.",
    "Computes R² in closed form from accumulated sums (single pass, no second loop).",
])

add_box(s2, 0.5, 4.1, 6.0, 1.6,
        "Outputs\n• baseline_drift_4.mat\n   (slope_map, intercept_map, r2_map)\n• baseline_drift_slope_r2.png\n• baseline_drift_summary_scatter.png",
        LIGHT_BLUE, BLUE, 13)

add_box(s2, 6.8, 4.1, 6.0, 1.6,
        "Run twice\nWhole-brain version: right after step 3,\nusing the brain mask.\n\nV1 version: after steps 6+7, restricted\nto V1 pixels (V1-aware day_setup).",
        LIGHT_ORG, ORANGE, 13)

add_box(s2, 0.5, 5.9, 12.3, 1.0,
        "Interpretation: a flat slope map and trendless scatter -> baseline is stable (Method 0, per-trial baseline, is fine).\n"
        "Significant drift -> prefer Method 1 (F_global from steps 5_B1/8_B1), which pools ~12,000 frames across the whole session.",
        LIGHT_GRN, GREEN, 13)

# ==============================================================
# SLIDE 3 - Step 5 (Method 0 vs Method 1)
# ==============================================================
s3 = prs.slides.add_slide(BLANK)
add_title(s3, "Step 5: Whole-Brain Pixelwise dF/F(x,y,t)",
          "Two baseline normalization methods - same output format, both feed step 9")

# Method 0 column
add_box(s3, 0.5, 1.3, 6.0, 0.6, "Method 0  (Step 5_A)\nPer-trial baseline", LIGHT_GRN, GREEN, 16, bold=True)
add_box(s3, 0.5, 2.0, 6.0, 1.1,
        "Definition\ndF/F(x,y,t) = [F(x,y,t) - F_pre_trial(x,y)] / F_pre_trial(x,y)\n\nF_pre_trial = mean F over THIS trial's pre-stim frames",
        WHITE, GREEN, 13)
add_bullets(s3, 0.6, 3.25, 5.8, 3.0, [
    "Each trial normalized by its own ~10-frame pre-stim window.",
    "Standard approach; does not require step 4's output.",
    "Saves per-trial movies dff_ch{N}_{I}uA_trial{K} and a trial-averaged mean_dff_movie.",
    "Best when raw F is stable within each trial but may drift slowly across the session.",
])

# Method 1 column
add_box(s3, 6.85, 1.3, 6.0, 0.6, "Method 1  (Steps 5_B1 -> 5_B2)\nGlobal baseline", LIGHT_ORG, ORANGE, 16, bold=True)
add_box(s3, 6.85, 2.0, 6.0, 1.6,
        "Definition\nStep 5_B1:  F_global(x,y) = mean F over ALL frames\nof ALL 0 uA trials (one-pass accumulation)\n\nstd_dff_m1(x,y) = std[(F-F_global)/F_global]  (used in step 9_B)\n\nStep 5_B2:  dF/F(x,y,t) = [F(x,y,t) - F_global(x,y)] / F_global(x,y)",
        WHITE, ORANGE, 12.5)
add_bullets(s3, 6.95, 3.85, 5.8, 2.4, [
    "Single session-wide baseline (~12,000 frames per pixel) instead of ~10.",
    "Same baseline used for the dF/F signal AND the step 9_B noise threshold -> self-consistent.",
    "Saves global_baseline_m1.mat, then per-trial/mean dF/F movies under method1/ch{N}_{I}uA/.",
    "Best when raw F drifts across the session (see step 4).",
])

# ==============================================================
# SLIDE 4 - Step 9 (Method 0 vs Method 1)
# ==============================================================
s4 = prs.slides.add_slide(BLANK)
add_title(s4, "Step 9: Per-Pixel Significance Thresholding",
          "Required for all paths - applies a |dF/F| > n_std · threshold mask to a dF/F movie")

# Method 0 column
add_box(s4, 0.5, 1.3, 6.0, 0.6, "Method 0  (Step 9_A)\nWithin-trial pre-stim std", LIGHT_GRN, GREEN, 16, bold=True)
add_box(s4, 0.5, 2.0, 6.0, 1.1,
        "Threshold definition\npixel_std(x,y) = std( dF/F(x,y, t<0) )\n\nsig_threshold(x,y) = n_std × pixel_std(x,y)",
        WHITE, GREEN, 13)
add_bullets(s4, 0.6, 3.25, 5.8, 3.0, [
    "Threshold computed from THIS movie's own pre-stim frames (~10 samples per pixel).",
    "Works on any dF/F movie from step 5_A or 8_A.",
    "Default n_std = 3 (~0.3% of Gaussian baseline samples cross by chance).",
    "Output tagged e.g. thresh_mean_dff_ch16_7uA_3σ.mat",
])

# Method 1 column
add_box(s4, 6.85, 1.3, 6.0, 0.6, "Method 1  (Step 9_B)\nGlobal std threshold", LIGHT_ORG, ORANGE, 16, bold=True)
add_box(s4, 6.85, 2.0, 6.0, 1.1,
        "Threshold definition\nstd_dff_m1(x,y)  <- loaded from\nglobal_baseline_m1.mat (5_B1) or\nglobal_baseline_m1_v1.mat (8_B1)\n\nsig_threshold(x,y) = n_std × std_dff_m1(x,y)",
        WHITE, ORANGE, 12.5)
add_bullets(s4, 6.95, 3.85, 5.8, 2.4, [
    "Threshold derived from ~12,000 frames of 0 uA null data per pixel, far more robust than ~10.",
    "Works on dF/F movies from step 5_B2 or 8_B2 (Method 1 dF/F).",
    "Same |dF/F| > sig_threshold logic and frame-grid/video output as Method 0.",
    "Output tagged e.g. thresh_mean_dff_m1_ch16_7uA_0.3σ_m1.mat",
])

# ==============================================================
# SLIDE 5 — Step 5_B: Drift-corrected dF/F
# ==============================================================
s5 = prs.slides.add_slide(BLANK)
add_title(s5, "Step 5_B — Drift-Corrected dF/F (Method 1)",
          "Step 4 linear model gives each trial its own time-varying baseline  ·  "
          "F_baseline(x,y) = intercept(x,y) + slope(x,y) · t_session")

# ---------------------------------------------------------------
# LEFT PANEL: session-timeline diagram  (x 0.25 – 7.75")
# ---------------------------------------------------------------
# Diagram coordinate helpers
DX0 = 0.55   # x of y-axis (left edge of plot area)
DX1 = 7.55   # x of right edge of plot area
DY0 = 1.55   # y of top  of plot area  (high F)
DY1 = 6.40   # y of bottom of plot area (low F, i.e. session start)

def lerp(a, b, t):
    return a + t * (b - a)

def drift_y(x_inch):
    """y on the drift line for a given x (linear interpolation)."""
    t = (x_inch - DX0) / (DX1 - DX0)
    return lerp(DY1, DY0, t)   # F rises from left (low) to right (high)

F_GLOBAL_Y = lerp(DY1, DY0, 0.5)   # constant F_global at session mid-point

# Plot background
bg = s5.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(0.25), Inches(1.35), Inches(7.55), Inches(5.30))
bg.fill.solid(); bg.fill.fore_color.rgb = RGBColor(0xF6, 0xF6, 0xF6)
bg.line.color.rgb = RGBColor(0xCC, 0xCC, 0xCC); bg.line.width = Pt(0.75)

# X-axis
xax = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
    Inches(DX0), Inches(DY1 + 0.10), Inches(DX1), Inches(DY1 + 0.10))
xax.line.color.rgb = DARK; xax.line.width = Pt(1.2)
# Arrow head on x-axis
from pptx.oxml.ns import qn as _qn
_ln = xax.line._get_or_add_ln()
_ln.append(_ln.makeelement(_qn('a:tailEnd'), {'type': 'none'}))
_ln.append(_ln.makeelement(_qn('a:headEnd'), {'type': 'arrow', 'w': 'sm', 'len': 'sm'}))

# X-axis label
tb = s5.shapes.add_textbox(Inches(3.0), Inches(DY1 + 0.15), Inches(3.5), Inches(0.35))
p = tb.text_frame.paragraphs[0]
p.text = "Session time  →"; p.font.size = Pt(11); p.font.color.rgb = DARK
p.alignment = PP_ALIGN.CENTER

# Y-axis
yax = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
    Inches(DX0), Inches(DY0), Inches(DX0), Inches(DY1 + 0.10))
yax.line.color.rgb = DARK; yax.line.width = Pt(1.2)

# Y-axis label
tb2 = s5.shapes.add_textbox(Inches(0.25), Inches(3.2), Inches(0.55), Inches(1.8))
tb2.text_frame.word_wrap = True
p2 = tb2.text_frame.paragraphs[0]
p2.text = "Raw F  ↑"; p2.font.size = Pt(10); p2.font.color.rgb = DARK

# ── Old constant F_global (blue dashed) ──
fg_ln = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
    Inches(DX0), Inches(F_GLOBAL_Y), Inches(DX1), Inches(F_GLOBAL_Y))
fg_ln.line.color.rgb = BLUE; fg_ln.line.width = Pt(2.0)
_fln = fg_ln.line._get_or_add_ln()
_fln.append(_fln.makeelement(_qn('a:prstDash'), {'val': 'dash'}))

tb_fg = s5.shapes.add_textbox(Inches(5.5), Inches(F_GLOBAL_Y - 0.35), Inches(2.2), Inches(0.35))
p_fg = tb_fg.text_frame.paragraphs[0]
p_fg.text = "old: constant F_global"; p_fg.font.size = Pt(9.5)
p_fg.font.italic = True; p_fg.font.color.rgb = BLUE

# ── New drift line (orange solid, going bottom-left → top-right) ──
dr_ln = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
    Inches(DX0), Inches(DY1), Inches(DX1), Inches(DY0))
dr_ln.line.color.rgb = ORANGE; dr_ln.line.width = Pt(2.5)

tb_dr = s5.shapes.add_textbox(Inches(3.7), Inches(DY0 - 0.05), Inches(3.8), Inches(0.40))
p_dr = tb_dr.text_frame.paragraphs[0]
p_dr.text = "new: F_baseline(t) = intercept + slope · t"
p_dr.font.size = Pt(10); p_dr.font.bold = True; p_dr.font.color.rgb = ORANGE

# ── Three trial markers ──
TRIAL_XS     = [1.10,   3.85,   6.80  ]
TRIAL_LABELS = ["Trial 1\n(early)", "Trial k\n(mid)", "Trial N\n(late)"]
TRIAL_COLORS = [RGBColor(0x1F, 0x7A, 0x1F),   # green  – early, low F_baseline
                RGBColor(0xAA, 0x66, 0x00),   # amber  – middle
                RGBColor(0xC0, 0x00, 0x00)]   # red    – late,  high F_baseline
FB_LABELS    = ["F_b(t₁)", "F_b(t_k)", "F_b(t_N)"]

for i, (tx, lbl, col, fbl) in enumerate(zip(TRIAL_XS, TRIAL_LABELS, TRIAL_COLORS, FB_LABELS)):
    ty = drift_y(tx)          # y of this trial's baseline on the drift line
    xax_y = DY1 + 0.10        # y of x-axis

    # Vertical dashed drop-line from x-axis up to the drift point
    vl = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
        Inches(tx), Inches(xax_y), Inches(tx), Inches(ty))
    vl.line.color.rgb = col; vl.line.width = Pt(1.0)
    _vln = vl.line._get_or_add_ln()
    _vln.append(_vln.makeelement(_qn('a:prstDash'), {'val': 'sysDash'}))

    # Horizontal reference line from y-axis to the drift point
    hl = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
        Inches(DX0), Inches(ty), Inches(tx), Inches(ty))
    hl.line.color.rgb = col; hl.line.width = Pt(0.75)
    _hln = hl.line._get_or_add_ln()
    _hln.append(_hln.makeelement(_qn('a:prstDash'), {'val': 'sysDash'}))

    # Filled circle on drift line
    DOT = 0.14
    dot = s5.shapes.add_shape(MSO_SHAPE.OVAL,
        Inches(tx - DOT/2), Inches(ty - DOT/2), Inches(DOT), Inches(DOT))
    dot.fill.solid(); dot.fill.fore_color.rgb = col; dot.line.fill.background()

    # F_baseline label on the left (y-axis)
    tb_b = s5.shapes.add_textbox(Inches(0.27), Inches(ty - 0.17), Inches(0.70), Inches(0.30))
    p_b  = tb_b.text_frame.paragraphs[0]
    p_b.text = fbl; p_b.font.size = Pt(8.5); p_b.font.color.rgb = col; p_b.font.bold = True
    p_b.alignment = PP_ALIGN.RIGHT

    # Trial label below x-axis
    tb_t = s5.shapes.add_textbox(Inches(tx - 0.55), Inches(xax_y + 0.05), Inches(1.1), Inches(0.45))
    p_t  = tb_t.text_frame.paragraphs[0]
    p_t.text = lbl; p_t.font.size = Pt(8.5); p_t.font.color.rgb = col
    p_t.alignment = PP_ALIGN.CENTER

    # Bias arrow: gap between F_global (blue dash) and per-trial F_baseline
    if i != 1:   # skip the mid trial (gap ≈ 0)
        gap_x   = tx + 0.28
        y_top   = min(ty, F_GLOBAL_Y) + 0.05
        y_bot   = max(ty, F_GLOBAL_Y) - 0.05
        if y_bot - y_top > 0.15:
            ga = s5.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
                Inches(gap_x), Inches(y_top), Inches(gap_x), Inches(y_bot))
            ga.line.color.rgb = RGBColor(0x80, 0x00, 0x80); ga.line.width = Pt(1.5)
            _galn = ga.line._get_or_add_ln()
            _galn.append(_galn.makeelement(_qn('a:headEnd'), {'type': 'arrow', 'w': 'sm', 'len': 'sm'}))
            _galn.append(_galn.makeelement(_qn('a:tailEnd'), {'type': 'arrow', 'w': 'sm', 'len': 'sm'}))
            gap_lbl = "over-corrects" if i == 0 else "under-corrects"
            tb_gap = s5.shapes.add_textbox(Inches(gap_x + 0.05), Inches((y_top + y_bot)/2 - 0.15),
                                           Inches(1.3), Inches(0.35))
            p_gap  = tb_gap.text_frame.paragraphs[0]
            p_gap.text = gap_lbl; p_gap.font.size = Pt(8.5)
            p_gap.font.color.rgb = RGBColor(0x80, 0x00, 0x80); p_gap.font.italic = True

# ── Legend note ──
add_box(s5, 0.35, 6.68, 7.35, 0.60,
        "Using constant F_global: baseline is wrong for early AND late trials — a systematic bias in dF/F\n"
        "Using drift-corrected F_baseline(t): each trial's normalisation tracks the actual fluorescence level at that moment",
        LIGHT_GRY, GRAY, 9.5)

# ---------------------------------------------------------------
# RIGHT PANEL: per-trial math  (x 8.0 – 13.1")
# ---------------------------------------------------------------
# Step 4 input
add_box(s5, 8.0, 1.35, 5.1, 0.75,
        "Step 4 output  (baseline_drift_4.mat)",
        LIGHT_BLUE, BLUE, 12, bold=True)
add_box(s5, 8.0, 2.15, 5.1, 0.85,
        "slope_map(x,y)      [ΔF / second]\nintercept_map(x,y)  [F at t = 0 s]",
        WHITE, BLUE, 11)

add_arrow(s5, 10.55, 3.05, 10.55, 3.30)

# Per-trial baseline computation
add_box(s5, 8.0, 3.30, 5.1, 0.45,
        "For each trial  (onset frame → session clock time)",
        LIGHT_ORG, ORANGE, 11, bold=True)
add_box(s5, 8.0, 3.80, 5.1, 0.55,
        "t_session = (onset_frame − 1) / Fs",
        WHITE, ORANGE, 11.5)

add_arrow(s5, 10.55, 4.40, 10.55, 4.65)

add_box(s5, 8.0, 4.65, 5.1, 0.70,
        "F_baseline(x,y)  =  intercept_map  +  slope_map × t_session",
        LIGHT_ORG, ORANGE, 11.5, bold=True)

add_arrow(s5, 10.55, 5.40, 10.55, 5.65)

# dF/F formula
add_box(s5, 8.0, 5.65, 5.1, 0.95,
        "dF/F(x,y,t)  =\n"
        "[ F(x,y,t) − F_baseline(x,y) ] / F_baseline(x,y)",
        RGBColor(0xFF, 0xF2, 0xCC), RGBColor(0xBF, 0x8F, 0x00), 12, bold=True)

# Key insight
add_box(s5, 8.0, 6.68, 5.1, 0.60,
        "Each trial is normalised by the expected fluorescence at its own\n"
        "point in session time — drift is removed before computing dF/F.",
        LIGHT_GRN, GREEN, 9.5)

# ==============================================================
prs.save("LGN_pipeline_overview.pptx")
print("Saved LGN_pipeline_overview.pptx")