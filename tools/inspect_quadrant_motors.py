import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

models_dir = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm'

def inspect_motors_of(fname):
    path = os.path.join(models_dir, fname)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print("\n" + "="*60)
    print("FILE:", fname)
    
    # Check all objects for motor/rotor or geometry clusters
    for o in bpy.context.scene.objects:
        nl = o.name.lower()
        if o.type == 'MESH':
            # Check if this mesh contains separate motor islands
            # by clustering vertices in 4 quadrants (FL, FR, BL, BR)
            # if the mesh is body or frame
            verts = o.data.vertices
            print(f"Mesh: {o.name} verts={len(verts)}")
            for quad, (sx, sy) in [('FL', (-1, 1)), ('FR', (1, 1)), ('BL', (-1, -1)), ('BR', (1, -1))]:
                q_verts = [v.co for v in verts if (v.co.x * sx > 0.02) and (v.co.y * sy > 0.02)]
                if q_verts:
                    # top 20 highest Z vertices in this quadrant
                    q_sorted = sorted(q_verts, key=lambda v: v.z, reverse=True)
                    top_z = q_sorted[0].z
                    top_pts = [v for v in q_sorted if abs(v.z - top_z) < 0.005]
                    cen = sum(top_pts, mathutils.Vector()) / len(top_pts)
                    mw = o.matrix_world
                    w_cen = mw @ cen
                    print(f"   {quad}: top_z={top_z:.4f} local_cen=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f}) world=({w_cen.x:.4f}, {w_cen.y:.4f}, {w_cen.z:.4f})")

for f in ['holka.glb', 'pinapipe.glb', 'avata2.glb', 'pisun_vtol.glb', 'peleng.glb', 'grim7m.glb']:
    inspect_motors_of(f)
