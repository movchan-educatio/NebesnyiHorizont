"""Blender 5.x cottage / barn kit for the village vertical slice.

The old village houses were single boxes with stickers for windows.  These are
still stylised, but they have a real plinth, gable roof with eaves, framed
windows, shutters, porch, chimney and a readable silhouette.  Godot assigns the
PBR plaster/brick/roof/wood materials by material name after import.

Run:
  blender -b --factory-startup --python tools/blender_village_kit.py
"""

import bpy
import math
import os

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "Assets", "frontline", "village_cottage.glb")

MATS = {
    "plaster": (0.80, 0.73, 0.60),
    "brick": (0.54, 0.31, 0.23),
    "stone": (0.52, 0.50, 0.45),
    "roof": (0.44, 0.18, 0.11),
    "roof_metal": (0.30, 0.32, 0.32),
    "wood": (0.30, 0.19, 0.10),
    "trim": (0.82, 0.77, 0.68),
    "glass": (0.035, 0.055, 0.07),
    "metal": (0.22, 0.24, 0.25),
}


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
    color = MATS.get(name, (0.6, 0.6, 0.6))
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.82 if name != "glass" else 0.16
    bsdf.inputs["Metallic"].default_value = 0.35 if name in ("roof_metal", "metal") else 0.0
    return mat


def box(name, size, loc, mat, bevel=0.04, rotation=(0, 0, 0)):
    # Callers use (width, height, depth); Blender is Z-up, so map Y->Z and
    # Z->Y at the last moment.
    bpy.ops.mesh.primitive_cube_add(size=1.0,
            location=(loc[0], loc[2], loc[1]), rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = obj.modifiers.new("edge_softening", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(material(mat))
    return obj


def roof(name, width, depth, height, loc, mat):
    w = width * 0.5
    d = depth * 0.5
    # Z-up: ridge runs along X, height along Z, depth along Y.
    verts = [
        (-w, -d, 0.0), (w, -d, 0.0), (w, d, 0.0), (-w, d, 0.0),
        (-w, 0.0, height), (w, 0.0, height),
    ]
    faces = [
        (0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5),
        (0, 3, 2, 1),
    ]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (loc[0], loc[2], loc[1])
    obj.data.materials.append(material(mat))
    return obj


def window(prefix, x, y, z, facing, trim_mat="trim"):
    # x = width, y = facade depth, z = height.  box() expects (x, height, depth).
    if facing in ("front", "back"):
        depth = 0.14
        box(prefix + "_glass", (1.02, 1.18, 0.06), (x, z, y), "glass", 0.0)
        for dz in (-0.64, 0.64):
            box(prefix + "_h", (1.24, 0.12, depth), (x, z + dz, y), trim_mat, 0.02)
        for dx in (-0.62, 0.62):
            box(prefix + "_v", (0.12, 1.34, depth), (x + dx, z, y), trim_mat, 0.02)
        for dx in (-0.86, 0.86):
            box(prefix + "_shutter", (0.38, 1.16, 0.07),
                (x + dx, z, y + (0.08 if facing == "front" else -0.08)), "wood", 0.02)
    else:
        box(prefix + "_glass", (0.06, 1.02, 1.18), (x, z, y), "glass", 0.0)
        for dz in (-0.64, 0.64):
            box(prefix + "_h", (0.14, 1.24, 0.12), (x, z + dz, y), trim_mat, 0.02)
        for dy in (-0.62, 0.62):
            box(prefix + "_v", (0.14, 0.12, 1.34), (x, z, y + dy), trim_mat, 0.02)


def cottage(prefix, wall_mat="plaster", roof_mat="roof", two_floor=False):
    wall_h = 5.6 if two_floor else 3.3
    width, depth = 8.0, 6.2
    base_y = 0.52
    # Plinth and main volume.
    box(prefix + "_plinth", (width + 0.55, 0.52, depth + 0.55),
        (0, 0.26, 0), "stone", 0.05)
    box(prefix + "_walls", (width, wall_h, depth),
        (0, base_y + wall_h * 0.5, 0), wall_mat, 0.045)
    # Gable roof with a readable overhang.
    roof(prefix + "_roof", width + 1.1, depth + 1.1, 2.35,
         (0, base_y + wall_h, 0), roof_mat)
    # Eaves fascia.
    for side in (-1, 1):
        box(prefix + "_eave", (width + 1.1, 0.14, 0.18),
            (0, base_y + wall_h - 0.08, side * (depth * 0.5 + 0.48)), "trim", 0.02)
    # Chimney.
    box(prefix + "_chimney", (0.72, 3.0, 0.72),
        (width * 0.30, base_y + wall_h + 1.05, depth * 0.20), "stone", 0.04)
    box(prefix + "_chimney_cap", (0.92, 0.16, 0.92),
        (width * 0.30, base_y + wall_h + 2.62, depth * 0.20), "roof", 0.02)
    # Front door, frame and porch.
    front_z = depth * 0.5 + 0.02
    box(prefix + "_door", (1.25, 2.25, 0.10), (0, 1.65, front_z), "wood", 0.025)
    for dx in (-0.72, 0.72):
        box(prefix + "_door_frame", (0.16, 2.5, 0.18), (dx, 1.65, front_z), "trim", 0.02)
    box(prefix + "_door_lintel", (1.7, 0.16, 0.20), (0, 2.92, front_z), "trim", 0.02)
    box(prefix + "_porch", (2.35, 0.16, 1.55), (0, 3.12, depth * 0.5 + 0.80), "roof", 0.02)
    for dx in (-0.95, 0.95):
        box(prefix + "_porch_post", (0.14, 2.85, 0.14),
            (dx, 1.68, depth * 0.5 + 1.42), "wood", 0.02)
    # Long facades: three framed windows per floor.
    runs = [(2.0, "front"), (2.0, "back")]
    if two_floor:
        runs += [(4.4, "front"), (4.4, "back")]
    for zoff, face in runs:
        z = (depth * 0.5 + 0.02) if face == "front" else (-depth * 0.5 - 0.02)
        for i, x in enumerate((-2.25, 0.0, 2.25)):
            window(f"{prefix}_{face}_{zoff}_{i}", x, z, zoff, face)
    # Short facades: one window each.
    for sx in (-1, 1):
        window(prefix + "_side_" + str(sx), sx * (width * 0.5 + 0.02), 0, 2.0, "side")
    # Attic window in the front gable.
    box(prefix + "_attic_glass", (0.9, 0.06, 0.9),
        (0, base_y + wall_h + 1.0, depth * 0.5 + 0.02), "glass", 0.0)
    for dx in (-0.55, 0.55):
        box(prefix + "_attic_v", (0.10, 0.12, 1.18),
            (dx, base_y + wall_h + 1.0, depth * 0.5 + 0.05), "trim", 0.01)
    for dz in (-0.55, 0.55):
        box(prefix + "_attic_h", (1.18, 0.12, 0.10),
            (0, base_y + wall_h + 1.0 + dz, depth * 0.5 + 0.05), "trim", 0.01)


def barn(prefix):
    width, depth, height = 10.0, 7.0, 3.8
    box(prefix + "_plinth", (width + 0.5, 0.45, depth + 0.5),
        (0, 0.22, 0), "stone", 0.04)
    box(prefix + "_walls", (width, height, depth), (0, 2.1, 0), "wood", 0.04)
    roof(prefix + "_roof", width + 1.2, depth + 1.2, 2.6, (0, 2.1 + height * 0.5, 0), "roof_metal")
    front_z = depth * 0.5 + 0.02
    box(prefix + "_big_door", (3.4, 2.9, 0.12), (0, 1.65, front_z), "wood", 0.03)
    for dx in (-1.85, 1.85):
        box(prefix + "_door_post", (0.18, 3.1, 0.20), (dx, 1.65, front_z), "trim", 0.02)
    for i in range(3):
        box(prefix + "_slat", (3.2, 0.08, 0.10), (0, 0.9 + i * 0.75, front_z + 0.08),
            "metal", 0.01)


def main():
    clear()
    objects = []
    cottage("cottage_a", "plaster", "roof", False)
    cottage("cottage_b", "brick", "roof_metal", True)
    barn("barn_a")
    # Join each building into one mesh with multiple material slots.  Godot
    # still draws one call per material, but the scene tree stays clean and
    # instancing a cottage is one PackedScene node instead of 60 boxes.
    for prefix in ("cottage_a", "cottage_b", "barn_a"):
        parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(prefix)]
        if not parts:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts:
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = prefix
        objects.append(joined)
    for obj in objects:
        print("[VillageKit]", obj.name, "dim=", tuple(round(v, 2) for v in obj.dimensions),
              "loc=", tuple(round(v, 2) for v in obj.location),
              "rot=", tuple(round(v, 2) for v in obj.rotation_euler))
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
    print("[VillageKit] exported", OUT, "objects:", len(objects))


if __name__ == "__main__":
    main()
