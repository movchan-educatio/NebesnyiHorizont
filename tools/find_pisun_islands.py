import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

obj3 = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(obj3.data)

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
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited:
                visited.add(o)
                stack.append(o)
    islands.append(island)

print(f"Object_3 islands count: {len(islands)}")
for idx, isl in enumerate(islands):
    vcos = [v.co for v in isl]
    cen = sum(vcos, mathutils.Vector((0,0,0))) / len(vcos)
    dx = max(c.x for c in vcos) - min(c.x for c in vcos)
    dy = max(c.y for c in vcos) - min(c.y for c in vcos)
    dz = max(c.z for c in vcos) - min(c.z for c in vcos)
    print(f"Island {idx}: verts={len(isl)}, center=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f}), dims=[{dx:.4f}, {dy:.4f}, {dz:.4f}], Z_range=[{min(c.z for c in vcos):.4f}, {max(c.z for c in vcos):.4f}]")
bm.free()
