#!/usr/bin/env python3
"""vt3_splash.py <out.c> [preview.png] [--labels start|literal]: draws the Quest
start-up screen for Virtua Tennis 3 (VR edition) and writes it as a deflated
RGBA image in C for host_xr.c's splash (splash_art.c).

Release rule (owner, 2026-11-12): everything drawn here is our own art - no
Sega logo, texture or font. The game's own title logo is NOT in this file:
the panel leaves a place for it (lg_splash_logo_at), and at start-up
host_xr.c reads the logo from the player's game files and composites it
there with our "VR" tag after it (lindberghrecomp/src/runtime/
splash_logo.c). Without readable game files our own text title "VIRTUA
TENNIS 3" + the tag goes there instead.

Typeface: Inter (variable, OFL 1.1, quest/tools/fonts/Inter.ttf + OFL.txt) -
one family for everything; no system font (2026-11-13: the DIN / Avenir
Next Apple fonts of the first version could not be released).

Design (owner, 2026-11-12 / -13): minimal and spacious; the logo with a small
orange "VR" tag at its top right (superscript: the tag's top on the logo's
top - the top of the "3" - just right of the logo's drawn right edge; the
orange is the logo's own swoosh orange, sampled ~(240, 90, 16), navy
letters); a left and a right controller drawn as thin lines (our own
simplified drawings) with callouts to the controls (xr_controls.c
lever_buttons: either hand alike - trigger top spin, A / X slice, B / Y lob,
thumbstick move and click = Start; the left controller's menu button opens
the settings). Both hands' shots are one legend in the middle between the
controllers - TOP SPIN / LOB / SLICE, top to bottom, a level leader to each
hand's trigger / button; outside only MOVE (both sticks) and SETTINGS (the
left menu button). One line per label, no grey sub-lines (owner, 2026-11-13);
--labels start (committed) labels the sticks "MOVE \u00b7 START" so the stick
click = Start stays on screen, --labels literal just "MOVE". At the bottom
the word LOADING tied to a thin line that fills with the loading time, a
small tennis ball riding on its end.
Size scale (px on the 1536 x 864 panel, 1.8 m wide at 2 m - ~32 px per
degree): tag 46 high (cap 24), action labels 26 (caps, +8 % tracking),
LOADING 15 (caps, +30 % tracking). Margins >= 96 px at the sides, the bar
55 px above the bottom edge.

The image is an atlas, top to bottom:
  the panel, PANEL_W x PANEL_H
  a row of cells, CELL_W x CELL_H: cell 10 is the line's solid colour
  a row of parts: the VR tag, the fallback title, the ball
Needs Pillow."""
import os, sys, zlib, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

LABELS = 'start'                # committed: the sticks read "MOVE \u00b7 START"; 'literal' = just "MOVE"
args = []
it = iter(sys.argv[1:])
for a in it:
    if a == '--labels':
        LABELS = next(it)
    else:
        args.append(a)
assert LABELS in ('start', 'literal'), LABELS

PANEL_W, PANEL_H = 1536, 864
CELL_W, CELL_H = 64, 96
PARTS_H = 260
W, H = PANEL_W, PANEL_H + CELL_H + PARTS_H

FONT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts', 'Inter.ttf')
def inter(size, weight, slant=0):
    f = ImageFont.truetype(FONT_FILE, int(round(size)))
    f.set_variation_by_axes([weight, slant])
    return f

ACT_F = inter(26, 700)          # TOP SPIN
LOAD_F = inter(15, 600)         # LOADING
BTN_F = inter(15, 650)          # the A / B / X / Y on the drawings

# the game's own colours (its title screen: navy, chrome white, ball lime)
BG0, BG1 = (12, 26, 62), (3, 7, 20)
LIME = (200, 222, 72)
WHITE = (236, 242, 250)
LINE = (150, 168, 200)
DIM = (104, 120, 152)
FAINT = (40, 56, 96)
NAVY = (8, 18, 46)
ORANGE = (240, 90, 16)          # the logo's swoosh orange (sampled ~(240, 84-96, 16)): the VR tag

img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
panel = Image.new('RGBA', (PANEL_W, PANEL_H), BG1 + (255,))
d = ImageDraw.Draw(panel)
for y in range(PANEL_H):
    t = y / PANEL_H
    d.line([(0, y), (PANEL_W, y)], fill=tuple(int(BG0[k] * (1 - t) + BG1[k] * t) for k in range(3)) + (255,))


# ---------------------------------------------------------------- text with tracking
def tracked_width(text, f, track):
    return sum(f.getlength(c) for c in text) + track * f.size * (len(text) - 1)

def tracked(dr, x, y, text, f, fill, track=0.0, align='l', anchor='s'):
    """text on baseline y (anchor 's') or top y ('a'), letter-spaced by track x the size; align l / r / m at x"""
    w = tracked_width(text, f, track)
    x = x - w if align == 'r' else x - w / 2 if align == 'm' else x
    for c in text:
        dr.text((x, y), c, font=f, fill=fill, anchor='l' + anchor)
        x += f.getlength(c) + track * f.size


# ---------------------------------------------------------------- the VR tag, the fallback title
TAG_H = 46
def vr_tag():
    """a small tag: orange rounded rectangle, "VR" in navy Inter ExtraBold, optically centred; cropped
    tight (its top edge is what lines up with the logo's top)"""
    SS = 4
    f = inter(33 * SS, 800)
    tw = tracked_width('VR', f, 0.04)
    cap = f.getbbox('V', anchor='ls')
    caph = -cap[1]
    h = TAG_H * SS
    padx = 15 * SS
    w = int(tw + 2 * padx)
    t = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    td = ImageDraw.Draw(t)
    td.rounded_rectangle([0, 0, w - 1, h - 1], radius=8 * SS, fill=ORANGE + (255,))
    tracked(td, padx, (h + caph) / 2, 'VR', f, NAVY + (255,), 0.04)
    return t.resize((w // SS, h // SS), Image.LANCZOS)

def title_text():
    """our own title when the game's logo cannot be read: VIRTUA TENNIS 3 in Inter Black, slanted, white"""
    f = inter(92, 900, -10)
    bb = ImageDraw.Draw(Image.new('L', (1, 1))).textbbox((0, 0), 'VIRTUA TENNIS 3', font=f)
    w, h = bb[2] - bb[0] + 24, bb[3] - bb[1] + 24
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).text((12 - bb[0], 12 - bb[1]), 'VIRTUA TENNIS 3', font=f, fill=255)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sh = Image.new('RGBA', (w, h), (0, 0, 0, 255)); sh.putalpha(m.filter(ImageFilter.GaussianBlur(4)).point(lambda v: v * 150 // 255))
    out.alpha_composite(sh, (0, 3))
    body = Image.new('RGBA', (w, h), WHITE + (255,)); body.putalpha(m)
    out.alpha_composite(body)
    bb = out.getbbox()
    return out.crop(bb), m.getbbox()[1] - bb[1]        # the picture, its lettering's top in it


# ---------------------------------------------------------------- a controller, thin lines (our own drawing)
def controller(cx, cy, s, left):
    """A Quest-style controller seen from above, simplified: a rounded head,
    the handle below it, the trigger as a tab behind the head's top edge,
    the thumbstick on the outer side, the two buttons on the inner side (and
    the left one's menu button under them). s = scale (1 = ~320 px tall).
    Returns the controls' anchor points."""
    k = -1 if left else 1               # outer side: -1 left, +1 right
    lw = max(2, int(3 * s))
    P = lambda x, y: (cx + x * s, cy + y * s)
    d.rounded_rectangle([*P(-34, -132), *P(34, -100)], radius=14 * s, outline=LIME + (255,), width=lw, fill=BG0 + (255,))
    d.rounded_rectangle([*P(-100 + 8 * k, -112), *P(100 + 8 * k, 46)], radius=78 * s, outline=LINE + (255,), width=lw, fill=BG0 + (255,))
    hb = [P(-46, 36), P(46, 36), P(34 + 22 * k, 168), P(-34 + 22 * k, 168)]
    d.line([hb[0], hb[3]], fill=LINE + (255,), width=lw)
    d.line([hb[1], hb[2]], fill=LINE + (255,), width=lw)
    d.arc([*P(-34 + 22 * k, 146), *P(34 + 22 * k, 190)], 0, 180, fill=LINE + (255,), width=lw)
    sx, sy = 40 * k, -40
    d.ellipse([*P(sx - 30, sy - 30), *P(sx + 30, sy + 30)], outline=LIME + (255,), width=lw)
    d.ellipse([*P(sx - 15, sy - 15), *P(sx + 15, sy + 15)], outline=LINE + (255,), width=max(1, lw - 1))
    names = ('X', 'Y') if left else ('A', 'B')
    lo, up = P(-38 * k, -6), P(-24 * k, -58)
    br = 17 * s
    for (x, y), n in ((lo, names[0]), (up, names[1])):
        d.ellipse([x - br, y - br, x + br, y + br], outline=LIME + (255,), width=lw)
        d.text((x, y + 1), n, font=BTN_F, fill=WHITE + (255,), anchor='mm')
    marks = {'trigger': P(0, -121), 'stick': P(sx, sy), 'lower': lo, 'upper': up, 'r_btn': br, 'r_stick': 30 * s}
    if left:
        mx, my = P(-6, 26)
        mr = 10 * s
        d.ellipse([mx - mr, my - mr, mx + mr, my + mr], outline=LIME + (255,), width=max(1, lw - 1))
        for j in (-3, 0, 3):
            d.line([(mx - 5 * s, my + j * s), (mx + 5 * s, my + j * s)], fill=WHITE + (255,), width=max(1, int(1.5 * s)))
        marks['menu'] = (mx, my)
    else:
        mx, my = P(6, 26)                              # the system button: drawn, not used
        d.ellipse([mx - 9 * s, my - 9 * s, mx + 9 * s, my + 9 * s], outline=DIM + (255,), width=max(1, lw - 1))
    return marks


LEADER_W = 2


# ---------------------------------------------------------------- parts: VR tag, fallback title, ball
vr = vr_tag()
VR_W, VR_H = vr.size
t1, t1_top = title_text()
TITLE_GAP = 14
TITLE_W, TITLE_H = t1.size[0] + TITLE_GAP + VR_W, t1.size[1]
title = Image.new('RGBA', (TITLE_W, TITLE_H), (0, 0, 0, 0))
title.alpha_composite(t1, (0, 0))
title.alpha_composite(vr, (t1.size[0] + TITLE_GAP, t1_top))     # superscript: the tag's top on the lettering's top

BALL, SS = 30, 8
bimg = Image.new('RGBA', (BALL * SS, BALL * SS), (0, 0, 0, 0))
bd = ImageDraw.Draw(bimg)
R = BALL * SS / 2 - 2
bd.ellipse([2, 2, BALL * SS - 2, BALL * SS - 2], fill=LIME + (255,))
for s_ in (-1, 1):
    o = BALL * SS / 2 + s_ * R * 1.3
    bd.ellipse([o - R, BALL * SS / 2 - R * 1.08, o + R, BALL * SS / 2 + R * 1.08], outline=(250, 252, 240, 255), width=int(R * .14))
m = Image.new('L', bimg.size, 0); ImageDraw.Draw(m).ellipse([2, 2, BALL * SS - 2, BALL * SS - 2], fill=255)
bimg.putalpha(ImageChops.multiply(bimg.getchannel('A'), m))
bimg = bimg.rotate(-25, resample=Image.BICUBIC).resize((BALL, BALL), Image.LANCZOS)


# ---------------------------------------------------------------- the layout (centre stage)
# Both hands play alike and their shot controls face each other: TOP SPIN, LOB
# and SLICE are one legend in the middle between the controllers, top to
# bottom in the order of the controls (trigger, upper button, lower button),
# each with a level leader to either hand (the button letters are on the
# drawings); outside only what is not shared - MOVE on both sticks, SETTINGS
# on the left menu button - one row per control, on its own height.
def radius(marks, key):
    return {'trigger': 34 * SC, 'stick': marks['r_stick'], 'lower': marks['r_btn'], 'upper': marks['r_btn'], 'menu': 10 * SC}[key]   # trigger: the tab's side

def leader(x0, y0, x1, y1, dot=True):
    d.line([(x0, y0), (x1, y1)], fill=DIM + (255,), width=LEADER_W)
    if dot: d.ellipse([x1 - 3, y1 - 3, x1 + 3, y1 + 3], fill=LIME + (255,))

def side_label(pt, r, label_x, act, side):
    """a level leader from the control to its label (side -1: label left of label_x, right-aligned)"""
    x, y = pt
    end = label_x - 14 * side
    leader(x + side * (r + 5), y, end, y)
    tracked(d, label_x, y + 9, act, ACT_F, LIME + (255,), 0.08, 'r' if side < 0 else 'l')   # caps: baseline 9 under -> centred

# the game's logo (908 x 388, cropped to its drawn pixels by splash_logo.c) fits 640 x 273 here, its
# top (the top of the "3") on the place's top. host_xr.c / splash_logo.c put the tag's bottom at
# lg_splash_vr_at[1] from the fitted logo's bottom and its drawn left edge lg_splash_vr_at[0] after the
# logo's right edge (the drawn group logo + gap + tag centred by measured pixels): the tag's top on
# the logo's top, a gap after the "3"'s right edge
LOGO_AT = (448, 52, 640, 274)
LOGO_FH = LOGO_AT[2] * 388 // 908                       # 273, as splash_logo.c fits it
TAG_GAP, TAG_TOP = 12, 2
VR_AT = (TAG_GAP, TAG_TOP + VR_H - LOGO_FH)
TITLE_AT = ((PANEL_W - TITLE_W) // 2, 52 + (274 - TITLE_H) // 2)
SC = .9                                                 # the controllers' scale
cy = 540
HALF = 196                                              # the controllers' centres from the panel's centre
L = controller(PANEL_W / 2 - HALF, cy, SC, True)
Rm = controller(PANEL_W / 2 + HALF, cy, SC, False)
OUT = 150                                               # the outer labels' edges from the controllers' centres
LX, RX = PANEL_W / 2 - HALF - OUT, PANEL_W / 2 + HALF + OUT
MOVE = 'MOVE \u00b7 START' if LABELS == 'start' else 'MOVE'
side_label(L['stick'], radius(L, 'stick'), LX, MOVE, -1)
side_label(L['menu'], radius(L, 'menu'), LX, 'SETTINGS', -1)
side_label(Rm['stick'], radius(Rm, 'stick'), RX, MOVE, 1)
for key, act in (('trigger', 'TOP SPIN'), ('upper', 'LOB'), ('lower', 'SLICE')):   # the shared legend
    (xl, yl), (xr, yr) = L[key], Rm[key]
    y = (yl + yr) / 2
    w = tracked_width(act, ACT_F, 0.08)
    tracked(d, PANEL_W / 2, y + 9, act, ACT_F, LIME + (255,), 0.08, 'm')
    leader(PANEL_W / 2 - w / 2 - 12, y, xl + radius(L, key) + 5, yl, False)
    leader(PANEL_W / 2 + w / 2 + 12, y, xr - radius(Rm, key) - 5, yr, False)
BAR = (568, 806, 968, 809)
tracked(d, PANEL_W // 2, BAR[1] - 16, 'LOADING', LOAD_F, DIM + (255,), 0.30, 'm')
d.rectangle([BAR[0], BAR[1], BAR[2], BAR[3]], fill=FAINT + (255,))
img.alpha_composite(panel, (0, 0))

# the cells row: cell 10 = the line's colour (no digits: lg_splash_digits height 0)
ImageDraw.Draw(img).rectangle([10 * CELL_W + 8, PANEL_H + 8, 11 * CELL_W - 8, PANEL_H + CELL_H - 8], fill=LIME + (255,))

PY = PANEL_H + CELL_H
assert VR_H <= PARTS_H and TITLE_H <= PARTS_H and VR_W + TITLE_W + BALL + 24 <= W, (VR_W, VR_H, TITLE_W, TITLE_H)
VR = (0, PY, VR_W, VR_H)
TITLE = (VR_W + 8, PY, TITLE_W, TITLE_H)
BALLR = (VR_W + 8 + TITLE_W + 8, PY, BALL, BALL)
img.alpha_composite(vr, VR[:2]); img.alpha_composite(title, TITLE[:2]); img.alpha_composite(bimg, BALLR[:2])

raw = img.tobytes()
z = zlib.compress(raw, 9)
with open(args[0], 'w') as f:
    f.write('/* Generated by quest/tools/vt3_splash.py (labels %s; typeface Inter, OFL) - original artwork for the\n' % LABELS)
    f.write(' * Quest start-up screen (host_xr.c). Do not edit; run the script.\n'
            ' * No game art: the title logo is read from the player\'s game files at\n'
            ' * start-up and composited into lg_splash_logo_at (splash_logo.c). */\n')
    f.write('#include <stddef.h>\n')
    f.write(f'const int lg_splash_w = {W}, lg_splash_h = {H}, lg_splash_panel_h = {PANEL_H};\n')
    f.write(f'const int lg_splash_cell[2] = {{ {CELL_W}, {CELL_H} }};\n')
    f.write('const int lg_splash_digits[3] = { 0, 0, 0 };   /* no countdown digits */\n')
    f.write(f'const int lg_splash_bar[4] = {{ {BAR[0]}, {BAR[1]}, {BAR[2]}, {BAR[3]} }};\n')
    f.write(f'const int lg_splash_ball[4] = {{ {BALLR[0]}, {BALLR[1]}, {BALLR[2]}, {BALLR[3]} }};   /* rides on the line\'s end */\n')
    f.write(f'const int lg_splash_logo_at[4] = {{ {LOGO_AT[0]}, {LOGO_AT[1]}, {LOGO_AT[2]}, {LOGO_AT[3]} }};   /* the logo\'s place: x, y, w, h */\n')
    f.write(f'const int lg_splash_vr[4] = {{ {VR[0]}, {VR[1]}, {VR[2]}, {VR[3]} }};   /* the VR tag in the atlas */\n')
    f.write(f'const int lg_splash_vr_at[2] = {{ {VR_AT[0]}, {VR_AT[1]} }};   /* the tag\'s drawn left edge after the fitted logo\'s right edge, its bottom from the logo\'s bottom (top on the logo\'s top) */\n')
    f.write(f'const int lg_splash_title[4] = {{ {TITLE[0]}, {TITLE[1]}, {TITLE[2]}, {TITLE[3]} }};   /* our own title in the atlas */\n')
    f.write(f'const int lg_splash_title_at[2] = {{ {TITLE_AT[0]}, {TITLE_AT[1]} }};   /* where it goes without the logo */\n')
    f.write('const char lg_splash_logo_file[] = "resource/sprite/I_ADV_titlelogo_us_KB.abr";   /* the player\'s, in the game folder */\n')
    f.write(f'const size_t lg_splash_zlen = {len(z)};\n')
    f.write('const unsigned char lg_splash_z[] = {\n')
    for i in range(0, len(z), 24):
        f.write(''.join(f'{b},' for b in z[i:i + 24]) + '\n')
    f.write('};\n')
print(f'labels {LABELS}: {W}x{H}, {len(raw)} bytes -> {len(z)} deflated')
if len(args) > 1:       # the panel without game files (our title), the line at 40 %
    prev = img.crop((0, 0, PANEL_W, PANEL_H))
    prev.alpha_composite(title, TITLE_AT)
    x1 = BAR[0] + (BAR[2] - BAR[0]) * .4
    ImageDraw.Draw(prev).rectangle([BAR[0], BAR[1], x1, BAR[3]], fill=LIME + (255,))
    prev.alpha_composite(bimg, (int(x1 - BALL / 2), int((BAR[1] + BAR[3]) / 2 - BALL / 2)))
    prev.save(args[1])
