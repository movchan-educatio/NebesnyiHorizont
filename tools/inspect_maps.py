## inspect_maps.py — dump object names + bounds for donor GLBs.
## Run: blender --background --python inspect_maps.py
import bpy
import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "Assets", "sceneries", "city")
BASE = os.path.normpath(BASE)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def bounds_world(obj):
    ws = [obj.matrix_world @ v.co for v in obj.data.vertices] if obj.data and hasattr(obj.data, "vertices") else []
    if not ws:
        return None
    mn = [min(v[i] for v in ws) for i in range(3)]
    mx = [max(v[i] for v in ws) for i in range(3)]
    return mn, mx


for fname in ("street.glb", "west_street.glb", "street_city_buildings_8.glb"):
    path = os.path.join(BASE, fname)
    if not os.path.exists(path):
        print("MISSING", fname)
        continue
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    print("=" * 70)
    print("FILE:", fname)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print("mesh objects:", len(meshes))
    mats = set()
    for o in meshes:
        for s in o.material_slots:
            if s.material:
                mats.add(s.material.name)
    print("materials:", len(mats))
    items = []
    for o in meshes:
        b = bounds_world(o)
        if b is None:
            continue
        size = [b[1][i] - b[0][i] for i in range(3)]
        items.append((max(size), o.name, size, b[0]))
    items.sort(reverse=True)
    print("--- 25 largest objects (maxdim, name, size, min) ---")
    for maxd, name, size, mn in items[:25]:
        print("  %8.1f | %s | (%7.1f %7.1f %7.1f) @ (%8.1f %8.1f %8.1f)"
              % (maxd, name[:60], size[0], size[1], size[2], mn[0], mn[1], mn[2]))
    print("--- materials ---")
    for m in sorted(mats)[:40]:
        print("  ", m[:70])
