extends Node


signal game_mode_changed


enum GameMode {FREE, RACE}
enum RaceState {START, RACE, END}
enum PlayMode {TRAINING, COMBAT, SPEED, TUTORIAL, CHAOS}
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
var play_mode: int = PlayMode.COMBAT
## Current combat mission stage (1 = Infantry, 2 = Tank & BTR, 3 = Helicopter, 4 = Shahed).
var combat_mission: int = 1
## Special operations are standalone sorties, not campaign records.  0 means a
## normal campaign mission; 1-6 select recon / escort / evacuation / cargo /
## night strike / EW breach.
var special_mission: int = 0
const SPECIAL_MISSION_NAMES := {
	1: "РОЗВІДКА",
	2: "СУПРОВІД",
	3: "ЕВАКУАЦІЯ",
	4: "ДОСТАВКА ВАНТАЖУ",
	5: "НІЧНИЙ ВИЛІТ",
	6: "ПРОРИВ РЕБ",
}


func get_special_mission_name(mission_id: int = -1) -> String:
	var id := special_mission if mission_id < 0 else mission_id
	return str(SPECIAL_MISSION_NAMES.get(id, "СПЕЦОПЕРАЦІЯ"))
## Set by the results screen when "Next mission" is pressed.  The next level
## shows its briefing overlay before flight so the campaign flows
## briefing -> mission -> debriefing without a trip to the main menu.
var chain_briefing_pending: bool = false
## 20-minute time limit (in seconds) for each combat mission.
const COMBAT_TIME_LIMIT := 1200.0
## Small set of menu-only preferences (start video sound, defaults, ...).
var menu_settings := {"video_audio": false, "drone_preset": 7,
		"selected_mode": 1, "selected_mission": 1, "selected_special": 0,
		"selected_map": "village", "difficulty": 1}

## Currently selected drone preset (index into DroneCatalog.PRESETS).
var drone_preset: int = 7

## Target scene to return to from the calibration wizard (e.g. ControlsScreen).
## If empty, defaults to MainMenu.
var calibration_return_scene := ""


func get_difficulty_name() -> String:
	match difficulty:
		Difficulty.RECRUIT: return "РЕКРУТ"
		Difficulty.OPERATOR: return "ОПЕРАТОР"
		Difficulty.ACE: return "АС"
		_: return "ОПЕРАТОР"


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


func _ready() -> void:
	initialize()
	load_menu_settings()
	load_campaign_records()
	var mode_env := OS.get_environment("DRONE_PLAY_MODE").strip_edges().to_lower()
	match mode_env:
		"training":
			play_mode = PlayMode.TRAINING
		"speed":
			play_mode = PlayMode.SPEED
		"combat":
			play_mode = PlayMode.COMBAT
		"tutorial":
			play_mode = PlayMode.TUTORIAL
		"chaos":
			play_mode = PlayMode.CHAOS
	if OS.has_environment("DRONE_TUTORIAL"):
		play_mode = PlayMode.TUTORIAL
	if OS.has_environment("DRONE_COMBAT_MISSION"):
		combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 5)
	if OS.has_environment("DRONE_PRESET"):
		drone_preset = clampi(int(OS.get_environment("DRONE_PRESET")), 0, maxi(DroneCatalog.count() - 1, 0))


func menu_settings_path() -> String:
	return "%s/Menu.cfg" % config_dir


func load_menu_settings() -> void:
	var config := ConfigFile.new()
	if config.load(menu_settings_path()) == OK:
		for key in menu_settings.keys():
			if config.has_section_key("menu", key):
				menu_settings[key] = config.get_value("menu", key)
	# Keep the live selection in sync with the saved one.
	if menu_settings.has("drone_preset"):
		drone_preset = clampi(int(menu_settings["drone_preset"]), 0,
				maxi(DroneCatalog.count() - 1, 0))
	difficulty = clampi(int(menu_settings.get("difficulty", difficulty)), 0, 2)


func save_menu_settings() -> void:
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


func record_mission_result(mission_id: int, score: int, time_taken: float, diff: int) -> Dictionary:
	if OS.has_environment("DRONE_NO_RECORD"):
		return {"completed": true, "best_score": score, "best_time": time_taken,
				"stars": 3, "highest_diff": diff}
	var sec := "mission_%d" % mission_id
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


func get_mission_record(mission_id: int) -> Dictionary:
	var sec := "mission_%d" % mission_id
	return campaign_records.get(sec, {
		"completed": false,
		"best_score": 0,
		"best_time": 0.0,
		"stars": 0,
		"highest_diff": 0
	})


## Sequential campaign gate: missions unlock only when the previous one is
## completed.  Returns the first incomplete mission (1..5).
func campaign_unlocked_mission() -> int:
	for mission_id in range(1, 6):
		if not bool(get_mission_record(mission_id).get("completed", false)):
			return mission_id
	return 5


func is_mission_unlocked(mission_id: int) -> bool:
	return mission_id >= 1 and mission_id <= campaign_unlocked_mission()


func campaign_completed_count() -> int:
	var count := 0
	for mission_id in range(1, 6):
		if bool(get_mission_record(mission_id).get("completed", false)):
			count += 1
	return count


func campaign_stars_total() -> int:
	var total := 0
	for mission_id in range(1, 6):
		total += int(get_mission_record(mission_id).get("stars", 0))
	return total


func campaign_is_complete() -> bool:
	return campaign_completed_count() >= 5


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
