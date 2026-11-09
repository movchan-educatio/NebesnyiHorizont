import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

prop = bpy.data.objects.get("propeller_FR")
print(f"propeller_FR verts: {len(prop.data.vertices)}")
bm = bmesh.new()
bm.from_mesh(prop.data)

# Find islands in propeller_FR
visited = set()
islands = []
for v in bm.verts:
    if v in visited:
        continue
    isl = []
    stack = [v]
    visited.add(v)
    while stack:
        curr = stack.pop()
        isl.append(curr)
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited:
                visited.add(o)
                stack.append(o)
    islands.append(isl)

print(f"propeller_FR has {len(islands)} islands:")
for idx, isl in enumerate(islands):
    vcos = [v.co for v in isl]
    cen = sum(vcos, mathutils.Vector((0,0,0))) / len(vcos)
    dx = max(c.x for c in vcos) - min(c.x for c in vcos)
    dy = max(c.y for c in vcos) - min(c.y for c in vcos)
    dz = max(c.z for c in vcos) - min(c.z for c in vcos)
    print(f"   isl {idx}: verts={len(isl)}, dims=[{dx:.4f}, {dy:.4f}, {dz:.4f}], center=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
bm.free()
