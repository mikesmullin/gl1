#!/usr/bin/env python3
"""Generate a 24×24 aseprite-quality UI icon sheet + YAML manifest.

Classic solid fills + dark outlines on transparent. Cursor / hands / chevrons
are hand-authored pixel maps so directions read clearly at UI scale.
"""
from __future__ import annotations
from PIL import Image
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
CELL = 24
COLS = 8
GUTTER = 2
STRIDE = CELL + GUTTER

# Palette — slightly richer than 16px set
K  = (18, 20, 24, 255)       # outline
W  = (248, 250, 252, 255)    # white
G  = (168, 174, 186, 255)    # gray
DG = (86, 92, 104, 255)      # dark gray
A  = (72, 196, 118, 255)     # accent green
AH = (120, 220, 150, 255)    # accent highlight
B  = (88, 148, 232, 255)     # blue
BH = (140, 190, 255, 255)
Y  = (242, 198, 64, 255)     # yellow
YH = (255, 228, 120, 255)
O  = (242, 148, 56, 255)     # orange
R  = (228, 78, 78, 255)      # red
RH = (255, 130, 130, 255)
P  = (198, 118, 228, 255)    # purple
BR = (158, 108, 68, 255)     # brown
SK = (255, 214, 178, 255)    # skin (emoji only)
CY = (72, 198, 208, 255)
T  = (0, 0, 0, 0)

def blank():
    return Image.new("RGBA", (CELL, CELL), T)

def setp(im, x, y, c):
    if 0 <= x < CELL and 0 <= y < CELL and c is not None:
        im.putpixel((x, y), c)

def fill(im, x0, y0, x1, y1, c):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            setp(im, x, y, c)

def hline(im, x0, x1, y, c):
    for x in range(min(x0, x1), max(x0, x1) + 1):
        setp(im, x, y, c)

def vline(im, x, y0, y1, c):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        setp(im, x, y, c)

def rect_o(im, x0, y0, x1, y1, c):
    hline(im, x0, x1, y0, c)
    hline(im, x0, x1, y1, c)
    vline(im, x0, y0, y1, c)
    vline(im, x1, y0, y1, c)

def circle(im, cx, cy, r, fill_c=None, edge_c=K):
    r2 = r * r
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if fill_c and d2 <= r2:
                setp(im, x, y, fill_c)
            if edge_c and r2 - r * 1.2 <= d2 <= r2 + r * 0.9:
                setp(im, x, y, edge_c)

def paint(im, rows, mapping):
    """rows: list of equal-length strings; mapping char→color ('.' = empty)."""
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            c = mapping.get(ch)
            if c is not None:
                setp(im, x, y, c)

def clean_alpha(im):
    px = im.load()
    for y in range(CELL):
        for x in range(CELL):
            r, g, b, a = px[x, y]
            if a == 0:
                px[x, y] = (0, 0, 0, 0)

# ── Cursors (hotspots marked in ICONS list) ──────────────────────────────────

def draw_cursor_arrow(im):
    # Classic OS pointer, 24px — tip at (2,1)
    rows = [
        "##......................",
        "#W#.....................",
        "#WW#....................",
        "#WWW#...................",
        "#WWWW#..................",
        "#WWWWW#.................",
        "#WWWWWW#................",
        "#WWWWWWW#...............",
        "#WWWWWWWW#..............",
        "#WWWWWWWWW#.............",
        "#WWWWWWWWWW#............",
        "#WWWWW######............",
        "#WWWW#W#................",
        "#WWW#.#W#...............",
        "#WW#...#W#..............",
        "#W#.....#W#.............",
        "##.......#W#............",
        "#.........#W#...........",
        "...........#W#..........",
        "............##..........",
        "........................",
        "........................",
        "........................",
        "........................",
    ]
    paint(im, rows, {"#": K, "W": W})

def draw_hand_open(im):
    # Rounded open hand (grab) — white, black outline
    rows = [
        "........................",
        "....#..#..#..#..........",
        "...#W##W##W##W#.........",
        "...#W##W##W##W#.........",
        "...#W##W##W##W#.........",
        "...#W##W##W##W#.........",
        "...#W##W##W##W#.........",
        "...#WWWWWWWWWW#.........",
        "..#WWWWWWWWWWWW#........",
        ".#WWWWWWWWWWWWWW#.......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        ".#WWWWWWWWWWWWWW#.......",
        "..#WWWWWWWWWWWW#........",
        "...#WWWWWWWWWW#.........",
        "....#WWWWWWWW#..........",
        ".....#WWWWWW#...........",
        "......######............",
        "........................",
        "........................",
        "........................",
        "........................",
    ]
    paint(im, rows, {"#": K, "W": W})

def draw_hand_closed(im):
    # Closed fist / grip
    rows = [
        "........................",
        "......######............",
        ".....#WWWWWW#...........",
        "....#WWWWWWWW#..........",
        "...#WW#W#W#W#W#.........",
        "...#WWWWWWWWWW#.........",
        "..#WWWWWWWWWWWW#........",
        ".#WWWWWWWWWWWWWW#.......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        "#WWWWWWWWWWWWWWWW#......",
        ".#WWWWWWWWWWWWWW#.......",
        "..#WWWWWWWWWWWW#........",
        "...#WWWWWWWWWW#.........",
        "....#WWWWWWWW#..........",
        ".....#WWWWWW#...........",
        "......######............",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
    ]
    paint(im, rows, {"#": K, "W": W})

def draw_cursor_text(im):
    # I-beam
    hline(im, 6, 17, 3, K)
    hline(im, 6, 17, 4, K)
    hline(im, 6, 17, 19, K)
    hline(im, 6, 17, 20, K)
    fill(im, 11, 4, 12, 19, W)
    vline(im, 10, 4, 19, K)
    vline(im, 13, 4, 19, K)
    hline(im, 7, 9, 3, K)
    hline(im, 14, 16, 3, K)
    hline(im, 7, 9, 20, K)
    hline(im, 14, 16, 20, K)

def draw_cursor_cross(im):
    fill(im, 11, 3, 12, 20, W)
    fill(im, 3, 11, 20, 12, W)
    rect_o(im, 10, 3, 13, 20, K)
    rect_o(im, 3, 10, 20, 13, K)
    fill(im, 11, 11, 12, 12, W)

def draw_resize_h(im):
    fill(im, 6, 11, 17, 12, W)
    rect_o(im, 6, 11, 17, 12, K)
    # left head
    for i in range(5):
        fill(im, 5 - i, 11 - i, 5 - i, 12 + i, W)
        setp(im, 5 - i, 10 - i, K)
        setp(im, 5 - i, 13 + i, K)
    # right head
    for i in range(5):
        fill(im, 18 + i, 11 - i, 18 + i, 12 + i, W)
        setp(im, 18 + i, 10 - i, K)
        setp(im, 18 + i, 13 + i, K)

def draw_resize_v(im):
    fill(im, 11, 6, 12, 17, W)
    rect_o(im, 11, 6, 12, 17, K)
    for i in range(5):
        fill(im, 11 - i, 5 - i, 12 + i, 5 - i, W)
        setp(im, 10 - i, 5 - i, K)
        setp(im, 13 + i, 5 - i, K)
    for i in range(5):
        fill(im, 11 - i, 18 + i, 12 + i, 18 + i, W)
        setp(im, 10 - i, 18 + i, K)
        setp(im, 13 + i, 18 + i, K)

def draw_resize_diag(im):
    for i in range(5, 19):
        setp(im, i, i, W)
        setp(im, i + 1, i, W)
        setp(im, i, i + 1, K)
        setp(im, i - 1, i, K)
    setp(im, 4, 4, K)
    setp(im, 5, 4, K)
    setp(im, 4, 5, K)
    setp(im, 19, 19, K)
    setp(im, 18, 19, K)
    setp(im, 19, 18, K)

def draw_busy(im):
    # Hourglass
    hline(im, 6, 17, 3, K)
    hline(im, 6, 17, 4, K)
    fill(im, 7, 3, 16, 4, Y)
    hline(im, 6, 17, 19, K)
    hline(im, 6, 17, 20, K)
    fill(im, 7, 19, 16, 20, Y)
    for i in range(7):
        setp(im, 7 + i, 5 + i, K)
        setp(im, 16 - i, 5 + i, K)
        setp(im, 7 + i, 18 - i, K)
        setp(im, 16 - i, 18 - i, K)
    fill(im, 10, 8, 13, 9, YH)
    fill(im, 10, 14, 13, 15, YH)
    fill(im, 11, 11, 12, 12, Y)

# ── Arrows / chevrons (clear, symmetric) ─────────────────────────────────────

def draw_arrow(im, d):
    """Filled green arrow with outline — d in up/down/left/right."""
    if d == "down":
        fill(im, 10, 4, 13, 12, A)
        rect_o(im, 10, 4, 13, 12, K)
        for i in range(8):
            x0, x1 = 11 - i, 12 + i
            hline(im, x0, x1, 12 + i, A)
            setp(im, x0 - 1, 12 + i, K)
            setp(im, x1 + 1, 12 + i, K)
        hline(im, 3, 20, 19, K)
    elif d == "up":
        fill(im, 10, 11, 13, 19, A)
        rect_o(im, 10, 11, 13, 19, K)
        for i in range(8):
            x0, x1 = 11 - i, 12 + i
            hline(im, x0, x1, 11 - i, A)
            setp(im, x0 - 1, 11 - i, K)
            setp(im, x1 + 1, 11 - i, K)
        hline(im, 3, 20, 4, K)
    elif d == "left":
        fill(im, 11, 10, 19, 13, A)
        rect_o(im, 11, 10, 19, 13, K)
        for i in range(8):
            y0, y1 = 11 - i, 12 + i
            vline(im, 11 - i, y0, y1, A)
            setp(im, 11 - i, y0 - 1, K)
            setp(im, 11 - i, y1 + 1, K)
        vline(im, 4, 3, 20, K)
    else:  # right
        fill(im, 4, 10, 12, 13, A)
        rect_o(im, 4, 10, 12, 13, K)
        for i in range(8):
            y0, y1 = 11 - i, 12 + i
            vline(im, 12 + i, y0, y1, A)
            setp(im, 12 + i, y0 - 1, K)
            setp(im, 12 + i, y1 + 1, K)
        vline(im, 19, 3, 20, K)

def draw_chevron(im, direction, double=False):
    def one(ox):
        if direction == "left":
            for t in range(0, 3):
                # thick chevron
                for i in range(8):
                    setp(im, 15 + ox - i + t, 5 + i, A if t < 2 else K)
                    setp(im, 15 + ox - i + t, 18 - i, A if t < 2 else K)
        else:
            for t in range(0, 3):
                for i in range(8):
                    setp(im, 8 + ox + i + t, 5 + i, A if t < 2 else K)
                    setp(im, 8 + ox + i + t, 18 - i, A if t < 2 else K)
    if double:
        one(-3)
        one(3)
    else:
        one(0)

def draw_tree_collapsed(im):
    # Clear ">" chevron
    for t in range(3):
        for i in range(9):
            c = A if t < 2 else K
            setp(im, 8 + i + t, 5 + i, c)
            setp(im, 8 + i + t, 18 - i, c)

def draw_tree_expanded(im):
    # Clear "v" chevron
    for t in range(3):
        for i in range(9):
            c = A if t < 2 else K
            setp(im, 5 + i, 7 + i + t, c)
            setp(im, 18 - i, 7 + i + t, c)

def draw_tree_leaf(im):
    fill(im, 9, 9, 14, 14, G)
    rect_o(im, 9, 9, 14, 14, K)
    fill(im, 11, 11, 12, 12, A)

def draw_folder(im, open_=False):
    fill(im, 3, 8, 20, 19, Y)
    rect_o(im, 3, 8, 20, 19, K)
    fill(im, 3, 6, 11, 8, O)
    rect_o(im, 3, 6, 11, 8, K)
    fill(im, 4, 9, 19, 11, YH)
    if open_:
        fill(im, 6, 11, 21, 20, Y)
        rect_o(im, 6, 11, 21, 20, K)
        fill(im, 7, 12, 20, 14, YH)

def draw_file(im):
    fill(im, 6, 3, 17, 20, W)
    rect_o(im, 6, 3, 17, 20, K)
    # folded corner
    fill(im, 13, 3, 17, 8, G)
    vline(im, 13, 3, 8, K)
    hline(im, 13, 17, 8, K)
    for y in (11, 14, 17):
        hline(im, 9, 14, y, DG)

def draw_check(im):
    for i in range(9):
        setp(im, 5 + i, 11 + i, A)
        setp(im, 5 + i, 12 + i, A)
        setp(im, 5 + i, 10 + i, K)
        setp(im, 5 + i, 13 + i, K)
    for i in range(12):
        setp(im, 13 + i, 19 - i, A)
        setp(im, 13 + i, 18 - i, A)
        setp(im, 13 + i, 20 - i, K)
        setp(im, 13 + i, 17 - i, K)

def draw_close(im):
    for i in range(14):
        setp(im, 5 + i, 5 + i, R)
        setp(im, 5 + i, 6 + i, R)
        setp(im, 5 + i, 18 - i, R)
        setp(im, 5 + i, 17 - i, R)
        setp(im, 4 + i, 5 + i, K)
        setp(im, 5 + i, 4 + i, K)
        setp(im, 4 + i, 18 - i, K)
        setp(im, 5 + i, 19 - i, K)

def draw_plus(im):
    fill(im, 10, 5, 13, 18, A)
    fill(im, 5, 10, 18, 13, A)
    rect_o(im, 10, 5, 13, 18, K)
    rect_o(im, 5, 10, 18, 13, K)

def draw_minus(im):
    fill(im, 5, 10, 18, 13, A)
    rect_o(im, 5, 10, 18, 13, K)

def draw_search(im):
    circle(im, 10, 10, 6, W, K)
    circle(im, 10, 10, 5, W, None)
    for i in range(7):
        setp(im, 15 + i, 15 + i, K)
        setp(im, 16 + i, 15 + i, K)
        setp(im, 15 + i, 16 + i, W)

def draw_settings(im):
    # Gear-ish
    fill(im, 9, 3, 14, 20, G)
    fill(im, 3, 9, 20, 14, G)
    rect_o(im, 9, 3, 14, 20, K)
    rect_o(im, 3, 9, 20, 14, K)
    # diagonals
    for i in range(4, 20):
        setp(im, i, i, G)
        setp(im, i, 23 - i, G)
    circle(im, 11, 11, 4, DG, K)
    circle(im, 11, 11, 2, W, None)

def draw_home(im):
    # Roof
    for i in range(10):
        hline(im, 11 - i, 12 + i, 10 - i, R)
        setp(im, 10 - i, 10 - i, K)
        setp(im, 13 + i, 10 - i, K)
    fill(im, 6, 11, 17, 20, B)
    rect_o(im, 6, 11, 17, 20, K)
    fill(im, 10, 14, 13, 20, BR)
    rect_o(im, 10, 14, 13, 20, K)
    fill(im, 7, 12, 9, 14, BH)

def draw_save(im):
    fill(im, 4, 3, 19, 20, B)
    rect_o(im, 4, 3, 19, 20, K)
    fill(im, 7, 3, 16, 9, W)
    rect_o(im, 7, 3, 16, 9, K)
    fill(im, 7, 12, 17, 18, Y)
    rect_o(im, 7, 12, 17, 18, K)
    fill(im, 14, 4, 15, 7, B)

def draw_copy(im):
    fill(im, 8, 6, 19, 20, W)
    rect_o(im, 8, 6, 19, 20, K)
    fill(im, 4, 3, 15, 17, G)
    rect_o(im, 4, 3, 15, 17, K)
    hline(im, 7, 12, 8, DG)
    hline(im, 7, 12, 11, DG)

def draw_paste(im):
    fill(im, 6, 7, 17, 20, W)
    rect_o(im, 6, 7, 17, 20, K)
    fill(im, 8, 3, 15, 8, BR)
    rect_o(im, 8, 3, 15, 8, K)
    fill(im, 9, 4, 14, 6, Y)

def draw_trash(im):
    fill(im, 6, 8, 17, 20, DG)
    rect_o(im, 6, 8, 17, 20, K)
    hline(im, 5, 18, 8, K)
    hline(im, 5, 18, 7, K)
    fill(im, 9, 4, 14, 7, G)
    rect_o(im, 9, 4, 14, 7, K)
    for x in (9, 12, 15):
        vline(im, x, 11, 17, G)

def draw_eye(im):
    # Almond eye
    for x in range(3, 21):
        setp(im, x, 11, K)
        setp(im, x, 12, K)
    for x in range(4, 20):
        setp(im, x, 9, K)
        setp(im, x, 14, K)
    for x in range(5, 19):
        setp(im, x, 8, W)
        setp(im, x, 15, W)
        setp(im, x, 10, W)
        setp(im, x, 13, W)
    circle(im, 11, 11, 3, B, K)
    fill(im, 11, 11, 12, 12, K)

def draw_lock(im):
    fill(im, 7, 11, 16, 20, Y)
    rect_o(im, 7, 11, 16, 20, K)
    # shackle
    for x in range(8, 16):
        setp(im, x, 5, K)
        setp(im, x, 6, K)
    vline(im, 8, 5, 11, K)
    vline(im, 9, 5, 11, K)
    vline(im, 14, 5, 11, K)
    vline(im, 15, 5, 11, K)
    fill(im, 11, 14, 12, 17, K)

def draw_play(im):
    for y in range(4, 20):
        if y <= 11:
            w = (y - 4) * 2
        else:
            w = (19 - y) * 2
        for x in range(7, 8 + w):
            setp(im, x, y, A)
        setp(im, 7, y, K)
        setp(im, 7 + w, y, K)
    setp(im, 7, 4, K)
    setp(im, 7, 19, K)

def draw_pause(im):
    fill(im, 6, 5, 10, 18, A)
    fill(im, 13, 5, 17, 18, A)
    rect_o(im, 6, 5, 10, 18, K)
    rect_o(im, 13, 5, 17, 18, K)

def draw_warning(im):
    for y in range(3, 20):
        half = y - 3
        for x in range(11 - half, 12 + half):
            setp(im, x, y, Y)
        setp(im, 11 - half, y, K)
        setp(im, 12 + half, y, K)
    hline(im, 3, 20, 20, K)
    fill(im, 11, 8, 12, 13, K)
    fill(im, 11, 16, 12, 17, K)

def draw_info(im):
    circle(im, 11, 11, 9, B, K)
    fill(im, 10, 6, 13, 8, W)
    fill(im, 10, 10, 13, 17, W)

def draw_star(im):
    # 5-point-ish blob star
    fill(im, 10, 3, 13, 20, Y)
    fill(im, 3, 10, 20, 13, Y)
    for i in range(5, 19):
        setp(im, i, i, Y)
        setp(im, i, 23 - i, Y)
        setp(im, i + 1, i, YH)
    rect_o(im, 10, 3, 13, 20, K)
    rect_o(im, 3, 10, 20, 13, K)

# ── Emoji ────────────────────────────────────────────────────────────────────

def face(im, col=Y):
    circle(im, 11, 11, 9, col, K)
    # slight highlight
    setp(im, 7, 7, YH)
    setp(im, 8, 6, YH)

def draw_emoji_smile(im):
    face(im)
    fill(im, 7, 9, 8, 10, K)
    fill(im, 14, 9, 15, 10, K)
    for x in range(7, 16):
        setp(im, x, 15, K)
    setp(im, 7, 14, K)
    setp(im, 15, 14, K)

def draw_emoji_heart(im):
    # Two lobes + point
    circle(im, 7, 8, 5, R, K)
    circle(im, 15, 8, 5, R, K)
    for y in range(10, 21):
        half = 20 - y
        for x in range(11 - half, 12 + half):
            setp(im, x, y, R)
        setp(im, 11 - half, y, K)
        setp(im, 12 + half, y, K)
    fill(im, 8, 7, 14, 12, R)
    setp(im, 9, 6, RH)
    setp(im, 10, 5, RH)

def draw_emoji_laugh(im):
    face(im)
    hline(im, 6, 9, 9, K)
    hline(im, 14, 17, 9, K)
    fill(im, 6, 12, 17, 17, K)
    fill(im, 7, 13, 16, 16, R)
    fill(im, 8, 14, 15, 15, RH)

def draw_emoji_thumbs(im):
    fill(im, 8, 9, 17, 20, W)
    rect_o(im, 8, 9, 17, 20, K)
    fill(im, 11, 3, 16, 10, W)
    rect_o(im, 11, 3, 16, 10, K)
    fill(im, 3, 12, 8, 17, W)
    rect_o(im, 3, 12, 8, 17, K)
    fill(im, 12, 4, 14, 7, G)

def draw_emoji_fire(im):
    for y in range(3, 21):
        w = 2 + (y // 3)
        if y > 16:
            w = 22 - y + 2
        for x in range(11 - w, 12 + w):
            c = R if y < 8 else (O if y < 14 else Y)
            setp(im, x, y, c)
        setp(im, 11 - w, y, K)
        setp(im, 12 + w, y, K)
    for y in range(6, 18):
        setp(im, 11, y, YH)
        setp(im, 12, y, YH)

def draw_emoji_party(im):
    fill(im, 3, 12, 11, 20, O)
    rect_o(im, 3, 12, 11, 20, K)
    fill(im, 4, 13, 10, 15, Y)
    # streamer
    for i in range(10):
        setp(im, 11 + i, 11 - i, K)
        setp(im, 12 + i, 11 - i, P if i % 2 == 0 else A)
    for x, y, c in [(16, 3, R), (19, 5, B), (17, 7, A), (20, 4, Y), (15, 6, P)]:
        setp(im, x, y, c)
        setp(im, x + 1, y, c)

def draw_emoji_cry(im):
    face(im)
    fill(im, 7, 9, 8, 10, K)
    fill(im, 14, 9, 15, 10, K)
    fill(im, 7, 12, 8, 15, B)
    fill(im, 14, 12, 15, 15, B)
    hline(im, 8, 15, 17, K)

def draw_emoji_think(im):
    circle(im, 10, 9, 8, Y, K)
    fill(im, 6, 7, 7, 8, K)
    fill(im, 12, 7, 13, 8, K)
    hline(im, 7, 13, 12, K)
    # hand
    fill(im, 14, 14, 21, 21, W)
    rect_o(im, 14, 14, 21, 21, K)
    # dots
    setp(im, 18, 5, K)
    setp(im, 20, 3, K)
    setp(im, 21, 6, K)

def draw_emoji_clap(im):
    fill(im, 3, 7, 10, 18, W)
    rect_o(im, 3, 7, 10, 18, K)
    fill(im, 13, 7, 20, 18, W)
    rect_o(im, 13, 7, 20, 18, K)
    # spark
    vline(im, 11, 3, 6, Y)
    setp(im, 9, 4, Y)
    setp(im, 13, 4, Y)

def draw_emoji_100(im):
    fill(im, 2, 5, 21, 18, R)
    rect_o(im, 2, 5, 21, 18, K)
    # "100"
    fill(im, 4, 8, 6, 15, W)
    rect_o(im, 8, 8, 13, 15, W)
    fill(im, 9, 9, 12, 14, R)
    rect_o(im, 15, 8, 20, 15, W)
    fill(im, 16, 9, 19, 14, R)

ICONS = [
    ("cursor_arrow", ["pointer", "default", "cursor"], (2, 1), draw_cursor_arrow),
    ("cursor_hand_open", ["grab", "hand_open", "pointer_hand"], (9, 2), draw_hand_open),
    ("cursor_hand_closed", ["grabbing", "hand_closed", "grip"], (9, 3), draw_hand_closed),
    ("cursor_text", ["ibeam", "text"], (11, 2), draw_cursor_text),
    ("cursor_cross", ["crosshair"], (11, 11), draw_cursor_cross),
    ("cursor_resize_h", ["resize_ew", "col_resize"], (11, 11), draw_resize_h),
    ("cursor_resize_v", ["resize_ns", "row_resize"], (11, 11), draw_resize_v),
    ("cursor_resize_diag", ["resize_nwse"], (11, 11), draw_resize_diag),
    ("cursor_busy", ["wait", "hourglass"], (11, 11), draw_busy),
    ("arrow_down", ["v", "chevron_down"], (11, 11), lambda im: draw_arrow(im, "down")),
    ("arrow_up", ["^", "chevron_up"], (11, 11), lambda im: draw_arrow(im, "up")),
    ("arrow_left", ["<", "chevron_left"], (11, 11), lambda im: draw_arrow(im, "left")),
    ("arrow_right", [">", "chevron_right"], (11, 11), lambda im: draw_arrow(im, "right")),
    ("chevron_double_left", ["<<", "collapse_left"], (11, 11), lambda im: draw_chevron(im, "left", True)),
    ("chevron_double_right", [">>", "collapse_right"], (11, 11), lambda im: draw_chevron(im, "right", True)),
    ("tree_collapsed", ["tree_closed", "node_closed"], (11, 11), draw_tree_collapsed),
    ("tree_expanded", ["tree_open", "node_open"], (11, 11), draw_tree_expanded),
    ("tree_leaf", ["leaf", "node_leaf"], (11, 11), draw_tree_leaf),
    ("folder", ["dir"], (11, 11), lambda im: draw_folder(im, False)),
    ("folder_open", ["dir_open"], (11, 11), lambda im: draw_folder(im, True)),
    ("file", ["document", "doc"], (11, 11), draw_file),
    ("check", ["ok", "tick"], (11, 11), draw_check),
    ("close", ["x", "cancel"], (11, 11), draw_close),
    ("plus", ["add"], (11, 11), draw_plus),
    ("minus", ["remove"], (11, 11), draw_minus),
    ("search", ["find", "filter"], (11, 11), draw_search),
    ("settings", ["gear", "cog"], (11, 11), draw_settings),
    ("home", [], (11, 11), draw_home),
    ("save", ["disk"], (11, 11), draw_save),
    ("copy", [], (11, 11), draw_copy),
    ("paste", [], (11, 11), draw_paste),
    ("trash", ["delete"], (11, 11), draw_trash),
    ("eye", ["visible"], (11, 11), draw_eye),
    ("lock", [], (11, 11), draw_lock),
    ("play", [], (11, 11), draw_play),
    ("pause", [], (11, 11), draw_pause),
    ("warning", ["alert"], (11, 11), draw_warning),
    ("info", [], (11, 11), draw_info),
    ("star", ["favorite"], (11, 11), draw_star),
    ("emoji_smile", ["smile"], (11, 11), draw_emoji_smile),
    ("emoji_heart", ["heart"], (11, 11), draw_emoji_heart),
    ("emoji_laugh", ["joy"], (11, 11), draw_emoji_laugh),
    ("emoji_thumbs_up", ["thumbsup"], (11, 11), draw_emoji_thumbs),
    ("emoji_fire", ["fire"], (11, 11), draw_emoji_fire),
    ("emoji_party", ["tada"], (11, 11), draw_emoji_party),
    ("emoji_cry", ["sad"], (11, 11), draw_emoji_cry),
    ("emoji_think", ["thinking"], (11, 11), draw_emoji_think),
    ("emoji_clap", ["clap"], (11, 11), draw_emoji_clap),
    ("emoji_100", ["hundred"], (11, 11), draw_emoji_100),
]

def write_bmp_rgba(path, im: Image.Image):
    w, h = im.size
    pixels = im.load()
    row_stride = w * 4
    pixel_data = bytearray(row_stride * h)
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            i = y * row_stride + x * 4
            pixel_data[i] = b
            pixel_data[i + 1] = g
            pixel_data[i + 2] = r
            pixel_data[i + 3] = a
    dib = struct.pack(
        "<IiiHHIIiiII",
        40, w, -h, 1, 32, 0, len(pixel_data), 3780, 3780, 0, 0,
    )
    offset = 14 + len(dib)
    file_size = offset + len(pixel_data)
    hdr = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, offset)
    with open(path, "wb") as f:
        f.write(hdr)
        f.write(dib)
        f.write(pixel_data)

def write_yaml(path, icons_meta, sheet_w, sheet_h, rows):
    lines = [
        "# gl1 icon atlas — generated by tools/gen_icons.py",
        "sheet: icons.bmp",
        f"tile: {CELL}",
        f"gutter: {GUTTER}",
        f"stride: {STRIDE}",
        f"columns: {COLS}",
        f"rows: {rows}",
        f"width: {sheet_w}",
        f"height: {sheet_h}",
        "icons:",
    ]
    for m in icons_meta:
        lines.append(f"  - id: {m['id']}")
        if m["aliases"]:
            lines.append(f"    aliases: [{', '.join(m['aliases'])}]")
        else:
            lines.append("    aliases: []")
        for k in ("x", "y", "w", "h", "hotspot_x", "hotspot_y"):
            lines.append(f"    {k}: {m[k]}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = (len(ICONS) + COLS - 1) // COLS
    sheet_w = COLS * STRIDE - GUTTER
    sheet_h = rows * STRIDE - GUTTER
    sheet = Image.new("RGBA", (sheet_w, sheet_h), T)
    meta = []
    for i, (id_, aliases, hotspot, drawer) in enumerate(ICONS):
        col = i % COLS
        row = i // COLS
        im = blank()
        drawer(im)
        clean_alpha(im)
        x0 = col * STRIDE
        y0 = row * STRIDE
        sheet.paste(im, (x0, y0), im)
        meta.append({
            "id": id_,
            "aliases": aliases,
            "x": x0,
            "y": y0,
            "w": CELL,
            "h": CELL,
            "hotspot_x": hotspot[0],
            "hotspot_y": hotspot[1],
        })
    png_path = os.path.join(OUT_DIR, "icons.png")
    bmp_path = os.path.join(OUT_DIR, "icons.bmp")
    yaml_path = os.path.join(OUT_DIR, "icons.yaml")
    sheet.save(png_path)
    write_bmp_rgba(bmp_path, sheet)
    write_yaml(yaml_path, meta, sheet_w, sheet_h, rows)
    print(f"Wrote {len(ICONS)} icons @ {CELL}×{CELL} → {sheet_w}×{sheet_h}")
    print(f"  {png_path}")
    print(f"  {bmp_path}")
    print(f"  {yaml_path}")

if __name__ == "__main__":
    main()
