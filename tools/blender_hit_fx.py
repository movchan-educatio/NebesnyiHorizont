"""Generate two authored hit-reaction VFX scenes for Godot.

  Assets/combat/hit_infantry.glb  - blood/dust burst + flash + debris
  Assets/combat/hit_vehicle.glb   - sparks, metal shards, flash + shock ring

Run:
  blender -b --factory-startup --python tools/blender_hit_fx.py
"""
import bpy
import math
import os
import random

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "Assets", "combat")
os.makedirs(OUT_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def material(name, color, emission=0.0, metallic=0.0, roughness=0.7):
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


def cube(name, size, color, emission=0.0, metallic=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size, size, size)
    # Bake the size into the mesh; the animation scale is a 0..1 multiplier.
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material(name + "_mat", color, emission, metallic))
    return obj


def sphere(name, radius, color, emission=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material(name + "_mat", color, emission, 0.0, 0.45))
    return obj


def torus(name, major, minor, color, emission=0.0):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                    major_segments=24, minor_segments=8)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material(name + "_mat", color, emission, 0.0, 0.5))
    return obj


def key_scale(obj, frame, value):
    obj.scale = (value, value, value)
    obj.keyframe_insert(data_path="scale", frame=frame)


def key_loc(obj, frame, loc):
    obj.location = loc
    obj.keyframe_insert(data_path="location", frame=frame)


def key_rot(obj, frame, rot):
    obj.rotation_euler = rot
    obj.keyframe_insert(data_path="rotation_euler", frame=frame)


def build_infantry():
    clear_scene()
    bpy.context.scene.render.fps = 24
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 20

    flash = sphere("InfantryFlash", 0.16, (0.72, 0.08, 0.04), 2.0)
    key_scale(flash, 1, 0.01)
    key_scale(flash, 4, 1.2)
    key_scale(flash, 12, 0.55)
    key_scale(flash, 20, 0.01)

    rng = random.Random(1017)
    for i in range(7):
        a = math.tau * i / 7.0 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.35, 0.75)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.15, 0.55))
        c = cube("BloodBit_%d" % i, rng.uniform(0.030, 0.060),
                 (0.32, 0.025, 0.018), 0.0)
        key_loc(c, 1, (0, 0, 0))
        key_loc(c, 10, p)
        key_loc(c, 20, (p[0] * 1.10, p[1] * 1.10, p[2] - 0.35))
        key_scale(c, 1, 0.01)
        key_scale(c, 4, 1.0)
        key_scale(c, 20, 0.0)
        key_rot(c, 1, (0, 0, 0))
        key_rot(c, 20, (rng.uniform(2, 8), rng.uniform(2, 8), rng.uniform(2, 8)))

    # (No expanding ring: at close range it read as a white disc.  The flash
    # and debris carry the impact.)

    bpy.context.scene.frame_set(1)
    path = os.path.join(OUT_DIR, "hit_infantry.glb")
    export(path)
    print("[HITFX] infantry ->", path)


def build_vehicle():
    clear_scene()
    bpy.context.scene.render.fps = 24
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 24

    flash = sphere("VehicleFlash", 0.20, (1.0, 0.62, 0.12), 2.5)
    key_scale(flash, 1, 0.01)
    key_scale(flash, 4, 1.2)
    key_scale(flash, 10, 0.75)
    key_scale(flash, 24, 0.01)

    # (No shock ring: the close-range bloom read as a white disc.)

    rng = random.Random(2027)
    for i in range(12):
        a = math.tau * i / 12.0 + rng.uniform(-0.22, 0.22)
        d = rng.uniform(0.35, 0.95)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.10, 0.75))
        spark = cube("Spark_%d" % i, rng.uniform(0.020, 0.040),
                     (1.0, 0.72, 0.16), 1.6)
        key_loc(spark, 1, (0, 0, 0))
        key_loc(spark, 9, p)
        key_loc(spark, 24, (p[0] * 1.3, p[1] * 1.3, p[2] - 0.55))
        key_scale(spark, 1, 0.01)
        key_scale(spark, 3, 1.0)
        key_scale(spark, 24, 0.0)

    for i in range(5):
        a = math.tau * i / 5.0 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.30, 0.60)
        p = (math.cos(a) * d, math.sin(a) * d, rng.uniform(0.0, 0.35))
        shard = cube("Shard_%d" % i, rng.uniform(0.035, 0.065),
                     (0.12, 0.13, 0.14), 0.0, 0.8)
        key_loc(shard, 1, (0, 0, 0))
        key_loc(shard, 11, p)
        key_loc(shard, 24, (p[0] * 1.4, p[1] * 1.4, p[2] - 0.65))
        key_scale(shard, 1, 0.01)
        key_scale(shard, 3, 1.0)
        key_scale(shard, 24, 0.02)
        key_rot(shard, 1, (0, 0, 0))
        key_rot(shard, 24, (rng.uniform(3, 9), rng.uniform(3, 9), rng.uniform(3, 9)))

    # (No solid smoke sphere: it read as a grey ball at close range.  The
    # authored sparks/shards/flash are enough; the game adds real smoke.)

    bpy.context.scene.frame_set(1)
    path = os.path.join(OUT_DIR, "hit_vehicle.glb")
    export(path)
    print("[HITFX] vehicle ->", path)


def export(path):
    # Pack every object action into an NLA track named "Hit"; the glTF
    # exporter groups tracks with the same name into one animation.
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


if __name__ == "__main__":
    build_infantry()
    build_vehicle()
    print("[HITFX] done")
