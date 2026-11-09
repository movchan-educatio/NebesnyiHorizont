import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

models_dir = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm'

def analyze_drone(idx, fname):
    path = os.path.join(models_dir, fname)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    print("\n" + "="*70)
    print(f"ANALYZE [{idx}] {fname}")
    
    all_meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print(f"Total meshes: {len(all_meshes)}")
    
    # Print all mesh names and their bounding centers
    for m in all_meshes:
        bb = [m.matrix_world @ mathutils.Vector(c) for c in m.bound_box]
        cen = sum(bb, mathutils.Vector()) / 8.0
        sz = mathutils.Vector((max(c.x for c in bb)-min(c.x for c in bb), max(c.y for c in bb)-min(c.y for c in bb), max(c.z for c in bb)-min(c.z for c in bb)))
        is_prop = any(k in m.name.lower() for k in ['prop', 'vint', 'blade'])
        tag = "[PROP]" if is_prop else ""
        print(f"  {tag:6} {m.name:32} parent={(m.parent.name if m.parent else 'None'):16} cen=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f}) sz=({sz.x:.4f}, {sz.y:.4f}, {sz.z:.4f})")

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
    analyze_drone(idx, f)
