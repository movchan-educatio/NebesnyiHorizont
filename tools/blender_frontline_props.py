"""Generate 20 frontline set-dressing props for the combat maps.

Everything is vertex-coloured and shares one material, so each prop is a single
draw call when instanced through a MultiMesh.  Run:

  blender -b --factory-startup --python tools/blender_frontline_props.py
"""
import math
import os

import bpy
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "Assets", "frontline", "props")
os.makedirs(OUT, exist_ok=True)


class MB:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []
        self.c = []

    def vert(self, p, col):
        self.v.append(tuple(p))
        self.c.append(tuple(col) + (1.0,))
        return len(self.v) - 1

    def quad(self, a, b, c, d, col):
        ia = self.vert(a, col); ib = self.vert(b, col)
        ic = self.vert(c, col); idd = self.vert(d, col)
        self.f.append((ia, ib, ic, idd))

    def box(self, centre, size, col, rot=0.0):
        cx, cy, cz = centre
        sx, sy, sz = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
        ca, sa = math.cos(rot), math.sin(rot)
        def tr(x, y, z):
            return (cx + x * ca - y * sa, cy + x * sa + y * ca, cz + z)
        p = [tr(-sx, -sy, -sz), tr(sx, -sy, -sz), tr(sx, sy, -sz), tr(-sx, sy, -sz),
             tr(-sx, -sy, sz), tr(sx, -sy, sz), tr(sx, sy, sz), tr(-sx, sy, sz)]
        for q in [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
                  (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]:
            self.quad(p[q[0]], p[q[1]], p[q[2]], p[q[3]], col)

    def cyl(self, centre, radius, height, sides, col, axis='Z', rot=0.0):
        cx, cy, cz = centre
        h = height * 0.5
        rings = []
        for end in (-h, h):
            ring = []
            for i in range(sides):
                a = TAU * i / sides
                x = math.cos(a) * radius
                y = math.sin(a) * radius
                if axis == 'Z':
                    p = (cx + x, cy + y, cz + end)
                elif axis == 'X':
                    p = (cx + end, cy + x, cz + y)
                else:
                    p = (cx + x, cy + end, cz + y)
                ring.append(self.vert(p, col))
            rings.append(ring)
        for i in range(sides):
            j = (i + 1) % sides
            self.f.append((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
        # End caps.
        c0 = self.vert((cx, cy, cz - h), col)
        c1 = self.vert((cx, cy, cz + h), col)
        for i in range(sides):
            j = (i + 1) % sides
            self.f.append((c0, rings[0][j], rings[0][i]))
            self.f.append((c1, rings[1][i], rings[1][j]))

    def sphere(self, centre, radius, col, seg=6, rings=3):
        cx, cy, cz = centre
        grid = []
        for r in range(rings + 1):
            phi = math.pi * r / rings
            row = []
            for s in range(seg):
                th = TAU * s / seg
                x = math.sin(phi) * math.cos(th) * radius
                y = math.sin(phi) * math.sin(th) * radius
                z = math.cos(phi) * radius
                row.append(self.vert((cx + x, cy + y, cz + z), col))
            grid.append(row)
        for r in range(rings):
            for s in range(seg):
                s2 = (s + 1) % seg
                self.f.append((grid[r][s], grid[r][s2], grid[r + 1][s2], grid[r + 1][s]))

    def build(self, material, collection):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.v, [], self.f)
        mesh.update()
        col = mesh.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                vi = mesh.loops[li].vertex_index
                col.data[li].color = self.c[vi]
        mesh.materials.append(material)
        mesh.validate()
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        return obj


TAU = math.pi * 2.0

WOOD = (0.30, 0.22, 0.13)
WOOD_D = (0.20, 0.145, 0.085)
METAL = (0.30, 0.32, 0.29)
RUST = (0.34, 0.19, 0.10)
CONCRETE = (0.46, 0.44, 0.39)
SAND = (0.52, 0.45, 0.30)
CANVAS = (0.22, 0.26, 0.16)
TIRE = (0.05, 0.05, 0.05)
GLASS = (0.10, 0.14, 0.16)
OLIVE = (0.18, 0.22, 0.12)


def prop_crate(mb):
    mb.box((0, 0, 0.45), (0.9, 0.9, 0.9), WOOD)
    for z in (0.12, 0.78):
        mb.box((0, 0, z), (0.94, 0.10, 0.10), WOOD_D)
        mb.box((0, 0, z), (0.10, 0.94, 0.10), WOOD_D)


def prop_barrel(mb):
    mb.cyl((0, 0, 0.45), 0.30, 0.90, 10, METAL)
    for z in (0.16, 0.45, 0.74):
        mb.cyl((0, 0, z), 0.315, 0.05, 10, RUST)


def prop_oil_drum(mb):
    mb.cyl((0, 0, 0.44), 0.33, 0.88, 10, RUST)
    mb.cyl((0.13, 0.05, 0.30), 0.33, 0.06, 10, (0.22, 0.12, 0.07))
    mb.cyl((0, 0, 0.88), 0.28, 0.04, 10, METAL)


def prop_sandbags(mb):
    for row in range(3):
        for i in range(3 - row):
            x = (i - (2 - row) * 0.5) * 0.52
            mb.box((x, 0, 0.18 + row * 0.30), (0.55, 0.38, 0.30), SAND)


def prop_barrier(mb):
    mb.box((0, 0, 0.22), (2.0, 0.55, 0.44), CONCRETE)
    mb.box((0, 0, 0.62), (1.9, 0.40, 0.36), CONCRETE)
    for x in (-0.7, 0.7):
        mb.box((x, 0, 0.94), (0.22, 0.22, 0.30), (0.30, 0.29, 0.26))


def prop_pipe(mb):
    mb.cyl((0, 0.55, 0.55), 0.55, 2.4, 12, CONCRETE, axis='X')
    mb.cyl((0, 0.55, 0.55), 0.40, 2.42, 12, (0.10, 0.10, 0.09), axis='X')


def prop_pallet(mb):
    for i in range(5):
        mb.box((0, -0.55 + i * 0.27, 0.16), (1.2, 0.20, 0.06), WOOD)
    for x in (-0.48, 0.0, 0.48):
        mb.box((x, 0, 0.07), (0.12, 1.25, 0.10), WOOD_D)


def prop_tires(mb):
    for i in range(4):
        mb.cyl((0, 0, 0.16 + i * 0.30), 0.42, 0.26, 10, TIRE)
        mb.cyl((0, 0, 0.16 + i * 0.30), 0.22, 0.27, 10, (0.12, 0.12, 0.11))


def prop_ammo(mb):
    mb.box((0, 0, 0.24), (0.85, 0.45, 0.48), OLIVE)
    mb.box((0, 0, 0.50), (0.88, 0.48, 0.06), (0.12, 0.15, 0.08))
    for x in (-0.28, 0.28):
        mb.box((x, 0.25, 0.32), (0.12, 0.05, 0.12), METAL)


def prop_camo_net(mb):
    for x in (-1.6, 1.6):
        for y in (-1.2, 1.2):
            mb.cyl((x, y, 1.1), 0.05, 2.2, 6, WOOD_D)
    mb.box((0, 0, 2.05), (3.4, 2.6, 0.08), CANVAS)
    mb.box((0, 0, 1.65), (3.0, 2.2, 0.06), (0.16, 0.19, 0.11))


def prop_hay(mb):
    mb.cyl((0, 0, 0.55), 0.62, 1.35, 10, (0.55, 0.46, 0.22), axis='X')


def prop_car_wreck(mb):
    mb.box((0, 0, 0.52), (3.7, 1.6, 0.65), RUST)
    mb.box((-0.2, 0, 1.03), (1.8, 1.45, 0.55), (0.26, 0.14, 0.08))
    for x in (-1.2, 1.2):
        for y in (-0.8, 0.8):
            mb.cyl((x, y, 0.32), 0.32, 0.22, 8, TIRE, axis='Y')
    mb.box((1.65, 0, 0.42), (0.7, 1.5, 0.35), (0.20, 0.12, 0.07))


def prop_apc(mb):
    mb.box((0, 0, 0.85), (4.6, 2.5, 1.1), OLIVE)
    mb.box((-0.9, 0, 1.75), (2.0, 1.7, 0.7), (0.15, 0.18, 0.10))
    mb.cyl((-0.9, 0, 2.2), 0.12, 2.2, 8, (0.10, 0.12, 0.08), axis='X')
    for z in (0.35, 1.35):
        for y in (-1.35, 1.35):
            mb.box((0, y, z), (4.0, 0.30, 0.5), TIRE)
    mb.box((2.2, 0, 1.0), (0.25, 2.2, 0.7), (0.12, 0.14, 0.09))


def prop_fence(mb):
    for x in (-2.2, 0.0, 2.2):
        mb.box((x, 0, 0.8), (0.12, 0.12, 1.6), WOOD_D)
    for z in (0.55, 1.15, 1.45):
        mb.box((0, 0, z), (4.5, 0.05, 0.05), (0.42, 0.42, 0.40))


def prop_antenna(mb):
    mb.cyl((0, 0, 2.4), 0.06, 4.8, 6, METAL)
    for z in (2.2, 3.3, 4.2):
        mb.box((0, 0, z), (1.0, 0.06, 0.06), METAL)
    mb.box((0.45, 0, 4.6), (0.25, 0.25, 0.25), (0.10, 0.10, 0.10))
    for x, y in ((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)):
        mb.box((x, y, 0.05), (0.18, 0.18, 0.10), CONCRETE)


def prop_generator(mb):
    mb.box((0, 0, 0.55), (1.5, 0.9, 0.9), METAL)
    mb.box((0.2, 0, 1.05), (0.7, 0.6, 0.12), (0.16, 0.16, 0.14))
    mb.cyl((-0.5, 0.35, 1.15), 0.08, 0.9, 6, RUST)
    for x in (-0.5, 0.5):
        mb.cyl((x, -0.5, 0.22), 0.24, 0.15, 8, TIRE, axis='Y')


def prop_tent(mb):
    mb.cyl((0, 0, 0.9), 1.35, 3.2, 4, CANVAS, axis='X')
    mb.box((1.62, 0, 0.55), (0.06, 0.9, 1.0), (0.08, 0.09, 0.06))
    for x in (-1.7, 1.7):
        mb.cyl((x, 0, 1.7), 0.04, 0.9, 5, WOOD_D)


def prop_logs(mb):
    for i in range(3):
        for j in range(3 - i):
            x = (j - (2 - i) * 0.5) * 0.45
            mb.cyl((x, 0, 0.22 + i * 0.38), 0.21, 2.4, 8, WOOD, axis='Y')


def prop_sign(mb):
    mb.cyl((0, 0, 1.2), 0.05, 2.4, 6, METAL)
    mb.box((0, 0, 2.15), (0.9, 0.08, 0.6), (0.62, 0.15, 0.08))
    mb.box((0, 0.05, 2.15), (0.5, 0.04, 0.12), (0.85, 0.85, 0.80))


def prop_fuel_tank(mb):
    mb.cyl((0, 0, 0.85), 0.55, 2.6, 12, METAL, axis='X')
    for x in (-0.9, 0.9):
        mb.box((x, 0, 0.35), (0.25, 1.0, 0.7), CONCRETE)
    mb.cyl((-0.3, 0.0, 1.45), 0.08, 0.6, 6, RUST)
    mb.cyl((0.3, 0.0, 1.45), 0.08, 0.6, 6, METAL)


PROPS = [
    ("prop_crate", prop_crate), ("prop_barrel", prop_barrel),
    ("prop_oil_drum", prop_oil_drum), ("prop_sandbags", prop_sandbags),
    ("prop_barrier", prop_barrier), ("prop_pipe", prop_pipe),
    ("prop_pallet", prop_pallet), ("prop_tires", prop_tires),
    ("prop_ammo", prop_ammo), ("prop_camo_net", prop_camo_net),
    ("prop_hay", prop_hay), ("prop_car_wreck", prop_car_wreck),
    ("prop_apc", prop_apc), ("prop_fence", prop_fence),
    ("prop_antenna", prop_antenna), ("prop_generator", prop_generator),
    ("prop_tent", prop_tent), ("prop_logs", prop_logs),
    ("prop_sign", prop_sign), ("prop_fuel_tank", prop_fuel_tank),
]


def make_material():
    mat = bpy.data.materials.new("prop_vcol")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.15
    return mat


def main():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    collection = bpy.context.collection
    mat = make_material()
    roots = []
    for name, func in PROPS:
        mb = MB(name)
        func(mb)
        obj = mb.build(mat, collection)
        root = bpy.data.objects.new(name + "_root", None)
        root.empty_display_type = 'PLAIN_AXES'
        collection.objects.link(root)
        obj.parent = root
        roots.append(root)
        print("[Props]", name, "faces", len(obj.data.polygons))
    select = []
    for root in roots:
        select.append(root)
        select.extend(root.children)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in select:
        obj.select_set(True)
    path = os.path.join(OUT, "props_library.glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=True,
        export_apply=True, export_cameras=False, export_lights=False,
        export_materials='EXPORT', export_animations=False,
        export_texcoords=False, export_normals=True,
        export_vertex_color='ACTIVE', export_all_vertex_colors=True)
    print("[Props] exported", path, os.path.getsize(path))


if __name__ == "__main__":
    main()
