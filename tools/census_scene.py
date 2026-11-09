## census_scene.py — print world bounds for every mesh in the CURRENT scene.
import bpy

bpy.context.view_layer.update()
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
print("COUNT", len(ms))
for o in sorted(ms, key=lambda x: x.name):
    if not o.data.vertices:
        print(o.name, "NOVERTS")
        continue
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = [round(min(v[i] for v in ws), 1) for i in range(3)]
    mx = [round(max(v[i] for v in ws), 1) for i in range(3)]
    print("%s size=(%.0f %.0f %.0f) min=(%.0f %.0f %.0f)" % (
        o.name[:44], mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2],
        mn[0], mn[1], mn[2]))
