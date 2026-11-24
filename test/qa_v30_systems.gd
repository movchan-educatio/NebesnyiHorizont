extends Node
## v30 QA: каталог/гвинти/звук, ворожі камікадзе, економіка.

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[V30-SYS] PASS ", label)
	else:
		_fails += 1
		print("[V30-SYS] FAIL ", label)


func _ready() -> void:
	_test_catalog()
	await _test_kamikaze()
	await _test_kamikaze_non_elim_and_impact()
	_test_economy()
	for _i in range(4):
		await get_tree().process_frame
	print("[V30-SYS] failures=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_catalog() -> void:
	_check(DroneCatalog.count() == 16, "каталог: 16 дронів (%d)" % DroneCatalog.count())
	var kinds: Dictionary = {}
	for i in range(DroneCatalog.count()):
		var p := DroneCatalog.preset(i)
		var kind := int(p.get("audio_kind", -1))
		kinds[kind] = true
		_check(String(p.get("name", "")) != "" and String(p.get("desc", "")) != "",
				"дрон %d має назву й опис" % i)
	_check(kinds.size() == DroneCatalog.count(), "audio_kind унікальні (%d)" % kinds.size())
	for i in range(13, 16):
		var holder := Node3D.new()
		add_child(holder)
		var model := DroneCatalog.attach_model(holder, i)
		var pivots: Array = []
		if model != null:
			pivots = model.get_meta("prop_pivots", [])
		_check(pivots.size() == 4, "дрон %d: рівно 4 півоти гвинтів (%d)" % [i, pivots.size()])
		if model != null and pivots.size() == 4:
			var pivot: Node3D = pivots[0] as Node3D
			var non_zero_hub := pivot.transform.origin.length() > 0.01
			_check(non_zero_hub, "дрон %d: півот у центрі мотора (origin=%s)" % [i, str(pivot.transform.origin)])
			var has_tip := pivot.find_child("*Tip*", true, false) != null
			_check(has_tip, "дрон %d: кінцівки лопатей перенесені під півот" % i)
			var before := pivot.transform
			DroneCatalog.animate_propellers(model, 0.1, [800.0, 800.0, 800.0, 800.0])
			_check(pivot.transform != before, "дрон %d: гвинти обертаються" % i)
		holder.queue_free()
		for _f in range(2):
			await get_tree().process_frame
	var preset5 := DroneCatalog.preset(5)
	_check(is_equal_approx(float(preset5.get("twr", 0.0)), 3.1), "пресет 5 military_fpv: TWR=3.1 збережено")


func _test_kamikaze() -> void:
	var script := load("res://combat/enemy_kamikaze_drone.gd")
	_check(script != null, "скрипт камікадзе завантажується")
	if script == null:
		return
	var drone = script.new()
	drone.variant = 1
	add_child(drone)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(drone.is_in_group("combat_target"), "камікадзе в групі combat_target")
	_check(drone.is_in_group("primary_combat_target"), "камікадзе — основна ціль")
	_check(int(drone.phase) == 1, "камікадзе автоактивується standalone у APPROACH (%d)" % int(drone.phase))
	_check(drone._props.size() == 6, "KT-12 має рівно 6 роторних півотів (%d)" % drone._props.size())
	var model: Node = drone.get_node_or_null("Model")
	_check(model != null and model.get_child_count() > 0, "модель KT-12 завантажена")
	var killed := [false]
	drone.destroyed.connect(func(_p: int) -> void: killed[0] = true)
	drone.take_damage(999.0, Vector3.ZERO)
	_check(killed[0], "сигнал destroyed спрацьовує")
	_check(drone.phase == 4, "перехід у FALLING (%d)" % drone.phase)
	for _i in range(260):
		await get_tree().physics_frame
	_check(not is_instance_valid(drone) or drone.phase == 5, "падіння завершується вибухом")
	if is_instance_valid(drone):
		drone.queue_free()
		for _f in range(2):
			await get_tree().process_frame


func _test_kamikaze_non_elim_and_impact() -> void:
	var script := load("res://combat/enemy_kamikaze_drone.gd")
	var kd = script.new()
	kd.variant = 0
	kd.set_primary_target(false)
	add_child(kd)
	await get_tree().physics_frame
	_check(not kd.is_in_group("primary_combat_target"), "не-основний камікадзе не в primary_combat_target")
	_check(kd._props.size() == 4, "KT-8 має рівно 4 роторні півоти (%d)" % kd._props.size())
	kd._impact()
	_check(bool(kd.impacted_player), "_impact виставляє impacted_player=true")
	kd.queue_free()
	for _f in range(2):
		await get_tree().process_frame
	# Verify non-kill special op 2 (Escort) does NOT register kamikaze in _mission_targets_total
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 2
	Global.difficulty = Global.Difficulty.OPERATOR
	var lvl_ps := load("res://sceneries/LisLevel.tscn") as PackedScene
	var lvl := lvl_ps.instantiate()
	add_child(lvl)
	for _i in range(15):
		await get_tree().physics_frame
	_check(int(lvl.get("_mission_targets_total")) == 0,
			"Escort на Лісі не додає камікадзе в _mission_targets_total (%d)" % int(lvl.get("_mission_targets_total")))
	lvl.queue_free()
	for _f in range(3):
		await get_tree().process_frame
	Global.special_mission = 0


func _test_economy() -> void:
	var saved_coins := Progress.coins
	var saved_earned := Progress.total_earned
	var saved_unlocked := Progress.unlocked.duplicate()
	var saved_awarded := Progress.awarded.duplicate()
	var saved_caps := Progress.daily_caps.duplicate(true)
	Progress.qa_reset()
	var got := Progress.award("qa_once", 100)
	var again := Progress.award("qa_once", 100)
	_check(got == 100 and again == 0, "нагорода idempotent (%d/%d)" % [got, again])
	var daily := Progress.award("qa_daily_1", 50, "qa_test", 1)
	var capped := Progress.award("qa_daily_2", 50, "qa_test", 1)
	_check(daily == 50 and capped == 0, "добовий кап працює")
	var before := Progress.coins
	var denied := Progress.try_unlock("drone_wraith")
	_check(not denied and Progress.coins == before, "недостатньо монет — не відкриваємо")
	Progress.award("qa_funds", 4000)
	_check(Progress.try_unlock("drone_wraith"), "відкриття дрона за монети")
	_check(Progress.is_unlocked("drone_wraith"), "дрон відкритий")
	var spent := Progress.coins
	Progress.try_unlock("drone_wraith")
	_check(Progress.coins == spent, "баланс не змінився після повтору")
	Progress.save_progress()
	var coins_saved := Progress.coins
	Progress.load_progress()
	_check(Progress.coins == coins_saved, "збереження/завантаження профілю")
	# Test daily cap does NOT burn first_key
	Progress.qa_reset()
	for d_i in range(6):
		Progress.award("cap_fill_%d" % d_i, 10, "daily_missions", 6)
	var capped_m := Progress.award_mission("mission", 3, 0, true, 3, Global.Difficulty.OPERATOR)
	_check(capped_m == 0 and not Progress.awarded.has("first_mission_3_0"),
			"кап daily_missions не спалює first_key")
	# Test backup recovery
	Progress.save_progress()
	var f_corrupt := FileAccess.open(Progress.SAVE_PATH, FileAccess.WRITE)
	if f_corrupt != null:
		f_corrupt.store_string("[broken\nkey=")
		f_corrupt.close()
	Progress.coins = 0
	Progress.load_progress()
	_check(Progress.daily_caps.has("daily_missions") or Progress.awarded.size() >= 6,
			"аварійне відновлення з .bak після битого Progress.cfg")
	Progress.coins = saved_coins
	Progress.total_earned = saved_earned
	Progress.unlocked = saved_unlocked
	Progress.awarded = saved_awarded
	Progress.daily_caps = saved_caps
	Progress.save_progress()
