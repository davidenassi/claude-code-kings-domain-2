"""Blender (bpy 4.5) render harness for King's Domain sprites.

Every sprite is rendered with the project camera (orthographic, 50 deg elevation, looking north),
the project sun and sky, and post-processed with the same tonemap as the terrain, so nothing looks
"pasted" on the valley.

Two images per object:
  body   : RGBA, the object lit (with ground interaction: contact AO, bounce) but without the ground
  shadow : alpha-only shadow cast on a flat ground (shadow catcher), drawn in the shadow layer
Anchor = pixel where the object's ground origin (0, 0, 0) projects.
"""
from __future__ import annotations

import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402

TMP = os.path.join(tempfile.gettempdir(), "kd_render")
os.makedirs(TMP, exist_ok=True)

EL = math.radians(K.CAMERA_ELEVATION_DEG)
CAM_DIR = Vector((0.0, math.cos(EL), -math.sin(EL)))            # view direction (Blender, y north)
CAM_UP = Vector((0.0, math.sin(EL), math.cos(EL)))
CAM_RIGHT = Vector((1.0, 0.0, 0.0))

# exposure calibration: sun strength so that a flat ground of albedo a renders like the terrain
SUN_STRENGTH = 5.75
SKY_STRENGTH = 0.56


# ------------------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 1
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.use_adaptive_sampling = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    sc.render.threads_mode = "AUTO"
    # world (sky ambient)
    w = bpy.data.worlds.new("sky")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.SKY_COLOR, 1.0)
    bg.inputs["Strength"].default_value = SKY_STRENGTH
    sc.world = w
    # sun
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = SUN_STRENGTH
    sun_data.color = K.SUN_COLOR
    sun_data.angle = math.radians(2.0)
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    d = Vector(K.sun_dir_blender())
    sun.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    # camera
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(90.0 - K.CAMERA_ELEVATION_DEG), 0.0, 0.0)
    sc.camera = cam
    # ground: shadow catcher
    bpy.ops.mesh.primitive_plane_add(size=400.0, location=(0, 0, 0))
    g = bpy.context.object
    g.name = "ground"
    g.is_shadow_catcher = True
    gm = bpy.data.materials.new("ground_mat")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.2, 0.08, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    g.data.materials.append(gm)
    return sc


def screen_xy(p: Vector):
    """Project a world point (Blender coords) to camera plane coords (metres): x right, y up."""
    return p.dot(CAM_RIGHT), p.dot(CAM_UP)


def object_extent(objs, with_shadow=True, margin=0.25):
    """Screen-plane rectangle (metres) containing the objects and their ground shadows."""
    pts = []
    sun = Vector(K.sun_dir_blender())
    for o in objs:
        if o.type not in ("MESH", "CURVE"):
            continue
        for c in o.bound_box:
            wp = o.matrix_world @ Vector(c)
            pts.append(wp)
            if with_shadow and wp.z > 0.01:
                # where this corner's shadow lands on z=0
                t = wp.z / sun.z
                pts.append(Vector((wp.x - sun.x * t, wp.y - sun.y * t, 0.0)))
    xs = [screen_xy(p)[0] for p in pts]
    ys = [screen_xy(p)[1] for p in pts]
    return min(xs) - margin, max(xs) + margin, min(ys) - margin, max(ys) + margin


def frame_camera(rect, ppm):
    sc = bpy.context.scene
    x0, x1, y0, y1 = rect
    w, h = x1 - x0, y1 - y0
    cam = sc.camera
    cam.data.ortho_scale = max(w, h)
    rx = int(math.ceil(w * ppm))
    ry = int(math.ceil(h * ppm))
    # keep exact ppm: adjust rect to integer pixels
    w = rx / ppm
    h = ry / ppm
    cam.data.ortho_scale = max(w, h)
    sc.render.resolution_x = rx
    sc.render.resolution_y = ry
    sc.render.resolution_percentage = 100
    cx = x0 + w * 0.5
    cy = y0 + h * 0.5
    centre = CAM_RIGHT * cx + CAM_UP * cy
    cam.location = centre - CAM_DIR * 300.0
    cam.data.clip_start = 1.0
    cam.data.clip_end = 1000.0
    # pixel of the world origin (anchor), y down
    ax = (0.0 - x0) * ppm
    ay = (y0 + h - 0.0) * ppm
    return rx, ry, ax, ay


def _render_exr(path, samples):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()          # top row first


class _Group:
    """Treat several shadow-catcher planes as one 'ground'."""

    def __init__(self, objs):
        self.objs = objs

    def __setattr__(self, k, v):
        if k == "objs":
            object.__setattr__(self, k, v)
        else:
            for o in self.objs:
                setattr(o, k, v)


def render_object(objs, name, ppm=None, samples=64, shadow_samples=24, with_shadow=True, rect=None, catchers=None):
    """Render body + shadow of `objs` (already in the scene). Returns dict of float arrays."""
    ppm = ppm or K.SPRITE_PX_PER_M * K.SPRITE_SUPERSAMPLE
    rect = rect or object_extent(objs, with_shadow)
    rx, ry, ax, ay = frame_camera(rect, ppm)
    ground = _Group(catchers) if catchers else bpy.data.objects["ground"]
    # pass A: body with ground interaction (shadow catcher present)
    ground.hide_render = False
    for o in objs:
        o.visible_camera = True
    a = _render_exr(os.path.join(TMP, f"{name}_a.exr"), samples)
    # pass B: coverage only (no ground, no ink: lines that Freestyle draws over geometry hidden by a holdout
    # - under water / under ground - fall outside this coverage and vanish)
    ground.hide_render = True
    ink0 = bpy.context.scene.render.use_freestyle
    bpy.context.scene.render.use_freestyle = False
    b = _render_exr(os.path.join(TMP, f"{name}_b.exr"), 4)
    bpy.context.scene.render.use_freestyle = ink0
    out = {"anchor": (ax, ay), "size": (rx, ry)}
    alpha = np.clip(b[..., 3], 0, 1)
    rgb = a[..., :3] / np.maximum(a[..., 3:4], 1e-4)      # un-premultiply (Cycles film is premultiplied)
    out["body"] = np.concatenate([rgb, alpha[..., None]], -1)
    if with_shadow:
        ground.hide_render = False
        ink = bpy.context.scene.render.use_freestyle
        bpy.context.scene.render.use_freestyle = False
        for o in objs:
            o.visible_camera = False
        c = _render_exr(os.path.join(TMP, f"{name}_c.exr"), shadow_samples)
        bpy.context.scene.render.use_freestyle = ink
        for o in objs:
            o.visible_camera = True
        out["shadow"] = np.clip(c[..., 3], 0, 1)
    ground.hide_render = False
    return out


# ------------------------------------------------------------------------------------------------
# post-processing (numpy) — identical tonemap to the terrain
def tonemap(lin):
    x = np.maximum(lin, 0.0)
    knee = 0.78
    over = np.maximum(x - knee, 0.0)
    x = np.where(x > knee, knee + over / (1.0 + over / (1.0 - knee + 0.02)), x)
    return np.clip(x, 0.0, 1.0) ** (1 / 2.2)


def downsample(img, f):
    if f == 1:
        return img
    h, w = img.shape[:2]
    h2, w2 = h // f, w // f
    img = img[: h2 * f, : w2 * f]
    return img.reshape(h2, f, w2, f, *img.shape[2:]).mean(axis=(1, 3))


def sharpen(rgb, a, amount=0.45, radius=1.0):
    """Unsharp mask on premultiplied colour (crisp illustrated detail at sprite resolution)."""
    from scipy.ndimage import gaussian_filter
    prem = rgb * a
    blur = np.stack([gaussian_filter(prem[..., k], radius) for k in range(3)], -1)
    ab = gaussian_filter(a[..., 0], radius)[..., None]
    out = prem + amount * (prem - blur * np.where(ab > 1e-4, a / np.maximum(ab, 1e-4), 1.0))
    return np.clip(out / np.maximum(a, 1e-4), 0, None)


def finish(res, supersample=None, grade=None, crisp=0.0):
    """float render -> (body RGBA uint8, shadow L uint8, anchor) at sprite resolution."""
    f = supersample or K.SPRITE_SUPERSAMPLE
    body = res["body"]
    a = body[..., 3:4]
    prem = np.concatenate([body[..., :3] * a, a], -1)
    prem = downsample(prem, f)
    a = prem[..., 3:4]
    rgb = prem[..., :3] / np.maximum(a, 1e-4)
    if grade:
        rgb = grade(rgb)
    if crisp > 0:
        rgb = sharpen(rgb, a, crisp)
    srgb = tonemap(rgb)
    body8 = np.concatenate([srgb, a], -1)
    body8 = (np.clip(body8, 0, 1) * 255 + 0.5).astype(np.uint8)
    sh8 = None
    if "shadow" in res:
        sh = downsample(res["shadow"], f)
        sh8 = (np.clip(sh, 0, 1) * 255 + 0.5).astype(np.uint8)
    ax, ay = res["anchor"]
    return body8, sh8, (ax / f, ay / f)


def trim(body8, sh8, anchor, pad=2):
    """Crop to the union of visible body and shadow; returns new arrays and anchor."""
    m = body8[..., 3] > 2
    if sh8 is not None:
        m |= sh8 > 2
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return body8, sh8, anchor
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, m.shape[0])
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, m.shape[1])
    body8 = body8[y0:y1, x0:x1]
    if sh8 is not None:
        sh8 = sh8[y0:y1, x0:x1]
    return body8, sh8, (anchor[0] - x0, anchor[1] - y0)


# ------------------------------------------------------------------------------------------------
# small modelling helpers
def material(name, color, rough=0.85, spec=0.2, noise=None, bump=None, subsurface=0.0):
    """Principled material with optional colour noise (scale, amount) and bump (scale, strength)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = spec
    if noise:
        sc_, amt = noise
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = sc_
        tex.inputs["Detail"].default_value = 4.0
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = amt
        mix.inputs["A"].default_value = (*color, 1.0)
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.55, 0.55, 0.55, 1)
        ramp.color_ramp.elements[1].color = (1.45, 1.45, 1.45, 1)
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    if bump:
        sc_, strength = bump
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = sc_
        tex.inputs["Detail"].default_value = 6.0
        b = nt.nodes.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = strength
        nt.links.new(tex.outputs["Fac"], b.inputs["Height"])
        nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    if subsurface > 0:
        p.inputs["Subsurface Weight"].default_value = subsurface
    return m


def srgb_to_lin(c):
    return tuple((v / 255.0) ** 2.2 for v in c)


def clear_objects(keep=("sun", "cam", "ground")):
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


# ------------------------------------------------------------------------------------------------
# Phase 1B: illustrated style (outlines, grade) and yaw
def outlines(on=True, thickness=1.7, color=(0.075, 0.048, 0.03), alpha=0.72, crease=138.0):
    """Freestyle ink lines on silhouettes, creases and borders (thin at sprite resolution)."""
    sc = bpy.context.scene
    sc.render.use_freestyle = on
    if not on:
        return
    sc.render.line_thickness_mode = "ABSOLUTE"
    vl = sc.view_layers[0]
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(crease)
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("ink")
    ls.select_by_visibility = True
    ls.visibility = "VISIBLE"
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_external_contour = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    st = ls.linestyle
    st.color = color
    st.alpha = alpha
    st.thickness = thickness
    st.thickness_position = "INSIDE"
    st.use_chaining = True
    # helper planes (shadow catchers, under-water / under-ground cuts) never get ink
    ls.select_by_collection = True
    ls.collection = no_ink()
    ls.collection_negation = "EXCLUSIVE"
    if "ground" in bpy.data.objects:
        to_no_ink(bpy.data.objects["ground"])


def no_ink():
    """Collection of helper objects excluded from the ink lines."""
    c = bpy.data.collections.get("no_ink")
    if c is None:
        c = bpy.data.collections.new("no_ink")
        bpy.context.scene.collection.children.link(c)
    return c


def to_no_ink(o):
    c = no_ink()
    for oc in list(o.users_collection):
        oc.objects.unlink(o)
    c.objects.link(o)


def apply_yaw(objs, yaw_deg):
    """Rotate a whole model about the vertical axis through its origin (facade south at yaw 0)."""
    if not yaw_deg:
        return None
    root = bpy.data.objects.new("yaw_root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    bpy.context.view_layer.update()
    return root


def grade_illustrated(rgb, sat=1.16, contrast=1.07, warm=(1.035, 1.0, 0.94), pivot=0.18):
    """Illustrated grade (linear): richer colour, a little more contrast around the mid tones, warm light."""
    l = (rgb * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    rgb = np.clip(l + (rgb - l) * sat, 0, None)
    rgb = pivot * (np.maximum(rgb, 1e-6) / pivot) ** contrast
    return rgb * np.array(warm)


def illustrated_light(sun=6.3, sky=0.44):
    """Phase 1B sprites: a little more direct sun, a little less sky -> stronger lit / shaded faces."""
    sc = bpy.context.scene
    sc.cycles.max_bounces = 3
    sc.cycles.diffuse_bounces = 1
    sc.cycles.glossy_bounces = 1
    sc.cycles.adaptive_threshold = 0.03
    bpy.data.objects["sun"].data.energy = sun
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = sky
