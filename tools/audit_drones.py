import bpy, os, sys
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
    if not os.path.exists(path):
        print(f"=== [{idx}] {f} NOT FOUND ===")
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    print("=" * 60)
    print(f"PRESET {idx}: {f}")
    
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    prop_objs = [o for o in bpy.context.scene.objects if any(k in o.name.lower() for k in ['prop', 'vint', 'blade'])]
    
    print(f"  Total meshes: {len(mesh_objs)}, prop objects: {len(prop_objs)}")
    for o in bpy.context.scene.objects:
        nl = o.name.lower()
        if any(k in nl for k in ['prop', 'vint', 'blade', 'rotor', 'motor', 'stator', 'bell']):
            mw = o.matrix_world.translation
            pname = o.parent.name if o.parent else "None"
            print(f"    {o.name:32} {o.type:6} parent={pname:20} world_loc=({mw.x:+.4f}, {mw.y:+.4f}, {mw.z:+.4f})")
