"""Build the large landmark structures for the mobile maps (5 per map).

Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
      --python tools/build_map_landmarks.py

Each landmark is exported as:
  * one joined visual mesh with a vertex-colour material (one draw call),
  * one simplified "<name>-colonly" collision mesh, so Godot's glTF importer
    creates a StaticBody3D with hollow walls the drone can fly into.
Structures are stunt-friendly on purpose: open door bays, ridge skylights,
hollow chimneys and open cargo holds can be entered from the air.
Origins are at the base centre (Z-up in Blender, glTF converts to Y-up).
"""
import bpy
import math
import os
import random

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "Assets", "handcrafted", "landmarks")
MAT = None

WOOD = (0.25, 0.17, 0.10)
WOOD_LIGHT = (0.38, 0.28, 0.16)
METAL = (0.27, 0.28, 0.30)
METAL_LIGHT = (0.38, 0.39, 0.40)
RUST = (0.42, 0.20, 0.09)
CONCRETE = (0.44, 0.43, 0.39)
CONCRETE_DARK = (0.30, 0.30, 0.28)
SAND = (0.46, 0.40, 0.26)
HAY = (0.50, 0.42, 0.18)
GLASS = (0.18, 0.26, 0.30)
WHITE = (0.50, 0.49, 0.45)
BLACK = (0.11, 0.11, 0.12)
ORANGE = (0.55, 0.22, 0.05)
BLUE = (0.12, 0.22, 0.36)
RED = (0.45, 0.12, 0.08)
GREEN = (0.18, 0.30, 0.18)
SOOT = (0.07, 0.065, 0.06)
RUST_DARK = (0.30, 0.14, 0.06)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material():
    mat = bpy.data.materials.new("landmark_vcol")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def _lin(c):
    return (pow(c[0], 2.2), pow(c[1], 2.2), pow(c[2], 2.2))


def colourise(ob, rgb):
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    layer = me.color_attributes["Col"]
    for i in range(len(me.loops)):
        c = _lin(rgb)

        layer.data[i].color = (c[0], c[1], c[2], 1.0)
    ob.data.materials.clear()
    ob.data.materials.append(MAT)


def box(name, size, loc, rgb, rot=(0.0, 0.0, 0.0), collect=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    colourise(ob, rgb)
    if collect is not None:
        collect.append(ob)
    return ob


def cyl(name, radius, height, loc, rgb, rot=(0.0, 0.0, 0.0), verts=14, collect=None,
        open_ends=False):
    if open_ends:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=height,
                                            location=loc, rotation=rot,
                                            vertices=verts,
                                            end_fill_type='NOTHING')
    else:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=height,
                                            location=loc, rotation=rot,
                                            vertices=verts)
    ob = bpy.context.object
    ob.name = name
    colourise(ob, rgb)
    if collect is not None:
        collect.append(ob)
    return ob


def cone(name, radius, height, loc, rgb, rot=(0.0, 0.0, 0.0), verts=14, collect=None):
    bpy.ops.mesh.primitive_cone_add(radius1=radius, depth=height,
                                    location=loc, rotation=rot, vertices=verts)
    ob = bpy.context.object
    ob.name = name
    colourise(ob, rgb)
    if collect is not None:
        collect.append(ob)
    return ob


def gable_slab(name, width, height, depth, center_x, center_y, base_z, rgb, sign,
               collect):
    run = max(width * 0.5, 0.2)
    slope = math.atan2(height, run)
    half = math.sqrt(run * run + height * height) * 0.5
    bpy.ops.mesh.primitive_cube_add(size=1, location=(
        center_x, center_y, base_z + height * 0.5),
        rotation=(0.0, sign * slope, 0.0))
    ob = bpy.context.object
    ob.name = name + ("_L" if sign < 0 else "_R")
    ob.scale = (half * 1.04, depth, 0.08)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    colourise(ob, rgb)
    collect.append(ob)


def gable(name, width, depth, height, loc, rgb, collect, ridge_gap=0.0,
          damaged=False):
    """Gable roof split into three bays with a real ridge slot; `damaged`
    leaves one bay of the right slope missing for a battle-damaged hole."""
    run = (width - ridge_gap) * 0.5
    if run < width * 0.12:
        run = width * 0.12
    segs = 3
    seg_d = depth / float(segs)
    for sign in (-1.0, 1.0):
        for i in range(segs):
            if damaged and sign > 0.0 and i == 1:
                continue
            center_x = loc[0] + sign * (ridge_gap * 0.5 + run * 0.5)
            center_y = loc[1] - depth * 0.5 + seg_d * (i + 0.5)
            gable_slab(name, run * 2.0, height, seg_d * 1.01, center_x,
                       center_y, loc[2], rgb, sign, collect)


def prism_xz(name, width, height, depth, loc, rgb, collect):
    """Triangular gable-end wall (prism) in the XZ plane, extruded along Y."""
    hw = width * 0.5
    hd = depth * 0.5
    verts = [
        (-hw, -hd, 0.0), (hw, -hd, 0.0), (0.0, -hd, height),
        (-hw, hd, 0.0), (hw, hd, 0.0), (0.0, hd, height),
    ]
    faces = [(0, 1, 2), (3, 5, 4), (0, 2, 5, 3), (1, 4, 5, 2), (0, 3, 4, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = loc
    colourise(ob, rgb)
    collect.append(ob)
    return ob


def soot_and_rust(parts, wall_y, xs, z_top, face_sign=1.0):
    """Dark soot patches and rust streaks on a wall (thin boxes, no collision)."""
    for x in xs:
        box("soot", (2.2, 0.05, 2.4), (x, wall_y + face_sign * 0.02,
            z_top - 1.1), SOOT, collect=parts)
        box("rust", (0.22, 0.06, 1.8), (x + 0.8, wall_y + face_sign * 0.02,
            z_top - 2.1), RUST_DARK, collect=parts)


def rubble_pile(parts, x, y, z, count=8, seed=0):
    rng = random.Random(seed)
    for i in range(count):
        w = rng.uniform(0.4, 1.5)
        d = rng.uniform(0.4, 1.2)
        h = rng.uniform(0.2, 0.7)
        box("rubble", (w, d, h),
            (x + rng.uniform(-2.2, 2.2), y + rng.uniform(-2.2, 2.2),
             z + h * 0.5),
            CONCRETE_DARK if i % 3 else RUST_DARK,
            (rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), 0.0),
            collect=parts)


def wall_with_door(name, length, height, thick, y, door_w, door_h, z0, rgb,
                   vis, col):
    """Long wall along X with a rectangular doorway: two jamb panels + lintel."""
    half_door = door_w * 0.5
    left_w = length * 0.5 - half_door
    for sign in (-1.0, 1.0):
        box(name + "_seg", (left_w, thick, height),
            (sign * (half_door + left_w * 0.5), y, z0 + height * 0.5), rgb,
            collect=vis)
        box(name + "_seg_col", (left_w, thick, height),
            (sign * (half_door + left_w * 0.5), y, z0 + height * 0.5), rgb,
            collect=col)
    lintel_h = height - door_h
    if lintel_h > 0.1:
        box(name + "_lintel", (door_w, thick, lintel_h),
            (0, y, z0 + door_h + lintel_h * 0.5), rgb, collect=vis)
        box(name + "_lintel_col", (door_w, thick, lintel_h),
            (0, y, z0 + door_h + lintel_h * 0.5), rgb, collect=col)


def join_and_export(name, parts, colliders):
    if not parts:
        print("LANDMARK_FAIL", name)
        return
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    vis = bpy.context.object
    vis.name = name
    if colliders:
        bpy.ops.object.select_all(action='DESELECT')
        for ob in colliders:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = colliders[0]
        bpy.ops.object.join()
        col = bpy.context.object
        col.name = name + "-colonly"
        col.select_set(True)
    vis.select_set(True)
    bpy.context.view_layer.objects.active = vis
    os.makedirs(ROOT, exist_ok=True)
    out = os.path.join(ROOT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB',
                              use_selection=True, export_apply=True,
                              export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in vis.data.polygons)
    print("LANDMARK_OK", name, "verts=", len(vis.data.vertices),
          "tris=", tris, "colliders=", len(colliders), "->", out)


# ---------------------------------------------------------------- buildings
def building_trim(name, width, depth, height, z0, parts, trim_rgb=CONCRETE_DARK):
    """Plinth, corner pilasters and a thin eave band: cheap detail that makes
    the big shells read as authored buildings instead of plain boxes."""
    box(name + "_plinth_f", (width + 0.6, 0.6, 0.6),
        (0, -depth * 0.5, z0 + 0.3), trim_rgb, collect=parts)
    box(name + "_plinth_b", (width + 0.6, 0.6, 0.6),
        (0, depth * 0.5, z0 + 0.3), trim_rgb, collect=parts)
    box(name + "_plinth_l", (0.6, depth + 0.6, 0.6),
        (-width * 0.5, 0, z0 + 0.3), trim_rgb, collect=parts)
    box(name + "_plinth_r", (0.6, depth + 0.6, 0.6),
        (width * 0.5, 0, z0 + 0.3), trim_rgb, collect=parts)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            box(name + "_pilaster", (0.75, 0.75, height),
                (sx * width * 0.5, sy * depth * 0.5, z0 + height * 0.5),
                trim_rgb, collect=parts)
    box(name + "_eave_f", (width + 1.0, 0.9, 0.35),
        (0, -depth * 0.5 - 0.1, z0 + height - 0.2), trim_rgb, collect=parts)
    box(name + "_eave_b", (width + 1.0, 0.9, 0.35),
        (0, depth * 0.5 + 0.1, z0 + height - 0.2), trim_rgb, collect=parts)


def wall_y_door(name, length, height, thick, x, door_w, door_h, z0, rgb, vis, col):
    """Wall along Y with a rectangular doorway (through-hole)."""
    half = door_w * 0.5
    side = length * 0.5 - half
    for sign in (-1.0, 1.0):
        box(name + "_seg", (thick, side, height),
            (x, sign * (half + side * 0.5), z0 + height * 0.5), rgb, collect=vis)
        box(name + "_seg_col", (thick, side, height),
            (x, sign * (half + side * 0.5), z0 + height * 0.5), rgb, collect=col)
    lintel_h = height - door_h
    if lintel_h > 0.1:
        box(name + "_lintel", (thick, door_w, lintel_h),
            (x, 0, z0 + door_h + lintel_h * 0.5), rgb, collect=vis)
        box(name + "_lintel_col", (thick, door_w, lintel_h),
            (x, 0, z0 + door_h + lintel_h * 0.5), rgb, collect=col)


def wall_y_windows(name, length, height, thick, x, z0, win_w, win_h, win_z,
                   count, rgb, vis, col):
    """Wall along Y with a row of real through-window openings."""
    box(name + "_low", (thick, length, win_z),
        (x, 0, z0 + win_z * 0.5), rgb, collect=vis)
    box(name + "_low_col", (thick, length, win_z),
        (x, 0, z0 + win_z * 0.5), rgb, collect=col)
    top_h = height - win_z - win_h
    if top_h > 0.01:
        box(name + "_top", (thick, length, top_h),
            (x, 0, z0 + win_z + win_h + top_h * 0.5), rgb, collect=vis)
        box(name + "_top_col", (thick, length, top_h),
            (x, 0, z0 + win_z + win_h + top_h * 0.5), rgb, collect=col)
    span = length - win_w * float(count)
    gap = span / float(count + 1)
    cursor = -length * 0.5
    for i in range(count):
        box(name + "_pillar", (thick, gap, win_h),
            (x, cursor + gap * 0.5, z0 + win_z + win_h * 0.5), rgb, collect=vis)
        box(name + "_pillar_col", (thick, gap, win_h),
            (x, cursor + gap * 0.5, z0 + win_z + win_h * 0.5), rgb, collect=col)
        cursor += gap + win_w
    rest = length * 0.5 - cursor
    if rest > 0.01:
        box(name + "_pillar_end", (thick, rest, win_h),
            (x, cursor + rest * 0.5, z0 + win_z + win_h * 0.5), rgb, collect=vis)
        box(name + "_pillar_end_col", (thick, rest, win_h),
            (x, cursor + rest * 0.5, z0 + win_z + win_h * 0.5), rgb, collect=col)


def wall_x_windows(name, length, height, thick, y, z0, win_w, win_h, win_z,
                   count, rgb, vis, col):
    """Wall along X with a row of real through-window openings."""
    box(name + "_low", (length, thick, win_z),
        (0, y, z0 + win_z * 0.5), rgb, collect=vis)
    box(name + "_low_col", (length, thick, win_z),
        (0, y, z0 + win_z * 0.5), rgb, collect=col)
    top_h = height - win_z - win_h
    if top_h > 0.01:
        box(name + "_top", (length, thick, top_h),
            (0, y, z0 + win_z + win_h + top_h * 0.5), rgb, collect=vis)
        box(name + "_top_col", (length, thick, top_h),
            (0, y, z0 + win_z + win_h + top_h * 0.5), rgb, collect=col)
    span = length - win_w * float(count)
    gap = span / float(count + 1)
    cursor = -length * 0.5
    for i in range(count):
        box(name + "_pillar", (gap, thick, win_h),
            (cursor + gap * 0.5, y, z0 + win_z + win_h * 0.5), rgb, collect=vis)
        box(name + "_pillar_col", (gap, thick, win_h),
            (cursor + gap * 0.5, y, z0 + win_z + win_h * 0.5), rgb, collect=col)
        cursor += gap + win_w
    rest = length * 0.5 - cursor
    if rest > 0.01:
        box(name + "_pillar_end", (rest, thick, win_h),
            (cursor + rest * 0.5, y, z0 + win_z + win_h * 0.5), rgb, collect=vis)
        box(name + "_pillar_end_col", (rest, thick, win_h),
            (cursor + rest * 0.5, y, z0 + win_z + win_h * 0.5), rgb, collect=col)


def _prism_yz(name, span_y, height, thick_x, loc, rgb, collect):
    """Triangular gable-end wall in the YZ plane, extruded along X."""
    hy = span_y * 0.5
    hx = thick_x * 0.5
    verts = [
        (-hx, -hy, 0.0), (-hx, hy, 0.0), (-hx, 0.0, height),
        (hx, -hy, 0.0), (hx, hy, 0.0), (hx, 0.0, height),
    ]
    faces = [(0, 1, 2), (3, 5, 4), (0, 2, 5, 3), (1, 4, 5, 2), (0, 3, 4, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = loc
    colourise(ob, rgb)
    collect.append(ob)


def _gable_along_x(name, length_x, span_y, height, loc, rgb, collect,
                   ridge_gap=0.0, damaged=False):
    """Gable roof running along X (3 bays), sloping down across Y."""
    run = max((span_y - ridge_gap) * 0.5, span_y * 0.12)
    slope = math.atan2(height, run)
    slope_len = math.hypot(run, height) * 1.02
    segs = 3
    seg_x = length_x / float(segs)
    for sign in (-1.0, 1.0):
        for i in range(segs):
            if damaged and sign > 0.0 and i == 1:
                continue
            cx = loc[0] - length_x * 0.5 + seg_x * (i + 0.5)
            cy = loc[1] + sign * (ridge_gap * 0.5 + run * 0.5)
            bpy.ops.mesh.primitive_cube_add(
                size=1,
                location=(cx, cy, loc[2] + height * 0.5),
                rotation=(-sign * slope, 0.0, 0.0),
            )
            ob = bpy.context.object
            ob.name = "%s_%s_%d" % (name, "R" if sign > 0 else "L", i)
            ob.scale = (seg_x * 1.01, slope_len, 0.10)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            colourise(ob, rgb)
            collect.append(ob)


def l_warehouse():
    parts, col = [], []
    box("slab", (42.0, 18.0, 0.3), (0, 0, 0.15), CONCRETE, collect=parts)
    # Back wall also has a full door bay: the warehouse is fly-through.
    wall_with_door("wall_back", 42.0, 7.0, 0.35, 8.8, 8.0, 6.0, 0.0,
                   CONCRETE, parts, col)
    wall_with_door("wall_front", 42.0, 7.0, 0.35, -8.8, 8.0, 6.0, 0.0,
                   CONCRETE, parts, col)
    for sx in (-1.0, 1.0):
        # End walls get real through-window openings.
        wall_y_windows("end", 18.0, 7.0, 0.35, sx * 20.8, 0.0, 3.0, 1.6, 4.4, 2,
                       CONCRETE, parts, col)
    # Rolled-up shutter above the opening and a painted lintel stripe.
    box("shutter", (7.6, 0.16, 1.1), (0, -8.6, 6.4), METAL_LIGHT, collect=parts)
    box("lintel", (9.0, 0.5, 0.4), (0, -8.8, 7.0), ORANGE, collect=parts)
    # Hazard frame marks the fly-through door bay at range.
    for sx in (-1.0, 1.0):
        box("door_hazard_v", (0.45, 0.5, 6.2), (sx * 4.25, -8.8, 3.1), ORANGE,
            collect=parts)
    box("door_hazard_h", (9.0, 0.5, 0.45), (0, -8.8, 6.2), ORANGE, collect=parts)
    # Roof running lengthwise along X (42.6 m) across the 18 m hall with an open ridge slot.
    _gable_along_x("roof", 42.6, 19.6, 3.2, (0, 0, 7.0), RUST, parts,
                   ridge_gap=1.6, damaged=True)
    _gable_along_x("roof_col", 42.6, 19.6, 3.2, (0, 0, 7.0), RUST, col,
                   ridge_gap=1.6, damaged=True)
    for sx in (-1.0, 1.0):
        _prism_yz("gable_end", 18.0, 3.2, 0.35, (sx * 20.8, 0.0, 7.0),
                  CONCRETE, parts)
        _prism_yz("gable_end_col", 18.0, 3.2, 0.35, (sx * 20.8, 0.0, 7.0),
                  CONCRETE, col)
    soot_and_rust(parts, -8.98, [-14.0, -4.0, 6.0], 7.0, -1.0)
    soot_and_rust(parts, 8.98, [-10.0, 2.0, 12.0], 7.0, 1.0)
    rubble_pile(parts, 0.0, -10.0, 0.0, 10, 11)
    rubble_pile(parts, 18.0, -8.0, 0.0, 6, 12)
    for i in range(6):
        box("truss", (0.25, 17.0, 0.25), (-17.0 + i * 6.8, 0, 8.2), METAL, collect=parts)
    # Roof vents seated directly on the undamaged -Y roof slope (slope z ~= 8.99 m at y = -4.2).
    for i in range(4):
        box("vent", (1.2, 1.2, 1.0), (-12.0 + i * 8.0, -4.2, 9.15), METAL_LIGHT,
            collect=parts)
    box("dock", (10.0, 2.0, 1.1), (0, -10.5, 0.55), CONCRETE_DARK, collect=parts)
    building_trim('warehouse', 42.0, 18.0, 7.0, 0.0, parts)
    join_and_export("warehouse", parts, col)


def l_grain_elevator():
    parts, col = [], []
    box("pad", (34.0, 20.0, 0.3), (0, 0, 0.15), CONCRETE, collect=parts)
    for i in range(3):
        x = -8.0 + i * 8.0
        cyl("silo", 3.2, 15.0, (x, 2.0, 7.5), CONCRETE, verts=14, collect=parts)
        cyl("silo_col", 3.2, 15.0, (x, 2.0, 7.5), CONCRETE, verts=14, collect=col)
        cone("cap", 3.3, 2.2, (x, 2.0, 16.1), METAL, verts=14, collect=parts)
        cyl("band", 3.25, 0.18, (x, 2.0, 4.0), METAL, verts=14, collect=parts)
        cyl("band2", 3.25, 0.18, (x, 2.0, 11.0), METAL, verts=14, collect=parts)
    # Headhouse: hollow collision box with open side windows is overkill; keep
    # the tower solid but give the loading shed a fly-through bay.
    box("headhouse", (10.0, 9.0, 22.0), (12.0, -3.0, 11.0), CONCRETE, collect=parts)
    box("headhouse_col", (10.0, 9.0, 22.0), (12.0, -3.0, 11.0), CONCRETE, collect=col)
    box("hh_roof", (10.6, 9.6, 0.4), (12.0, -3.0, 22.2), CONCRETE_DARK, collect=parts)
    for i in range(4):
        box("hh_win", (1.2, 0.14, 1.1), (8.8 + i * 2.0, -7.55, 17.0), GLASS, collect=parts)
    box("gallery", (2.2, 2.4, 16.0), (2.0, 0.0, 8.0), METAL, (math.radians(32), 0, 0),
        collect=parts)
    # Loading shed with a 5 m open bay facing the yard.
    box("shed_back", (12.0, 0.3, 5.0), (-14.0, -2.0, 2.5), CONCRETE, collect=parts)
    box("shed_back_col", (12.0, 0.3, 5.0), (-14.0, -2.0, 2.5), CONCRETE, collect=col)
    for sx in (-1.0, 1.0):
        box("shed_side", (0.3, 8.0, 5.0), (-14.0 + sx * 6.0, -6.0, 2.5), CONCRETE,
            collect=parts)
        box("shed_side_col", (0.3, 8.0, 5.0), (-14.0 + sx * 6.0, -6.0, 2.5), CONCRETE,
            collect=col)
    box("shed_front_l", (3.5, 0.3, 5.0), (-16.25, -10.0, 2.5), CONCRETE, collect=parts)
    box("shed_front_l_col", (3.5, 0.3, 5.0), (-16.25, -10.0, 2.5), CONCRETE, collect=col)
    box("shed_front_r", (3.5, 0.3, 5.0), (-11.75, -10.0, 2.5), CONCRETE, collect=parts)
    box("shed_front_r_col", (3.5, 0.3, 5.0), (-11.75, -10.0, 2.5), CONCRETE, collect=col)
    gable("shed_roof", 8.6, 12.6, 1.8, (-14.0, -6.0, 5.0), RUST, parts)
    gable("shed_roof_col", 8.6, 12.6, 1.8, (-14.0, -6.0, 5.0), RUST, col)
    for sy in (-1.0, 1.0):
        prism_xz("shed_gable", 8.6, 1.8, 0.3, (-14.0, -6.0 + sy * 6.3, 5.0),
                 CONCRETE, parts)
        prism_xz("shed_gable_col", 8.6, 1.8, 0.3, (-14.0, -6.0 + sy * 6.3, 5.0),
                 CONCRETE, col)
    soot_and_rust(parts, -7.55, [10.0, 13.0], 20.0, -1.0)
    rubble_pile(parts, -14.0, -12.0, 0.0, 8, 41)
    box("ladder", (0.5, 0.5, 20.0), (16.8, -3.0, 10.0), METAL, collect=parts)
    join_and_export("grain_elevator", parts, col)


def l_cargo_ship():
    parts, col = [], []
    # Hull: solid sides and bottom, open-top cargo holds so the drone can dive in.
    box("hull_bottom", (36.0, 8.4, 0.6), (0, 0, 0.3), RED, collect=col)
    box("hull_bottom_vis", (36.0, 8.4, 0.6), (0, 0, 0.3), RED, collect=parts)
    for sy in (-1.0, 1.0):
        box("hull_side", (36.0, 0.4, 3.4), (0, sy * 4.0, 1.7), RED, collect=col)
        box("hull_side_vis", (36.0, 0.4, 3.4), (0, sy * 4.0, 1.7), RED, collect=parts)
        box("bulwark", (34.0, 0.22, 1.0), (0, sy * 4.35, 3.9), METAL_LIGHT,
            collect=parts)
    box("stern", (0.5, 8.4, 3.4), (-18.0, 0, 1.7), RED, collect=col)
    box("stern_vis", (0.5, 8.4, 3.4), (-18.0, 0, 1.7), RED, collect=parts)
    # Deck strips leave two hatch openings (the holds are enterable).
    for sy in (-1.0, 1.0):
        box("deck_strip", (36.0, 2.2, 0.25), (0, sy * 3.1, 3.55), METAL, collect=parts)
    for x0 in (-13.5, -9.0, 4.5, 9.0, 14.5):
        box("deck_bar", (4.5, 4.0, 0.25), (x0, 0, 3.55), METAL, collect=parts)
    # Open holds with coaming walls (fly-in boxes).
    for x in (-8.0, 6.0):
        for sx in (-1.0, 1.0):
            box("hold_wall", (0.25, 6.4, 1.0), (x + sx * 4.5, 0, 4.05), METAL,
                collect=col)
        for sy in (-1.0, 1.0):
            box("hold_end", (9.2, 0.25, 1.0), (x, sy * 3.2, 4.05), METAL,
                collect=col)
    # Bow plates.
    for sy in (-1.0, 1.0):
        box("bow_plate", (5.0, 2.8, 3.4), (18.8, sy * 2.4, 1.7), RED,
            (0, 0, sy * math.radians(26)), collect=parts)
        box("bow_plate_col", (5.0, 2.8, 3.4), (18.8, sy * 2.4, 1.7), RED,
            (0, 0, sy * math.radians(26)), collect=col)
    # Superstructure with an open bridge deck door.
    box("house", (8.0, 7.0, 5.5), (-13.0, 0, 6.2), WHITE, collect=col)
    box("house_vis", (8.0, 7.0, 5.5), (-13.0, 0, 6.2), WHITE, collect=parts)
    box("bridge", (6.4, 7.4, 1.5), (-12.2, 0, 9.6), WHITE, collect=parts)
    for sy in (-1.0, 1.0):
        box("bridge_win", (6.0, 0.16, 0.9), (-12.2, sy * 3.78, 9.7), GLASS, collect=parts)
    box("funnel", (1.4, 1.4, 2.4), (-15.6, 0, 12.4), BLACK, collect=parts)
    box("funnel_band", (1.5, 1.5, 0.35), (-15.6, 0, 13.2), ORANGE, collect=parts)
    cyl("mast", 0.12, 6.0, (-17.5, 0, 9.0), METAL, verts=8, collect=parts)
    for i in range(3):
        box("cont", (5.6, 2.3, 2.5), (2.5 + i * 6.2, -3.0, 4.85),
            BLUE if i % 2 else ORANGE, collect=parts)
    for i in range(2):
        box("cont2", (5.4, 2.2, 2.4), (6.0 + i * 6.0, 3.0, 4.8), GREEN, collect=parts)
    for i in range(8):
        cyl("bollard", 0.12, 0.5, (-15.0 + i * 4.2, -4.3, 4.5), METAL, verts=6,
            collect=parts)
    join_and_export("cargo_ship", parts, col)


def l_factory_plant():
    parts, col = [], []
    box("slab", (34.0, 20.0, 0.3), (0, 0, 0.15), CONCRETE_DARK, collect=parts)
    # Hollow hall: full door bays on both long walls (fly-through), window
    # openings in the end walls and an open ridge skylight.
    wall_with_door("hall_back", 28.0, 9.0, 0.4, 7.0, 7.0, 7.5, 0.0,
                   CONCRETE, parts, col)
    wall_with_door("hall_front", 28.0, 9.0, 0.4, -7.0, 7.0, 7.5, 0.0,
                   CONCRETE, parts, col)
    for sx in (-1.0, 1.0):
        wall_y_windows("hall_end", 14.0, 9.0, 0.4, sx * 14.0, 0.0, 2.4, 2.0, 4.8,
                       2, CONCRETE, parts, col)
    gable("roof", 15.2, 28.8, 3.4, (0, 0, 9.0), METAL, parts, ridge_gap=1.4, damaged=True)
    gable("roof_col", 15.2, 28.8, 3.4, (0, 0, 9.0), METAL, col, ridge_gap=1.4, damaged=True)
    for sy in (-1.0, 1.0):
        prism_xz("gable_end", 15.2, 3.4, 0.4, (0.0, sy * 7.1, 9.0),
                 CONCRETE, parts)
        prism_xz("gable_end_col", 15.2, 3.4, 0.4, (0.0, sy * 7.1, 9.0),
                 CONCRETE, col)
    soot_and_rust(parts, -7.2, [-9.0, 0.0, 9.0], 9.0, -1.0)
    soot_and_rust(parts, 7.2, [-7.0, 5.0], 9.0, 1.0)
    rubble_pile(parts, 0.0, -8.0, 0.0, 10, 21)
    for i in range(6):
        box("win", (2.4, 0.16, 1.8), (-11.0 + i * 4.4, -7.1, 6.6), GLASS, collect=parts)
    # Door bays on both long walls make the hall fly-through.
    # Open door bay on the south wall so the hall can be entered in flight.
    wall_with_door("hall_door", 28.0, 9.0, 0.4, -7.2, 7.0, 7.5, 0.0,
                   CONCRETE, parts, col)
    # Hollow smokestack: eight panels, open top and bottom (dive-through).
    stack_r = 1.7
    stack_h = 24.0
    for i in range(8):
        a = float(i) * math.tau / 8.0
        px = 17.5 + math.sin(a) * stack_r
        py = 6.0 + math.cos(a) * stack_r
        panel = box("stack_panel", (1.0, 0.34, stack_h), (px, py, stack_h * 0.5),
                     CONCRETE, (0, 0, a), collect=parts)
        box("stack_panel_col", (1.0, 0.34, stack_h), (px, py, stack_h * 0.5),
            CONCRETE, (0, 0, a), collect=col)
    for h in (6.0, 12.0, 18.0):
        cyl("band_a", 1.95, 0.35, (17.5, 6.0, h), RUST, verts=12, collect=parts)
    box("smokestack_b", (2.0, 2.0, 20.0), (16.5, -4.0, 10.0), CONCRETE, collect=parts)
    box("smokestack_b_col", (2.0, 2.0, 20.0), (16.5, -4.0, 10.0), CONCRETE, collect=col)
    for h in (6.0, 12.0, 18.0):
        box("band_b", (2.1, 2.1, 0.3), (16.5, -4.0, h), RUST, collect=parts)
    box("pipe", (1.0, 1.0, 16.0), (-8.0, 9.0, 5.0), METAL, (0, math.radians(78), 0),
        collect=parts)
    for i in range(2):
        cyl("tank", 3.0, 6.0, (-10.0 - i * 7.0, 11.0 - i * 2.0, 3.0), METAL_LIGHT,
            verts=14, collect=parts)
        cone("tank_cap", 3.05, 1.0, (-10.0 - i * 7.0, 11.0 - i * 2.0, 6.5), RUST,
             verts=14, collect=parts)
    box("loading_dock", (8.0, 3.0, 1.2), (-6.0, -8.5, 0.6), CONCRETE_DARK,
        collect=parts)
    building_trim('factory', 28.0, 14.0, 9.0, 0.0, parts)
    join_and_export("factory_plant", parts, col)


def l_farm_complex():
    parts, col = [], []
    box("yard", (28.0, 20.0, 0.25), (0, 0, 0.12), CONCRETE_DARK, collect=parts)
    # Barn: solid back/sides, front wall with a 5 m open door bay.
    box("barn_back", (22.0, 0.3, 6.0), (0, 5.5, 3.0), WOOD, collect=parts)
    box("barn_back_col", (22.0, 0.3, 6.0), (0, 5.5, 3.0), WOOD, collect=col)
    wall_with_door("barn_front", 22.0, 6.0, 0.3, -5.5, 5.0, 4.6, 0.0,
                   WOOD, parts, col)
    for sx in (-1.0, 1.0):
        # One end gets a side door for a second entry, the other real windows.
        if sx > 0.0:
            wall_y_door("barn_side_door", 11.0, 6.0, 0.3, sx * 11.0, 3.5, 4.4,
                        0.0, WOOD, parts, col)
        else:
            wall_y_windows("barn_side_win", 11.0, 6.0, 0.3, sx * 11.0, 0.0,
                           2.0, 1.4, 3.4, 2, WOOD, parts, col)
    gable("barn_roof", 12.4, 22.8, 4.0, (0, 0, 6.0), RUST, parts, ridge_gap=1.2, damaged=True)
    gable("barn_roof_col", 12.4, 22.8, 4.0, (0, 0, 6.0), RUST, col, ridge_gap=1.2, damaged=True)
    for sy in (-1.0, 1.0):
        prism_xz("barn_gable", 12.4, 4.0, 0.3, (0.0, sy * 5.55, 6.0),
                 WOOD, parts)
        prism_xz("barn_gable_col", 12.4, 4.0, 0.3, (0.0, sy * 5.55, 6.0),
                 WOOD, col)
    soot_and_rust(parts, -5.6, [-6.0, 4.0], 6.0, -1.0)
    rubble_pile(parts, -2.0, -7.0, 0.0, 8, 31)
    box("barn_door_l", (2.2, 0.16, 4.4), (-1.3, -5.7, 2.2), WOOD_LIGHT, collect=parts)
    box("door_x", (2.4, 0.1, 0.12), (-1.3, -5.8, 2.4), WOOD, (0, 0, 0.7), collect=parts)
    for i in range(3):
        box("loft_win", (0.9, 0.12, 0.8), (-6.0 + i * 6.0, -5.6, 5.0), BLACK,
            collect=parts)
    # Open machine shed.
    for sx in (-1.0, 1.0):
        box("shed_post", (0.3, 0.3, 4.5), (13.0 + sx * 4.0, -7.0, 2.25), WOOD,
            collect=col)
    box("shed_roof", (10.0, 6.5, 0.3), (13.0, -5.0, 4.9), RUST, collect=col)
    box("shed_roof_vis", (10.0, 6.5, 0.3), (13.0, -5.0, 4.9), RUST, collect=parts)
    box("shed_floor", (10.0, 6.0, 0.2), (13.0, -5.0, 0.1), CONCRETE, collect=parts)
    box("tractor", (2.4, 1.2, 1.1), (12.0, -5.0, 0.75), GREEN, collect=parts)
    cyl("wheel", 0.5, 0.3, (11.0, -5.8, 0.5), BLACK, (math.pi / 2, 0, 0), verts=8,
        collect=parts)
    for i in range(2):
        cyl("silo", 2.4, 10.0, (-9.0 + i * 5.0, 7.0, 5.0), METAL_LIGHT, verts=12,
            collect=parts)
        cyl("silo_col", 2.4, 10.0, (-9.0 + i * 5.0, 7.0, 5.0), METAL_LIGHT, verts=12,
            collect=col)
        cone("silo_cap", 2.45, 1.4, (-9.0 + i * 5.0, 7.0, 10.5), RUST, verts=12,
             collect=parts)
    box("hay_rack", (6.0, 2.0, 1.6), (-12.0, -4.0, 0.8), WOOD, collect=parts)
    box("hay", (5.6, 1.8, 1.2), (-12.0, -4.0, 1.9), HAY, collect=parts)
    building_trim('barn', 22.0, 11.0, 6.0, 0.0, parts, WOOD_LIGHT)
    join_and_export("farm_complex", parts, col)


def l_fuel_depot():
    parts, col = [], []
    box("pad", (30.0, 24.0, 0.3), (0, 0, 0.15), CONCRETE, collect=parts)
    for sy in (-1.0, 1.0):
        box("bund", (26.0, 0.8, 1.4), (0, sy * 9.0, 0.7), CONCRETE_DARK, collect=col)
        box("bund_vis", (26.0, 0.8, 1.4), (0, sy * 9.0, 0.7), CONCRETE, collect=parts)
    for sx in (-1.0, 1.0):
        box("bund_end", (0.8, 18.0, 1.4), (sx * 13.0, 0, 0.7), CONCRETE_DARK,
            collect=col)
    # Three closed tanks and one open-top section for a dive-in stunt.
    for i in range(3):
        x = -8.0 + (i % 2) * 8.0
        y = -4.0 + (i // 2) * 8.0
        cyl("tank", 3.4, 7.0, (x, y, 3.5), WHITE, verts=16, collect=parts)
        cyl("tank_col", 3.4, 7.0, (x, y, 3.5), WHITE, verts=16, collect=col)
        cone("tank_cap", 3.45, 1.2, (x, y, 7.6), METAL, verts=16, collect=parts)
        cyl("tank_band", 3.45, 0.25, (x, y, 5.6), METAL, verts=16, collect=parts)
        box("platform", (1.2, 6.8, 0.16), (x, y, 6.9), METAL, collect=parts)
    # Open-top tank: wall ring + floor, open from above.
    open_x, open_y = 6.0, 4.0
    cyl("open_floor", 3.3, 0.3, (open_x, open_y, 0.3), CONCRETE_DARK, verts=16,
        collect=parts)
    for i in range(12):
        a = float(i) * math.tau / 12.0
        px = open_x + math.sin(a) * 3.2
        py = open_y + math.cos(a) * 3.2
        box("open_wall", (1.75, 0.28, 7.0), (px, py, 3.5), WHITE, (0, 0, a),
            collect=parts)
        box("open_wall_col", (1.75, 0.28, 7.0), (px, py, 3.5), WHITE, (0, 0, a),
            collect=col)
    box("pump_house", (7.0, 5.0, 3.2), (18.0, -7.0, 1.6), CONCRETE, collect=parts)
    box("pump_house_col", (7.0, 5.0, 3.2), (18.0, -7.0, 1.6), CONCRETE, collect=col)
    gable("pump_roof", 5.6, 7.6, 1.2, (18.0, -7.0, 3.2), RUST, parts)
    for sy in (-1.0, 1.0):
        prism_xz("pump_gable", 5.6, 1.2, 0.3, (18.0, -7.0 + sy * 3.8, 3.2),
                 CONCRETE, parts)
    soot_and_rust(parts, -9.55, [16.0, 20.0], 3.2, -1.0)
    rubble_pile(parts, 16.0, -10.0, 0.0, 6, 51)
    box("pump_win", (1.2, 0.14, 0.8), (18.0, -9.55, 2.0), GLASS, collect=parts)
    for i in range(4):
        box("pipe", (0.45, 0.45, 14.0), (-8.0 + i * 2.0, 9.0, 0.9), METAL,
            collect=parts)
    box("pipe_hdr", (14.0, 0.5, 0.5), (18.0, 9.0, 0.9), METAL, collect=parts)
    cyl("flare", 0.3, 8.0, (20.0, 6.0, 4.0), METAL, verts=8, collect=parts)
    box("sign", (2.4, 0.2, 1.2), (16.0, -9.6, 1.2), ORANGE, collect=parts)
    join_and_export("fuel_depot", parts, col)


STRUCTURES = {
    "warehouse": l_warehouse,
    "grain_elevator": l_grain_elevator,
    "cargo_ship": l_cargo_ship,
    "factory_plant": l_factory_plant,
    "farm_complex": l_farm_complex,
    "fuel_depot": l_fuel_depot,
}


def build_one(name):
    reset()
    global MAT
    MAT = make_material()
    STRUCTURES[name]()


def main():
    import sys
    only = []
    if "--" in sys.argv:
        only = [a for a in sys.argv[sys.argv.index("--") + 1:] if a in STRUCTURES]
    targets = only if only else list(STRUCTURES.keys())
    for name in targets:
        build_one(name)


main()
