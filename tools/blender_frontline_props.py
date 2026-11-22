"""Generate 20 high-detail frontline set-dressing props for the combat & freestyle maps.

Every prop is sculpted with multi-part architectural/mechanical detail, chamfered profiles,
box-projected UVs, and vertical AO + edge-highlight vertex colors, sharing one material so
each prop remains a single draw call when instanced through a MultiMesh.

Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender_frontline_props.py
"""
import math
import os
import bpy
from mathutils import Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "Assets", "frontline", "props")
os.makedirs(OUT, exist_ok=True)

TAU = math.pi * 2.0


def _shade(col, z, n_z=0.5, ao_h=1.2):
    """Apply vertical ambient occlusion and top directional sun highlight to vertex colors."""
    ao = 0.72 + 0.28 * min(max(z / max(ao_h, 0.2), 0.0), 1.0)
    top = 1.08 if n_z > 0.55 else (0.86 if n_z < -0.55 else 1.0)
    f = ao * top
    return (
        min(max(col[0] * f, 0.02), 1.0),
        min(max(col[1] * f, 0.02), 1.0),
        min(max(col[2] * f, 0.02), 1.0),
    )


class MB:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []
        self.c = []
        self.uv = []

    def vert(self, p, col, n_z=0.3):
        self.v.append(tuple(p))
        sc = _shade(col, p[2], n_z)
        self.c.append(sc + (1.0,))
        return len(self.v) - 1

    def quad(self, a, b, c, d, col, n_z=0.3):
        ia = self.vert(a, col, n_z)
        ib = self.vert(b, col, n_z)
        ic = self.vert(c, col, n_z)
        idd = self.vert(d, col, n_z)
        self.f.append((ia, ib, ic, idd))

    def box(self, centre, size, col, rot=0.0, pitch=0.0):
        cx, cy, cz = centre
        sx, sy, sz = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
        ca, sa = math.cos(rot), math.sin(rot)
        cp, sp = math.cos(pitch), math.sin(pitch)

        def tr(x, y, z):
            # pitch around Y, then yaw around Z
            xp = x * cp + z * sp
            zp = -x * sp + z * cp
            return (cx + xp * ca - y * sa, cy + xp * sa + y * ca, cz + zp)

        p = [
            tr(-sx, -sy, -sz), tr(sx, -sy, -sz), tr(sx, sy, -sz), tr(-sx, sy, -sz),
            tr(-sx, -sy, sz), tr(sx, -sy, sz), tr(sx, sy, sz), tr(-sx, sy, sz),
        ]
        faces_spec = [
            ((0, 1, 2, 3), -0.9),
            ((4, 7, 6, 5), 0.9),
            ((0, 4, 5, 1), 0.1),
            ((1, 5, 6, 2), 0.2),
            ((2, 6, 7, 3), 0.1),
            ((3, 7, 4, 0), 0.0),
        ]
        for q, nz in faces_spec:
            self.quad(p[q[0]], p[q[1]], p[q[2]], p[q[3]], col, nz)

    def tapered_box(self, centre, size_bot, size_top, height, col, rot=0.0):
        cx, cy, cz = centre
        bx, by = size_bot[0] * 0.5, size_bot[1] * 0.5
        tx, ty = size_top[0] * 0.5, size_top[1] * 0.5
        hz = height * 0.5
        ca, sa = math.cos(rot), math.sin(rot)

        def tr(x, y, z):
            return (cx + x * ca - y * sa, cy + x * sa + y * ca, cz + z)

        p = [
            tr(-bx, -by, -hz), tr(bx, -by, -hz), tr(bx, by, -hz), tr(-bx, by, -hz),
            tr(-tx, -ty, hz), tr(tx, -ty, hz), tr(tx, ty, hz), tr(-tx, ty, hz),
        ]
        for q, nz in [
            ((0, 1, 2, 3), -0.9),
            ((4, 7, 6, 5), 0.9),
            ((0, 4, 5, 1), 0.25),
            ((1, 5, 6, 2), 0.25),
            ((2, 6, 7, 3), 0.25),
            ((3, 7, 4, 0), 0.25),
        ]:
            self.quad(p[q[0]], p[q[1]], p[q[2]], p[q[3]], col, nz)

    def cyl(self, centre, radius, height, sides, col, axis='Z', rot=0.0, r2=None):
        cx, cy, cz = centre
        h = height * 0.5
        rad2 = radius if r2 is None else r2
        ca, sa = math.cos(rot), math.sin(rot)
        rings = []
        for idx_e, end in enumerate((-h, h)):
            rr = radius if idx_e == 0 else rad2
            ring = []
            for i in range(sides):
                a = TAU * i / sides
                x = math.cos(a) * rr
                y = math.sin(a) * rr
                if axis == 'Z':
                    lx, ly, lz = x, y, end
                    nz = 0.2
                elif axis == 'X':
                    lx, ly, lz = end, x, y
                    nz = y / max(rr, 0.001)
                else:
                    lx, ly, lz = x, end, y
                    nz = y / max(rr, 0.001)
                px = cx + lx * ca - ly * sa
                py = cy + lx * sa + ly * ca
                pz = cz + lz
                ring.append(self.vert((px, py, pz), col, nz))
            rings.append(ring)
        for i in range(sides):
            j = (i + 1) % sides
            self.f.append((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
        if axis == 'Z':
            c0_p, c1_p = (cx, cy, cz - h), (cx, cy, cz + h)
        elif axis == 'X':
            c0_p = (cx - h * ca, cy - h * sa, cz)
            c1_p = (cx + h * ca, cy + h * sa, cz)
        else:
            c0_p = (cx + h * sa, cy - h * ca, cz)
            c1_p = (cx - h * sa, cy + h * ca, cz)
        c0 = self.vert(c0_p, col, -0.7 if axis == 'Z' else 0.2)
        c1 = self.vert(c1_p, col, 0.85 if axis == 'Z' else 0.2)
        for i in range(sides):
            j = (i + 1) % sides
            self.f.append((c0, rings[0][j], rings[0][i]))
            self.f.append((c1, rings[1][i], rings[1][j]))

    def build(self, material, collection):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.v, [], self.f)
        mesh.update()
        col = mesh.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            n = poly.normal
            for li in poly.loop_indices:
                vi = mesh.loops[li].vertex_index
                col.data[li].color = self.c[vi]
                co = mesh.vertices[vi].co
                if abs(n.z) > 0.65:
                    uv_layer.data[li].uv = (co.x * 0.5, co.y * 0.5)
                elif abs(n.x) > abs(n.y):
                    uv_layer.data[li].uv = (co.y * 0.5, co.z * 0.5)
                else:
                    uv_layer.data[li].uv = (co.x * 0.5, co.z * 0.5)
        mesh.materials.append(material)
        mesh.validate()
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        return obj


WOOD = (0.34, 0.25, 0.15)
WOOD_D = (0.22, 0.16, 0.095)
WOOD_L = (0.44, 0.33, 0.20)
METAL = (0.32, 0.34, 0.33)
METAL_D = (0.18, 0.20, 0.20)
RUST = (0.38, 0.21, 0.11)
RUST_D = (0.26, 0.14, 0.07)
CONCRETE = (0.50, 0.48, 0.43)
CONCRETE_D = (0.34, 0.33, 0.30)
SAND = (0.54, 0.47, 0.32)
SAND_D = (0.42, 0.36, 0.24)
CANVAS = (0.24, 0.29, 0.18)
CANVAS_D = (0.17, 0.21, 0.12)
TIRE = (0.08, 0.08, 0.085)
GLASS = (0.12, 0.17, 0.20)
OLIVE = (0.21, 0.26, 0.15)
OLIVE_D = (0.14, 0.18, 0.10)
BRASS = (0.68, 0.54, 0.20)
HAZARD_Y = (0.78, 0.60, 0.10)


def prop_crate(mb):
    # Detailed military ordnance crate with skids, recessed panels, corner brackets, lid battens & handles
    for sx in (-0.34, 0.34):
        mb.box((sx, 0, 0.04), (0.12, 0.94, 0.08), WOOD_D)
    mb.box((0, 0, 0.46), (0.86, 0.86, 0.76), WOOD)
    # Recessed inner panels & plank slats
    for i in range(4):
        z = 0.18 + i * 0.18
        mb.box((0, 0, z), (0.91, 0.82, 0.04), WOOD_L)
        mb.box((0, 0, z), (0.82, 0.91, 0.04), WOOD_L)
    # Vertical corner cleats & diagonal braces
    for sx in (-0.42, 0.42):
        for sy in (-0.42, 0.42):
            mb.box((sx, sy, 0.46), (0.09, 0.09, 0.78), WOOD_D)
    for sy in (-0.44, 0.44):
        mb.box((0, sy, 0.46), (0.76, 0.04, 0.09), WOOD_D, pitch=0.55)
    # Overhanging lid with steel corner brackets & stencil plate
    mb.box((0, 0, 0.87), (0.94, 0.94, 0.08), WOOD_D)
    for sx in (-0.30, 0.0, 0.30):
        mb.box((sx, 0, 0.92), (0.10, 0.95, 0.04), WOOD_L)
    for sx in (-0.44, 0.44):
        for sy in (-0.44, 0.44):
            mb.box((sx, sy, 0.87), (0.12, 0.12, 0.10), METAL_D)
    for sx in (-0.46, 0.46):
        mb.box((sx, 0, 0.56), (0.05, 0.24, 0.06), METAL_D)
    mb.box((0, -0.46, 0.54), (0.36, 0.02, 0.16), METAL_D)


def prop_barrel(mb):
    # 200L military steel fuel drum with 18-sided smooth body, pressed rolling hoops, chime rim & bungs
    mb.cyl((0, 0, 0.46), 0.295, 0.88, 18, (0.20, 0.27, 0.33))
    for z in (0.03, 0.89):
        mb.cyl((0, 0, z), 0.312, 0.045, 18, METAL_D)
    for z in (0.30, 0.62):
        mb.cyl((0, 0, z), 0.316, 0.055, 18, METAL)
    mb.cyl((0, 0, 0.905), 0.27, 0.02, 18, METAL_D)
    mb.cyl((0.14, 0.06, 0.92), 0.04, 0.04, 8, BRASS)
    mb.cyl((-0.12, -0.08, 0.92), 0.025, 0.035, 8, METAL)


def prop_oil_drum(mb):
    # Clustered pair of weathered fuel drums (one upright, one slightly tilted on timber chocks)
    mb.box((0, 0, 0.03), (0.85, 0.75, 0.06), WOOD_D)
    mb.cyl((-0.14, 0.0, 0.48), 0.30, 0.88, 18, RUST)
    for z in (0.06, 0.32, 0.64, 0.90):
        mb.cyl((-0.14, 0.0, z), 0.318, 0.048, 18, RUST_D)
    mb.cyl((-0.14, 0.0, 0.92), 0.26, 0.02, 18, METAL_D)
    mb.cyl((-0.02, 0.08, 0.94), 0.038, 0.04, 8, BRASS)
    # Small jerrycan leaning against the drum
    mb.box((0.26, 0.04, 0.24), (0.18, 0.34, 0.44), OLIVE)
    mb.box((0.26, 0.04, 0.48), (0.12, 0.22, 0.06), OLIVE_D)
    mb.cyl((0.26, 0.14, 0.49), 0.03, 0.06, 8, RUST)


def prop_sandbags(mb):
    # Curved, pillowed multi-course sandbag breastwork with tied ears & timber firing step
    mb.box((0, 0.22, 0.04), (1.55, 0.32, 0.08), WOOD_D)
    for row in range(4):
        count = 4 - (row % 2)
        for i in range(count):
            x = (i - (count - 1) * 0.5) * 0.44
            y = -0.05 + abs(x) * 0.14
            z = 0.11 + row * 0.20
            yaw = -x * 0.24 + (0.04 if (i + row) % 2 == 0 else -0.04)
            col = SAND if (i + row) % 2 == 0 else SAND_D
            mb.tapered_box((x, y, z), (0.46, 0.34), (0.38, 0.26), 0.21, col, rot=yaw)
            # Pinched tied bag neck & seam band
            mb.box((x + 0.22 * math.cos(yaw), y + 0.22 * math.sin(yaw), z), (0.09, 0.14, 0.10), SAND_D, rot=yaw)


def prop_barrier(mb):
    # Authentic F-shape concrete Jersey barrier with wide foot, tapered web, forklift cutouts & lifting loops
    mb.tapered_box((0, 0, 0.14), (2.06, 0.62), (2.04, 0.42), 0.28, CONCRETE_D)
    mb.tapered_box((0, 0, 0.56), (2.02, 0.42), (1.96, 0.22), 0.58, CONCRETE)
    mb.box((0, 0, 0.90), (1.94, 0.22, 0.12), CONCRETE)
    # Forklift drainage cutouts at base
    for x in (-0.58, 0.58):
        mb.box((x, 0, 0.07), (0.36, 0.64, 0.12), METAL_D)
    # Rebar lifting loops on top & hazard chevron end caps
    for x in (-0.65, 0.65):
        mb.cyl((x, 0, 0.98), 0.04, 0.14, 8, RUST, axis='X')
    for x in (-0.82, 0.82):
        mb.box((x, 0, 0.62), (0.22, 0.34, 0.32), HAZARD_Y)


def prop_pipe(mb):
    # Twin stacked reinforced concrete/steel pipeline culvert sections on timber cradle chocks
    for x in (-0.75, 0.75):
        mb.box((x, 0.55, 0.08), (0.24, 1.35, 0.16), WOOD_D)
        for sy in (-0.54, 0.54):
            mb.tapered_box((x, 0.55 + sy, 0.22), (0.24, 0.22), (0.24, 0.08), 0.18, WOOD)
    mb.cyl((0, 0.55, 0.58), 0.52, 2.45, 20, CONCRETE, axis='X')
    # Flared bell collar & outer reinforcement rings
    for x in (-1.14, 1.14):
        mb.cyl((x, 0.55, 0.58), 0.57, 0.18, 20, CONCRETE_D, axis='X')
    for x in (-0.55, 0.0, 0.55):
        mb.cyl((x, 0.55, 0.58), 0.54, 0.08, 20, RUST, axis='X')
    # Dark hollow interior bore core
    mb.cyl((0, 0.55, 0.58), 0.41, 2.47, 16, (0.07, 0.07, 0.07), axis='X')


def prop_pallet(mb):
    # Detailed EUR/EPAL pallet with 9 spacer blocks, 3 bottom deckboards, 3 stringers, 7 top deckboards & strapped cargo box
    for x in (-0.52, 0.0, 0.52):
        mb.box((x, 0, 0.015), (0.14, 1.20, 0.03), WOOD_D)
        for y in (-0.52, 0.0, 0.52):
            mb.box((x, y, 0.07), (0.14, 0.14, 0.08), WOOD_D)
    for y in (-0.52, 0.0, 0.52):
        mb.box((0, y, 0.125), (1.20, 0.14, 0.03), WOOD)
    for i in range(7):
        x = -0.51 + i * 0.17
        mb.box((x, 0, 0.155), (0.13, 1.22, 0.03), WOOD_L if i % 2 == 0 else WOOD)


def prop_tires(mb):
    # Heavy military truck tire stack with beveled treads, deep sidewall rims, wheel hub & leaning fifth tire
    for i in range(3):
        z = 0.15 + i * 0.29
        ox = 0.04 if i == 1 else (-0.03 if i == 2 else 0.0)
        mb.cyl((ox, 0, z), 0.44, 0.27, 18, TIRE)
        mb.cyl((ox, 0, z), 0.455, 0.18, 18, (0.05, 0.05, 0.055))
        mb.cyl((ox, 0, z), 0.25, 0.285, 14, METAL_D)
        mb.cyl((ox, 0, z), 0.12, 0.30, 10, RUST)
    # Leaning tire beside the stack
    mb.cyl((0.46, 0.12, 0.38), 0.42, 0.26, 18, TIRE, axis='X', rot=0.35)
    mb.cyl((0.46, 0.12, 0.38), 0.23, 0.275, 14, METAL_D, axis='X', rot=0.35)


def prop_ammo(mb):
    # Stacked military ammo crates + M2A1 steel ammo cans + cylindrical ordnance shipping tubes on pallet
    mb.box((0, 0, 0.04), (1.02, 0.64, 0.08), WOOD_D)
    mb.box((-0.06, 0, 0.25), (0.86, 0.46, 0.34), OLIVE)
    mb.box((-0.06, 0, 0.44), (0.90, 0.50, 0.06), OLIVE_D)
    for x in (-0.34, 0.22):
        mb.box((x, -0.24, 0.30), (0.08, 0.04, 0.16), METAL)
        mb.box((x, 0.24, 0.30), (0.08, 0.04, 0.16), METAL)
    # Top M2A1 ammo cans & brass/olive mortar tube
    mb.box((-0.22, -0.04, 0.58), (0.34, 0.18, 0.22), OLIVE_D, rot=0.12)
    mb.box((0.16, 0.06, 0.58), (0.34, 0.18, 0.22), OLIVE, rot=-0.08)
    mb.cyl((0.02, -0.14, 0.55), 0.085, 0.78, 12, RUST, axis='X')
    for x in (-0.32, 0.36):
        mb.cyl((x, -0.14, 0.55), 0.095, 0.06, 12, BRASS, axis='X')


def prop_camo_net(mb):
    # Tactical camo net shelter over angled telescopic poles with pitched canopy, side skirts & ammo/radio crates inside
    for x in (-1.55, 1.55):
        for y in (-1.15, 1.15):
            mb.cyl((x, y, 1.05), 0.055, 2.1, 8, METAL_D)
            mb.box((x * 1.12, y * 1.12, 0.08), (0.16, 0.16, 0.16), SAND_D)
    # Multi-faceted pitched camo canopy & draped side skirts
    mb.tapered_box((0, 0, 1.98), (3.45, 2.55), (2.20, 1.40), 0.36, CANVAS)
    for sy in (-1.22, 1.22):
        mb.box((0, sy, 1.52), (3.30, 0.10, 0.65), CANVAS_D, pitch=0.12)
    for sx in (-1.65, 1.65):
        mb.box((sx, 0, 1.52), (0.10, 2.35, 0.65), CANVAS_D)
    # Tactical table & crate underneath
    mb.box((-0.4, 0.0, 0.35), (1.1, 0.7, 0.7), OLIVE)
    mb.box((0.65, -0.2, 0.25), (0.65, 0.55, 0.5), WOOD)


def prop_hay(mb):
    # Detailed cylindrical round hay bale with beveled ends, 3 twine bindings & loose base straw bolster
    mb.tapered_box((0, 0, 0.08), (1.42, 1.26), (1.28, 1.02), 0.16, (0.48, 0.39, 0.18))
    mb.cyl((0, 0, 0.64), 0.62, 1.32, 18, (0.58, 0.48, 0.23), axis='X')
    mb.cyl((0, 0, 0.64), 0.42, 1.36, 14, (0.46, 0.37, 0.17), axis='X')
    for x in (-0.42, 0.0, 0.42):
        mb.cyl((x, 0, 0.64), 0.635, 0.04, 18, WOOD_D, axis='X')


def prop_car_wreck(mb):
    # Sculpted burnt-out offroad pickup/SUV wreck with engine bay, A/B/C pillars, wheel wells, bumpers & 4 wheels
    # Lower chassis frame & rocker panels
    mb.box((0, 0, 0.36), (3.75, 1.52, 0.24), METAL_D)
    # Front hood (sloped) & exposed engine block
    mb.tapered_box((1.22, 0, 0.66), (1.30, 1.58), (1.22, 1.44), 0.42, RUST)
    mb.box((1.35, 0, 0.76), (0.65, 0.72, 0.32), METAL_D)
    # Main lower body tub & rear cargo bed
    mb.box((-0.35, 0, 0.64), (2.35, 1.64, 0.48), RUST_D)
    # Cabin pillars & roof (hollowed out windows instead of solid cube)
    mb.tapered_box((-0.05, 0, 1.36), (1.65, 1.46), (1.42, 1.32), 0.12, RUST)
    for px, py in ((0.68, -0.68), (0.68, 0.68), (-0.10, -0.68), (-0.10, 0.68), (-0.78, -0.68), (-0.78, 0.68)):
        mb.box((px, py, 1.10), (0.14, 0.12, 0.48), RUST_D)
    # Front & rear heavy bumpers + grille
    mb.box((1.92, 0, 0.42), (0.18, 1.66, 0.24), METAL_D)
    mb.box((1.88, 0, 0.64), (0.08, 1.24, 0.28), (0.10, 0.10, 0.10))
    mb.box((-1.92, 0, 0.44), (0.18, 1.64, 0.24), METAL_D)
    # 4 wheels with tires & steel hubs
    for x in (-1.18, 1.18):
        for y in (-0.78, 0.78):
            mb.cyl((x, y, 0.34), 0.34, 0.24, 14, TIRE, axis='Y')
            mb.cyl((x, y, 0.34), 0.19, 0.26, 10, RUST, axis='Y')


def prop_apc(mb):
    # Sculpted 8x8 BTR-80 style armored personnel carrier hull with sloped upper/lower glacis, side hatches, turret & 8 wheels
    # Lower hull boat-shaped belly
    mb.tapered_box((0, 0, 0.56), (4.30, 2.10), (4.85, 2.54), 0.48, OLIVE_D)
    # Upper hull with sloped armor sides
    mb.tapered_box((-0.08, 0, 1.12), (4.85, 2.54), (4.15, 2.02), 0.66, OLIVE)
    # Pointed armored bow nose & wave deflector
    mb.tapered_box((2.42, 0, 0.88), (0.75, 2.15), (0.30, 1.55), 0.46, OLIVE)
    mb.box((2.58, 0, 1.18), (0.12, 1.65, 0.26), OLIVE_D, pitch=-0.35)
    # Conical BPU-1 turret + 14.5mm KPVT & 7.62mm coaxial barrels
    mb.cyl((0.45, 0, 1.68), 0.78, 0.48, 14, OLIVE_D, r2=0.56)
    mb.box((0.95, 0, 1.72), (0.45, 0.42, 0.28), METAL_D)
    mb.cyl((1.75, 0.04, 1.76), 0.055, 1.55, 8, METAL_D, axis='X')
    mb.cyl((1.45, -0.10, 1.74), 0.035, 0.95, 8, METAL_D, axis='X')
    # Rear engine deck louvers & stowage boxes
    mb.box((-1.55, 0, 1.48), (1.10, 1.65, 0.10), OLIVE_D)
    for sy in (-1.22, 1.22):
        mb.box((-0.6, sy, 1.08), (1.45, 0.16, 0.36), OLIVE_D)
    # 8 armored wheels (4 per side) with hubcaps
    for x in (-1.58, -0.56, 0.56, 1.58):
        for y in (-1.18, 1.18):
            mb.cyl((x, y, 0.44), 0.43, 0.30, 14, TIRE, axis='Y')
            mb.cyl((x, y, 0.44), 0.24, 0.32, 10, OLIVE_D, axis='Y')


def prop_fence(mb):
    # Industrial/military perimeter fence section with concrete posts, corrugated panel inserts, rails & barbed wire arms
    for x in (-2.2, 0.0, 2.2):
        mb.box((x, 0, 0.16), (0.28, 0.28, 0.32), CONCRETE_D)
        mb.box((x, 0, 0.88), (0.18, 0.18, 1.65), CONCRETE)
        mb.box((x, 0.08, 1.82), (0.10, 0.28, 0.32), METAL_D, pitch=0.45)
    for z in (0.35, 0.95, 1.52):
        mb.box((0, 0, z), (4.48, 0.08, 0.10), WOOD_D)
    # Vertical corrugated slats/pickets between posts
    for bx in (-1.1, 1.1):
        for i in range(6):
            px = bx - 0.80 + i * 0.32
            mb.box((px, 0.03, 0.92), (0.24, 0.04, 1.32), METAL if i % 2 == 0 else RUST)
    for z in (1.76, 1.92):
        mb.box((0, 0.14, z), (4.50, 0.03, 0.03), METAL_D)


def prop_antenna(mb):
    # Tactical lattice communications tower on concrete foundation pad with transceiver cabinet, microwave dish & dipole array
    mb.box((0, 0, 0.08), (1.15, 1.15, 0.16), CONCRETE_D)
    mb.box((-0.32, 0.24, 0.46), (0.48, 0.38, 0.64), OLIVE)
    # 4 tapered lattice legs & cross-braces
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            mb.cyl((sx * 0.24, sy * 0.24, 2.15), 0.04, 4.2, 6, METAL)
    for i in range(7):
        z = 0.55 + i * 0.58
        w = 0.52
        mb.box((0, 0, z), (w, w, 0.05), METAL_D)
    # Upper whip mast, microwave parabolic dish & cross-dipole array
    mb.cyl((0, 0, 4.55), 0.045, 1.1, 8, METAL)
    mb.cyl((0.0, -0.32, 3.65), 0.44, 0.14, 14, (0.72, 0.74, 0.72), axis='Y', r2=0.14)
    mb.box((0, 0, 4.35), (1.15, 0.06, 0.06), METAL)
    mb.box((0, 0, 4.75), (0.06, 0.95, 0.06), METAL)


def prop_generator(mb):
    # Mobile military diesel generator on heavy steel skid frame with wheel axle, canopy louvers, exhaust stack & control panel
    mb.box((0, 0, 0.10), (1.76, 0.98, 0.12), METAL_D)
    for sx in (-0.82, 0.82):
        mb.box((sx, 0, 0.06), (0.12, 1.04, 0.10), METAL_D)
    # Main canopy housing & roof cap
    mb.box((0.05, 0, 0.60), (1.52, 0.88, 0.88), OLIVE)
    mb.tapered_box((0.05, 0, 1.08), (1.58, 0.94), (1.42, 0.78), 0.10, OLIVE_D)
    # Side cooling louver grilles & access doors
    for sy in (-0.45, 0.45):
        mb.box((0.35, sy, 0.62), (0.55, 0.04, 0.52), METAL_D)
        mb.box((-0.35, sy, 0.60), (0.58, 0.04, 0.68), OLIVE_D)
    # Control panel with gauges + vertical exhaust muffler pipe
    mb.box((-0.73, 0.10, 0.68), (0.06, 0.46, 0.38), (0.14, 0.15, 0.14))
    mb.cyl((-0.52, 0.34, 1.22), 0.095, 0.46, 10, RUST)
    mb.cyl((-0.52, 0.34, 1.52), 0.055, 0.28, 10, METAL_D)
    for x in (-0.48, 0.48):
        for y in (-0.54, 0.54):
            mb.cyl((x, y, 0.22), 0.22, 0.14, 12, TIRE, axis='Y')
            mb.cyl((x, y, 0.22), 0.11, 0.16, 8, OLIVE_D, axis='Y')


def prop_tent(mb):
    # Military field command tent with vertical side walls, pitched ridge roof, buttress guy ribs, entrance vestibule & stove pipe
    mb.box((0, 0, 0.05), (3.45, 2.75, 0.10), WOOD_D)
    # Vertical canvas side walls + pitched gable roof
    mb.box((0, 0, 0.58), (3.25, 2.55, 0.96), CANVAS_D)
    mb.tapered_box((0, 0, 1.48), (3.35, 2.68), (3.25, 0.18), 0.86, CANVAS)
    # Ridge beam & external frame ribs
    mb.box((0, 0, 1.92), (3.48, 0.14, 0.12), WOOD_D)
    for x in (-1.45, -0.48, 0.48, 1.45):
        mb.box((x, 0, 0.58), (0.10, 2.64, 0.98), CANVAS)
        for sy in (-1.48, 1.48):
            mb.box((x, sy, 0.35), (0.08, 0.32, 0.65), WOOD_D)
    # Front entrance flap opening & stove chimney pipe
    mb.box((1.64, 0, 0.62), (0.08, 0.96, 1.14), (0.08, 0.09, 0.07))
    mb.cyl((-0.85, 0.65, 2.05), 0.07, 0.75, 8, RUST)
    mb.cyl((-0.85, 0.65, 2.45), 0.12, 0.08, 8, METAL_D)


def prop_logs(mb):
    # Pyramid of 6 heavy felled timber logs with dark bark, lighter cut heartwood ends & retaining vertical stakes
    for sx in (-0.82, 0.82):
        for sy in (-0.75, 0.75):
            mb.cyl((sx, sy, 0.58), 0.065, 1.16, 8, WOOD_D)
    coords = [
        (-0.48, 0.22, 0.22), (0.0, 0.22, 0.22), (0.48, 0.22, 0.22),
        (-0.24, 0.58, 0.21), (0.24, 0.58, 0.21),
        (0.0, 0.92, 0.20),
    ]
    for idx, (x, z, r) in enumerate(coords):
        col = WOOD_D if idx % 2 == 0 else WOOD
        mb.cyl((x, 0, z), r, 2.42, 12, col, axis='Y')
        # Lighter cut wood growth-ring discs at both ends
        mb.cyl((x, 0, z), r * 0.82, 2.45, 10, WOOD_L, axis='Y')


def prop_sign(mb):
    # Fortified military checkpoint warning sign on twin steel posts with sandbagged base, hazard header & reflective board
    mb.tapered_box((0, 0, 0.16), (0.95, 0.65), (0.78, 0.48), 0.32, SAND)
    for sx in (-0.34, 0.34):
        mb.box((sx, 0, 1.22), (0.08, 0.08, 2.38), METAL_D)
    # Main sign backing plate, red/yellow border & inner placard
    mb.box((0, 0.05, 1.98), (1.08, 0.06, 0.74), (0.64, 0.16, 0.09))
    mb.box((0, 0.07, 1.98), (0.94, 0.05, 0.60), (0.86, 0.82, 0.72))
    mb.box((0, 0.09, 2.10), (0.72, 0.04, 0.14), (0.16, 0.16, 0.15))
    mb.box((0, 0.09, 1.86), (0.56, 0.04, 0.10), (0.64, 0.16, 0.09))
    # Top hazard bar
    mb.box((0, 0.05, 2.44), (1.08, 0.07, 0.14), HAZARD_Y)


def prop_fuel_tank(mb):
    # Horizontal cylindrical GSM fuel tank on 2 saddle piers with dished ends, manway turret, valve manifold & ladder
    for x in (-0.88, 0.88):
        mb.tapered_box((x, 0, 0.28), (0.36, 1.24), (0.28, 1.02), 0.56, CONCRETE_D)
    mb.cyl((0, 0, 0.90), 0.56, 2.55, 20, METAL, axis='X')
    # Dished end caps & stiffening rings
    for x in (-1.32, 1.32):
        mb.cyl((x, 0, 0.90), 0.46, 0.14, 16, METAL_D, axis='X')
    for x in (-0.88, 0.0, 0.88):
        mb.cyl((x, 0, 0.90), 0.58, 0.06, 20, RUST, axis='X')
    # Top manway dome, breather vent & side access ladder
    mb.cyl((-0.30, 0, 1.50), 0.22, 0.18, 12, RUST)
    mb.cyl((-0.30, 0, 1.60), 0.25, 0.05, 12, METAL_D)
    mb.cyl((0.42, 0, 1.56), 0.06, 0.35, 8, METAL_D)
    for z in (0.35, 0.62, 0.89, 1.16, 1.42):
        mb.box((0.20, -0.60, z), (0.36, 0.04, 0.04), METAL_D)
    for sx in (0.04, 0.36):
        mb.box((sx, -0.60, 0.90), (0.04, 0.04, 1.25), METAL_D)


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
    bsdf.inputs["Roughness"].default_value = 0.85
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
        export_texcoords=True, export_normals=True,
        export_vertex_color='ACTIVE', export_all_vertex_colors=True)
    print("[Props] exported", path, os.path.getsize(path))


if __name__ == "__main__":
    main()
