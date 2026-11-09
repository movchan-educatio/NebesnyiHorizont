import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

for pname in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
    p_obj = bpy.data.objects.get(pname)
    bm = bmesh.new()
    bm.from_mesh(p_obj.data)
    # Check all vertices
    verts = [v.co for v in bm.verts]
    # For a propeller, find the central hub:
    # Look at the thickness along Z: at the hub, there is a cylinder / hole
    # Vertices near origin (say radius < 25mm)
    inner_verts = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.025]
    if inner_verts:
        # The hub has the highest concentration of cylindrical vertices
        # Let's find the circle center
        cen = sum(inner_verts, mathutils.Vector((0,0,0))) / len(inner_verts)
        # Refine center: find vertices within 10mm of cen
        close = [v for v in inner_verts if ((v.x - cen.x)**2 + (v.y - cen.y)**2)**0.5 < 0.010]
        if close:
            cen2 = sum(close, mathutils.Vector((0,0,0))) / len(close)
            print(f"{pname}: refined hub center = ({cen2.x:.5f}, {cen2.y:.5f}, {cen2.z:.5f}), close count={len(close)}")
        else:
            print(f"{pname}: hub center = ({cen.x:.5f}, {cen.y:.5f}, {cen.z:.5f})")
    bm.free()
