"""Generate four large ruined industrial interiors for the frontline maps.

  Assets/frontline/industrial_hall.glb  - main factory hall ("Промзона")
  Assets/frontline/village_hall.glb     - grain elevator / tractor repair shop
  Assets/frontline/steppe_hall.glb      - ore processing / mine hall
  Assets/frontline/wetlands_hall.glb    - flooded pump station / shipyard

The reference is a photoreal, multi-level concrete ruin: broken skylight
strips, deep catwalks, collapsed roof sections, rubble, moss and hard shafts
of sunlight.  Geometry is authored here; the 2K PBR materials and volumetric
lighting are applied in Godot.

Run:
  blender -b --factory-startup --python tools/blender_ruined_halls.py
"""
from __future__ import annotations

import math
import os
import random

import bpy
import mathutils

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "Assets", "frontline")
BLEND_PATH = os.path.join(os.path.dirname(PROJECT), "ruined_halls.blend")

# Batch generation creates thousands of primitives.  Blender's undo stack makes
# every later bpy.ops call progressively slower; disabling it is essential.
try:
    bpy.context.preferences.edit.use_global_undo = False
except Exception:
    pass

PARTS = []
LIGHTS = []
RNG = random.Random(1986)

MAT_COLORS = {
    "hall_concrete": (0.56, 0.54, 0.49),
    "hall_floor": (0.40, 0.38, 0.34),
    "hall_moss": (0.20, 0.28, 0.13),
    "hall_rust": (0.34, 0.16, 0.08),
    "hall_metal": (0.24, 0.26, 0.27),
    "hall_glass": (0.55, 0.68, 0.72),
    "hall_dark": (0.045, 0.045, 0.04),
    "hall_water": (0.035, 0.05, 0.045),
    "hall_brick": (0.40, 0.25, 0.19),
    "hall_wood": (0.31, 0.22, 0.14),
    "hall_paint": (0.30, 0.36, 0.30),
    "hall_gravel": (0.30, 0.29, 0.26),
}


# ------------------------------------------------------------------ helpers
def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)



def material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    color = MAT_COLORS.get(name, (0.5, 0.5, 0.5))
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    rough = 0.88
    metal = 0.0
    if name in ("hall_rust", "hall_metal", "hall_paint"):
        rough, metal = 0.62, 0.35
    if name == "hall_glass":
        rough, metal = 0.12, 0.05
    if name == "hall_water":
        rough, metal = 0.04, 0.0
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


def add(obj, mat_name):
    obj.data.materials.append(material(mat_name))
    PARTS.append(obj)
    return obj


_UNIT_CUBES = {}


def _unit_cube(mat_name):
    """One shared unit cube per material instead of a bpy.ops call per box."""
    if mat_name in _UNIT_CUBES:
        return _UNIT_CUBES[mat_name]
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    mesh = obj.data
    mesh.name = "unit_" + mat_name
    mesh.materials.append(material(mat_name))
    bpy.data.objects.remove(obj, do_unlink=True)
    _UNIT_CUBES[mat_name] = mesh
    return mesh


def box(size, loc, mat, bevel=0.0, rot=(0.0, 0.0, 0.0)):
    obj = bpy.data.objects.new("box_" + mat, _unit_cube(mat))
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.scale = size
    obj.rotation_euler = rot
    PARTS.append(obj)
    return obj


def cyl(radius, height, loc, mat, rot=(0.0, 0.0, 0.0), vertices=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
            depth=height, location=loc, rotation=rot)
    return add(bpy.context.object, mat)


def cone(r1, r2, height, loc, mat, rot=(0.0, 0.0, 0.0), vertices=14):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2,
            depth=height, location=loc, rotation=rot)
    return add(bpy.context.object, mat)


def beam_between(a, b, width, mat, width_y=None, bevel=0.0):
    a = mathutils.Vector(a)
    b = mathutils.Vector(b)
    d = b - a
    length = d.length
    if length < 0.01:
        return None
    mid = (a + b) * 0.5
    obj = bpy.data.objects.new("beam_" + mat, _unit_cube(mat))
    bpy.context.scene.collection.objects.link(obj)
    obj.location = mid
    obj.scale = (width, width if width_y is None else width_y, length)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = d.to_track_quat("Z", "Y")
    PARTS.append(obj)
    return obj


def arch_point(half_w, spring, apex, t):
    y = -half_w + 2.0 * half_w * t
    z = spring + (apex - spring) * math.sin(t * math.pi)
    return (y, z)


def empty(name, loc):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    LIGHTS.append(e)
    return e


def in_clear_lane(x, y, cfg):
    """Keep the spawn sightline clear of rubble and machines."""
    lane = cfg.get("lane")
    if lane is None:
        return False
    x0, x1, half = lane
    return x0 <= x <= x1 and abs(y) < half


# ------------------------------------------------------------------ roof
def build_roof(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    spring = cfg["spring"]
    apex = cfg["apex"]
    bay = cfg["bay"]
    segments = 20
    glazing = cfg.get("glazing", (4, 5, 14, 15))
    broken_bays = set(cfg.get("broken_bays", ()))
    coll_bay = cfg.get("collapsed_bay")
    n_bays = int(round(length / bay))
    start = -length * 0.5
    roof_mat = cfg["roof_mat"]

    # Arch ribs and purlins.
    for i in range(n_bays + 1):
        x = start + i * bay
        for seg in range(segments + 1):
            t = seg / segments
            y, z = arch_point(half_w - 0.7, spring, apex, t)
            if seg > 0:
                y0, z0 = arch_point(half_w - 0.7, spring, apex, (seg - 1) / segments)
                beam_between((x, y0, z0), (x, y, z), 0.42, "hall_rust")
    # Longitudinal purlins under the panels.
    for seg in (2, 7, 12, 17):
        t = seg / segments
        y, z = arch_point(half_w - 0.7, spring, apex, t)
        beam_between((start, y, z - 0.35), (start + length, y, z - 0.35),
                0.26, "hall_metal")

    for i in range(n_bays):
        x = start + (i + 0.5) * bay
        broken = i in broken_bays or (coll_bay is not None and abs(i - coll_bay) <= 1)
        for seg in range(segments):
            t0 = seg / segments
            t1 = (seg + 1) / segments
            y0, z0 = arch_point(half_w - 0.8, spring, apex, t0)
            y1, z1 = arch_point(half_w - 0.8, spring, apex, t1)
            ym, zm = (y0 + y1) * 0.5, (z0 + z1) * 0.5
            angle = math.atan2(z1 - z0, y1 - y0)
            panel_len = math.hypot(y1 - y0, z1 - z0) + 0.05
            is_glass = seg in glazing
            if is_glass:
                # Glazing strip: a dark frame with surviving panes or dark metal backing so the roof is continuous.
                box((bay * 0.97, panel_len, 0.12), (x, ym, zm),
                        "hall_rust" if broken else "hall_metal",
                        0.005, (angle, 0.0, 0.0))
                if not broken and RNG.random() < 0.62:
                    box((bay * 0.86, panel_len * 0.82, 0.06),
                            (x, ym, zm + 0.03), "hall_glass", 0.0,
                            (angle, 0.0, 0.0))
                for k in (-0.42, 0.0, 0.42):
                    box((0.10, panel_len, 0.16),
                            (x + k * bay, ym, zm + 0.05), "hall_rust", 0.0,
                            (angle, 0.0, 0.0))
            else:
                box((bay * 0.98, panel_len, 0.24), (x, ym, zm),
                        "hall_rust" if broken else ("hall_concrete" if seg % 7 == 0 else roof_mat),
                        0.008, (angle, 0.0, 0.0))
                # Raised corrugation ribs catch the sun.
                if seg % 2 == 0:
                    for k in (-0.30, 0.0, 0.30):
                        box((0.12, panel_len, 0.12),
                                (x + k * bay, ym, zm + 0.12), "hall_metal",
                                0.0, (angle, 0.0, 0.0))
    # Rooftop ventilators and ridge monitors along the barrel apex.
    for i in range(1, n_bays, 2):
        x = start + (i + 0.5) * bay
        box((2.4, 2.8, 1.4), (x, 0.0, apex + 0.55), "hall_metal", 0.02)
        box((2.8, 3.2, 0.22), (x, 0.0, apex + 1.32), "hall_rust", 0.01)
    # Skylight markers for the Godot light rig.
    for i in range(n_bays):
        if i in broken_bays or (coll_bay is not None and abs(i - coll_bay) <= 1):
            continue
        for seg in glazing:
            t = (seg + 0.5) / segments
            y, z = arch_point(half_w - 0.8, spring, apex, t)
            empty("skylight_%02d_%02d" % (i, seg),
                    (start + (i + 0.5) * bay, y, z - 0.4))


# ------------------------------------------------------------------ shell
def build_shell(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    spring = cfg["spring"]
    apex = cfg["apex"]
    bay = cfg["bay"]
    wall_mat = cfg["wall_mat"]
    floor_mat = cfg.get("floor_mat", "hall_floor")
    n_bays = int(round(length / bay))
    start = -length * 0.5

    # Foundation skirt and floor slab (deep skirt down to z = -4.5 so the hall never floats on sloped ground).
    box((length + 7.2, 2.0 * half_w + 7.2, 4.6), (0.0, 0.0, -2.25),
            "hall_concrete", 0.03)
    box((length + 6.0, 2.0 * half_w + 6.0, 0.70), (0.0, 0.0, 0.35),
            floor_mat, 0.035)
    # Expansion joints and a broken border.
    for i in range(n_bays):
        x = start + i * bay
        # Thin cross joints only.  A longitudinal joint down the centre read
        # as a black cable in the FPV camera and ruined the spawn composition.
        box((0.035, 2.0 * half_w + 2.0, 0.012), (x, 0.0, 0.706),
                "hall_dark", 0.0)

    # Column grid: two side rows plus an inner row on the big halls.
    inner = cfg.get("inner_columns", False)
    rows = [-half_w + 2.0, half_w - 2.0]
    if inner:
        rows += [-half_w * 0.38, half_w * 0.38]
    for i in range(n_bays + 1):
        x = start + i * bay
        broken = i in set(cfg.get("broken_columns", ()))
        for y in rows:
            if in_clear_lane(x, y, cfg):
                continue
            box((2.2, 2.2, 0.55), (x, y, 0.70 + 0.275), "hall_concrete", 0.03)
            if broken:
                h = RNG.uniform(2.8, 6.5)
                box((1.55, 1.55, h), (x, y, 0.98 + h * 0.5),
                        "hall_concrete", 0.02)
                for k in range(3):
                    box((RNG.uniform(0.4, 1.2), RNG.uniform(0.4, 1.1),
                            RNG.uniform(0.3, 0.8)),
                            (x + RNG.uniform(-0.6, 0.6), y + RNG.uniform(-0.6, 0.6),
                            0.98 + h + RNG.uniform(0.0, 0.5)),
                            "hall_concrete", 0.0,
                            (RNG.uniform(-0.4, 0.4), 0.0, RNG.uniform(0, 3.14)))
            else:
                box((1.5, 1.5, spring - 1.0), (x, y, 0.98 + (spring - 1.0) * 0.5),
                        "hall_concrete", 0.025)
                box((2.0, 2.0, 0.42), (x, y, spring - 0.1),
                        "hall_concrete", 0.02)
                # Rust streak down the column.
                box((0.05, 0.08, RNG.uniform(2.0, 5.5)),
                        (x + 0.77, y + 0.77, RNG.uniform(2.0, 6.0)),
                        "hall_rust", 0.0)
        # Main cross beam at each bay.
        box((0.55, 2.0 * half_w - 2.0, 0.85), (x, 0.0, spring - 0.3),
                "hall_concrete", 0.02)
        # Longitudinal beams over the side rows.
        if i < n_bays:
            for y in rows:
                box((bay, 0.75, 0.65), (x + bay * 0.5, y, spring - 0.35),
                        "hall_concrete", 0.02)

    # Side walls: piers, lower wall, window band and upper band.
    for side in (-1, 1):
        y = side * half_w
        for i in range(n_bays):
            x = start + (i + 0.5) * bay
            # Lower solid wall.
            box((bay - 0.2, 0.55, 2.2), (x, y, 1.1), wall_mat, 0.02)
            # Sill / upper band.
            box((bay - 0.2, 0.60, 1.1), (x, y, 2.65), wall_mat, 0.02)
            box((bay - 0.2, 0.55, spring - 9.2),
                    (x, y, 9.1 + (spring - 9.2) * 0.5), wall_mat, 0.02)
            # Piers at bay boundaries + exterior buttress relief.
            box((0.85, 0.95, spring - 1.2), (x - bay * 0.5, y + side * 0.18, 1.2
                    + (spring - 1.2) * 0.5), wall_mat, 0.025)
            box((1.15, 1.25, 3.2), (x - bay * 0.5, y + side * 0.32, 1.6),
                    "hall_concrete", 0.025)
            # Horizontal relief cornice and sill ledge on exterior facade.
            box((bay - 0.1, 0.85, 0.32), (x, y + side * 0.14, 9.0),
                    "hall_concrete", 0.015)
            box((bay - 0.1, 0.85, 0.28), (x, y + side * 0.14, 14.5),
                    "hall_concrete", 0.015)
            # Window frame and broken glazing.
            win_bottom, win_top = 3.3, 8.5
            box((bay - 0.4, 0.10, 0.12), (x, y - side * 0.02, win_bottom),
                    "hall_rust", 0.0)
            box((bay - 0.4, 0.10, 0.12), (x, y - side * 0.02, win_top),
                    "hall_rust", 0.0)
            for k in (-0.30, 0.0, 0.30):
                box((0.10, 0.10, win_top - win_bottom),
                        (x + k * bay, y - side * 0.02, (win_bottom + win_top) * 0.5),
                        "hall_rust", 0.0)
            if (i * 7 + (0 if side < 0 else 3)) % 5 != 0:
                box((bay - 0.55, 0.06, win_top - win_bottom - 0.2),
                        (x, y - side * 0.03, (win_bottom + win_top) * 0.5),
                        "hall_glass", 0.0)
            else:
                # Empty broken window: a few shards at the frame.
                for k in range(2):
                    box((bay * 0.16, 0.05, RNG.uniform(0.3, 1.0)),
                            (x + RNG.uniform(-bay * 0.3, bay * 0.3), y - side * 0.03,
                            RNG.uniform(win_bottom + 0.3, win_top - 0.3)),
                            "hall_glass", 0.0,
                            (RNG.uniform(-0.3, 0.3), 0.0, RNG.uniform(0, 3.14)))
        # Wall top cap.
        box((length - 0.4, 0.95, 0.55), (0.0, y, spring - 0.1), wall_mat, 0.02)

    # End walls with a wide central doorway and arched tympanum closing the barrel vault.
    door_w = cfg.get("door_w", 14.0)
    door_h = cfg.get("door_h", 11.0)
    for ex in (-length * 0.5, length * 0.5):
        for sy in (-1, 1):
            seg_w = half_w - door_w * 0.5
            box((0.9, seg_w, spring - 1.4), (ex,
                    sy * (door_w * 0.5 + seg_w * 0.5), 0.7 + (spring - 1.4) * 0.5),
                    wall_mat, 0.025)
            # Exterior vertical pilasters on the gable wall for strong 3D relief.
            for py in (door_w * 0.5 + 3.5, half_w - 2.5):
                box((1.35, 0.85, spring - 0.8), (ex, sy * py, 0.4 + (spring - 0.8) * 0.5),
                        "hall_concrete", 0.02)
        box((0.9, door_w, spring - door_h), (ex, 0.0,
                door_h + 0.7 + (spring - door_h) * 0.5), wall_mat, 0.025)
        # Arched gable tympanum from spring up to apex so the barrel end is closed.
        for a_step in range(7):
            frac = (a_step + 0.5) / 7.0
            zh = spring + frac * (apex - spring - 0.3)
            span_Ratio = math.sqrt(max(0.0, 1.0 - frac * frac))
            tymp_w = max(2.0, 2.0 * (half_w - 1.0) * span_Ratio)
            box((0.85, tymp_w, (apex - spring) / 6.5), (ex, 0.0, zh),
                    wall_mat, 0.02)
        # Door frame, broken edges and threshold.
        box((1.2, 0.6, door_h), (ex, -door_w * 0.5, 0.7 + door_h * 0.5),
                "hall_rust", 0.02)
        box((1.2, 0.6, door_h), (ex, door_w * 0.5, 0.7 + door_h * 0.5),
                "hall_rust", 0.02)
        box((1.2, door_w + 0.8, 0.6), (ex, 0.0, door_h + 0.6),
                "hall_rust", 0.02)
        # A few broken chunks around the doorway.
        for k in range(4):
            box((RNG.uniform(0.5, 1.8), RNG.uniform(0.5, 2.0),
                    RNG.uniform(0.4, 1.2)),
                    (ex + RNG.uniform(-0.8, 0.8),
                    RNG.uniform(-half_w, half_w), RNG.uniform(0.9, 4.5)),
                    "hall_concrete", 0.0, (RNG.uniform(-0.5, 0.5), 0.0,
                    RNG.uniform(0, 3.14)))

    # Door markers, used by Godot for the spawn and navigation.
    empty("door_west", (-length * 0.5, 0.0, 1.0))
    empty("door_east", (length * 0.5, 0.0, 1.0))

    # Annex / exterior silhouette for each theme.
    build_annex(cfg)


def build_annex(cfg):
    theme = cfg["theme"]
    half_w = cfg["half_w"]
    length = cfg["length"]
    annex_mat = cfg.get("annex_mat", cfg["wall_mat"])
    if theme == "industrial":
        bx, by = -length * 0.5 + 14.0, half_w + 5.8
        # Deep foundation plinth so the boiler house never floats on sloped ground.
        box((21.2, 13.2, 5.0), (bx, by, -2.2), "hall_concrete", 0.03)
        box((20.0, 12.0, 9.0), (bx, by, 4.5), "hall_brick", 0.03)
        box((21.0, 13.0, 1.0), (bx, by, 9.5), "hall_metal", 0.02)
        for px in (-7.5, -2.5, 2.5, 7.5):
            box((0.65, 12.5, 8.8), (bx + px, by, 4.5), "hall_concrete", 0.02)
            box((2.2, 12.6, 2.4), (bx + px, by, 5.2), "hall_dark", 0.01)
        # Overhead steam duct bridge into the main hall.
        beam_between((bx, by - 5.5, 7.2), (bx, half_w, 7.2), 1.4, "hall_rust")
    elif theme == "village":
        # Grain dryer / weighbridge annex on the north side of the repair shed (silos are built as OpenTowers in Godot).
        bx, by = -length * 0.22, half_w + 5.2
        box((17.0, 11.0, 5.0), (bx, by, -2.2), "hall_concrete", 0.03)
        box((16.0, 10.0, 8.2), (bx, by, 4.1), "hall_brick", 0.03)
        box((17.0, 11.0, 0.9), (bx, by, 8.5), "hall_rust", 0.02)
        for px in (-5.5, 0.0, 5.5):
            box((0.55, 10.5, 8.0), (bx + px, by, 4.1), "hall_concrete", 0.02)
    elif theme == "steppe":
        # Ore classifier annex along the north wall with a conveyor bridge.
        bx, by = -length * 0.18, half_w + 6.5
        box((14.4, 15.6, 5.0), (bx, by, -2.2), "hall_concrete", 0.03)
        box((13.0, 14.5, 11.0), (bx, by, 5.5), "hall_concrete", 0.03)
        cone(6.5, 1.5, 4.5, (bx, by, 13.0), "hall_rust", vertices=16)
        beam_between((bx, half_w, 8.5), (bx, by - 4.0, 11.5),
                2.4, "hall_rust", width_y=2.0)
        for px in (-4.5, 0.0, 4.5):
            box((0.6, 15.0, 10.6), (bx + px, by, 5.4), "hall_rust", 0.02)
    elif theme == "wetlands":
        # Pump-house annex and intake pipes into the water with a deep concrete foundation.
        bx, by = -length * 0.25, -half_w - 5.5
        box((19.2, 12.2, 5.2), (bx, by, -2.3), "hall_concrete", 0.03)
        box((18.0, 11.0, 8.0), (bx, by, 4.0), "hall_concrete", 0.03)
        box((19.0, 12.0, 0.8), (bx, by, 8.4), "hall_metal", 0.02)
        for px in (-6.0, 0.0, 6.0):
            box((0.6, 11.5, 7.8), (bx + px, by, 4.0), "hall_rust", 0.02)
        for i in range(3):
            cyl(0.8, 12.0, (bx - 4.0 + i * 4.0, by - 4.5, 1.8),
                    "hall_rust", (math.pi * 0.5, 0.0, 0.0), vertices=12)


# ------------------------------------------------------------------ catwalks
def build_catwalks(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    levels = cfg.get("levels", (8.0, 15.0, 22.0))
    deck_mat = cfg.get("deck_mat", "hall_floor")
    rail_mat = cfg.get("rail_mat", "hall_rust")
    bay = cfg["bay"]
    start = -length * 0.5
    for side in (-1, 1):
        y = side * (half_w - 2.6)
        for li, z in enumerate(levels):
            # Deck in segments with damaged gaps.
            seg = 0.0
            while seg < length - 6.0:
                run = RNG.uniform(9.0, 16.0)
                if run > length - 6.0 - seg:
                    run = length - 6.0 - seg
                x0 = start + 3.0 + seg
                gap = 0.0
                if seg > 3.0 and RNG.random() < 0.22:
                    gap = RNG.uniform(1.0, 2.2)
                if gap > 0.0:
                    seg += gap
                    continue
                box((run, 4.6, 0.28), (x0 + run * 0.5, y, z), deck_mat, 0.015)
                # Railings: posts plus two rails, with missing sections.
                n_posts = max(2, int(run / 2.6))
                for k in range(n_posts + 1):
                    if RNG.random() < 0.10:
                        continue
                    px = x0 + run * k / n_posts
                    box((0.08, 0.08, 1.25), (px, y - side * 2.1, z + 0.7),
                            rail_mat, 0.0)
                for rz in (0.45, 1.0, 1.30):
                    if RNG.random() < 0.12:
                        continue
                    box((run, 0.08, 0.08), (x0 + run * 0.5,
                            y - side * 2.1, z + rz), rail_mat, 0.0)
                # Support brackets.
                for k in range(int(run / 4.0) + 1):
                    px = x0 + 1.0 + k * 4.0
                    beam_between((px, side * (half_w - 0.4), z - 0.3),
                            (px, y, z - 0.3), 0.16, rail_mat)
                    beam_between((px, side * (half_w - 0.4), z - 3.0),
                            (px, y - side * 1.5, z - 0.4), 0.14, rail_mat)
                seg += run
            # Stairs between levels at the west end.
            if li < len(levels) - 1:
                build_stairs(cfg, side, z, levels[li + 1])
    # Cross bridges: one at the top (the crane level) and one low enough to be
    # inside the spawn frame, like the reference's stacked galleries.
    for bx, z in ((-length * 0.24, levels[-1] - 0.15),
            (-length * 0.30, levels[0]), (length * 0.18, levels[0])):
        box((4.4, half_w * 2.0 - 4.0, 0.30), (bx, 0.0, z), deck_mat, 0.02)
        for side in (-1, 1):
            for xoff in (-2.0, 2.0):
                box((0.09, 0.09, 1.2), (bx + xoff, side * (half_w - 2.4), z + 0.7),
                        rail_mat, 0.0)
        for k in range(6):
            box((4.2, 0.08, 0.08), (bx, -half_w + 2.0 + k * (half_w * 2.0 - 4.0) / 5.0,
                    z + 1.0 if k % 2 == 0 else z + 0.5), rail_mat, 0.0)

    # Ladders along the walls.
    for side in (-1, 1):
        for x in (-length * 0.38, length * 0.38):
            y = side * (half_w - 0.8)
            for k in range(12):
                box((0.7, 0.06, 0.06), (x, y, 2.0 + k * 1.1), rail_mat, 0.0)
            box((0.06, 0.08, levels[-1] - 2.0), (x - 0.35, y, (levels[-1] + 2.0) * 0.5),
                    rail_mat, 0.0)
            box((0.06, 0.08, levels[-1] - 2.0), (x + 0.35, y, (levels[-1] + 2.0) * 0.5),
                    rail_mat, 0.0)

    # Catwalk clutter.
    for side in (-1, 1):
        for li, z in enumerate(levels):
            for k in range(5):
                x = RNG.uniform(-length * 0.42, length * 0.42)
                y = side * (half_w - 2.6) + RNG.uniform(-1.2, 1.2)
                if RNG.random() < 0.55:
                    box((RNG.uniform(0.5, 1.1), RNG.uniform(0.5, 1.1),
                            RNG.uniform(0.4, 0.9)), (x, y, z + 0.35),
                            "hall_rust", 0.01, (0, 0, RNG.uniform(0, 3.14)))
                else:
                    cyl(RNG.uniform(0.25, 0.42), RNG.uniform(0.7, 1.1),
                            (x, y, z + 0.55), "hall_rust", (0, 0, 0), 10)


def build_stairs(cfg, side, z0, z1):
    length = cfg["length"]
    x0 = -length * 0.5 + 4.0
    y = side * (cfg["half_w"] - 2.6)
    steps = 12
    for i in range(steps):
        t = i / steps
        box((0.65, 3.2, 0.16), (x0 + t * 4.0, y, z0 + (z1 - z0) * t),
                "hall_metal", 0.0)
    beam_between((x0, y - 1.5, z0), (x0 + 4.0, y - 1.5, z1), 0.14,
            "hall_rust")
    beam_between((x0, y + 1.5, z0), (x0 + 4.0, y + 1.5, z1), 0.14,
            "hall_rust")


# ------------------------------------------------------------------ props
def build_crane(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    z = cfg.get("crane_z", 12.5)
    for y in (-half_w + 4.0, half_w - 4.0):
        box((length - 4.0, 0.42, 0.42), (0.0, y, z), "hall_metal", 0.02)
        box((length - 4.0, 0.55, 0.16), (0.0, y, z - 0.25), "hall_rust", 0.0)
    bx = -length * 0.22
    box((1.1, 2.0 * half_w - 8.0, 1.0), (bx, 0.0, z + 0.6),
            "hall_metal", 0.02)
    box((2.0, 2.4, 1.1), (bx, 0.0, z + 1.4), "hall_rust", 0.02)
    cyl(0.05, z - 1.0, (bx, 0.0, (z - 1.0) * 0.5 + 1.0), "hall_dark", vertices=6)
    box((0.7, 0.9, 0.7), (bx, 0.0, 2.2), "hall_rust", 0.02)
    for k in range(8):
        box((0.12, 0.12, 0.20), (bx + 0.5, 0.0, 1.0 + k * 0.16),
                "hall_dark", 0.0)


def build_pipes(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    spring = cfg["spring"]
    for side in (-1, 1):
        y = side * (half_w - 1.5)
        for j, (z, r) in enumerate(((8.2, 0.22), (9.2, 0.16),
                (10.4, 0.30))):
            cyl(r, length - 4.0, (0.0, y, z), "hall_metal",
                    (0.0, math.pi * 0.5, 0.0), 10)
            for i in range(9):
                cyl(r * 1.35, 0.22, (-length * 0.42 + i * length * 0.105, y, z),
                        "hall_rust", (0.0, math.pi * 0.5, 0.0), 10)
        # Cable trays.
        box((length - 4.0, 0.55, 0.10), (0.0, y, 6.4), "hall_metal", 0.0)
        box((length - 4.0, 0.06, 0.22), (0.0, y - 0.22, 6.55),
                "hall_metal", 0.0)
        box((length - 4.0, 0.06, 0.22), (0.0, y + 0.22, 6.55),
                "hall_metal", 0.0)
    # Overhead pipes crossing the nave.
    for i in range(4):
        x = -length * 0.32 + i * length * 0.22
        for j in range(3):
            cyl(0.12 + j * 0.03, 2.0 * half_w - 5.0,
                    (x + j * 0.6, 0.0, spring - 1.2 - j * 0.45),
                    "hall_metal", (math.pi * 0.5, 0.0, 0.0), 10)


def build_machine_factory(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    # Lathe.
    x, y = -length * 0.30, half_w - 5.5
    box((5.2, 1.4, 0.9), (x, y, 1.15), "hall_metal", 0.03)
    box((1.4, 1.2, 1.2), (x - 1.8, y, 2.1), "hall_metal", 0.02)
    box((1.0, 1.0, 1.0), (x + 2.0, y, 1.9), "hall_metal", 0.02)
    cyl(0.5, 3.0, (x, y, 2.1), "hall_rust", (0.0, math.pi * 0.5, 0.0), 12)
    # Press.
    x += 7.0
    box((3.0, 3.0, 0.8), (x, y, 1.1), "hall_metal", 0.03)
    for dx in (-1.0, 1.0):
        box((0.35, 0.35, 3.0), (x + dx, y, 2.8), "hall_metal", 0.01)
    box((2.4, 2.0, 0.7), (x, y, 4.3), "hall_metal", 0.02)
    box((1.0, 1.0, 0.6), (x, y, 2.4), "hall_rust", 0.02)
    # Generator / turbine.
    x, y = length * 0.18, -half_w + 5.0
    box((4.5, 2.0, 0.7), (x, y, 1.05), "hall_metal", 0.02)
    cyl(1.3, 4.0, (x - 0.7, y, 2.2), "hall_metal",
            (0.0, math.pi * 0.5, 0.0), 18)
    cyl(1.5, 0.5, (x - 2.7, y, 2.2), "hall_rust",
            (0.0, math.pi * 0.5, 0.0), 18)
    box((1.6, 1.6, 1.4), (x + 2.2, y, 1.8), "hall_metal", 0.02)
    # Control cabinets.
    for i in range(4):
        box((1.4, 0.8, 2.3), (-length * 0.10 + i * 1.8, half_w - 7.0, 1.85),
                "hall_paint", 0.02)
        for k in range(3):
            cyl(0.10, 0.10, (-length * 0.10 + i * 1.8, half_w - 7.45,
                    1.4 + k * 0.45), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 8)
    # Forklift silhouette.
    x, y = length * 0.33, half_w - 8.0
    box((2.6, 1.4, 1.0), (x, y, 1.0), "hall_paint", 0.02)
    box((1.5, 1.2, 1.4), (x - 0.4, y, 2.1), "hall_paint", 0.02)
    box((0.15, 1.4, 3.0), (x + 1.0, y, 1.8), "hall_metal", 0.0)
    box((1.8, 0.8, 0.15), (x + 1.8, y, 0.75), "hall_metal", 0.0)
    for dx in (-0.8, 0.8):
        for dy in (-0.7, 0.7):
            cyl(0.45, 0.3, (x + dx, y + dy, 0.55), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 12)
    # Near-spawn machining island: the operator sees tools and a toppled
    # turbine before reaching the central collapse.
    x, y = 31.0, -13.0
    box((4.2, 1.4, 0.9), (x, y, 1.15), "hall_metal", 0.02)
    box((1.2, 1.1, 1.2), (x - 1.5, y, 2.05), "hall_metal", 0.02)
    cyl(0.45, 2.4, (x, y, 2.0), "hall_rust",
            (0.0, math.pi * 0.5, 0.0), 12)
    x, y = 27.0, 13.0
    box((3.0, 3.0, 0.8), (x, y, 1.1), "hall_metal", 0.02)
    for dx in (-1.0, 1.0):
        box((0.35, 0.35, 3.0), (x + dx, y, 2.8), "hall_metal", 0.0)
    box((2.4, 2.0, 0.7), (x, y, 4.3), "hall_metal", 0.02)
    box((1.0, 1.0, 0.6), (x, y, 2.4), "hall_rust", 0.02)
    # Toppled turbine in the near nave.
    box((4.0, 1.6, 0.6), (24.0, 0.0, 1.0), "hall_metal", 0.02)
    cyl(1.35, 6.0, (24.0, 0.0, 2.3), "hall_metal",
            (0.0, math.pi * 0.5, 0.0), 18)
    cyl(1.5, 0.5, (21.0, 0.0, 2.3), "hall_rust",
            (0.0, math.pi * 0.5, 0.0), 18)


def build_machine_repair(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    # Tractor on blocks.
    x, y = -length * 0.18, half_w - 6.0
    box((3.2, 1.6, 0.8), (x, y, 1.3), "hall_paint", 0.03)
    box((1.4, 1.3, 1.3), (x - 0.6, y, 2.3), "hall_paint", 0.02)
    box((0.5, 0.5, 1.5), (x + 1.2, y, 2.8), "hall_dark", 0.0)
    for dx in (-1.2, 1.2):
        for dy in (-0.85, 0.85):
            cyl(0.65, 0.35, (x + dx, y + dy, 1.0), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 14)
    box((0.8, 0.5, 0.7), (x + 0.6, y, 2.1), "hall_metal", 0.02)
    # Engine hoist.
    x += 6.0
    beam_between((x, y, 0.9), (x, y, 4.4), 0.16, "hall_rust")
    beam_between((x, y, 4.4), (x + 2.4, y, 3.4), 0.16, "hall_rust")
    beam_between((x, y, 2.2), (x + 2.4, y, 3.4), 0.12, "hall_rust")
    cyl(0.04, 2.0, (x + 2.4, y, 2.4), "hall_dark", vertices=6)
    box((0.5, 0.5, 0.4), (x + 2.4, y, 1.3), "hall_rust", 0.01)
    # Workbench and tool wall.
    x, y = length * 0.12, -half_w + 4.5
    box((5.0, 1.2, 0.9), (x, y, 1.1), "hall_wood", 0.02)
    for i in range(8):
        box((0.25, 0.1, 0.25), (x - 2.0 + i * 0.55, y - 0.6, 1.7),
                "hall_metal", 0.0)
    box((3.0, 0.2, 2.5), (x, y - 0.75, 2.4), "hall_paint", 0.01)
    # Tire stacks and welding bottles.
    for i in range(3):
        for k in range(4):
            cyl(0.55, 0.38, (x - 5.0 + i * 1.4, y + 2.8 + k * 0.38, 0.9),
                    "hall_dark", (math.pi * 0.5, 0.0, 0.0), 14)
    for i in range(3):
        cyl(0.18, 1.4, (x + 1.0 + i * 0.5, y + 2.0, 1.0),
                "hall_paint", vertices=10)
    # Grain chutes and sacks at the silo end.
    for i in range(3):
        beam_between((length * 0.42, -half_w + 4.0 + i * 2.0, 8.0),
                (length * 0.30, -half_w + 6.0 + i * 2.0, 2.0),
                0.5, "hall_metal", width_y=0.8)
    for i in range(8):
        box((0.9, 0.6, 0.5), (length * 0.26 + (i % 4) * 0.9,
                -half_w + 5.0 + (i // 4) * 0.8, 0.95),
                "hall_wood", 0.01, (0, 0, RNG.uniform(0, 1.0)))
    # Second tractor and a repair bench in the near bay.
    x, y = 30.0, 12.0
    box((3.2, 1.6, 0.8), (x, y, 1.3), "hall_paint", 0.03)
    box((1.4, 1.3, 1.3), (x - 0.6, y, 2.3), "hall_paint", 0.02)
    box((0.5, 0.5, 1.5), (x + 1.2, y, 2.8), "hall_dark", 0.0)
    for dx in (-1.2, 1.2):
        for dy in (-0.85, 0.85):
            cyl(0.65, 0.35, (x + dx, y + dy, 1.0), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 14)
    x, y = 30.0, -12.0
    box((5.0, 1.2, 0.9), (x, y, 1.1), "hall_wood", 0.02)
    box((3.0, 0.2, 2.2), (x, y - 0.7, 2.2), "hall_paint", 0.01)
    for i in range(5):
        box((0.25, 0.12, 0.25), (x - 2.0 + i * 0.7, y - 0.6, 1.7),
                "hall_metal", 0.0)


def build_machine_mine(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    # Crusher.
    x, y = -length * 0.26, half_w - 7.0
    box((5.0, 4.0, 1.2), (x, y, 1.2), "hall_concrete", 0.03)
    box((3.2, 3.0, 2.6), (x, y, 3.1), "hall_metal", 0.03)
    cone(2.0, 0.8, 2.0, (x, y, 5.4), "hall_rust", vertices=16)
    cyl(0.8, 1.4, (x + 2.4, y, 2.2), "hall_metal",
            (0.0, math.pi * 0.5, 0.0), 12)
    # Inclined conveyor with legs.
    x0, y0, z0 = x + 2.0, y - 1.0, 2.0
    x1, y1, z1 = length * 0.30, y - 1.0, 9.0
    beam_between((x0, y0, z0), (x1, y1, z1), 1.6, "hall_rust", width_y=1.1)
    for i in range(6):
        t = i / 6.0
        px = x0 + (x1 - x0) * t
        pz = z0 + (z1 - z0) * t
        beam_between((px, y0 - 1.0, 0.75), (px, y0 - 1.0, pz), 0.14,
                "hall_metal")
        beam_between((px, y0 + 1.0, 0.75), (px, y0 + 1.0, pz), 0.14,
                "hall_metal")
    # Vibrating screen.
    x, y = length * 0.12, -half_w + 7.0
    box((3.6, 4.0, 0.8), (x, y, 2.1), "hall_metal", 0.02)
    for i in range(10):
        box((0.08, 3.8, 0.08), (x - 1.6 + i * 0.35, y, 2.55),
                "hall_rust", 0.0)
    for dx in (-1.4, 1.4):
        for dy in (-1.6, 1.6):
            beam_between((x + dx, y + dy, 0.75), (x + dx, y + dy, 1.9),
                    0.18, "hall_metal")
    # Ore chute / silo.
    x, y = length * 0.30, -half_w + 5.0
    cyl(2.6, 5.0, (x, y, 4.0), "hall_concrete", vertices=20)
    cone(2.8, 0.7, 2.5, (x, y, 1.3), "hall_rust", vertices=20)
    # Rail cart and track.
    for i in range(2):
        box((14.0, 0.15, 0.15), (0.0, -half_w + 2.5 + i * 1.2, 0.85),
                "hall_rust", 0.0)
    x, y = -length * 0.05, -half_w + 3.1
    box((2.6, 1.8, 1.2), (x, y, 1.6), "hall_rust", 0.02)
    box((2.4, 1.6, 1.0), (x, y, 2.6), "hall_dark", 0.0)
    for dx in (-0.8, 0.8):
        for dy in (-0.8, 0.8):
            cyl(0.28, 0.18, (x + dx, y + dy, 0.9), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 10)
    # Second crusher and a short conveyor in the near bay.
    x, y = 26.0, 13.0
    box((4.0, 3.2, 1.1), (x, y, 1.2), "hall_concrete", 0.03)
    box((2.8, 2.6, 2.2), (x, y, 2.9), "hall_metal", 0.03)
    cone(1.8, 0.7, 1.8, (x, y, 5.0), "hall_rust", vertices=16)
    beam_between((x + 1.8, y, 2.6), (x + 18.0, y, 7.2), 1.4,
            "hall_rust", width_y=1.0)
    for i in range(4):
        beam_between((x + 4.0 + i * 4.0, y - 0.9, 0.8),
                (x + 4.0 + i * 4.0, y - 0.9, 3.4 + i * 1.1), 0.13,
                "hall_metal")
    # A rail cart in the near aisle.
    x, y = 34.0, -12.0
    box((2.6, 1.8, 1.2), (x, y, 1.6), "hall_rust", 0.02)
    box((2.4, 1.6, 1.0), (x, y, 2.6), "hall_dark", 0.0)
    for dx in (-0.8, 0.8):
        for dy in (-0.8, 0.8):
            cyl(0.28, 0.18, (x + dx, y + dy, 0.9), "hall_dark",
                    (math.pi * 0.5, 0.0, 0.0), 10)
    # Rock piles.
    for i in range(6):
        rubble(RNG.uniform(-length * 0.35, length * 0.35),
                RNG.uniform(-half_w + 3.0, half_w - 3.0), 0.85,
                RNG.uniform(1.2, 2.8), 18, RNG.uniform(0.3, 1.4),
                ("hall_gravel", "hall_concrete"))


def build_machine_pump(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    # Pump sets on concrete plinths.
    for i in range(3):
        x = -length * 0.26 + i * 7.0
        y = half_w - 6.0
        box((4.0, 2.4, 0.8), (x, y, 1.1), "hall_concrete", 0.02)
        cyl(1.0, 3.0, (x - 0.7, y, 2.1), "hall_metal",
                (0.0, math.pi * 0.5, 0.0), 18)
        box((1.4, 1.2, 1.6), (x + 1.4, y, 1.9), "hall_paint", 0.02)
        cyl(0.45, 0.8, (x - 1.8, y, 2.1), "hall_rust",
                (0.0, math.pi * 0.5, 0.0), 14)
    # Valve manifold and big pipes.
    for i in range(4):
        cyl(0.35, 8.0, (length * 0.05 + i * 1.2, -half_w + 3.0, 1.6),
                "hall_rust", (0.0, 0.0, 0.0), 12)
        cyl(0.6, 0.4, (length * 0.05 + i * 1.2, -half_w + 3.0, 4.0),
                "hall_metal", vertices=12)
    # Water tank / surge vessel.
    x, y = length * 0.28, half_w - 6.0
    cyl(3.2, 7.0, (x, y, 4.0), "hall_metal", vertices=20)
    cone(3.4, 1.0, 2.0, (x, y, 8.0), "hall_rust", vertices=20)
    # Grated service platform over the flooded nave.
    box((10.0, 5.0, 0.18), (-length * 0.10, 0.0, 3.2), "hall_metal", 0.0)
    for i in range(10):
        box((10.0, 0.06, 0.08), (-length * 0.10, -2.2 + i * 0.5, 3.35),
                "hall_rust", 0.0)
    for dx in (-4.8, 4.8):
        for dy in (-2.3, 2.3):
            box((0.08, 0.08, 1.2), (-length * 0.10 + dx, dy, 3.9),
                    "hall_rust", 0.0)
    # Pipes crossing the nave above the water.
    for i in range(3):
        cyl(0.30, 2.0 * half_w - 4.0, (-length * 0.28 + i * 3.0, 0.0,
                8.5 + i * 0.6), "hall_rust", (math.pi * 0.5, 0.0, 0.0), 12)
    # Near-spawn pump pair and valve station, standing above the flood.
    x, y = 27.0, 12.0
    box((3.8, 2.2, 0.8), (x, y, 1.1), "hall_concrete", 0.02)
    cyl(0.95, 2.8, (x - 0.6, y, 2.1), "hall_metal",
            (0.0, math.pi * 0.5, 0.0), 16)
    box((1.3, 1.1, 1.5), (x + 1.3, y, 1.9), "hall_paint", 0.02)
    x, y = 30.0, -12.0
    for i in range(4):
        cyl(0.30, 7.0, (x - 2.0 + i * 1.3, y, 1.6),
                "hall_rust", (0.0, 0.0, 0.0), 12)
        cyl(0.55, 0.4, (x - 2.0 + i * 1.3, y, 3.8),
                "hall_metal", vertices=12)
    # Half-sunken workboat in the flooded bay.
    x, y = length * 0.24, -half_w + 7.0
    box((9.0, 3.2, 1.6), (x, y, 1.3), "hall_rust", 0.05)
    box((7.0, 2.4, 1.0), (x + 1.0, y, 2.3), "hall_dark", 0.02)
    beam_between((x + 4.5, y, 1.8), (x + 6.5, y, 3.2), 0.2, "hall_metal")


def rubble(cx, cy, cz, radius, count, height, mats):
    for _ in range(count):
        ang = RNG.uniform(0, math.tau)
        r = RNG.uniform(0, radius)
        x = cx + math.cos(ang) * r
        y = cy + math.sin(ang) * r
        sx = RNG.uniform(0.35, 2.4)
        sy = RNG.uniform(0.35, 2.0)
        sz = RNG.uniform(0.12, 0.65)
        box((sx, sy, sz), (x, y, cz + sz * 0.5 + RNG.uniform(0, height)),
                RNG.choice(mats), 0.01,
                (RNG.uniform(-0.7, 0.7), RNG.uniform(-0.7, 0.7),
                 RNG.uniform(0, math.tau)))


def build_debris(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    theme = cfg["theme"]
    # Edge rubble piles.
    for i in range(10):
        side = -1 if i % 2 == 0 else 1
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = side * RNG.uniform(half_w - 10.0, half_w - 3.0)
        if in_clear_lane(x, y, cfg):
            continue
        rubble(x, y, 0.71, RNG.uniform(1.5, 4.5),
                RNG.randint(10, 28), RNG.uniform(0.2, 1.8),
                ("hall_concrete", "hall_floor", "hall_moss"))
    # The collapsed roof section dumps its material into the nave.
    coll = cfg.get("collapsed_x", 0.0)
    rubble(coll, RNG.uniform(-half_w * 0.4, half_w * 0.4), 0.71,
            RNG.uniform(5.0, 8.0), 55, RNG.uniform(1.0, 3.5),
            ("hall_concrete", "hall_floor", "hall_rust"))
    # The spawn view needs a foreground frame, not a clean empty runway: a
    # sheared column and two fallen beams on each side, 15-20 m ahead of the
    # camera, with rubble spilling towards the aisle.
    lane = cfg.get("lane", (0.0, 0.0, 4.0))
    fx = float(lane[0]) - 14.0
    for side in (-1, 1):
        px = fx + side * 3.0
        py = side * 8.0
        box((1.5, 1.5, 4.4), (px, py, 2.9), "hall_concrete", 0.02)
        for k in range(4):
            box((RNG.uniform(0.5, 1.4), RNG.uniform(0.4, 1.2),
                    RNG.uniform(0.3, 0.7)),
                    (px + RNG.uniform(-0.8, 0.8), py + RNG.uniform(-0.8, 0.8),
                     5.1 + k * 0.22), "hall_concrete", 0.0,
                    (RNG.uniform(-0.5, 0.5), 0.0, RNG.uniform(0, math.tau)))
        beam_between((px, py, 1.0), (px - 9.0, py + side * 2.0, 5.2),
                RNG.uniform(0.32, 0.48), "hall_rust")
        rubble(px, py + side * 2.0, 0.72, 3.2, 14, 1.2,
                ("hall_floor", "hall_concrete", "hall_rust"))
    # Low rubble field across the near nave so the floor is broken up by the
    # time the reference shot reaches the first columns.
    for i in range(7):
        lx = RNG.uniform(float(lane[0]) - 30.0, float(lane[0]) - 8.0)
        ly = RNG.uniform(-half_w * 0.42, half_w * 0.42)
        if in_clear_lane(lx, ly, cfg):
            continue
        rubble(lx, ly, 0.72, RNG.uniform(1.4, 3.4), 14,
                RNG.uniform(0.3, 1.6),
                ("hall_floor", "hall_concrete", "hall_rust"))
    for i in range(3):
        ly = RNG.uniform(-half_w * 0.3, half_w * 0.3)
        beam_between((float(lane[0]) - 20.0 - i * 5.0, ly, 0.9),
                (float(lane[0]) - 30.0 - i * 4.0, ly + RNG.uniform(-4, 4),
                RNG.uniform(2.2, 5.0)), RNG.uniform(0.28, 0.44), "hall_rust")
    # Shattered slab islands.
    for i in range(18):
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = RNG.uniform(-half_w + 4.0, half_w - 4.0)
        if in_clear_lane(x, y, cfg):
            continue
        box((RNG.uniform(1.2, 4.0), RNG.uniform(0.8, 2.4),
                RNG.uniform(0.10, 0.40)), (x, y, 0.78),
                "hall_floor", 0.01,
                (RNG.uniform(-0.15, 0.15), RNG.uniform(-0.20, 0.20),
                 RNG.uniform(0, math.tau)))
    # Dark collapsed pockets in the slab.  The real floor is one poured slab;
    # these black pockets plus a broken rim read as holes without cutting the
    # collision mesh into expensive islands.
    for i in range(6):
        x = RNG.uniform(-length * 0.38, length * 0.38)
        y = RNG.uniform(-half_w + 4.0, half_w - 4.0)
        if in_clear_lane(x, y, cfg):
            continue
        hx = RNG.uniform(1.6, 5.0)
        hy = RNG.uniform(1.2, 3.8)
        box((hx, hy, 0.025), (x, y, 0.716), "hall_dark", 0.0,
                (0.0, 0.0, RNG.uniform(0, math.tau)))
        for k in range(7):
            box((RNG.uniform(0.4, 1.4), RNG.uniform(0.3, 0.9),
                    RNG.uniform(0.15, 0.5)),
                    (x + RNG.uniform(-hx, hx) * 0.6,
                    y + RNG.uniform(-hy, hy) * 0.6, 0.85),
                    "hall_floor", 0.0,
                    (RNG.uniform(-0.4, 0.4), RNG.uniform(-0.4, 0.4),
                     RNG.uniform(0, math.tau)))
    # Rebar bundles.
    for i in range(14):
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = RNG.uniform(-half_w + 4.0, half_w - 4.0)
        if in_clear_lane(x, y, cfg):
            continue
        bx = x + RNG.uniform(-2.0, 2.0)
        by = y + RNG.uniform(-1.5, 1.5)
        beam_between((x, y, 0.85), (bx, by, RNG.uniform(1.1, 2.8)),
                0.05, "hall_rust")
    # Bricks, planks and barrels.
    for i in range(40):
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = RNG.uniform(-half_w + 3.0, half_w - 3.0)
        if in_clear_lane(x, y, cfg):
            continue
        if RNG.random() < 0.4:
            box((RNG.uniform(0.4, 1.2), RNG.uniform(0.2, 0.4), 0.18),
                    (x, y, 0.85), "hall_brick", 0.0,
                    (0, 0, RNG.uniform(0, math.tau)))
        elif RNG.random() < 0.5:
            cyl(RNG.uniform(0.25, 0.42), RNG.uniform(0.7, 1.1),
                    (x, y, 1.2), "hall_rust", (0, 0, 0), 10)
        else:
            box((RNG.uniform(0.8, 2.2), RNG.uniform(0.15, 0.3), 0.12),
                    (x, y, 0.86), "hall_wood", 0.0,
                    (0, 0, RNG.uniform(0, math.tau)))
    # Moss patches and puddles.
    for i in range(30):
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = RNG.uniform(-half_w + 3.0, half_w - 3.0)
        if in_clear_lane(x, y, cfg):
            continue
        p = cyl(RNG.uniform(0.3, 1.4), 0.012, (x, y, 0.725),
                "hall_moss", (0, 0, 0), 12)
        p.scale = (1.0, RNG.uniform(0.5, 1.0), 1.0)
    for i in range(10):
        x = RNG.uniform(-length * 0.42, length * 0.42)
        y = RNG.uniform(-half_w + 4.0, half_w - 4.0)
        if in_clear_lane(x, y, cfg):
            continue
        p = cyl(RNG.uniform(0.6, 2.0), 0.008, (x, y, 0.721),
                "hall_water", (0, 0, 0), 12)
        p.scale = (1.0, RNG.uniform(0.5, 1.0), 1.0)
    # Ivy on a few columns.
    for i in range(18):
        x = RNG.uniform(-length * 0.40, length * 0.40)
        side = -1 if i % 2 == 0 else 1
        y = side * (half_w - 2.0)
        for k in range(3):
            beam_between((x + RNG.uniform(-0.4, 0.4), y,
                    RNG.uniform(0.8, 2.0)),
                    (x + RNG.uniform(-0.4, 0.4), y,
                    RNG.uniform(3.0, 8.0)), 0.04, "hall_moss")
    # Fallen beams across the nave.
    for i in range(8):
        x = RNG.uniform(-length * 0.35, length * 0.35)
        y = RNG.uniform(-half_w + 5.0, half_w - 5.0)
        if in_clear_lane(x, y, cfg):
            continue
        beam_between((x, y, 0.9), (x + RNG.uniform(-12, 12),
                y + RNG.uniform(-8, 8), RNG.uniform(2.5, 7.0)),
                RNG.uniform(0.25, 0.5), "hall_rust")


def build_lamp_fixtures(cfg):
    length = cfg["length"]
    half_w = cfg["half_w"]
    spring = cfg["spring"]
    for i in range(4):
        x = -length * 0.35 + i * length * 0.23
        for side in (-1, 1):
            y = side * (half_w - 1.2)
            z = spring - 2.5
            cyl(0.30, 0.12, (x, y, z), "hall_dark", vertices=12)
            box((0.05, 0.05, 1.0), (x, y, z + 0.55), "hall_dark", 0.0)
            empty("lamp_%02d_%d" % (i, 0 if side < 0 else 1),
                    (x, y, z - 0.1))


# ------------------------------------------------------------------ themes
THEMES = {
    "industrial": {
        "theme": "industrial",
        "length": 120.0, "half_w": 27.0, "spring": 22.0, "apex": 32.0,
        "bay": 8.0, "levels": (8.0, 15.0, 22.0),
        "wall_mat": "hall_concrete", "roof_mat": "hall_metal",
        "floor_mat": "hall_floor", "inner_columns": True,
        "broken_bays": (4, 10), "collapsed_bay": 8,
        "broken_columns": (3, 11),
        "glazing": (4, 5, 14, 15),
        "door_w": 15.0, "door_h": 12.0,
        "lane": (54.0, 61.0, 4.5),
        "collapsed_x": 0.0,
    },
    "village": {
        "theme": "village",
        "length": 96.0, "half_w": 23.0, "spring": 16.0, "apex": 25.0,
        "bay": 8.0, "levels": (7.0, 13.0),
        "wall_mat": "hall_brick", "roof_mat": "hall_wood",
        "floor_mat": "hall_floor", "inner_columns": False,
        "broken_bays": (7,), "collapsed_bay": 3,
        "broken_columns": (5,),
        "glazing": (5, 6, 13, 14),
        "door_w": 11.0, "door_h": 9.0,
        "lane": (39.0, 53.0, 4.0),
        "collapsed_x": -12.0,
    },
    "steppe": {
        "theme": "steppe",
        "length": 112.0, "half_w": 25.0, "spring": 20.5, "apex": 30.0,
        "bay": 8.0, "levels": (7.5, 14.0, 20.0),
        "wall_mat": "hall_concrete", "roof_mat": "hall_metal",
        "floor_mat": "hall_floor", "inner_columns": True,
        "broken_bays": (2, 9), "collapsed_bay": 6,
        "broken_columns": (8,),
        "glazing": (4, 5, 14, 15),
        "door_w": 14.0, "door_h": 11.0,
        "lane": (45.0, 58.0, 4.0),
        "collapsed_x": -18.0,
    },
    "wetlands": {
        "theme": "wetlands",
        "length": 104.0, "half_w": 24.0, "spring": 19.5, "apex": 29.0,
        "bay": 8.0, "levels": (6.5, 13.0, 19.0),
        "wall_mat": "hall_concrete", "roof_mat": "hall_metal",
        "floor_mat": "hall_floor", "inner_columns": False,
        "broken_bays": (1, 6, 11), "collapsed_bay": 8,
        "broken_columns": (2, 9),
        "glazing": (4, 5, 14, 15),
        "door_w": 13.0, "door_h": 10.0,
        "lane": (42.0, 54.0, 4.0),
        "collapsed_x": 15.0,
    },
}

ORDER = ("industrial", "village", "steppe", "wetlands")


def build(cfg):
    global RNG
    RNG = random.Random(cfg.get("seed", 1986) + ORDER.index(cfg["theme"]) * 73)
    print("[Hall]  shell", flush=True)
    build_shell(cfg)
    print("[Hall]  roof", flush=True)
    build_roof(cfg)
    print("[Hall]  catwalks", flush=True)
    build_catwalks(cfg)
    print("[Hall]  crane", flush=True)
    build_crane(cfg)
    print("[Hall]  pipes", flush=True)
    build_pipes(cfg)
    print("[Hall]  machines", flush=True)
    if cfg["theme"] == "industrial":
        build_machine_factory(cfg)
    elif cfg["theme"] == "village":
        build_machine_repair(cfg)
    elif cfg["theme"] == "steppe":
        build_machine_mine(cfg)
    else:
        build_machine_pump(cfg)
    print("[Hall]  debris", flush=True)
    build_debris(cfg)
    print("[Hall]  lamps", flush=True)
    build_lamp_fixtures(cfg)


def export(cfg, path):
    # Bake every object's transform into a unique mesh copy.  The builders use
    # one shared unit cube per material for speed; object.join() cannot reliably
    # bake thousands of users of the same mesh, so do it explicitly first.
    from mathutils import Matrix
    groups = {}
    for obj in PARTS:
        if obj.type != "MESH" or not obj.data.materials:
            continue
        obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        key = obj.data.materials[0].name
        groups.setdefault(key, []).append(obj)
    joined = []
    for mat_name, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = mat_name
        joined.append(obj)
        print("[Hall]", cfg["theme"], obj.name, "verts", len(obj.data.vertices))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined + LIGHTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = joined[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("[Hall]", cfg["theme"], "exported", path, "objects", len(joined))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    selected = os.environ.get("HALL_THEMES", "").strip()
    order = ORDER
    if selected:
        order = tuple(x.strip() for x in selected.split(",") if x.strip())
    for key in order:
        if key not in THEMES:
            continue
        print("[Hall] building", key, flush=True)
        clear()
        PARTS.clear()
        LIGHTS.clear()
        _UNIT_CUBES.clear()
        cfg = THEMES[key]
        build(cfg)
        out = os.path.join(OUT_DIR, key + "_hall.glb")
        export(cfg, out)
        print("[Hall] finished", key, flush=True)
    if not selected:
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)


if __name__ == "__main__":
    main()
