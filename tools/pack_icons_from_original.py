#!/usr/bin/env python3
"""Pack assets/icons from tmp/icons-original.png using explicit 1-based (col,row) map.

Source: fat-icons PNG copied to tmp/icons-original.png.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from icon_atlas import EXTRA_ALIASES, ICON_ORDER, PRIMARY_ALIAS

SRC = Path("tmp/icons-original.png")
OUT_DIR = Path("assets/icons")
SIZE = 24
GUTTER = 2
COLS = 8

# 1-based (col, row) on the source sheet.
POS: dict[str, tuple[int, int]] = {
    # cursors
    "cursor_arrow": (1, 1),
    "cursor_text": (2, 1),
    "cursor_cross": (3, 1),
    "cursor_resize_v": (4, 1),
    "cursor_resize_h": (5, 1),
    "cursor_resize_nesw": (7, 1),
    "cursor_resize_nwse": (8, 1),
    "cursor_busy": (1, 3),
    "cursor_hand_open": (5, 3),
    "cursor_hand_closed": (6, 3),
    # folders
    "folder": (3, 3),
    "folder_open": (4, 3),
    # carets (tree expand/collapse uses these too)
    "arrow_up": (2, 7),
    "arrow_right": (3, 7),
    "arrow_down": (4, 7),
    "arrow_left": (5, 7),
    "close": (6, 7),
    "download": (7, 7),
    # compass arrows
    "arrow_s": (2, 2),
    "arrow_n": (3, 2),
    "arrow_w": (4, 2),
    "arrow_e": (5, 2),
    "long_arrow_w": (6, 2),
    "long_arrow_e": (7, 2),
    # row 4 chrome
    "search": (2, 4),  # find
    "tree_leaf": (3, 4),
    "settings": (4, 4),
    "home": (5, 4),  # house (was wrongly mapped to disk cell)
    "save": (6, 4),  # disk
    "paste": (6, 4),  # same sheet cell as disk (user-specified)
    "copy": (7, 4),
    "trash": (8, 4),
    # row 5
    "eye": (1, 5),
    "lock": (2, 5),
    "check": (5, 5),  # ok
    "star": (6, 5),
    "emoji_smile": (7, 5),
    # row 8 math + chevrons
    "minus": (3, 8),
    "plus": (4, 8),
    "chevron_s": (1, 8),
    "chevron_n": (2, 8),
    "chevron_s_dark": (5, 8),
    "chevron_n_dark": (6, 8),
    # emoji
    "emoji_heart": (1, 6),
    "emoji_laugh": (2, 6),
    "emoji_thumbs_up": (3, 6),
    "emoji_fire": (4, 6),
    "emoji_party": (5, 6),
    "emoji_cry": (6, 6),
    "emoji_think": (7, 6),
    "emoji_clap": (8, 6),
    "emoji_100": (1, 7),
}

HOTSPOT = {
    "cursor_arrow": (2, 1),
    "cursor_hand_open": (12, 3),
    "cursor_hand_closed": (12, 3),
    "cursor_text": (12, 2),
    "cursor_cross": (12, 12),
    "cursor_resize_h": (12, 12),
    "cursor_resize_v": (12, 12),
    "cursor_resize_nwse": (12, 12),
    "cursor_resize_nesw": (12, 12),
    "cursor_busy": (12, 12),
}


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def main() -> None:
    rev: dict[tuple[int, int], list[str]] = {}
    for k, v in POS.items():
        rev.setdefault(v, []).append(k)
    for cell, ids in sorted(rev.items()):
        if len(ids) > 1:
            print(f"NOTE: shared cell {cell}: {ids}")

    missing = [iid for iid in ICON_ORDER if iid not in POS]
    if missing:
        raise SystemExit(f"POS missing: {missing}")
    extra = [k for k in POS if k not in ICON_ORDER]
    if extra:
        raise SystemExit(f"POS extra: {extra}")

    im = Image.open(SRC).convert("RGBA")
    a = np.array(im)
    alpha = a[:, :, 3]
    rr = runs(alpha.max(axis=1) > 10)
    cc = runs(alpha.max(axis=0) > 10)
    print(f"detected {len(cc)} cols x {len(rr)} rows")

    def cell_image(col_1: int, row_1: int) -> Image.Image:
        if row_1 < 1 or row_1 > len(rr) or col_1 < 1 or col_1 > len(cc):
            raise SystemExit(f"cell col={col_1} row={row_1} out of range ({len(cc)}x{len(rr)})")
        y0, y1 = rr[row_1 - 1]
        x0, x1 = cc[col_1 - 1]
        crop = im.crop((x0, y0, x1, y1))
        ca = np.array(crop)
        aa = ca[:, :, 3]
        ys, xs = np.where(aa > 10)
        if len(xs) == 0:
            print(f"WARNING: empty cell col={col_1} row={row_1}")
            return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        tight = crop.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
        tw, th = tight.size
        scale = min(SIZE / tw, SIZE / th)
        nw = max(1, int(round(tw * scale)))
        nh = max(1, int(round(th * scale)))
        scaled = tight.resize((nw, nh), Image.Resampling.LANCZOS)
        out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        out.paste(scaled, ((SIZE - nw) // 2, (SIZE - nh) // 2), scaled)
        return out

    n = len(ICON_ORDER)
    rows_out = (n + COLS - 1) // COLS
    stride = SIZE + GUTTER
    w = COLS * SIZE + (COLS - 1) * GUTTER
    h = rows_out * SIZE + (rows_out - 1) * GUTTER
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    yaml_lines = [
        "# gl1 icon atlas manifest — packed from tmp/icons-original.png",
        "sheet: icons.png",
        f"tile: {SIZE}",
        f"gutter: {GUTTER}",
        f"stride: {stride}",
        f"columns: {COLS}",
        f"rows: {rows_out}",
        f"width: {w}",
        f"height: {h}",
        "icons:",
    ]

    for i, iid in enumerate(ICON_ORDER):
        col = i % COLS
        row = i // COLS
        x = col * stride
        y = row * stride
        c, r = POS[iid]
        tile = cell_image(c, r)
        print(f"{iid:22} col={c} row={r}")
        sheet.paste(tile, (x, y), tile)

        aliases: list[str] = []
        seen: set[str] = set()
        for a in [PRIMARY_ALIAS.get(iid, iid)] + EXTRA_ALIASES.get(iid, []):
            if a not in seen:
                seen.add(a)
                aliases.append(a)
        hx, hy = HOTSPOT.get(iid, (12, 12))
        yaml_lines.append(f"  - id: {iid}")
        yaml_lines.append(f"    aliases: [{', '.join(aliases)}]")
        yaml_lines.append(f"    x: {x}")
        yaml_lines.append(f"    y: {y}")
        yaml_lines.append(f"    w: {SIZE}")
        yaml_lines.append(f"    h: {SIZE}")
        yaml_lines.append(f"    hotspot_x: {hx}")
        yaml_lines.append(f"    hotspot_y: {hy}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_DIR / "icons.png")
    (OUT_DIR / "icons.yaml").write_text("\n".join(yaml_lines) + "\n")
    print(f"Wrote {OUT_DIR / 'icons.png'} {sheet.size}, {n} icons")


if __name__ == "__main__":
    main()
