"""Render a quick top-down (and front) preview of each imported model so we can
tell which way it faces before wiring it into Godot.

Run: blender --background --factory-startup --python tools/preview_models.py
"""
from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
SRC = PROJECT / "assets" / "vehicles"
OUT = PROJECT.parent / "vehicle_previews"
MODELS = [
    "low_poly_t-72_tank_-_game_ready.glb",
    "low-poly_bmp-2m.glb",
    "btr-90_ussr.glb",
    "gaz_tigr_low_poly.glb",
    "apache_hecu_half-life.glb",
    "hecu_half-life.glb",
]


def clear() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    found = False
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        found = True
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); lo.z = min(lo.z, p.z)
            hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y); hi.z = max(hi.z, p.z)
    if not found:
        return None, None
    return lo, hi


def render(name: str, top: bool) -> None:
    clear()
    bpy.ops.import_scene.gltf(filepath=str(SRC / name))
    lo, hi = bounds()
    if lo is None:
        print("[preview] no mesh", name)
        return
    centre = (lo + hi) * 0.5
    size = max((hi - lo).x, (hi - lo).y, (hi - lo).z)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size * 1.25
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    if top:
        cam.location = centre + Vector((0, 0, size * 3))
        cam.rotation_euler = (0, 0, 0)
    else:
        cam.location = centre + Vector((0, -size * 3, 0))
        cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.camera = cam

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 5.0
    sun = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(40), math.radians(20), 0)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    tag = "top" if top else "front"
    scene.render.filepath = str(OUT / f"{Path(name).stem}_{tag}.png")
    bpy.ops.render.render(write_still=True)
    print("[preview]", name, tag, "size", tuple(round(v, 2) for v in (hi - lo)))


OUT.mkdir(parents=True, exist_ok=True)
for m in MODELS:
    render(m, True)
    if m.endswith("hecu_half-life.glb"):
        render(m, False)
print("[preview] done")
