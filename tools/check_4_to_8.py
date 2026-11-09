import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

models_dir = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm'
files = [
    (4, 'peleng.glb'),
    (5, 'grim7.glb'),
    (6, 'grim7m.glb'),
    (7, 'strila8.glb'),
    (8, 'falcon_x.glb')
]

for idx, f in files:
    path = os.path.join(models_dir, f)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    print(f"\n================ PRESET {idx}: {f} ================")
    props = []
    motors = []
    
    for o in bpy.context.scene.objects:
        nl = o.name.lower()
        bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
        cx = sum((c.x for c in bb)) / 8.0
        cy = sum((c.y for c in bb)) / 8.0
        cz = sum((c.z for c in bb)) / 8.0
        dx = max((c.x for c in bb)) - min((c.x for c in bb))
        dy = max((c.y for c in bb)) - min((c.y for c in bb))
        dz = max((c.z for c in bb)) - min((c.z for c in bb))
        loc = o.matrix_world.translation
        
        if o.type == 'MESH':
            if any(k in nl for k in ['prop', 'vint', 'blade', 'material_002']) and 'ring' not in nl:
                props.append((o.name, loc, mathutils.Vector((cx, cy, cz)), mathutils.Vector((dx, dy, dz))))
            elif any(k in nl for k in ['motor', 'stator', 'bell', 'rotor']):
                motors.append((o.name, loc, mathutils.Vector((cx, cy, cz)), mathutils.Vector((dx, dy, dz))))
    
    print(f"  PROPELLERS ({len(props)}):")
    for name, loc, cen, sz in props:
        print(f"    {name:28} origin=({loc.x:+.4f}, {loc.y:+.4f}, {loc.z:+.4f}) bbox_center=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f}) size=({sz.x:.4f}, {sz.y:.4f}, {sz.z:.4f})")
        
    print(f"  MOTORS ({len(motors)}):")
    for name, loc, cen, sz in motors[:10]:
        print(f"    {name:28} origin=({loc.x:+.4f}, {loc.y:+.4f}, {loc.z:+.4f}) bbox_center=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f}) size=({sz.x:.4f}, {sz.y:.4f}, {sz.z:.4f})")
