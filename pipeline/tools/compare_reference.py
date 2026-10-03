"""Side-by-side comparison sheets: reference image vs King's Domain screenshots.

python tools/compare_reference.py <reference image> <screenshots dir> <out dir>
Produces COMPARE_<name>.png (reference crop left, our screenshot right, same height) and a palette
comparison (k-means colours of both).
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.cluster.vq import kmeans2

PAIRS = [
    # (our screenshot, reference crop box (x0, y0, x1, y1) in the 1672x941 reference, label)
    ("VALLEY_MID", (0, 0, 1672, 941), "insieme della valle"),
    ("VALLEY_CLOSE", (700, 250, 1350, 620), "città murata e castello"),
    ("FOREST_TEST", (0, 0, 600, 340), "foreste e montagne"),
    ("WATER_TEST_BRIDGE", (1050, 380, 1672, 720), "acqua, rive, ponti"),
    ("FIELDS_MID", (550, 450, 1200, 820), "campi e villaggi"),
]


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def palette(img, k=10):
    px = np.asarray(img.convert("RGB")).reshape(-1, 3).astype(float)[::17]
    c, l = kmeans2(px, k, minit="++", seed=3)
    cnt = np.bincount(l, minlength=k)
    order = np.argsort(-cnt)
    return [(c[i], cnt[i] / cnt.sum()) for i in order]


def main():
    ref_path, shots, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    ref = Image.open(ref_path).convert("RGB")
    H = 720
    for name, box, label in PAIRS:
        p = os.path.join(shots, name + ".png")
        if not os.path.exists(p):
            continue
        ours = Image.open(p).convert("RGB")
        r = ref.crop(box)
        r = r.resize((int(r.width * H / r.height), H), Image.LANCZOS)
        o = ours.resize((int(ours.width * H / ours.height), H), Image.LANCZOS)
        sheet = Image.new("RGB", (r.width + o.width + 30, H + 150), (24, 22, 20))
        sheet.paste(r, (10, 60))
        sheet.paste(o, (r.width + 20, 60))
        d = ImageDraw.Draw(sheet)
        d.text((10, 14), f"RIFERIMENTO — {label}", fill=(240, 230, 200), font=font(28))
        d.text((r.width + 20, 14), f"KING'S DOMAIN — {name}", fill=(240, 230, 200), font=font(28))
        # palettes
        for col0, img in ((10, r), (r.width + 20, o)):
            x = col0
            for c, f in palette(img):
                w = max(4, int(f * min(r.width, o.width)))
                d.rectangle([x, H + 80, x + w, H + 130], fill=tuple(int(v) for v in c))
                x += w
        sheet.save(os.path.join(out, f"COMPARE_{name}.png"), optimize=True)
        print("wrote", name)


if __name__ == "__main__":
    main()
