## Enhance handcrafted GLBs (factory_complex, farm_complex, village_house, wetlands_dock)
## with 3D architectural relief (pilasters, cornice ledges, window/door trim,
## deep foundation skirts) and extra compound objects, while preserving all
## existing materials, UV maps, and node names.
import bpy
import bmesh
from mathutils import Vector, Matrix
import math
import os

HANDCRAFTED_DIR = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted"


def add_box_to_bmesh(bm, size, center, rot=(0.0, 0.0, 0.0)):
    bmesh.ops.create_cube(bm, size=1.0)
    verts = bm.verts[-8:]
    sx, sy, sz = size
    rx, ry, rz = rot
    mat = (
        Matrix.Translation(Vector(center))
        @ Matrix.Rotation(rz, 4, "Z")
        @ Matrix.Rotation(ry, 4, "Y")
        @ Matrix.Rotation(rx, 4, "X")
        @ Matrix.Diagonal(Vector((sx, sy, sz, 1.0)))
    )
    bmesh.ops.transform(bm, matrix=mat, verts=verts)


def add_cyl_to_bmesh(bm, radius, depth, center, rot=(0.0, 0.0, 0.0), segs=12):
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    verts = ret["verts"]
    rx, ry, rz = rot
    mat = (
        Matrix.Translation(Vector(center))
        @ Matrix.Rotation(rz, 4, "Z")
        @ Matrix.Rotation(ry, 4, "Y")
        @ Matrix.Rotation(rx, 4, "X")
    )
    bmesh.ops.transform(bm, matrix=mat, verts=verts)


def append_geometry(obj, boxes, cyls=()):
    if obj is None or obj.type != "MESH":
        return
    inv = obj.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.active
    if uv_layer is None:
        uv_layer = bm.loops.layers.uv.new("UVMap")
    start_faces = len(bm.faces)
    for size, world_center, rot in boxes:
        local_center = inv @ Vector(world_center)
        add_box_to_bmesh(bm, size, local_center, rot)
    for radius, depth, world_center, rot in cyls:
        local_center = inv @ Vector(world_center)
        add_cyl_to_bmesh(bm, radius, depth, local_center, rot)
    bm.faces.ensure_lookup_table()
    for f in bm.faces[start_faces:]:
        n = f.normal
        for loop in f.loops:
            co = loop.vert.co
            if abs(n.z) > 0.7:
                loop[uv_layer].uv = (co.x * 0.25, co.y * 0.25)
            elif abs(n.x) > abs(n.y):
                loop[uv_layer].uv = (co.y * 0.25, co.z * 0.25)
            else:
                loop[uv_layer].uv = (co.x * 0.25, co.z * 0.25)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[start_faces:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def enhance_factory():
    path = os.path.join(HANDCRAFTED_DIR, "factory_complex.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    brick_obj = bpy.data.objects.get("hall_main")
    conc_obj = bpy.data.objects.get("hall_main_par-1")
    metal_obj = bpy.data.objects.get("wh1")

    conc_boxes = []
    conc_cyls = []
    brick_boxes = []
    metal_boxes = []
    metal_cyls = []

    # 1. Main brick hall [-32..32, -13..13, 0..20]: deep foundation skirt + pilasters + cornice ledges
    conc_boxes.append(((65.2, 27.2, 4.0), (0.0, 0.0, -1.9), (0, 0, 0)))
    for x in range(-28, 30, 8):
        for sy in (-1, 1):
            conc_boxes.append(((0.9, 0.8, 19.6), (float(x), sy * 13.25, 9.9), (0, 0, 0)))
            conc_boxes.append(((1.3, 1.1, 2.6), (float(x), sy * 13.35, 1.3), (0, 0, 0)))
    for sy in (-1, 1):
        conc_boxes.append(((64.6, 0.7, 0.45), (0.0, sy * 13.2, 10.2), (0, 0, 0)))
        conc_boxes.append(((64.6, 0.85, 0.55), (0.0, sy * 13.25, 19.6), (0, 0, 0)))
    # Rooftop ventilator housings on main brick hall
    for x in (-20.0, -6.0, 8.0, 22.0):
        metal_boxes.append(((3.4, 3.8, 2.2), (x, 0.0, 21.8), (0, 0, 0)))
        metal_boxes.append(((3.9, 4.3, 0.28), (x, 0.0, 23.0), (0, 0, 0)))

    # 2. West concrete annex [-116..-68, 14..34, 0..15]: foundation + pilasters + transformer substation
    conc_boxes.append(((49.0, 21.0, 4.0), (-92.0, 24.0, -1.9), (0, 0, 0)))
    for x in range(-112, -68, 8):
        for y in (13.8, 34.2):
            conc_boxes.append(((0.85, 0.75, 14.8), (float(x), y, 7.4), (0, 0, 0)))
    conc_boxes.append(((48.8, 20.8, 0.5), (-92.0, 24.0, 14.8), (0, 0, 0)))
    # Transformer substation yard next to west annex (-92, 42)
    conc_boxes.append(((14.0, 8.5, 2.6), (-92.0, 42.5, -0.5), (0, 0, 0)))
    for i in range(3):
        tx = -96.5 + i * 4.5
        metal_boxes.append(((2.8, 2.4, 3.4), (tx, 42.5, 2.4), (0, 0, 0)))
        for r in (-0.9, 0.0, 0.9):
            metal_boxes.append(((0.22, 2.8, 2.8), (tx + r, 42.5, 2.4), (0, 0, 0)))
        conc_cyls.append((0.22, 1.4, (tx - 0.6, 42.5, 4.6), (0, 0, 0)))
        conc_cyls.append((0.22, 1.4, (tx + 0.6, 42.5, 4.6), (0, 0, 0)))

    # 3. East concrete annex [75..117, -27..-9, 0..13]: foundation + pilasters + compressor shed + tanks
    conc_boxes.append(((43.0, 19.0, 4.0), (96.0, -18.0, -1.9), (0, 0, 0)))
    for x in range(78, 116, 8):
        for y in (-27.2, -8.8):
            conc_boxes.append(((0.85, 0.75, 12.8), (float(x), y, 6.4), (0, 0, 0)))
    conc_boxes.append(((42.8, 18.8, 0.5), (96.0, -18.0, 12.8), (0, 0, 0)))
    # New brick compressor house & horizontal pressure vessels at (52, -20)
    conc_boxes.append(((15.0, 11.0, 3.8), (52.0, -20.0, -1.1), (0, 0, 0)))
    brick_boxes.append(((14.0, 10.0, 6.4), (52.0, -20.0, 3.8), (0, 0, 0)))
    metal_boxes.append(((14.8, 10.8, 0.55), (52.0, -20.0, 7.2), (0, 0, 0)))
    for k in range(2):
        ty = -33.5 - k * 4.8
        conc_boxes.append(((12.0, 3.4, 2.4), (52.0, ty, -0.4), (0, 0, 0)))
        metal_cyls.append((1.65, 11.0, (52.0, ty, 2.5), (0.0, math.pi * 0.5, 0.0)))

    # 4. Two warehouses wh1 [-54..-14, 87..105] and [-2..38, 87..105]: foundation + buttresses + loading canopy
    conc_boxes.append(((41.2, 19.2, 4.0), (-34.0, 96.0, -1.9), (0, 0, 0)))
    conc_boxes.append(((41.2, 19.2, 4.0), (18.0, 96.0, -1.9), (0, 0, 0)))
    for cx in (-34.0, 18.0):
        for dx in range(-16, 18, 8):
            for y in (86.8, 105.2):
                metal_boxes.append(((0.65, 0.65, 9.8), (cx + dx, y, 4.9), (0, 0, 0)))
        metal_boxes.append(((14.0, 3.6, 0.35), (cx, 85.2, 5.4), (0.12, 0, 0)))
        conc_boxes.append(((14.4, 3.2, 1.4), (cx, 85.4, 0.4), (0, 0, 0)))

    append_geometry(conc_obj, conc_boxes, conc_cyls)
    append_geometry(brick_obj, brick_boxes)
    append_geometry(metal_obj, metal_boxes, metal_cyls)

    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=False, export_apply=False
    )
    print("[ENHANCE] exported", path)


def enhance_farm():
    path = os.path.join(HANDCRAFTED_DIR, "farm_complex.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    barn_obj = bpy.data.objects.get("barn")
    head_obj = bpy.data.objects.get("head")
    roof_obj = bpy.data.objects.get("head_roof")

    conc_boxes = []
    conc_cyls = []
    wood_boxes = []
    roof_boxes = []

    # 1. Barn [13.3..34.7, 12..24] and Elevator head [11.5..21.5, -5..5, 0..24]: deep foundations + pilasters
    conc_boxes.append(((22.6, 13.2, 4.5), (24.0, 18.0, -2.1), (0, 0, 0)))
    conc_boxes.append(((11.2, 11.2, 4.5), (16.5, 0.0, -2.1), (0, 0, 0)))
    for z in (6.0, 12.0, 18.0, 23.6):
        conc_boxes.append(((10.6, 10.6, 0.45), (16.5, 0.0, z), (0, 0, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            conc_boxes.append(((0.85, 0.85, 24.0), (16.5 + sx * 4.9, sy * 4.9, 12.0), (0, 0, 0)))
    # Timber buttresses and window/door framing on the barn
    for x in (14.5, 19.0, 24.0, 29.0, 33.5):
        for y in (11.85, 24.15):
            wood_boxes.append(((0.48, 0.48, 7.6), (x, y, 3.8), (0, 0, 0)))
    wood_boxes.append(((22.0, 0.45, 0.38), (24.0, 11.82, 4.4), (0, 0, 0)))
    wood_boxes.append(((22.0, 0.45, 0.38), (24.0, 24.18, 4.4), (0, 0, 0)))

    # 2. Additional farm objects: Machinery / Tractor shed & Grain Weighbridge at (-4.0, 16.0)
    conc_boxes.append(((16.4, 9.4, 4.2), (-4.0, 16.0, -1.9), (0, 0, 0)))
    wood_boxes.append(((15.6, 0.45, 4.6), (-4.0, 20.2, 2.3), (0, 0, 0)))
    for x in (-11.2, -6.4, -1.6, 3.2):
        wood_boxes.append(((0.42, 0.42, 4.8), (x, 11.8, 2.4), (0, 0, 0)))
        wood_boxes.append(((0.42, 0.42, 5.2), (x, 20.2, 2.6), (0, 0, 0)))
        wood_boxes.append(((0.35, 8.8, 0.35), (x, 16.0, 4.7), (0.08, 0, 0)))
    roof_boxes.append(((16.6, 9.6, 0.28), (-4.0, 16.0, 5.0), (0.08, 0, 0)))

    # Weighbridge deck + operator booth at (-2.0, -8.0)
    conc_boxes.append(((13.0, 4.4, 3.2), (-2.0, -8.0, -1.3), (0, 0, 0)))
    for x in (-7.5, -2.0, 3.5):
        for sy in (-1, 1):
            wood_boxes.append(((0.35, 0.35, 1.1), (x, -8.0 + sy * 2.0, 0.8), (0, 0, 0)))
    conc_boxes.append(((4.6, 4.0, 3.4), (-11.5, -8.0, -1.4), (0, 0, 0)))
    wood_boxes.append(((4.0, 3.4, 3.2), (-11.5, -8.0, 1.8), (0, 0, 0)))
    roof_boxes.append(((4.6, 4.0, 0.35), (-11.5, -8.0, 3.55), (0.1, 0, 0)))

    append_geometry(conc_obj if False else head_obj, conc_boxes, conc_cyls)
    append_geometry(barn_obj, wood_boxes)
    append_geometry(roof_obj, roof_boxes)

    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=False, export_apply=False
    )
    print("[ENHANCE] exported", path)


def enhance_village():
    path = os.path.join(HANDCRAFTED_DIR, "village_house.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    plaster_obj = bpy.data.objects.get("house1")
    brick_obj = bpy.data.objects.get("house1_chimney")
    wood_obj = bpy.data.objects.get("house1_door")
    roof_obj = bpy.data.objects.get("house1_roof-1")

    plaster_boxes = []
    brick_boxes = []
    wood_boxes = []
    roof_boxes = []

    # 1. Deep foundation plinths & corner quoins/pilasters on the 3 main cottages
    # House A: [-24..-12, -4..4, 0..4.9]
    brick_boxes.append(((12.6, 8.6, 3.8), (-18.0, 0.0, -1.6), (0, 0, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            brick_boxes.append(((0.65, 0.65, 5.0), (-18.0 + sx * 6.0, sy * 4.0, 2.5), (0, 0, 0)))
    plaster_boxes.append(((12.4, 8.4, 0.28), (-18.0, 0.0, 4.85), (0, 0, 0)))

    # House B: [-2.4..6.5, -1.5..5.5, 0..4.1]
    brick_boxes.append(((9.5, 7.6, 3.8), (2.05, 2.0, -1.6), (0, 0, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            brick_boxes.append(((0.55, 0.55, 4.2), (2.05 + sx * 4.45, 2.0 + sy * 3.5, 2.1), (0, 0, 0)))
    plaster_boxes.append(((9.3, 7.4, 0.26), (2.05, 2.0, 4.05), (0, 0, 0)))

    # House C: [15..25, -6.5..0.5, 0..4.6]
    brick_boxes.append(((10.6, 7.6, 3.8), (20.0, -3.0, -1.6), (0, 0, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            brick_boxes.append(((0.60, 0.60, 4.6), (20.0 + sx * 5.0, -3.0 + sy * 3.5, 2.3), (0, 0, 0)))
    plaster_boxes.append(((10.4, 7.4, 0.28), (20.0, -3.0, 4.55), (0, 0, 0)))

    # Brick outbuilding [-38..-30, 4..12, 0..5.9] and timber barn [25.3..42.7, 6..18, 0..6.4]
    brick_boxes.append(((8.6, 8.6, 3.8), (-34.0, 8.0, -1.6), (0, 0, 0)))
    brick_boxes.append(((18.0, 12.6, 3.8), (34.0, 12.0, -1.6), (0, 0, 0)))

    # 2. Additional village compound objects: Covered well (криниця), Summer kitchen (літня кухня) & Cellar (погріб)
    # Summer kitchen at (-8.0, 11.5)
    brick_boxes.append(((7.4, 5.6, 3.6), (-8.0, 11.5, -1.5), (0, 0, 0)))
    plaster_boxes.append(((6.8, 5.0, 3.4), (-8.0, 11.5, 1.9), (0, 0, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            brick_boxes.append(((0.45, 0.45, 3.5), (-8.0 + sx * 3.4, 11.5 + sy * 2.5, 1.9), (0, 0, 0)))
    roof_boxes.append(((7.4, 3.2, 0.25), (-8.0, 10.2, 4.1), (0.38, 0, 0)))
    roof_boxes.append(((7.4, 3.2, 0.25), (-8.0, 12.8, 4.1), (-0.38, 0, 0)))
    brick_boxes.append(((0.65, 0.65, 1.6), (-6.2, 11.5, 4.8), (0, 0, 0)))

    # Village well with pitched canopy at (-7.0, -3.5)
    brick_boxes.append(((2.2, 2.2, 3.2), (-7.0, -3.5, -1.2), (0, 0, 0)))
    wood_boxes.append(((1.6, 1.6, 1.0), (-7.0, -3.5, 0.8), (0, 0, 0)))
    for sy in (-0.7, 0.7):
        wood_boxes.append(((0.18, 0.18, 2.2), (-7.0, -3.5 + sy, 1.9), (0, 0, 0)))
    roof_boxes.append(((2.2, 1.4, 0.16), (-7.0, -4.0, 3.1), (0.5, 0, 0)))
    roof_boxes.append(((2.2, 1.4, 0.16), (-7.0, -3.0, 3.1), (-0.5, 0, 0)))

    # Arched root cellar (погріб) at (11.0, 10.5)
    brick_boxes.append(((5.6, 6.4, 3.4), (11.0, 10.5, -1.4), (0, 0, 0)))
    brick_boxes.append(((5.0, 5.8, 2.2), (11.0, 10.5, 1.1), (0, 0, 0)))
    wood_boxes.append(((1.4, 0.22, 1.9), (11.0, 7.55, 1.0), (0, 0, 0)))
    roof_boxes.append(((5.4, 6.2, 0.35), (11.0, 10.5, 2.35), (0.12, 0, 0)))

    append_geometry(plaster_obj, plaster_boxes)
    append_geometry(brick_obj, brick_boxes)
    append_geometry(wood_obj, wood_boxes)
    append_geometry(roof_obj, roof_boxes)

    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=False, export_apply=False
    )
    print("[ENHANCE] exported", path)


def enhance_wetlands():
    path = os.path.join(HANDCRAFTED_DIR, "wetlands_dock.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    rust_obj = bpy.data.objects.get("barge")
    metal_obj = bpy.data.objects.get("barge_cabin")
    roof_obj = bpy.data.objects.get("barge_roof")
    wood_obj = bpy.data.objects.get("plank0")

    rust_boxes = []
    rust_cyls = []
    metal_boxes = []
    roof_boxes = []
    wood_boxes = []
    wood_cyls = []

    # 1. Barge [0..16, 5..11]: hull ribs, bollards, wheelhouse framing
    for x in range(1, 16, 2):
        for y in (4.92, 11.08):
            rust_boxes.append(((0.22, 0.24, 1.85), (float(x), y, 0.6), (0, 0, 0)))
    for x in (1.2, 14.8):
        for y in (5.5, 10.5):
            rust_cyls.append((0.22, 0.65, (x, y, 1.75), (0, 0, 0)))

    # 2. Deep timber pilings under the dock so it never floats above water/mud
    for x in (-10.0, -5.0, 0.0, 5.0, 10.0):
        for y in (-5.0, -1.5, 2.0, 4.5):
            wood_cyls.append((0.24, 6.5, (x, y, -1.8), (0, 0, 0)))

    # 3. Boathouse / cargo shed on the pier at (-6.5, -1.5) + dock crane at (9.5, 1.5)
    wood_boxes.append(((9.2, 5.4, 0.35), (-6.5, -1.5, 0.85), (0, 0, 0)))
    wood_boxes.append(((8.6, 4.8, 3.4), (-6.5, -1.5, 2.65), (0, 0, 0)))
    for dx in (-4.1, 0.0, 4.1):
        for dy in (-2.3, 2.3):
            wood_boxes.append(((0.32, 0.32, 3.6), (-6.5 + dx, -1.5 + dy, 2.65), (0, 0, 0)))
    roof_boxes.append(((9.4, 3.0, 0.22), (-6.5, -2.7, 4.75), (0.35, 0, 0)))
    roof_boxes.append(((9.4, 3.0, 0.22), (-6.5, -0.3, 4.75), (-0.35, 0, 0)))

    # Dockside jib crane + fuel cistern at (9.5, 1.5)
    rust_boxes.append(((2.4, 2.4, 4.2), (9.5, 1.5, -0.8), (0, 0, 0)))
    metal_boxes.append(((1.8, 1.8, 1.6), (9.5, 1.5, 2.0), (0, 0, 0)))
    rust_cyls.append((0.28, 6.2, (9.5, 1.5, 4.8), (0, 0, 0)))
    rust_boxes.append(((0.35, 6.8, 0.35), (9.5, 4.2, 7.2), (-0.32, 0, 0)))
    # Fuel tank on concrete/rust cradle at (-11.5, 3.2)
    rust_boxes.append(((5.2, 2.8, 3.8), (-11.5, 3.2, -0.6), (0, 0, 0)))
    rust_cyls.append((1.25, 4.8, (-11.5, 3.2, 2.4), (0.0, math.pi * 0.5, 0.0)))

    append_geometry(rust_obj, rust_boxes, rust_cyls)
    append_geometry(metal_obj, metal_boxes)
    append_geometry(roof_obj, roof_boxes)
    append_geometry(wood_obj, wood_boxes, wood_cyls)

    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=False, export_apply=False
    )
    print("[ENHANCE] exported", path)


if __name__ == "__main__":
    enhance_factory()
    enhance_farm()
    enhance_village()
    enhance_wetlands()
