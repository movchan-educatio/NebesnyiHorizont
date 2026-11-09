import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\grim7.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

print("=== GRIM7 OBJECTS ===")
for o in bpy.context.scene.objects:
    mw = o.matrix_world
    bb = [mw @ mathutils.Vector(c) for c in o.bound_box] if o.type == 'MESH' else []
    cen = sum(bb, mathutils.Vector()) / 8.0 if bb else mw.translation
    sz = mathutils.Vector((max(c.x for c in bb)-min(c.x for c in bb), max(c.y for c in bb)-min(c.y for c in bb), max(c.z for c in bb)-min(c.z for c in bb))) if bb else mathutils.Vector()
    print(f"  {repr(o.name):35} type={o.type:6} loc=({mw.translation.x:+.4f}, {mw.translation.y:+.4f}, {mw.translation.z:+.4f}) cen=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f}) size=({sz.x:.4f}, {sz.y:.4f}, {sz.z:.4f})")
