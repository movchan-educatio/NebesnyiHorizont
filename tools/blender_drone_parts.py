"""Blender 5.x generator for per-drone propellers and motor bells.

Every airframe in DroneCatalog gets its own propeller profile instead of one
generic white mesh: 2/3/4 blades, different chord distribution, pitch, sweep,
thickness, tip shape and hub.  Meshes are authored at exactly 1.0 m diameter
(radius 0.5) with the blades in the XY plane and the spin axis on +Z, so Godot
can scale them by the real prop_d and tint them per airframe.

Run:
  blender -b --factory-startup --python tools/blender_drone_parts.py
"""

import bpy
import math
import os

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "Assets", "Drones")
OUT_PATH = os.path.join(OUT_DIR, "drone_parts.glb")
os.makedirs(OUT_DIR, exist_ok=True)

TAU = math.pi * 2.0
STATIONS = (0.00, 0.10, 0.22, 0.36, 0.52, 0.68, 0.82, 0.92, 0.97)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def make_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.38
    bsdf.inputs["Metallic"].default_value = 0.05
    return mat


def make_mesh_object(name, verts, faces, material, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    return obj


AIRFOIL = (
    (-0.500, 0.00),
    (-0.420, 0.45),
    (-0.250, 0.85),
    (0.000, 1.00),
    (0.250, 0.78),
    (0.500, 0.00),
    (0.250, -0.55),
    (0.000, -0.80),
    (-0.250, -0.72),
    (-0.420, -0.35),
)


def sample_profile(values, t):
    """Linear resample of the six authored profile stations to any t."""
    x = max(0.0, min(1.0, t)) * (len(values) - 1)
    i = int(x)
    if i >= len(values) - 1:
        return values[-1]
    f = x - i
    return values[i] * (1.0 - f) + values[i + 1] * f


def add_blade(verts, faces, sections, angle):
    """One twisted blade with a ten-point cambered airfoil, root to tip."""
    ca, sa = math.cos(angle), math.sin(angle)
    start = len(verts)
    for r, chord, thickness, pitch, sweep, rise in sections:
        half_c = chord * 0.5
        half_t = thickness * 0.5
        cp, sp = math.cos(pitch), math.sin(pitch)
        for ax, az in AIRFOIL:
            y = ax * chord
            z = az * thickness
            # Twist around the radial axis.
            py = y * cp - z * sp
            pz = y * sp + z * cp
            # Tangential sweep and vertical rake.
            py += sweep
            pz += rise
            verts.append((r * ca - py * sa, r * sa + py * ca, pz))
    sides = len(AIRFOIL)
    for i in range(len(sections) - 1):
        a = start + i * sides
        b = start + (i + 1) * sides
        for k in range(sides):
            k2 = (k + 1) % sides
            faces.append((a + k, a + k2, b + k2, b + k))
    tip = start + (len(sections) - 1) * sides
    faces.append(tuple(range(start, start + sides)))
    faces.append(tuple(range(tip + sides - 1, tip - 1, -1)))


def add_hub(verts, faces, radius, height, top_scale=0.78, sides=24):
    """A small tapered spinner with a chamfered top."""
    start = len(verts)
    hz = height * 0.5
    rings = (
        (radius * 0.92, -hz),
        (radius, -hz * 0.55),
        (radius * top_scale, hz * 0.55),
        (radius * top_scale * 0.62, hz),
    )
    for rr, z in rings:
        for i in range(sides):
            a = TAU * i / sides
            verts.append((math.cos(a) * rr, math.sin(a) * rr, z))
    for r in range(len(rings) - 1):
        a = r * sides
        b = (r + 1) * sides
        for i in range(sides):
            i2 = (i + 1) % sides
            faces.append((a + i, a + i2, b + i2, b + i))
    top = (len(rings) - 1) * sides
    faces.append(tuple(range(top, top + sides)))
    faces.append(tuple(range(sides - 1, -1, -1)))


def build_prop(name, spec):
    verts = []
    faces = []
    root = spec["root"]
    thick_ratio = spec["thick"]
    sections = []
    for t in STATIONS:
        r = root + (0.5 - root) * t
        chord = sample_profile(spec["chord"], t)
        sections.append((
            r,
            chord,
            max(0.0022, chord * thick_ratio),
            math.radians(sample_profile(spec["pitch"], t)),
            sample_profile(spec["sweep"], t) * r,
            sample_profile(spec["rise"], t),
        ))
    # Rounded / pointed tip cap.
    last = sections[-1]
    tip_chord = max(0.0018, spec["chord"][-1] * spec["tip"])
    sections.append((
        0.5,
        tip_chord,
        max(0.0016, last[2] * 0.55),
        math.radians(spec["pitch"][-1] * 0.82),
        last[4] + spec["tip_sweep"] * 0.5,
        last[5] + spec["tip_rise"],
    ))
    for b in range(spec["blades"]):
        add_blade(verts, faces, sections, TAU * b / spec["blades"])
    add_hub(verts, faces, spec["hub_r"], spec["hub_h"], spec["hub_top"])
    mat = make_material(name + "_mat", (0.80, 0.80, 0.78))
    return make_mesh_object(name, verts, faces, mat)


def build_motor_bell(name):
    verts = []
    faces = []
    sides = 24
    rings = (
        (0.50, -0.18),
        (0.50, 0.02),
        (0.46, 0.16),
        (0.36, 0.23),
        (0.16, 0.25),
    )
    for radius, z in rings:
        for i in range(sides):
            a = TAU * i / sides
            verts.append((math.cos(a) * radius, math.sin(a) * radius, z))
    for r in range(len(rings) - 1):
        a = r * sides
        b = (r + 1) * sides
        for i in range(sides):
            i2 = (i + 1) % sides
            faces.append((a + i, a + i2, b + i2, b + i))
    top = (len(rings) - 1) * sides
    for i in range(1, sides - 1):
        faces.append((top, top + i, top + i + 1))
    for i in range(1, sides - 1):
        faces.append((0, i + 1, i))
    mat = make_material(name + "_mat", (0.16, 0.17, 0.18))
    return make_mesh_object(name, verts, faces, mat)


# One entry per DroneCatalog preset (index 0..11).  Preset 10 is the naval
# Magura and never uses propellers; its profile is generated only so the
# library stays index-complete.
PROFILES = {
    # 0 - GOLKA: 5" racing, three narrow high-pitch scimitar blades.
    0: dict(blades=3, root=0.055, hub_r=0.048, hub_h=0.046, hub_top=0.72,
            thick=0.16,
            chord=(0.070, 0.130, 0.150, 0.132, 0.082, 0.020),
            pitch=(31, 30, 27, 21, 14, 9),
            sweep=(0.00, 0.012, 0.036, 0.080, 0.135, 0.185),
            rise=(0.000, 0.002, 0.005, 0.009, 0.014, 0.019),
            tip=0.28, tip_sweep=0.10, tip_rise=0.003),
    # 1 - PinaPipe: 5" freestyle, broad rounded three-blade paddle.
    1: dict(blades=3, root=0.060, hub_r=0.055, hub_h=0.050, hub_top=0.80,
            thick=0.15,
            chord=(0.090, 0.158, 0.182, 0.168, 0.128, 0.052),
            pitch=(24, 23, 21, 17, 12, 8),
            sweep=(0.00, 0.005, 0.016, 0.036, 0.062, 0.090),
            rise=(0.000, 0.001, 0.002, 0.004, 0.006, 0.008),
            tip=0.46, tip_sweep=0.03, tip_rise=0.001),
    # 2 - DJI Avata 2: 3.2" cinewhoop, very wide low-pitch ducted blade.
    2: dict(blades=3, root=0.070, hub_r=0.060, hub_h=0.044, hub_top=0.82,
            thick=0.19,
            chord=(0.105, 0.175, 0.205, 0.198, 0.162, 0.090),
            pitch=(18, 17, 16, 13, 10, 7),
            sweep=(0.00, 0.002, 0.008, 0.018, 0.034, 0.052),
            rise=(0.000, 0.001, 0.002, 0.003, 0.004, 0.005),
            tip=0.55, tip_sweep=0.015, tip_rise=0.001),
    # 3 - PISUN VTOL: 7" two-blade long scimitar for cruise efficiency.
    3: dict(blades=2, root=0.045, hub_r=0.042, hub_h=0.040, hub_top=0.72,
            thick=0.15,
            chord=(0.060, 0.100, 0.118, 0.108, 0.072, 0.014),
            pitch=(28, 27, 24, 19, 13, 8),
            sweep=(0.00, 0.018, 0.050, 0.100, 0.168, 0.235),
            rise=(0.000, 0.003, 0.007, 0.013, 0.021, 0.029),
            tip=0.24, tip_sweep=0.12, tip_rise=0.004),
    # 4 - PELENG: 5" recon, two low-drag blades with square tips.
    4: dict(blades=2, root=0.050, hub_r=0.045, hub_h=0.042, hub_top=0.75,
            thick=0.14,
            chord=(0.068, 0.118, 0.140, 0.132, 0.098, 0.032),
            pitch=(22, 21, 19, 16, 11, 7),
            sweep=(0.00, 0.008, 0.020, 0.040, 0.070, 0.100),
            rise=(0.000, 0.001, 0.002, 0.004, 0.006, 0.009),
            tip=0.50, tip_sweep=0.02, tip_rise=0.001),
    # 5 - GRIM-7: 8" heavy lift, broad three-blade paddle.
    5: dict(blades=3, root=0.065, hub_r=0.062, hub_h=0.056, hub_top=0.82,
            thick=0.17,
            chord=(0.095, 0.162, 0.188, 0.174, 0.130, 0.048),
            pitch=(22, 21, 19, 15, 10, 7),
            sweep=(0.00, 0.004, 0.012, 0.028, 0.050, 0.080),
            rise=(0.000, 0.001, 0.003, 0.005, 0.008, 0.011),
            tip=0.44, tip_sweep=0.03, tip_rise=0.002),
    # 6 - GRIM-7M: 8" dropper, more swept and higher pitch than #5.
    6: dict(blades=3, root=0.060, hub_r=0.058, hub_h=0.052, hub_top=0.80,
            thick=0.16,
            chord=(0.086, 0.145, 0.168, 0.150, 0.104, 0.030),
            pitch=(25, 24, 22, 18, 12, 8),
            sweep=(0.00, 0.012, 0.034, 0.072, 0.118, 0.168),
            rise=(0.000, 0.002, 0.006, 0.011, 0.017, 0.024),
            tip=0.30, tip_sweep=0.08, tip_rise=0.003),
    # 7 - STRILA-8: 8.5" strike, wide rounded paddle with a fat hub.
    7: dict(blades=3, root=0.070, hub_r=0.068, hub_h=0.060, hub_top=0.85,
            thick=0.17,
            chord=(0.100, 0.174, 0.202, 0.188, 0.146, 0.058),
            pitch=(20, 19, 17, 14, 9, 6),
            sweep=(0.00, 0.003, 0.010, 0.022, 0.038, 0.058),
            rise=(0.000, 0.001, 0.002, 0.004, 0.006, 0.008),
            tip=0.52, tip_sweep=0.02, tip_rise=0.001),
    # 8 - Falcon-X: 5" digital speed, four thin high-pitch scimitar blades.
    8: dict(blades=4, root=0.050, hub_r=0.044, hub_h=0.042, hub_top=0.70,
            thick=0.13,
            chord=(0.060, 0.100, 0.120, 0.106, 0.070, 0.014),
            pitch=(32, 31, 28, 22, 15, 9),
            sweep=(0.00, 0.014, 0.040, 0.086, 0.142, 0.198),
            rise=(0.000, 0.003, 0.007, 0.012, 0.018, 0.025),
            tip=0.22, tip_sweep=0.12, tip_rise=0.004),
    # 9 - QUAD-5: 5" freestyle, four medium-chord blades.
    9: dict(blades=4, root=0.055, hub_r=0.050, hub_h=0.046, hub_top=0.78,
            thick=0.15,
            chord=(0.076, 0.132, 0.156, 0.142, 0.098, 0.030),
            pitch=(26, 25, 23, 19, 13, 8),
            sweep=(0.00, 0.007, 0.020, 0.044, 0.080, 0.115),
            rise=(0.000, 0.001, 0.004, 0.007, 0.011, 0.015),
            tip=0.32, tip_sweep=0.05, tip_rise=0.002),
    # 10 - USV MAGURA: unused by the boat, kept for index completeness.
    10: dict(blades=4, root=0.075, hub_r=0.070, hub_h=0.060, hub_top=0.90,
             thick=0.20,
             chord=(0.100, 0.155, 0.175, 0.160, 0.115, 0.045),
             pitch=(22, 21, 19, 15, 10, 6),
             sweep=(0.00, 0.004, 0.012, 0.026, 0.046, 0.070),
             rise=(0.000, 0.001, 0.002, 0.004, 0.006, 0.008),
             tip=0.48, tip_sweep=0.02, tip_rise=0.001),
    # 11 - Military 10in: very broad square-tipped heavy-lift paddle.
    11: dict(blades=3, root=0.075, hub_r=0.075, hub_h=0.066, hub_top=0.88,
             thick=0.18,
             chord=(0.130, 0.195, 0.220, 0.212, 0.188, 0.120),
             pitch=(18, 17, 15, 12, 8, 5),
             sweep=(0.00, 0.002, 0.006, 0.014, 0.024, 0.036),
             rise=(0.000, 0.001, 0.002, 0.003, 0.004, 0.005),
             tip=0.62, tip_sweep=0.01, tip_rise=0.001),
    # 12 - BABA YAGA: 28in six-rotor heavy lifter, broad low-pitch paddles.
    12: dict(blades=3, root=0.085, hub_r=0.080, hub_h=0.070, hub_top=0.86,
             thick=0.19,
             chord=(0.150, 0.220, 0.245, 0.235, 0.205, 0.150),
             pitch=(16, 15, 13, 11, 8, 5),
             sweep=(0.00, 0.002, 0.005, 0.010, 0.018, 0.030),
             rise=(0.000, 0.001, 0.002, 0.003, 0.004, 0.005),
             tip=0.66, tip_sweep=0.01, tip_rise=0.001),
    # 13 - LELEKA fixed-wing pusher: long, narrow, efficient two-blade.
    13: dict(blades=2, root=0.050, hub_r=0.045, hub_h=0.042, hub_top=0.76,
             thick=0.13,
             chord=(0.055, 0.085, 0.100, 0.092, 0.062, 0.018),
             pitch=(30, 29, 26, 21, 14, 8),
             sweep=(0.00, 0.014, 0.040, 0.085, 0.145, 0.200),
             rise=(0.000, 0.002, 0.005, 0.010, 0.016, 0.022),
             tip=0.28, tip_sweep=0.10, tip_rise=0.003),
    # 14 - FURIA fixed-wing pusher: broad carbon two-blade with a square tip.
    14: dict(blades=2, root=0.055, hub_r=0.050, hub_h=0.046, hub_top=0.78,
             thick=0.15,
             chord=(0.075, 0.120, 0.142, 0.132, 0.096, 0.040),
             pitch=(24, 23, 20, 16, 11, 7),
             sweep=(0.00, 0.006, 0.018, 0.042, 0.080, 0.120),
             rise=(0.000, 0.001, 0.003, 0.006, 0.010, 0.014),
             tip=0.52, tip_sweep=0.02, tip_rise=0.001),
    # 15 - CHAKLUN jet: index-complete turbine placeholder (not used).
    15: dict(blades=4, root=0.060, hub_r=0.055, hub_h=0.050, hub_top=0.80,
             thick=0.14,
             chord=(0.060, 0.095, 0.110, 0.100, 0.070, 0.024),
             pitch=(28, 27, 24, 19, 13, 8),
             sweep=(0.00, 0.008, 0.022, 0.050, 0.090, 0.130),
             rise=(0.000, 0.001, 0.003, 0.007, 0.011, 0.016),
             tip=0.30, tip_sweep=0.06, tip_rise=0.002),
}


def main():
    clear_scene()
    objs = []
    for index in range(16):
        objs.append(build_prop("prop_p%d" % index, PROFILES[index]))
    objs.append(build_motor_bell("motor_bell"))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("[DroneParts] exported", OUT_PATH, "with", len(objs), "objects")


if __name__ == "__main__":
    main()
