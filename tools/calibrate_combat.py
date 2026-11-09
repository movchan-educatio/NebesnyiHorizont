"""Import the combat FPV drone GLB and report the bounds of its parts, so the
in-game FPV camera and the drop animation can be placed correctly."""
import os
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
GLB = PROJECT / "assets" / "drones" / "combat__fpv_drone.glb"


def world_aabb(objects):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    found = False
    for obj in objects:
        if obj.type != "MESH":
            continue
        found = True
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); lo.z = min(lo.z, p.z)
            hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y); hi.z = max(hi.z, p.z)
    if not found:
        return None, None
    return lo, hi


def report(label, objects):
    lo, hi = world_aabb(objects)
    if lo is None:
        print(f"[calib] {label}: (no meshes)")
        return
    size = hi - lo
    center = (lo + hi) * 0.5
    print(f"[calib] {label}: lo={tuple(round(v,3) for v in lo)} "
          f"hi={tuple(round(v,3) for v in hi)} size={tuple(round(v,3) for v in size)} "
          f"center={tuple(round(v,3) for v in center)}")


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(GLB))

all_objs = list(bpy.data.objects)
report("ALL", all_objs)

for name in ("MORKOVKA", "frame_low"):
    root = next((o for o in all_objs if o.name == name), None)
    if root is None:
        print(f"[calib] {name}: not found")
        continue
    objs = [o for o in all_objs if o.name == name or o.name.startswith(name + "_")]
    # include descendants
    def descendants(node, out):
        for c in node.children:
            out.append(c)
            descendants(c, out)
    kids = []
    descendants(root, kids)
    report(name, [root] + kids)

print("[calib] top-level parts:", [o.name for o in all_objs if o.parent is None])
