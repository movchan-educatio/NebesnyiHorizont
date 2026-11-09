## Background battle atmosphere for the frontline combat maps: distant
## explosions, burning impacts and the occasional enemy shell hitting a
## destructible structure.  Purely decorative except for the shell hits, which
## damage buildings through the normal explosion damage pass.
class_name AmbientBattle
extends Node3D

const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const TerrainScript = preload("res://scripts/util/frontline_terrain.gd")

var map_name := ""
var drone: Node3D = null
## MEDIUM doubles this so distant blasts/smoke are half as frequent.
var rate_scale := 1.0
var _timer := 0.8


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(7.0, 14.0) * rate_scale
	_distant_gunfire()
	if randf() < 0.55:
		_distant_artillery()


## Distant artillery audio only.  Spawning the full explosion/smoke VFX here
## compiled particle shaders in mid-flight and caused a 0.3-0.4 s freeze on the
## first ambient blast; the gunfire/rumble gives the atmosphere without it.
func _distant_artillery() -> void:
	var base := drone.global_position if is_instance_valid(drone) else Vector3.ZERO
	var angle := randf() * TAU
	var radius := randf_range(150.0, 520.0)
	var x := base.x + cos(angle) * radius
	var z := base.z + sin(angle) * radius
	var y := TerrainScript.height_at(map_name, x, z)
	CombatSfxScript.play_artillery(self, Vector3(x, y + 0.4, z), -9.0)


## A short burst of small-arms fire somewhere on the horizon: the valley feels
## alive even when the player is far from the objectives.
func _distant_gunfire() -> void:
	var base := drone.global_position if is_instance_valid(drone) else Vector3.ZERO
	var angle := randf() * TAU
	var radius := randf_range(180.0, 480.0)
	var p := Vector3(base.x + cos(angle) * radius, 0.0,
			base.z + sin(angle) * radius)
	p.y = TerrainScript.height_at(map_name, p.x, p.z) + 1.0
	for _i in range(randi_range(3, 6)):
		CombatSfxScript.play_rifle(self, p + Vector3(
				randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), -19.0)
		await get_tree().create_timer(randf_range(0.07, 0.14)).timeout


func _spawn_distant_blast() -> void:
	var base := drone.global_position if is_instance_valid(drone) else Vector3.ZERO
	var angle := randf() * TAU
	var radius := randf_range(150.0, 520.0)
	var x := base.x + cos(angle) * radius
	var z := base.z + sin(angle) * radius
	var y := TerrainScript.height_at(map_name, x, z)
	var at := Vector3(x, y + 0.4, z)
	ExplosionScript.spawn(self, at, randf_range(5.0, 8.5), 0.0)
	if randf() < 0.6:
		ExplosionScript.smoke_column(self, at + Vector3.UP * 2.0,
				randf_range(18.0, 30.0))
	# A low artillery rumble instead of a second close-range boom: distant
	# explosions should be felt more than heard.
	CombatSfxScript.play_artillery(self, at, -9.0)


## Enemy armour periodically shells the ruins: this is what makes buildings
## collapse even if the player only watches.  Only "destructible" nodes are
## targeted, never mission-critical vehicles/infantry.
func _shell_building() -> void:
	var candidates := get_tree().get_nodes_in_group("destructible")
	if candidates.is_empty():
		return
	var target: Node3D = null
	for _i in range(8):
		var pick := candidates[randi() % candidates.size()] as Node3D
		if pick != null and is_instance_valid(pick) and not bool(pick.get("is_destroyed")):
			target = pick
			break
	if target == null:
		return
	var offset := Vector3(randf_range(-14.0, 14.0), 0.0, randf_range(-14.0, 14.0))
	var at := target.global_position + offset
	at.y = TerrainScript.height_at(map_name, at.x, at.z) + 0.4
	# Visual-only ambient shell: applying real damage here destroyed a
	# building in the middle of a flight and produced a 0.3-0.4 s collapse
	# hitch.  Player weapons still destroy these buildings normally.
	ExplosionScript.spawn(self, at, 8.0, 0.0)
	CombatSfxScript.play_cannon(self, at, -7.0)
