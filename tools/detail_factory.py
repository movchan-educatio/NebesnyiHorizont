## Ground-level authored detail for the handcrafted factory hall: loading
## doors, a canopy, downpipes, a maintenance ladder and rooftop vents.  The
## hall shell stays clean red brick (no white scaffold outline), while these
## pieces break the box at eye level.  Reuses the existing materials, so the
## draw-call count is unchanged.
##
## Usage:
##   blender --background --factory-startup --python detail_factory.py
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
OUT = SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

concrete = bpy.data.materials.get("concrete")
metal = bpy.data.materials.get("metal")
dark = bpy.data.materials.get("dark")
glass = bpy.data.materials.get("glass")
assert concrete and metal and dark

created = []

def box(name, loc, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    created.append(ob)
    return ob

def cyl(name, loc, radius, height, mat, verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius,
                                        depth=height, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    created.append(ob)
    return ob

# Hall AABB in Blender space: x [-32, 65.6], y [-37.6, 13.0], z [0, 44].

# Three loading doors on the east end.
for i, y in enumerate([-28.0, -14.0, 0.0]):
    box("loading_door_%d" % i, (66.1, y, 5.0), (0.4, 9.0, 10.0), dark)
    box("loading_frame_%d" % i, (66.25, y, 10.4), (0.5, 9.6, 0.6), metal)

# Loading canopy on the south facade.
box("canopy", (30.0, 17.2, 8.4), (18.0, 8.0, 0.35), metal)
for px in [22.0, 38.0]:
    for py in [13.8, 20.6]:
        box("canopy_post_%.0f_%.0f" % (px, py), (px, py, 4.2),
            (0.22, 0.22, 8.4), metal)

# Downpipes along the north facade.
for px in [-18.0, 10.0, 38.0, 58.0]:
    cyl("downpipe_%.0f" % px, (px, -38.2, 21.0), 0.14, 41.0, metal, 8)

# Maintenance ladder on the east end.
box("ladder_rail_a", (66.35, 5.5, 24.0), (0.12, 0.12, 24.0), metal)
box("ladder_rail_b", (66.35, 6.6, 24.0), (0.12, 0.12, 24.0), metal)
for i in range(20):
    box("ladder_rung_%d" % i, (66.35, 6.05, 12.6 + i * 1.15),
        (0.12, 1.1, 0.09), metal)

# Rooftop vents and skylights.
for i, px in enumerate([-6.0, 22.0, 50.0]):
    cyl("roof_vent_%d" % i, (px, -12.0, 45.2), 1.4, 2.4, metal, 12)
    cyl("roof_vent_cap_%d" % i, (px, -12.0, 46.5), 1.6, 0.3, dark, 12)
for i, px in enumerate([0.0, 20.0, 40.0]):
    box("skylight_%d" % i, (px, -12.0, 44.35), (8.0, 2.4, 0.2), glass)

bpy.ops.object.select_all(action='DESELECT')
for ob in created:
    ob.select_set(True)
bpy.context.view_layer.objects.active = created[0]
bpy.ops.object.join()
detail = bpy.context.active_object
detail.name = "factory_facade_detail"
print("[DETAIL] added", len(created), "pieces, joined verts",
      len(detail.data.vertices))

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[DETAIL] exported", OUT)
