"""Blender 5.x generator for a large ruined industrial hall.

The reference is a photoreal concrete hall with catwalks, an arched skylight
roof, rubble and overgrowth.  This asset provides the architectural shell; the
CC0 PBR textures and volumetric light shafts are applied in Godot.

Run:
  blender -b --factory-startup --python tools/blender_industrial_hall.py
"""

import bpy
import math
import os
import random

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "Assets", "frontline", "industrial_hall.glb")

MAT_COLORS = {
    "hall_concrete": (0.62, 0.60, 0.55),
    "hall_floor": (0.48, 0.46, 0.42),
    "hall_moss": (0.24, 0.32, 0.16),
    "hall_rust": (0.34, 0.18, 0.10),
    "hall_metal": (0.28, 0.30, 0.31),
    "hall_glass": (0.55, 0.68, 0.72),
    "hall_dark": (0.055, 0.055, 0.05),
    "hall_water": (0.045, 0.055, 0.05),
}
PARTS = []
RNG = random.Random(1986)


def in_spawn_lane(x, y, pad=3.5):
    """Keep the spawn sightline down the nave free of loose debris.

    The drone starts near the east doorway (local x~34, y~0) and looks down
    the hall; a random pipe or drum 4 m from the camera ruins the hero shot.
    """
    return 18.0 < x < 40.0 and abs(y) < pad


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    color = MAT_COLORS.get(name, (0.5, 0.5, 0.5))
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.86
    bsdf.inputs["Metallic"].default_value = 0.2 if name in ("hall_rust", "hall_metal") else 0.0
    if name == "hall_water":
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Metallic"].default_value = 0.05
    return mat


def add(obj, mat):
    obj.data.materials.append(material(mat))
    PARTS.append(obj)
    return obj


def box(size, loc, mat, bevel=0.035, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("soft", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return add(obj, mat)


def cyl(radius, height, loc, mat, rotation=(0, 0, 0), vertices=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
            depth=height, location=loc, rotation=rotation)
    return add(bpy.context.object, mat)


def beam_between(a, b, width, mat):
    import mathutils
    a = mathutils.Vector(a)
    b = mathutils.Vector(b)
    mid = (a + b) * 0.5
    direction = b - a
    length = direction.length
    if length < 0.01:
        return None
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=mid)
    obj = bpy.context.object
    obj.scale = (width, width, length)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = direction.to_track_quat('Z', 'Y')
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return add(obj, mat)


def arch_rib(x, half_width, spring, apex, width, mat, segments=14):
    prev = None
    for i in range(segments + 1):
        t = i / segments
        y = -half_width + 2.0 * half_width * t
        z = spring + (apex - spring) * math.sin(t * math.pi)
        p = (x, y, z)
        if prev is not None:
            beam_between(prev, p, width, mat)
        prev = p


def build_hall():
    length = 80.0
    half_w = 20.0
    spring = 13.0
    apex = 20.0
    # Foundation / floor.
    box((length + 4.0, 2.0 * half_w + 4.0, 0.7), (0, 0, 0.35), "hall_floor", 0.04)
    # Columns and main beams.
    for x in (-32.0, -16.0, 0.0, 16.0, 32.0):
        for y in (-18.0, 18.0):
            box((1.2, 1.2, 13.0), (x, y, 7.0), "hall_concrete", 0.05)
            box((1.8, 1.8, 0.5), (x, y, 13.4), "hall_concrete", 0.03)
    for y in (-18.0, 18.0, 0.0):
        box((length, 0.9, 1.1), (0, y, 13.0), "hall_concrete", 0.04)
    for x in (-32.0, -16.0, 0.0, 16.0, 32.0):
        box((0.8, 2.0 * half_w, 0.9), (x, 0, 12.8), "hall_concrete", 0.04)
    # Side wall panels with window openings and upper/sill bands.
    for side in (-1, 1):
        y = side * half_w
        for bay in range(10):
            x0 = -36.0 + bay * 8.0
            # solid piers at bay boundaries
            box((0.9, 0.55, 13.0), (x0 - 4.0, y, 6.8), "hall_concrete", 0.03)
            # Solid lower wall below the sill: an enclosed concrete shell, not
            # an open colonnade (the first render showed daylight at floor level).
            box((7.3, 0.55, 1.6), (x0, y, 0.8), "hall_concrete", 0.02)
            # sill and upper band; window opening between
            box((7.3, 0.55, 1.3), (x0, y, 2.2), "hall_concrete", 0.02)
            box((7.3, 0.55, 2.0), (x0, y, 11.7), "hall_concrete", 0.02)
            # Broken glazing: only the occasional bay still has glass; most
            # windows are open, so the shell reads as a ruin from outside.
            if bay % 4 == 0:
                box((6.9, 0.20, 7.5), (x0, y, 7.0), "hall_glass", 0.0)
                for z in (4.0, 7.0, 10.0):
                    box((7.1, 0.28, 0.16), (x0, y, z), "hall_metal", 0.01)
    # End walls with a wide central doorway - the bright mouth of the hall and
    # the natural way in and out for the drone.
    for ex in (-39.5, 39.5):
        for sy in (-1, 1):
            box((1.0, 13.0, 13.0), (ex, sy * 13.5, 6.8), "hall_concrete", 0.04)
        box((1.0, 14.0, 5.0), (ex, 0.0, 10.5), "hall_concrete", 0.04)
    # Barrel-vault roof: ribs and panels, with skylight gaps.
    for rx in range(-36, 37, 8):
        arch_rib(float(rx), half_w - 1.0, spring, apex, 0.65, "hall_metal", 16)
    for bay in range(9):
        x0 = -36.0 + bay * 8.0 + 4.0
        for seg in range(16):
            if bay % 4 == 2 and 5 <= seg <= 10:
                continue  # hole in the roof
            if bay % 5 == 3 and seg >= 12:
                continue
            t0 = seg / 16.0
            t1 = (seg + 1) / 16.0
            tm = (t0 + t1) * 0.5
            y0 = -(half_w - 1.0) + 2.0 * (half_w - 1.0) * t0
            y1 = -(half_w - 1.0) + 2.0 * (half_w - 1.0) * t1
            z0 = spring + (apex - spring) * math.sin(t0 * math.pi)
            z1 = spring + (apex - spring) * math.sin(t1 * math.pi)
            ym = (y0 + y1) * 0.5
            zm = (z0 + z1) * 0.5
            dy = y1 - y0
            dz = z1 - z0
            # Solid curved roof panels (0.22 m slab) instead of open slats:
            # only the skipped segments become the skylight holes.
            panel_len = math.hypot(dy, dz) + 0.08
            angle = math.atan2(dz, dy)
            box((7.85, panel_len, 0.22), (x0, ym, zm),
                "hall_concrete" if seg % 5 == 0 else "hall_metal", 0.01,
                (angle, 0.0, 0.0))
    # Side catwalks / balconies.
    for side in (-1, 1):
        y = side * 15.0
        box((length - 2.0, 5.0, 0.45), (0, y, 7.0), "hall_floor", 0.03)
        # railings
        for i in range(31):
            x = -38.0 + i * 2.6
            box((0.10, 0.10, 1.3), (x, y - side * 2.2, 7.8), "hall_rust", 0.0)
        for z in (7.5, 8.2):
            box((length - 2.0, 0.10, 0.10), (0, y - side * 2.2, z), "hall_rust", 0.0)
        # support brackets
        for x in (-32.0, -16.0, 0.0, 16.0, 32.0):
            beam_between((x, y, 6.8), (x, y - side * 3.6, 4.2), 0.22, "hall_rust")
    # ---------------------------------------------------------------- interior
    # Gantry crane runway, bridge and hoist: the strongest "working factory"
    # silhouette in the reference.
    for y in (-11.5, 11.5):
        box((76.0, 0.35, 0.35), (0, y, 10.2), "hall_metal", 0.02)
    box((0.9, 23.0, 0.9), (6.0, 0, 10.8), "hall_metal", 0.03)
    box((1.8, 2.4, 0.9), (6.0, 0, 11.4), "hall_rust", 0.02)
    cyl(0.045, 6.4, (6.0, 0, 7.9), "hall_dark", (0, 0, 0), vertices=6)
    box((0.5, 0.7, 0.5), (6.0, 0, 4.6), "hall_rust", 0.02)
    # Machines along the west end: lathe, press, cabinets, workbench.
    box((5.0, 1.0, 1.2), (-30, 8.5, 1.3), "hall_metal", 0.03)
    cyl(0.55, 4.2, (-30, 8.5, 1.9), "hall_rust", (0, math.pi * 0.5, 0), vertices=10)
    box((2.2, 2.2, 1.6), (-30, -8.0, 1.5), "hall_metal", 0.03)
    box((0.8, 1.6, 0.5), (-30, -8.0, 2.6), "hall_rust", 0.02)
    for i in range(4):
        box((1.6, 0.6, 2.1), (-20.0 + float(i) * 2.0, 16.5, 1.75),
            "hall_metal", 0.02)
    box((6.0, 1.2, 0.9), (-8.0, 16.0, 1.15), "hall_rust", 0.02)
    for i in range(4):
        box((0.6, 0.6, 0.6), (-10.0 + float(i) * 1.5, 15.6, 1.7),
            "hall_metal", 0.01)
    # Cable trays along both walls with brackets.
    for side in (-1, 1):
        y = side * 19.3
        for z in (5.2, 8.4):
            box((76.0, 0.55, 0.10), (0, y, z), "hall_metal", 0.0)
            box((76.0, 0.06, 0.22), (0, y - 0.20, z + 0.12), "hall_metal", 0.0)
            box((76.0, 0.06, 0.22), (0, y + 0.20, z + 0.12), "hall_metal", 0.0)
            for i in range(13):
                box((0.10, 0.55, 0.30), (-36.0 + float(i) * 6.0, y, z - 0.10),
                    "hall_rust", 0.0)
    # Overhead pipes with flanges along both walls.
    for side in (-1, 1):
        y = side * 18.6
        cyl(0.18, 74.0, (0, y, 9.2), "hall_metal",
            (0, math.pi * 0.5, 0), vertices=10)
        for i in range(10):
            cyl(0.26, 0.22, (-34.0 + float(i) * 7.5, y, 9.2), "hall_rust",
                (0, math.pi * 0.5, 0), vertices=10)
    # Visible housings for the two sodium lamps (the light nodes are in Godot).
    for x in (-24.0, 24.0):
        cyl(0.42, 0.10, (x, 0, 6.6), "hall_dark", (0, 0, 0), vertices=12)
        box((0.05, 0.05, 1.4), (x, 0, 7.3), "hall_dark", 0.0)
    # Geometric decals: floor cracks and rust streaks on the walls.
    for i in range(26):
        x = RNG.uniform(-34, 34)
        y = RNG.uniform(-17, 17)
        if in_spawn_lane(x, y):
            continue
        box((RNG.uniform(1.2, 4.5), 0.025, 0.04), (x, y, 0.716),
            "hall_dark", 0.0, (0, 0, RNG.uniform(0, math.pi)))
    for i in range(18):
        side = -1 if i % 2 == 0 else 1
        x = RNG.uniform(-34, 34)
        box((RNG.uniform(0.35, 0.8), 0.03, RNG.uniform(1.6, 3.8)),
            (x, side * 19.55, RNG.uniform(3.0, 8.0)), "hall_rust", 0.0)
    # Foreground debris cluster just inside the east doorway.  Keep a 4 m
    # corridor clear along the spawn sightline; the debris frames the sides.
    for i in range(10):
        x = RNG.uniform(22.0, 31.0)
        side = -1.0 if i % 2 == 0 else 1.0
        y = side * RNG.uniform(5.5, 14.0)
        w = RNG.uniform(0.8, 2.6)
        d = RNG.uniform(0.7, 2.0)
        h = RNG.uniform(0.12, 0.4)
        box((w, d, h), (x, y, h * 0.5 + 0.7), "hall_floor", 0.02,
            (0.0, 0.0, RNG.uniform(0, math.pi)))
    beam_between((20.0, -12.0, 0.85), (30.0, -5.0, 1.4), 0.32, "hall_rust")
    beam_between((22.0, 11.0, 0.8), (28.0, 5.0, 1.1), 0.26, "hall_rust")
    # Rubble slabs and collapsed beams.  Clustered along the walls where a real
    # roof collapse would shed its debris, plus a few in the open nave.
    for i in range(60):
        edge = i % 3 != 0
        if edge:
            x = RNG.choice([RNG.uniform(-37, -24), RNG.uniform(24, 37)])
            y = RNG.uniform(-18, 18)
        else:
            x = RNG.uniform(-24, 24)
            y = RNG.uniform(-15, 15)
        if in_spawn_lane(x, y):
            continue
        w = RNG.uniform(1.0, 4.2)
        d = RNG.uniform(0.8, 3.0)
        h = RNG.uniform(0.15, 0.55)
        box((w, d, h), (x, y, h * 0.5 + 0.7),
            "hall_moss" if i % 10 == 0 else "hall_floor", 0.02,
            (0.0, 0.0, RNG.uniform(0, math.pi)))
    for i in range(17):
        x = RNG.uniform(-33, 33)
        y = RNG.uniform(-15, 15)
        ex = x + RNG.uniform(-11, 11)
        ey = y + RNG.uniform(-8, 8)
        if in_spawn_lane(x, y) or in_spawn_lane(ex, ey):
            continue
        beam_between((x, y, 0.8), (ex, ey, RNG.uniform(2.0, 7.0)),
                     RNG.uniform(0.25, 0.45), "hall_rust")
    # Fallen roof panels leaning against the walls and rubble.
    for i in range(14):
        x = RNG.uniform(-34, 34)
        y = RNG.uniform(-17, 17)
        if in_spawn_lane(x, y):
            continue
        box((RNG.uniform(2.5, 4.5), RNG.uniform(1.6, 2.8), 0.14),
            (x, y, RNG.uniform(0.9, 1.8)), "hall_metal", 0.01,
            (RNG.uniform(-0.9, 0.9), RNG.uniform(-0.25, 0.25),
             RNG.uniform(0, math.pi)))
    # Barrels, pipes and debris.
    for i in range(24):
        x = RNG.uniform(-36, 36)
        y = RNG.uniform(-18, 18)
        if in_spawn_lane(x, y):
            continue
        cyl(RNG.uniform(0.28, 0.45), RNG.uniform(0.8, 1.3),
            (x, y, 1.0), "hall_rust", (0, 0, RNG.uniform(0, math.pi)))
    for i in range(14):
        x = RNG.uniform(-35, 35)
        y = RNG.uniform(-18, 18)
        if in_spawn_lane(x, y):
            continue
        cyl(0.16, RNG.uniform(4.0, 10.0), (x, y, 0.9),
            "hall_metal", (math.pi * 0.5, 0, RNG.uniform(0, math.pi)))
    # Hanging power cables sagging under the roof.
    for i in range(10):
        x = RNG.uniform(-30, 30)
        y = RNG.uniform(-14, 14)
        cyl(0.035, RNG.uniform(1.5, 6.0), (x, y, RNG.uniform(9.0, 12.5)),
            "hall_dark", (0.0, math.pi * 0.5, RNG.uniform(0, math.pi)), vertices=6)
    # Clutter on the catwalks: crates, drums and cable spools.
    for side in (-1, 1):
        for i in range(6):
            x = RNG.uniform(-32, 32)
            box((RNG.uniform(0.5, 1.0), RNG.uniform(0.5, 1.0), RNG.uniform(0.4, 0.9)),
                (x, side * 15.0 + RNG.uniform(-1.6, 1.6), 7.6), "hall_rust", 0.01,
                (0, 0, RNG.uniform(0, math.pi)))
    # Rain puddles: irregular thin discs, not rectangles.
    for i in range(8):
        x = RNG.uniform(-33, 33)
        y = RNG.uniform(-16, 16)
        if in_spawn_lane(x, y):
            continue
        puddle = cyl(RNG.uniform(1.1, 2.6), 0.025, (x, y, 0.715),
                     "hall_water", (0, 0, 0), vertices=10)
        puddle.scale = (1.0, RNG.uniform(0.55, 0.95), 1.0)
    # Irregular moss patches on the floor (the shader/grass adds the rest).
    for i in range(14):
        x = RNG.uniform(-30, 30)
        y = RNG.uniform(-15, 15)
        if in_spawn_lane(x, y):
            continue
        patch = cyl(RNG.uniform(0.8, 2.2), 0.03, (x, y, 0.745),
                    "hall_moss", (0, 0, 0), vertices=9)
        patch.scale = (1.0, RNG.uniform(0.6, 1.0), 1.0)


def main():
    clear()
    build_hall()
    # Apply all transforms, join by material for a small draw-call count.
    groups = {}
    for obj in PARTS:
        if obj.type != 'MESH':
            continue
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        key = obj.data.materials[0].name if obj.data.materials else "hall_concrete"
        groups.setdefault(key, []).append(obj)
    objects = []
    for mat_name, objs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = "hall_" + mat_name.replace("hall_", "")
        objects.append(joined)
        print("[Hall]", joined.name, "verts=", len(joined.data.vertices))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("[Hall] exported", OUT, "objects:", len(objects))


if __name__ == "__main__":
    main()
