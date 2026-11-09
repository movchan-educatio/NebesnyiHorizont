import bpy, os
from mathutils import Vector

glb_path = r'GodotDrone-master\Assets\Drones\ua_norm\quad5_custom.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

to_delete = []
for obj in bpy.data.objects:
    # Delete old Sketchfab props and blades
    name_lower = obj.name.lower()
    if any(k in name_lower for k in ['blade_', '_314', '_269', '_404', '_359', 'prop_hub', 'prop_nut']):
        to_delete.append(obj)
    elif obj.name in ['Object_360', 'Object_318', 'Object_276', 'Object_234']:
        to_delete.append(obj)

print(f'Deleting {len(to_delete)} old duplicate prop objects from quad5_custom...')
for obj in to_delete:
    bpy.data.objects.remove(obj, do_unlink=True)

# Verify surviving prop objects
surviving_props = [o.name for o in bpy.data.objects if 'prop' in o.name.lower()]
print('Surviving prop objects in quad5_custom:', surviving_props)

# Export cleaned GLB
bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False,
    export_yup=True
)
print('EXPORTED CLEANED QUAD5_CUSTOM GLB')
