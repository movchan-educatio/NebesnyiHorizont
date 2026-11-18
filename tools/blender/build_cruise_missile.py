"""Build a HIGH-QUALITY low-poly cruise missile (Kh-101 / Kalibr / Tomahawk style).

Run headless:
  blender.exe -b -P tools/blender/build_cruise_missile.py -- --proj <project_root>

Conventions:
  Blender: nose = +Y, up = +Z. glTF export with Y-up maps this to
  Godot: nose = -Z (forward), up = +Y. Single root Empty, transforms applied.

Outputs:
  Assets/combat/cruise_missile.glb       intact flying missile
  Assets/combat/hit_cruise_missile.glb   shattered wreck for hit VFX
  tools/blender/preview_missile.png      hero preview render
  tools/blender/preview_wreck.png        wreck preview render
"""

import bpy
import math
import os
import sys
from mathutils import Vector

# ---- project root ---------------------------------------------------------
PROJ = None
argv = sys.argv
if "--proj" in argv:
    PROJ = argv[argv.index("--proj") + 1]
if not PROJ:
    PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSET_DIR = os.path.join(PROJ, "Assets", "combat")
TOOL_DIR = os.path.join(PROJ, "tools", "blender")
os.makedirs(ASSET_DIR, exist_ok=True)
os.makedirs(TOOL_DIR, exist_ok=True)

INTACT_GLB = os.path.join(ASSET_DIR, "cruise_missile.glb")
WRECK_GLB = os.path.join(ASSET_DIR, "hit_cruise_missile.glb")
PREVIEW_PNG = os.path.join(TOOL_DIR, "preview_missile.png")
WRECK_PNG = os.path.join(TOOL_DIR, "preview_wreck.png")

SEG = 20  # radial segments for fuselage (low-poly but smooth enough)


# ---- helpers --------------------------------------------------------------
def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(data):
            if block.users == 0:
                data.remove(block)


def material(name, color, metallic=0.0, roughness=0.8, emission=None):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        print("MAT", name, "base", tuple(bsdf.inputs['Base Color'].default_value[:3]))
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 1.2
    return m


def link_mesh(name, verts, faces, mat, parent=None, smooth=False):
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    return obj


def lathe(name, profile, mat, segments=SEG, parent=None, smooth=True, cap=True):
    """Surface of revolution around +Y. profile = list of (y, radius)."""
    verts = []
    for y, r in profile:
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            verts.append((math.cos(a) * r, y, math.sin(a) * r))
    faces = []
    for ring in range(len(profile) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a = ring * segments + i
            b = ring * segments + j
            c = (ring + 1) * segments + j
            d = (ring + 1) * segments + i
            faces.append((a, b, c, d))
    if cap:
        faces.append(tuple(range(segments - 1, -1, -1)))
        faces.append(tuple(range((len(profile) - 1) * segments, len(profile) * segments)))
    return link_mesh(name, verts, faces, mat, parent, smooth)


def ring_band(name, y, radius, width, mat, parent=None, segments=SEG):
    return lathe(name, [(y - width / 2, radius), (y + width / 2, radius)],
                 mat, segments, parent, smooth=False, cap=False)


def extruded_poly(name, top, bottom, mat, parent=None):
    """top/bottom: list of 3D points (same order, CCW viewed from +Z)."""
    n = len(top)
    verts = list(top) + list(bottom)
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    return link_mesh(name, verts, faces, mat, parent)


def variable_wing(name, root_le, root_te, tip_le, tip_te, mat, parent=None,
                  root_thick=0.075, tip_thick=0.022, sign=1):
    """Tapered swept wing. Points are (x_span, y_chord). sign mirrors to -X."""
    # corners in XY plane
    c = [root_le, root_te, tip_te, tip_le]  # CCW-ish order
    top = [(sign * x, y, root_thick / 2) for (x, y) in (root_le, root_te)]
    top += [(sign * x, y, tip_thick / 2) for (x, y) in (tip_te, tip_le)]
    bot = [(sign * x, y, -root_thick / 2) for (x, y) in (root_le, root_te)]
    bot += [(sign * x, y, -tip_thick / 2) for (x, y) in (tip_te, tip_le)]
    return extruded_poly(name, top, bot, mat, parent)


def detail_box(name, location, dims, mat, parent=None, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    if rotation:
        obj.rotation_euler = rotation
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def make_root(name):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.8
    return e


def apply_all():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")


def export_glb(path):
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False,
        export_apply=True, export_yup=True, export_cameras=False,
        export_lights=False, export_materials="EXPORT",
    )
    print("EXPORTED", path)


def make_materials():
    """High-contrast paint: the missile must read against green terrain and
    dark water.  `keep_authored_colors` in vehicle.gd preserves these colours."""
    return {
        "body": material("M01_BodyLightGrey", (0.56, 0.58, 0.58), roughness=0.62),
        "body2": material("M02_BodyMidGrey", (0.42, 0.45, 0.46), roughness=0.64),
        "nose": material("M03_SeekerGraphite", (0.045, 0.05, 0.055), metallic=0.35, roughness=0.30),
        "wing": material("M04_WingGrey", (0.40, 0.43, 0.44), roughness=0.62),
        "metal": material("M05_Gunmetal", (0.12, 0.135, 0.14), metallic=0.7, roughness=0.45),
        "panel": material("M06_PanelLine", (0.045, 0.05, 0.055), roughness=0.9),
        "accent": material("M07_WarningOrange", (0.96, 0.24, 0.06), roughness=0.55),
        "mark": material("M08_MarkYellow", (0.98, 0.78, 0.10), roughness=0.6),
        "scorch": material("M09_Scorch", (0.055, 0.05, 0.045), roughness=1.0),
        "ember": material("M10_Ember", (0.9, 0.28, 0.05), emission=(1.0, 0.25, 0.02), roughness=1.0),
        "exhaust": material("M11_ExhaustGlow", (1.0, 0.42, 0.07),
                            emission=(1.0, 0.32, 0.03), roughness=1.0),
        "navred": material("M12_NavRed", (1.0, 0.06, 0.04),
                           emission=(1.0, 0.05, 0.02), roughness=1.0),
        "navgreen": material("M13_NavGreen", (0.10, 1.0, 0.22),
                             emission=(0.05, 1.0, 0.12), roughness=1.0),
    }


# ---- intact missile -------------------------------------------------------
def build_intact(root, m):
    # --- fuselage: smooth ogive nose -> cylindrical body -> tail taper ---
    lathe("fuselage", [
        (2.85, 0.005), (2.80, 0.045), (2.68, 0.095), (2.50, 0.150),
        (2.25, 0.205), (1.95, 0.255), (1.70, 0.282), (1.40, 0.292),
        (0.90, 0.300), (0.20, 0.302), (-0.60, 0.300), (-1.30, 0.295),
        (-1.80, 0.285), (-2.05, 0.268), (-2.25, 0.235),
    ], m["body"], parent=root, smooth=True)

    # --- seeker dome / nose tip (dark glass) ---
    lathe("seeker_dome", [
        (2.90, 0.0), (2.86, 0.035), (2.78, 0.075), (2.68, 0.100), (2.60, 0.112),
    ], m["nose"], parent=root, smooth=True)

    # --- panel-line bands around fuselage ---
    for y, r in [(1.68, 0.285), (1.42, 0.294), (0.85, 0.302),
                 (-0.62, 0.301), (-1.78, 0.287), (-2.22, 0.240)]:
        ring_band("panel_band", y, r + 0.008, 0.022, m["panel"], root)

    # --- high-visibility warning bands (read at distance against terrain) ---
    ring_band("warn_band_nose", 1.86, 0.282, 0.16, m["accent"], root)
    ring_band("warn_band_tail", -1.95, 0.287, 0.10, m["accent"], root)
    # graphite seeker collar just behind the dark dome
    lathe("seeker_band", [(1.92, 0.268), (2.04, 0.255)], m["metal"],
          parent=root, smooth=True, cap=False)

    # --- mid-body darker shoulder section (visual break) ---
    lathe("body_shoulder", [(1.05, 0.315), (0.55, 0.316)], m["body2"],
          parent=root, smooth=True, cap=False)

    # --- swept main wings (mid-body) ---
    for sign, s in ((1, "R"), (-1, "L")):
        variable_wing("wing_" + s, (0.29, 0.55), (0.29, -0.72),
                      (1.62, -0.18), (1.62, -0.70), m["wing"], root,
                      root_thick=0.085, tip_thick=0.024, sign=sign)
        # wing panel line (dark strip near leading edge on top)
        detail_box("wing_line_" + s, (sign * 0.95, 0.05, 0.052),
                   (1.15, 0.018, 0.006), m["panel"], root,
                   rotation=(0, 0, math.radians(-11 * sign)))
        # control surface hinge line
        detail_box("wing_hinge_" + s, (sign * 1.0, -0.52, 0.030),
                   (1.05, 0.014, 0.006), m["panel"], root)
        # bold orange warning chevron on the upper wing
        detail_box("wing_warn_" + s, (sign * 0.80, -0.12, 0.048),
                   (0.62, 0.16, 0.008), m["accent"], root,
                   rotation=(0, 0, math.radians(-11 * sign)))
        # emissive wingtip navigation light (port red / starboard green)
        detail_box("navlight_" + s, (sign * 1.58, -0.42, 0.0),
                   (0.10, 0.18, 0.07),
                   m["navred"] if sign < 0 else m["navgreen"], root)

    # --- cruciform tail fins ---
    for sign, s in ((1, "R"), (-1, "L")):
        variable_wing("tail_h_" + s, (0.24, -1.62), (0.24, -2.32),
                      (0.86, -2.22), (0.66, -1.76), m["wing"], root,
                      root_thick=0.06, tip_thick=0.02, sign=sign)
    for sign, s in ((1, "U"), (-1, "D")):
        # build vertical fins in XY then rotate into ZY plane
        obj = variable_wing("tail_v_" + s, (0.24, -1.62), (0.24, -2.32),
                            (0.86, -2.22), (0.66, -1.76), m["wing"], root,
                            root_thick=0.06, tip_thick=0.02, sign=1)
        obj.rotation_euler = (0, math.radians(-90 * sign), 0)

    # --- air intake under mid-body (rectangular ramp) ---
    detail_box("intake_fairing", (0.0, 0.62, -0.275), (0.30, 0.72, 0.14),
               m["body2"], root, rotation=(math.radians(8), 0, 0))
    detail_box("intake_mouth", (0.0, 0.98, -0.295), (0.235, 0.02, 0.10),
               m["nose"], root, rotation=(math.radians(8), 0, 0))
    detail_box("intake_ramp", (0.0, 0.80, -0.22), (0.20, 0.30, 0.035),
               m["metal"], root, rotation=(math.radians(-18), 0, 0))

    # --- engine nozzle with flared petals ---
    lathe("nozzle_outer", [(-2.25, 0.235), (-2.42, 0.215), (-2.62, 0.185),
                           (-2.74, 0.175)], m["metal"], parent=root, smooth=True)
    ring_band("nozzle_ring1", -2.46, 0.211, 0.035, m["panel"], root)
    ring_band("nozzle_ring2", -2.66, 0.182, 0.030, m["panel"], root)
    # glowing exhaust core — visible from behind even against dark water
    lathe("exhaust_disc", [(-2.735, 0.0), (-2.735, 0.155)], m["exhaust"],
          parent=root, smooth=False, cap=False)
    # nozzle petals (8 thin boxes around rim)
    for i in range(8):
        a = 2 * math.pi * i / 8
        px = math.cos(a) * 0.168
        pz = math.sin(a) * 0.168
        detail_box("nozzle_petal_%d" % i, (px, -2.66, pz), (0.055, 0.20, 0.022),
                   m["panel"], root, rotation=(0, a, 0))

    # --- dorsal antenna / pitot probe details ---
    detail_box("dorsal_antenna", (0.0, -1.05, 0.305), (0.035, 0.30, 0.055),
               m["panel"], root, rotation=(math.radians(-12), 0, 0))
    detail_box("ventral_probe", (0.0, -0.10, -0.315), (0.025, 0.22, 0.045),
               m["metal"], root)

    # --- warning/serial markings (small colored panels) ---
    detail_box("mark_red", (0.0, 1.30, 0.311), (0.14, 0.12, 0.012), m["accent"], root)
    detail_box("mark_yellow", (0.0, 1.16, 0.313), (0.10, 0.08, 0.012), m["mark"], root)
    # dorsal warning stripe — lifted clear of the fuselage to avoid z-fighting
    detail_box("spine_stripe", (0.0, 0.15, 0.316), (0.10, 1.30, 0.010),
               m["accent"], root)


# ---- wreck variant --------------------------------------------------------
def build_wreck(root, m):
    # broken front section (nose still mostly intact, scorched)
    lathe("wreck_nose", [
        (2.85, 0.005), (2.70, 0.10), (2.40, 0.18), (2.00, 0.26), (1.60, 0.29),
        (1.20, 0.30), (0.75, 0.30),
    ], m["scorch"], parent=root, smooth=True)
    # broken rear section, separated by a gap and tilted
    rear = lathe("wreck_tail", [
        (0.20, 0.29), (-0.40, 0.30), (-1.20, 0.29), (-1.80, 0.28),
        (-2.10, 0.26), (-2.35, 0.22),
    ], m["scorch"], parent=root, smooth=True)
    rear.location = (0.45, -0.35, -0.25)
    rear.rotation_euler = (math.radians(18), math.radians(-12), math.radians(9))

    # crumpled wing fragments
    wing = variable_wing("wreck_wing_L", (0.29, 0.55), (0.29, -0.72),
                         (1.40, -0.25), (1.25, -0.68), m["scorch"], root,
                         root_thick=0.08, tip_thick=0.02, sign=1)
    wing.rotation_euler = (math.radians(25), math.radians(-15), math.radians(40))
    wing.location = (-0.2, 0.1, -0.3)

    wing2 = variable_wing("wreck_wing_R", (0.29, 0.55), (0.29, -0.72),
                          (1.10, -0.30), (1.00, -0.70), m["scorch"], root,
                          root_thick=0.07, tip_thick=0.02, sign=-1)
    wing2.rotation_euler = (math.radians(-35), math.radians(20), math.radians(-50))
    wing2.location = (0.3, -0.2, 0.1)

    # scattered debris chunks
    for i, (loc, dims, rot) in enumerate([
        ((0.7, 0.9, 0.35), (0.35, 0.5, 0.12), (0.4, 0.2, 0.7)),
        ((-0.8, -0.6, -0.4), (0.25, 0.4, 0.1), (-0.3, 0.5, -0.6)),
        ((0.1, 1.6, -0.2), (0.18, 0.3, 0.08), (0.2, -0.4, 1.1)),
        ((-0.4, -1.4, 0.3), (0.3, 0.25, 0.1), (0.9, 0.1, 0.3)),
    ]):
        detail_box("debris_%d" % i, loc, dims, m["scorch"], root, rot)

    # glowing embers
    for i, loc in enumerate([(0.5, 0.4, 0.0), (-0.3, -0.2, 0.1), (0.1, 0.9, -0.2)]):
        detail_box("ember_%d" % i, loc, (0.10, 0.10, 0.10), m["ember"], root)


# ---- render ---------------------------------------------------------------
def setup_render(wreck=False):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    world = bpy.data.worlds.new("StudioWorld") if not bpy.context.scene.world else bpy.context.scene.world
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.055, 0.075, 0.10, 1.0)
        bg.inputs["Strength"].default_value = 0.6

    cam_data = bpy.data.cameras.new("HeroCam")
    cam = bpy.data.objects.new("HeroCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (6.0, 7.0, 3.6) if not wreck else (5.5, 6.5, 4.0)
    target = Vector((0, 0.1, 0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 46
    scene.camera = cam

    def area(name, loc, energy, color, size):
        d = bpy.data.lights.new(name, "AREA")
        d.energy = energy
        d.shape = "DISK"
        d.size = size
        d.color = color
        o = bpy.data.objects.new(name, d)
        bpy.context.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

    area("Key_Warm", (4, 4, 7), 180, (1.0, 0.93, 0.82), 6)
    area("Fill_Cool", (-6, -2, 4), 90, (0.65, 0.78, 1.0), 7)
    area("Rim", (0, -6, 2), 140, (0.85, 0.95, 1.0), 4)


def main():
    # ---- intact ----
    clear_scene()
    mats = make_materials()
    root = make_root("CruiseMissile")
    build_intact(root, mats)
    apply_all()
    setup_render()
    bpy.context.scene.render.filepath = PREVIEW_PNG
    bpy.ops.render.render(write_still=True)
    print("RENDERED", PREVIEW_PNG)
    export_glb(INTACT_GLB)

    # ---- wreck ----
    clear_scene()
    mats2 = make_materials()
    root2 = make_root("CruiseMissileWreck")
    build_wreck(root2, mats2)
    apply_all()
    setup_render(wreck=True)
    bpy.context.scene.render.filepath = WRECK_PNG
    bpy.ops.render.render(write_still=True)
    print("RENDERED", WRECK_PNG)
    export_glb(WRECK_GLB)


if __name__ == "__main__":
    main()
