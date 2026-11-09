## census_glb.py — print world bounds + transforms for every mesh in a GLB.
## Run: blender --background --python census_glb.py -- <path.glb>
import bpy
import sys

path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=path)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
print("COUNT", len(ms))
for o in sorted(ms, key=lambda x: x.name):
    if not o.data.vertices:
        print(o.name, "NOVERTS rot=", tuple(o.rotation_euler), "loc=", tuple(o.location))
        continue
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = [round(min(v[i] for v in ws), 1) for i in range(3)]
    mx = [round(max(v[i] for v in ws), 1) for i in range(3)]
    print("%s size=(%.0f %.0f %.0f) min=(%.0f %.0f %.0f) rot=(%.2f %.2f %.2f)" % (
        o.name[:44], mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2],
        mn[0], mn[1], mn[2],
        o.rotation_euler[0], o.rotation_euler[1], o.rotation_euler[2]))
