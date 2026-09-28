"""Output helpers: PNG writer (no PIL available), zlib raster files, JSON."""
import json
import os
import struct
import zlib

import numpy as np


def _png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, array):
    """array: HxW (gray8/gray16) or HxWx3 (RGB8) or HxWx4 (RGBA8)."""
    a = np.asarray(array)
    if a.ndim == 2:
        h, w = a.shape
        color_type = 0
        if a.dtype == np.uint16:
            bit_depth, buf, row_len = 16, a.astype(">u2").tobytes(), w * 2
        else:
            bit_depth, buf, row_len = 8, a.astype(np.uint8).tobytes(), w
    else:
        h, w, c = a.shape
        color_type = {3: 2, 4: 6}[c]
        bit_depth, buf, row_len = 8, a.astype(np.uint8).tobytes(), w * c
    raw = np.frombuffer(buf, dtype=np.uint8).reshape(h, row_len)
    payload = np.hstack([np.zeros((h, 1), dtype=np.uint8), raw]).tobytes()
    ihdr = struct.pack(">IIBBBBB", w, h, bit_depth, color_type, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(_png_chunk(b"IHDR", ihdr))
        f.write(_png_chunk(b"IDAT", zlib.compress(payload, 6)))
        f.write(_png_chunk(b"IEND", b""))


def write_raster(path, array):
    """Raw little-endian raster compressed with zlib (Godot: PackedByteArray.decompress, DEFLATE)."""
    a = np.ascontiguousarray(array)
    if a.dtype == np.uint16:
        data = a.astype("<u2").tobytes()
    elif a.dtype == np.float32:
        data = a.astype("<f4").tobytes()
    else:
        data = a.astype(np.uint8).tobytes()
    comp = zlib.compress(data, 6)
    with open(path, "wb") as f:
        f.write(comp)
    return {"file": os.path.basename(path), "width": int(a.shape[1]), "height": int(a.shape[0]),
            "dtype": str(a.dtype), "uncompressed_bytes": len(data), "compressed_bytes": len(comp)}


def write_json(path, obj, compact=False):
    with open(path, "w", encoding="utf-8") as f:
        if compact:
            json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
        else:
            json.dump(obj, f, ensure_ascii=False, indent=1)

