"""Generate high-detail authored hit-reaction VFX for CityFPV.

Outputs (Assets/combat):
  hit_infantry.glb
  hit_tank.glb, hit_bmp.glb, hit_apc.glb, hit_truck.glb,
  hit_sam.glb, hit_heli.glb, hit_shahed.glb
  hit_vehicle.glb (generic fallback)

Each GLB contains one NLA-track animation named "Hit": a hot flash, a debris
burst, dirt/dust, smoke and type-specific fragments.  The scenes are built from
low-poly primitives so a hit costs only a few thousand triangles and a handful
of draw calls.

Run:
  blender -b --factory-startup --python tools/blender_hit_fx_v2.py
"""
import bpy
import math
import os
import random

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "Assets", "combat")
os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------- materials
def material(name, color, emission=0.0, metallic=0.0, roughness=0.72):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.actions):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def _bake_size(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def cube(name, size, color, emission=0.0, metallic=0.0, roughness=0.7):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    obj.name = name
    if isinstance(size, (int, float)):
        size = (size, size, size)
    obj.scale = size
    _bake_size(obj)
    obj.data.materials.append(material(name + "_mat", color, emission,
                                       metallic, roughness))
    return obj


def sphere(name, radius, color, emission=0.0, metallic=0.0, roughness=0.6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6,
                                        radius=radius)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material(name + "_mat", color, emission,
                                       metallic, roughness))
    return obj


def cylinder(name, radius, depth, color, emission=0.0, metallic=0.0,
             vertices=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                       depth=depth)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material(name + "_mat", color, emission,
                                       metallic, 0.55))
    return obj


def torus(name, major, minor, color, emission=0.0, metallic=0.0):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                    major_segments=20, minor_segments=6)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material(name + "_mat", color, emission,
                                       metallic, 0.55))
    return obj


# ---------------------------------------------------------------- keyframes
def key_loc(obj, frame, loc):
    obj.location = loc
    obj.keyframe_insert(data_path="location", frame=frame)


def key_scale(obj, frame, value):
    if isinstance(value, (int, float)):
        value = (value, value, value)
    obj.scale = value
    obj.keyframe_insert(data_path="scale", frame=frame)


def key_rot(obj, frame, rot):
    obj.rotation_euler = rot
    obj.keyframe_insert(data_path="rotation_euler", frame=frame)


# ---------------------------------------------------------------- effects
def flash(name, radius, color, energy, frame_end=30, secondary=False):
    obj = sphere(name, radius, color, energy, 0.0, 0.25)
    key_scale(obj, 1, 0.01)
    key_scale(obj, 3, 1.35)
    key_scale(obj, 8, 0.95)
    key_scale(obj, frame_end, 0.01)
    # A smaller, hotter core reads as fire instead of a flat pale ball.
    core = sphere(name + "_Core", radius * 0.46, (1.0, 0.82, 0.35),
                  energy * 1.5, 0.0, 0.2)
    key_scale(core, 1, 0.01)
    key_scale(core, 2, 1.1)
    key_scale(core, 7, 0.7)
    key_scale(core, frame_end, 0.01)
    return obj


def sparks(rng, count, color=(1.0, 0.70, 0.16), energy=3.4, seed_radius=0.05,
           distance=1.6, size=0.045):
    for i in range(count):
        a = math.tau * i / max(count, 1) + rng.uniform(-0.35, 0.35)
        d = rng.uniform(distance * 0.35, distance)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.10, 0.85))
        s = cube("Spark_%02d" % i, rng.uniform(size * 0.55, size),
                 color, energy, 0.25, 0.45)
        key_loc(s, 1, (rng.uniform(-seed_radius, seed_radius),
                       rng.uniform(-seed_radius, seed_radius),
                       rng.uniform(0.0, 0.18)))
        key_loc(s, 6, p)
        key_loc(s, 22, (p[0] * 1.25, p[1] * 1.25, p[2] - 0.65))
        key_scale(s, 1, 0.01)
        key_scale(s, 3, 1.0)
        key_scale(s, 22, 0.0)


def shards(rng, count, color=(0.24, 0.25, 0.23), distance=1.5,
           size=0.10, spin=9.0):
    for i in range(count):
        a = math.tau * i / max(count, 1) + rng.uniform(-0.28, 0.28)
        d = rng.uniform(distance * 0.35, distance)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.06, 0.65))
        obj = cube("Shard_%02d" % i,
                   (rng.uniform(0.45, 1.0) * size,
                    rng.uniform(0.5, 1.1) * size,
                    rng.uniform(0.12, 0.35) * size),
                   color, 0.0, 0.75, 0.48)
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 8, p)
        key_loc(obj, 26, (p[0] * 1.45, p[1] * 1.45, p[2] - 0.8))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 26, 0.02)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 26, (rng.uniform(-spin, spin),
                          rng.uniform(-spin, spin), rng.uniform(-spin, spin)))


def dirt(rng, count, distance=1.3, size=0.075):
    for i in range(count):
        a = math.tau * i / max(count, 1) + rng.uniform(-0.3, 0.3)
        d = rng.uniform(distance * 0.3, distance)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.18, 0.50))
        obj = cube("Dirt_%02d" % i,
                   (rng.uniform(0.6, 1.5) * size,
                    rng.uniform(0.6, 1.4) * size,
                    rng.uniform(0.5, 1.2) * size),
                   (0.32, 0.27, 0.19), 0.0, 0.0, 0.96)
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 7, p)
        key_loc(obj, 26, (p[0] * 1.2, p[1] * 1.2, p[2] - 0.45))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 26, 0.0)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 26, (rng.uniform(-5, 5), rng.uniform(-5, 5),
                          rng.uniform(-5, 5)))


def smoke(rng, count, radius=0.28, height=1.0, spread=0.85, dark=0.25):
    # Solid smoke spheres read as grey balls at FPV range.  The engine adds
    # soft billboard smoke in combat/hit_fx.gd; the Blender scene carries the
    # flash, debris, sparks and shockwave instead.
    return


def fire_puff(name, radius, height, frame=8):
    obj = sphere(name, radius, (1.0, 0.32, 0.04), 2.6, 0.0, 0.5)
    obj.location = (0, 0, height)
    key_scale(obj, 1, 0.01)
    key_scale(obj, frame, 1.2)
    key_scale(obj, frame + 10, 1.9)
    key_scale(obj, 30, 0.01)


def shockwave(name, color, max_scale=2.6):
    obj = torus(name, 0.28, 0.018, color, 1.6, 0.1)
    obj.rotation_euler = (math.pi * 0.5, 0, 0)
    key_scale(obj, 1, 0.01)
    key_scale(obj, 6, 1.0)
    key_scale(obj, 26, max_scale)
    return obj


def track_links(rng, count, color=(0.16, 0.165, 0.15)):
    for i in range(count):
        obj = cube("TrackLink_%02d" % i,
                   (rng.uniform(0.20, 0.34), rng.uniform(0.045, 0.070),
                    rng.uniform(0.14, 0.24)), color, 0.0, 0.7, 0.42)
        a = math.tau * i / max(count, 1) + rng.uniform(-0.4, 0.4)
        d = rng.uniform(0.9, 2.0)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.1, 0.45))
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 9, p)
        key_loc(obj, 28, (p[0] * 1.35, p[1] * 1.35, p[2] - 0.55))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 28, 0.02)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 28, (rng.uniform(-8, 8), rng.uniform(-8, 8),
                          rng.uniform(-8, 8)))


def wheel_chunks(rng, count):
    for i in range(count):
        obj = torus("WheelChunk_%02d" % i, 0.22, 0.070,
                    (0.075, 0.078, 0.070))
        obj.rotation_euler = (rng.uniform(0, math.tau),
                              rng.uniform(0, math.tau),
                              rng.uniform(0, math.tau))
        a = math.tau * i / max(count, 1) + rng.uniform(-0.5, 0.5)
        d = rng.uniform(1.0, 2.0)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(0.0, 0.6))
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 9, p)
        key_loc(obj, 28, (p[0] * 1.25, p[1] * 1.25, p[2] - 0.55))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 28, 0.02)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 28, (rng.uniform(-8, 8), rng.uniform(-8, 8),
                          rng.uniform(-8, 8)))


def body_chunk(name, size, color, start, end, spin, metallic=0.55):
    obj = cube(name, size, color, 0.0, metallic, 0.45)
    key_loc(obj, 1, start)
    key_loc(obj, 10, end)
    key_loc(obj, 28, (end[0] * 1.35, end[1] * 1.35, end[2] - 0.9))
    key_scale(obj, 1, 0.01)
    key_scale(obj, 3, 1.0)
    key_scale(obj, 28, 0.02)
    key_rot(obj, 1, (0, 0, 0))
    key_rot(obj, 28, (spin[0], spin[1], spin[2]))


def blade_fragments(rng, count, color):
    for i in range(count):
        obj = cube("BladeFrag_%02d" % i,
                   (rng.uniform(0.40, 0.80), 0.035, rng.uniform(0.08, 0.16)),
                   color, 0.0, 0.65, 0.35)
        a = math.tau * i / max(count, 1) + rng.uniform(-0.3, 0.3)
        d = rng.uniform(1.0, 2.4)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(0.1, 0.9))
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 10, p)
        key_loc(obj, 30, (p[0] * 1.4, p[1] * 1.4, p[2] - 0.7))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 30, 0.02)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 30, (rng.uniform(-9, 9), rng.uniform(-9, 9),
                          rng.uniform(-9, 9)))


def gear_chunks(rng, count):
    colors = [(0.17, 0.19, 0.14), (0.10, 0.10, 0.09), (0.28, 0.29, 0.22)]
    for i in range(count):
        obj = cube("Gear_%02d" % i,
                   (rng.uniform(0.05, 0.11), rng.uniform(0.03, 0.09),
                    rng.uniform(0.03, 0.08)), colors[i % len(colors)],
                   0.0, 0.15, 0.8)
        a = math.tau * i / max(count, 1) + rng.uniform(-0.4, 0.4)
        d = rng.uniform(0.4, 1.0)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.1, 0.45))
        key_loc(obj, 1, (0, 0, 0))
        key_loc(obj, 8, p)
        key_loc(obj, 26, (p[0] * 1.1, p[1] * 1.1, p[2] - 0.55))
        key_scale(obj, 1, 0.01)
        key_scale(obj, 3, 1.0)
        key_scale(obj, 26, 0.02)
        key_rot(obj, 1, (0, 0, 0))
        key_rot(obj, 26, (rng.uniform(-7, 7), rng.uniform(-7, 7),
                          rng.uniform(-7, 7)))


# ---------------------------------------------------------------- scene types
def build_infantry():
    rng = random.Random(701)
    flash("InfantryFlash", 0.24, (0.9, 0.08, 0.03), 1.0, 24)
    smoke(rng, 8, 0.22, 0.8, 0.6, 0.30)
    dirt(rng, 12, 1.0, 0.060)
    shards(rng, 12, (0.40, 0.06, 0.04), 0.85, 0.055, 6.0)
    gear_chunks(rng, 8)
    # A helmet-like shell and a magazine give the burst a readable silhouette.
    body_chunk("HelmetShell", (0.28, 0.14, 0.32), (0.22, 0.24, 0.18),
               (0, 0, 0.15), (0.7, 0.3, 1.1), (5, 3, 7), 0.25)
    body_chunk("Magazine", (0.09, 0.05, 0.22), (0.10, 0.10, 0.09),
               (0, 0, 0.12), (-0.4, 0.4, 0.95), (7, 5, 9), 0.4)


def build_tank():
    rng = random.Random(1101)
    flash("TankFlash", 0.55, (1.0, 0.30, 0.02), 1.8, 32, True)
    sparks(rng, 36, (1.0, 0.70, 0.16), 4.2, 0.08, 2.2, 0.060)
    shards(rng, 24, (0.24, 0.25, 0.22), 2.1, 0.12, 10.0)
    dirt(rng, 18, 1.8, 0.090)
    smoke(rng, 12, 0.36, 1.2, 1.15, 0.24)
    track_links(rng, 8)
    wheel_chunks(rng, 3)
    shockwave("TankShock", (1.0, 0.55, 0.12), 2.8)
    body_chunk("TurretHatch", (0.66, 0.12, 0.66), (0.26, 0.29, 0.20),
               (0, 0, 0.55), (0.2, 0.35, 1.65), (8, 3, 6))
    body_chunk("ERA_Block", (0.60, 0.24, 0.34), (0.23, 0.27, 0.18),
               (0, 0, 0.12), (-1.1, 0.4, 1.0), (6, 5, 9))
    fire_puff("TankFire", 0.36, 0.85, 9)


def build_bmp():
    rng = random.Random(2202)
    flash("BmpFlash", 0.46, (1.0, 0.30, 0.02), 1.7, 30, True)
    sparks(rng, 30, (1.0, 0.68, 0.14), 3.8, 0.06, 1.9, 0.052)
    shards(rng, 18, (0.22, 0.23, 0.19), 1.8, 0.10, 9.0)
    dirt(rng, 14, 1.5, 0.080)
    smoke(rng, 10, 0.32, 1.1, 1.0, 0.22)
    track_links(rng, 7)
    shockwave("BmpShock", (1.0, 0.52, 0.10), 2.4)
    body_chunk("BMP_Skirt", (0.76, 0.13, 0.30), (0.23, 0.27, 0.15),
               (0, 0, 0.18), (1.1, 0.4, 0.95), (7, 4, 9))
    fire_puff("BmpFire", 0.30, 0.65, 8)


def build_apc():
    rng = random.Random(3303)
    flash("ApcFlash", 0.48, (1.0, 0.32, 0.02), 1.7, 30, True)
    sparks(rng, 32, (1.0, 0.66, 0.14), 3.6, 0.06, 1.9, 0.048)
    shards(rng, 16, (0.22, 0.23, 0.20), 1.6, 0.10, 9.0)
    dirt(rng, 18, 1.6, 0.085)
    smoke(rng, 10, 0.30, 1.1, 0.95, 0.25)
    wheel_chunks(rng, 8)
    shockwave("ApcShock", (1.0, 0.58, 0.12), 2.5)
    body_chunk("Apc_SideArmor", (0.70, 0.16, 0.38), (0.23, 0.27, 0.17),
               (0, 0, 0.12), (1.0, 0.5, 0.9), (6, 5, 8))


def build_truck():
    rng = random.Random(4404)
    flash("TruckFlash", 0.38, (1.0, 0.35, 0.03), 1.5, 28, True)
    sparks(rng, 26, (1.0, 0.68, 0.16), 3.2, 0.05, 1.6, 0.042)
    shards(rng, 14, (0.25, 0.24, 0.20), 1.4, 0.085, 8.0)
    dirt(rng, 12, 1.3, 0.075)
    smoke(rng, 9, 0.28, 1.0, 0.85, 0.24)
    wheel_chunks(rng, 5)
    shockwave("TruckShock", (1.0, 0.60, 0.14), 2.2)
    body_chunk("Tigr_Hood", (0.58, 0.15, 0.72), (0.28, 0.29, 0.20),
               (0, 0, 0.24), (0.5, 0.3, 1.1), (5, 4, 7))
    fire_puff("TruckFire", 0.28, 0.55, 7)


def build_sam():
    rng = random.Random(5505)
    flash("SamFlash", 0.48, (0.65, 0.45, 1.0), 1.6, 30, True)
    sparks(rng, 34, (0.85, 0.78, 1.0), 4.0, 0.06, 2.0, 0.050)
    shards(rng, 18, (0.27, 0.28, 0.31), 1.7, 0.085, 9.0)
    dirt(rng, 12, 1.4, 0.075)
    smoke(rng, 10, 0.32, 1.1, 1.0, 0.22)
    shockwave("SamShock", (0.70, 0.58, 1.0), 2.5)
    body_chunk("RadarDish_1", (0.65, 0.06, 0.45), (0.30, 0.32, 0.27),
               (0, 0, 0.70), (1.0, 0.4, 1.4), (7, 4, 9))
    body_chunk("RadarDish_2", (0.46, 0.05, 0.36), (0.32, 0.34, 0.29),
               (0, 0, 0.70), (-0.9, -0.2, 1.2), (9, 3, 7))
    body_chunk("Electronics", (0.26, 0.13, 0.22), (0.14, 0.16, 0.12),
               (0, 0, 0.2), (0.4, 0.6, 1.0), (8, 6, 10))


def build_heli():
    rng = random.Random(6606)
    flash("HeliFlash", 0.52, (1.0, 0.30, 0.02), 1.8, 32, True)
    sparks(rng, 36, (1.0, 0.68, 0.14), 4.0, 0.08, 2.2, 0.052)
    shards(rng, 16, (0.25, 0.26, 0.23), 1.6, 0.085, 8.0)
    dirt(rng, 8, 1.4, 0.075)
    smoke(rng, 13, 0.32, 1.3, 1.15, 0.24)
    blade_fragments(rng, 8, (0.24, 0.26, 0.21))
    shockwave("HeliShock", (1.0, 0.58, 0.14), 2.7)
    body_chunk("TailBoom", (0.70, 0.20, 0.26), (0.25, 0.28, 0.19),
               (0, 0, 0.6), (1.5, 0.5, 1.6), (7, 5, 9))
    body_chunk("RotorHub", (0.30, 0.15, 0.30), (0.16, 0.17, 0.16),
               (0, 0, 0.7), (0.3, 0.5, 1.8), (9, 7, 8))
    fire_puff("HeliFire", 0.34, 0.95, 8)


def build_shahed():
    rng = random.Random(7707)
    flash("ShahedFlash", 0.42, (1.0, 0.32, 0.02), 1.6, 30, True)
    sparks(rng, 28, (1.0, 0.66, 0.14), 3.4, 0.05, 1.8, 0.042)
    shards(rng, 14, (0.26, 0.27, 0.23), 1.5, 0.075, 8.0)
    dirt(rng, 8, 1.1, 0.065)
    smoke(rng, 10, 0.28, 1.0, 0.9, 0.22)
    blade_fragments(rng, 6, (0.30, 0.32, 0.27))
    shockwave("ShahedShock", (1.0, 0.58, 0.12), 2.3)
    body_chunk("Shahed_Wing", (0.70, 0.045, 0.42), (0.30, 0.32, 0.26),
               (0, 0, 0.18), (1.1, 0.5, 0.85), (6, 5, 9))
    body_chunk("Shahed_Engine", (0.24, 0.18, 0.36), (0.16, 0.17, 0.15),
               (0, 0, 0.20), (-0.5, 0.3, 1.0), (8, 7, 7))
    fire_puff("ShahedFire", 0.26, 0.55, 7)


def build_generic():
    rng = random.Random(8808)
    flash("VehicleFlash", 0.44, (1.0, 0.33, 0.02), 1.6, 30, True)
    sparks(rng, 28, (1.0, 0.70, 0.16), 3.6, 0.06, 1.8, 0.045)
    shards(rng, 14, (0.24, 0.25, 0.23), 1.5, 0.09, 8.0)
    dirt(rng, 12, 1.3, 0.070)
    smoke(rng, 9, 0.28, 1.0, 0.85, 0.24)
    shockwave("VehicleShock", (1.0, 0.60, 0.14), 2.4)


# ---------------------------------------------------------------- export
def export(path):
    for obj in bpy.data.objects:
        ad = obj.animation_data
        if ad is not None and ad.action is not None:
            action = ad.action
            track = ad.nla_tracks.new()
            track.name = "Hit"
            track.strips.new("Hit", 1, action)
            ad.action = None
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("[HITFX2] ->", path)


def build(kind, builder, frames=30):
    clear_scene()
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = frames
    builder()
    bpy.context.scene.frame_set(1)
    export(os.path.join(OUT_DIR, "hit_%s.glb" % kind))


if __name__ == "__main__":
    build("infantry", build_infantry, 26)
    build("tank", build_tank, 32)
    build("bmp", build_bmp, 30)
    build("apc", build_apc, 30)
    build("truck", build_truck, 28)
    build("sam", build_sam, 30)
    build("heli", build_heli, 32)
    build("shahed", build_shahed, 30)
    build("vehicle", build_generic, 30)
    print("[HITFX2] done")
