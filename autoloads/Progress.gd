extends Node
## Локальна економіка пілота: монети, відкриття дронів/карт/режимів.
##Offline-first: жодних IAP/акаунтів/серверів. Збереження — ConfigFile поруч
## з іншими профілями (user://config_G3/Progress.cfg), з версією схеми й бекапом.

signal coins_changed(value: int)
signal item_unlocked(id: String)

const SAVE_PATH := "user://config_G3/Progress.cfg"
const BACKUP_PATH := "user://config_G3/Progress.cfg.bak"
const SCHEMA_VERSION := 1

## Ціни нових елементів. Усі наявні дрони/карти/режими доступні зі старту.
const PRICES := {
	"drone_wraith": 450, "drone_komar": 300, "drone_shmel": 380,
	"map_lis_forest_freestyle": 600,
	"mode_special_11": 250, "mode_special_12": 300, "mode_special_13": 350,
}

const DEFAULT_UNLOCKED := [
	"map_oilrig", "map_industrial", "map_wetlands", "map_airport",
	"mode_training", "mode_combat", "mode_tutorial", "mode_race",
]

var coins: int = 0
var unlocked: Dictionary = {}
var awarded: Dictionary = {}
var daily_caps: Dictionary = {}
var total_earned: int = 0


func _ready() -> void:
	load_progress()


func is_qa_unlock_all() -> bool:
	return OS.has_environment("QA_UNLOCK_ALL")


func load_progress() -> void:
	coins = 0
	total_earned = 0
	unlocked = {}
	awarded = {}
	daily_caps = {}
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	var loaded_from_backup := false
	if err != OK:
		var backup := ConfigFile.new()
		if backup.load(BACKUP_PATH) == OK:
			cfg = backup
			err = OK
			loaded_from_backup = true
	if err != OK:
		return
	var ver := int(cfg.get_value("meta", "schema_version", 0))
	coins = maxi(0, int(cfg.get_value("profile", "coins", 0)))
	total_earned = maxi(0, int(cfg.get_value("profile", "total_earned", 0)))
	var u: Variant = cfg.get_value("profile", "unlocked", [])
	if u is Array:
		for id in (u as Array):
			var sid := str(id)
			if sid != "mode_chaos" and not sid.is_empty():
				unlocked[sid] = true
	var a: Variant = cfg.get_value("profile", "awarded", [])
	if a is Array:
		for id in (a as Array):
			var sid := str(id)
			if not sid.is_empty():
				awarded[sid] = true
	var c: Variant = cfg.get_value("profile", "daily_caps", {})
	if c is Dictionary:
		daily_caps = (c as Dictionary).duplicate(true)
	if ver < SCHEMA_VERSION or loaded_from_backup:
		save_progress()


func save_progress() -> void:
	var dir_abs := ProjectSettings.globalize_path("user://config_G3")
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
	var tmp_res := SAVE_PATH + ".tmp"
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema_version", SCHEMA_VERSION)
	cfg.set_value("profile", "coins", coins)
	cfg.set_value("profile", "total_earned", total_earned)
	cfg.set_value("profile", "unlocked", unlocked.keys())
	cfg.set_value("profile", "awarded", awarded.keys())
	cfg.set_value("profile", "daily_caps", daily_caps)
	var save_err := cfg.save(tmp_res)
	if save_err != OK:
		push_warning("[Progress] save failed: %s" % error_string(save_err))
		return
	# Verify temp config before touching backup or live profile.
	var verify := ConfigFile.new()
	if verify.load(tmp_res) != OK:
		push_warning("[Progress] temp verify failed; keeping previous save intact")
		return
	var save_abs := ProjectSettings.globalize_path(SAVE_PATH)
	var bak_abs := ProjectSettings.globalize_path(BACKUP_PATH)
	var tmp_abs := ProjectSettings.globalize_path(tmp_res)
	if FileAccess.file_exists(SAVE_PATH):
		var cur_cfg := ConfigFile.new()
		if cur_cfg.load(SAVE_PATH) == OK:
			if FileAccess.file_exists(BACKUP_PATH):
				DirAccess.remove_absolute(bak_abs)
			DirAccess.copy_absolute(save_abs, bak_abs)
		DirAccess.remove_absolute(save_abs)
	var ren_err := DirAccess.rename_absolute(tmp_abs, save_abs)
	if ren_err != OK:
		DirAccess.copy_absolute(tmp_abs, save_abs)
		DirAccess.remove_absolute(tmp_abs)


func is_unlocked(id: String) -> bool:
	if is_qa_unlock_all() or DEFAULT_UNLOCKED.has(id):
		return true
	return bool(unlocked.get(id, false))


func price_of(id: String) -> int:
	return int(PRICES.get(id, 0))


## Списання монет. Повертає true, якщо предмет уже відкритий або щойно куплений.
func try_unlock(id: String) -> bool:
	if is_unlocked(id):
		return true
	var cost := price_of(id)
	if cost <= 0:
		return false  # невідомий ід — нічого не відкриваємо
	if coins < cost:
		return false
	coins -= cost
	unlocked[id] = true
	coins_changed.emit(coins)
	item_unlocked.emit(id)
	save_progress()
	return true


## Заробіток. Ідентичний award_id ніколи не нараховується двічі.
## daily_key/daily_limit — захист від фарму (лічильник на календарний день).
func award(award_id: String, amount: int, daily_key: String = "",
		daily_limit: int = 0) -> int:
	amount = maxi(0, amount)
	if amount <= 0:
		return 0
	if awarded.has(award_id):
		return 0
	if daily_key != "" and daily_limit > 0:
		var today := Time.get_date_string_from_system()
		var rec: Dictionary = daily_caps.get(daily_key, {})
		if str(rec.get("date", "")) != today:
			rec = {"date": today, "count": 0}
		if int(rec.get("count", 0)) >= daily_limit:
			return 0
		rec["count"] = int(rec.get("count", 0)) + 1
		daily_caps[daily_key] = rec
	awarded[award_id] = true
	coins += amount
	total_earned += amount
	coins_changed.emit(coins)
	save_progress()
	return amount


func coins_text() -> String:
	return "◈ %d" % coins


func drone_unlock_id(index: int) -> String:
	return "drone_%s" % str(DroneCatalog.preset(index).get("id", "?"))


func map_unlock_id(map_id: String) -> String:
	return "map_%s" % map_id


func mode_unlock_id(mode: int) -> String:
	match mode:
		Global.PlayMode.TRAINING: return "mode_training"
		Global.PlayMode.COMBAT: return "mode_combat"
		Global.PlayMode.TUTORIAL: return "mode_tutorial"
		_: return "mode_training"


## Викликається зі шляхів завершення місії. Не дублює XP — лише монети.
func award_mission(mission_key: String, mission_id: int, special_id: int,
		success: bool, stars: int, difficulty: int) -> int:
	if not success:
		return 0
	var base := 40
	match difficulty:
		Global.Difficulty.OPERATOR: base = 70
		Global.Difficulty.ACE: base = 120
	var key := "mission_%s_%d_%d_%d" % [mission_key, mission_id, special_id, difficulty]
	var amount := base + maxi(0, stars - 1) * 20
	# Перше проходження дає бонус, але не має згорати, якщо вичерпано добовий ліміт.
	var first_key := "first_%s_%d_%d" % [mission_key, mission_id, special_id]
	var is_first := not awarded.has(first_key)
	var total := amount + (base if is_first else 0)
	var gained := award(key, total, "daily_missions", 6)
	if gained > 0 and is_first:
		awarded[first_key] = true
		save_progress()
	return gained


## Для QA: скинути профіль до чистого стану.
func qa_reset() -> void:
	coins = 0
	total_earned = 0
	unlocked = {}
	awarded = {}
	daily_caps = {}
	save_progress()
