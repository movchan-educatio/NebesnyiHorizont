extends Node

const LocScript = preload("res://scripts/util/localization_manager.gd")

signal game_mode_changed
signal leaderboard_requested


enum GameMode {FREE, RACE}
enum RaceState {START, RACE, END}
enum PlayMode { TRAINING = 0, COMBAT = 1, TUTORIAL = 3 }
enum Difficulty { RECRUIT = 0, OPERATOR = 1, ACE = 2 }

var difficulty: int = Difficulty.OPERATOR


var packed_popup := preload("res://GUI/ConfirmationPopup.tscn")

var log_path := "user://output.log"

var startup := true

var highscore_path := "user://highscores.sav"

var config_dir_old := "user://config"
var config_dir := "user://config_G3"
var replay_dir_old := "user://replays"
var replay_dir := "user://replays_G3"

var game_mode: int = GameMode.FREE: set = set_game_mode
var active_track: Track = null

## Currently selected gameplay mode, chosen in the main menu and consumed by
## CourseLevel when it starts.
var play_mode: int = PlayMode.TUTORIAL
## Current combat mission stage (1 = Recon Sector, 2 = Armor Column, 3 = Rotary Target, 4 = Aerial Intercept).
var combat_mission: int = 1
## Special operations are standalone sorties, not campaign records.  0 means a
## normal campaign mission; 1-6 select recon / escort / evacuation / cargo /
## night flight / EW breach.
var special_mission: int = 0
const SPECIAL_MISSION_NAMES := {
	1: "РОЗВІДКА",
	2: "СУПРОВІД",
	3: "ЕВАКУАЦІЯ",
	4: "ДОСТАВКА ВАНТАЖУ",
	5: "НІЧНИЙ ВИЛІТ",
	6: "ПРОРИВ РЕБ",
	7: "ТИЛОВА КОЛОНА",
	8: "ОРЕШНИК",
	9: "ГЛИБОКИЙ ТИЛ",
}
const SPECIAL_MISSION_NAMES_EN := {
	1: "RECONNAISSANCE",
	2: "CONVOY ESCORT",
	3: "PILOT EXTRACTION",
	4: "CARGO DELIVERY",
	5: "NIGHT STRIKE",
	6: "EW BREACH",
	7: "REAR-AREA CONVOY",
	8: "ORESHNIK",
	9: "DEEP-STRIKE OPERATION",
}


func _is_english() -> bool:
	return LocScript.get_language() == LocScript.Language.EN


func get_special_mission_name(mission_id: int = -1) -> String:
	var id := special_mission if mission_id < 0 else mission_id
	if _is_english():
		return str(SPECIAL_MISSION_NAMES_EN.get(id, "SPECIAL OPERATION"))
	return str(SPECIAL_MISSION_NAMES.get(id, "СПЕЦОПЕРАЦІЯ"))
## Set by the results screen when "Next mission" is pressed.  The next level
## shows its briefing overlay before flight so the campaign flows
## briefing -> mission -> debriefing without a trip to the main menu.
var chain_briefing_pending: bool = false
## 20-minute time limit (in seconds) for each combat mission.
const COMBAT_TIME_LIMIT := 1200.0
## Small set of menu-only preferences (haptics, defaults, ...).
var menu_settings := {"haptics_enabled": true, "drone_preset": 0,
		"selected_mode": PlayMode.TUTORIAL, "selected_mission": 1, "selected_special": 0,
		"selected_map": "village", "difficulty": 1,
		"touch_floating_sticks": false, "touch_left_spring": false,
		"touch_input_mode": "auto",
		"touch_sensitivity": 1.0, "touch_expo": 0.2,
		"touch_layout_positions": {}, "touch_layout_scale": 1.0,
		"career_xp": 0, "career_kills_armor": 0, "career_kills_aa": 0,
		"career_kills_infantry": 0, "career_kills_air": 0,
		"career_sorties": 0, "career_hits": 0, "career_drops": 0}

## Currently selected drone preset (index into DroneCatalog.PRESETS).
var drone_preset: int = 0

## Target scene to return to from the calibration wizard (e.g. ControlsScreen).
## If empty, defaults to MainMenu.
var calibration_return_scene := ""


func get_difficulty_name() -> String:
	var is_en := _is_english()
	match difficulty:
		Difficulty.RECRUIT: return "RECRUIT" if is_en else "РЕКРУТ"
		Difficulty.OPERATOR: return "OPERATOR" if is_en else "ОПЕРАТОР"
		Difficulty.ACE: return "ACE" if is_en else "АС"
		_: return "OPERATOR" if is_en else "ОПЕРАТОР"


func get_difficulty_time_limit() -> float:
	match difficulty:
		Difficulty.RECRUIT: return COMBAT_TIME_LIMIT * 1.25 # 25 хв
		Difficulty.OPERATOR: return COMBAT_TIME_LIMIT        # 20 хв
		Difficulty.ACE: return COMBAT_TIME_LIMIT * 0.75      # 15 хв
		_: return COMBAT_TIME_LIMIT


func get_difficulty_wind_scale() -> float:
	match difficulty:
		Difficulty.RECRUIT: return 0.45
		Difficulty.OPERATOR: return 1.0
		Difficulty.ACE: return 1.45
		_: return 1.0


func get_difficulty_score_multiplier() -> float:
	match difficulty:
		Difficulty.RECRUIT: return 1.0
		Difficulty.OPERATOR: return 1.25
		Difficulty.ACE: return 1.75
		_: return 1.0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("race_mode"):
		if game_mode == GameMode.FREE:
			self.game_mode = GameMode.RACE
		elif game_mode == GameMode.RACE:
			self.game_mode = GameMode.FREE


func initialize() -> void:
	if not DirAccess.dir_exists_absolute(config_dir):
		if DirAccess.dir_exists_absolute(config_dir_old):
			DirAccess.rename_absolute(config_dir_old, config_dir)
		else:
			DirAccess.make_dir_recursive_absolute(config_dir)
	if not DirAccess.dir_exists_absolute(replay_dir):
		if DirAccess.dir_exists_absolute(replay_dir_old):
			DirAccess.rename_absolute(replay_dir_old, replay_dir)
		else:
			DirAccess.make_dir_recursive_absolute(replay_dir)
	if not FileAccess.file_exists(highscore_path):
		var file := FileAccess.open(highscore_path, FileAccess.WRITE)
		if file != null:
			file.close()
	
	startup = false


func get_formatted_date_time() -> String:
	var date_time := Time.get_datetime_dict_from_system()
	var time := "[%04d-%02d-%02d %02d:%02d:%02d]" % [date_time["year"], date_time["month"], \
			date_time["day"], date_time["hour"], date_time["minute"], date_time["second"]]
	return time


func show_error_popup(control: Control, error: String) -> void:
	var controller_dialog := packed_popup.instantiate()
	control.add_child(controller_dialog)
	controller_dialog.set_text(error)
	controller_dialog.set_buttons("OK")
	controller_dialog.show_modal(true)
	var _dialog = await controller_dialog.validated


func log_error(err_code: int, message: String = "") -> void:
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s ERROR %d: %s" % [get_formatted_date_time(), err_code, message])
	file.close()


func sanitize_play_mode(mode: int) -> int:
	if mode == PlayMode.TUTORIAL or mode == PlayMode.TRAINING or mode == PlayMode.COMBAT:
		return mode
	return PlayMode.TUTORIAL


func set_play_mode(mode: int) -> int:
	play_mode = sanitize_play_mode(mode)
	menu_settings["selected_mode"] = play_mode
	return play_mode


func should_use_gentle_angle_assist() -> bool:
	return not is_tutorial_completed()


func _ready() -> void:
	initialize()
	load_campaign_records()
	load_menu_settings()
	var mode_env := OS.get_environment("DRONE_PLAY_MODE").strip_edges().to_lower()
	match mode_env:
		"training":
			play_mode = PlayMode.TRAINING
		"combat":
			play_mode = PlayMode.COMBAT
		"tutorial":
			play_mode = PlayMode.TUTORIAL
		_:
			if not mode_env.is_empty():
				play_mode = PlayMode.TUTORIAL
	if OS.has_environment("DRONE_TUTORIAL") or (mode_env.is_empty() and not is_tutorial_completed()):
		play_mode = PlayMode.TUTORIAL
		menu_settings["selected_mode"] = PlayMode.TUTORIAL
	if OS.has_environment("DRONE_COMBAT_MISSION"):
		combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 4)
	if OS.has_environment("DRONE_PRESET"):
		drone_preset = clampi(int(OS.get_environment("DRONE_PRESET")), 0, maxi(DroneCatalog.count() - 1, 0))


func _exit_tree() -> void:
	active_track = null


func menu_settings_path() -> String:
	return "%s/Menu.cfg" % config_dir


func load_menu_settings() -> void:
	var config := ConfigFile.new()
	if config.load(menu_settings_path()) == OK:
		for key in menu_settings.keys():
			if config.has_section_key("menu", key):
				menu_settings[key] = config.get_value("menu", key)
	menu_settings["selected_mode"] = sanitize_play_mode(int(menu_settings.get("selected_mode", PlayMode.TUTORIAL)))
	play_mode = int(menu_settings["selected_mode"])
	# Keep the live selection in sync with the saved one.
	if menu_settings.has("drone_preset"):
		drone_preset = clampi(int(menu_settings["drone_preset"]), 0,
				maxi(DroneCatalog.count() - 1, 0))
	difficulty = clampi(int(menu_settings.get("difficulty", difficulty)), 0, 2)
	menu_settings["touch_floating_sticks"] = bool(menu_settings.get("touch_floating_sticks", false))
	menu_settings["touch_left_spring"] = bool(menu_settings.get("touch_left_spring", false))
	var raw_tim := str(menu_settings.get("touch_input_mode", "auto")).to_lower()
	menu_settings["touch_input_mode"] = raw_tim if raw_tim in ["auto", "controller", "touch"] else "auto"
	menu_settings["touch_sensitivity"] = clampf(float(menu_settings.get("touch_sensitivity", 1.0)), 0.4, 1.6)
	menu_settings["touch_expo"] = clampf(float(menu_settings.get("touch_expo", 0.2)), 0.0, 0.7)
	var touch_positions: Variant = menu_settings.get("touch_layout_positions", {})
	if not (touch_positions is Dictionary):
		touch_positions = {}
	menu_settings["touch_layout_positions"] = touch_positions
	menu_settings["touch_layout_scale"] = clampf(
			float(menu_settings.get("touch_layout_scale", 1.0)), 0.7, 1.4)
	menu_settings["career_xp"] = maxi(0, int(menu_settings.get("career_xp", 0)))
	menu_settings["career_kills_armor"] = maxi(0, int(menu_settings.get("career_kills_armor", 0)))
	menu_settings["career_kills_aa"] = maxi(0, int(menu_settings.get("career_kills_aa", 0)))
	menu_settings["career_kills_infantry"] = maxi(0, int(menu_settings.get("career_kills_infantry", 0)))
	menu_settings["career_kills_air"] = maxi(0, int(menu_settings.get("career_kills_air", 0)))
	menu_settings["career_sorties"] = maxi(0, int(menu_settings.get("career_sorties", 0)))
	menu_settings["career_hits"] = maxi(0, int(menu_settings.get("career_hits", 0)))
	menu_settings["career_drops"] = maxi(0, int(menu_settings.get("career_drops", 0)))


func save_menu_settings() -> void:
	menu_settings["selected_mode"] = sanitize_play_mode(int(menu_settings.get("selected_mode", play_mode)))
	var config := ConfigFile.new()
	config.load(menu_settings_path())
	for key in menu_settings.keys():
		config.set_value("menu", key, menu_settings[key])
	config.save(menu_settings_path())


var campaign_records: Dictionary = {}


func campaign_records_path() -> String:
	return "%s/Campaign.cfg" % config_dir


func load_campaign_records() -> void:
	campaign_records.clear()
	var config := ConfigFile.new()
	if config.load(campaign_records_path()) == OK:
		for sec in config.get_sections():
			var m_dict := {}
			for k in config.get_section_keys(sec):
				m_dict[k] = config.get_value(sec, k)
			campaign_records[sec] = m_dict


func save_campaign_records() -> void:
	var config := ConfigFile.new()
	for sec in campaign_records.keys():
		var m_dict: Dictionary = campaign_records[sec]
		for k in m_dict.keys():
			config.set_value(sec, k, m_dict[k])
	config.save(campaign_records_path())


func _record_entry(sec: String, score: int, time_taken: float, diff: int) -> Dictionary:
	if OS.has_environment("DRONE_NO_RECORD"):
		return {"completed": true, "best_score": score, "best_time": time_taken,
				"stars": 3, "highest_diff": diff}
	var prev: Dictionary = campaign_records.get(sec, {
		"completed": false,
		"best_score": 0,
		"best_time": 9999.0,
		"stars": 0,
		"highest_diff": 0
	})
	var stars: int = 1
	if diff == Difficulty.ACE or time_taken <= 300.0:
		stars = 3
	elif diff == Difficulty.OPERATOR or time_taken <= 540.0:
		stars = 2

	var rec := {
		"completed": true,
		"best_score": maxi(score, int(prev.get("best_score", 0))),
		"best_time": minf(time_taken, float(prev.get("best_time", 9999.0))),
		"stars": maxi(stars, int(prev.get("stars", 0))),
		"highest_diff": maxi(diff, int(prev.get("highest_diff", 0)))
	}
	campaign_records[sec] = rec
	save_campaign_records()
	return rec


func record_mission_result(mission_id: int, score: int, time_taken: float, diff: int) -> Dictionary:
	return _record_entry("mission_%d" % mission_id, score, time_taken, diff)


func record_special_mission_result(mission_id: int, score: int, time_taken: float, diff: int) -> Dictionary:
	return _record_entry("special_%d" % mission_id, score, time_taken, diff)


func get_mission_record(mission_id: int) -> Dictionary:
	var sec := "mission_%d" % mission_id
	return campaign_records.get(sec, {
		"completed": false,
		"best_score": 0,
		"best_time": 0.0,
		"stars": 0,
		"highest_diff": 0
	})


func get_special_mission_record(mission_id: int) -> Dictionary:
	var sec := "special_%d" % mission_id
	return campaign_records.get(sec, {
		"completed": false,
		"best_score": 0,
		"best_time": 0.0,
		"stars": 0,
		"highest_diff": 0
	})


## Sequential campaign gate: missions unlock only when the previous one is
## completed.  Returns the first incomplete mission (1..4).
func campaign_unlocked_mission() -> int:
	for mission_id in range(1, 5):
		if not bool(get_mission_record(mission_id).get("completed", false)):
			return mission_id
	return 4


func is_mission_unlocked(mission_id: int) -> bool:
	return mission_id >= 1 and mission_id <= campaign_unlocked_mission()


func campaign_completed_count() -> int:
	var count := 0
	for mission_id in range(1, 5):
		if bool(get_mission_record(mission_id).get("completed", false)):
			count += 1
	return count


func campaign_stars_total() -> int:
	var total := 0
	for mission_id in range(1, 5):
		total += int(get_mission_record(mission_id).get("stars", 0))
	return total


func campaign_is_complete() -> bool:
	return campaign_completed_count() >= 4


func is_tutorial_completed() -> bool:
	var sec := "flight_school"
	var rec: Dictionary = campaign_records.get(sec, {})
	return bool(rec.get("completed", false))


func set_tutorial_completed(completed: bool = true) -> void:
	var sec := "flight_school"
	var rec: Dictionary = campaign_records.get(sec, {})
	rec["completed"] = completed
	rec["timestamp"] = get_formatted_date_time()
	campaign_records[sec] = rec
	save_campaign_records()


func set_game_mode(mode: int) -> void:
	if mode < GameMode.size():
		if mode == game_mode:
			return
		game_mode = mode
		emit_signal("game_mode_changed", game_mode)


func compute_rating(score: int, time_s: float, passed: int, total: int,
		failed: bool = false) -> Dictionary:
	if failed:
		return {"stars": 1, "rank": "B"}
	var safe_total := maxi(total, 1)
	var completion := float(passed) / float(safe_total) if total > 0 else 1.0
	var fast_run := (time_s > 0.0 and time_s <= 130.0)
	var medium_run := (time_s > 0.0 and time_s <= 260.0)
	if completion >= 0.99 and (score >= 900 or fast_run):
		return {"stars": 3, "rank": "S"}
	if completion >= 0.65 and (score >= 450 or medium_run or passed >= 3):
		return {"stars": 2, "rank": "A"}
	return {"stars": 1, "rank": "B"}


func get_training_record(map_id: String) -> Dictionary:
	var sec := "training_%s" % map_id.strip_edges().to_lower()
	return campaign_records.get(sec, {
		"completed": false,
		"best_time": 0.0,
		"best_passed": 0,
		"total": 0,
		"best_score": 0,
		"stars": 0,
		"rank": "-",
		"runs": 0,
	})


func record_training_result(map_id: String, time_s: float, passed: int,
		total: int) -> Dictionary:
	var clean_id := map_id.strip_edges().to_lower()
	if clean_id.is_empty():
		clean_id = str(menu_settings.get("selected_map", "village")).to_lower()
	var sec := "training_%s" % clean_id
	var prev: Dictionary = campaign_records.get(sec, {})
	var time_bonus := maxi(0, int(round(360.0 - time_s))) if time_s > 0.0 else 0
	var score := maxi(0, passed) * 120 + time_bonus
	var rating := compute_rating(score, time_s, passed, total, false)
	if OS.has_environment("DRONE_NO_RECORD"):
		return {
			"completed": passed > 0 or total == 0,
			"best_time": time_s,
			"best_passed": passed,
			"total": total,
			"best_score": score,
			"stars": int(rating["stars"]),
			"rank": str(rating["rank"]),
			"runs": 1,
		}
	var prev_best_time := float(prev.get("best_time", 0.0))
	var new_best_time := time_s
	if prev_best_time > 0.0 and time_s > 0.0:
		new_best_time = minf(prev_best_time, time_s)
	elif prev_best_time > 0.0:
		new_best_time = prev_best_time
	var rank_order := {"S": 3, "A": 2, "B": 1, "-": 0}
	var prev_rank := str(prev.get("rank", "-"))
	var new_rank := str(rating["rank"])
	if int(rank_order.get(prev_rank, 0)) > int(rank_order.get(new_rank, 0)):
		new_rank = prev_rank
	var rec := {
		"completed": bool(prev.get("completed", false)) or passed > 0 or total == 0,
		"best_time": new_best_time,
		"best_passed": maxi(passed, int(prev.get("best_passed", 0))),
		"total": maxi(total, int(prev.get("total", 0))),
		"best_score": maxi(score, int(prev.get("best_score", 0))),
		"stars": maxi(int(rating["stars"]), int(prev.get("stars", 0))),
		"rank": new_rank,
		"runs": int(prev.get("runs", 0)) + 1,
	}
	campaign_records[sec] = rec
	save_campaign_records()
	return rec


func get_daily_challenge() -> Dictionary:
	var d := Time.get_date_dict_from_system()
	var y := int(d.get("year", 2026))
	var m := int(d.get("month", 1))
	var day := int(d.get("day", 1))
	var date_key := "%04d-%02d-%02d" % [y, m, day]
	var seed_idx := absi(y * 372 + m * 31 + day)
	var pool := [
		{
			"id": "daily_steppe_course",
			"map": "steppe",
			"mode": PlayMode.TRAINING,
			"mission": 1,
			"bonus_score": 300,
			"title_ua": "СТЕПОВИЙ СЛАЛОМ",
			"title_en": "STEPPE SLALOM",
			"desc_ua": "Пройдіть тренувальний маршрут у степу з рангом A або S",
			"desc_en": "Complete the Steppe training circuit with Rank A or S",
		},
		{
			"id": "daily_village_precision",
			"map": "village",
			"mode": PlayMode.COMBAT,
			"mission": 1,
			"bonus_score": 400,
			"title_ua": "МІСЬКА ТОЧНІСТЬ",
			"title_en": "URBAN PRECISION",
			"desc_ua": "Виконайте тактичний виліт у забудові з високою точністю",
			"desc_en": "Complete a tactical range sortie in the village sector",
		},
		{
			"id": "daily_industrial_gates",
			"map": "industrial",
			"mode": PlayMode.TRAINING,
			"mission": 2,
			"bonus_score": 450,
			"title_ua": "ІНДУСТРІАЛЬНІ ВОРОТА",
			"title_en": "INDUSTRIAL GATES",
			"desc_ua": "Пройдіть технічний маршрут між цехами без пошкоджень",
			"desc_en": "Navigate the industrial technical gate run cleanly",
		},
		{
			"id": "daily_wetlands_intercept",
			"map": "wetlands",
			"mode": PlayMode.COMBAT,
			"mission": 4,
			"bonus_score": 500,
			"title_ua": "ПЕРЕХОПЛЕННЯ НАД БОЛОТАМИ",
			"title_en": "WETLANDS INTERCEPT",
			"desc_ua": "Тактичне перехоплення повітряної цілі над заплавою",
			"desc_en": "Aerial target interception drill over the wetlands",
		},
	]
	var tpl: Dictionary = pool[seed_idx % pool.size()].duplicate(true)
	var rec: Dictionary = campaign_records.get("daily_challenge", {})
	tpl["date"] = date_key
	tpl["completed"] = (str(rec.get("last_completed_date", "")) == date_key)
	tpl["streak"] = int(rec.get("streak", 0))
	return tpl


func mark_daily_challenge_completed() -> void:
	if OS.has_environment("DRONE_NO_RECORD"):
		return
	var ch := get_daily_challenge()
	var date_key := str(ch.get("date", ""))
	var rec: Dictionary = campaign_records.get("daily_challenge", {})
	if str(rec.get("last_completed_date", "")) == date_key:
		return
	rec["last_completed_date"] = date_key
	rec["streak"] = int(rec.get("streak", 0)) + 1
	rec["total_completed"] = int(rec.get("total_completed", 0)) + 1
	rec["bonus_total"] = int(rec.get("bonus_total", 0)) + int(ch.get("bonus_score", 300))
	campaign_records["daily_challenge"] = rec
	save_campaign_records()


func _ghost_track_path(key: String) -> String:
	var clean := key.strip_edges().validate_filename()
	if clean.is_empty():
		clean = "default"
	return "%s/%s.ghost" % [replay_dir, clean]


func save_ghost_track(key: String, samples: Array) -> void:
	if samples.is_empty():
		return
	if not DirAccess.dir_exists_absolute(replay_dir):
		DirAccess.make_dir_recursive_absolute(replay_dir)
	var f := FileAccess.open(_ghost_track_path(key), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(samples))
	f.close()


func load_ghost_track(key: String) -> Array:
	var p := _ghost_track_path(key)
	if not FileAccess.file_exists(p):
		return []
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Array:
		return parsed as Array
	return []


func is_game_center_available() -> bool:
	return Engine.has_singleton("GameCenter") \
			or OS.get_name() == "iOS" or OS.has_feature("ios")


func get_leaderboard_summary(is_en: bool = false) -> String:
	var best_score := 0
	var completed := campaign_completed_count()
	var stars := campaign_stars_total()
	for m_id in range(1, 5):
		best_score = maxi(best_score, int(get_mission_record(m_id).get("best_score", 0)))
	for map_id in ["steppe", "village", "industrial", "wetlands"]:
		best_score = maxi(best_score, int(get_training_record(map_id).get("best_score", 0)))
	var daily_streak := int(campaign_records.get("daily_challenge", {}).get("streak", 0))
	if is_en:
		var gc_tag := "GC READY" if is_game_center_available() else "LOCAL"
		return "%s · %d★ · %d/4 OPS · TOP %d · STREAK %d" % [
			gc_tag, stars, completed, best_score, daily_streak
		]
	var gc_tag_ua := "GAME CENTER" if is_game_center_available() else "ЛОКАЛЬНО"
	return "%s · %d★ · %d/4 ЕТАПІВ · РЕКОРД %d · СЕРІЯ %d" % [
		gc_tag_ua, stars, completed, best_score, daily_streak
	]


func open_game_center_leaderboard() -> void:
	if Engine.has_singleton("GameCenter"):
		var gc := Engine.get_singleton("GameCenter")
		if gc != null and gc.has_method("show_game_center"):
			gc.call("show_game_center", {"view": "leaderboards"})
	emit_signal("leaderboard_requested")


const PILOT_RANKS := [
	{"xp": 0, "ua": "КУРСАНТ", "en": "CADET"},
	{"xp": 500, "ua": "МОЛ. ОПЕРАТОР", "en": "JR. OPERATOR"},
	{"xp": 1500, "ua": "БОЙОВИЙ ПІЛОТ", "en": "COMBAT PILOT"},
	{"xp": 3500, "ua": "СТАРШИЙ АС", "en": "SENIOR ACE"},
	{"xp": 7000, "ua": "КОМАНДИР ЕСКАДРИЛЬЇ", "en": "SQUADRON LEAD"},
]


func get_pilot_rank_info(xp_val: int = -1) -> Dictionary:
	var xp: int = maxi(0, int(menu_settings.get("career_xp", 0))) if xp_val < 0 else maxi(0, xp_val)
	var idx := 0
	for i in range(PILOT_RANKS.size()):
		if xp >= int(PILOT_RANKS[i]["xp"]):
			idx = i
	var rank: Dictionary = PILOT_RANKS[idx]
	var cur_min := int(rank["xp"])
	var next_xp := xp
	var progress := 1.0
	if idx + 1 < PILOT_RANKS.size():
		next_xp = int(PILOT_RANKS[idx + 1]["xp"])
		var span := maxi(1, next_xp - cur_min)
		progress = clampf(float(xp - cur_min) / float(span), 0.0, 1.0)
	return {
		"xp": xp,
		"rank_idx": idx,
		"rank_ua": String(rank["ua"]),
		"rank_en": String(rank["en"]),
		"next_xp": next_xp,
		"progress": progress,
	}


func record_sortie_career(xp_gain: int, kills: Dictionary = {},
		hits: int = 0, drops: int = 0) -> Dictionary:
	var prev_info := get_pilot_rank_info()
	var prev_idx := int(prev_info.get("rank_idx", 0))
	var gained := maxi(0, xp_gain)
	if OS.has_environment("DRONE_NO_RECORD"):
		var preview := get_pilot_rank_info(maxi(0, int(menu_settings.get("career_xp", 0))) + gained)
		preview["prev_rank_idx"] = prev_idx
		preview["promoted"] = int(preview.get("rank_idx", 0)) > prev_idx
		preview["xp_gain"] = gained
		return preview
	menu_settings["career_xp"] = maxi(0, int(menu_settings.get("career_xp", 0))) + gained
	menu_settings["career_kills_armor"] = maxi(0, int(menu_settings.get("career_kills_armor", 0))) + maxi(0, int(kills.get("armor", 0)))
	menu_settings["career_kills_aa"] = maxi(0, int(menu_settings.get("career_kills_aa", 0))) + maxi(0, int(kills.get("aa", 0)))
	menu_settings["career_kills_infantry"] = maxi(0, int(menu_settings.get("career_kills_infantry", 0))) + maxi(0, int(kills.get("infantry", 0)))
	menu_settings["career_kills_air"] = maxi(0, int(menu_settings.get("career_kills_air", 0))) + maxi(0, int(kills.get("air", 0)))
	menu_settings["career_sorties"] = maxi(0, int(menu_settings.get("career_sorties", 0))) + 1
	menu_settings["career_hits"] = maxi(0, int(menu_settings.get("career_hits", 0))) + maxi(0, hits)
	menu_settings["career_drops"] = maxi(0, int(menu_settings.get("career_drops", 0))) + maxi(0, drops)
	save_menu_settings()
	var info := get_pilot_rank_info()
	info["prev_rank_idx"] = prev_idx
	info["promoted"] = int(info.get("rank_idx", 0)) > prev_idx
	info["xp_gain"] = gained
	return info
