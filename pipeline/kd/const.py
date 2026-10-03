"""King's Domain — single source of truth for scale, projection and lighting.

Every tool in the pipeline (terrain generator, Blender renderers, atlas packer) imports
these values, and `write_projection_json()` exports them to `game/data/projection.json`
so the Godot runtime uses exactly the same numbers.

Coordinate conventions
----------------------
World (gameplay)   : metres. x -> east, y -> SOUTH (towards the camera), z -> up.
Godot world pixels : X = x * PX_PER_M
                     Y = (y * sin(EL) - z * cos(EL)) * PX_PER_M
                     (orthographic camera, yaw 0 = looking north, elevation EL above horizon)
Blender            : x -> east, y -> NORTH, z -> up  (so y_blender = -y_world).
"""
from __future__ import annotations

import json
import math
import os

# --- camera / projection --------------------------------------------------------------
CAMERA_ELEVATION_DEG = 50.0          # angle of the view direction above the horizon
SIN_EL = math.sin(math.radians(CAMERA_ELEVATION_DEG))   # ground depth factor   (0.766)
COS_EL = math.cos(math.radians(CAMERA_ELEVATION_DEG))   # vertical height factor (0.643)

PX_PER_M = 32.0                       # Godot world px per metre (zoom 1.0 = closest zoom)
SPRITE_PX_PER_M = 32.0                # sprites are delivered at native zoom-1.0 resolution
SPRITE_SUPERSAMPLE = 2                # rendered at 2x then downsampled (clean anti-aliasing)

# --- valley (terrain) --------------------------------------------------------------------
VALLEY_W_M = 3072.0                   # playable ground extent west -> east
VALLEY_H_M = 2560.0                   # playable ground extent north -> south
NORTH_PAD_M = 640.0                   # extra mountains generated north of y=0 (fills the top of the view)
GRID_M = 1.0                          # ground-space resolution of the terrain maps (metres per cell)
TERRAIN_PX_PER_M = 2.0                # projected terrain macro texture density (texels per metre)
TERRAIN_CHUNK_PX = 1024               # terrain texture chunk size
SEA_LEVEL = 0.0
VALLEY_FLOOR_Z = 100.0                # nominal valley floor altitude (m)

# --- light ---------------------------------------------------------------------------------
# Sun from the west-south-west: lights the facades that face the camera and the west sides,
# shadows fall to the east-north-east (right / slightly up on screen).
SUN_AZIMUTH_FROM_WEST_TOWARD_SOUTH_DEG = 25.0
SUN_ELEVATION_DEG = 47.0


def sun_dir_world():
    """Unit vector from the ground TOWARDS the sun, world coords (x east, y south, z up)."""
    a = math.radians(SUN_AZIMUTH_FROM_WEST_TOWARD_SOUTH_DEG)
    e = math.radians(SUN_ELEVATION_DEG)
    return (-math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))


def sun_dir_blender():
    x, y, z = sun_dir_world()
    return (x, -y, z)


SUN_COLOR = (1.0, 0.93, 0.80)         # linear, warm
SKY_COLOR = (0.46, 0.59, 0.90)        # linear, cool ambient
SUN_STRENGTH = 3.2                    # Blender sun strength (W/m^2) used for all sprites
SKY_STRENGTH = 0.85                   # Blender world background strength


# --- helpers --------------------------------------------------------------------------------
def world_to_px(x: float, y: float, z: float):
    return (x * PX_PER_M, (y * SIN_EL - z * COS_EL) * PX_PER_M)


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME_DIR = os.path.join(REPO_ROOT, "game")
CACHE_DIR = os.path.join(REPO_ROOT, "pipeline", ".cache")


def write_projection_json():
    data = {
        "camera_elevation_deg": CAMERA_ELEVATION_DEG,
        "sin_el": SIN_EL,
        "cos_el": COS_EL,
        "px_per_m": PX_PER_M,
        "sprite_px_per_m": SPRITE_PX_PER_M,
        "valley_w_m": VALLEY_W_M,
        "valley_h_m": VALLEY_H_M,
        "north_pad_m": NORTH_PAD_M,
        "terrain_px_per_m": TERRAIN_PX_PER_M,
        "terrain_chunk_px": TERRAIN_CHUNK_PX,
        "sun_dir_world": sun_dir_world(),
        "sun_color": SUN_COLOR,
        "sky_color": SKY_COLOR,
    }
    path = os.path.join(GAME_DIR, "data", "projection.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    return path


if __name__ == "__main__":
    print(write_projection_json())
    print("sun (world):", sun_dir_world())
