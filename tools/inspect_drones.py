import bpy
import sys
import os

def inspect_glb(glb_path):
    print("=" * 80)
    print(f"INSPECTING: {glb_path}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    for obj in bpy.data.objects:
        p_name = obj.parent.name if obj.parent else "None"
        bbox = [list(corner) for corner in obj.bound_box] if obj.type == 'MESH' else None
        dim = list(obj.dimensions) if obj.type == 'MESH' else None
        vcount = len(obj.data.vertices) if obj.type == 'MESH' else 0
        print(f"OBJ: {obj.name} | Type: {obj.type} | Parent: {p_name} | Loc: {list(obj.location)} | RotEuler: {list(obj.rotation_euler)} | Scale: {list(obj.scale)} | Verts: {vcount} | Dim: {dim}")
        if "prop" in obj.name.lower() or "motor" in obj.name.lower() or "ring" in obj.name.lower():
            if obj.type == 'MESH':
                # Compute center of vertices in local and world space
                verts = [v.co for v in obj.data.vertices]
                if verts:
                    local_center = sum(verts, bpy.mathutils.Vector((0,0,0))) / len(verts)
                    world_center = obj.matrix_world @ local_center
                    print(f"   -> Local vert center: {list(local_center)} | World center: {list(world_center)}")
                    min_z = min(v.z for v in verts)
                    max_z = max(v.z for v in verts)
                    min_x = min(v.x for v in verts)
                    max_x = max(v.x for v in verts)
                    min_y = min(v.y for v in verts)
                    max_y = max(v.y for v in verts)
                    print(f"   -> Local bounds: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}]")

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
for fname in ["avata2.glb", "pisun_vtol.glb", "falcon_x.glb", "peleng.glb", "holka.glb"]:
    inspect_glb(os.path.join(base_dir, fname))
