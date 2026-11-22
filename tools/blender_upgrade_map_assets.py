"""Upgrade map GLB assets and generate Assets/maps/airport_landmarks.glb in Blender 5.2.

Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender_upgrade_map_assets.py
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix, Euler

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HALL_TEX_DIR = os.path.join(ROOT_DIR, "Assets", "frontline", "industrial_hall")
FRONT_TEX_DIR = os.path.join(ROOT_DIR, "Assets", "frontline", "textures")


def _reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _lin(c):
    return (pow(max(0.0, c[0]), 2.2), pow(max(0.0, c[1]), 2.2), pow(max(0.0, c[2]), 2.2))


def _load_img(path):
    if not os.path.exists(path):
        print("[WARN] Missing texture:", path)
        return None
    for img in bpy.data.images:
        if os.path.normpath(bpy.path.abspath(img.filepath)) == os.path.normpath(path):
            return img
    return bpy.data.images.load(path)


def _attach_pbr_to_mat(mat, diff_path, nor_path, rough_path, tint_rgb=None, metallic=0.1, rough_mult=1.0):
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            bsdf = n
            break
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic

    # Avoid adding duplicate image nodes if already textured
    has_tex = any(n.type == 'TEX_IMAGE' for n in nt.nodes)
    if has_tex:
        return

    base_col = tuple(bsdf.inputs["Base Color"].default_value[:3]) if tint_rgb is None else tint_rgb
    img_d = _load_img(diff_path)
    img_n = _load_img(nor_path)
    img_r = _load_img(rough_path)

    if img_d is not None:
        tex_d = nt.nodes.new("ShaderNodeTexImage")
        tex_d.image = img_d
        # Multiply texture by tint color so wagon_red / wagon_blue / wagon_green keep their distinct hues
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 0.82
        nt.links.new(tex_d.outputs["Color"], mix.inputs[6])
        # Boost tint slightly so multiplying by texture doesn't make it overly dark
        boosted = (
            min(1.0, base_col[0] * 1.45 + 0.08),
            min(1.0, base_col[1] * 1.45 + 0.08),
            min(1.0, base_col[2] * 1.45 + 0.08),
            1.0,
        )
        mix.inputs[7].default_value = boosted
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])

    if img_r is not None:
        img_r.colorspace_settings.name = 'Non-Color'
        tex_r = nt.nodes.new("ShaderNodeTexImage")
        tex_r.image = img_r
        nt.links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])

    if img_n is not None:
        img_n.colorspace_settings.name = 'Non-Color'
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = img_n
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = 0.9
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])


def _ensure_box_uv(ob, uv_scale=0.35):
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv_layer = me.uv_layers.active.data
    for poly in me.polygons:
        n = poly.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            if az >= ax and az >= ay:
                u, v = co.x * uv_scale, co.y * uv_scale
            elif ax >= ay:
                u, v = co.y * uv_scale, co.z * uv_scale
            else:
                u, v = co.x * uv_scale, co.z * uv_scale
            uv_layer[li].uv = (u, v)


def _add_box_mesh(name, size, loc, mat, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.clear()
    if mat is not None:
        ob.data.materials.append(mat)
    return ob


def _add_cyl_mesh(name, radius, depth, loc, mat, rot=(0.0, 0.0, 0.0), verts=14):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=loc, rotation=rot, vertices=verts)
    ob = bpy.context.object
    ob.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.clear()
    if mat is not None:
        ob.data.materials.append(mat)
    return ob


# ==============================================================================
# 1. UPGRADE Assets/handcrafted/freight_train.glb
# ==============================================================================
def upgrade_freight_train():
    path = os.path.join(ROOT_DIR, "Assets", "handcrafted", "freight_train.glb")
    if not os.path.exists(path):
        print("[SKIP] freight_train.glb not found")
        return
    _reset()
    bpy.ops.import_scene.gltf(filepath=path)

    mats = {m.name: m for m in bpy.data.materials}
    metal_d = os.path.join(HALL_TEX_DIR, "metal_plate_02_diff_2k.jpg")
    metal_n = os.path.join(HALL_TEX_DIR, "metal_plate_02_nor_gl_2k.jpg")
    metal_r = os.path.join(HALL_TEX_DIR, "metal_plate_02_rough_2k.jpg")
    rust_d = os.path.join(HALL_TEX_DIR, "rusty_metal_02_diff_2k.jpg")
    rust_n = os.path.join(HALL_TEX_DIR, "rusty_metal_02_nor_gl_2k.jpg")
    rust_r = os.path.join(HALL_TEX_DIR, "rusty_metal_02_rough_2k.jpg")

    if "dark" in mats:
        _attach_pbr_to_mat(mats["dark"], metal_d, metal_n, metal_r, tint_rgb=(0.18, 0.19, 0.21), metallic=0.55)
    if "rust" in mats:
        _attach_pbr_to_mat(mats["rust"], rust_d, rust_n, rust_r, tint_rgb=(0.45, 0.24, 0.14), metallic=0.30)
    if "wagon_red" in mats:
        _attach_pbr_to_mat(mats["wagon_red"], rust_d, rust_n, rust_r, tint_rgb=(0.48, 0.17, 0.13), metallic=0.25)
    if "wagon_blue" in mats:
        _attach_pbr_to_mat(mats["wagon_blue"], metal_d, metal_n, metal_r, tint_rgb=(0.16, 0.27, 0.39), metallic=0.35)
    if "wagon_green" in mats:
        _attach_pbr_to_mat(mats["wagon_green"], metal_d, metal_n, metal_r, tint_rgb=(0.19, 0.31, 0.20), metallic=0.30)

    # Add sculpted details to the 3 boxcars (wagon0 at x=16, wagon1 at x=33, wagon2 at x=50)
    # and the 4th rust boxcar at x=67 (inside loco_roof), plus locomotive details at x=0
    wagon_specs = [
        ("wagon0", 16.0, mats.get("wagon_red")),
        ("wagon1", 33.0, mats.get("wagon_blue")),
        ("wagon2", 50.0, mats.get("wagon_green")),
    ]
    dark_mat = mats.get("dark")
    roof_mat = mats.get("roof")
    rust_mat = mats.get("rust")
    metal_mat = mats.get("metal")

    extra_dark = []
    extra_roof = []
    extra_rust = []
    extra_loco = []

    # ChME3/TEM2 diesel-electric locomotive details:
    # Tall cab at x in [-7.0, -1.9], z in [3.3, 5.9] (roof cap at z = 6.12)
    # Long engine hood at x in [-1.9, 8.1], z in [0.7, 3.9]
    for sy in (-1.0, 1.0):
        # Louvered engine inspection doors & radiator grilles flush along long hood sides (x in [-1.2, 6.8])
        for lx in (-0.4, 1.8, 4.0, 6.0):
            extra_dark.append(_add_box_mesh("loco_louver", (1.45, 0.08, 1.35), (lx, sy * 1.50, 2.75), dark_mat))
        # Cab side windows & frame on tall cab (x in [-6.5, -2.5], z in [4.2, 5.2])
        extra_dark.append(_add_box_mesh("loco_cab_win", (1.6, 0.10, 0.90), (-4.4, sy * 1.52, 4.65), dark_mat))
        # Walkway handrails along long engine hood (x in [-1.8, 7.8], y = ±1.48)
        extra_loco.append(_add_box_mesh("loco_handrail_top", (9.4, 0.06, 0.06), (3.0, sy * 1.48, 2.35), metal_mat))
        for px in (-1.6, 0.4, 2.4, 4.4, 6.4, 7.6):
            extra_loco.append(_add_box_mesh("loco_stanchion", (0.06, 0.06, 0.85), (float(px), sy * 1.48, 1.92), metal_mat))
    # Rear cab windshields (x = -7.02) & forward nose grille/headlight (x = 8.12)
    for wy in (-0.68, 0.68):
        extra_dark.append(_add_box_mesh("loco_windshield", (0.08, 0.95, 0.85), (-7.02, wy, 4.65), dark_mat))
        extra_loco.append(_add_box_mesh("loco_visor", (0.28, 1.02, 0.07), (-7.12, wy, 5.12), metal_mat))
    extra_dark.append(_add_box_mesh("loco_front_grille", (0.08, 1.85, 1.25), (8.12, 0.0, 2.55), dark_mat))
    extra_loco.append(_add_cyl_mesh("loco_headlight_f", 0.22, 0.22, (8.18, 0.0, 3.45), metal_mat, (0.0, math.pi * 0.5, 0.0), 12))
    extra_loco.append(_add_cyl_mesh("loco_headlight_r", 0.22, 0.22, (-7.08, 0.0, 5.55), metal_mat, (0.0, math.pi * 0.5, 0.0), 12))
    for sx_end, wx in ((-1.0, -7.05), (1.0, 8.12)):
        extra_dark.append(_add_box_mesh("loco_plow", (0.35, 2.85, 0.65), (wx + sx_end * 0.12, 0.0, 0.82), dark_mat))
    # Roof cooling fans and exhaust stack flush on top of engine hood (z = 3.90) & cab antenna
    for fx in (2.2, 4.6):
        extra_dark.append(_add_cyl_mesh("loco_roof_fan", 0.68, 0.20, (fx, 0.0, 3.96), dark_mat, verts=14))
    extra_dark.append(_add_cyl_mesh("loco_exhaust", 0.32, 0.48, (0.4, 0.0, 4.10), dark_mat, verts=12))
    extra_dark.append(_add_box_mesh("loco_fuel_tank", (6.4, 2.55, 0.85), (2.2, 0.0, 0.85), dark_mat))

    # Add corrugated ribs, sliding doors, door tracks, roof ribs, end ladders to all 4 freight wagons
    all_wagons = wagon_specs + [("loco_roof", 67.0, rust_mat)]
    for w_obj_name, wx, w_mat in all_wagons:
        target_ob = bpy.data.objects.get(w_obj_name)
        w_parts = []
        for sy in (-1.0, 1.0):
            # Central heavy sliding cargo door with raised frame and latch bars
            w_parts.append(_add_box_mesh("w_door", (2.8, 0.12, 2.55), (wx, sy * 1.37, 2.12), w_mat))
            extra_dark.append(_add_box_mesh("w_door_track_top", (5.6, 0.14, 0.10), (wx, sy * 1.39, 3.46), dark_mat))
            extra_dark.append(_add_box_mesh("w_door_track_bot", (5.6, 0.16, 0.12), (wx, sy * 1.39, 0.78), dark_mat))
            for lx in (-0.65, 0.65):
                extra_dark.append(_add_box_mesh("w_door_lock", (0.07, 0.16, 2.45), (wx + lx, sy * 1.41, 2.12), dark_mat))
            # Vertical external body ribs along left and right panels
            for rx in (-5.8, -4.7, -3.6, -2.5, 2.5, 3.6, 4.7, 5.8):
                w_parts.append(_add_box_mesh("w_rib", (0.16, 0.11, 2.78), (wx + rx, sy * 1.36, 2.10), w_mat))
            # Underframe solebar + truss struts
            extra_dark.append(_add_box_mesh("w_solebar", (13.1, 0.16, 0.24), (wx, sy * 1.32, 0.68), dark_mat))
        # End wall ribs + brake wheel + ladder
        for sx in (-1.0, 1.0):
            ex = wx + sx * 6.52
            for ey in (-0.85, 0.0, 0.85):
                w_parts.append(_add_box_mesh("w_end_rib", (0.12, 0.16, 2.75), (ex, ey, 2.10), w_mat))
            extra_dark.append(_add_box_mesh("w_ladder_stiles", (0.10, 0.48, 2.65), (ex + sx * 0.06, 0.88, 2.15), dark_mat))
        # Roof transverse ribs & roof walk plank
        for rfx in range(-5, 6, 2):
            extra_roof.append(_add_box_mesh("w_roof_rib", (0.20, 2.94, 0.12), (wx + float(rfx), 0.0, 3.78), roof_mat))
        extra_rust.append(_add_box_mesh("w_roof_walk", (12.8, 0.58, 0.08), (wx, 0.0, 3.84), rust_mat))

        if target_ob is not None and w_parts:
            bpy.ops.object.select_all(action='DESELECT')
            target_ob.select_set(True)
            for p in w_parts:
                p.select_set(True)
            bpy.context.view_layer.objects.active = target_ob
            bpy.ops.object.join()

    # Join extra details into their material owner meshes
    for owner_name, extras in [
        ("rail_0_-1", extra_dark),
        ("wagon0_top", extra_roof),
        ("loco_roof", extra_rust),
        ("loco_body", extra_loco),
    ]:
        owner = bpy.data.objects.get(owner_name)
        if owner is not None and extras:
            bpy.ops.object.select_all(action='DESELECT')
            owner.select_set(True)
            for p in extras:
                p.select_set(True)
            bpy.context.view_layer.objects.active = owner
            bpy.ops.object.join()

    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            _ensure_box_uv(ob, uv_scale=0.35)

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
    )
    print("[UPGRADE_OK] freight_train.glb ->", path)


# ==============================================================================
# 2. UPGRADE wetlands_dock.glb AND factory_complex.glb
# ==============================================================================
def upgrade_wetlands_dock():
    path = os.path.join(ROOT_DIR, "Assets", "handcrafted", "wetlands_dock.glb")
    if not os.path.exists(path):
        return
    _reset()
    bpy.ops.import_scene.gltf(filepath=path)
    mats = {m.name: m for m in bpy.data.materials}
    rust_d = os.path.join(HALL_TEX_DIR, "rusty_metal_02_diff_2k.jpg")
    rust_n = os.path.join(HALL_TEX_DIR, "rusty_metal_02_nor_gl_2k.jpg")
    rust_r = os.path.join(HALL_TEX_DIR, "rusty_metal_02_rough_2k.jpg")
    wood_d = os.path.join(FRONT_TEX_DIR, "wood_albedo.jpg")
    wood_n = os.path.join(FRONT_TEX_DIR, "wood_normal.jpg")
    wood_r = os.path.join(FRONT_TEX_DIR, "wood_rough.jpg")

    if "rust" in mats:
        _attach_pbr_to_mat(mats["rust"], rust_d, rust_n, rust_r, tint_rgb=(0.44, 0.24, 0.14), metallic=0.32)
    if "wood" in mats:
        _attach_pbr_to_mat(mats["wood"], wood_d, wood_n, wood_r, tint_rgb=(0.38, 0.27, 0.17), metallic=0.02)

    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            _ensure_box_uv(ob, uv_scale=0.35)

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
    )
    print("[UPGRADE_OK] wetlands_dock.glb ->", path)


def upgrade_factory_complex():
    path = os.path.join(ROOT_DIR, "Assets", "handcrafted", "factory_complex.glb")
    if not os.path.exists(path):
        return
    _reset()
    bpy.ops.import_scene.gltf(filepath=path)
    metal_d = os.path.join(HALL_TEX_DIR, "metal_plate_02_diff_2k.jpg")
    metal_n = os.path.join(HALL_TEX_DIR, "metal_plate_02_nor_gl_2k.jpg")
    metal_r = os.path.join(HALL_TEX_DIR, "metal_plate_02_rough_2k.jpg")
    rust_d = os.path.join(HALL_TEX_DIR, "rusty_metal_02_diff_2k.jpg")
    rust_n = os.path.join(HALL_TEX_DIR, "rusty_metal_02_nor_gl_2k.jpg")
    rust_r = os.path.join(HALL_TEX_DIR, "rusty_metal_02_rough_2k.jpg")

    for m in bpy.data.materials:
        if m.name.startswith("cont0"):
            _attach_pbr_to_mat(m, rust_d, rust_n, rust_r, tint_rgb=(0.48, 0.20, 0.14), metallic=0.28)
        elif m.name.startswith("cont1"):
            _attach_pbr_to_mat(m, metal_d, metal_n, metal_r, tint_rgb=(0.16, 0.28, 0.42), metallic=0.35)
        elif m.name.startswith("cont2"):
            _attach_pbr_to_mat(m, metal_d, metal_n, metal_r, tint_rgb=(0.20, 0.34, 0.22), metallic=0.30)

    for ob in bpy.data.objects:
        if ob.type == 'MESH':
            _ensure_box_uv(ob, uv_scale=0.35)

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
    )
    print("[UPGRADE_OK] factory_complex.glb ->", path)


# ==============================================================================
# 3. GENERATE Assets/maps/airport_landmarks.glb
# ==============================================================================
class MeshBuilder:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.color_layer = self.bm.loops.layers.color.new("Col")

    def _paint(self, geom, rgb):
        c = (*_lin(rgb), 1.0)
        faces = [ele for ele in geom if isinstance(ele, bmesh.types.BMFace)]
        for f in faces:
            for l in f.loops:
                l[self.color_layer] = c

    def box(self, size, center=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), rgb=(0.5, 0.5, 0.5), bevel=0.0):
        mat = Matrix.Translation(center) @ Euler(rot, 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        verts = res["verts"]
        bmesh.ops.contextual_create(self.bm, geom=verts)
        faces = list({f for v in verts for f in v.link_faces})
        if bevel > 0.0001:
            edges = list({e for f in faces for e in f.edges})
            bres = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=1, affect='EDGES')
            faces = list({f for v in verts for f in v.link_faces} | set(bres.get("faces", [])))
        self._paint(faces, rgb)

    def cyl(self, r1, r2, height, center=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), segs=14, rgb=(0.5, 0.5, 0.5), cap_ends=True):
        mat = Matrix.Translation(center) @ Euler(rot, 'XYZ').to_matrix().to_4x4()
        res = bmesh.ops.create_cone(
            self.bm,
            cap_ends=cap_ends,
            cap_tris=False,
            segments=segs,
            radius1=r1,
            radius2=r2,
            depth=height,
            matrix=mat,
        )
        verts = res["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        self._paint(faces, rgb)

    def finish(self, mat):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        uv_layer = self.bm.loops.layers.uv.new("UVMap")
        if self.bm.verts:
            zs = [v.co.z for v in self.bm.verts]
            z_min, z_max = min(zs), max(zs)
            z_span = max(0.25, z_max - z_min)
        else:
            z_min, z_span = 0.0, 1.0

        for f in self.bm.faces:
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            sun = max(0.0, n.x * 0.35 - n.y * 0.40 + n.z * 0.85)
            for l in f.loops:
                co = l.vert.co
                if az >= ax and az >= ay:
                    u, v = co.x * 0.35, co.y * 0.35
                elif ax >= ay:
                    u, v = co.y * 0.35, co.z * 0.35
                else:
                    u, v = co.x * 0.35, co.z * 0.35
                l[uv_layer].uv = (u, v)
                h_t = max(0.0, min(1.0, (co.z - z_min) / z_span))
                ao = (0.78 + 0.22 * pow(h_t, 0.60)) * (0.90 + 0.16 * sun)
                c = l[self.color_layer]
                l[self.color_layer] = (min(1.0, c[0] * ao), min(1.0, c[1] * ao), min(1.0, c[2] * ao), 1.0)

        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        me.materials.append(mat)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        print(f"[LandmarkMesh] {self.name}: verts={len(me.vertices)} tris={sum(len(p.vertices)-2 for p in me.polygons)}")
        return ob


def _build_control_tower_ruins(mat):
    # Note: Blender Z is up -> glTF exporter converts +Z to Godot +Y, +Y to Godot -Z
    b = MeshBuilder("ControlTowerRuins")
    CONC = (0.74, 0.72, 0.68)
    CONC_DARK = (0.56, 0.55, 0.52)
    RUST = (0.66, 0.38, 0.22)
    STEEL = (0.62, 0.64, 0.68)
    CHAR = (0.30, 0.29, 0.28)
    GLASS = (0.34, 0.48, 0.56)

    # Base administration plinth (9.4 x 9.4 x 7.6 m) with corner pilasters, blast breaches & entrance canopy
    b.box((9.6, 9.6, 0.6), (0.0, 0.0, 0.3), rgb=CONC_DARK)
    b.box((9.0, 9.0, 7.2), (0.0, 0.0, 3.8), rgb=CONC)
    b.box((9.8, 9.8, 0.45), (0.0, 0.0, 7.55), rgb=CONC_DARK)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            b.box((0.85, 0.85, 7.4), (sx * 4.35, sy * 4.35, 3.8), rgb=CONC_DARK)
        # Window bays & blast charring on plinth walls
        for wz in (2.2, 5.2):
            for wx in (-2.6, 0.0, 2.6):
                b.box((1.4, 0.22, 1.4), (wx, sx * 4.52, wz), rgb=CHAR)
                b.box((0.18, 1.4, 1.4), (sx * 4.52, wx, wz), rgb=CHAR)

    # Octagonal fluted brutalist tower shaft (z = 7.6 to 18.8 m)
    b.cyl(3.55, 3.25, 11.2, (0.0, 0.0, 13.2), segs=8, rgb=CONC)
    for i in range(8):
        ang = i * math.tau / 8.0
        rx, ry = math.cos(ang) * 3.35, math.sin(ang) * 3.35
        b.box((0.42, 0.42, 11.2), (rx, ry, 13.2), rot=(0.0, 0.0, ang), rgb=CONC_DARK)
        if i % 2 == 0:
            wx, wy = math.cos(ang + math.pi / 8.0) * 3.12, math.sin(ang + math.pi / 8.0) * 3.12
            for hz in (10.0, 13.2, 16.4):
                b.box((0.85, 0.25, 1.8), (wx, wy, hz), rot=(0.0, 0.0, ang + math.pi / 8.0 + math.pi * 0.5), rgb=CHAR)
    # Intermediate concrete collar rings
    for hz in (11.2, 15.0):
        b.cyl(3.65, 3.65, 0.38, (0.0, 0.0, hz), segs=8, rgb=CONC_DARK)

    # Lower observation catwalk gallery (z = 18.8 m) with cantilevered brackets & steel railings
    b.cyl(5.4, 4.2, 0.75, (0.0, 0.0, 18.55), segs=8, rgb=CONC_DARK)
    b.cyl(5.6, 5.6, 0.45, (0.0, 0.0, 19.05), segs=8, rgb=CONC)
    for i in range(8):
        ang = i * math.tau / 8.0
        # Cantilevered concrete fins under the catwalk
        b.box((0.35, 1.8, 1.4), (math.cos(ang) * 4.1, math.sin(ang) * 4.1, 18.0), rot=(0.25, 0.0, ang + math.pi * 0.5), rgb=CONC_DARK)
        # Catwalk perimeter handrail posts
        b.box((0.14, 0.14, 1.1), (math.cos(ang) * 5.35, math.sin(ang) * 5.35, 19.75), rgb=RUST)
    b.cyl(5.42, 5.42, 0.10, (0.0, 0.0, 20.22), segs=8, rgb=RUST, cap_ends=False)

    # Open hollow ATC observation cab (z = 19.3 to 23.5 m): 8 wide open fly-through
    # window bays on every side (no central solid block), slim corner mullions, and tiny
    # corner glass shards framing the perimeter without blocking flight paths.
    b.cyl(4.95, 4.95, 0.45, (0.0, 0.0, 19.50), segs=8, rgb=CONC)
    for i in range(8):
        ang = i * math.tau / 8.0
        # Flared steel window mullions at the 8 octagon vertices (r = 4.65 m)
        mx, my = math.cos(ang) * 4.65, math.sin(ang) * 4.65
        b.box((0.26, 0.26, 4.05), (mx, my, 21.50), rot=(0.08 * math.sin(ang), -0.08 * math.cos(ang), ang), rgb=STEEL)
        # Small corner-hugging broken glass shards beside mullions (leaving > 3 m center bay clear)
        if i in (0, 2, 4, 6):
            s_ang = ang + 0.14
            gx, gy = math.cos(s_ang) * 4.55, math.sin(s_ang) * 4.55
            b.box((0.55, 0.06, 0.72), (gx, gy, 20.12), rot=(0.0, 0.0, s_ang + math.pi * 0.5), rgb=GLASS)

    # Tilted battle-damaged roof slab (z = 23.65 m) + rooftop steel lattice radar tower + parabolic radar dish (z = 27.7 m)
    b.cyl(5.25, 5.05, 0.55, (0.2, 0.1, 23.65), rot=(0.05, -0.04, 0.0), segs=8, rgb=CONC_DARK)
    for sx in (-1.1, 1.1):
        for sy in (-1.1, 1.1):
            b.box((0.18, 0.18, 3.6), (sx * 0.85, sy * 0.85, 25.5), rot=(-sy * 0.08, sx * 0.08, 0.0), rgb=RUST)
    for hz in (24.6, 25.8, 26.9):
        b.box((1.6, 1.6, 0.14), (0.0, 0.0, hz), rgb=RUST)
    # Curved radar scanner dish at z = 27.75 m
    b.cyl(0.45, 0.45, 1.2, (0.0, 0.0, 27.2), segs=10, rgb=STEEL)
    b.box((5.4, 0.35, 1.05), (0.0, 0.0, 27.75), rot=(0.08, 0.0, 0.45), rgb=RUST)
    for rib in (-2.2, -1.1, 0.0, 1.1, 2.2):
        b.box((0.14, 0.65, 1.12), (rib * math.cos(0.45), rib * math.sin(0.45), 27.75), rot=(0.08, 0.0, 0.45), rgb=STEEL)

    # Fallen concrete rubble blocks & twisted rebar at tower base
    rng = random.Random(101)
    for i in range(10):
        ang = i * math.tau / 10.0 + rng.uniform(-0.15, 0.15)
        dist = rng.uniform(5.2, 6.8)
        w, d, h = rng.uniform(1.6, 2.8), rng.uniform(1.2, 2.2), rng.uniform(0.6, 1.4)
        b.box((w, d, h), (math.cos(ang) * dist, math.sin(ang) * dist, h * 0.45),
              rot=(rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), ang),
              rgb=CONC_DARK if i % 2 == 0 else CHAR)

    return b.finish(mat)


def _build_fuel_depot(mat):
    b = MeshBuilder("FuelDepot")
    CONC = (0.48, 0.47, 0.43)
    CONC_DARK = (0.33, 0.32, 0.30)
    TANK_WHITE = (0.64, 0.63, 0.59)
    RUST = (0.45, 0.24, 0.14)
    STEEL = (0.36, 0.38, 0.41)
    HAZARD = (0.62, 0.26, 0.08)

    # Reinforced concrete bund pad (24 x 16 m) with chamfered dike walls & corner buttresses
    b.box((24.0, 16.0, 0.4), (0.0, 0.0, 0.2), rgb=CONC_DARK)
    for sy in (-7.7, 7.7):
        b.box((24.0, 0.65, 1.25), (0.0, sy, 0.8), rgb=CONC)
        b.box((24.2, 0.82, 0.18), (0.0, sy, 1.45), rgb=CONC_DARK)
        for bx in range(-10, 11, 5):
            b.box((0.45, 0.95, 1.2), (float(bx), sy, 0.75), rgb=CONC_DARK)
    for sx in (-11.7, 11.7):
        b.box((0.65, 15.0, 1.25), (sx, 0.0, 0.8), rgb=CONC)
        b.box((0.82, 15.2, 0.18), (sx, 0.0, 1.45), rgb=CONC_DARK)

    # 4 Horizontal Cylindrical Fuel Cisterns at (±5.6, ±3.4, z=2.5)
    # Note: In Godot coordinates, tx = ±5.6, tz = ±3.4 -> in Blender (X, Y, Z), X = tx, Y = tz, Z = 2.5
    for tx in (-5.6, 5.6):
        for ty in (-3.4, 3.4):
            # Concrete saddle cradles under each tank
            for cx_off in (-3.0, 0.0, 3.0):
                b.box((0.55, 3.4, 1.35), (tx + cx_off, ty, 1.05), rgb=CONC_DARK)
            # Main cylindrical tank body along X (length 8.6 m, radius 1.92 m)
            b.cyl(1.92, 1.92, 8.6, (tx, ty, 2.55), rot=(0.0, math.pi * 0.5, 0.0), segs=18, rgb=TANK_WHITE)
            # Dished hemispherical end caps
            for end_s in (-1.0, 1.0):
                b.cyl(1.90, 1.15, 0.65, (tx + end_s * 4.62, ty, 2.55),
                      rot=(0.0, end_s * math.pi * 0.5, 0.0), segs=18, rgb=TANK_WHITE)
            # Circumferential stiffening rings & rust hazard bands
            for rx_off in (-2.8, 0.0, 2.8):
                b.cyl(1.97, 1.97, 0.18, (tx + rx_off, ty, 2.55), rot=(0.0, math.pi * 0.5, 0.0), segs=18,
                      rgb=HAZARD if rx_off == 0.0 else RUST)
            # Top manway dome + pressure relief valve
            b.cyl(0.55, 0.55, 0.45, (tx - 1.2, ty, 4.55), segs=12, rgb=RUST)
            b.cyl(0.64, 0.64, 0.10, (tx - 1.2, ty, 4.78), segs=12, rgb=STEEL)
            b.cyl(0.22, 0.22, 0.55, (tx + 1.4, ty, 4.60), segs=8, rgb=STEEL)

    # Overhead steel inspection catwalk at z = 4.75 m with handrails & access stairs
    b.box((20.4, 1.1, 0.16), (0.0, 0.0, 4.72), rgb=STEEL)
    for sy in (-0.52, 0.52):
        b.box((20.4, 0.08, 0.08), (0.0, sy, 5.75), rgb=RUST)
        b.box((20.4, 0.06, 0.06), (0.0, sy, 5.25), rgb=RUST)
        for px in range(-10, 11, 2):
            b.box((0.08, 0.08, 1.05), (float(px), sy, 5.25), rgb=RUST)
    # Cross catwalks over the tanks
    for tx in (-5.6, 5.6):
        b.box((0.95, 7.6, 0.14), (tx, 0.0, 4.74), rgb=STEEL)

    # Central pipe manifold & pumping valves along Y
    for px in (-0.45, 0.45):
        b.cyl(0.24, 0.24, 13.6, (px, 0.0, 1.65), rot=(math.pi * 0.5, 0.0, 0.0), segs=10, rgb=RUST)
    for vy in (-3.4, 0.0, 3.4):
        b.box((2.6, 0.35, 0.35), (0.0, vy, 1.65), rgb=STEEL)
        b.cyl(0.32, 0.32, 0.08, (0.0, vy, 2.05), segs=10, rgb=HAZARD)

    return b.finish(mat)


def _build_cargo_container(mat):
    # Centered at (0, 0, 0), Godot size (6.2, 2.6, 2.5) -> Blender size (6.2, 2.5, 2.6)
    # Uses neutral white/grey vertex colors so MultiMesh instance_color tints it cleanly!
    b = MeshBuilder("CargoContainer")
    BODY = (0.86, 0.86, 0.86)
    RIB = (0.72, 0.72, 0.74)
    FRAME = (0.62, 0.62, 0.64)
    DARK = (0.30, 0.31, 0.33)

    # Core container box slightly inset from outer frame
    b.box((6.04, 2.34, 2.46), (0.0, 0.0, 0.0), rgb=BODY)
    # Top and bottom longitudinal & transverse frame rails
    for sz in (-1.23, 1.23):
        for sy in (-1.18, 1.18):
            b.box((6.16, 0.16, 0.16), (0.0, sy, sz), rgb=FRAME)
        for sx in (-3.02, 3.02):
            b.box((0.16, 2.48, 0.16), (sx, 0.0, sz), rgb=FRAME)
    # 8 ISO corner castings + vertical corner posts
    for sx in (-3.02, 3.02):
        for sy in (-1.18, 1.18):
            b.box((0.18, 0.18, 2.58), (sx, sy, 0.0), rgb=FRAME)
            for sz in (-1.22, 1.22):
                b.box((0.24, 0.24, 0.24), (sx, sy, sz), rgb=DARK)
    # Side wall vertical corrugation ribs (15 per side)
    for sy in (-1.20, 1.20):
        for i in range(-7, 8):
            b.box((0.16, 0.09, 2.30), (i * 0.37, sy, 0.0), rgb=RIB)
    # Roof transverse corrugation ribs
    for i in range(-7, 8):
        b.box((0.18, 2.26, 0.07), (i * 0.37, 0.0, 1.25), rgb=RIB)
    # Front end doors (+X) with vertical locking bars & hinges; rear wall (-X) with ribs
    for dy in (-0.58, 0.58):
        b.box((0.08, 1.08, 2.28), (3.04, dy, 0.0), rgb=BODY)
        for bar_off in (-0.28, 0.28):
            b.box((0.09, 0.06, 2.26), (3.08, dy + bar_off, 0.0), rgb=DARK)
    for i in range(-2, 3):
        b.box((0.08, 0.18, 2.30), (-3.04, i * 0.44, 0.0), rgb=RIB)

    return b.finish(mat)


def _build_ruined_hangar_frame(mat):
    b = MeshBuilder("RuinedHangarFrame")
    STEEL = (0.64, 0.67, 0.70)
    RUST = (0.64, 0.38, 0.24)
    CONC = (0.70, 0.68, 0.64)
    SHEET = (0.54, 0.56, 0.58)

    # 4 Main Lattice Portal Arch Trusses at Y = -12, -4, 4, 12 (Godot Z = -12, -4, 4, 12)
    for arch_y in (-12.0, -4.0, 4.0, 12.0):
        for side_x in (-14.0, 14.0):
            # Concrete column footing pier
            b.box((1.35, 1.35, 1.4), (side_x, arch_y, 0.7), rgb=CONC)
            # Double-chord steel lattice column up to z = 10.4 m
            for cx_off in (-0.32, 0.32):
                b.box((0.24, 0.48, 9.6), (side_x + cx_off, arch_y, 5.5), rgb=STEEL)
            for hz in range(2, 10, 2):
                b.box((0.75, 0.38, 0.20), (side_x, arch_y, float(hz)), rgb=RUST)
            # Knee brace joining column to roof rafter
            s_sign = -1.0 if side_x > 0.0 else 1.0
            b.box((3.2, 0.32, 0.28), (side_x + s_sign * 1.3, arch_y, 9.4),
                  rot=(0.0, -s_sign * 0.65, 0.0), rgb=RUST)
        # Pitched lattice roof rafters (left and right slopes meeting at ridge z = 12.4 m)
        for s_sign in (-1.0, 1.0):
            cx = s_sign * 7.1
            tilt = s_sign * 0.16
            # Upper and lower rafter chords
            b.box((14.8, 0.45, 0.28), (cx, arch_y, 11.45), rot=(0.0, tilt, 0.0), rgb=STEEL)
            b.box((14.6, 0.38, 0.24), (cx, arch_y, 10.65), rot=(0.0, tilt, 0.0), rgb=RUST)
            for strut_i in range(-2, 3):
                sx = cx + strut_i * 2.4
                sz = 11.05 - s_sign * (strut_i * 2.4) * math.tan(0.16)
                b.box((0.22, 0.34, 0.82), (sx, arch_y, sz), rgb=RUST)

    # Longitudinal roof purlins & side girts spanning Y in [-12.5, 12.5]
    for purlin_x, pz in [(-11.5, 10.65), (-6.5, 11.45), (-2.0, 12.15), (2.0, 12.15), (6.5, 11.45), (11.5, 10.65)]:
        b.box((0.28, 25.4, 0.28), (purlin_x, 0.0, pz), rgb=STEEL)
    for side_x in (-14.0, 14.0):
        for gz in (4.5, 8.5, 10.2):
            b.box((0.26, 25.2, 0.26), (side_x, 0.0, gz), rgb=RUST)

    # Surviving torn corrugated roof sheeting clades on outer bays
    for (sx, sy, sz, tilt) in [
        (-9.2, -8.0, 11.25, -0.16),
        (-9.0, 8.0, 11.25, -0.16),
        (9.2, -8.0, 11.25, 0.16),
        (8.8, 0.0, 11.30, 0.16),
    ]:
        b.box((6.2, 6.8, 0.10), (sx, sy, sz), rot=(0.0, tilt, 0.0), rgb=SHEET)

    return b.finish(mat)


def _build_aircraft_wreck(mat):
    # Orient along Y in Blender so after glTF Y-up conversion it aligns along Z in Godot
    b = MeshBuilder("AircraftWreck")
    ALLOY = (0.74, 0.77, 0.79)
    CAMO_TOP = (0.52, 0.58, 0.52)
    CHAR = (0.32, 0.31, 0.30)
    RUST = (0.58, 0.36, 0.24)
    DARK = (0.26, 0.27, 0.29)
    GLASS = (0.32, 0.44, 0.52)

    # Main fuselage sections along Y (total length ~16.8 m, centered near Y = 0)
    # Forward nose cone & radome (Y = -8.4 to -5.4)
    b.cyl(0.45, 1.25, 1.8, (0.0, -7.5, 1.65), rot=(math.pi * 0.5, 0.0, 0.0), segs=14, rgb=DARK)
    b.cyl(1.25, 1.62, 2.2, (0.0, -5.5, 1.80), rot=(math.pi * 0.5, 0.0, 0.0), segs=14, rgb=ALLOY)
    # Stepped cockpit canopy & glazed windshield frames
    b.box((1.85, 2.1, 0.75), (0.0, -5.6, 2.65), rot=(0.22, 0.0, 0.0), rgb=CAMO_TOP)
    b.box((1.65, 1.2, 0.55), (0.0, -6.2, 2.55), rot=(0.35, 0.0, 0.0), rgb=GLASS)
    # Center fuselage barrel (Y = -4.4 to +2.8) with charred blast breach on top
    b.cyl(1.62, 1.62, 7.2, (0.0, -0.8, 1.90), rot=(math.pi * 0.5, 0.0, 0.0), segs=16, rgb=ALLOY)
    b.box((2.1, 6.8, 0.45), (0.0, -0.8, 3.30), rgb=CAMO_TOP)
    # Battle-damaged breach crater + exposed ribs on center fuselage
    b.box((1.95, 3.4, 0.55), (0.0, 0.4, 3.25), rgb=CHAR)
    for ry in (-0.9, -0.1, 0.7, 1.5):
        b.box((2.05, 0.14, 0.65), (0.0, ry, 3.28), rgb=RUST)
    # Main landing gear sponsons on lower fuselage sides
    for sx in (-1.55, 1.55):
        b.box((0.85, 3.8, 0.95), (sx, -0.6, 1.15), rgb=ALLOY)
        for wy in (-1.2, 0.0):
            b.cyl(0.52, 0.52, 0.36, (sx, wy, 0.55), rot=(0.0, math.pi * 0.5, 0.0), segs=12, rgb=DARK)

    # Upswept rear fuselage & cargo ramp tail cone (Y = +2.8 to +7.8)
    b.cyl(1.62, 0.78, 5.2, (0.0, 5.2, 2.35), rot=(math.pi * 0.5 - 0.11, 0.0, 0.0), segs=14, rgb=CHAR)

    # High-mounted swept wings (wingspan 19.6 m, mounted at Z = 3.15 m, Y = -0.8)
    b.box((4.2, 2.8, 0.46), (0.0, -0.8, 3.22), rgb=CAMO_TOP)
    for sx in (-1.0, 1.0):
        b.box((8.2, 2.35, 0.34), (sx * 5.6, -0.4, 3.12),
              rot=(0.0, sx * 0.04, sx * 0.12), rgb=ALLOY if sx < 0 else CAMO_TOP)
        # Wingtip scorched damage & flap track fairings
        b.box((1.6, 1.85, 0.26), (sx * 9.3, 0.1, 2.98), rot=(0.0, sx * 0.05, sx * 0.12), rgb=CHAR)
        for fy in (-2.4, -4.8, -7.0):
            b.box((0.24, 1.25, 0.28), (sx * abs(fy), 0.7, 2.92), rgb=RUST)

    # 2 Underwing Turbofan / Turboprop Engine Nacelles at X = ±4.5
    for sx in (-4.5, 4.5):
        b.box((0.32, 1.8, 0.65), (sx, -1.1, 2.65), rgb=STEEL if 'STEEL' in locals() else ALLOY)
        b.cyl(0.68, 0.62, 2.8, (sx, -1.3, 2.05), rot=(math.pi * 0.5, 0.0, 0.0), segs=14, rgb=CHAR)
        b.cyl(0.52, 0.58, 0.35, (sx, -2.75, 2.05), rot=(math.pi * 0.5, 0.0, 0.0), segs=14, rgb=DARK)

    # Swept T-Tail vertical fin & horizontal stabilizer at Y = +6.8 .. +7.8
    b.box((0.38, 2.8, 4.2), (0.0, 6.8, 4.7), rot=(-0.24, 0.0, 0.0), rgb=CHAR)
    b.box((0.44, 2.2, 0.38), (0.0, 7.35, 6.75), rgb=RUST)
    for sx in (-1.0, 1.0):
        b.box((3.6, 1.55, 0.24), (sx * 1.75, 7.45, 6.68), rot=(0.0, 0.0, sx * 0.14), rgb=ALLOY)

    return b.finish(mat)


def _build_runway_edge_light(mat):
    b = MeshBuilder("RunwayEdgeLight")
    YELLOW = (0.85, 0.62, 0.12)
    DARK = (0.20, 0.21, 0.23)
    LENS = (0.98, 0.84, 0.28)

    b.cyl(0.22, 0.25, 0.08, (0.0, 0.0, 0.04), segs=10, rgb=DARK)
    b.cyl(0.08, 0.10, 0.18, (0.0, 0.0, 0.17), segs=8, rgb=YELLOW)
    b.cyl(0.16, 0.14, 0.14, (0.0, 0.0, 0.32), segs=10, rgb=YELLOW)
    b.cyl(0.10, 0.14, 0.10, (0.0, 0.0, 0.43), segs=10, rgb=LENS)
    return b.finish(mat)


def _build_patrol_boat_hull(mat):
    # Orient along Y in Blender so after glTF export (+Y -> -Z) bow points along -Z or +Z
    # Wait: in MovingPatrolBoat.gd:
    # Bow prism is at z = +4.4, stern wake is at z = -7.0, so bow points towards +Z in Godot!
    # In Blender glTF export (Y-up): Blender +X -> Godot +X, Blender +Z -> Godot +Y, Blender -Y -> Godot +Z!
    # So to point bow towards Godot +Z, bow is at Blender Y = -4.8 and stern is at Blender Y = +4.4!
    b = MeshBuilder("PatrolBoatHull")
    HULL = (0.46, 0.52, 0.44)
    HULL_LOW = (0.34, 0.38, 0.34)
    DECK = (0.52, 0.54, 0.50)
    CABIN = (0.56, 0.60, 0.54)
    GLASS = (0.24, 0.38, 0.46)
    METAL = (0.54, 0.56, 0.58)
    RUST_ORANGE = (0.86, 0.40, 0.16)

    # Lower planing V-hull + main armored freeboard (stern Y = +4.2 to bow stem Y = -5.2)
    b.box((2.55, 6.8, 0.55), (0.0, 0.8, 0.28), rgb=HULL_LOW)
    b.box((2.75, 6.8, 0.55), (0.0, 0.8, 0.72), rgb=HULL)
    # Rubbing strake / chine fender around hull
    b.box((2.92, 6.9, 0.14), (0.0, 0.8, 0.88), rgb=HULL_LOW)
    # Tapered flared bow section (Y = -2.6 to -5.2)
    for sx in (-1.0, 1.0):
        b.box((1.35, 2.9, 0.85), (sx * 0.68, -3.7, 0.56), rot=(0.08, 0.0, -sx * 0.26), rgb=HULL)
        b.box((0.18, 2.8, 0.22), (sx * 1.15, -3.6, 1.04), rot=(0.0, 0.0, -sx * 0.26), rgb=METAL)
    b.box((1.4, 2.2, 0.18), (0.0, -3.5, 0.98), rgb=DECK)
    # Main nonskid deck & gunwale coaming
    b.box((2.58, 6.6, 0.14), (0.0, 0.8, 1.02), rgb=DECK)
    for sx in (-1.28, 1.28):
        b.box((0.14, 6.6, 0.24), (sx, 0.8, 1.14), rgb=HULL_LOW)

    # Armored stealth wheelhouse superstructure (Y = -1.6 to +1.5)
    b.box((2.15, 2.8, 0.85), (0.0, -0.1, 1.45), rgb=CABIN)
    b.box((1.85, 2.2, 0.45), (0.0, 0.0, 2.02), rgb=CABIN)
    # Armored forward & side ballistic glass visors (facing bow at -Y)
    for wx in (-0.48, 0.48):
        b.box((0.72, 0.12, 0.34), (wx, -1.48, 1.68), rot=(0.22, 0.0, 0.0), rgb=GLASS)
    for sx in (-1.0, 1.0):
        b.box((0.10, 1.45, 0.32), (sx * 1.06, -0.2, 1.68), rgb=GLASS)
        # Orange rescue lifebuoys mounted on cabin sides
        b.cyl(0.28, 0.28, 0.12, (sx * 1.12, 0.65, 1.42), rot=(0.0, math.pi * 0.5, 0.0), segs=10, rgb=RUST_ORANGE)

    # Radar & communications mast on wheelhouse roof
    b.cyl(0.08, 0.06, 1.45, (0.0, 0.35, 2.90), segs=8, rgb=METAL)
    b.box((0.95, 0.18, 0.14), (0.0, 0.35, 3.35), rgb=METAL)
    b.cyl(0.28, 0.24, 0.22, (0.0, -0.25, 2.35), segs=10, rgb=HULL_LOW)

    # Forward & Aft Remote Weapon Stations (Katran-M 30mm turret)
    for (ty, tz, b_dir) in [(-3.0, 1.25, -1.0), (2.5, 1.25, 1.0)]:
        b.cyl(0.55, 0.62, 0.28, (0.0, ty, tz), segs=10, rgb=HULL_LOW)
        b.box((0.88, 0.95, 0.44), (0.0, ty, tz + 0.32), rgb=CABIN)
        b.cyl(0.055, 0.045, 1.35, (0.0, ty + b_dir * 0.95, tz + 0.36),
              rot=(math.pi * 0.5, 0.0, 0.0), segs=8, rgb=METAL)

    # Stern engine hatch, bollards & twin transom exhaust cowls
    b.box((1.65, 1.2, 0.22), (0.0, 2.8, 1.15), rgb=HULL_LOW)
    for sx in (-0.95, 0.95):
        b.cyl(0.10, 0.10, 0.32, (sx, 3.8, 1.22), segs=8, rgb=METAL)
        b.cyl(0.10, 0.10, 0.32, (sx * 0.75, -4.3, 1.22), segs=8, rgb=METAL)

    return b.finish(mat)


def _build_burnt_tank_wreck(mat):
    b = MeshBuilder("BurntTankWreck")
    CHAR = (0.30, 0.29, 0.28)
    RUST = (0.54, 0.33, 0.21)
    RUST_LIGHT = (0.66, 0.40, 0.25)
    STEEL = (0.44, 0.45, 0.47)

    # Main hull tub + sloped glacis & rear engine deck (length along X = 6.2 m, width along Y = 3.4 m)
    b.box((5.6, 2.1, 0.95), (0.0, 0.0, 0.82), rgb=CHAR)
    b.box((1.6, 2.05, 0.65), (2.4, 0.0, 0.92), rot=(0.0, 0.38, 0.0), rgb=RUST)
    # ERA reactive armor bricks on glacis
    for ex in (2.1, 2.6):
        for ey in (-0.65, 0.0, 0.65):
            b.box((0.38, 0.52, 0.14), (ex, ey, 1.24), rot=(0.0, 0.38, 0.0), rgb=RUST_LIGHT)
    # Track assemblies, 6 roadwheels per side, drive sprockets & armored side skirts
    for sy in (-1.35, 1.35):
        b.box((6.1, 0.62, 0.78), (0.0, sy, 0.45), rgb=CHAR)
        b.box((6.2, 0.14, 0.48), (0.0, sy * 1.24, 0.95), rgb=RUST)
        for w_i in range(6):
            wx = -2.1 + w_i * 0.84
            b.cyl(0.38, 0.38, 0.68, (wx, sy, 0.40), rot=(math.pi * 0.5, 0.0, 0.0), segs=12, rgb=STEEL)
            b.cyl(0.22, 0.22, 0.72, (wx, sy, 0.40), rot=(math.pi * 0.5, 0.0, 0.0), segs=10, rgb=RUST)
        # Idler and sprocket wheels
        for end_x in (-2.75, 2.75):
            b.cyl(0.34, 0.34, 0.66, (end_x, sy, 0.65), rot=(math.pi * 0.5, 0.0, 0.0), segs=10, rgb=RUST)
    # Rear engine deck louvers & external fuel drums
    for lx in (-2.2, -1.5):
        b.box((0.55, 1.75, 0.08), (lx, 0.0, 1.32), rgb=STEEL)
    for dy in (-0.75, 0.75):
        b.cyl(0.28, 0.28, 0.85, (-3.05, dy, 1.15), rot=(math.pi * 0.5, 0.0, 0.0), segs=10, rgb=RUST)

    # Flattened cast dome turret (slightly tilted from internal ammo cook-off)
    b.cyl(1.42, 1.18, 0.72, (0.2, 0.08, 1.58), rot=(0.08, -0.06, 0.18), segs=14, rgb=RUST)
    b.cyl(0.45, 0.42, 0.28, (-0.15, 0.55, 2.02), segs=10, rgb=CHAR)
    # Turret ERA blocks & stowage boxes
    for i in range(-2, 3):
        ang = i * 0.42
        b.box((0.36, 0.48, 0.32), (0.2 + math.cos(ang) * 1.32, 0.08 + math.sin(ang) * 1.32, 1.58),
              rot=(0.0, -0.25, ang), rgb=RUST_LIGHT)
    # 125mm 2A46 main gun barrel with thermal sleeve & bore evacuator
    b.cyl(0.11, 0.09, 4.4, (2.8, 0.25, 1.55), rot=(0.0, math.pi * 0.5 + 0.08, 0.12), segs=10, rgb=CHAR)
    b.cyl(0.15, 0.15, 0.65, (2.3, 0.20, 1.58), rot=(0.0, math.pi * 0.5 + 0.08, 0.12), segs=10, rgb=RUST)

    return b.finish(mat)


def _build_nav_beacon_tower(mat):
    # 26 m tall tapered 4-leg steel lattice navigation mast (z = 0 to 26.0 m)
    b = MeshBuilder("NavBeaconTower")
    STEEL = (0.58, 0.61, 0.64)
    RUST = (0.72, 0.38, 0.22)
    CONC = (0.70, 0.68, 0.64)
    WHITE = (0.86, 0.85, 0.82)

    # Concrete foundation pedestal
    b.box((2.8, 2.8, 0.65), (0.0, 0.0, 0.32), rgb=CONC)
    # 4 Tapered corner legs from (±1.05, ±1.05, 0.5) to (±0.42, ±0.42, 25.2)
    tiers = 6
    z0, z1 = 0.5, 25.2
    dz = (z1 - z0) / float(tiers)
    for t in range(tiers):
        za = z0 + t * dz
        zb = za + dz
        zm = (za + zb) * 0.5
        ra = 1.05 - (1.05 - 0.42) * (t / float(tiers))
        rb = 1.05 - (1.05 - 0.42) * ((t + 1) / float(tiers))
        rm = (ra + rb) * 0.5
        col = WHITE if t % 2 == 1 else RUST
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                b.box((0.15, 0.15, dz + 0.12), (sx * rm, sy * rm, zm),
                      rot=(-sy * 0.025, sx * 0.025, 0.0), rgb=col)
        # Horizontal frame ring at zb
        b.box((rb * 2.08, 0.12, 0.12), (0.0, -rb, zb), rgb=STEEL)
        b.box((rb * 2.08, 0.12, 0.12), (0.0, rb, zb), rgb=STEEL)
        b.box((0.12, rb * 2.08, 0.12), (-rb, 0.0, zb), rgb=STEEL)
        b.box((0.12, rb * 2.08, 0.12), (rb, 0.0, zb), rgb=STEEL)
        # Diagonal brace struts on all 4 faces
        diag_len = math.hypot(rm * 1.95, dz)
        diag_ang = math.atan2(rm * 1.95, dz)
        s_alt = 1.0 if t % 2 == 0 else -1.0
        for sy in (-1.0, 1.0):
            b.box((0.09, 0.09, diag_len), (0.0, sy * rm, zm),
                  rot=(0.0, s_alt * sy * diag_ang, 0.0), rgb=STEEL)
        for sx in (-1.0, 1.0):
            b.box((0.09, 0.09, diag_len), (sx * rm, 0.0, zm),
                  rot=(s_alt * sx * diag_ang, 0.0, 0.0), rgb=STEEL)

    # Top circular service platform & handrail cage at z = 25.3 m
    b.cyl(1.15, 1.05, 0.18, (0.0, 0.0, 25.3), segs=12, rgb=STEEL)
    b.cyl(1.15, 1.15, 0.08, (0.0, 0.0, 26.15), segs=12, rgb=RUST, cap_ends=False)
    for i in range(8):
        ang = i * math.tau / 8.0
        b.box((0.07, 0.07, 0.85), (math.cos(ang) * 1.10, math.sin(ang) * 1.10, 25.72), rgb=RUST)
    # Lantern pedestal housing (the glowing lens sphere is added at z = 26.5 m in Godot)
    b.cyl(0.46, 0.52, 0.75, (0.0, 0.0, 25.75), segs=12, rgb=STEEL)
    b.cyl(0.58, 0.12, 0.35, (0.0, 0.0, 27.35), segs=12, rgb=RUST)

    return b.finish(mat)


def build_airport_landmarks_glb():
    _reset()
    mat = bpy.data.materials.new("airport_landmark_vcol")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.86
    bsdf.inputs["Metallic"].default_value = 0.12

    _build_control_tower_ruins(mat)
    _build_fuel_depot(mat)
    _build_cargo_container(mat)
    _build_ruined_hangar_frame(mat)
    _build_aircraft_wreck(mat)
    _build_runway_edge_light(mat)
    _build_patrol_boat_hull(mat)
    _build_burnt_tank_wreck(mat)
    _build_nav_beacon_tower(mat)

    out_dir = os.path.join(ROOT_DIR, "Assets", "maps")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "airport_landmarks.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
    )
    print("[UPGRADE_OK] airport_landmarks.glb ->", out_path, os.path.getsize(out_path))


if __name__ == "__main__":
    upgrade_freight_train()
    build_airport_landmarks_glb()
