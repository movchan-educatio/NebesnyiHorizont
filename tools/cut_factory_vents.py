import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

obj = bpy.data.objects.get("factory_facade_detail")
if obj is None:
    raise SystemExit("[VENTCUT] factory_facade_detail not found")

mw = obj.matrix_world
verts = obj.data.vertices
boxes = [
    (-8.5, -3.5, -15.0, -9.5),
    (19.5, 24.5, -15.0, -9.5),
    (47.5, 52.5, -15.0, -9.5),
]
remove = []
for v in verts:
    w = mw @ v.co
    if w.z < 43.7:
        continue
    for (x0, x1, y0, y1) in boxes:
        if x0 <= w.x <= x1 and y0 <= w.y <= y1:
            remove.append(v.index)
            break
print("[VENTCUT] removing", len(remove), "vertices")
if remove:
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for i in remove:
        obj.data.vertices[i].select = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')

bpy.ops.export_scene.gltf(
    filepath=SRC,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[VENTCUT] saved")
