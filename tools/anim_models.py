"""Bake simple loop animations onto the imported combat models and export GLBs
with animations, so Godot can just play them.

  tank      -> turret slew + wheel spin + barrel recoil   (action: "move")
  soldiers  -> walk cycle + fire pose                     (actions: "walk", "fire")

Run:
  blender --background --factory-startup --python tools/anim_models.py
Outputs: GodotDrone-master/assets/vehicles_anim/*.glb
"""
from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
SRC = PROJECT / "assets" / "vehicles"
OUT = PROJECT / "assets" / "vehicles_anim"
FPS = 24


def clear() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes,
                  bpy.data.materials, bpy.data.objects):
        for item in list(block):
            try:
                block.remove(item)
            except Exception:
                pass


def import_glb(path: Path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def objects_starting(prefixes):
    out = []
    for o in bpy.data.objects:
        for p in prefixes:
            if o.name.startswith(p):
                out.append(o)
                break
    return out


def make_action(obj, name: str):
    if obj.animation_data is None:
        obj.animation_data_create()
    action = bpy.data.actions.new(name)
    obj.animation_data.action = action
    obj.rotation_mode = "XYZ"
    return action


def key_rot(obj, frame: int, axis: int, value: float) -> None:
    obj.rotation_euler[axis] = value
    obj.keyframe_insert(data_path="rotation_euler", index=axis, frame=frame)


def anim_tank(path: Path) -> int:
    objs = import_glb(path)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    if arm is None:
        arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        print("[anim] tank: no armature")
        return 0

    def bones(*parts):
        out = []
        for b in arm.pose.bones:
            low = b.name.lower()
            if all(p.lower() in low for p in parts):
                out.append(b)
        return out

    turret = bones("turret")
    barrel = bones("barrel")
    wheels = [b for b in arm.pose.bones if "wheel" in b.name.lower()]

    # Lateral (axle) axis: average offset between the L and R wheel bones.
    lateral = Vector((1.0, 0.0, 0.0))
    left = [b for b in wheels if ".l" in b.name.lower()]
    right = [b for b in wheels if ".r" in b.name.lower()]
    if left and right:
        lc = sum((b.head for b in left), Vector()) / len(left)
        rc = sum((b.head for b in right), Vector()) / len(right)
        axis = (lc - rc)
        if axis.length > 1e-4:
            lateral = axis.normalized()

    def local_axis(pb, world_axis):
        m = pb.bone.matrix_local.to_3x3()
        return (m.inverted() @ Vector(world_axis)).normalized()

    def key_quat(pb, frame, world_axis, angle):
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion(local_axis(pb, world_axis), angle)
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    arm.animation_data_create()
    act = bpy.data.actions.new("Move")
    arm.animation_data.action = act
    for frame, deg in ((1, 0.0), (24, 55.0), (48, -55.0), (72, 0.0)):
        for b in turret:
            key_quat(b, frame, (0.0, 0.0, 1.0), math.radians(deg))
    for b in wheels:
        for frame, deg in ((1, 0.0), (24, 180.0), (48, 360.0)):
            key_quat(b, frame, lateral, math.radians(deg))
    for b in barrel:
        for frame, deg in ((1, 0.0), (18, 0.0), (22, -10.0), (40, 0.0), (72, 0.0)):
            key_quat(b, frame, lateral, math.radians(deg))
    act.use_cyclic = True
    return 72


def anim_soldier(path: Path) -> int:
    objs = import_glb(path)
    armature = next((o for o in objs if o.type == "ARMATURE"), None)
    if armature is None:
        armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if armature is None:
        print("[anim] no armature in", path.name)
        return 0

    def bone(*parts):
        for b in armature.pose.bones:
            low = b.name.lower()
            if all(p.lower() in low for p in parts):
                return b
        return None

    lt, rt = bone("L", "Thigh"), bone("R", "Thigh")
    lc, rc = bone("L", "Calf"), bone("R", "Calf")
    la, ra = bone("L", "UpperArm"), bone("R", "UpperArm")

    def walk(name: str) -> None:
        armature.animation_data_create()
        act = bpy.data.actions.new(name)
        armature.animation_data.action = act
        keys = (1, 13, 25, 37, 49)          # 48-frame loop
        swing = math.radians(26.0)
        bend = math.radians(34.0)
        lthigh = (swing, -swing, -swing, swing, swing)
        rthigh = (-swing, swing, swing, -swing, -swing)
        lcalf = (0.0, bend, 0.0, 0.0, 0.0)
        rcalf = (0.0, 0.0, 0.0, bend, 0.0)
        larm = (-swing * 0.7, swing * 0.7, swing * 0.7, -swing * 0.7, -swing * 0.7)
        rarm = (swing * 0.7, -swing * 0.7, -swing * 0.7, swing * 0.7, swing * 0.7)
        for i, frame in enumerate(keys):
            for b, vals in ((lt, lthigh), (rt, rthigh), (lc, lcalf), (rc, rcalf),
                            (la, larm), (ra, rarm)):
                if b is None:
                    continue
                b.rotation_mode = "XYZ"
                b.rotation_euler[0] = vals[i]
                b.keyframe_insert(data_path="rotation_euler", index=0, frame=frame)
        act.use_cyclic = True

    def fire(name: str) -> None:
        armature.animation_data_create()
        act = bpy.data.actions.new(name)
        armature.animation_data.action = act
        for frame in (1, 4, 10):
            for b, ang in ((la, math.radians(-70.0)), (ra, math.radians(-70.0))):
                if b is None:
                    continue
                b.rotation_mode = "XYZ"
                b.rotation_euler[0] = ang + (0.0 if frame == 4 else math.radians(9.0) * (frame - 1))
                b.keyframe_insert(data_path="rotation_euler", index=0, frame=frame)

    walk("Walk")
    fire("Fire")
    return 48


def export(out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path), export_format="GLB",
        use_selection=False, export_apply=False,
        export_animations=True, export_animation_mode="ACTIONS",
        export_yup=True, export_cameras=False, export_lights=False,
    )


def do(name: str, builder) -> None:
    clear()
    src = SRC / (name + ".glb")
    if not src.exists():
        print("[anim] missing", src)
        return
    frames = builder(src)
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = max(frames, 1)
    out = OUT / (name + "_anim.glb")
    export(out)
    anims = []
    for a in bpy.data.actions:
        anims.append(a.name)
    print(f"[anim] {name}: actions={anims} -> {out.name}")


def main() -> None:
    do("low_poly_t-72_tank_-_game_ready", anim_tank)
    do("hecu_half-life", anim_soldier)
    do("alpha4_soldier_2_with_val.paranoia_mod_half_life", anim_soldier)
    print("[anim] done")


main()
