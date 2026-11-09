"""Repair every flyable drone so propellers sit on the stock motor geometry.

The earlier pass added AI-generated motor cylinders and parented the props to
them.  This script removes those cylinders, keeps the original stock motors
that are already part of the airframe, and rebuilds the `motor_*` nodes as
plain empty pivots exactly where the props are.

Pisun VTOL is special: its four stock 3-blade props are still baked into
`pisun_fuselage` as loose mesh islands.  They are separated out, given hubs as
origins, and mounted on new `motor_*` pivots; the bogus AI props are deleted.

Run:
  blender -b --python tools/fix_props_on_stock_motors.py
Set DRONE_NORM_DIR to work on a copy first.
"""

import bpy
import os
import math
from mathutils import Vector, Matrix

NORM = os.environ.get(
    "DRONE_NORM_DIR",
    r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm",
)
DRONES = [
    "holka",
    "pinapipe",
    "avata2",
    "peleng",
    "grim7",
    "grim7m",
    "strila8",
    "falcon_x",
    "quad5_custom",
]
CORNERS = ["FL", "FR", "BR", "BL"]

# Pisun stock prop hubs in Blender/world space (from circle fitting the hubs).
PISUN_HUBS = {
    "FL": Vector((-0.1357, 0.0008, -0.0440)),  # left nacelle
    "FR": Vector((0.1368, -0.0001, -0.0440)),  # right nacelle
    "BL": Vector((-0.0012, 0.1374, -0.0440)),  # front / +Y nacelle
    "BR": Vector((-0.0022, -0.1322, -0.0440)),  # rear / -Y nacelle
}


# Specific drone positioning and orientation overrides to seat props on authentic stock motors.
# Offsets / target transforms in world coordinates (Blender space).
DRONE_OVERRIDES = {
    # PinaPipe: props shifted outward diagonally to center on the stock motor rotor grilles.
    "pinapipe": {
        "FL": {"loc": Vector((-0.06455, +0.05328, -0.00900))},
        "FR": {"loc": Vector((+0.06455, +0.05328, -0.00900))},
        "BR": {"loc": Vector((+0.06450, -0.05325, -0.00900))},
        "BL": {"loc": Vector((-0.06450, -0.05325, -0.00900))},
    },
    # Avata 2: props shifted along Y (~9mm) to seat directly on the stock motor bells.
    "avata2": {
        "FL": {"loc": Vector((-0.05857, +0.04488, -0.00396))},
        "FR": {"loc": Vector((+0.05854, +0.04487, -0.00396))},
        "BR": {"loc": Vector((+0.05848, -0.04511, -0.00396))},
        "BL": {"loc": Vector((-0.05856, -0.04509, -0.00396))},
    },
    # Falcon-X: props are tilted and placed at the circular lip of each angled motor nacelle pod.
    # Front nacelles tilt ~51° forward/up, rear nacelles tilt ~71° forward/up.
    "falcon_x": {
        "FL": {
            "loc": Vector((-0.0966, -0.0587, 0.0272)),
            "normal": Vector((-0.046, -0.777, 0.628)),
        },
        "FR": {
            "loc": Vector((+0.0966, -0.0587, 0.0272)),
            "normal": Vector((+0.046, -0.777, 0.628)),
        },
        "BR": {
            "loc": Vector((+0.0969, +0.0538, 0.1091)),
            "normal": Vector((+0.217, -0.918, 0.332)),
        },
        "BL": {
            "loc": Vector((-0.0970, +0.0540, 0.1093)),
            "normal": Vector((-0.211, -0.922, 0.324)),
        },
    },
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


def import_drone(name):
    path = os.path.join(NORM, name + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    return path


def export_drone(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_apply=False,
    )


def world_bbox(obj):
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def reparent_prop_to_empty(prop, empty):
    """Keep the prop's world transform while making its local transform identity.

    The prop object's origin is already on the motor/prop hub, so a new pivot
    placed at that same world matrix can own it with identity local TRS.  This
    is important: the glTF exporter writes `matrix_basis`, not
    `matrix_parent_inverse`, so compensating with the parent-inverse alone
    produces a doubled offset in Godot.
    """
    saved = prop.matrix_world.copy()
    prop.parent = None
    prop.matrix_world = saved
    bpy.context.view_layer.update()

    empty.matrix_world = saved
    bpy.context.view_layer.update()

    prop.parent = empty
    prop.matrix_parent_inverse = Matrix.Identity(4)
    prop.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()

    delta = (prop.matrix_world.translation - saved.translation).length
    if delta > 1e-6:
        print("    !! transform drift %.8f m" % delta)


def fix_standard_drone(name):
    path = import_drone(name)
    print("=== %s ===" % name)

    for corner in CORNERS:
        motor = bpy.data.objects.get("motor_" + corner)
        prop = bpy.data.objects.get("propeller_" + corner)
        if motor is None or prop is None:
            print("  [%s] MISSING motor=%s prop=%s" % (corner, motor, prop))
            continue
        if prop.parent is not motor:
            print("  [%s] unexpected parent %s" % (corner, prop.parent))
        if motor.type != "MESH":
            print("  [%s] motor is %s, not the AI cylinder" % (corner, motor.type))

        motor_world = motor.matrix_world.copy()
        prop_world = prop.matrix_world.copy()
        if (motor_world.translation - prop_world.translation).length > 1e-6:
            print(
                "  [%s] motor/prop origins differ by %.6f"
                % (corner, (motor_world.translation - prop_world.translation).length)
            )

        prop.parent = None
        prop.matrix_world = prop_world
        bpy.context.view_layer.update()

        bpy.data.objects.remove(motor, do_unlink=True)
        bpy.context.view_layer.update()

        # Check for drone-specific placement / orientation overrides.
        override = DRONE_OVERRIDES.get(name, {}).get(corner)
        if override:
            if "normal" in override:
                norm = override["normal"].normalized()
                # Align empty local +Z with the nacelle normal
                rot = norm.to_track_quat("Z", "Y").to_matrix().to_4x4()
                target_world = Matrix.Translation(override["loc"]) @ rot
            else:
                target_world = prop_world.copy()
                target_world.translation = override["loc"]
        else:
            target_world = prop_world.copy()

        empty = bpy.data.objects.new("motor_" + corner, None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.02
        bpy.context.scene.collection.objects.link(empty)
        bpy.context.view_layer.update()

        prop.matrix_world = target_world
        bpy.context.view_layer.update()

        reparent_prop_to_empty(prop, empty)

        print(
            "  [%s] pivot=(%.5f,%.5f,%.5f) prop_local=%s"
            % (
                corner,
                empty.matrix_world.translation.x,
                empty.matrix_world.translation.y,
                empty.matrix_world.translation.z,
                tuple(round(v, 6) for v in prop.location),
            )
        )

    export_drone(path)
    print("  exported", path)


def separate_loose(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o for o in bpy.data.objects if o.type == "MESH"]


def nearest_hub(point):
    best = None
    best_d = 1e9
    for corner, hub in PISUN_HUBS.items():
        d = math.hypot(point.x - hub.x, point.y - hub.y)
        if d < best_d:
            best_d = d
            best = corner
    return best, best_d


def fix_pisun():
    name = "pisun_vtol"
    path = import_drone(name)
    print("=== %s (stock prop extraction) ===" % name)

    # Drop the AI props and their motor empties.
    for corner in CORNERS:
        for prefix in ("propeller_", "motor_"):
            obj = bpy.data.objects.get(prefix + corner)
            if obj is not None:
                bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()

    fuselage = None
    for obj in bpy.data.objects:
        if obj.type == "MESH" and "fuselage" in obj.name.lower():
            fuselage = obj
            break
    if fuselage is None:
        raise RuntimeError("pisun fuselage not found")

    parts = separate_loose(fuselage)
    print("  loose islands:", len(parts))

    groups = {c: [] for c in CORNERS}
    for obj in parts:
        mn, mx = world_bbox(obj)
        c = (mn + mx) * 0.5
        if not (-0.065 < c.z < -0.034):
            continue
        corner, dist = nearest_hub(c)
        if dist < 0.10:
            groups[corner].append(obj)

    for corner, objs in groups.items():
        print("  %s: %d islands" % (corner, len(objs)))
        if len(objs) < 3:
            raise RuntimeError("pisun %s extraction looks wrong" % corner)

    props = {}
    for corner, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        prop = bpy.context.view_layer.objects.active
        prop.name = "propeller_" + corner
        prop.data.name = "propeller_" + corner

        # Refine the hub from vertices close to the measured hub centre.
        approx = PISUN_HUBS[corner]
        verts = [prop.matrix_world @ v.co for v in prop.data.vertices]
        near = [
            v
            for v in verts
            if math.hypot(v.x - approx.x, v.y - approx.y) < 0.014
        ]
        if near:
            hub = Vector(
                (
                    sum(v.x for v in near) / len(near),
                    sum(v.y for v in near) / len(near),
                    sum(v.z for v in near) / len(near),
                )
            )
        else:
            hub = approx.copy()
        if (hub.xy - approx.xy).length > 0.004:
            print("  [%s] hub refinement rejected (%s), using approx" % (corner, hub))
            hub = approx.copy()

        bpy.context.scene.cursor.location = hub
        bpy.ops.object.select_all(action="DESELECT")
        prop.select_set(True)
        bpy.context.view_layer.objects.active = prop
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.context.view_layer.update()
        props[corner] = (prop, hub.copy())
        print(
            "  [%s] hub=(%.5f,%.5f,%.5f) verts=%d"
            % (corner, hub.x, hub.y, hub.z, len(prop.data.vertices))
        )

    # Join the remaining shell back into one neat fuselage object.
    prop_objects = {p for p, _ in props.values()}
    remainder = [
        o for o in bpy.data.objects if o.type == "MESH" and o not in prop_objects
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in remainder:
        obj.select_set(True)
    # The old `fuselage` object may itself have been one of the loose prop
    # islands, so pick the biggest remaining shell part as the join target.
    body = max(remainder, key=lambda o: len(o.data.vertices))
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "pisun_fuselage"
    body.data.name = "pisun_fuselage"
    print("  fuselage verts:", len(body.data.vertices), "objects:", len(bpy.data.objects))

    for corner, (prop, hub) in props.items():
        empty = bpy.data.objects.new("motor_" + corner, None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.02
        bpy.context.scene.collection.objects.link(empty)
        bpy.context.view_layer.update()
        reparent_prop_to_empty(prop, empty)
        print(
            "  [%s] pivot=(%.5f,%.5f,%.5f) prop_local=%s"
            % (
                corner,
                hub.x,
                hub.y,
                hub.z,
                tuple(round(v, 6) for v in prop.location),
            )
        )

    export_drone(path)
    print("  exported", path)


def main():
    print("TARGET DIR:", NORM)
    only = os.environ.get("DRONE_ONLY", "").strip()
    for name in DRONES:
        if only and only != name:
            continue
        reset_scene()
        fix_standard_drone(name)
    if not only or only == "pisun_vtol":
        reset_scene()
        fix_pisun()
    print("ALL DRONES REPAIRED")


main()
