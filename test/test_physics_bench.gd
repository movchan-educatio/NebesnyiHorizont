extends Node

## Physics telemetry bench for every aerial preset.
##
## Measures the numbers that actually define "Liftoff feel":
##   * installed static TWR vs the catalog design TWR;
##   * hover RPM / hover stick;
##   * motor 0->90% spool and 90->10% ESC-braking time;
##   * battery sag after a sustained full-throttle punch;
##   * ground-effect boost at 2 / 10 / 30 cm;
##   * honest inertia tensor.
##
## Results are written to qa_shots/physics/physics_bench.csv so a real
## Betaflight blackbox / telemetry log can be compared side by side.
## Run: godot --headless --path GodotDrone-master res://test/test_physics_bench.tscn

const OUT_DIR := "C:/Users/USER_UA/Desktop/Новий симулятор/qa_shots/physics"
const OUT_CSV := OUT_DIR + "/physics_bench.csv"

const SPOOL_BANDS := {
	"micro": [0.04, 0.15],
	"5inch": [0.03, 0.12],
	"7inch": [0.08, 0.18],
	"8inch": [0.10, 0.25],
	"10inch": [0.15, 0.30],
}
const HOVER_BANDS := {
	"micro": [0.35, 0.80],
	"5inch": [0.25, 0.65],
	"7inch": [0.35, 0.70],
	"8inch": [0.35, 0.70],
	"10inch": [0.40, 0.75],
}

var _rows: Array[PackedStringArray] = []
var _fails: Array[String] = []


func _ready() -> void:
	print("==================================================")
	print("=== PHYSICS BENCH: 5 / 7 / 8 / 10 INCH ===")
	print("==================================================")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_rows.append(PackedStringArray([
		"preset", "name", "class", "mass_kg", "design_twr", "physical_twr",
		"hover_rpm", "hover_pct", "spool90_s", "brake10_s", "sag_factor",
		"cell_v", "ge_2cm", "ge_10cm", "ge_30cm",
		"inertia_x", "inertia_y", "inertia_z"]))

	var scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	if scene == null:
		_fail("Drone1.tscn must load")
		_finish()
		return
	var drone := scene.instantiate() as Drone
	add_child(drone)
	GameSettings.hud_config["infinite_battery"] = false

	var checked := 0
	for idx in range(DroneCatalog.count()):
		var p := DroneCatalog.preset(idx)
		DroneCatalog.apply_to_drone(drone, idx)
		_measure(drone, idx, p)
		checked += 1

	drone.queue_free()
	print("[BENCH] presets checked: ", checked)
	_finish()


func _measure(drone: Drone, idx: int, p: Dictionary) -> void:
	var name := str(p.get("name", "?"))
	var cls := drone.physics_class
	var prop: Propeller = drone.motors[0].propeller
	var max_rpm: float = drone.motors[0].MAX_RPM
	var weight: float = maxf(drone.mass * 9.81, 0.001)
	var max_thrust := 0.0
	for motor in drone.motors:
		max_thrust += motor.propeller.static_thrust(max_rpm)
	var physical_twr := max_thrust / weight
	var design_twr := float(p.get("twr", physical_twr))
	var hover_rpm := _hover_rpm(prop, weight * 0.25)
	var hover_pct := hover_rpm / maxf(max_rpm, 1.0)
	var spool := _spool_time(drone.motors[0], 0.0, max_rpm, 0.9, true)
	var brake := _spool_time(drone.motors[0], max_rpm, 0.0, 0.1, false)

	for motor in drone.motors:
		motor.set_rpm(max_rpm)
	drone.battery_cell_voltage = drone.battery_cell_voltage_rest
	drone.battery_voltage = drone.battery_cell_voltage_rest * float(drone.battery_cells)
	drone.battery_sag_factor = 1.0
	for i in range(20):
		drone.update_voltage_sag(0.1)
	var sag := drone.battery_sag_factor
	var cell_v := drone.battery_cell_voltage

	var ge2 := prop.ground_effect_for_height(0.02)
	var ge10 := prop.ground_effect_for_height(0.10)
	var ge30 := prop.ground_effect_for_height(0.30)

	print("[BENCH] %-2d %-22s %-7s m=%.2f twr=%.2f (design %.2f) hover=%.0f%% spool=%.3fs brake=%.3fs ge=%.2f/%.2f/%.2f sag=%.2f" % [
		idx, name, cls, drone.mass, physical_twr, design_twr, hover_pct * 100.0,
		spool, brake, ge2, ge10, ge30, sag])

	# Design TWR and the installed propeller set should tell the same story.
	if absf(physical_twr - design_twr) > maxf(0.30, design_twr * 0.10):
		_fail("preset %d: physical TWR %.2f vs design %.2f" % [idx, physical_twr, design_twr])
	# Spool time must depend on prop class, not be one global value.
	if SPOOL_BANDS.has(cls):
		var band: Array = SPOOL_BANDS[cls]
		if spool < float(band[0]) or spool > float(band[1]):
			_fail("preset %d: spool %.3fs outside %s band %s" % [idx, spool, cls, str(band)])
	if HOVER_BANDS.has(cls):
		var hband: Array = HOVER_BANDS[cls]
		if hover_pct < float(hband[0]) or hover_pct > float(hband[1]):
			_fail("preset %d: hover %.0f%% outside %s band %s" % [
				idx, hover_pct * 100.0, cls, str(hband)])
	# ESC braking must be faster than the equivalent spool-up.
	if brake >= spool:
		_fail("preset %d: brake %.3fs is not faster than spool %.3fs" % [idx, brake, spool])
	# Ground effect: finite and monotonic with height.
	if ge2 > 1.36:
		_fail("preset %d: ground effect %.2fx exceeds 1.36" % [idx, ge2])
	if ge2 + 0.005 < ge10 or ge10 + 0.005 < ge30:
		_fail("preset %d: ground effect not monotonic %.2f/%.2f/%.2f" % [
			idx, ge2, ge10, ge30])
	if sag > 1.0 or sag < 0.50:
		_fail("preset %d: sag %.2f outside 0.50..1.0" % [idx, sag])

	_rows.append(PackedStringArray([
		str(idx), name, cls, "%.3f" % drone.mass, "%.3f" % design_twr,
		"%.3f" % physical_twr, "%.0f" % hover_rpm, "%.3f" % hover_pct,
		"%.4f" % spool, "%.4f" % brake, "%.3f" % sag, "%.3f" % cell_v,
		"%.3f" % ge2, "%.3f" % ge10, "%.3f" % ge30,
		"%.6f" % drone.inertia.x, "%.6f" % drone.inertia.y,
		"%.6f" % drone.inertia.z]))

	for motor in drone.motors:
		motor.set_rpm(0.0)
	drone.battery_cell_voltage = drone.battery_cell_voltage_rest
	drone.battery_voltage = drone.battery_cell_voltage_rest * float(drone.battery_cells)
	drone.battery_sag_factor = 1.0


func _hover_rpm(prop: Propeller, thrust: float) -> float:
	var lo := 0.0
	var hi: float = prop.get_parent().MAX_RPM
	for i in range(48):
		var mid: float = (lo + hi) * 0.5
		if prop.static_thrust(mid) >= thrust:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


func _spool_time(motor: Motor, from_rpm: float, to_rpm: float, threshold: float,
		up: bool) -> float:
	motor.powered = true
	motor.set_rpm(from_rpm)
	motor.set_rpm_target(to_rpm)
	var dt := 1.0 / 960.0
	var t := 0.0
	for i in range(9600):
		motor.update_thrust(dt)
		t += dt
		if up and motor.rpm >= to_rpm * threshold:
			return t
		if not up and motor.rpm <= to_rpm + (from_rpm - to_rpm) * threshold:
			return t
	return 99.0


func _fail(message: String) -> void:
	_fails.append(message)
	push_error("[BENCH] " + message)


func _finish() -> void:
	var file := FileAccess.open(OUT_CSV, FileAccess.WRITE)
	if file != null:
		for row in _rows:
			file.store_csv_line(row)
		file.close()
		print("[BENCH] CSV -> ", OUT_CSV)
	if _fails.is_empty():
		print("==================================================")
		print("=== PHYSICS BENCH PASSED (all aerial presets) ===")
		print("==================================================")
		get_tree().quit(0)
	else:
		print("[BENCH] FAILURES: ", _fails.size())
		for failure in _fails:
			print("  - ", failure)
		get_tree().quit(1)
