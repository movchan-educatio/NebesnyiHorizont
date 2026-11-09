## Replace the 512 px procedural concrete/brick/metal/roof textures embedded in
## the handcrafted GLBs with the 1K CC0 PBR sets (ambientCG).  Geometry, UVs and
## object names are preserved; only the image nodes change.
##
## Usage:
##   blender --background --factory-startup --python retexture_handcrafted.py -- <in.glb> <out.glb>
import bpy
import os
import sys

CC0 = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\cc0\1k"

SETS = {
    "concrete": ("concrete_albedo.png", "concrete_normal.png", "concrete_rough.png"),
    "brick": ("brick_albedo.png", "brick_normal.png", "brick_rough.png"),
    "metal": ("metal_albedo.png", "metal_normal.png", "metal_rough.png"),
    "roof": ("roof_albedo.png", "roof_normal.png", "roof_rough.png"),
    "metalness": ("metalness_albedo.png", None, None),
}

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []
if len(argv) < 2:
    print("[RETEX] need <in.glb> <out.glb>")
    sys.exit(1)
src, out = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
print("[RETEX] imported", src)

def load_img(fname, non_color):
    if not fname:
        return None
    path = os.path.join(CC0, fname)
    if not os.path.exists(path):
        print("[RETEX] missing", path)
        return None
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img

family = None
for mat in bpy.data.materials:
    if mat.users == 0 or not mat.use_nodes:
        continue
    low = mat.name.lower()
    if "brick" in low:
        family = "brick"
    elif "concrete" in low or low.startswith("cont"):
        family = "concrete"
    elif "metal" in low or "steel" in low:
        family = "metal"
    elif "roof" in low:
        family = "roof"
    else:
        family = None
    if family is None or family not in SETS:
        continue
    albedo, normal, rough = SETS[family]
    replaced = 0
    for node in mat.node_tree.nodes:
        if node.type != 'TEX_IMAGE':
            continue
        iname = (node.image.name.lower() if node.image else "")
        is_normal = "normal" in iname or "nor" in iname
        is_rough = "rough" in iname
        if is_normal:
            img = load_img(normal, True)
        elif is_rough:
            img = load_img(rough, True)
        else:
            img = load_img(albedo, False)
        if img is not None:
            node.image = img
            replaced += 1
    # Flat metal materials (containers) keep their albedo tint but gain the
    # authored metal roughness/normal for close-up surface response.
    if replaced == 0 and family == "metal":
        if not any(n.type == 'TEX_IMAGE' for n in mat.node_tree.nodes):
            img = load_img(SETS["metal"][0], False)
            if img is not None:
                tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
                tex.image = img
                replaced += 1
    print("[RETEX]", mat.name, "->", family, "nodes", replaced)

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[RETEX] exported", out)
