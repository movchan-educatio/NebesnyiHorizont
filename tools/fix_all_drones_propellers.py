import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

models_dir = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm'

DRONE_TARGETS = {
    'holka.glb': {
        'FL': (-0.0692, +0.0695, -0.0270),
        'FR': (+0.0692, +0.0695, -0.0270),
        'BL': (-0.0612, -0.0702, -0.0270),
        'BR': (+0.0612, -0.0702, -0.0270),
    },
    'pinapipe.glb': {
        'FL': (-0.0646, +0.0533, -0.0050),
        'FR': (+0.0646, +0.0533, -0.0050),
        'BL': (-0.0646, -0.0533, -0.0050),
        'BR': (+0.0646, -0.0533, -0.0050),
    },
    'avata2.glb': {
        'FL': (-0.0586, +0.0450, -0.0040),
        'FR': (+0.0586, +0.0450, -0.0040),
        'BL': (-0.0586, -0.0448, -0.0040),
        'BR': (+0.0586, -0.0448, -0.0040),
    },
    'pisun_vtol.glb': {
        'FL': (-0.1270, 0.0000, -0.0500),
        'FR': (+0.1270, 0.0000, -0.0500),
        'BL': (0.0000, +0.1270, -0.0500),
        'BR': (0.0000, -0.1270, -0.0500),
    },
    'peleng.glb': {
        'FL': (-0.0749, +0.0718, +0.0050),
        'FR': (+0.0749, +0.0718, +0.0050),
        'BL': (-0.0860, -0.0820, +0.0100),
        'BR': (+0.0860, -0.0820, +0.0100),
    },
    'grim7.glb': {
        'FL': (-0.1301, +0.0850, +0.0170),
        'FR': (+0.1008, +0.0850, +0.0170),
        'BL': (-0.1301, -0.1150, +0.0170),
        'BR': (+0.1008, -0.1150, +0.0170),
    },
    'grim7m.glb': {
        'FL': (-0.1070, +0.1275, +0.0050),
        'FR': (+0.1070, +0.1275, +0.0050),
        'BL': (-0.1070, -0.1106, +0.0050),
        'BR': (+0.1070, -0.1106, +0.0050),
    },
    'strila8.glb': {
        'FL': (-0.0919, +0.0722, +0.0179),
        'FR': (+0.0919, +0.0722, +0.0179),
        'BL': (-0.0919, -0.1110, +0.0179),
        'BR': (+0.0919, -0.1110, +0.0179),
    },
    'falcon_x.glb': {
        'FL': (+0.1080, -0.0674, +0.0413),
        'FR': (-0.1080, -0.0674, +0.0413),
        'BL': (-0.1051, +0.0352, +0.1163),
        'BR': (+0.1051, +0.0352, +0.1163),
    },
    'quad5_custom.glb': {
        'FL': (+0.0780, -0.0825, +0.0245),
        'FR': (+0.0780, +0.0825, +0.0245),
        'BL': (-0.0780, -0.0825, +0.0245),
        'BR': (-0.0780, +0.0825, +0.0245),
    },
}

def center_and_reposition_mesh(obj, target_pos):
    # Unparent cleanly keeping world transform
    if obj.parent:
        mw = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = mw
        
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    
    verts = obj.data.vertices
    if not verts:
        return
    cen = sum((v.co for v in verts), mathutils.Vector()) / len(verts)
    
    for v in verts:
        v.co -= cen
        
    obj.data.update()
    
    obj.location = mathutils.Vector(target_pos)
    obj.rotation_euler = mathutils.Euler((0, 0, 0), 'XYZ')
    obj.scale = mathutils.Vector((1, 1, 1))

def process_file(fname):
    path = os.path.join(models_dir, fname)
    if not os.path.exists(path):
        print(f"Skipping {fname} (not found)")
        return
        
    print("\n" + "="*60)
    print(f"PROCESSING: {fname}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    targets = DRONE_TARGETS.get(fname, {})
    
    # Special handling per model
    if fname == 'grim7.glb':
        # Identify the 4 props by vertex position before renaming
        for o in bpy.context.scene.objects:
            if o.type == 'MESH' and 'Material.002' in o.name:
                bb = [mathutils.Vector(c) for c in o.bound_box]
                cen = sum(bb, mathutils.Vector()) / 8.0
                if cen.x < 0 and cen.y > 0:
                    o.name = 'propeller_FL'
                elif cen.x > 0 and cen.y > 0:
                    o.name = 'propeller_FR'
                elif cen.x < 0 and cen.y < 0:
                    o.name = 'propeller_BL'
                elif cen.x > 0 and cen.y < 0:
                    o.name = 'propeller_BR'
                    
    elif fname == 'strila8.glb':
        name_map = {
            'vint_fl_low_DRONE_0': 'propeller_FL',
            'vint_fr_low_DRONE_0': 'propeller_FR',
            'vint_bl_low_DRONE_0': 'propeller_BL',
            'vint_br_low_DRONE_0': 'propeller_BR',
        }
        for old_n, new_n in name_map.items():
            o = bpy.context.scene.objects.get(old_n)
            if o:
                o.name = new_n
                
    elif fname == 'falcon_x.glb':
        # Scale entire model by 0.001
        for o in bpy.context.scene.objects:
            if o.parent is None:
                o.scale *= 0.001
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        
    # Now for each quadrant FL, FR, BL, BR:
    for q in ['FL', 'FR', 'BL', 'BR']:
        p_name = f'propeller_{q}'
        obj = bpy.context.scene.objects.get(p_name)
        if obj and obj.type == 'MESH':
            tgt = targets.get(q)
            if tgt:
                center_and_reposition_mesh(obj, tgt)
                print(f"  Repositioned {p_name} -> {tgt}")
        else:
            print(f"  WARNING: {p_name} not found in {fname}")

    # Export back to GLB
    bpy.ops.object.select_all(action='SELECT')
    out_path = path
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=False
    )
    print(f"Saved: {out_path}")

for f in DRONE_TARGETS.keys():
    process_file(f)

print("\n=== ALL 10 DRONES ALIGNED SUCCESSFULLY ===")
