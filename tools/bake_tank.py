import bpy
import os

SRC = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\assets\vehicles\low_poly_t-72_tank_-_game_ready.glb"
DST = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\assets\vehicles\t72_baked.glb"

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.meshes):
    bpy.data.meshes.remove(block)
for block in list(bpy.data.armatures):
    bpy.data.armatures.remove(block)

bpy.ops.import_scene.gltf(filepath=SRC)

# Bake the evaluated (skinned) pose into plain meshes so Godot sees the same
# silhouette the GLB viewer shows, with sane bounds.
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for ob in list(bpy.context.scene.objects):
    if ob.type != 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)

bpy.ops.object.select_all(action='DESELECT')
for ob in meshes:
    if ob.name not in bpy.context.scene.objects:
        continue
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.convert(target='MESH')
    except Exception as exc:
        print("[BAKE] convert failed", ob.name, exc)

# Apply transforms so the exported GLB is clean.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True)
print("[BAKE] wrote", DST, "size", os.path.getsize(DST))
