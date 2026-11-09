## assemble_city.py — build ONE clean single-level map from donor street.glb:
## flat ground, grounded blocks, no decks/sheets/duplicates.
## Run: blender --background --python assemble_city.py
## Output: Assets/sceneries/city/merged_city.glb (+ merged_city.blend in root).
import bpy
import os

PROJ_DIR = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), ".."))
CITY_DIR = os.path.join(PROJ_DIR, "Assets", "sceneries", "city")
SRC = os.path.join(CITY_DIR, "street.glb")
GLB_PATH = os.path.join(CITY_DIR, "merged_city.glb")
BLEND_PATH = os.path.join(os.path.dirname(PROJ_DIR), "merged_city.blend")


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def world_min_z(obj):
    if obj.type != "MESH" or not obj.data or not obj.data.vertices:
        return None
    return min((obj.matrix_world @ v.co).z for v in obj.data.vertices)


def world_size(obj):
    if obj.type != "MESH" or not obj.data or not obj.data.vertices:
        return None
    ws = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = [min(v[i] for v in ws) for i in range(3)]
    mx = [max(v[i] for v in ws) for i in range(3)]
    return [mx[i] - mn[i] for i in range(3)]


clear()
bpy.ops.import_scene.gltf(filepath=SRC)
bpy.context.view_layer.update()
# Flatten hierarchy: keep world transforms, drop all parents (importers
# often wrap nodes in rotated correction empties).
for o in list(bpy.context.scene.objects):
    if o.parent is not None:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
bpy.context.view_layer.update()
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
print("imported meshes:", len(meshes))

# --- 1. ground planes: keep the single flat one, delete the rest
grounds = []
for o in meshes:
    s = world_size(o)
    if s is not None and s[0] > 7000 and s[1] > 7000:
        grounds.append(o)
print("ground planes found:", [o.name for o in grounds])
kept = None
for o in grounds:
    if kept is None and abs(world_size(o)[2]) < 0.01:
        kept = o  # keep the first perfectly flat one
if kept is None and grounds:
    kept = grounds[0]
for o in grounds:
    if o != kept:
        bpy.data.objects.remove(o, do_unlink=True)
print("kept ground:", kept.name if kept else "NONE")

kept_names = {kept.name}
# Pass 1: classify with fresh matrices (no mutation yet).
to_delete = []
to_drop = []
for o in list(bpy.context.scene.objects):
    if o.type != "MESH" or o.name in kept_names:
        continue
    s = world_size(o)
    if s is None:
        continue
    sx, sy, sz = s
    # thin wide decks / sheets / duplicate slabs -> delete
    if (sz < 6.0 and max(sx, sy) > 400.0) or (min(sx, sy, sz) < 1.0 and max(sx, sy, sz) > 400.0):
        to_delete.append(o)
        continue
    # floating blocks -> drop onto the ground plane
    mnz = world_min_z(o)
    if mnz is not None and mnz > 1.0:
        to_drop.append((o, mnz))
for o in to_delete:
    bpy.data.objects.remove(o, do_unlink=True)
deleted = len(to_delete)
# Pass 2: pure translations (parents already cleared, location == world).
bpy.context.view_layer.update()
for o, mnz in to_drop:
    o.location.z -= mnz
dropped = len(to_drop)

rest = [o for o in bpy.context.scene.objects if o.type == "MESH"]
print("deleted junk:", deleted, " grounded:", dropped, " kept:", len(rest))

# --- 2. single root + export
root = bpy.data.objects.new("MergedCity", None)
bpy.context.scene.collection.objects.link(root)
for o in rest:
    o.parent = root

bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_yup=True,
    export_cameras=False,
    export_lights=False,
    export_extras=False,
)
print("WROTE", GLB_PATH)
