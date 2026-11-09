import bpy
import bmesh
import mathutils
import os

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

# -------------------------------------------------------------
# 1. FIX FALCON-X
# -------------------------------------------------------------
print("=" * 80)
print("APPLYING PERFECT FIX TO FALCON-X")
print("=" * 80)

falcon_path = os.path.join(base_dir, "falcon_x.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=falcon_path)

falcon_targets = {
    "propeller_FL": mathutils.Vector((-0.0996, -0.0496, 0.0150)),
    "propeller_FR": mathutils.Vector(( 0.0996, -0.0496, 0.0150)),
    "propeller_BL": mathutils.Vector((-0.0952,  0.0636, 0.1080)),
    "propeller_BR": mathutils.Vector(( 0.0954,  0.0636, 0.1080)),
}

for pname, tpos in falcon_targets.items():
    p_obj = bpy.data.objects.get(pname)
    if not p_obj:
        print(f"Missing {pname}!")
        continue
    verts = [v.co for v in p_obj.data.vertices]
    inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.012]
    hub_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner) if inner else mathutils.Vector((0,0,0))
    min_z = min(v.z for v in verts)
    for v in p_obj.data.vertices:
        v.co.x -= hub_cen.x
        v.co.y -= hub_cen.y
        v.co.z -= min_z
    p_obj.data.update()
    p_obj.location = tpos
    p_obj.rotation_euler = (0, 0, 0)
    print(f"Falcon-X: Placed {pname} at {list(round(c, 4) for c in tpos)}")

bpy.ops.export_scene.gltf(
    filepath=falcon_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Exported fixed falcon_x.glb")

# -------------------------------------------------------------
# 2. FIX HOLKA
# -------------------------------------------------------------
print("=" * 80)
print("APPLYING PERFECT FIX TO HOLKA")
print("=" * 80)

holka_path = os.path.join(base_dir, "holka.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=holka_path)

holka_targets = {
    "propeller_FR": mathutils.Vector(( 0.0696,  0.0716, -0.0270)),
    "propeller_FL": mathutils.Vector((-0.0696,  0.0716, -0.0270)),
    "propeller_BR": mathutils.Vector(( 0.0702, -0.0749, -0.0270)),
    "propeller_BL": mathutils.Vector((-0.0667, -0.0714, -0.0270)),
}

for pname, tpos in holka_targets.items():
    p_obj = bpy.data.objects.get(pname)
    if not p_obj:
        print(f"Missing {pname}!")
        continue
    verts = [v.co for v in p_obj.data.vertices]
    inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.012]
    hub_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner) if inner else mathutils.Vector((0,0,0))
    min_z = min(v.z for v in verts)
    for v in p_obj.data.vertices:
        v.co.x -= hub_cen.x
        v.co.y -= hub_cen.y
        v.co.z -= min_z
    p_obj.data.update()
    p_obj.location = tpos
    p_obj.rotation_euler = (0, 0, 0)
    print(f"Holka: Placed {pname} at {list(round(c, 4) for c in tpos)}")

bpy.ops.export_scene.gltf(
    filepath=holka_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Exported fixed holka.glb")
