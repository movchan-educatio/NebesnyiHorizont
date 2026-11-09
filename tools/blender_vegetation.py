"""Blender 5.x generator for the frontline vegetation library.

Builds, entirely from Python:
  * a broadleaf tree family (3 shape variants) with tapered trunk, real
    branches, sub-branches and alpha-cut leaf-spray cards;
  * a conifer family (2 variants) with a trunk and needle-spray cards;
  * a 3D grass clump and a cheaper field tuft;
  * hero versions of the oak and pine with collision and a baked wind
    animation (two perpendicular shape keys driven out of phase).

Outputs (all paths relative to the Godot project):
  Assets/frontline/vegetation/vegetation_library.glb
  Assets/frontline/vegetation/oak_hero.glb
  Assets/frontline/vegetation/pine_hero.glb
  Assets/frontline/vegetation/leaf_atlas.png
  Assets/frontline/vegetation/pine_atlas.png
  Assets/frontline/vegetation/bark_albedo.png
  Assets/frontline/vegetation/bark_normal.png
  qa_shots/vegetation/*.png preview renders

Run:
  blender -b --factory-startup --python tools/blender_vegetation.py
"""

import bpy
import math
import os
import struct
import zlib
from mathutils import Vector

try:
    import numpy as np
except Exception as exc:  # pragma: no cover
    raise RuntimeError("numpy is required") from exc

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(PROJECT, "Assets", "frontline", "vegetation")
QA_DIR = os.path.join(os.path.dirname(PROJECT), "qa_shots", "vegetation")
os.makedirs(ASSET_DIR, exist_ok=True)
os.makedirs(QA_DIR, exist_ok=True)

TAU = math.pi * 2.0
SKIP_RENDER = os.environ.get("VEG_SKIP_RENDER", "0") == "1"


# ---------------------------------------------------------------------------
#  PNG writer (exact sRGB bytes, no colour-management surprises)
# ---------------------------------------------------------------------------
def write_png(path, arr):
    arr = np.ascontiguousarray(arr.astype(np.uint8))
    h, w = arr.shape[:2]
    channels = arr.shape[2] if arr.ndim == 3 else 1
    color_type = {1: 0, 3: 2, 4: 6}[channels]
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def smoothstep(e0, e1, x):
    # e0 may be greater than e1 (inverted ramp, used for anti-aliased lines):
    # dividing by a clamped positive epsilon turned that case into "everything
    # outside the line is opaque", which filled whole quads with a brown slab.
    den = e1 - e0
    if abs(den) < 1e-6:
        return np.where(x < e0, 0.0, 1.0).astype(np.float32)
    t = np.clip((x - e0) / den, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
#  Procedural atlas textures
# ---------------------------------------------------------------------------
LEAF_COLORS = [
    (0.255, 0.420, 0.130),
    (0.300, 0.480, 0.150),
    (0.205, 0.355, 0.105),
    (0.340, 0.500, 0.165),
    (0.245, 0.395, 0.120),
    (0.285, 0.445, 0.140),
]
AUTUMN_COLORS = [
    (0.520, 0.400, 0.120),
    (0.470, 0.330, 0.095),
    (0.560, 0.450, 0.150),
]
PINE_COLORS = [
    (0.115, 0.230, 0.105),
    (0.140, 0.270, 0.115),
    (0.095, 0.200, 0.085),
    (0.165, 0.300, 0.130),
]


def _draw_leaf(canvas, cx, cy, angle, length, width, color, alpha_scale=1.0):
    h, w = canvas.shape[:2]
    ca, sa = math.cos(angle), math.sin(angle)
    ex = abs(length * ca) + abs(width * sa) + 3
    ey = abs(length * sa) + abs(width * ca) + 3
    x0 = max(0, int(cx - ex)); x1 = min(w, int(cx + ex) + 1)
    y0 = max(0, int(cy - ey)); y1 = min(h, int(cy + ey) + 1)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dx = xx - cx
    dy = yy - cy
    u = dx * ca + dy * sa
    v = -dx * sa + dy * ca
    t = np.clip(u / max(length, 1e-3), -1.0, 1.0)
    taper = np.clip(1.0 - t * t, 0.0, 1.0) ** 0.62
    # small serration on the leaf edge
    serr = 1.0 + 0.045 * np.sin(u * 1.35)
    halfw = width * taper * serr
    edge = halfw - np.abs(v)
    mask = smoothstep(-0.8, 0.9, edge) * (np.abs(t) < 0.995)
    # midrib + a couple of veins
    mid = np.exp(-(v * v) / (2.0 * max(width * 0.09, 0.7) ** 2))
    vein = (0.90
            + 0.07 * np.sin(u * 0.55 + v * 0.9)
            + 0.05 * np.sin(u * 1.7 - v * 0.4))
    shade = np.clip(vein + mid * 0.18, 0.0, 1.3)
    col = np.array(color, dtype=np.float32)[None, None, :] * shade[..., None]
    a = (mask * alpha_scale)[..., None]
    region = canvas[y0:y1, x0:x1, :3]
    canvas[y0:y1, x0:x1, :3] = region * (1.0 - a) + col * a
    ac = canvas[y0:y1, x0:x1, 3:4]
    canvas[y0:y1, x0:x1, 3:4] = ac * (1.0 - a) + a


def _draw_segment(canvas, x0, y0, x1, y1, width, color):
    h, w = canvas.shape[:2]
    pad = width + 3
    bx0 = max(0, int(min(x0, x1) - pad)); bx1 = min(w, int(max(x0, x1) + pad) + 1)
    by0 = max(0, int(min(y0, y1) - pad)); by1 = min(h, int(max(y0, y1) + pad) + 1)
    if bx0 >= bx1 or by0 >= by1:
        return
    yy, xx = np.mgrid[by0:by1, bx0:bx1]
    px, py = xx - x0, yy - y0
    vx, vy = x1 - x0, y1 - y0
    seg_len2 = max(vx * vx + vy * vy, 1e-6)
    t = np.clip((px * vx + py * vy) / seg_len2, 0.0, 1.0)
    dx = px - vx * t
    dy = py - vy * t
    d = np.sqrt(dx * dx + dy * dy)
    a = smoothstep(width * 0.5 + 1.3, width * 0.5 - 0.7, d)[..., None]
    col = np.array(color, dtype=np.float32)[None, None, :]
    region = canvas[by0:by1, bx0:bx1, :3]
    canvas[by0:by1, bx0:bx1, :3] = region * (1.0 - a) + col * a
    ac = canvas[by0:by1, bx0:bx1, 3:4]
    canvas[by0:by1, bx0:bx1, 3:4] = ac * (1.0 - a) + a


def _bleed_transparent(canvas):
    """Fill transparent RGB with the mean leaf colour so mipmaps do not bleed
    black into the cut-out edges."""
    alpha = canvas[..., 3]
    solid = alpha > 0.55
    if not np.any(solid):
        return
    mean = canvas[solid][:, :3].mean(axis=0)
    empty = alpha < 0.01
    canvas[empty, :3] = mean


def build_leaf_atlas(path, size=512, seed=7):
    """One atlas cell must read as a full leaf cluster, not a thin sprig.

    The earlier version drew a single narrow stem, so every 1.5 m card showed
    only a few dozen centimetres of leaves and the crowns looked like bare
    sticks.  Here four curved stems fan out from the bottom centre and fill
    most of the cell width with overlapping leaves.
    """
    rng = np.random.default_rng(seed)
    canvas = np.zeros((size, size, 4), dtype=np.float32)
    cell = size // 2
    for cell_index in range(4):
        cx0 = (cell_index % 2) * cell + 5
        cy0 = (cell_index // 2) * cell + 5
        cs = cell - 10
        # Keep all four cells green: the map is a summer frontline, and a
        # single autumn cell read as dead orange patches inside every crown.
        autumn = False
        palette = LEAF_COLORS
        base_x = cx0 + cs * 0.5 + rng.uniform(-0.05, 0.05) * cs
        base_y = cy0 + cs * 0.97
        stem_angles = [-2.18, -1.86, -1.28, -0.96]
        for si, ang in enumerate(stem_angles):
            ang += rng.uniform(-0.10, 0.10)
            reach = cs * (0.58 + 0.20 * (si % 2) + rng.uniform(-0.05, 0.08))
            pts = [(base_x, base_y)]
            steps = 4
            for k in range(1, steps + 1):
                t = k / float(steps)
                px = base_x + math.cos(ang) * reach * t
                py = base_y + math.sin(ang) * reach * t
                px += math.sin(t * 4.2 + si) * cs * 0.025
                py += math.cos(t * 3.1 + si) * cs * 0.018
                pts.append((px, py))
            for k in range(steps):
                _draw_segment(canvas, pts[k][0], pts[k][1], pts[k + 1][0],
                              pts[k + 1][1], cs * 0.012,
                              (0.26, 0.23, 0.10))
            # leaves alternate along both sides of the stem, getting denser
            # towards the tip so the card silhouette stays full
            n_leaves = 13
            for i in range(n_leaves):
                t = 0.12 + 0.86 * (i / (n_leaves - 1.0))
                seg = min(steps - 1, int(t * steps))
                local = t * steps - seg
                sx = pts[seg][0] + (pts[seg + 1][0] - pts[seg][0]) * local
                sy = pts[seg][1] + (pts[seg + 1][1] - pts[seg][1]) * local
                side = -1.0 if i % 2 == 0 else 1.0
                out_len = cs * rng.uniform(0.07, 0.15) * (1.05 - 0.25 * t)
                leaf_ang = ang + side * rng.uniform(0.55, 1.15)
                lx = sx + math.cos(leaf_ang) * out_len
                ly = sy + math.sin(leaf_ang) * out_len
                _draw_segment(canvas, sx, sy, lx, ly, cs * 0.0055,
                              (0.27, 0.24, 0.10))
                length = cs * rng.uniform(0.075, 0.115)
                width = cs * rng.uniform(0.034, 0.052)
                color = palette[int(rng.integers(0, len(palette)))]
                color = tuple(float(c * rng.uniform(0.86, 1.14)) for c in color)
                _draw_leaf(canvas,
                           lx + math.cos(leaf_ang) * length * 0.55,
                           ly + math.sin(leaf_ang) * length * 0.55,
                           leaf_ang, length, width, color)
        # low fill leaves hide the bare stem bases
        for i in range(10):
            ang = -math.pi * 0.5 + rng.uniform(-1.25, 1.25)
            dist = cs * rng.uniform(0.05, 0.22)
            length = cs * rng.uniform(0.085, 0.125)
            width = cs * rng.uniform(0.038, 0.055)
            color = palette[int(rng.integers(0, len(palette)))]
            _draw_leaf(canvas,
                       base_x + math.cos(ang) * dist,
                       base_y + math.sin(ang) * dist,
                       ang, length, width, color)
    _bleed_transparent(canvas)
    rgba = np.clip(canvas * 255.0, 0, 255).astype(np.uint8)
    write_png(path, rgba)
    return path


def build_pine_atlas(path, size=512, seed=11):
    rng = np.random.default_rng(seed)
    canvas = np.zeros((size, size, 4), dtype=np.float32)
    cell = size // 2
    for cell_index in range(4):
        cx0 = (cell_index % 2) * cell + 8
        cy0 = (cell_index // 2) * cell + 8
        cs = cell - 16
        base_x = cx0 + cs * 0.5 + rng.uniform(-0.06, 0.06) * cs
        base_y = cy0 + cs * 0.97
        top_x = cx0 + cs * 0.5 + rng.uniform(-0.12, 0.12) * cs
        top_y = cy0 + cs * 0.05
        # main twig
        prev = (base_x, base_y)
        for k in range(1, 7):
            t = k / 6.0
            x = base_x + (top_x - base_x) * t
            y = base_y + (top_y - base_y) * t
            _draw_segment(canvas, prev[0], prev[1], x, y, cs * 0.016,
                          (0.24, 0.19, 0.09))
            prev = (x, y)
        # needles: two dense fans left/right of the twig
        for i in range(64):
            t = 0.04 + 0.92 * rng.random()
            sx = base_x + (top_x - base_x) * t
            sy = base_y + (top_y - base_y) * t
            side = -1.0 if i % 2 == 0 else 1.0
            spread = rng.uniform(0.42, 1.32)
            length = cs * rng.uniform(0.13, 0.26) * (1.0 - 0.30 * t)
            ang = side * spread + rng.uniform(-0.16, 0.16)
            ex = sx + math.cos(ang) * length
            ey = sy + math.sin(ang) * length
            color = PINE_COLORS[int(rng.integers(0, len(PINE_COLORS)))]
            color = tuple(float(c * rng.uniform(0.85, 1.15)) for c in color)
            _draw_segment(canvas, sx, sy, ex, ey, cs * rng.uniform(0.006, 0.011),
                          color)
        # a short dense tuft at the top
        for i in range(12):
            sx = top_x + rng.uniform(-0.04, 0.04) * cs
            sy = top_y + rng.uniform(0.0, 0.12) * cs
            ang = -math.pi * 0.5 + rng.uniform(-0.9, 0.9)
            length = cs * rng.uniform(0.06, 0.12)
            color = PINE_COLORS[int(rng.integers(0, len(PINE_COLORS)))]
            _draw_segment(canvas, sx, sy,
                          sx + math.cos(ang) * length,
                          sy + math.sin(ang) * length,
                          cs * 0.007, color)
    _bleed_transparent(canvas)
    rgba = np.clip(canvas * 255.0, 0, 255).astype(np.uint8)
    write_png(path, rgba)
    return path


def _value_noise(w, h, freq_x, freq_y, rng):
    gw, gh = int(freq_x) + 2, int(freq_y) + 2
    grid = rng.random((gh, gw)).astype(np.float32)
    xs = np.linspace(0, freq_x, w, endpoint=False, dtype=np.float32)
    ys = np.linspace(0, freq_y, h, endpoint=False, dtype=np.float32)
    x0 = xs.astype(np.int32); y0 = ys.astype(np.int32)
    fx = xs - x0; fy = ys - y0
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    x0 = np.clip(x0, 0, gw - 2); y0 = np.clip(y0, 0, gh - 2)
    g00 = grid[y0][:, x0]
    g10 = grid[y0][:, x0 + 1]
    g01 = grid[y0 + 1][:, x0]
    g11 = grid[y0 + 1][:, x0 + 1]
    top = g00 * (1 - fx)[None, :] + g10 * fx[None, :]
    bot = g01 * (1 - fx)[None, :] + g11 * fx[None, :]
    return top * (1 - fy)[:, None] + bot * fy[:, None]


def build_bark_textures(albedo_path, normal_path, size=512, seed=23):
    rng = np.random.default_rng(seed)
    h = w = size
    u = np.linspace(0, 1, w, endpoint=False, dtype=np.float32)
    v = np.linspace(0, 1, h, endpoint=False, dtype=np.float32)
    height = np.zeros((h, w), dtype=np.float32)
    # periodic vertical ridges with wavy edges
    for k in (3, 5, 8, 11, 17, 23, 31):
        phase = float(rng.uniform(0, TAU))
        amp = 1.0 / (k ** 0.85)
        warp = 2.4 * np.sin(v[:, None] * TAU * rng.uniform(1.0, 2.2) + phase * 0.7)
        height += amp * np.sin(u[None, :] * TAU * k + phase + warp)
    detail = (_value_noise(w, h, 26, 9, rng) - 0.5) * 0.42
    detail += (_value_noise(w, h, 64, 22, rng) - 0.5) * 0.16
    height = height * 0.5 + detail
    height = (height - height.min()) / max(float(height.max() - height.min()), 1e-5)

    # cracks: narrow dark valleys
    crack = smoothstep(0.16, 0.02, np.abs(height - 0.5)) * 0.55
    moss = smoothstep(0.58, 0.80,
                      _value_noise(w, h, 7, 5, rng) * 0.7
                      + _value_noise(w, h, 19, 13, rng) * 0.3)
    moss *= 0.65
    base_dark = np.array([0.150, 0.105, 0.070], dtype=np.float32)
    base_light = np.array([0.430, 0.345, 0.250], dtype=np.float32)
    moss_col = np.array([0.265, 0.330, 0.135], dtype=np.float32)
    rgb = base_dark[None, None, :] + (base_light - base_dark)[None, None, :] * height[..., None]
    rgb = rgb * (1.0 - crack[..., None] * 0.55)
    rgb = rgb * (1.0 - moss[..., None]) + moss_col[None, None, :] * moss[..., None]
    rgb *= (0.86 + 0.28 * _value_noise(w, h, 96, 96, rng))[..., None]
    write_png(albedo_path, np.clip(rgb * 255.0, 0, 255).astype(np.uint8))

    # normal map from the height field
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    strength = 5.0
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(nx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= norm; ny /= norm; nz /= norm
    nrm = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], axis=-1)
    write_png(normal_path, np.clip(nrm * 255.0, 0, 255).astype(np.uint8))


# ---------------------------------------------------------------------------
#  Mesh builder
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.uvs = []
        self.colors = []
        self.materials = []
        self.smooth = []

    def vertex(self, p, uv, color):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        self.uvs.append((float(uv[0]), float(uv[1])))
        self.colors.append((float(color[0]), float(color[1]), float(color[2]),
                            float(color[3])))
        return len(self.verts) - 1

    def face(self, indices, material=0, smooth=False):
        self.faces.append(tuple(indices))
        self.materials.append(material)
        self.smooth.append(smooth)

    def quad(self, p0, p1, p2, p3, uv0, uv1, uv2, uv3, color, material=0,
             smooth=False):
        a = self.vertex(p0, uv0, color)
        b = self.vertex(p1, uv1, color)
        c = self.vertex(p2, uv2, color)
        d = self.vertex(p3, uv3, color)
        self.face([a, b, c, d], material, smooth)
        return a, b, c, d

    def build_object(self, materials, collection=None):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.update(calc_edges=True)
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            for loop_index in poly.loop_indices:
                vi = mesh.loops[loop_index].vertex_index
                uv_layer.data[loop_index].uv = self.uvs[vi]
        colors = mesh.color_attributes.new(name="Col", type='FLOAT_COLOR',
                                           domain='CORNER')
        for poly in mesh.polygons:
            for loop_index in poly.loop_indices:
                vi = mesh.loops[loop_index].vertex_index
                colors.data[loop_index].color = self.colors[vi]
        for mat in materials:
            mesh.materials.append(mat)
        for i, poly in enumerate(mesh.polygons):
            poly.material_index = (0 if not materials
                                   else min(self.materials[i], len(materials) - 1))
            poly.use_smooth = self.smooth[i]
        mesh.validate(verbose=False)
        obj = bpy.data.objects.new(self.name, mesh)
        (collection or bpy.context.collection).objects.link(obj)
        return obj


def _tube(mb, points, radii, sides, material, color=(1, 1, 1, 1),
          uv_v_scale=1.0, cap_end=True, cap_start=False, smooth=True):
    n = len(points)
    tangents = []
    for i in range(n):
        if i == 0:
            t = points[1] - points[0]
        elif i == n - 1:
            t = points[-1] - points[-2]
        else:
            t = points[i + 1] - points[i - 1]
        tangents.append(t.normalized())
    nrm = tangents[0].cross(Vector((0, 0, 1)))
    if nrm.length < 0.2:
        nrm = tangents[0].cross(Vector((1, 0, 0)))
    nrm.normalize()
    rings = []
    acc_v = 0.0
    for i in range(n):
        if i > 0:
            acc_v += (points[i] - points[i - 1]).length
        t = tangents[i]
        projected = nrm - t * nrm.dot(t)
        if projected.length > 1e-5:
            nrm = projected.normalized()
        binorm = t.cross(nrm).normalized()
        ring = []
        for s in range(sides):
            ang = TAU * s / sides
            off = nrm * (math.cos(ang) * radii[i]) + binorm * (math.sin(ang) * radii[i])
            uv = (s / sides * 2.0, acc_v / max(uv_v_scale, 0.001))
            ring.append(mb.vertex(points[i] + off, uv, color))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            mb.face([rings[i][s], rings[i][s2], rings[i + 1][s2],
                     rings[i + 1][s]], material, smooth)
    if cap_end:
        last = rings[-1]
        center_uv = (0.5, acc_v / max(uv_v_scale, 0.001))
        ci = mb.vertex(points[-1], center_uv, color)
        for s in range(sides):
            s2 = (s + 1) % sides
            mb.face([ci, last[s], last[s2]], material, smooth)
    if cap_start:
        first = rings[0]
        ci = mb.vertex(points[0], (0.5, 0.0), color)
        for s in range(sides):
            s2 = (s + 1) % sides
            mb.face([ci, first[s2], first[s]], material, smooth)


def _card(mb, center, u, v, cell, brightness, sway, material=0, atlas_cells=2,
          phase=0.0):
    """Add one textured leaf card.  `u` and `v` are half-extent vectors.

    Vertex colour encodes, for the Godot wind shader: R = brightness,
    G = per-card phase (0..1), B = 1, A = sway weight (0 at trunk, 1 at tip).
    """
    col = (brightness, phase, 1.0, sway)
    p0 = center - u - v
    p1 = center + u - v
    p2 = center + u + v
    p3 = center - u + v
    col_u = cell % atlas_cells
    col_v = cell // atlas_cells
    inset = 0.006
    step = 1.0 / atlas_cells
    u0 = col_u * step + inset
    v0 = col_v * step + inset
    u1 = (col_u + 1) * step - inset
    v1 = (col_v + 1) * step - inset
    mb.quad(p0, p1, p2, p3, (u0, v0), (u1, v0), (u1, v1), (u0, v1),
            col, material, smooth=False)


def _leaf_cluster(mb, center, size, rng, sway, material=0, cards=3,
                  autumn=False, brightness=1.0):
    for i in range(cards):
        yaw = rng.uniform(0, TAU)
        pitch = rng.uniform(-0.85, 0.85)
        cu = Vector((math.cos(yaw), math.sin(yaw), 0.0)) * (size * 0.5)
        cv = Vector((-math.sin(yaw) * math.cos(pitch),
                     math.cos(yaw) * math.cos(pitch),
                     math.sin(pitch))) * (size * 0.5)
        offset = Vector((rng.uniform(-0.22, 0.22),
                         rng.uniform(-0.22, 0.22),
                         rng.uniform(-0.18, 0.18))) * size
        b = brightness * rng.uniform(0.80, 1.0)
        cell = int(rng.integers(0, 4))
        # The fourth atlas cell is autumn; only use it when the caller wants
        # an autumn tree.  Otherwise every summer crown gets brown patches.
        if not autumn and cell == 3:
            cell = 0
        _card(mb, center + offset, cu, cv, cell, b, sway, material,
              phase=rng.uniform(0.0, 1.0))


def _branch_segment(mb, start, direction, length, radius, material, rng,
                    segments=3, children=0, depth=0, sides=4):
    pts = [start]
    d = direction.normalized()
    for i in range(segments):
        d = (d + Vector((rng.uniform(-0.05, 0.05),
                         rng.uniform(-0.05, 0.05),
                         rng.uniform(-0.02, 0.06)))).normalized()
        pts.append(pts[-1] + d * (length / segments))
    radii = [radius * (1.0 - 0.78 * (i / segments)) for i in range(segments + 1)]
    _tube(mb, pts, radii, sides, material, uv_v_scale=0.9, cap_end=False,
          smooth=True)
    if children > 0 and depth < 2:
        for c in range(children):
            base = pts[-1] + (pts[-2] - pts[-1]) * rng.uniform(0.0, 0.35)
            side = Vector((math.cos(rng.uniform(0, TAU)),
                           math.sin(rng.uniform(0, TAU)),
                           rng.uniform(0.1, 0.5))).normalized()
            new_dir = (d * 0.55 + side * 0.65).normalized()
            _branch_segment(mb, base, new_dir, length * rng.uniform(0.45, 0.65),
                            radius * 0.55, material, rng,
                            segments=max(2, segments - 1), children=0,
                            depth=depth + 1, sides=sides)
    return pts


def build_broadleaf(name, seed, variant=0, hero=False):
    rng = np.random.default_rng(seed)
    trunk = MeshBuilder(name + "_trunk")
    leaves = MeshBuilder(name + "_leaves")
    height = rng.uniform(7.2, 9.4) if not hero else rng.uniform(8.2, 9.6)
    trunk_h = height * rng.uniform(0.56, 0.68)
    base_r = rng.uniform(0.26, 0.34) * (1.15 if hero else 1.0)
    lean_x = rng.uniform(-0.25, 0.25)
    lean_y = rng.uniform(-0.25, 0.25)
    # trunk path with a gentle S curve and a root flare.  The instanced library
    # meshes use a lighter trunk (6 sides, 5 rings) than the hero trees: at
    # 8-13 m the 8-sided/8-ring version was invisible but cost a third of the
    # GPU budget when 400+ trees were on screen.
    pts = []
    radii = []
    trunk_points = 8 if hero else 6
    trunk_sides = 8 if hero else 6
    for i in range(trunk_points):
        t = i / float(trunk_points - 1)
        x = lean_x * (t ** 1.7) + math.sin(t * 3.4) * 0.16
        y = lean_y * (t ** 1.7) + math.cos(t * 2.9) * 0.13
        z = trunk_h * t
        pts.append(Vector((x, y, z)))
        radii.append(base_r * (1.0 - 0.62 * t) + base_r * 0.34 * (1.0 - t) ** 5)
    _tube(trunk, pts, radii, trunk_sides, 0, uv_v_scale=1.05, cap_end=False,
          cap_start=False, smooth=True)
    # root flare: short buttress roots, only a silhouette cue
    root_count = 5 if hero else 3
    for i in range(root_count):
        ang = TAU * i / float(root_count) + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(ang), math.sin(ang), -0.18)).normalized()
        _branch_segment(trunk, Vector((0, 0, 0.25)), d,
                        0.65 + rng.uniform(0, 0.35), base_r * 0.45, 0, rng,
                        segments=2 if hero else 1, children=0,
                        sides=4 if hero else 3)
    # main branches + sub-branches + leaf clusters
    branch_count = 7 if hero else 6
    branch_levels = np.linspace(0.34, 0.94, branch_count)
    for i, level in enumerate(branch_levels):
        t = float(level)
        idx = min(len(pts) - 1, int(t * (len(pts) - 1)))
        start = pts[idx] * 1.0
        az = TAU * i / branch_count + rng.uniform(-0.32, 0.32)
        elev = rng.uniform(0.38, 0.82)
        d = Vector((math.cos(az) * (1.0 - elev * 0.45),
                    math.sin(az) * (1.0 - elev * 0.45),
                    elev + 0.25)).normalized()
        length = rng.uniform(1.15, 1.95) * (1.0 - 0.24 * abs(t - 0.55))
        radius = base_r * (0.42 - 0.24 * t) + 0.012
        seg_pts = _branch_segment(trunk, start, d, length, radius, 0, rng,
                                  segments=3 if hero else 2,
                                  children=1 if hero else 0, depth=0,
                                  sides=5 if hero else 3)
        # Clusters run from the middle of the branch all the way past its tip,
        # so no bare wooden spikes stick out of the crown.
        branch_clusters = 2 if not hero else 4
        for k in range(branch_clusters):
            f = 0.50 + 0.66 * (k / max(1, branch_clusters - 1))
            c = seg_pts[0].lerp(seg_pts[-1], min(1.16, f))
            c.z += rng.uniform(-0.15, 0.25)
            sz = (rng.uniform(1.35, 1.85) if hero else rng.uniform(1.55, 2.05))
            sway = min(1.0, max(0.05, c.z / height))
            _leaf_cluster(leaves, c, sz, rng, sway, 0,
                          cards=3, brightness=rng.uniform(0.86, 1.0))
    # crown fill clusters in an ellipsoid shell
    crown_z0 = height * 0.40
    crown_z1 = height * 1.00
    crown_r = height * rng.uniform(0.38, 0.44)
    fill_count = 56 if hero else 22
    for i in range(fill_count):
        ang = rng.uniform(0, TAU)
        # Bias towards the outer shell: a hollow crown hides the branches and
        # reads as a full canopy from every approach angle.
        rr = crown_r * math.sqrt(rng.uniform(0.45, 1.0))
        z = rng.uniform(crown_z0, crown_z1)
        # narrow the crown towards the top
        top_t = (z - crown_z0) / max(crown_z1 - crown_z0, 0.001)
        rr *= 1.0 - 0.52 * (top_t ** 2)
        c = Vector((math.cos(ang) * rr + lean_x * 0.7,
                    math.sin(ang) * rr + lean_y * 0.7,
                    z))
        sz = rng.uniform(1.35, 1.85) if hero else rng.uniform(1.55, 2.05)
        sway = min(1.0, max(0.05, z / height))
        _leaf_cluster(leaves, c, sz, rng, sway, 0, cards=3,
                      brightness=rng.uniform(0.80, 0.98))
    # a few low under-crown sprays break the umbrella silhouette
    for i in range(5 if not hero else 12):
        ang = rng.uniform(0, TAU)
        rr = crown_r * rng.uniform(0.55, 0.95)
        z = rng.uniform(height * 0.30, height * 0.46)
        c = Vector((math.cos(ang) * rr, math.sin(ang) * rr, z))
        _leaf_cluster(leaves, c, rng.uniform(1.35, 1.75), rng,
                      min(1.0, z / height), 0, cards=3,
                      brightness=rng.uniform(0.70, 0.88))
    trunk_obj = trunk.build_object([bark_material])
    leaf_obj = leaves.build_object([leaf_material])
    return trunk_obj, leaf_obj, height


def build_conifer(name, seed, variant=0, hero=False):
    rng = np.random.default_rng(seed)
    trunk = MeshBuilder(name + "_trunk")
    leaves = MeshBuilder(name + "_leaves")
    height = rng.uniform(9.0, 12.0) if not hero else rng.uniform(10.0, 12.5)
    base_r = rng.uniform(0.24, 0.31) * (1.2 if hero else 1.0)
    lean_x = rng.uniform(-0.22, 0.22)
    lean_y = rng.uniform(-0.22, 0.22)
    pts = []
    radii = []
    trunk_points = 9 if hero else 6
    for i in range(trunk_points):
        t = i / float(trunk_points - 1)
        pts.append(Vector((lean_x * t ** 2, lean_y * t ** 2, height * t)))
        radii.append(base_r * (1.0 - 0.84 * t) + base_r * 0.22 * (1.0 - t) ** 6)
    _tube(trunk, pts, radii, 7 if hero else 6, 0, uv_v_scale=1.1,
          cap_end=True, cap_start=False, smooth=True)
    for i in range(4 if hero else 3):
        ang = TAU * i / float(4 if hero else 3) + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), math.sin(ang), -0.15)).normalized()
        _branch_segment(trunk, Vector((0, 0, 0.2)), d,
                        0.55 + rng.uniform(0, 0.25), base_r * 0.40, 0, rng,
                        segments=2 if hero else 1, children=0,
                        sides=4 if hero else 3)
    whorls = 10 if hero else 7
    for w in range(whorls):
        t = 0.22 + 0.76 * (w / max(whorls - 1, 1))
        idx = min(len(pts) - 1, int(t * (len(pts) - 1)))
        center = pts[idx]
        branch_n = 6 if hero else 5
        for b in range(branch_n):
            az = TAU * b / branch_n + w * 0.55 + rng.uniform(-0.22, 0.22)
            droop = rng.uniform(-0.28, -0.08) - 0.25 * t
            length = (1.0 - 0.72 * t) * height * rng.uniform(0.19, 0.26)
            length = max(length, 0.45)
            d = Vector((math.cos(az), math.sin(az), droop)).normalized()
            start = center + Vector((math.cos(az) * 0.08,
                                     math.sin(az) * 0.08, 0.0))
            seg = _branch_segment(trunk, start, d, length,
                                  max(0.035, base_r * (0.30 - 0.18 * t)), 0,
                                  rng, segments=2 if hero else 1, children=0,
                                  sides=4 if hero else 3)
            # Needle sprays along the branch: two fan positions even on the
            # instanced LOD, three on the hero tree.
            for k in range(3 if hero else 2):
                f = (0.32 if hero else 0.38) + 0.34 * k
                c = seg[0].lerp(seg[-1], f)
                c.z += 0.04
                sz = rng.uniform(1.30, 1.95) * (1.0 - 0.25 * t)
                sway = min(1.0, max(0.06, c.z / height))
                yaw = az + rng.uniform(-0.5, 0.5)
                # horizontal card
                cu = Vector((math.cos(yaw), math.sin(yaw), 0)) * sz * 0.5
                cv = Vector((-math.sin(yaw), math.cos(yaw), 0)) * sz * 0.42
                _card(leaves, c, cu, cv, int(rng.integers(0, 4)),
                      rng.uniform(0.82, 1.0), sway, 0,
                      phase=rng.uniform(0.0, 1.0))
                # tilted card, breaks the flat disk silhouette
                pitch = rng.uniform(0.55, 1.15)
                cv2 = Vector((-math.sin(yaw) * math.cos(pitch),
                              math.cos(yaw) * math.cos(pitch),
                              math.sin(pitch))) * sz * 0.44
                _card(leaves, c + Vector((0, 0, 0.08)), cu, cv2,
                      int(rng.integers(0, 4)),
                      rng.uniform(0.78, 0.98), sway, 0,
                      phase=rng.uniform(0.0, 1.0))
    # top leader sprays
    for i in range(5 if hero else 3):
        z = height * rng.uniform(0.90, 1.01)
        yaw = rng.uniform(0, TAU)
        c = Vector((math.cos(yaw) * 0.10, math.sin(yaw) * 0.10, z))
        sz = rng.uniform(0.55, 0.85)
        cu = Vector((math.cos(yaw), math.sin(yaw), 0)) * sz * 0.5
        cv = Vector((-math.sin(yaw), math.cos(yaw), 0)) * sz * 0.45
        _card(leaves, c, cu, cv, int(rng.integers(0, 4)), 0.85, 1.0, 0,
              phase=rng.uniform(0.0, 1.0))
    trunk_obj = trunk.build_object([bark_material])
    leaf_obj = leaves.build_object([pine_material])
    return trunk_obj, leaf_obj, height


def build_grass(name, blades=14, seed=101, tuft=False):
    rng = np.random.default_rng(seed)
    mb = MeshBuilder(name)
    radius = 0.20 if not tuft else 0.38
    h_lo, h_hi = (0.20, 0.55) if not tuft else (0.16, 0.46)
    for b in range(blades):
        ang = rng.uniform(0, TAU)
        dist = radius * math.sqrt(rng.uniform(0.0, 1.0))
        root = Vector((math.cos(ang) * dist, math.sin(ang) * dist, -0.02))
        yaw = rng.uniform(0, TAU)
        h = rng.uniform(h_lo, h_hi)
        width = rng.uniform(0.008, 0.017) * (1.25 if tuft else 1.0)
        lean = h * rng.uniform(0.10, 0.34)
        side = Vector((math.cos(yaw), math.sin(yaw), 0)) * width
        out = Vector((math.cos(ang + rng.uniform(-0.7, 0.7)),
                      math.sin(ang + rng.uniform(-0.7, 0.7)), 0))
        # three segments, tapering to a point; the tip bends over
        rings = []
        for s in range(3):
            t = s / 3.0
            c = root + Vector((0, 0, h * t)) + out * (lean * (t ** 1.7))
            w = width * (1.0 - 0.78 * t)
            rings.append((c - side * w, c + side * w, t))
        tip = root + Vector((0, 0, h)) + out * (lean * 1.18)
        # per-blade colour: neutral brightness multiplier (the Godot grass
        # shader supplies the per-map green/straw palette), a few blades warm
        # and dry so the carpet is not a single hue
        dry = rng.uniform(0.0, 1.0) < 0.18
        if dry:
            base_col = (0.86, 0.74, 0.48)
            tip_col = (1.0, 0.92, 0.68)
        else:
            shade = rng.uniform(0.80, 1.0)
            base_col = (0.82 * shade, 0.82 * shade, 0.82 * shade)
            tip_col = (0.98 * shade, 0.98 * shade, 0.98 * shade)
        # build the strip
        for s in range(3):
            t0 = s / 3.0
            t1 = (s + 1) / 3.0
            a0 = rings[s][0]; b0 = rings[s][1]
            if s < 2:
                a1 = rings[s + 1][0]; b1 = rings[s + 1][1]
            else:
                a1 = tip; b1 = tip
            c0 = _mix(base_col, tip_col, t0)
            c1 = _mix(base_col, tip_col, t1)
            v0 = 1.0 - t0
            v1 = 1.0 - t1
            if s < 2:
                mb.quad(a0, b0, b1, a1,
                        (0.0, v0), (1.0, v0), (1.0, v1), (0.0, v1),
                        (c0[0], c0[1], c0[2], 1.0), 0, smooth=True)
            else:
                c = mb.vertex(a0, (0.0, v0), (c0[0], c0[1], c0[2], 1.0))
                c2 = mb.vertex(b0, (1.0, v0), (c0[0], c0[1], c0[2], 1.0))
                c3 = mb.vertex(tip, (0.5, 0.0), (c1[0], c1[1], c1[2], 1.0))
                mb.face([c, c2, c3], 0, smooth=True)
    obj = mb.build_object([grass_material])
    return obj


def _mix(a, b, t):
    return (a[0] * (1 - t) + b[0] * t,
            a[1] * (1 - t) + b[1] * t,
            a[2] * (1 - t) + b[2] * t)


def add_sway_shape_keys(obj, wind_amp=0.16):
    mesh = obj.data
    base = [v.co.copy() for v in mesh.vertices]
    obj.shape_key_add(name="Basis", from_mix=False)
    key_x = obj.shape_key_add(name="WindX", from_mix=False)
    key_y = obj.shape_key_add(name="WindY", from_mix=False)
    colors = mesh.color_attributes.get("Col")
    sway = []
    if colors is not None:
        for i in range(len(mesh.vertices)):
            sway.append(colors.data[i].color[3])
    else:
        sway = [1.0] * len(mesh.vertices)
    for i, co in enumerate(base):
        w = sway[i]
        phase = (i * 0.61803398875) % 1.0
        dx = wind_amp * w * (0.55 + 0.45 * math.cos(phase * TAU))
        dy = wind_amp * w * 0.22 * math.sin(phase * TAU)
        key_x.data[i].co = co + Vector((dx, dy, 0.0))
        dx2 = wind_amp * w * 0.22 * math.sin((phase + 0.37) * TAU)
        dy2 = wind_amp * w * (0.55 + 0.45 * math.cos((phase + 0.37) * TAU))
        key_y.data[i].co = co + Vector((dx2, dy2, 0.0))
    # animate the two keys out of phase for a looping circular sway
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 121
    ad = obj.data.shape_keys.animation_data_create()
    if ad.action is None:
        ad.action = bpy.data.actions.new("Sway")
    for f in range(1, 122, 5):
        t = (f - 1) / 120.0 * TAU
        key_x.value = 0.5 + 0.5 * math.sin(t)
        key_y.value = 0.5 + 0.5 * math.cos(t * 0.93 + 0.6)
        key_x.keyframe_insert(data_path="value", frame=f)
        key_y.keyframe_insert(data_path="value", frame=f)
    action = ad.action
    if action is not None:
        action.name = "Sway"


def add_trunk_collision(name, height, radius, collection):
    mb = MeshBuilder(name)
    pts = [Vector((0, 0, 0)), Vector((0, 0, height * 0.45)),
           Vector((0, 0, height))]
    _tube(mb, pts, [radius, radius * 0.75, radius * 0.55], 6, 0,
          uv_v_scale=1.0, cap_end=True, cap_start=True, smooth=False)
    obj = mb.build_object([], collection)
    return obj


# ---------------------------------------------------------------------------
#  Materials
# ---------------------------------------------------------------------------
def _load_image(path, non_color=False):
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    return img


def make_materials():
    global bark_material, leaf_material, pine_material, grass_material
    bark = bpy.data.materials.new("bark")
    bark.use_nodes = True
    nt = bark.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    albedo = nt.nodes.new("ShaderNodeTexImage")
    albedo.image = _load_image(os.path.join(ASSET_DIR, "bark_albedo.png"))
    nt.links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
    normal_tex = nt.nodes.new("ShaderNodeTexImage")
    normal_tex.image = _load_image(os.path.join(ASSET_DIR, "bark_normal.png"),
                                   non_color=True)
    normal_map = nt.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.85
    nt.links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    bark.use_backface_culling = False

    leaf = bpy.data.materials.new("leaf_spray")
    leaf.use_nodes = True
    nt = leaf.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _load_image(os.path.join(ASSET_DIR, "leaf_atlas.png"))
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.90
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Strength"].default_value = 0.0
    leaf.use_backface_culling = False
    leaf.surface_render_method = 'DITHERED'

    pine = bpy.data.materials.new("pine_spray")
    pine.use_nodes = True
    nt = pine.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _load_image(os.path.join(ASSET_DIR, "pine_atlas.png"))
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    pine.use_backface_culling = False
    pine.surface_render_method = 'DITHERED'

    grass = bpy.data.materials.new("grass")
    grass.use_nodes = True
    nt = grass.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Metallic"].default_value = 0.0
    grass.use_backface_culling = False
    grass.surface_render_method = 'DITHERED'

    bark_material = bark
    leaf_material = leaf
    pine_material = pine
    grass_material = grass
    return bark, leaf, pine, grass


# ---------------------------------------------------------------------------
#  Export helpers
# ---------------------------------------------------------------------------
def select_only(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        obj.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def export_glb(path, objects, animations=False):
    select_only(objects)
    kwargs = dict(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_skins=False,
        export_morph=animations,
        export_morph_animation=animations,
        export_animations=animations,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_frame_range=animations,
        export_optimize_animation_size=False,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=True,
        export_attributes=False,
    )
    bpy.ops.export_scene.gltf(**kwargs)
    print("[Veg] exported", path, os.path.getsize(path), "bytes")


def make_root(name, children, collection):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = 0.5
    collection.objects.link(root)
    for child in children:
        child.parent = root
    return root


# ---------------------------------------------------------------------------
#  Preview render
# ---------------------------------------------------------------------------
def _try_engine(scene):
    for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
        try:
            scene.render.engine = engine
            return engine
        except TypeError:
            continue
    return scene.render.engine


def render_preview(name, objs, cam_pos, look_at, focal=45, frame=1,
                   res=(900, 900)):
    scene = bpy.context.scene
    engine = _try_engine(scene)
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.join(QA_DIR, name + ".png")
    if engine == 'CYCLES':
        scene.cycles.samples = 24
        scene.cycles.use_denoising = True
    else:
        try:
            scene.eevee.taa_render_samples = 32
        except AttributeError:
            pass
    # world
    world = bpy.data.worlds.get("VegWorld")
    if world is None:
        world = bpy.data.worlds.new("VegWorld")
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.46, 0.62, 0.82, 1.0)
        bg.inputs["Strength"].default_value = 1.05
    scene.world = world

    # ground plane
    plane_mesh = bpy.data.meshes.new("preview_ground")
    plane_mesh.from_pydata([(-12, -12, 0), (12, -12, 0), (12, 12, 0),
                            (-12, 12, 0)], [], [(0, 1, 2, 3)])
    plane_obj = bpy.data.objects.new("preview_ground", plane_mesh)
    bpy.context.collection.objects.link(plane_obj)
    ground_mat = bpy.data.materials.new("preview_ground_mat")
    ground_mat.use_nodes = True
    gb = ground_mat.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.13, 0.16, 0.07, 1.0)
    gb.inputs["Roughness"].default_value = 0.95
    plane_mesh.materials.append(ground_mat)

    # sun
    sun_data = bpy.data.lights.new("preview_sun", type='SUN')
    sun_data.energy = 4.2
    sun_data.angle = math.radians(2.0)
    sun_obj = bpy.data.objects.new("preview_sun", sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(52), math.radians(8), math.radians(-38))

    # camera
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.lens = focal
    cam_obj = bpy.data.objects.new("preview_cam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = cam_pos
    direction = Vector(look_at) - Vector(cam_pos)
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam_obj

    scene.frame_set(frame)
    # hide everything except the provided objects and the set
    keep = set(objs) | {plane_obj, sun_obj, cam_obj}
    hidden = []
    for obj in bpy.context.scene.objects:
        if obj not in keep and not obj.hide_render:
            obj.hide_render = True
            hidden.append(obj)
    bpy.ops.render.render(write_still=True)
    for obj in hidden:
        obj.hide_render = False
    for obj in (plane_obj, sun_obj, cam_obj):
        bpy.data.objects.remove(obj, do_unlink=True)
    print("[Veg] preview", name)


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
def main():
    # clean scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)

    print("[Veg] generating textures")
    leaf_atlas = os.path.join(ASSET_DIR, "leaf_atlas.png")
    pine_atlas = os.path.join(ASSET_DIR, "pine_atlas.png")
    bark_albedo = os.path.join(ASSET_DIR, "bark_albedo.png")
    bark_normal = os.path.join(ASSET_DIR, "bark_normal.png")
    build_leaf_atlas(leaf_atlas)
    build_pine_atlas(pine_atlas)
    build_bark_textures(bark_albedo, bark_normal)
    print("[Veg] textures written")

    make_materials()
    collection = bpy.context.collection

    # ----- library: trees + grass -----------------------------------------
    library_objects = []
    grass_obj = build_grass("grass_clump", blades=14, seed=101)
    tuft_obj = build_grass("grass_tuft", blades=6, seed=202, tuft=True)
    library_objects += [grass_obj, tuft_obj]

    tree_specs = [
        ("oak_a", 1001, "broadleaf", 0),
        ("oak_b", 1002, "broadleaf", 1),
        ("oak_c", 1003, "broadleaf", 2),
        ("pine_a", 2001, "conifer", 0),
        ("pine_b", 2002, "conifer", 1),
    ]
    for name, seed, kind, variant in tree_specs:
        if kind == "broadleaf":
            trunk, leaves, h = build_broadleaf(name, seed, variant)
        else:
            trunk, leaves, h = build_conifer(name, seed, variant)
        root = make_root(name, [trunk, leaves], collection)
        library_objects += [root, trunk, leaves]
        print("[Veg] built", name, "height", round(h, 2),
              "verts", len(leaves.data.vertices), "faces", len(leaves.data.polygons))

    # export the library
    export_glb(os.path.join(ASSET_DIR, "vegetation_library.glb"),
               library_objects, animations=False)

    # ----- hero oak -------------------------------------------------------
    hero_oak_trunk, hero_oak_leaves, hero_oak_h = build_broadleaf(
        "oak_leaves", 5001, 0, hero=True)
    hero_oak_trunk.name = "trunk"
    hero_oak_leaves.name = "leaves"
    add_sway_shape_keys(hero_oak_leaves, 0.18)
    oak_collision = add_trunk_collision("oak-convcolonly", hero_oak_h * 0.62,
                                        0.55, collection)
    oak_root = make_root("oak", [hero_oak_trunk, hero_oak_leaves,
                                 oak_collision], collection)
    export_glb(os.path.join(ASSET_DIR, "oak_hero.glb"),
               [oak_root, hero_oak_trunk, hero_oak_leaves, oak_collision],
               animations=True)

    # ----- hero pine ------------------------------------------------------
    hero_pine_trunk, hero_pine_leaves, hero_pine_h = build_conifer(
        "pine_leaves", 6001, 0, hero=True)
    hero_pine_trunk.name = "trunk"
    hero_pine_leaves.name = "leaves"
    add_sway_shape_keys(hero_pine_leaves, 0.14)
    pine_collision = add_trunk_collision("pine-convcolonly",
                                         hero_pine_h * 0.62, 0.50, collection)
    pine_root = make_root("pine", [hero_pine_trunk, hero_pine_leaves,
                                   pine_collision], collection)
    export_glb(os.path.join(ASSET_DIR, "pine_hero.glb"),
               [pine_root, hero_pine_trunk, hero_pine_leaves, pine_collision],
               animations=True)

    # ----- previews -------------------------------------------------------
    if not SKIP_RENDER:
        print("[Veg] rendering previews")
        scene = bpy.context.scene
        # keep everything visible by default; render_preview hides the rest
        for obj in bpy.context.scene.objects:
            obj.hide_render = False
        render_preview("grass_clump", [grass_obj],
                       (0.30, -1.45, 0.32), (0.0, 0.0, 0.24), focal=60)
        render_preview("oak_a", [library_objects[2], library_objects[3],
                                 library_objects[4]],
                       (9.0, -13.0, 5.4), (0.0, 0.0, 4.6), focal=50)
        render_preview("pine_a", [library_objects[11], library_objects[12],
                                  library_objects[13]],
                       (12.0, -17.0, 6.6), (0.0, 0.0, 6.0), focal=45)
        render_preview("oak_hero", [oak_root, hero_oak_trunk,
                                    hero_oak_leaves, oak_collision],
                       (7.5, -11.0, 4.8), (0.0, 0.0, 5.0), focal=55, frame=1)
        render_preview("oak_hero_sway", [oak_root, hero_oak_trunk,
                                         hero_oak_leaves, oak_collision],
                       (7.5, -11.0, 4.8), (0.0, 0.0, 5.0), focal=55, frame=31)
        # atlas contact sheets are just the PNGs
    print("[Veg] done")


if __name__ == "__main__":
    main()




