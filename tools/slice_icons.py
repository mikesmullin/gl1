#!/usr/bin/env python3
"""Re-emit icons.yaml from gen_icons layout rules."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from gen_icons import ICONS, CELL, COLS, GUTTER, STRIDE, OUT_DIR, write_yaml

def main():
    rows = (len(ICONS) + COLS - 1) // COLS
    sheet_w = COLS * STRIDE - GUTTER
    sheet_h = rows * STRIDE - GUTTER
    meta = []
    for i, (id_, aliases, hotspot, _) in enumerate(ICONS):
        col = i % COLS
        row = i // COLS
        meta.append({
            "id": id_,
            "aliases": aliases,
            "x": col * STRIDE,
            "y": row * STRIDE,
            "w": CELL,
            "h": CELL,
            "hotspot_x": hotspot[0],
            "hotspot_y": hotspot[1],
        })
    write_yaml(os.path.join(OUT_DIR, "icons.yaml"), meta, sheet_w, sheet_h, rows)
    print(f"Sliced {len(meta)} icons @ {CELL}px")

if __name__ == "__main__":
    main()
