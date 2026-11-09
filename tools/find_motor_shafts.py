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
    
    print("\n" + "="*70)
    print(f"PRESET {idx}: {f}")
    
    # 1. Look for existing propeller meshes
    prop_nodes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and ('propeller' in o.name.lower() or 'vint' in o.name.lower() or 'blade' in o.name.lower()) and 'ring' not in o.name.lower()]
    print(f"  Found {len(prop_nodes)} propeller meshes:")
    for p in prop_nodes:
        mw = p.matrix_world
        bb = [mw @ mathutils.Vector(c) for c in p.bound_box]
        cen = sum(bb, mathutils.Vector()) / 8.0
        print(f"    '{p.name}' loc=({p.location.x:+.4f}, {p.location.y:+.4f}, {p.location.z:+.4f}) bbox_center=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f})")
        
    # 2. Look for motor nodes or empty markers
    motor_nodes = [o for o in bpy.context.scene.objects if ('motor' in o.name.lower() or 'stator' in o.name.lower() or 'bell' in o.name.lower() or 'rotor' in o.name.lower()) and 'prop' not in o.name.lower()]
    print(f"  Found {len(motor_nodes)} motor-related objects:")
    for m in motor_nodes[:12]:
        mw = m.matrix_world
        print(f"    '{m.name}' type={m.type} loc=({mw.translation.x:+.4f}, {mw.translation.y:+.4f}, {mw.translation.z:+.4f})")
