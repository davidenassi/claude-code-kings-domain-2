"""Cuts the UI asset sheets (art_source/ui/sheet*.png) into single pieces with transparency.

Run with Blender's bundled Python (numpy only, no Pillow):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/slice_ui.py

The sheets come with their own transparency. The cut is an XY-cut on the empty gutters: bands of empty rows
split the sheet into rows, bands of empty columns split each row into pieces, and every piece is trimmed to
what it actually covers.

Output: art_source/ui/cut/<sheet>/rNN_cNN.png + manifest.json with the rectangle of every piece on the sheet, so a
piece can be recognised by where it was.
"""
import json
import os
import struct
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
from kdio import write_png  # noqa: E402

SRC_DIR = os.path.join(ROOT, "art_source", "ui")
OUT_DIR = os.path.join(ROOT, "art_source", "ui", "cut")   # intermediates: the game never loads these
WHITE = 0.955          # brighter than this on every channel...
GREY = 0.05            # ...and this close to grey, is background
MIN_GUTTER = 6         # a gap of fewer white lines than this does not split
MIN_SIDE = 14          # pieces smaller than this are noise


# --- a small PNG reader (8 bit, colour type 2 or 6, not interlaced) -------------------------------------

def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "%s is not a PNG" % path
    pos = 8
    idat = []
    width = height = depth = color = 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, color, _comp, _filt, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and interlace == 0, "unsupported PNG (depth %d, interlace %d)" % (depth, interlace)
            assert color in (2, 6), "unsupported colour type %d" % color
        elif tag == b"IDAT":
            idat.append(chunk)
        elif tag == b"IEND":
            break
    raw = zlib.decompress(b"".join(idat))
    channels = 3 if color == 2 else 4
    stride = width * channels
    out = np.zeros((height, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.uint8)
    pos = 0
    for y in range(height):
        filter_type = raw[pos]
        pos += 1
        line = np.frombuffer(raw[pos:pos + stride], dtype=np.uint8).astype(np.int32).copy()
        pos += stride
        if filter_type == 0:
            cur = line
        elif filter_type == 1:   # Sub
            cur = line
            for i in range(channels, stride):
                cur[i] = (cur[i] + cur[i - channels]) & 0xFF
        elif filter_type == 2:   # Up
            cur = (line + prev.astype(np.int32)) & 0xFF
        elif filter_type == 3:   # Average
            cur = line
            for i in range(stride):
                left = cur[i - channels] if i >= channels else 0
                cur[i] = (cur[i] + ((left + int(prev[i])) >> 1)) & 0xFF
        elif filter_type == 4:   # Paeth
            cur = line
            for i in range(stride):
                left = int(cur[i - channels]) if i >= channels else 0
                up = int(prev[i])
                up_left = int(prev[i - channels]) if i >= channels else 0
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                pred = left if (pa <= pb and pa <= pc) else (up if pb <= pc else up_left)
                cur[i] = (cur[i] + pred) & 0xFF
        else:
            raise AssertionError("unknown filter %d" % filter_type)
        cur = cur.astype(np.uint8)
        out[y] = cur
        prev = cur
    img = out.reshape(height, width, channels).astype(np.float32) / 255.0
    if channels == 3:
        img = np.concatenate([img, np.ones((height, width, 1), dtype=np.float32)], axis=2)
    return img


# --- the cut ---------------------------------------------------------------------------------------------

def background_mask(img, threshold=0.6):
    """True where there is (almost) nothing. The soft shadows of the assets bridge the gaps between one piece
    and the next, so the cut ignores anything fainter than `threshold` while the trimming keeps it."""
    return img[..., 3] < threshold


def runs(flags, minimum):
    """Start/end of the runs of True at least `minimum` long."""
    out = []
    start = None
    for i, v in enumerate(flags):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= minimum:
                out.append((start, i))
            start = None
    if start is not None and len(flags) - start >= minimum:
        out.append((start, len(flags)))
    return out


def bands(empty, length):
    """The spans of content between the gutters."""
    gutters = runs(empty, MIN_GUTTER)
    spans = []
    cursor = 0
    for a, b in gutters:
        if a > cursor:
            spans.append((cursor, a))
        cursor = b
    if cursor < length:
        spans.append((cursor, length))
    return spans


def trim(piece_bg):
    ys, xs = np.nonzero(~piece_bg)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def outside_alpha(bg):
    """Alpha 0 only where the white touches the border of the piece: white inside a frame stays."""
    h, w = bg.shape
    outside = np.zeros_like(bg)
    stack = []
    for x in range(w):
        stack.append((0, x))
        stack.append((h - 1, x))
    for y in range(h):
        stack.append((y, 0))
        stack.append((y, w - 1))
    while stack:
        y, x = stack.pop()
        if y < 0 or x < 0 or y >= h or x >= w or outside[y, x] or not bg[y, x]:
            continue
        outside[y, x] = True
        stack.append((y + 1, x))
        stack.append((y - 1, x))
        stack.append((y, x + 1))
        stack.append((y, x - 1))
    return outside


def cut(bg, x0, y0, x1, y1, depth=0):
    """Splits a region on its empty gutters, over and over, until nothing splits any more."""
    region = bg[y0:y1, x0:x1]
    if depth > 6 or region.size == 0:
        return [(x0, y0, x1, y1)]
    rows = bands(region.all(axis=1), y1 - y0)
    if len(rows) > 1:
        out = []
        for a, b in rows:
            out.extend(cut(bg, x0, y0 + a, x1, y0 + b, depth + 1))
        return out
    cols = bands(region.all(axis=0), x1 - x0)
    if len(cols) > 1:
        out = []
        for a, b in cols:
            out.extend(cut(bg, x0 + a, y0, x0 + b, y1, depth + 1))
        return out
    return [(x0, y0, x1, y1)]


def slice_sheet(path, name):
    img = read_png(path)
    h, w, _ = img.shape
    bg = background_mask(img, 0.6)        # for the cut: shadows do not count as content
    solid = background_mask(img, 0.06)    # for the trimming: the shadow belongs to the piece
    out_dir = os.path.join(OUT_DIR, name)
    os.makedirs(out_dir, exist_ok=True)
    manifest = []
    boxes = cut(bg, 0, 0, w, h)
    boxes.sort(key=lambda b: (b[1] // 40, b[0]))
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        box = trim(solid[y0:y1, x0:x1])
        if box is None:
            continue
        tx0, ty0, tx1, ty1 = box
        px0, py0, px1, py1 = x0 + tx0, y0 + ty0, x0 + tx1, y0 + ty1
        if px1 - px0 < MIN_SIDE or py1 - py0 < MIN_SIDE:
            continue
        piece = img[py0:py1, px0:px1].copy()
        file_name = "%02d_x%04d_y%04d.png" % (i, px0, py0)
        write_png(os.path.join(out_dir, file_name), (np.clip(piece, 0, 1) * 255).astype(np.uint8))
        manifest.append({"file": file_name, "x": int(px0), "y": int(py0),
                         "w": int(px1 - px0), "h": int(py1 - py0)})
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8", newline=chr(10)) as f:
        json.dump({"sheet": name, "source_size": [w, h], "pieces": manifest}, f, indent=1)
    print("%s: %d pezzi (%dx%d)" % (name, len(manifest), w, h))
    return manifest


def main():
    if not os.path.isdir(SRC_DIR):
        raise SystemExit("manca %s" % SRC_DIR)
    for file in sorted(os.listdir(SRC_DIR)):
        if not file.lower().endswith(".png") or "sketch" in file:
            continue
        slice_sheet(os.path.join(SRC_DIR, file), os.path.splitext(file)[0])


if __name__ == "__main__":
    main()

