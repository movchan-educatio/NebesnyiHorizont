"""Procedural generation of three large, themed CityFPV maps in Blender.

  assets/maps/map_training.glb  - green urban city (freeride / training)
  assets/maps/map_combat.glb    - battlefield fields (trenches, bunkers, ruins)
  assets/maps/map_speed.glb     - desert canyon circuit (speed)

Run: blender --background --factory-startup --python tools/make_maps.py

Helpers take Godot-space coordinates (x right, y up, z depth) and convert to
Blender (z up) internally.  Godot collision suffixes: -col, -colonly, -convcol.
"""
from __future__ import annotations

import math
import os
import random
from pathlib import Path

import bpy
from mathutils import Vector, noise

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
OUT_DIR = PROJECT / "assets" / "maps"
BLEND_PATH = PROJECT.parent / "big_maps.blend"

random.seed(11)


# ------------------------------------------------------------------ helpers
def bl(loc):
    return (loc[0], loc[2], loc[1])


def bs(size):
    return (size[0], size[2], size[1])


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                  bpy.data.collections, bpy.data.curves):
        for item in list(block):
            try:
                block.remove(item)
            except Exception:
                pass


def get_bsdf(material):
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")


def flat(name, color, roughness=0.9, metallic=0.0, emission=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = get_bsdf(material)
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        shader.inputs["Emission Color"].default_value = (*color, 1.0)
        shader.inputs["Emission Strength"].default_value = emission
    material.diffuse_color = (*color, 1.0)
    return material


def link(coll, obj):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    coll.objects.link(obj)
    return obj


def apply_transforms():
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def box(coll, name, loc, size, material=None, yaw=0.0, pitch=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = bs(size)
    obj.rotation_euler = (pitch, 0.0, yaw)
    apply_transforms()
    if material is not None:
        obj.data.materials.append(material)
    return link(coll, obj)


def plane(coll, name, loc, size_xz, material=None, yaw=0.0):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size_xz[0], size_xz[1], 1.0)
    obj.rotation_euler = (0.0, 0.0, yaw)
    apply_transforms()
    if material is not None:
        obj.data.materials.append(material)
    return link(coll, obj)


def cylinder(coll, name, loc, radius, depth, material=None, yaw=0.0, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius,
                                        depth=depth, location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = (0.0, 0.0, yaw)
    apply_transforms()
    if material is not None:
        obj.data.materials.append(material)
    return link(coll, obj)


def ring(coll, name, loc, radius, material=None, yaw=0.0):
    bpy.ops.mesh.primitive_torus_add(location=bl(loc), major_radius=radius,
                                     minor_radius=max(0.35, radius * 0.12),
                                     major_segments=24, minor_segments=8)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = (math.pi * 0.5, 0.0, yaw)
    apply_transforms()
    if material is not None:
        obj.data.materials.append(material)
    return link(coll, obj)


def square_gate(coll, loc, size, material, yaw=0.0):
    w, h, t = size
    box(coll, "Square", (loc[0], loc[1] + h * 0.5, loc[2]), (w, t, t), material, yaw=yaw)
    box(coll, "Square", (loc[0], loc[1] - h * 0.5, loc[2]), (w, t, t), material, yaw=yaw)
    box(coll, "Square", (loc[0] + w * 0.5, loc[1], loc[2]), (t, h, t), material, yaw=yaw)
    box(coll, "Square", (loc[0] - w * 0.5, loc[1], loc[2]), (t, h, t), material, yaw=yaw)


def building(coll, loc, size, mat, roof_mat, floors=4):
    w, h, d = size
    for i in range(floors):
        fh = h / floors
        y = loc[1] - h * 0.5 + fh * (i + 0.5)
        inset = 0.0 if i % 2 == 0 else 0.8
        box(coll, "Building-col", (loc[0], y, loc[2]),
            (w - inset, fh * 0.88, d - inset), mat)
        box(coll, "Facade", (loc[0], y + fh * 0.30, loc[2]),
            (w + 0.2, fh * 0.20, d + 0.2), roof_mat)
    box(coll, "Roof", (loc[0], loc[1] + h * 0.5 + 0.4, loc[2]),
        (w * 0.8, 1.0, d * 0.8), roof_mat)


def container_stack(coll, loc, mat, count=3, yaw=0.0):
    for i in range(count):
        box(coll, "Container-col", (loc[0], loc[1] + i * 2.7, loc[2]),
            (12.0, 2.6, 5.0), mat, yaw=yaw)


def silo(coll, loc, radius, height, mat):
    cylinder(coll, "Silo-col", (loc[0], loc[1] + height * 0.5, loc[2]),
             radius, height, mat, 20)
    cylinder(coll, "SiloTop", (loc[0], loc[1] + height + radius * 0.4, loc[2]),
             radius * 1.05, radius * 0.7, mat, 20)


def crane(coll, loc, mat, yaw=0.0):
    box(coll, "Crane-col", (loc[0], loc[1] + 26.0, loc[2]), (3.0, 52.0, 3.0), mat, yaw=yaw)
    box(coll, "CraneBoom", (loc[0] + 15.0, loc[1] + 50.0, loc[2]),
        (32.0, 2.0, 2.0), mat, yaw=yaw)


def billboard(coll, loc, mat, panel_mat, yaw=0.0):
    box(coll, "BillboardPost", (loc[0] - 5.0, loc[1] + 4.0, loc[2]),
        (0.8, 8.0, 0.8), mat, yaw=yaw)
    box(coll, "BillboardPost", (loc[0] + 5.0, loc[1] + 4.0, loc[2]),
        (0.8, 8.0, 0.8), mat, yaw=yaw)
    box(coll, "BillboardPanel", (loc[0], loc[1] + 10.0, loc[2]),
        (12.0, 5.0, 0.5), panel_mat, yaw=yaw)


def tree(coll, loc, trunk_mat, leaf_mat, scale=1.0):
    cylinder(coll, "TreeTrunk-convcol", (loc[0], loc[1] + 3.0 * scale, loc[2]),
             0.6 * scale, 6.0 * scale, trunk_mat, 8)
    box(coll, "TreeLeaf-convcol", (loc[0], loc[1] + 8.0 * scale, loc[2]),
        (6.5 * scale, 6.5 * scale, 6.5 * scale), leaf_mat)
    box(coll, "TreeLeaf-convcol", (loc[0], loc[1] + 12.0 * scale, loc[2]),
        (4.5 * scale, 4.5 * scale, 4.5 * scale), leaf_mat, yaw=0.6)


def hangar(coll, loc, size, mat, roof_mat, yaw=0.0):
    w, h, d = size
    box(coll, "Hangar-col", (loc[0], loc[1] + h * 0.5, loc[2]), (w, h, d), mat, yaw=yaw)
    box(coll, "HangarRoof", (loc[0], loc[1] + h + 1.0, loc[2]),
        (w + 3.0, 2.5, d + 3.0), roof_mat, yaw=yaw)
    box(coll, "HangarDoor", (loc[0], loc[1] + h * 0.45, loc[2] + d * 0.5 + 0.3),
        (w * 0.6, h * 0.8, 0.4), roof_mat, yaw=yaw)


def terrain(coll, name, size, subdivisions, height, material, seed=1.0,
            flatten_center=0.0):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=subdivisions,
                                    y_subdivisions=subdivisions, size=size,
                                    location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    for vertex in obj.data.vertices:
        x, y = vertex.co.x, vertex.co.y
        n = noise.noise(Vector((x * 0.0016, y * 0.0016, seed)))
        n2 = noise.noise(Vector((x * 0.006, y * 0.006, seed + 5.0)))
        ridge = 1.0 - abs(n)
        z = (n2 * 0.35 + ridge * 0.9) * height
        if flatten_center > 0.0:
            d = math.hypot(x, y)
            if d < flatten_center:
                z *= max(0.0, d / flatten_center)
        vertex.co.z = z
    obj.data.update()
    if material is not None:
        obj.data.materials.append(material)
    return link(coll, obj)


def terrain_height(x: float, y: float, height: float, seed: float = 1.0) -> float:
    n = noise.noise(Vector((x * 0.0016, y * 0.0016, seed)))
    n2 = noise.noise(Vector((x * 0.006, y * 0.006, seed + 5.0)))
    ridge = 1.0 - abs(n)
    return (n2 * 0.35 + ridge * 0.9) * height


def flattened_height(x: float, z: float, height: float, seed: float,
                     flatten: float) -> float:
    h = terrain_height(x, z, height, seed)
    if flatten > 0.0:
        d = math.hypot(x, z)
        if d < flatten:
            h *= max(0.0, d / flatten)
    return h


def forest(coll, center, radius, count, trunk_mat, leaf_mat, height, seed,
           flatten, min_radius=0.0, scale=(0.8, 1.6)):
    rng = random.Random(int(center[0]) * 13 + int(center[1]) * 7 + count)
    for i in range(count):
        angle = rng.uniform(0.0, math.tau)
        rr = rng.uniform(min_radius, radius)
        x = center[0] + math.cos(angle) * rr
        z = center[1] + math.sin(angle) * rr
        y = flattened_height(x, z, height, seed, flatten)
        tree(coll, (x, y - 0.5, z), trunk_mat, leaf_mat,
             rng.uniform(scale[0], scale[1]))


def undergrowth(coll, center, radius, count, bush_mat, flower_mat, height, seed,
                flatten, min_radius=0.0):
    rng = random.Random(int(center[0]) * 5 + count)
    for i in range(count):
        angle = rng.uniform(0.0, math.tau)
        rr = rng.uniform(min_radius, radius)
        x = center[0] + math.cos(angle) * rr
        z = center[1] + math.sin(angle) * rr
        y = flattened_height(x, z, height, seed, flatten)
        if rng.random() < 0.7:
            s = rng.uniform(1.2, 2.6)
            box(coll, "Bush-convcol", (x, y + s * 0.4, z), (s, s * 0.8, s), bush_mat)
        else:
            box(coll, "Flower", (x, y + 0.3, z), (0.5, 0.6, 0.5), flower_mat)


def new_collection(name):
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    for child in bpy.context.view_layer.layer_collection.children:
        if child.collection == coll:
            bpy.context.view_layer.active_layer_collection = child
            break
    return coll


def export_collection(coll, path):
    bpy.ops.object.select_all(action="DESELECT")
    active = None
    for obj in coll.all_objects:
        if obj.type == "MESH":
            obj.select_set(True)
            active = obj
    if active is not None:
        bpy.context.view_layer.objects.active = active
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_cameras=False,
        export_lights=False)
    print(f"[maps] wrote {path}")


# ------------------------------------------------------------------ palettes
def palette_city():
    return {
        "grass": flat("Grass", (0.16, 0.30, 0.14), 1.0),
        "asphalt": flat("Asphalt", (0.10, 0.10, 0.11), 0.85),
        "sidewalk": flat("Sidewalk", (0.40, 0.40, 0.42), 0.9),
        "b1": flat("CityA", (0.55, 0.53, 0.50), 0.85),
        "b2": flat("CityB", (0.42, 0.44, 0.48), 0.85),
        "b3": flat("CityC", (0.60, 0.52, 0.44), 0.85),
        "roof": flat("CityRoof", (0.18, 0.18, 0.20), 0.8),
        "trunk": flat("Trunk", (0.26, 0.19, 0.11), 0.95),
        "leaf": flat("Leaf", (0.13, 0.34, 0.13), 0.95),
        "metal": flat("Metal", (0.22, 0.24, 0.27), 0.45, 0.6),
        "lamp": flat("Lamp", (1.0, 0.88, 0.62), 0.4, 0.0, 4.0),
        "pad": flat("Pad", (0.16, 0.60, 0.30), 0.85),
        "accent2": flat("Accent2", (0.10, 0.85, 0.70), 0.5, 0.2),
    }


def palette_field():
    return {
        "field": flat("Field", (0.24, 0.29, 0.15), 1.0),
        "field2": flat("Field2", (0.31, 0.30, 0.17), 1.0),
        "dirt": flat("Dirt", (0.32, 0.24, 0.15), 0.95),
        "mud": flat("Mud", (0.24, 0.18, 0.12), 0.95),
        "concrete": flat("Concrete", (0.40, 0.40, 0.38), 0.85),
        "concrete2": flat("Concrete2", (0.28, 0.28, 0.27), 0.85),
        "sandbag": flat("Sandbag", (0.38, 0.34, 0.24), 0.95),
        "wood": flat("Wood", (0.30, 0.21, 0.12), 0.9),
        "rust": flat("Rust", (0.36, 0.20, 0.10), 0.85),
        "leaf": flat("Hedge", (0.15, 0.28, 0.13), 0.95),
        "metal": flat("Metal", (0.20, 0.21, 0.23), 0.5, 0.5),
        "pad": flat("Pad", (0.60, 0.55, 0.20), 0.85),
        "accent": flat("Accent", (0.90, 0.35, 0.10), 0.5, 0.2),
    }


def palette_desert():
    return {
        "sand": flat("Sand", (0.62, 0.47, 0.28), 1.0),
        "sand2": flat("Sand2", (0.55, 0.40, 0.23), 1.0),
        "rock": flat("Rock", (0.46, 0.34, 0.22), 0.95),
        "rock2": flat("Rock2", (0.36, 0.26, 0.17), 0.95),
        "track": flat("Track", (0.14, 0.13, 0.13), 0.8),
        "accent": flat("Accent", (0.95, 0.45, 0.08), 0.5, 0.2),
        "accent2": flat("Accent2", (0.10, 0.85, 0.70), 0.5, 0.2),
        "pad": flat("Pad", (0.16, 0.55, 0.30), 0.85),
    }


# ------------------------------------------------------------------ training (city)
def build_training(coll, mats):
    terrain(coll, "Ground-col", 2800.0, 110, 42.0, mats["grass"], seed=1.0,
            flatten_center=780.0)
    roads = range(-5, 6)
    for i in roads:
        plane(coll, "Road-col", (i * 130.0, 2.05, 0), (26.0, 1700.0), mats["asphalt"])
        plane(coll, "Road-col", (0, 2.05, i * 130.0), (1700.0, 26.0), mats["asphalt"])
        plane(coll, "Sidewalk-col", (i * 130.0 + 16.0, 2.1, 0), (6.0, 1700.0), mats["sidewalk"])
        plane(coll, "Sidewalk-col", (i * 130.0 - 16.0, 2.1, 0), (6.0, 1700.0), mats["sidewalk"])
        plane(coll, "Sidewalk-col", (0, 2.1, i * 130.0 + 16.0), (1700.0, 6.0), mats["sidewalk"])
        plane(coll, "Sidewalk-col", (0, 2.1, i * 130.0 - 16.0), (1700.0, 6.0), mats["sidewalk"])
    rng = random.Random(5)
    for bx in roads:
        for bz in roads:
            cx = bx * 130.0 + 65.0
            cz = bz * 130.0 + 65.0
            if math.hypot(cx, cz) > 740.0:
                continue
            if rng.random() < 0.16:
                for _ in range(6):
                    tree(coll, (cx + rng.uniform(-45, 45), 2.0, cz + rng.uniform(-45, 45)),
                         mats["trunk"], mats["leaf"], rng.uniform(0.8, 1.4))
                continue
            for _ in range(rng.randint(1, 3)):
                w = rng.uniform(24.0, 58.0)
                d = rng.uniform(24.0, 58.0)
                floors = rng.randint(2, 7)
                h = floors * 9.0
                building(coll, (cx + rng.uniform(-34, 34), 2.0 + h * 0.5,
                        cz + rng.uniform(-34, 34)), (w, h, d),
                        rng.choice([mats["b1"], mats["b2"], mats["b3"]]),
                        mats["roof"], floors)
    for i in roads:
        for j in range(-7, 8):
            x = i * 130.0 + 16.0
            z = j * 62.0
            box(coll, "LampPost", (x, 5.5, z), (0.3, 7.0, 0.3), mats["metal"])
            box(coll, "LampHead", (x, 9.2, z), (0.9, 0.35, 0.9), mats["lamp"])
    for i in range(6):
        angle = i / 6.0 * math.tau
        x = math.cos(angle) * 300.0
        z = math.sin(angle) * 300.0
        cylinder(coll, "RooftopPad-col", (x, 44.0, z), 12.0, 1.0, mats["pad"])
        plane(coll, "SquarePad-col", (math.cos(angle) * 470.0, 2.2,
                math.sin(angle) * 470.0), (44.0, 44.0), mats["sidewalk"])
    rng2 = random.Random(3)
    for i in range(24):
        x = rng2.uniform(-660.0, 660.0)
        z = rng2.uniform(-660.0, 660.0)
        y = 20.0 + rng2.uniform(0.0, 52.0)
        ring(coll, "Ring", (x, y, z), 6.5, mats["accent2"], yaw=rng2.uniform(0, math.pi))
    for i in range(10):
        angle = random.uniform(0, math.tau)
        radius = random.uniform(140.0, 600.0)
        x = math.cos(angle) * radius
        z = math.sin(angle) * radius
        square_gate(coll, (x, 22.0 + random.uniform(0, 30), z),
                    (14.0, 14.0, 1.6), mats["accent2"])
    # forests on the city outskirts and green undergrowth in the parks
    forest(coll, (0.0, 0.0), 1450.0, 220, mats["trunk"], mats["leaf"], 42.0, 1.0,
           780.0, min_radius=720.0)
    undergrowth(coll, (0.0, 0.0), 1400.0, 260, mats["leaf"], mats["accent2"],
                42.0, 1.0, 780.0, min_radius=700.0)


# ------------------------------------------------------------------ combat (fields)
def build_combat(coll, mats):
    terrain(coll, "Ground-col", 2300.0, 96, 14.0, mats["field"], seed=9.0,
            flatten_center=620.0)
    for offset in (-480.0, 0.0, 480.0):
        plane(coll, "Road-col", (offset, 0.06, 0), (26.0, 2000.0), mats["dirt"])
        plane(coll, "Road-col", (0, 0.06, offset), (2000.0, 26.0), mats["dirt"])
    # hedgerows dividing the fields
    for i in range(24):
        x = random.uniform(-950.0, 950.0)
        z = random.uniform(-950.0, 950.0)
        length = random.uniform(60.0, 120.0)
        box(coll, "Hedge-convcol", (x, 2.6, z), (length, 5.2, 3.0), mats["leaf"],
            yaw=random.uniform(0.0, math.pi))
    # trenches with sandbag parapets
    for i in range(16):
        x = random.uniform(-820.0, 820.0)
        z = random.uniform(-820.0, 820.0)
        a = random.uniform(0.0, math.pi)
        box(coll, "Trench-col", (x, 0.8, z), (76.0, 2.2, 7.0), mats["mud"], yaw=a)
        for k in range(10):
            px = x + math.cos(a) * (k - 4.5) * 7.4
            pz = z + math.sin(a) * (k - 4.5) * 7.4
            box(coll, "Sandbag-col", (px, 1.9, pz), (6.2, 1.6, 2.4), mats["sandbag"], yaw=a)
    # bunkers / pillboxes
    for i in range(12):
        x = random.uniform(-760.0, 760.0)
        z = random.uniform(-760.0, 760.0)
        a = random.uniform(0.0, math.pi)
        box(coll, "Bunker-col", (x, 2.6, z), (16.0, 5.2, 11.0), mats["concrete"], yaw=a)
        box(coll, "BunkerSlit", (x + math.cos(a) * 6.0, 3.6, z + math.sin(a) * 6.0),
            (0.5, 0.9, 6.5), mats["concrete2"], yaw=a)
        box(coll, "BunkerRoof", (x, 5.6, z), (18.0, 1.2, 13.0), mats["concrete2"], yaw=a)
    # ruined village
    rng = random.Random(31)
    for cluster in range(3):
        cx = random.uniform(-700.0, 700.0)
        cz = random.uniform(-700.0, 700.0)
        for i in range(rng.randint(5, 9)):
            x = cx + rng.uniform(-90, 90)
            z = cz + rng.uniform(-90, 90)
            w = rng.uniform(14.0, 26.0)
            d = rng.uniform(14.0, 26.0)
            h = rng.uniform(6.0, 16.0)
            box(coll, "Ruin-col", (x, h * 0.5, z), (w, h, d),
                rng.choice([mats["concrete"], mats["wood"], mats["concrete2"]]),
                yaw=rng.uniform(0, math.pi))
            if rng.random() < 0.5:
                box(coll, "RuinBeam", (x, h + 1.0, z), (w * 0.4, 2.0, d * 0.4),
                    mats["wood"], yaw=rng.uniform(0, math.pi))
    # watchtowers
    for i in range(10):
        angle = i / 10.0 * math.tau
        x = math.cos(angle) * rng.uniform(320.0, 520.0)
        z = math.sin(angle) * rng.uniform(320.0, 520.0)
        box(coll, "WatchTower-col", (x, 24.0, z), (9.0, 48.0, 9.0), mats["wood"])
        box(coll, "WatchTop", (x, 50.0, z), (14.0, 4.0, 14.0), mats["metal"])
    # craters
    for i in range(34):
        x = random.uniform(-880.0, 880.0)
        z = random.uniform(-880.0, 880.0)
        cylinder(coll, "Crater", (x, 0.12, z), random.uniform(6.0, 15.0), 0.3,
                 mats["mud"], random.uniform(0, math.pi))
    # wrecked static vehicles / hulls
    for i in range(14):
        x = random.uniform(-820.0, 820.0)
        z = random.uniform(-820.0, 820.0)
        a = random.uniform(0.0, math.pi)
        box(coll, "Wreck-col", (x, 1.4, z), (6.4, 2.4, 3.2), mats["rust"], yaw=a)
        box(coll, "WreckTurret", (x, 3.0, z), (3.0, 1.4, 2.6), mats["metal"], yaw=a)
    # container depots and square cover
    for i in range(12):
        x = random.uniform(-820.0, 820.0)
        z = random.uniform(-820.0, 820.0)
        container_stack(coll, (x, 0.0, z), mats["rust"], random.randint(2, 4),
                        random.uniform(0, math.pi))
    for i in range(20):
        x = random.uniform(-820.0, 820.0)
        z = random.uniform(-820.0, 820.0)
        box(coll, "SquareCover-col", (x, 3.0, z), (11.0, 6.0, 11.0), mats["sandbag"])
    for i in range(4):
        x = random.uniform(-500.0, 500.0)
        z = random.uniform(-500.0, 500.0)
        hangar(coll, (x, 0.0, z), (44.0, 13.0, 32.0), mats["concrete"],
               mats["rust"], yaw=random.uniform(0, math.pi))
    for i in range(6):
        angle = i / 6.0 * math.tau
        x = math.cos(angle) * 430.0
        z = math.sin(angle) * 430.0
        billboard(coll, (x, 0.0, z), mats["metal"], mats["accent"], yaw=angle)
    for i in range(4):
        angle = i / 4.0 * math.tau
        cylinder(coll, "SpawnPad-col", (math.cos(angle) * 140.0, 0.6,
                 math.sin(angle) * 140.0), 12.0, 1.0, mats["pad"])
    # forest belts and field undergrowth
    forest(coll, (0.0, 0.0), 1180.0, 240, mats["wood"], mats["leaf"], 14.0, 9.0,
           620.0, min_radius=260.0)
    undergrowth(coll, (0.0, 0.0), 1100.0, 320, mats["leaf"], mats["accent"],
                14.0, 9.0, 620.0, min_radius=180.0)


# ------------------------------------------------------------------ speed (desert)
def build_speed(coll, mats):
    rx = 700.0
    ry = 380.0
    count = 140
    track_w = 54.0
    for i in range(count):
        t = i / count * math.tau
        t2 = (i + 1) / count * math.tau
        x0, y0 = math.cos(t) * rx, math.sin(t) * ry
        x1, y1 = math.cos(t2) * rx, math.sin(t2) * ry
        lx, lz = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        seg = math.hypot(x1 - x0, y1 - y0)
        yaw = math.atan2(y1 - y0, x1 - x0)
        box(coll, "Track-col", (lx, 20.0, lz), (seg + 6.0, 2.0, track_w),
            mats["track"], yaw=yaw)
        nx, nz = math.cos(yaw + math.pi * 0.5), math.sin(yaw + math.pi * 0.5)
        # Leave a wide open pocket around the start grid: the spawn looks down
        # an unobstructed straight instead of being boxed in by canyon walls.
        if i in (0, 1, 2, 3, 136, 137, 138, 139):
            continue
        for side in [-1, 1]:
            wx = lx + nx * side * (track_w * 0.5 + 28.0)
            wz = lz + nz * side * (track_w * 0.5 + 28.0)
            box(coll, "Canyon-colonly", (wx, 40.0, wz), (seg + 8.0, 80.0, 40.0),
                None, yaw=yaw)
            # Ground the visible cliff instead of floating a rock slab at 66 m:
            # from the cockpit the old slabs read as a ceiling over the track.
            box(coll, "CanyonRock-convcol", (wx, 40.0, wz),
                (seg + 8.0, 80.0, 34.0), mats["rock"], yaw=yaw)
    for i in range(20):
        t = (i + 0.5) / 20.0 * math.tau
        x, z = math.cos(t) * rx, math.sin(t) * ry
        yaw = math.atan2(-math.sin(t) * rx, math.cos(t) * ry) + math.pi * 0.5
        # Rock spires guard the shoulders instead of growing out of the racing
        # line, so the canyon stays readable and every gate is flyable.
        side = -1.0 if i % 2 == 0 else 1.0
        off = track_w * 0.5 + 9.0
        px = x + math.cos(yaw + math.pi * 0.5) * side * off
        pz = z + math.sin(yaw + math.pi * 0.5) * side * off
        box(coll, "CanyonPillar-convcol", (px, 40.0, pz), (10.0, 80.0, 10.0),
            mats["rock2"], yaw=yaw)
        # The start gate is the glowing checkpoint ring; a canyon arch directly
        # over it used to box the spawn in, so keep the grid open.
        if i != 0:
            square_gate(coll, (x, 34.0, z), (18.0, 18.0, 2.0), mats["accent"], yaw=yaw)
    for i in range(20):
        t = i / 20.0 * math.tau
        if i == 0:
            # No arch over the starting grid: the spawn must look down an open
            # straight with only the first checkpoint ring ahead.
            continue
        x, z = math.cos(t) * rx, math.sin(t) * ry
        yaw = math.atan2(-math.sin(t) * rx, math.cos(t) * ry) + math.pi * 0.5
        left = (x + math.cos(yaw + math.pi * 0.5) * 30.0,
                z + math.sin(yaw + math.pi * 0.5) * 30.0)
        right = (x + math.cos(yaw - math.pi * 0.5) * 30.0,
                 z + math.sin(yaw - math.pi * 0.5) * 30.0)
        box(coll, "ArchPost", (left[0], 36.0, left[1]), (4.0, 36.0, 4.0), mats["accent"], yaw=yaw)
        box(coll, "ArchPost", (right[0], 36.0, right[1]), (4.0, 36.0, 4.0), mats["accent"], yaw=yaw)
        box(coll, "ArchTop", (x, 56.0, z), (60.0, 4.0, 4.0), mats["accent"], yaw=yaw)
    for i in range(12):
        t = i / 12.0 * math.tau
        x, z = math.cos(t) * rx, math.sin(t) * ry
        yaw = math.atan2(-math.sin(t) * rx, math.cos(t) * ry) + math.pi * 0.5
        box(coll, "BoostPad", (x, 21.5, z), (18.0, 0.5, 12.0), mats["accent2"], yaw=yaw)
        container_stack(coll, (x + math.cos(yaw) * 90.0, 20.0, z + math.sin(yaw) * 90.0),
                        mats["rock2"], 2, yaw)
    for i in range(8):
        t = i / 8.0 * math.tau
        x, z = math.cos(t) * (rx + 70.0), math.sin(t) * (ry + 70.0)
        crane(coll, (x, 20.0, z), mats["rock2"], t)
    plane(coll, "StartGrid-col", (rx, 21.3, 0), (90.0, track_w), mats["pad"])
    for i in range(6):
        angle = random.uniform(0, math.tau)
        radius = random.uniform(300.0, 900.0)
        x = math.cos(angle) * radius
        z = math.sin(angle) * radius
        box(coll, "Dune-convcol", (x, -6.0, z), (random.uniform(80, 160), 20.0,
            random.uniform(80, 160)), mats["sand2"], yaw=angle)


# ------------------------------------------------------------------ main
def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # MAP_ONLY=map_speed rebuilds one map without touching big_maps.blend or
    # the other two GLBs (useful while iterating on a single course).
    selected = os.environ.get("MAP_ONLY", "").strip().lower()
    for coll_name, stem, builder, palette in [
            ("COL_Training", "map_training", build_training, palette_city),
            ("COL_Combat", "map_combat", build_combat, palette_field),
            ("COL_Speed", "map_speed", build_speed, palette_desert)]:
        if selected and selected != stem:
            continue
        clear_scene()
        mats = palette()
        coll = new_collection(coll_name)
        builder(coll, mats)
        export_collection(coll, OUT_DIR / f"{stem}.glb")
    if not selected:
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
        print(f"[maps] saved {BLEND_PATH}")


main()
