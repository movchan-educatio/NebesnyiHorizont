"""
Builds and mounts a high-detail tactical 5" FPV warhead (БЧ) onto
Assets/Drones/ua_norm/quad5_custom.glb in Blender 5.2 without modifying
any existing frame, electronics, motor, or propeller nodes.

Blender world coordinates for quad5_custom.glb (glTF +Y up imported):
  +X : Forward (front camera lens & nose Direction)
  -Y : Right, +Y : Left
  +Z : Up (bottom plate at Z=0..0.003, top plate Z=0.030..0.032, battery Z=0.033..0.063)

All added warhead meshes contain 'Warhead' (plus 'Detonator', 'Provoloka', 'Styazka')
in their names so BigLevel automatically hides them in pure Freestyle mode and
displays them in Combat and Menu/Hangar previews.
"""

import math
import os
import struct
import sys
import tempfile
import zlib
import numpy as np
import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GLB_PATH = os.path.join(REPO_ROOT, "Assets", "Drones", "ua_norm", "quad5_custom.glb")

WARHEAD_PREFIX = "Quad5_Warhead_"
_TEMP_FILES = []

# Warhead mount frame: slung neatly under the front carbon plate (+X is forward),
# pitched +5.2 deg nose-up so the olive body, yellow stencil band, machined fuze,
# and twin copper contact whiskers project cleanly forward between the front props
# without clipping the bottom plate, camera lens, battery, or propeller discs.
MOUNT_ORIGIN = Vector((0.062, 0.0, -0.0170))
MOUNT_PITCH_RAD = math.radians(-5.2)  # Negative rotation around +Y tilts +X tip UP (+Z)
MOUNT_ROT = Matrix.Rotation(MOUNT_PITCH_RAD, 4, 'Y')
MOUNT_XFORM = Matrix.Translation(MOUNT_ORIGIN) @ MOUNT_ROT


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def remove_existing_warhead():
    to_remove = [o for o in bpy.data.objects if o.name.startswith(WARHEAD_PREFIX)]
    for obj in to_remove:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh and mesh.users == 0:
            if isinstance(mesh, bpy.types.Mesh):
                bpy.data.meshes.remove(mesh)
            elif isinstance(mesh, bpy.types.Curve):
                bpy.data.curves.remove(mesh)


def _write_png_rgba(path: str, rgba_u8: np.ndarray) -> None:
    """Write an (H, W, 4) uint8 array cleanly as a standard RGBA PNG without external deps."""
    h, w, _ = rgba_u8.shape
    raw_rows = b"".join(b"\x00" + rgba_u8[y].tobytes() for y in range(h))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw_rows, level=6)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def make_packed_image(name: str, rgba: np.ndarray, colorspace: str = "sRGB") -> bpy.types.Image:
    # Flip vertically because numpy v=0 is bottom (glTF UV bottom) while PNG row 0 is top.
    flipped = np.flipud(np.clip(rgba, 0.0, 1.0))
    u8 = np.rint(flipped * 255.0).astype(np.uint8)
    tmp_png = os.path.join(tempfile.gettempdir(), f"{name}.png")
    _write_png_rgba(tmp_png, u8)
    _TEMP_FILES.append(tmp_png)
    img = bpy.data.images.load(tmp_png, check_existing=False)
    img.name = name
    img.colorspace_settings.name = colorspace
    img.pack()
    return img


def generate_warhead_body_textures():
    """Synthesize crisp 512x512 painted olive-drab steel casing PBR maps."""
    w, h = 512, 512
    u = np.linspace(0.0, 1.0, w, endpoint=False)[None, :]   # circumference (U)
    v = np.linspace(0.0, 1.0, h, endpoint=False)[:, None]   # axial length 0=rear .. 1=tip (V)

    rng = np.random.default_rng(202505)
    fine_noise = rng.normal(0.0, 1.0, (h, w))
    low_noise = np.fft.ifft2(
        np.fft.fft2(rng.normal(0.0, 1.0, (h, w)))
        * np.exp(-((np.fft.fftfreq(h)[:, None] * 18.0) ** 2 + (np.fft.fftfreq(w)[None, :] * 4.0) ** 2))
    ).real
    low_noise /= (np.std(low_noise) + 1e-6)

    # Rich military olive-drab enamel base (balanced so it reads clearly in linear PBR)
    r = np.full((h, w), 0.305) + low_noise * 0.022 + fine_noise * 0.014
    g = np.full((h, w), 0.378) + low_noise * 0.024 + fine_noise * 0.014
    b = np.full((h, w), 0.215) + low_noise * 0.016 + fine_noise * 0.010

    # Circumferential darker machined groove shadow / wear near fragment rings
    groove_centers = [0.22, 0.29, 0.36, 0.43, 0.50]
    height_map = np.zeros((h, w), dtype=np.float32) + fine_noise * 0.04
    for vc in groove_centers:
        d = np.abs(v - vc)
        mask = np.exp(-(d / 0.0065) ** 2)
        height_map -= mask * 0.65
        r -= mask * 0.065
        g -= mask * 0.075
        b -= mask * 0.045

    # Tactical ochre-yellow hazard/id stripe around mid-forward section (v in [0.58, 0.67])
    band = (v >= 0.580) & (v <= 0.668)
    edge_wear = (np.abs(v - 0.580) < 0.005) | (np.abs(v - 0.668) < 0.005)
    chip_noise = (low_noise > 1.35) & ((np.abs(v - 0.580) < 0.010) | (np.abs(v - 0.668) < 0.010))
    band_eff = band & (~chip_noise)
    r = np.where(band_eff, 0.84 + fine_noise * 0.018, r)
    g = np.where(band_eff, 0.66 + fine_noise * 0.016, g)
    b = np.where(band_eff, 0.14 + fine_noise * 0.010, b)

    # Dark tactical lettering blocks / ticks stamped inside yellow band
    for idx, u0 in enumerate([0.10, 0.24, 0.38, 0.60, 0.74, 0.88]):
        block = (v >= 0.603) & (v <= 0.643) & (np.abs(u - u0) < (0.016 if idx % 2 == 0 else 0.026))
        r = np.where(block, 0.14, r)
        g = np.where(block, 0.15, g)
        b = np.where(block, 0.11, b)

    # Dark rear datum stripe (v in [0.155, 0.178])
    datum = (v >= 0.155) & (v <= 0.178) & (low_noise < 1.35)
    r = np.where(datum, 0.15, r)
    g = np.where(datum, 0.17, g)
    b = np.where(datum, 0.13, b)

    # Metallic edge wear near ogive nose shoulder (v ~ 0.72) and tail rim (v ~ 0.065)
    scratch = ((np.abs(v - 0.72) < 0.008) | (np.abs(v - 0.065) < 0.007)) & (low_noise > 0.85)
    r = np.where(scratch, 0.52, r)
    g = np.where(scratch, 0.54, g)
    b = np.where(scratch, 0.50, b)

    alb = np.stack([r, g, b, np.ones_like(r)], axis=-1)
    img_alb = make_packed_image("quad5_warhead_body_alb", alb, "sRGB")

    # Roughness map (matte olive ~ 0.58, yellow stencil ~ 0.48, scratched steel ~ 0.30)
    rough = np.full((h, w), 0.58) + low_noise * 0.04 + fine_noise * 0.025
    rough = np.where(band_eff, 0.48 + fine_noise * 0.02, rough)
    rough = np.where(scratch, 0.28, rough)
    rough = np.where(edge_wear, 0.40, rough)
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)
    img_rough = make_packed_image("quad5_warhead_body_rough", rough_rgba, "Non-Color")

    # Normal map from height_map
    dy = np.roll(height_map, -1, axis=0) - np.roll(height_map, 1, axis=0)
    dx = np.roll(height_map, -1, axis=1) - np.roll(height_map, 1, axis=1)
    strength = 3.4
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(nx)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([0.5 + 0.5 * nx * inv_len, 0.5 + 0.5 * ny * inv_len, 0.5 + 0.5 * nz * inv_len, np.ones_like(nx)], axis=-1)
    img_nrm = make_packed_image("quad5_warhead_body_nrm", nrm, "Non-Color")
    return img_alb, img_rough, img_nrm


def generate_knurled_metal_textures():
    """Synthesize machined gunmetal/brass lathe-turned & knurled normal + albedo."""
    w, h = 256, 256
    u = np.linspace(0.0, 1.0, w, endpoint=False)[None, :]
    v = np.linspace(0.0, 1.0, h, endpoint=False)[:, None]
    knurl = np.sin(u * 2.0 * math.pi * 36.0) * 0.5 + np.sin(v * 2.0 * math.pi * 42.0) * 0.25
    rng = np.random.default_rng(771)
    grain = rng.normal(0.0, 0.04, (h, w))
    hmap = knurl * 0.35 + grain
    dy = np.roll(hmap, -1, axis=0) - np.roll(hmap, 1, axis=0)
    dx = np.roll(hmap, -1, axis=1) - np.roll(hmap, 1, axis=1)
    nx, ny, nz = -dx * 2.6, -dy * 2.6, np.ones_like(hmap)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([0.5 + 0.5 * nx * inv, 0.5 + 0.5 * ny * inv, 0.5 + 0.5 * nz * inv, np.ones_like(nx)], axis=-1)
    img_nrm = make_packed_image("quad5_warhead_metal_nrm", nrm, "Non-Color")
    return img_nrm


def make_image_pbr_material(name: str, img_alb, img_rough, img_nrm, metallic: float = 0.18):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if img_alb is not None:
        tex_a = nt.nodes.new("ShaderNodeTexImage")
        tex_a.image = img_alb
        nt.links.new(tex_a.outputs["Color"], bsdf.inputs["Base Color"])
    if img_rough is not None:
        tex_r = nt.nodes.new("ShaderNodeTexImage")
        tex_r.image = img_rough
        nt.links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])
    if img_nrm is not None:
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = img_nrm
        nrm_node = nt.nodes.new("ShaderNodeNormalMap")
        nrm_node.inputs["Strength"].default_value = 0.85
        nt.links.new(tex_n.outputs["Color"], nrm_node.inputs["Color"])
        nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_simple_pbr_material(name: str, color_rgba, metallic: float, roughness: float, img_nrm=None):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color_rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if img_nrm is not None:
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = img_nrm
        nrm_node = nt.nodes.new("ShaderNodeNormalMap")
        nrm_node.inputs["Strength"].default_value = 0.55
        nt.links.new(tex_n.outputs["Color"], nrm_node.inputs["Color"])
        nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def link_object(obj, world_matrix: Matrix):
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = world_matrix
    return obj


def set_smooth_with_angle(mesh, angle_deg: float = 36.0):
    for p in mesh.polygons:
        p.use_smooth = True
    # Mark sharp edges cleanly for crisp glTF split normals
    bm = bmesh.new()
    bm.from_mesh(mesh)
    thresh = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = (e.link_faces[0].normal.angle(e.link_faces[1].normal) < thresh)
        else:
            e.smooth = False
    bm.to_mesh(mesh)
    bm.free()


def build_lathe_mesh(name: str, profile_xr, segments: int = 48, mat=None, close_caps: bool = True):
    """
    Create a smooth high-detail surface of revolution along local +X axis.
    profile_xr: list of (x, radius) ordered from rear to front.
    """
    bm = bmesh.new()
    rings = []
    # Find x bounds for cylindrical UV mapping (v = 0 at rear .. 1 at tip)
    xs = [p[0] for p in profile_xr]
    x_min, x_max = min(xs), max(xs)
    x_span = max(x_max - x_min, 1e-5)

    for (x, r) in profile_xr:
        ring = []
        rr = max(r, 1e-4)
        for s in range(segments):
            ang = 2.0 * math.pi * (s / float(segments))
            y = rr * math.cos(ang)
            z = rr * math.sin(ang)
            ring.append(bm.verts.new((x, y, z)))
        rings.append((x, ring))

    bm.verts.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    for i in range(len(rings) - 1):
        x0, r0 = rings[i]
        x1, r1 = rings[i + 1]
        v0 = (x0 - x_min) / x_span
        v1 = (x1 - x_min) / x_span
        for s in range(segments):
            sn = (s + 1) % segments
            f = bm.faces.new((r0[s], r1[s], r1[sn], r0[sn]))
            u0 = s / float(segments)
            u1 = (s + 1) / float(segments)
            uvs = [(u0, v0), (u0, v1), (u1, v1), (u1, v0)]
            for loop, uv in zip(f.loops, uvs):
                loop[uv_layer].uv = uv

    if close_caps:
        # Rear cap
        x_start, r_start = rings[0]
        if profile_xr[0][1] > 1e-4:
            vc = bm.verts.new((x_start, 0.0, 0.0))
            for s in range(segments):
                sn = (s + 1) % segments
                f = bm.faces.new((vc, r_start[sn], r_start[s]))
                for loop in f.loops:
                    loop[uv_layer].uv = (0.5, 0.0)
        # Front cap
        x_end, r_end = rings[-1]
        if profile_xr[-1][1] > 1e-4:
            vc = bm.verts.new((x_end, 0.0, 0.0))
            for s in range(segments):
                sn = (s + 1) % segments
                f = bm.faces.new((vc, r_end[s], r_end[sn]))
                for loop in f.loops:
                    loop[uv_layer].uv = (0.5, 1.0)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    set_smooth_with_angle(mesh, 38.0)

    if mat is not None:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    link_object(obj, MOUNT_XFORM)
    return obj


def build_tube_along_points(name: str, pts, radius: float, radial_segs: int = 10, mat=None, closed_ends: bool = True):
    """Build a crisp miter-free swept circular tube mesh in local warhead coords."""
    bm = bmesh.new()
    rings = []
    n_pts = len(pts)
    uv_layer = bm.loops.layers.uv.new("UVMap")

    prev_ref = Vector((0.0, 0.0, 1.0))
    for i, p in enumerate(pts):
        p_vec = Vector(p)
        if i == 0:
            t = (Vector(pts[1]) - p_vec).normalized()
        elif i == n_pts - 1:
            t = (p_vec - Vector(pts[-2])).normalized()
        else:
            t = (Vector(pts[i + 1]) - Vector(pts[i - 1])).normalized()
        if t.length < 1e-6:
            t = Vector((1.0, 0.0, 0.0))
        # Parallel transport frame to avoid twist pinching in helix loops
        nrm = prev_ref - t * prev_ref.dot(t)
        if nrm.length < 1e-4:
            alt = Vector((0.0, 1.0, 0.0)) if abs(t.y) < 0.8 else Vector((1.0, 0.0, 0.0))
            nrm = alt - t * alt.dot(t)
        nrm.normalize()
        prev_ref = nrm
        binrm = t.cross(nrm).normalized()

        ring = []
        for s in range(radial_segs):
            ang = 2.0 * math.pi * (s / float(radial_segs))
            off = nrm * (math.cos(ang) * radius) + binrm * (math.sin(ang) * radius)
            ring.append(bm.verts.new(p_vec + off))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        v0 = i / float(max(n_pts - 1, 1))
        v1 = (i + 1) / float(max(n_pts - 1, 1))
        for s in range(radial_segs):
            sn = (s + 1) % radial_segs
            f = bm.faces.new((r0[s], r1[s], r1[sn], r0[sn]))
            u0 = s / float(radial_segs)
            u1 = (s + 1) / float(radial_segs)
            for loop, uv in zip(f.loops, [(u0, v0), (u0, v1), (u1, v1), (u1, v0)]):
                loop[uv_layer].uv = uv

    if closed_ends:
        v_start = bm.verts.new(Vector(pts[0]))
        for s in range(radial_segs):
            sn = (s + 1) % radial_segs
            bm.faces.new((v_start, rings[0][sn], rings[0][s]))
        v_end = bm.verts.new(Vector(pts[-1]))
        for s in range(radial_segs):
            sn = (s + 1) % radial_segs
            bm.faces.new((v_end, rings[-1][s], rings[-1][sn]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    set_smooth_with_angle(mesh, 60.0)
    if mat is not None:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    link_object(obj, MOUNT_XFORM)
    return obj


def build_box_mesh(name: str, center: Vector, size: Vector, world_mat: Matrix, mat=None, bevel_amt: float = 0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = v.co.x * size.x + center.x
        v.co.y = v.co.y * size.y + center.y
        v.co.z = v.co.z * size.z + center.z
    if bevel_amt > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_amt, segments=2, affect='EDGES')
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv_layer].uv = (loop.vert.co.x * 12.0 + 0.5, loop.vert.co.y * 12.0 + 0.5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    set_smooth_with_angle(mesh, 35.0)
    if mat is not None:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    link_object(obj, world_mat)
    return obj


def build_whisker_points(side_sign: float):
    """
    Generate smooth 3D centerline for left (+1) or right (-1) copper contact
    whisker starting at the nose fuze collar, curving into 2.5 spring helix turns,
    and sweeping forward + gently outward for clear target contact & FPV silhouette.
    """
    pts = []
    # 1. Exit stub out of collar at x=0.080
    base_y = side_sign * 0.0055
    base_z = 0.0010
    pts.append((0.075, side_sign * 0.0040, 0.0005))
    pts.append((0.081, base_y, base_z))
    pts.append((0.086, side_sign * 0.0075, 0.0018))

    # 2. Spring coil strain-relief helix (2.5 compact loops around forward axis)
    coil_turns = 2.5
    coil_steps = 36
    coil_r = 0.0032
    x0, x1 = 0.087, 0.104
    cy0, cz0 = side_sign * 0.0082, 0.0020
    for i in range(coil_steps + 1):
        t = i / float(coil_steps)
        ang = t * coil_turns * 2.0 * math.pi
        cx = x0 + (x1 - x0) * t
        # Gradually offset coil center slightly outward
        y_center = cy0 + side_sign * (0.0028 * t)
        z_center = cz0 + 0.0015 * t
        py = y_center + side_sign * (math.sin(ang) * coil_r)
        pz = z_center + (1.0 - math.cos(ang)) * coil_r * 0.85
        pts.append((cx, py, pz))

    # 3. Straight / gently bowed forward feeler probe projecting ahead of nose fuze
    probe_steps = 12
    sx, sy, sz = pts[-1]
    ex, ey, ez = 0.146, side_sign * 0.0235, 0.0110
    for i in range(1, probe_steps + 1):
        t = i / float(probe_steps)
        # Gentle upward/outward bow
        px = sx + (ex - sx) * t
        py = sy + (ey - sy) * (t ** 0.92)
        pz = sz + (ez - sz) * t + math.sin(t * math.pi) * 0.0014
        pts.append((px, py, pz))

    return pts


def build_warhead():
    img_body_alb, img_body_rough, img_body_nrm = generate_warhead_body_textures()
    img_metal_nrm = generate_knurled_metal_textures()

    mat_body = make_image_pbr_material("quad5_warhead_body_mat", img_body_alb, img_body_rough, img_body_nrm, metallic=0.16)
    mat_collar = make_simple_pbr_material("quad5_warhead_gunmetal_mat", (0.14, 0.15, 0.17, 1.0), metallic=0.88, roughness=0.30, img_nrm=img_metal_nrm)
    mat_brass = make_simple_pbr_material("quad5_warhead_brass_mat", (0.76, 0.58, 0.24, 1.0), metallic=0.92, roughness=0.24, img_nrm=img_metal_nrm)
    mat_steel = make_simple_pbr_material("quad5_warhead_steel_mat", (0.56, 0.58, 0.61, 1.0), metallic=0.94, roughness=0.26)
    mat_red_ring = make_simple_pbr_material("quad5_warhead_armring_mat", (0.72, 0.10, 0.08, 1.0), metallic=0.25, roughness=0.38)
    mat_copper = make_simple_pbr_material("quad5_warhead_copper_mat", (0.82, 0.42, 0.20, 1.0), metallic=0.96, roughness=0.22)
    mat_strap = make_simple_pbr_material("quad5_warhead_strap_mat", (0.045, 0.048, 0.052, 1.0), metallic=0.04, roughness=0.76)
    mat_foam = make_simple_pbr_material("quad5_warhead_foam_mat", (0.06, 0.065, 0.07, 1.0), metallic=0.0, roughness=0.90)
    mat_wire_red = make_simple_pbr_material("quad5_warhead_wire_red", (0.75, 0.08, 0.07, 1.0), metallic=0.05, roughness=0.42)
    mat_wire_blk = make_simple_pbr_material("quad5_warhead_wire_blk", (0.035, 0.035, 0.04, 1.0), metallic=0.05, roughness=0.48)
    mat_led = make_simple_pbr_material("quad5_warhead_init_led", (0.10, 0.85, 0.30, 1.0), metallic=0.0, roughness=0.20)

    # 1. Main Warhead Shell (local x from -0.084 rear to +0.074 ogive collar shoulder)
    # Length ~ 158 mm casing, max radius 15.8 mm (31.6 mm OD) -> compact 5" shaped-charge / frag warhead
    body_profile = [
        (-0.084, 0.0110),
        (-0.081, 0.0148),
        (-0.075, 0.0158),
        # Rear cylindrical section with machined fragmentation groove rings
        (-0.052, 0.0158),
        (-0.050, 0.0149),
        (-0.048, 0.0158),
        (-0.040, 0.0158),
        (-0.038, 0.0149),
        (-0.036, 0.0158),
        (-0.028, 0.0158),
        (-0.026, 0.0149),
        (-0.024, 0.0158),
        (-0.016, 0.0158),
        (-0.014, 0.0149),
        (-0.012, 0.0158),
        (-0.004, 0.0158),
        (-0.002, 0.0149),
        ( 0.000, 0.0158),
        # Smooth cylindrical waist to shoulder step
        ( 0.020, 0.0158),
        ( 0.023, 0.0154),
        # Ogive ballistic nose cone tapering toward the fuze collar
    ]
    ogive_steps = 12
    for k in range(1, ogive_steps + 1):
        t = k / float(ogive_steps)
        x = 0.023 + (0.074 - 0.023) * t
        # Smooth tangent-ogive taper from 0.0154 down to 0.0078
        r = 0.0154 * (1.0 - 0.495 * (t ** 1.38))
        body_profile.append((x, r))
    build_lathe_mesh(WARHEAD_PREFIX + "Body", body_profile, segments=48, mat=mat_body, close_caps=True)

    # 2. Machined Gunmetal Nose Collar (x: 0.073 .. 0.086)
    collar_profile = [
        (0.0730, 0.0084),
        (0.0745, 0.0092),
        (0.0790, 0.0092),
        (0.0800, 0.0082),
        (0.0835, 0.0082),
        (0.0850, 0.0072),
    ]
    build_lathe_mesh(WARHEAD_PREFIX + "Collar", collar_profile, segments=32, mat=mat_collar, close_caps=True)

    # 3. Impact Fuze / Detonator Tip (x: 0.0845 .. 0.1055) - machined brass, red arming collar & steel striker tip
    fuze_brass = [
        (0.0845, 0.0066),
        (0.0870, 0.0072),
        (0.0935, 0.0072),
        (0.0945, 0.0058),
        (0.0975, 0.0058),
        (0.0985, 0.0046),
    ]
    build_lathe_mesh(WARHEAD_PREFIX + "Detonator_Body", fuze_brass, segments=28, mat=mat_brass, close_caps=True)

    # Red anodized arming indicator ring on fuze
    arm_ring = [
        (0.0890, 0.00735),
        (0.0920, 0.00735),
    ]
    build_lathe_mesh(WARHEAD_PREFIX + "Detonator_ArmRing", arm_ring, segments=28, mat=mat_red_ring, close_caps=True)

    # Steel mushroom striker / crush cap at very tip
    striker_tip = [
        (0.0980, 0.0048),
        (0.1010, 0.0055),
        (0.1038, 0.0052),
        (0.1055, 0.0030),
        (0.1060, 0.0008),
    ]
    build_lathe_mesh(WARHEAD_PREFIX + "Detonator_Tip", striker_tip, segments=24, mat=mat_steel, close_caps=True)

    # Safety pull-pin ring sticking out cleanly to left side of detonator
    pin_pts = []
    for k in range(21):
        a = 2.0 * math.pi * (k / 20.0)
        pin_pts.append((0.090 + 0.0055 * math.cos(a), 0.0085 + 0.0055 * math.sin(a), 0.001))
    build_tube_along_points(WARHEAD_PREFIX + "Detonator_SafetyRing", pin_pts, radius=0.00055, radial_segs=8, mat=mat_steel, closed_ends=False)

    # 4. Twin Copper Contact Antenna Whiskers (PROVOLOKA)
    build_tube_along_points(WARHEAD_PREFIX + "Provoloka_L", build_whisker_points(+1.0), radius=0.00065, radial_segs=10, mat=mat_copper)
    build_tube_along_points(WARHEAD_PREFIX + "Provoloka_R", build_whisker_points(-1.0), radius=0.00065, radial_segs=10, mat=mat_copper)

    # 5. Rear Initiator Electronics Module & Connector Cables
    init_cap = [
        (-0.0910, 0.0072),
        (-0.0895, 0.0098),
        (-0.0840, 0.0098),
    ]
    build_lathe_mesh(WARHEAD_PREFIX + "InitBoard", init_cap, segments=24, mat=mat_collar, close_caps=True)
    # Small armed status indicator bead on rear/top-side
    build_box_mesh(
        WARHEAD_PREFIX + "InitLED",
        center=Vector((-0.087, 0.0082, 0.0052)),
        size=Vector((0.0028, 0.0018, 0.0018)),
        world_mat=MOUNT_XFORM,
        mat=mat_led,
    )

    # Twin flexible initiator leads curving cleanly up into rear stack (world X ~ -0.025..0.00, Z ~ 0.006..0.018)
    inv_mount = MOUNT_XFORM.inverted()
    red_world = [
        MOUNT_XFORM @ Vector((-0.087, -0.0035, 0.004)),
        Vector((-0.036, -0.0055, -0.006)),
        Vector((-0.030, -0.0080, 0.003)),
        Vector((-0.015, -0.0065, 0.011)),
    ]
    blk_world = [
        MOUNT_XFORM @ Vector((-0.087, 0.0035, 0.004)),
        Vector((-0.035, 0.0055, -0.006)),
        Vector((-0.028, 0.0080, 0.003)),
        Vector((-0.014, 0.0065, 0.011)),
    ]
    build_tube_along_points(WARHEAD_PREFIX + "Wire_Red", [inv_mount @ p for p in red_world], radius=0.00085, radial_segs=8, mat=mat_wire_red)
    build_tube_along_points(WARHEAD_PREFIX + "Wire_Blk", [inv_mount @ p for p in blk_world], radius=0.00085, radial_segs=8, mat=mat_wire_blk)

    # 6. Underbody Contoured Anti-Vibration Cradle & Tactical Retention Straps (STYAZKA)
    # World coordinates for cradle between carbon bottom plate (Z=0) and warhead top
    build_box_mesh(
        WARHEAD_PREFIX + "Cradle",
        center=Vector((0.018, 0.0, -0.0025)),
        size=Vector((0.072, 0.026, 0.0065)),
        world_mat=Matrix.Identity(4),
        mat=mat_foam,
        bevel_amt=0.0012,
    )

    # Build two tight wrap-around zip-tie retention bands around warhead + bottom plate edge
    for idx, x_strap in enumerate((-0.004, 0.042)):
        t_local = (x_strap - MOUNT_ORIGIN.x) / math.cos(MOUNT_PITCH_RAD)
        z_center = MOUNT_ORIGIN.z + t_local * (-math.sin(MOUNT_PITCH_RAD))
        r_w = 0.0159
        ring_pts = [
            Vector((x_strap, -0.0218, 0.0036)),
            Vector((x_strap,  0.0218, 0.0036)),
            Vector((x_strap,  0.0220, -0.0005)),
            Vector((x_strap,  0.0168, max(-0.002, z_center + 0.004))),
        ]
        # Smooth circular cradle arc hugging the bottom 180 degrees of the cylinder
        for k in range(13):
            ang = math.radians(15.0 + 150.0 * (k / 12.0))
            py = r_w * math.cos(ang)
            pz = z_center - r_w * math.sin(ang)
            ring_pts.append(Vector((x_strap, py, pz)))
        ring_pts.extend([
            Vector((x_strap, -0.0168, max(-0.002, z_center + 0.004))),
            Vector((x_strap, -0.0220, -0.0005)),
        ])
        # Convert into mount local? No, make strap in world directly
        bm = bmesh.new()
        w_half = 0.0024
        t_thick = 0.0013
        n_ring = len(ring_pts)
        # Compute outer offset points
        loops_inner_f = []
        loops_inner_b = []
        loops_outer_f = []
        loops_outer_b = []
        centroid = Vector((x_strap, 0.0, 0.5 * (0.0039 + z_center - r_w)))
        for p in ring_pts:
            out_dir = Vector((0.0, p.y - centroid.y, p.z - centroid.z))
            if out_dir.length < 1e-5:
                out_dir = Vector((0.0, 0.0, 1.0))
            out_dir.normalize()
            p_out = p + out_dir * t_thick
            loops_inner_f.append(bm.verts.new((p.x + w_half, p.y, p.z)))
            loops_inner_b.append(bm.verts.new((p.x - w_half, p.y, p.z)))
            loops_outer_f.append(bm.verts.new((p_out.x + w_half, p_out.y, p_out.z)))
            loops_outer_b.append(bm.verts.new((p_out.x - w_half, p_out.y, p_out.z)))
        for i in range(n_ring):
            inext = (i + 1) % n_ring
            bm.faces.new((loops_outer_b[i], loops_outer_f[i], loops_outer_f[inext], loops_outer_b[inext]))
            bm.faces.new((loops_inner_f[i], loops_inner_b[i], loops_inner_b[inext], loops_inner_f[inext]))
            bm.faces.new((loops_inner_f[i], loops_outer_f[i], loops_outer_f[inext], loops_inner_f[inext]))
            bm.faces.new((loops_outer_b[i], loops_inner_b[i], loops_inner_b[inext], loops_outer_b[inext]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(f"{WARHEAD_PREFIX}Styazka_{idx + 1}_Mesh")
        bm.to_mesh(mesh)
        bm.free()
        set_smooth_with_angle(mesh, 40.0)
        mesh.materials.append(mat_strap)
        obj = bpy.data.objects.new(f"{WARHEAD_PREFIX}Styazka_{idx + 1}", mesh)
        link_object(obj, Matrix.Identity(4))

        # Ratchet buckle block on side of strap
        build_box_mesh(
            f"{WARHEAD_PREFIX}Styazka_Buckle_{idx + 1}",
            center=Vector((x_strap, 0.0178, z_center - 0.003)),
            size=Vector((0.0062, 0.0042, 0.0058)),
            world_mat=Matrix.Identity(4),
            mat=mat_strap,
            bevel_amt=0.0005,
        )


def main():
    clear_scene()
    if not os.path.exists(GLB_PATH):
        raise FileNotFoundError(f"Missing GLB: {GLB_PATH}")
    bpy.ops.import_scene.gltf(filepath=GLB_PATH)
    remove_existing_warhead()
    build_warhead()

    # Deselect / select all for clean full-scene export
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format='GLB',
        export_yup=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
    )
    for p in _TEMP_FILES:
        try:
            os.remove(p)
        except OSError:
            pass
    print(f"[blender_add_quad5_warhead] Exported updated quad5_custom.glb ({os.path.getsize(GLB_PATH)} bytes)")


if __name__ == "__main__":
    main()
