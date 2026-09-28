"""Picks the pieces the game actually needs out of the cut sheets and prepares them for Godot.

  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/build_ui_kit.py

Two things happen here:

* the frames painted with a title inside ("Titolo della Finestra") get that title wiped, by tiling a clean
  column of the title bar over it: a nine-patch stretches its middle, and baked words would smear;
* every chosen piece is written to assets/ui/kit/<name>.png together with kit.json, which carries the
  nine-patch margins (how much of each side must never stretch).

The names in KIT are the contract with `KDTheme`: change a name here and the theme follows.
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

UI_DIR = os.path.join(ROOT, "assets", "ui")
CUT_DIR = os.path.join(ROOT, "art_source", "ui", "cut")   # where slice_ui.py leaves the pieces
KIT_DIR = os.path.join(UI_DIR, "kit")

# name -> (sheet, index in the cut manifest, nine-patch margins, how to clean it)
#   margins: (left, top, right, bottom) — the frame that must not stretch
#   clean:   None, or ("title", y0, y1, source_x) to wipe a baked title band
KIT = {
    # --- frames -------------------------------------------------------------------------------------
    # the painted window carries a title, a closing cross and a parchment inside: a frame that has to hold
    # live text must be cleared of all three, or every sheet would show the same painted words
    "window":        ("sheet1_hud", 16, (26, 46, 26, 26), ("window", 0, 0, 0)),
    "panel":         ("sheet1_hud", 16, (26, 22, 26, 26), ("panel", 0, 0, 0)),
    "panel_dark":    ("sheet4_buttons", 30, (18, 16, 18, 16), None),
    "panel_gold":    ("sheet4_buttons", 32, (18, 16, 18, 16), None),
    # --- buttons, four states ------------------------------------------------------------------------
    "button":          ("sheet4_buttons", 30, (16, 14, 16, 14), None),
    "button_hover":    ("sheet4_buttons", 31, (16, 14, 16, 14), None),
    "button_pressed":  ("sheet4_buttons", 32, (16, 14, 16, 14), None),
    "button_disabled": ("sheet4_buttons", 33, (16, 14, 16, 14), None),
    "button_green":    ("sheet4_buttons", 51, (16, 14, 16, 14), None),
    "button_red":      ("sheet4_buttons", 60, (16, 14, 16, 14), None),
    "button_blue":     ("sheet4_buttons", 83, (16, 14, 16, 14), None),
    # --- small parts ---------------------------------------------------------------------------------
    "slot":          ("sheet4_buttons", 104, (14, 12, 14, 12), None),
    "pill":          ("sheet4_buttons", 95, (22, 12, 22, 12), None),
    "close":         ("sheet4_buttons", 88, (10, 10, 10, 10), None),
    "close_hover":   ("sheet4_buttons", 89, (10, 10, 10, 10), None),
    "close_pressed": ("sheet4_buttons", 90, (10, 10, 10, 10), None),
    "check_on":      ("sheet4_buttons", 111, (8, 8, 8, 8), None),
    "check_off":     ("sheet4_buttons", 113, (8, 8, 8, 8), None),
    # --- what the map needs: pins, markers, rings and plates (sheet 5) -------------------------------
    # used as plain textures, not nine patches: the margins only satisfy the writer
    "icon_pin_village":    ("sheet5_heraldry", 27, (4, 4, 4, 4), None),
    "icon_pin_town":       ("sheet5_heraldry", 29, (4, 4, 4, 4), None),
    "icon_pin_city":       ("sheet5_heraldry", 30, (4, 4, 4, 4), None),
    "icon_pin_capital":    ("sheet5_heraldry", 31, (4, 4, 4, 4), None),
    "icon_mark_battle":    ("sheet5_heraldry", 37, (4, 4, 4, 4), None),
    "icon_mark_siege":     ("sheet5_heraldry", 38, (4, 4, 4, 4), None),
    "icon_ring_friend":    ("sheet5_heraldry", 48, (4, 4, 4, 4), None),
    "icon_ring_enemy":     ("sheet5_heraldry", 50, (4, 4, 4, 4), None),
    "icon_gonfalon_foot":  ("sheet5_heraldry", 41, (4, 4, 4, 4), None),
    "icon_gonfalon_horse": ("sheet5_heraldry", 43, (4, 4, 4, 4), None),
    "icon_gonfalon_bow":   ("sheet5_heraldry", 44, (4, 4, 4, 4), None),
    "plate":               ("sheet5_heraldry", 69, (20, 10, 20, 10), None),
    # --- sheet 3: the parts row at the foot of the sheet (one island for the slicer, cut here by hand) ------
    # ("crop", x0, y0, x1, y1[, wipe_x0, wipe_x1, source_x]): a rectangle inside the piece, and optionally a
    # stretch of it repainted with a clean column (the painted words "Sezione" / "Sottosezione")
    "section_bar":    ("sheet3_windows", 7, (46, 12, 18, 12), ("crop", 3, 221, 438, 266, 60, 420, 428)),
    "subsection_bar": ("sheet3_windows", 7, (40, 10, 16, 10), ("crop", 453, 221, 716, 266, 505, 700, 706)),
    "rule_ornate":    ("sheet3_windows", 7, (40, 4, 40, 4), ("crop", 724, 211, 1096, 257)),
}

# the icons of sheet 2, row by row as they are painted; each cell holds a big and a small version
ICON_NAMES = [
    ["gold", "people", "wood", "stone", "iron", "grain"],
    ["bread", "war", "book", "law", "lily", "culture"],
    ["growth", "consent", "beds", "build", "shield", "crown"],
    ["justice", "treasury", "house_arms", "clergy", "mine", "village"],
    ["bakery", "smith", "storehouse", "road", "camp", "development"],
    ["alert", "chronicle", "diplomacy", "trade", "intrigue", "fire", "birth"],
]


def load(sheet, index):
    folder = os.path.join(CUT_DIR, sheet)
    pieces = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))["pieces"]
    if index >= len(pieces):
        raise SystemExit("%s: manca il pezzo %d (ce ne sono %d)" % (sheet, index, len(pieces)))
    piece = pieces[index]
    return read_png(os.path.join(folder, piece["file"])), piece


def wipe_band(img, y0, y1, source_x, keep_left, keep_right):
    """Tiles a clean column of the title bar across it: no painted word, no painted cross, survives."""
    out = img.copy()
    column = out[y0:y1, source_x:source_x + 1, :]
    band = np.repeat(column, out.shape[1], axis=1)
    x0 = keep_left
    x1 = out.shape[1] - keep_right
    out[y0:y1, x0:x1] = band[:, x0:x1]
    return out


def darken_inside(img, wood_x=200, wood_y=20):
    """Replaces the painted parchment inside the frame with the wood of its own title bar, so the frame can
    hold light text like every other panel of the game. The parchment survives where the game asks for it
    (KDSheet.parchment builds its own)."""
    out = img.copy()
    rgb = out[..., :3]
    lo = rgb.min(axis=2)
    hi = rgb.max(axis=2)
    warm = rgb[..., 0] > rgb[..., 2]
    parchment = (lo > 0.62) & (hi > 0.78) & warm & (out[..., 3] > 0.5)
    wood = out[wood_y, wood_x, :3]
    # a touch of grain so the inside is not a dead flat rectangle
    noise = (np.random.default_rng(7).random(out.shape[:2]) - 0.5) * 0.012
    for c in range(3):
        channel = out[..., c]
        channel[parchment] = np.clip(wood[c] + noise[parchment], 0.0, 1.0)
        out[..., c] = channel
    return out


def clean_window(img):
    """The frame as the game needs it: title band emptied (cross included) and dark inside."""
    band = wipe_band(img, 2, 44, 60, 40, 6)
    return darken_inside(band)


def build_kit():
    os.makedirs(KIT_DIR, exist_ok=True)
    manifest = {}
    for name, (sheet, index, margins, clean) in KIT.items():
        img, piece = load(sheet, index)
        if clean and clean[0] == "window":
            img = clean_window(img)
        elif clean and clean[0] == "panel":
            img = clean_window(img)[30:]   # the same frame without its title band: bars, cards, inspectors
        elif clean and clean[0] == "crop":
            x0, y0, x1, y1 = clean[1:5]
            img = img[y0:y1, x0:x1].copy()
            if len(clean) >= 8:
                # the painted words go: a clean column of the bar is tiled over them, as for the window titles
                wx0, wx1, src = clean[5] - x0, clean[6] - x0, clean[7] - x0
                column = img[:, src:src + 1, :]
                img[:, wx0:wx1] = np.repeat(column, wx1 - wx0, axis=1)
        write_png(os.path.join(KIT_DIR, name + ".png"), (np.clip(img, 0, 1) * 255).astype(np.uint8))
        manifest[name] = {"file": "kit/%s.png" % name, "w": img.shape[1], "h": img.shape[0],
                          "margins": list(margins), "from": "%s#%d" % (sheet, index)}
    return manifest


def build_icons():
    """Sorts the cut icons into rows and columns and gives them their names (big and small)."""
    folder = os.path.join(CUT_DIR, "sheet2_icons")
    pieces = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))["pieces"]
    rows = {}
    for p in pieces:
        key = None
        for existing in rows:
            if abs(existing - p["y"]) < 90:
                key = existing
                break
        rows.setdefault(key if key is not None else p["y"], []).append(p)
    ordered_rows = [sorted(v, key=lambda p: p["x"]) for _, v in sorted(rows.items())]
    out_dir = os.path.join(UI_DIR, "icons")
    os.makedirs(out_dir, exist_ok=True)
    manifest = {}
    for r, row in enumerate(ordered_rows):
        if r >= len(ICON_NAMES):
            break
        # pair them up: within a cell the big one comes first, the small one follows
        names = ICON_NAMES[r]
        cells = []
        current = []
        for p in row:
            if current and p["w"] > current[-1]["w"] * 1.3:
                cells.append(current)
                current = []
            current.append(p)
            if len(current) == 2:
                cells.append(current)
                current = []
        if current:
            cells.append(current)
        for c, cell in enumerate(cells):
            if c >= len(names):
                break
            big = max(cell, key=lambda p: p["w"])
            img = read_png(os.path.join(folder, big["file"]))
            name = "icon_%s" % names[c]
            write_png(os.path.join(out_dir, name + ".png"), (np.clip(img, 0, 1) * 255).astype(np.uint8))
            manifest[name] = {"file": "icons/%s.png" % name, "w": img.shape[1], "h": img.shape[0]}
    return manifest


def main():
    kit = build_kit()
    icons = build_icons()
    kit.update(icons)
    with open(os.path.join(UI_DIR, "kit.json"), "w", encoding="utf-8", newline=chr(10)) as f:
        json.dump({"version": 1, "pieces": kit}, f, indent=1, sort_keys=True)
    print("kit: %d cornici/pulsanti, %d icone -> assets/ui/kit.json" % (len(KIT), len(icons)))


if __name__ == "__main__":
    main()

