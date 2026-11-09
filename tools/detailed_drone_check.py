import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

models_dir = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm'
files = [
    (0, 'holka.glb'),
    (1, 'pinapipe.glb'),
    (2, 'avata2.glb'),
    (3, 'pisun_vtol.glb'),
    (4, 'peleng.glb'),
    (5, 'grim7.glb'),
    (6, 'grim7m.glb'),
    (7, 'strila8.glb'),
    (8, 'falcon_x.glb'),
    (9, 'quad5_custom.glb')
]

for idx, f in files:
    path = os.path.join(models_dir, f)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    print(f"\n================================ PRESET {idx}: {f} ================================")
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
            cx = sum((c.x for c in bb)) / 8.0
            cy = sum((c.y for c in bb)) / 8.0
            cz = sum((c.z for c in bb)) / 8.0
            dx = max((c.x for c in bb)) - min((c.x for c in bb))
            dy = max((c.y for c in bb)) - min((c.y for c in bb))
            dz = max((c.z for c in bb)) - min((c.z for c in bb))
            loc = o.matrix_world.translation
            print(f"  MESH: {o.name:32} parent={(o.parent.name if o.parent else 'None'):20} origin=({loc.x:+.4f}, {loc.y:+.4f}, {loc.z:+.4f}) bbox_center=({cx:+.4f}, {cy:+.4f}, {cz:+.4f}) size=({dx:.4f}, {dy:.4f}, {dz:.4f})")
