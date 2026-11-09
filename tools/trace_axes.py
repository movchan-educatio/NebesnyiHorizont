## trace_axes.py — find which assembly step swaps Y/Z.
import bpy
import os

CITY = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "Assets", "sceneries", "city"))
SRC = os.path.join(CITY, "street.glb")


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def bounds(o):
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = [min(v[i] for v in ws) for i in range(3)]
    mx = [max(v[i] for v in ws) for i in range(3)]
    return ([round(mx[i] - mn[i], 1) for i in range(3)],
            [round(mn[i], 1) for i in range(3)])


def show(tag):
    o = bpy.data.objects.get("Material3.002")
    if o is None:
        print(tag, "MISSING")
        return
    print(tag, "size/min=", bounds(o),
          "rot=", tuple(round(float(r), 3) for r in o.rotation_euler),
          "loc=", tuple(round(float(v), 1) for v in o.location),
          "parent=", o.parent.name if o.parent else None)


clear()
bpy.ops.import_scene.gltf(filepath=SRC)
show("after-import")
o = bpy.data.objects.get("Material3.002")
ws = [o.matrix_world @ v.co for v in o.data.vertices]
mnz = min(v.z for v in ws)
o.location.z -= mnz
show("after-drop   ")
root = bpy.data.objects.new("R", None)
bpy.context.scene.collection.objects.link(root)
for x in bpy.context.scene.objects:
    if x.type == "MESH":
        x.parent = root
show("after-parent ")
