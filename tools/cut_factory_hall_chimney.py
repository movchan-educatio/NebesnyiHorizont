import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

# The old factory stack is part of the hall_main mesh (a solid capped tower at
# local x=62, y=-34).  Delete its vertices so the new open-top shell can stand
# in the same place without an invisible solid core blocking the bore.
targets = ["hall_main", "factory_facade_detail"]
removed = 0
for name in targets:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mw = obj.matrix_world
    remove = []
    for v in obj.data.vertices:
        w = mw @ v.co
        dx = w.x - 62.0
        dy = w.y + 34.0
        if w.z > 7.5 and dx * dx + dy * dy < 3.85 * 3.85:
            remove.append(v.index)
    if not remove:
        print("[HALLCHIM] no vertices in", name)
        continue
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
    print("[HALLCHIM] removed", len(remove), "vertices from", name)
    removed += len(remove)

bpy.ops.export_scene.gltf(
    filepath=SRC,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[HALLCHIM] saved, removed", removed)
