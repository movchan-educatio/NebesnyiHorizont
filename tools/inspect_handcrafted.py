import bpy, json, sys

path = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
rows = []
for ob in bpy.context.scene.objects:
    if ob.type != 'MESH':
        continue
    mats = [m.name for m in ob.data.materials if m]
    rows.append({
        "name": ob.name,
        "verts": len(ob.data.vertices),
        "polys": len(ob.data.polygons),
        "mats": mats,
        "loc": [round(v, 2) for v in ob.location],
        "dim": [round(v, 2) for v in ob.dimensions],
    })
print("OBJECTS", len(rows))
for r in rows:
    print(r)
print("MATERIALS")
for m in bpy.data.materials:
    if m.users == 0:
        continue
    print(m.name, [n.type for n in m.node_tree.nodes if n.type == 'TEX_IMAGE'] if m.use_nodes else None)
