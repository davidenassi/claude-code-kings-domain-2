"""Phase 1B comparison sheets: REFERENCE | CURRENT (unretouched game screenshots), with k-means palettes.

python tools/compare_1b.py <screenshots dir> <out dir>
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.cluster.vq import kmeans2

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "docs", "reference")
SHEETS = [
    ("COMPARE_REFERENCE_MID", "ref_B_villaggio.webp", "VERTICAL_SLICE_MID", "Riferimento B — villaggio (MID)"),
    ("COMPARE_REFERENCE_CLOSE", "ref_C_ravvicinato.webp", "VERTICAL_SLICE_CLOSE", "Riferimento C — ravvicinato (CLOSE)"),
    ("COMPARE_REFERENCE_MILITARY", "ref_D_militare.webp", "MILITARY_CLOSE", "Riferimento D — zona militare"),
    ("COMPARE_REFERENCE_VALLEY", "ref_A_valle.webp", "VALLEY_FAR_1B", "Riferimento A — valle"),
]


def font(sz):
    p = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    return ImageFont.truetype(p, sz) if os.path.exists(p) else ImageFont.load_default()


def palette(img, k=10):
    px = np.asarray(img.convert("RGB")).reshape(-1, 3).astype(float)[::13]
    c, lab = kmeans2(px, k, minit="++", seed=3)
    cnt = np.bincount(lab, minlength=k)
    order = np.argsort(-cnt)
    return [(c[i], cnt[i] / cnt.sum()) for i in order]


def main():
    shots, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    H = 760
    for name, ref_file, shot, label in SHEETS:
        p = os.path.join(shots, shot + ".png")
        if not os.path.exists(p):
            print("missing", shot)
            continue
        r = Image.open(os.path.join(REF, ref_file)).convert("RGB")
        o = Image.open(p).convert("RGB")
        r = r.resize((int(r.width * H / r.height), H), Image.LANCZOS)
        o = o.resize((int(o.width * H / o.height), H), Image.LANCZOS)
        sheet = Image.new("RGB", (r.width + o.width + 30, H + 160), (24, 22, 20))
        sheet.paste(r, (10, 64))
        sheet.paste(o, (r.width + 20, 64))
        d = ImageDraw.Draw(sheet)
        d.text((10, 16), f"REFERENCE — {label}", fill=(240, 230, 200), font=font(28))
        d.text((r.width + 20, 16), f"CURRENT — {shot} (gioco in esecuzione, non ritoccato)", fill=(240, 230, 200),
               font=font(28))
        for x0, img in ((10, r), (r.width + 20, o)):
            x = x0
            for c, f in palette(img):
                w = max(4, int(f * img.width))
                d.rectangle([x, H + 84, x + w, H + 140], fill=tuple(int(v) for v in c))
                x += w
        sheet.save(os.path.join(out, name + ".png"), optimize=True)
        print("wrote", name)


if __name__ == "__main__":
    main()
