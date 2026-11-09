import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r'GodotDrone-master\Assets\Drones\ua_norm\avata2.glb')

rings = bpy.data.objects.get('DJI_Avata2_Propeller_Rings')
if rings:
    print('DJI_Avata2_Propeller_Rings verts:', len(rings.data.vertices))
    verts = [v.co for v in rings.data.vertices]
    print('  X:', min(v.x for v in verts), max(v.x for v in verts))
    print('  Y:', min(v.y for v in verts), max(v.y for v in verts))
    print('  Z:', min(v.z for v in verts), max(v.z for v in verts))

for obj in bpy.data.objects:
    if 'prop' in obj.name.lower():
        nverts = len(obj.data.vertices) if obj.type == 'MESH' else 'NOT_MESH'
        print(f'{obj.name}: verts={nverts}, loc={obj.location}')
