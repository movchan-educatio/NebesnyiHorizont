## Merge the authored soldier's 12 skinned meshes / 11 materials into one
## skinned mesh with a single 2K texture atlas.  The rig animates bones, so the
## mesh count was the only reason a squad cost 13 draw calls per soldier.
##
## Usage:
##   blender --background --factory-startup --python merge_soldier.py
import bpy
import numpy as np

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\combat\soldier_detailed.glb"
OUT = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\combat\soldier_detailed_merged.glb"
ATLAS_PATH = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\combat\soldier_atlas.png"

COLS = 4
ROWS = 4
CELL = 512
W = COLS * CELL
H = ROWS * CELL

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
meshes = [o for o in meshes
          if o.data.materials and len(o.data.materials) > 0
          and not o.name.lower().startswith("icosphere")]
meshes.sort(key=lambda o: o.name)
print("[MERGE] meshes:", len(meshes))

atlas = bpy.data.images.new("soldier_atlas", width=W, height=H, alpha=True)
buf = np.zeros((H, W, 4), dtype=np.float32)
buf[..., 3] = 1.0

def material_image(mat):
    if mat is None or not mat.use_nodes:
        return None
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image is not None:
            return node.image
    return None

def resize_nearest(px, src_w, src_h, dst_w, dst_h):
    ys = (np.arange(dst_h) * (src_h / dst_h)).astype(np.int32)
    xs = (np.arange(dst_w) * (src_w / dst_w)).astype(np.int32)
    return px[ys][:, xs]

for idx, ob in enumerate(meshes):
    col = idx % COLS
    row = idx // COLS
    mat = ob.data.materials[0] if ob.data.materials else None
    img = material_image(mat)
    if img is not None and img.size[0] > 0 and img.size[1] > 0:
        src_w, src_h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(src_h, src_w, 4)
        cell = resize_nearest(px, src_w, src_h, CELL, CELL)
        buf[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = cell
        print("[MERGE]", ob.name, "tex", img.name, src_w, "x", src_h,
              "-> cell", col, row)
    else:
        print("[MERGE]", ob.name, "no texture, flat grey")
        buf[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL, :3] = 0.35
    uv = ob.data.uv_layers.active
    if uv is not None:
        data = uv.data
        for loop in data:
            u = loop.uv.x
            v = loop.uv.y
            loop.uv.x = (u + float(col)) / float(COLS)
            loop.uv.y = (v + float(row)) / float(ROWS)

atlas.pixels = buf.ravel().tolist()
atlas.filepath_raw = ATLAS_PATH
atlas.file_format = 'PNG'
atlas.save()
print("[MERGE] atlas saved", ATLAS_PATH)

bpy.ops.object.select_all(action='DESELECT')
for ob in meshes:
    ob.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
joined = bpy.context.active_object
joined.name = "SoldierMerged"

joined.data.materials.clear()
mat = bpy.data.materials.new("soldier_atlas")
mat.use_nodes = True
nodes = mat.node_tree.nodes
nodes.clear()
out = nodes.new("ShaderNodeOutputMaterial")
out.location = (500, 0)
bsdf = nodes.new("ShaderNodeBsdfPrincipled")
bsdf.location = (200, 0)
tex = nodes.new("ShaderNodeTexImage")
tex.location = (-200, 0)
tex.image = atlas
mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
joined.data.materials.append(mat)

for mod in joined.modifiers:
    if mod.type == 'ARMATURE':
        print("[MERGE] armature modifier ->", mod.object.name if mod.object else None)

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_skins=True,
    export_apply=False,
)
print("[MERGE] exported", OUT)
print("[MERGE] joined verts", len(joined.data.vertices),
      "polys", len(joined.data.polygons),
      "materials", len(joined.data.materials))
