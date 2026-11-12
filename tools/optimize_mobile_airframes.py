"""Create mobile-only GLBs by joining static meshes with identical materials.

Original PC GLBs remain untouched. Animated pusher props, camera assemblies,
warheads, flags and any object under an animated rotor/propeller stay as
separate nodes. Remaining geometry is joined by material so textures and
silhouette are preserved while node/draw submission count falls.
"""

import bpy
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = [
    ("Assets/Drones/ua_norm/leleka_100.glb", "Assets/Drones/ua_norm/leleka_100_mobile.glb"),
    ("Assets/Drones/ua_norm/furia_a1sm.glb", "Assets/Drones/ua_norm/furia_a1sm_mobile.glb"),
    ("Assets/Drones/ua_norm/chaklun_jet.glb", "Assets/Drones/ua_norm/chaklun_jet_mobile.glb"),
]
KEEP_WORDS = ("camera", "cam", "lens", "prop", "rotor", "flag", "ukraine",
              "warhead", "mork", "detonator", "antenna")


def signature(obj):
    return tuple(sorted({m.name for m in obj.data.materials if m}))


def has_animated_parent(obj):
    node = obj
    while node is not None:
        if any(word in node.name.lower() for word in ("propeller_rear", "rotor_pivot")):
            return True
        node = node.parent
    return False


for source_rel, target_rel in ASSETS:
    source = os.path.join(ROOT, source_rel)
    target = os.path.join(ROOT, target_rel)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = len(meshes)
    groups = {}
    preserved = []
    for obj in meshes:
        low = obj.name.lower()
        if has_animated_parent(obj) or any(w in low for w in KEEP_WORDS):
            preserved.append(obj)
            continue
        key = signature(obj)
        if not key:
            preserved.append(obj)
            continue
        groups.setdefault(key, []).append(obj)

    for key, objects in groups.items():
        if len(objects) < 2:
            continue
        # glTF-imported objects can have object transforms plus a shared root
        # parent. Blender Join alone double-applies some non-active origins
        # (notably Leleka's 63-part alloy group). Apply each local transform
        # into its mesh first; this preserves the group's world AABB exactly.
        for obj in objects:
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        active = objects[0]
        bpy.context.view_layer.objects.active = active
        bpy.ops.object.join()
        label = "_".join(re.sub(r"[^A-Za-z0-9_]+", "_", x).strip("_") for x in key)
        active.name = ("MobileMerged_" + label)[:63]
        active.data.name = active.name + "Mesh"

    after = len([o for o in bpy.context.scene.objects if o.type == "MESH"])
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "EMPTY", "ARMATURE"}:
            obj.select_set(True)
    active = next((o for o in bpy.context.scene.objects if o.type == "EMPTY"), None)
    if active is None:
        active = next((o for o in bpy.context.scene.objects if o.type == "MESH"), None)
    if active is not None:
        bpy.context.view_layer.objects.active = active
    bpy.ops.export_scene.gltf(
        filepath=target,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print("[AIRFRAME_OPT]", os.path.basename(source), "objects", before,
          "->", after, "preserved", len(preserved), "bytes", os.path.getsize(target))
