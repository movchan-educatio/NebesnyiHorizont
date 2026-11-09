## make_fpv_city.py — procedural single-level FPV city for the GodotDrone sim.
## Run: blender --background --python make_fpv_city.py
## Output: Assets/sceneries/city/fpv_city.glb (+ .blend next to it).
## Units are meters. The map is flat (one level): ground plane, one long
## straight main street for the gate course, cross streets, building rows
## set back from the road, lamp posts, and an open start plaza.

import bpy
import random
import os

random.seed(7)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "Assets", "sceneries", "city")
OUT_DIR = os.path.normpath(OUT_DIR)
GLB_PATH = os.path.join(OUT_DIR, "fpv_city.glb")
BLEND_PATH = os.path.normpath(os.path.join(OUT_DIR, "..", "..", "..", "..",
                                           "fpv_city.blend"))

# ---------------------------------------------------------------- clear scene
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
    for x in list(coll):
        coll.remove(x)

root_coll = bpy.context.scene.collection
city_coll = bpy.data.collections.new("FPVCity")
root_coll.children.link(city_coll)
root = bpy.data.objects.new("FPVCity", None)
city_coll.objects.link(root)


def link(obj):
    city_coll.objects.link(obj)
    obj.parent = root
    return obj


def box(name, loc, size, mat=None):
    # loc/size are given in Godot order (x, height, depth); Blender is Z-up.
    bloc = (loc[0], loc[2], loc[1])
    bsize = (size[0], size[2], size[1])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=bloc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = bsize
    # bake scale into mesh so the GLB is clean
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    return link(obj)


def get_bsdf(m):
    nodes = m.node_tree.nodes
    for n in nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    out = None
    for n in nodes:
        if n.type == "OUTPUT_MATERIAL":
            out = n
    if out is None:
        out = nodes.new("ShaderNodeOutputMaterial")
    m.node_tree.links.new(bsdf.outputs[0], out.inputs[0])
    return bsdf


def flat_mat(name, color):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = get_bsdf(m)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


def window_texture(name, wall, lit_ratio=0.45):
    # 256x256 facade: wall base + 4x5 window grid (some lit warm, rest dark)
    W = H = 256
    img = bpy.data.images.new(name, W, H)
    wall_px = list(wall)
    dark = (0.13, 0.17, 0.23)
    lit = (1.0, 0.78, 0.42)
    px = [0.0] * (W * H * 4)
    cols, rows = 4, 5
    mx, my = 14, 12
    cw = (W - mx * 2) // cols
    ch = (H - my * 2) // rows
    for y in range(H):
        for x in range(W):
            col = (x - mx) // cw if mx <= x < W - mx else -1
            row = (y - my) // ch if my <= y < H - my else -1
            if 0 <= col < cols and 0 <= row < rows:
                fx = (x - mx) % cw
                fy = (y - my) % ch
                if 3 <= fx < cw - 3 and 3 <= fy < ch - 3:
                    c = lit if random.random() < lit_ratio else dark
                else:
                    c = wall_px
            else:
                c = wall_px
            i = (y * W + x) * 4
            px[i], px[i + 1], px[i + 2], px[i + 3] = c[0], c[1], c[2], 1.0
    img.pixels.foreach_set(px)
    img.update()
    img.pack()
    return img


def building_mat(name, wall):
    tex = window_texture(name + "_tex", wall)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = get_bsdf(m)
    img_node = nodes.new("ShaderNodeTexImage")
    img_node.image = tex
    links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return m


def scale_uv(obj, su, sv):
    me = obj.data
    uv_layer = me.uv_layers.active
    if uv_layer is None:
        return
    for loop in uv_layer.data:
        loop.uv.x *= su
        loop.uv.y *= sv


# ---------------------------------------------------------------- materials
ground_mat = flat_mat("Ground", (0.16, 0.15, 0.13))
asphalt_mat = flat_mat("Asphalt", (0.10, 0.10, 0.11))
walk_mat = flat_mat("Sidewalk", (0.32, 0.30, 0.28))
dash_mat = flat_mat("DashLine", (0.85, 0.83, 0.75))
pad_mat = flat_mat("StartPad", (0.20, 0.55, 0.30))
pole_mat = flat_mat("LampPole", (0.08, 0.08, 0.09))

bmat_a = building_mat("BuildA", (0.55, 0.48, 0.40))
bmat_b = building_mat("BuildB", (0.45, 0.42, 0.45))
bmat_c = building_mat("BuildC", (0.60, 0.55, 0.47))
bmats = [bmat_a, bmat_b, bmat_c]

head_mat = bpy.data.materials.new("LampHead")
head_mat.use_nodes = True
hbsdf = get_bsdf(head_mat)
hbsdf.inputs["Base Color"].default_value = (1.0, 0.85, 0.6, 1.0)
hbsdf.inputs["Emission Color"].default_value = (1.0, 0.8, 0.55, 1.0)
hbsdf.inputs["Emission Strength"].default_value = 3.0

# ---------------------------------------------------------------- ground
bpy.ops.mesh.primitive_plane_add(size=400.0, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
ground.data.materials.append(ground_mat)
link(ground)

# ---------------------------------------------------------------- streets (X = width, Z = length)
STREET_W = 24.0
STREET_L = 340.0


def street_strip(name, cx, cz, w, l, mat):
    # cx/cz/w/l are Godot-order plan coords; Blender ground plane is XY.
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(cx, cz, 0.02))
    o = bpy.context.active_object
    o.name = name
    o.scale = (w, l, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    return link(o)


street_strip("MainStreet", 0, 0, STREET_W, STREET_L, asphalt_mat)
street_strip("WalkL", -STREET_W / 2 - 2.0, 0, 4.0, STREET_L, walk_mat)
street_strip("WalkR", STREET_W / 2 + 2.0, 0, 4.0, STREET_L, walk_mat)
# cross streets
street_strip("CrossN", 0, -70, 160, 14, asphalt_mat)
street_strip("CrossS", 0, 70, 160, 14, asphalt_mat)
# center dashes along the main street
for z in range(-160, 161, 8):
    box("Dash", (0, 0.05, z), (0.4, 0.02, 3.0), dash_mat)

# start pad (visual spawn marker, south end plaza)
box("StartPad", (0, 0.06, -140), (8.0, 0.04, 8.0), pad_mat)

# ---------------------------------------------------------------- buildings
def clear_of_cross(z, d):
    return not (abs(abs(z) - 70) < 14 + d / 2)


z = -150.0
while z < 150.0:
    for side in (-1, 1):
        if random.random() < 0.15:
            continue
        w = random.uniform(12, 18)
        d = random.uniform(12, 18)
        if not clear_of_cross(z, d):
            continue
        h = random.uniform(10, 30)
        x = side * (STREET_W / 2 + 5.0 + w / 2 + random.uniform(0, 6))
        b = box("Bld", (x, h / 2, z + random.uniform(-3, 3)), (w, h, d),
                random.choice(bmats))
        scale_uv(b, max(w, d) / 5.0, h / 5.0)
    z += random.uniform(22, 30)

# second row backdrop (taller, further out)
z = -145.0
while z < 150.0:
    for side in (-1, 1):
        if random.random() < 0.35:
            continue
        w = random.uniform(16, 24)
        d = random.uniform(16, 24)
        h = random.uniform(25, 45)
        x = side * (STREET_W / 2 + 30.0 + w / 2 + random.uniform(0, 10))
        b = box("BldFar", (x, h / 2, z + random.uniform(-4, 4)), (w, h, d),
                random.choice(bmats))
        scale_uv(b, max(w, d) / 5.0, h / 5.0)
    z += random.uniform(28, 38)

# ---------------------------------------------------------------- lamp posts along main street
for z in range(-150, 151, 30):
    for side in (-1, 1):
        x = side * (STREET_W / 2 + 1.0)
        box("Pole", (x, 3.5, z), (0.25, 7.0, 0.25), pole_mat)
        box("Lamp", (x, 7.1, z), (0.9, 0.35, 0.9), head_mat)

# ---------------------------------------------------------------- export
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_yup=True,
    export_cameras=False,
    export_lights=False,
    export_extras=False,
)
print("WROTE", GLB_PATH)
