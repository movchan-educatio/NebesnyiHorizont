"""Build the low-poly frontline prop pack for the mobile maps.

Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
      --python tools/build_map_props.py

Every prop is a single joined mesh with one vertex-colour material (COLOR_0),
so one placed prop costs one draw call in Godot.  Origins are at the base
centre; Z is up in Blender, the glTF exporter converts to Y-up.
"""
import bpy
import math
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "Assets", "handcrafted", "props_lowpoly")
MAT = None

# Palette (linear-ish mid tones; Godot multiplies by light).
WOOD = (0.24, 0.16, 0.09)
WOOD_LIGHT = (0.36, 0.26, 0.14)
METAL = (0.27, 0.28, 0.30)
METAL_LIGHT = (0.38, 0.39, 0.40)
RUST = (0.42, 0.20, 0.09)
CONCRETE = (0.44, 0.43, 0.39)
CONCRETE_DARK = (0.30, 0.30, 0.28)
SAND = (0.46, 0.40, 0.26)
CAMO = (0.22, 0.28, 0.15)
CANVAS = (0.34, 0.32, 0.21)
HAY = (0.50, 0.42, 0.18)
GLASS = (0.18, 0.26, 0.30)
WHITE = (0.50, 0.49, 0.45)
BLACK = (0.11, 0.11, 0.12)
ORANGE = (0.55, 0.22, 0.05)
BLUE = (0.10, 0.18, 0.30)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material():
    mat = bpy.data.materials.new("prop_vcol")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
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


def box(name, size, loc, rgb, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    colourise(ob, rgb)
    return ob


def cyl(name, radius, height, loc, rgb, rot=(0.0, 0.0, 0.0), verts=12):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=height,
                                        location=loc, rotation=rot, vertices=verts)
    ob = bpy.context.object
    ob.name = name
    colourise(ob, rgb)
    return ob


def cone(name, radius, height, loc, rgb, rot=(0.0, 0.0, 0.0), verts=8):
    bpy.ops.mesh.primitive_cone_add(radius1=radius, depth=height,
                                    location=loc, rotation=rot, vertices=verts)
    ob = bpy.context.object
    ob.name = name
    colourise(ob, rgb)
    return ob


def gable(name, width, depth, height, loc, rgb, rot_z=0.0):
    """Two slanted slabs forming a gable roof, centred on loc."""
    slope = math.atan2(height, width * 0.5)
    half = math.sqrt((width * 0.5) ** 2 + height ** 2) * 0.5
    parts = []
    for sign in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(
            loc[0] + sign * width * 0.25,
            loc[1],
            loc[2] + height * 0.5), rotation=(0.0, sign * slope, rot_z))
        ob = bpy.context.object
        ob.name = name + ("_L" if sign < 0 else "_R")
        ob.scale = (half * 1.05, depth, 0.06)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        colourise(ob, rgb)
        parts.append(ob)
    return parts


# ---------------------------------------------------------------- builders
def p_checkpoint_booth():
    box("base", (3.0, 2.6, 0.25), (0, 0, 0.12), CONCRETE_DARK)
    box("hut", (2.2, 2.0, 2.4), (0, 0, 1.45), CAMO)
    box("window", (1.1, 0.06, 0.7), (0, -1.02, 1.75), GLASS)
    box("door", (0.7, 0.06, 1.8), (0.65, -1.02, 1.05), WOOD)
    gable("roof", 2.8, 2.4, 0.6, (0, 0, 2.65), RUST)
    box("stripe", (2.24, 0.08, 0.18), (0, -1.02, 2.32), ORANGE)
    box("lamp", (0.18, 0.18, 0.12), (0.8, -1.06, 2.6), WHITE)


def p_sandbag_nest():
    parts = []
    for i in range(10):
        a = i / 10.0 * math.tau
        x = math.cos(a) * 2.2
        y = math.sin(a) * 2.2
        parts.append(box("bag%d" % i, (1.0, 0.55, 0.38),
                         (x, y, 0.19), SAND, (0, 0, a)))
    for i in range(6):
        a = (i / 6.0 + 0.08) * math.tau
        box("bag_top%d" % i, (0.95, 0.5, 0.34),
            (math.cos(a) * 2.2, math.sin(a) * 2.2, 0.53), SAND, (0, 0, a))
    for i in range(3):
        box("crate%d" % i, (0.6, 0.45, 0.4), (-0.8 + i * 0.7, 0, 0.2), WOOD)


def p_ammo_crates():
    box("crate_a", (1.1, 0.7, 0.55), (0, 0, 0.28), WOOD)
    box("crate_b", (1.0, 0.65, 0.5), (0.1, 0.05, 0.8), WOOD_LIGHT)
    box("crate_c", (0.9, 0.6, 0.45), (-1.2, 0.2, 0.23), WOOD)
    box("band_a", (1.12, 0.08, 0.08), (0, 0, 0.55), METAL)
    box("band_b", (1.02, 0.08, 0.08), (0.1, 0.05, 1.0), METAL)


def p_fuel_barrels():
    for i, (x, y, c) in enumerate([(0, 0, RUST), (0.75, 0.15, CAMO), (-0.7, 0.3, BLUE)]):
        cyl("barrel%d" % i, 0.32, 0.9, (x, y, 0.45), c, verts=10)
        cyl("rim%d" % i, 0.34, 0.06, (x, y, 0.86), METAL, verts=10)
    box("pallet", (1.6, 1.0, 0.1), (0, 0, 0.05), WOOD_LIGHT)


def p_watchtower():
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            box("leg", (0.22, 0.22, 5.4), (sx * 1.1, sy * 1.1, 2.7), WOOD)
    box("platform", (3.0, 3.0, 0.22), (0, 0, 5.35), WOOD_LIGHT)
    box("rail_n", (3.0, 0.08, 0.7), (0, -1.45, 5.8), WOOD)
    box("rail_s", (3.0, 0.08, 0.7), (0, 1.45, 5.8), WOOD)
    gable("roof", 3.4, 3.4, 0.9, (0, 0, 5.95), RUST)
    box("brace", (0.16, 0.16, 3.0), (-1.1, 1.1, 3.6), WOOD, (0.5, 0, 0))


def p_bus_stop():
    box("floor", (4.2, 1.8, 0.15), (0, 0, 0.08), CONCRETE)
    box("back", (4.2, 0.12, 2.2), (0, 0.85, 1.25), CONCRETE_DARK)
    for sx in (-1.9, 1.9):
        box("post", (0.18, 0.18, 2.5), (sx, -0.7, 1.25), METAL)
    box("roof", (4.4, 2.0, 0.12), (0, 0.05, 2.55), METAL_LIGHT)
    box("bench", (3.0, 0.45, 0.1), (0, 0.45, 0.55), WOOD)
    box("bench_back", (3.0, 0.08, 0.5), (0, 0.66, 0.85), WOOD)


def p_billboard_ruined():
    for sx in (-1.8, 1.8):
        box("post", (0.22, 0.22, 5.0), (sx, 0, 2.5), METAL)
    box("panel", (5.2, 0.16, 2.6), (0, 0.05, 4.3), CAMO, (0.06, 0, 0))
    box("stripe", (4.6, 0.05, 0.5), (0, -0.05, 4.9), ORANGE, (0.06, 0, 0))
    box("rip", (1.4, 0.18, 1.8), (1.4, 0.06, 3.2), BLACK, (0.06, 0, 0))


def p_power_pole():
    cyl("pole", 0.16, 7.0, (0, 0, 3.5), WOOD, verts=8)
    box("cross", (3.0, 0.14, 0.14), (0, 0, 6.3), WOOD)
    for sx in (-1.2, 0.0, 1.2):
        box("insulator", (0.1, 0.1, 0.22), (sx, 0, 6.45), WHITE)
    box("brace", (1.6, 0.1, 0.1), (0.7, 0, 5.9), WOOD, (0, 0, -0.5))


def p_haystack():
    cyl("base", 1.5, 1.2, (0, 0, 0.6), HAY, verts=10)
    cone("top", 1.5, 1.4, (0, 0, 1.9), HAY, verts=10)
    box("plank", (2.2, 0.5, 0.08), (0.2, 0.3, 0.04), WOOD, (0, 0, 0.4))


def p_well_house():
    cyl("ring", 1.1, 0.9, (0, 0, 0.45), CONCRETE_DARK, verts=12)
    cyl("water", 0.8, 0.05, (0, 0, 0.82), GLASS, verts=12)
    for sx in (-0.9, 0.9):
        box("post", (0.14, 0.14, 2.2), (sx, 0, 1.55), WOOD)
    gable("roof", 2.4, 1.8, 0.7, (0, 0, 2.5), RUST)
    cyl("winch", 0.12, 1.8, (0, 0, 1.7), METAL, (0, math.pi / 2, 0), verts=8)
    box("bucket", (0.3, 0.3, 0.3), (0, 0, 0.95), WOOD)


def p_barn_small():
    box("walls", (4.2, 3.0, 2.4), (0, 0, 1.2), WOOD)
    box("door", (1.6, 0.08, 1.8), (0, -1.52, 0.95), WOOD_LIGHT)
    box("door_brace", (1.6, 0.1, 0.12), (0, -1.58, 1.35), WOOD, (0, 0, 0.6))
    gable("roof", 4.8, 3.3, 1.1, (0, 0, 2.4), RUST)
    box("vent", (0.5, 0.3, 0.4), (0.9, 0.6, 3.0), METAL)


def p_silo_small():
    cyl("body", 1.3, 5.0, (0, 0, 2.5), METAL_LIGHT, verts=14)
    cone("cap", 1.35, 0.8, (0, 0, 5.4), RUST, verts=14)
    cyl("band_a", 1.32, 0.1, (0, 0, 1.4), METAL, verts=14)
    cyl("band_b", 1.32, 0.1, (0, 0, 3.6), METAL, verts=14)
    box("ladder", (0.1, 0.3, 4.6), (1.25, 0, 2.4), METAL)


def p_greenhouse():
    box("base", (5.0, 2.6, 0.2), (0, 0, 0.1), CONCRETE_DARK)
    for sx in (-2.2, 0.0, 2.2):
        box("frame", (0.08, 2.5, 1.9), (sx, 0, 1.1), METAL)
    box("glass_n", (5.0, 0.05, 1.7), (0, -1.2, 1.15), GLASS)
    box("glass_s", (5.0, 0.05, 1.7), (0, 1.2, 1.15), GLASS)
    gable("roof", 5.2, 2.8, 0.8, (0, 0, 2.0), GLASS)


def p_truck_wreck():
    box("chassis", (5.6, 2.0, 0.5), (0, 0, 0.55), RUST)
    box("cab", (1.7, 1.9, 1.5), (2.0, 0, 1.35), CAMO)
    box("hood", (1.3, 1.8, 0.7), (3.2, 0, 1.0), RUST)
    box("bed", (3.0, 1.9, 0.7), (-1.2, 0, 1.05), METAL)
    for sx in (-2.2, 0.2, 2.4):
        cyl("wheel", 0.5, 0.35, (sx, -0.95, 0.5), BLACK, (math.pi / 2, 0, 0), verts=10)
        cyl("wheel", 0.5, 0.35, (sx, 0.95, 0.5), BLACK, (math.pi / 2, 0, 0), verts=10)
    box("burn", (2.2, 1.4, 0.3), (-1.2, 0, 1.45), BLACK)


def p_apc_wreck():
    box("hull", (4.2, 2.2, 0.9), (0, 0, 0.75), CAMO)
    box("nose", (1.0, 2.0, 0.6), (2.4, 0, 0.65), CAMO, (0, 0.25, 0))
    box("turret", (1.2, 1.2, 0.5), (0.2, 0, 1.4), CAMO)
    cyl("gun", 0.07, 1.6, (1.1, 0, 1.45), METAL, (0, math.pi / 2, 0), verts=8)
    for sx in (-1.4, 1.4):
        for sy in (-1.05, 1.05):
            cyl("wheel", 0.45, 0.3, (sx, sy, 0.45), BLACK, (math.pi / 2, 0, 0), verts=10)
    box("burn", (1.4, 1.2, 0.3), (-0.9, 0, 1.25), BLACK)


def p_container_stack():
    box("a", (6.0, 2.4, 2.5), (0, 0, 1.25), BLUE)
    box("b", (6.0, 2.4, 2.5), (0.6, 0.2, 3.75), RUST)
    for i in range(6):
        box("rib", (0.08, 2.42, 2.3), (-2.4 + i * 0.95, 0, 1.25), METAL)
    box("door", (1.2, 0.1, 2.1), (2.4, -1.2, 1.15), METAL_LIGHT)


def p_tent_military():
    box("floor", (4.0, 3.0, 0.12), (0, 0, 0.06), SAND)
    for sign in (-1.0, 1.0):
        box("slope", (4.0, 2.1, 0.08), (0, sign * 0.75, 1.15), CAMO,
            (sign * math.radians(38), 0, 0))
    box("ridge", (4.0, 0.12, 0.12), (0, 0, 1.95), CAMO)
    box("entry", (0.9, 0.08, 1.2), (0, -1.55, 0.65), (0.14, 0.17, 0.10))


def p_antenna_mast():
    for sx in (-0.45, 0.45):
        for sy in (-0.45, 0.45):
            box("leg", (0.08, 0.08, 6.5), (sx, sy, 3.25), METAL,
                (sx * 0.05, -sy * 0.05, 0))
    for i in range(5):
        box("brace", (0.9, 0.06, 0.06), (0, 0, 1.0 + i * 1.2), METAL)
    box("dish", (0.9, 0.9, 0.12), (0, -0.5, 5.6), WHITE, (0.5, 0, 0))
    cyl("tip", 0.05, 1.4, (0, 0, 7.0), METAL, verts=6)


def p_jersey_barriers():
    for i in range(3):
        x = -1.6 + i * 1.6
        box("barrier%d" % i, (1.4, 0.55, 0.75), (x, 0, 0.38), CONCRETE)
        box("top%d" % i, (1.35, 0.3, 0.18), (x, 0, 0.84), CONCRETE_DARK)
        box("stripe%d" % i, (0.35, 0.56, 0.2), (x + 0.45, 0, 0.6), ORANGE)


def p_tank_traps():
    for i in range(3):
        a = i * math.pi / 3.0
        bpy.ops.mesh.primitive_cube_add(size=1, location=(
            math.cos(a) * 0.0, math.sin(a) * 0.0, 0.65))
        ob = bpy.context.object
        ob.name = "trap%d" % i
        ob.scale = (1.7, 0.18, 0.18)
        ob.rotation_euler = (0.6, 0.5, a)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        colourise(ob, METAL)


def p_fence_section():
    for i in range(4):
        box("post%d" % i, (0.12, 0.12, 1.4), (-2.1 + i * 1.4, 0, 0.7), WOOD)
    box("rail_a", (4.4, 0.08, 0.12), (0, 0, 1.1), WOOD_LIGHT)
    box("rail_b", (4.4, 0.08, 0.12), (0, 0, 0.65), WOOD_LIGHT)
    box("rail_c", (4.4, 0.08, 0.12), (0, 0, 0.25), WOOD_LIGHT)


def p_ruined_wall():
    box("wall", (5.0, 0.4, 2.6), (0, 0, 1.3), CONCRETE)
    box("hole_a", (1.1, 0.45, 1.0), (-1.2, 0, 1.8), BLACK)
    box("hole_b", (0.8, 0.45, 0.7), (1.4, 0, 1.0), BLACK)
    box("rubble", (2.2, 1.4, 0.4), (1.2, 0.9, 0.2), CONCRETE_DARK, (0, 0, 0.4))
    box("rubble_b", (1.2, 0.9, 0.3), (-1.8, 0.7, 0.15), CONCRETE_DARK, (0, 0, -0.3))


def p_water_tower_small():
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            box("leg", (0.16, 0.16, 4.2), (sx, sy, 2.1), METAL,
                (sx * 0.08, -sy * 0.08, 0))
    cyl("tank", 1.5, 2.0, (0, 0, 5.0), RUST, verts=12)
    cone("cap", 1.55, 0.7, (0, 0, 6.3), METAL, verts=12)
    box("cross_a", (2.2, 0.08, 0.08), (0, 0, 3.0), METAL)
    box("cross_b", (0.08, 2.2, 0.08), (0, 0, 3.6), METAL)


PROPS = {
    "checkpoint_booth": p_checkpoint_booth,
    "sandbag_nest": p_sandbag_nest,
    "ammo_crates": p_ammo_crates,
    "fuel_barrels": p_fuel_barrels,
    "watchtower": p_watchtower,
    "bus_stop": p_bus_stop,
    "billboard_ruined": p_billboard_ruined,
    "power_pole": p_power_pole,
    "haystack": p_haystack,
    "well_house": p_well_house,
    "barn_small": p_barn_small,
    "silo_small": p_silo_small,
    "greenhouse": p_greenhouse,
    "truck_wreck": p_truck_wreck,
    "apc_wreck": p_apc_wreck,
    "container_stack": p_container_stack,
    "tent_military": p_tent_military,
    "antenna_mast": p_antenna_mast,
    "jersey_barriers": p_jersey_barriers,
    "tank_traps": p_tank_traps,
    "fence_section": p_fence_section,
    "ruined_wall": p_ruined_wall,
    "water_tower_small": p_water_tower_small,
}


def _bake_uv_and_ao(ob):
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv_layer = me.uv_layers.active.data
    col_layer = me.color_attributes["Col"] if "Col" in me.color_attributes else me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    zs = [v.co.z for v in me.vertices] if me.vertices else [0.0, 1.0]
    z_min = min(zs)
    z_span = max(0.20, max(zs) - z_min)
    for poly in me.polygons:
        n = poly.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        sun = max(0.0, n.x * 0.35 - n.y * 0.40 + n.z * 0.85)
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            if az >= ax and az >= ay:
                u, v = co.x * 0.45, co.y * 0.45
            elif ax >= ay:
                u, v = co.y * 0.45, co.z * 0.45
            else:
                u, v = co.x * 0.45, co.z * 0.45
            uv_layer[li].uv = (u, v)
            h_t = max(0.0, min(1.0, (co.z - z_min) / z_span))
            ao = (0.64 + 0.36 * pow(h_t, 0.65)) * (0.86 + 0.24 * sun)
            c = col_layer.data[li].color
            col_layer.data[li].color = (
                min(1.0, c[0] * ao),
                min(1.0, c[1] * ao),
                min(1.0, c[2] * ao),
                1.0,
            )


def build_one(name, only=None):
    if only and name != only:
        return
    reset()
    global MAT
    MAT = make_material()
    PROPS[name]()
    parts = [o for o in bpy.data.objects if o.type == 'MESH']
    if not parts:
        print("PROP_FAIL no parts", name)
        return
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    _bake_uv_and_ao(joined)
    os.makedirs(ROOT, exist_ok=True)
    out = os.path.join(ROOT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB',
                              use_selection=True, export_apply=True,
                              export_texcoords=True, export_normals=True,
                              export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in joined.data.polygons)
    print("PROP_OK", name, "verts=", len(joined.data.vertices),
          "tris=", tris, "->", out)


def main():
    argv = sys.argv
    only = None
    if "--" in argv:
        extra = argv[argv.index("--") + 1:]
        if "--only" in extra:
            only = extra[extra.index("--only") + 1]
    for name in PROPS:
        build_one(name, only)


main()
