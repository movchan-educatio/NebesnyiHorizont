# OilRigMap - integration guide

## 1. Copy
Copy the whole folder `godot_package/maps/oil_rig/` into your project so that
it lands at `res://maps/oil_rig/` (create `res://maps/` if needed).
Keep every file: `.glb`, `.png`, `.gdshader`, `.tres`, `.gd`, `.json`, `.tscn`.

## 2. Instance
```gdscript
var rig = load("res://maps/oil_rig/oil_rig_map.tscn").instantiate()
add_child(rig)
```
Or simply open `res://maps/oil_rig/oil_rig_map.tscn` and use it as a sub-scene.

## 3. What the scene already contains
- `Sun` - one DirectionalLight3D with shadows (no dynamic OmniLights).
- `Ocean` - PlaneMesh 6000 x 6000 m with `shaders/ocean_water.gdshader`.
- `Modules` - 4 platform cores, 4 derricks, 8 cranes, 4 helipads,
  2 flare booms, 4 skybridges and 1 tanker (all modular `.glb` instancing).
- `MapColliders` - StaticBody3D, group `map_colliders`, **per-element**
  BoxShape3D / CylinderShape3D colliders only (no convex hulls on hollow
  structures, no colliders on rings, cables or railings).
- `FPVGates` - group `fpv_gates`, invisible Marker3D per gate for gameplay
  logic only. Neon rings were removed: no visual markers, no colliders.
- `InstancedDetails` - MultiMeshInstance3D for repeated rail posts.
- `SpawnPoints` - 5 Marker3D nodes; **local -Z is the drone forward axis**.
- `WaterKillZone` - Area3D at sea level, group `water_kill_zone`.

## 4. Connect your drone / gameplay
```gdscript
# spawn
var spawns := get_tree().get_nodes_in_group("map_spawn_points")
rig.global_transform = spawns[0].global_transform

# sea detection
$WaterKillZone.body_entered.connect(func(body):
	if body.is_in_group("drone"):
		respawn(body))

# gate logic (use the markers, not the visual rings)
for gate in get_tree().get_nodes_in_group("fpv_gates"):
	if gate is Marker3D:
		pass
```
All colliders are in group `map_colliders` on the parent StaticBody3D.

## 5. Renderer / performance
Project settings: `rendering/renderer/rendering_method = "mobile"`.
For very low-end devices switch to `gl_compatibility`; the scene uses no SSR,
no SDFGI, no volumetric fog and no screen-space effects.
The ocean shader uses 3 texture fetches; all static geometry shares 6 atlas
textures through the two `.tres` materials (materials are re-applied to the
GLB meshes at runtime by `scripts/oil_rig_materials.gd`).

## 6. Build statistics
- Unique module triangles: 34900
- Collider shapes: 937 (exact solids only)
- FPV gates: 49
- PBR atlases: 2 x 2048x2048 sets (Albedo / Normal OpenGL / ORM)
- Draw calls (typical view): ~55-75
