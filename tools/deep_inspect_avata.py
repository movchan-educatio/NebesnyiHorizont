import bpy
import mathutils
import sys
import os
import bmesh

def inspect_avata2(glb_path):
    print("=" * 80)
    print("DEEP INSPECTION AVATA2:", glb_path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue
        print(f"\nOBJECT: {obj.name} | Loc: {list(obj.location)} | Rot: {list(obj.rotation_euler)} | Dim: {list(obj.dimensions)} | Verts: {len(obj.data.vertices)}")
        # Check connected components / islands
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        
        # Find islands
        visited = set()
        islands = []
        for v in bm.verts:
            if v in visited:
                continue
            island = []
            stack = [v]
            visited.add(v)
            while stack:
                curr = stack.pop()
                island.append(curr)
                for edge in curr.link_edges:
                    other = edge.other_vert(curr)
                    if other not in visited:
                        visited.add(other)
                        stack.append(other)
            islands.append(island)
        
        bm.free()
        
        print(f"   -> Islands count: {len(islands)}")
        # Print top 5 largest islands by vertex count
        island_sizes = sorted([len(isl) for isl in islands], reverse=True)
        print(f"   -> Largest island sizes: {island_sizes[:8]}")
        
        # Check if any island looks like a 3-blade or 2-blade propeller
        if "prop" in obj.name.lower() or "ring" in obj.name.lower() or "motor" in obj.name.lower() or "hard" in obj.name.lower():
            # For each island in top 15, calculate bounds
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            visited = set()
            idx = 0
            for v in bm.verts:
                if v in visited:
                    continue
                island = []
                stack = [v]
                visited.add(v)
                while stack:
                    curr = stack.pop()
                    island.append(curr)
                    for edge in curr.link_edges:
                        other = edge.other_vert(curr)
                        if other not in visited:
                            visited.add(other)
                            stack.append(other)
                
                # Check bounds of island
                coords = [v.co for v in island]
                dx = max(c.x for c in coords) - min(c.x for c in coords)
                dy = max(c.y for c in coords) - min(c.y for c in coords)
                dz = max(c.z for c in coords) - min(c.z for c in coords)
                max_d = max(dx, dy, dz)
                # Avata 2 propeller is around 0.06 - 0.08m (2.8 - 3.0 inch ~ 75mm)
                if 0.04 < max_d < 0.12 or len(island) > 200:
                    cen = sum(coords, mathutils.Vector((0,0,0))) / len(coords)
                    world_cen = obj.matrix_world @ cen
                    print(f"      [Island {idx}] verts={len(island)}: dims=[{dx:.4f}, {dy:.4f}, {dz:.4f}] world_center=[{world_cen.x:.4f}, {world_cen.y:.4f}, {world_cen.z:.4f}]")
                idx += 1
            bm.free()

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
inspect_avata2(os.path.join(base_dir, "avata2.glb"))
