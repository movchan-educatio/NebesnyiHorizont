import bpy
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "Assets", "vehicles", "apache_hecu_half-life.glb")
OUT = os.path.join(ROOT, "Assets", "vehicles", "apache_hecu_half-life_mobile.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
before = len(meshes)

# Keep rotor/blade parts separate for the runtime rotor pivot detector. Merge
# all duplicate static parts which use the same material into one mesh/object.
rotor_words = ("rotor", "blade")
groups = {}
preserved = []
for obj in meshes:
    mat_names = [m.name.lower() for m in obj.data.materials if m]
    name = obj.name.lower()
    if any(w in name for w in rotor_words) or any(
        any(w in m for w in rotor_words) for m in mat_names
    ):
        preserved.append(obj)
        continue
    key = mat_names[0] if mat_names else "__no_material__"
    groups.setdefault(key, []).append(obj)

for key, objects in groups.items():
    if len(objects) < 2:
        continue
    # Apply imported glTF child transforms before joining so Blender does not
    # double-apply origins/parents; the mobile GLB must retain source bounds.
    for obj in objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    active = objects[0]
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    safe = re.sub(r"[^A-Za-z0-9_]+", "_", key).strip("_")[:48] or "Material"
    active.name = "MobileMerged_" + safe
    if active.data:
        active.data.name = active.name + "Mesh"

after = len([o for o in bpy.context.scene.objects if o.type == "MESH"])
bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type in {"MESH", "EMPTY", "ARMATURE"}:
        obj.select_set(True)
bpy.context.view_layer.objects.active = next(
    (o for o in bpy.context.scene.objects if o.type == "EMPTY"),
    next((o for o in bpy.context.scene.objects if o.type == "MESH"), None),
)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_cameras=False,
    export_lights=False,
    export_animations=False,
)
print("[APACHE_OPT] before_objects", before)
print("[APACHE_OPT] after_objects", after)
print("[APACHE_OPT] preserved_rotor_objects", len(preserved))
print("[APACHE_OPT] output_bytes", os.path.getsize(OUT))
