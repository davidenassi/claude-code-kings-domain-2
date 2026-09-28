"""Builds a contact sheet of the pieces cut from a UI asset sheet, in order, so they can be recognised.

  python tools/art/ui_contact_sheet.py sheet1_hud [cell] [cols]
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
sys.path.insert(0, HERE)
from kdio import write_png  # noqa: E402
from slice_ui import read_png  # noqa: E402


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "sheet1_hud"
    cell = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    folder = os.path.join(ROOT, "art_source", "ui", "cut", name)
    pieces = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))["pieces"]
    rows = (len(pieces) + cols - 1) // cols
    out = np.zeros((rows * cell, cols * cell, 3), dtype=np.float32)
    out[:] = np.array([0.35, 0.36, 0.38])
    for i, p in enumerate(pieces):
        img = read_png(os.path.join(folder, p["file"]))
        h, w, _ = img.shape
        scale = min((cell - 8) / w, (cell - 8) / h, 1.0)
        nw, nh = max(int(w * scale), 1), max(int(h * scale), 1)
        ys = (np.arange(nh) / scale).astype(int).clip(0, h - 1)
        xs = (np.arange(nw) / scale).astype(int).clip(0, w - 1)
        small = img[ys][:, xs]
        cy = (i // cols) * cell + (cell - nh) // 2
        cx = (i % cols) * cell + (cell - nw) // 2
        a = small[..., 3:4]
        out[cy:cy + nh, cx:cx + nw] = small[..., :3] * a + out[cy:cy + nh, cx:cx + nw] * (1 - a)
        # a white tick every 4 cells to help counting
        if i % 4 == 0:
            out[cy - 4:cy - 1, cx:cx + 10] = 1.0
    path = os.path.join(ROOT, "tools", "art", "out_preview", "contact_%s.png" % name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_png(path, (np.clip(out, 0, 1) * 255).astype(np.uint8))
    print("%s -> %s (%d pezzi, %d per riga)" % (name, path, len(pieces), cols))


if __name__ == "__main__":
    main()

