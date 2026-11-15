## Drone catalogue: a set of ready-made quads (racer, freestyle, cinematic,
## long-range, micro, combat bomber). Picking one changes the real flight model
## (mass, motors, propellers, rates) and the payload capacity.
##
## The 3D models in res://Assets/Drones/ua_norm/ were normalised in Blender:
## real-world scale, nose along -Z (Godot forward), origin at the visual centre
## and textures capped at 2K. Because of that they skip the runtime auto-fit.
extends Node

const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const DroneAssemblyBuilderScript = preload("res://scripts/util/DroneAssemblyBuilder.gd")
const GlbMaterialUtilsScript = preload("res://scripts/util/glb_material_utils.gd")

signal preset_changed(index: int)

var custom_presets: Dictionary = {}

## Switching drones used to spend 100-800 ms in ResourceLoader.load() on every
## press because the PackedScene was only a temporary local reference and its
## cache entry was dropped when the preview instance was freed.  Keep the
## PackedScenes alive and prefetch them on a worker thread so a switch is an
## instantiate() (about 2 ms) instead of a synchronous GLB/scene parse.
var _model_scene_cache: Dictionary = {}
var _model_prefetch_queue: Array[int] = []
var _model_prefetch_active := ""
var _model_prefetch_failed: Dictionary = {}


const PRESETS := [
	{
		"id": "grim7",
		"parts_profile": 5,
		"audio_kind": 6,
		"prop_tint": Color(0.17, 0.18, 0.20),
		"motor_tint": Color(0.14, 0.15, 0.17),
		"body_prop_tint": Color(0.20, 0.20, 0.22),
		"name": "«ГРІМ-7»",
		"name_en": "GRIM-7",
		"tag": "ТАКТИЧНИЙ 8–10\"",
		"tag_en": "TACTICAL 8–10\"",
		"desc": "Важкий тактичний дрон дальньої дії",
		"desc_en": "Heavy long-range tactical quad",
		"info": "Важкий квадрокоптер дальньої дії, рама 8–10 дюймів. Потужна батарея на верхній деці та видовжене корисне навантаження з хвостовим оперенням під днищем зміщують центр мас: дрон інертний у віражах і тренує точний захід на ціль.",
		"info_en": "Heavy long-range tactical quad on an 8–10-inch frame. Top-mounted battery and weighted underbody payload shift the center of mass, creating realistic inertia in turns and precision approach training.",
		"dry": 0.90, "batt": 0.50, "kv": 1350, "torque": 2800.0, "rpm": 23000.0,
		"prop_d": 8.0, "prop_p": 4.5, "blades": 3, "rate": 600, "motor_size": 2808,
		"payload": 3, "payload_mass": 1.30, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 3.5,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.032, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.055, -0.015),
		"dimensions": Vector3(0.36, 0.14, 0.36),
		"drag_area": Vector3(0.032, 0.035, 0.020),
		"model": "res://Assets/Drones/ua_norm/grim7.glb",
		"model_size": 0.391, "model_fit": false,
		"fpv_cam_pos": Vector3(-0.0146, 0.007, -0.095), "fpv_cam_pitch": -14.0,
	},
	{
		"id": "grim7m",
		"parts_profile": 6,
		"audio_kind": 6,
		"prop_tint": Color(0.17, 0.18, 0.20),
		"motor_tint": Color(0.14, 0.15, 0.17),
		"body_prop_tint": Color(0.20, 0.20, 0.22),
		"name": "«ГРІМ-7М»",
		"name_en": "GRIM-7M",
		"tag": "ТАКТИЧНИЙ + СКИД",
		"tag_en": "TACTICAL + DROP",
		"desc": "Тактичний дрон із системою скидання",
		"desc_en": "Tactical quad with a payload-release system",
		"info": "Модифікована комплектація: велика акумуляторна збірка зверху з ременем, силовід XT60, виносна антена VTX та нижня захисна дуга-лижа. Обладнаний системою скидання тренувального вантажу під рамою.",
		"info_en": "Upgraded long-range configuration with a top-strapped battery pack, XT60 lead, elevated VTX antenna, and lower skid guard. Equipped with an underframe payload-release mechanism.",
		"dry": 0.88, "batt": 0.48, "kv": 1400, "torque": 2600.0, "rpm": 20500.0,
		"prop_d": 8.0, "prop_p": 4.3, "blades": 3, "rate": 620, "motor_size": 2808,
		"payload": 4, "payload_mass": 0.80, "combat": true, "has_drop": true,
		"drop_name": "2x Скид-М (800г)",
		"drop_name_en": "2× Training Payloads (800 g)",
		"twr": 3.5,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.032, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.048, 0.0),
		"dimensions": Vector3(0.36, 0.14, 0.36),
		"drag_area": Vector3(0.030, 0.032, 0.018),
		"model": "res://Assets/Drones/ua_norm/grim7m.glb",
		"model_size": 0.420, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.002, -0.120), "fpv_cam_pitch": -14.0,
	},
	{
		"id": "strila8",
		"parts_profile": 7,
		"audio_kind": 6,
		"prop_tint": Color(0.68, 0.19, 0.02),
		"motor_tint": Color(0.20, 0.16, 0.12),
		"body_prop_tint": Color(0.22, 0.23, 0.25),
		"name": "«СТРІЛА-8»",
		"name_en": "STRILA-8",
		"tag": "ПЕРЕХОПЛЮВАЧ 8\"",
		"tag_en": "INTERCEPTOR 8\"",
		"desc": "Важкий FPV із виносним підвісом",
		"desc_en": "Heavy tactical FPV with underbody mount",
		"info": "Важкий тактичний дрон із нижнім підвісом та переднім сенсором контакту. Під днищем — видовжене навантаження, зверху вертикально орієнтований акумулятор. Високий момент інерції по осі рискання.",
		"info_en": "Heavy tactical quad featuring an underbody payload mount, forward contact sensor loop, and upright top-mounted battery pack for high-inertia precision flying.",
		"dry": 1.00, "batt": 0.60, "kv": 1100, "torque": 4200.0, "rpm": 23500.0,
		"prop_d": 8.5, "prop_p": 4.6, "blades": 3, "rate": 580, "motor_size": 3115,
		"payload": 4, "payload_mass": 1.40, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 4.2,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.032, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.060, -0.025),
		"dimensions": Vector3(0.38, 0.15, 0.38),
		"drag_area": Vector3(0.034, 0.038, 0.022),
		"model": "res://Assets/Drones/ua_norm/strila8.glb",
		"model_size": 0.376, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.004, -0.053), "fpv_cam_pitch": -10.0,
	},
	{
		"id": "quad5",
		"parts_profile": 9,
		"audio_kind": 0,
		"prop_tint": Color(0.10, 0.48, 0.24),
		"motor_tint": Color(0.10, 0.18, 0.12),
		"body_prop_tint": Color(0.20, 0.22, 0.24),
		"name": "«КВАД-5»",
		"name_en": "QUAD-5",
		"tag": "ШВИДКІСНИЙ FPV 5\"",
		"tag_en": "AGILE FPV 5\"",
		"desc": "Маневрений 5\" FPV на карбоновій X-рамі",
		"desc_en": "Agile 5\" carbon X-frame tactical FPV",
		"info": "Швидкісний 5-дюймовий FPV-дрон на посиленій карбоновій рамі Mark4. Збалансований центр ваги, верхнє розташування LiPo 6S, миттєвий відгук на стіки та тяга 6.5:1 для фрістайлу, перехоплення й тренування.",
		"info_en": "Agile 5-inch FPV quad on a reinforced Mark4 carbon frame. Balanced center of gravity, top-mounted 6S LiPo, crisp stick response, and a 6.5:1 thrust-to-weight ratio for training and interception.",
		"dry": 0.41, "batt": 0.24, "kv": 2450, "torque": 1450.0, "rpm": 34000.0,
		"prop_d": 5.0, "prop_p": 4.5, "blades": 4, "rate": 800, "motor_size": 2207,
		"payload": 1, "payload_mass": 0.18, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 6.5,
		"cog_offset": Vector3(0.0, 0.008, 0.0),
		"dimensions": Vector3(0.22, 0.08, 0.22),
		"drag_area": Vector3(0.012, 0.014, 0.006),
		"model": "res://Assets/Drones/ua_norm/quad5_custom.glb",
		"model_size": 0.225, "model_fit": false, "model_yaw": PI * 0.5,
		"fpv_cam_pos": Vector3(0.0, 0.038, -0.115), "fpv_cam_pitch": -6.0,
	},
	{
		"id": "pisun_vtol",
		"parts_profile": 3,
		"audio_kind": 1,
		"prop_tint": Color(0.18, 0.25, 0.16),
		"motor_tint": Color(0.18, 0.22, 0.16),
		"body_prop_tint": Color(0.22, 0.28, 0.22),
		"name": "«СОКІЛ» VTOL",
		"name_en": "SOKIL VTOL",
		"tag": "VTOL 7\"",
		"tag_en": "VTOL 7\"",
		"desc": "Вертикальний зліт, тактичний VTOL",
		"desc_en": "Vertical-takeoff tactical VTOL tailsitter",
		"info": "Тактичний FPV-дрон на витягнутій карбоновій деці з подовженим центральним відсіком. Злітає вертикально й переходить у горизонтальний політ; батарея 6S і швидкі безщіткові мотори з реалістичним балансом навантаження.",
		"info_en": "Tactical VTOL tailsitter on an extended carbon frame with a central bay. Lifts off vertically and transitions into forward flight; powered by a 6S battery and high-RPM brushless motors.",
		"dry": 0.75, "batt": 0.40, "kv": 1300, "torque": 2200.0, "rpm": 27000.0,
		"prop_d": 7.0, "prop_p": 5.0, "blades": 2, "rate": 500, "motor_size": 2806,
		"payload": 2, "payload_mass": 0.65, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 3.6,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.030, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.040, -0.020),
		"dimensions": Vector3(0.32, 0.12, 0.38),
		"drag_area": Vector3(0.025, 0.028, 0.015),
		"model": "res://Assets/Drones/ua_norm/pisun_vtol.glb",
		"model_size": 0.450, "model_fit": false,
		"model_pitch": 0.0,
		"fpv_cam_pos": Vector3(0.0, 0.088, -0.060), "fpv_cam_pitch": -12.0,
	},
	{
		"id": "military_fpv",
		"parts_profile": 11,
		"audio_kind": 6,
		"prop_tint": Color(0.22, 0.24, 0.16),
		"motor_tint": Color(0.16, 0.18, 0.14),
		"no_ukraine_mark": true,
		"name": "Тактичний БПЛА (Полігон / Скид)",
		"name_en": "Tactical UAV (Range / Drop)",
		"tag": "ТАКТИЧНИЙ БПЛА 8–10″",
		"tag_en": "TACTICAL UAV 8–10\"",
		"desc": "Важкий тактичний дрон із корисним навантаженням",
		"desc_en": "Heavy tactical quad with underbody payload",
		"info": "Важкий квадрокоптер 8–10 дюймів із навантаженням під днищем. Збільшена маса та інерція, центр мас зміщений вниз і вперед, помірна тягооснащеність та реалістичний аеродинамічний опір.",
		"info_en": "Heavy 8–10-inch tactical platform with an underbody payload. Increased mass and forward-shifted center of gravity provide realistic handling and approach momentum.",
		"dry": 1.4, "batt": 0.8, "kv": 1100, "torque": 5500.0, "rpm": 18000.0,
		"prop_d": 10.0, "prop_p": 5.5, "blades": 3, "rate": 550, "motor_size": 3115,
		"payload": 1, "payload_mass": 2.1, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 3.1,
		"battery_chemistry": 1, "battery_mah": 6000.0,
		"battery_resistance": 0.025, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.100, -0.050),
		"dimensions": Vector3(0.45, 0.18, 0.45),
		"drag_area": Vector3(0.050, 0.060, 0.035),
		"model": "res://Assets/Drones/ua_norm/strila8.glb",
		"model_size": 0.450, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.004, -0.090), "fpv_cam_pitch": -14.0,
	},
	{
		"id": "baba_yaga",
		"parts_profile": 12,
		"audio_kind": 5,
		"prop_tint": Color(0.10, 0.12, 0.09),
		"motor_tint": Color(0.12, 0.14, 0.11),
		"no_ukraine_mark": true,
		"name": "«БАБА ЯГА»",
		"name_en": "BABA YAGA",
		"tag": "ВАЖКИЙ ГЕКСАКОПТЕР 6×",
		"tag_en": "HEAVY HEX 6×",
		"desc": "Нічний важкий БПЛА: 6 моторів, 20 кг, Starlink",
		"desc_en": "Heavy night hexacopter: 6 motors, 20 kg, Starlink",
		"info": "Важка шестимоторна платформа нічних тренувальних вильотів. Несе до 20 кг корисного навантаження. Два тепловізійні канали, захищені GNSS-антени та супутниковий термінал Starlink зберігають зв'язок в умовах РЕБ. З повним навантаженням летить близько 40 км/год, після скиду — до 80 км/год; приціл скидання з поправкою на вітер.",
		"info_en": "Heavy six-rotor platform for night training sorties. Carries up to 20 kg payload with dual thermal channels, protected GNSS antennas, and satellite link telemetry. Cruises near 40 km/h loaded and up to 80 km/h after release with a wind-compensated drop sight.",
		"dry": 26.0, "batt": 12.0, "kv": 120, "torque": 12000.0, "rpm": 5600.0,
		"prop_d": 28.0, "prop_p": 8.0, "blades": 3, "rate": 260, "motor_size": 8318,
		"payload": 4, "payload_mass": 12.8, "combat": true, "has_drop": true,
		"drop_name": "4× тренувальні контейнери",
		"drop_name_en": "4× training payloads",
		"heavy_bomber": true, "fpv_hide_model": true,
		"max_speed_loaded": 11.11, "max_speed_empty": 22.22,
		"twr": 2.65,
		"battery_chemistry": 1, "battery_mah": 30000.0,
		"battery_resistance": 0.018, "battery_max_current": 180.0,
		"cog_offset": Vector3(0.0, -0.20, 0.0),
		"dimensions": Vector3(2.80, 0.95, 1.55),
		"drag_area": Vector3(0.28, 0.58, 0.40),
		"model": "res://Assets/Drones/ua_norm/baba_yaga.glb",
		"model_size": 2.80, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.16, -0.78), "fpv_cam_pitch": -18.0,
		"bomb_cam_pos": Vector3(0.0, 0.82, 0.10), "bomb_cam_pitch": -78.0,
	},
	{
		"id": "leleka100",
		"parts_profile": 13,
		"audio_kind": 3,
		"prop_tint": Color(0.72, 0.74, 0.72),
		"motor_tint": Color(0.22, 0.23, 0.24),
		"pusher": true,
		"composite_base": true,
		"no_ukraine_mark": true,
		"name": "«ЛЕЛЕКА-100»",
		"name_en": "LELEKA-100",
		"tag": "РОЗВІДУВАЛЬНИЙ БПЛА 2 м",
		"tag_en": "RECON UAV 2 m",
		"desc": "Оперативно-тактичний БАК, день/ніч",
		"desc_en": "Operational tactical fixed-wing UAV, day/night",
		"info": "Український оперативно-тактичний безпілотник: високоплан із двома хвостовими балками, штовхаючим гвинтом, гіростабілізованою денною/тепловізійною оптикою та захищеними каналами зв'язку й GNSS. Крейсерська швидкість 65–80 км/год.",
		"info_en": "Ukrainian operational tactical UAV: high-wing twin-boom airframe with pusher prop, gyrostabilized day/thermal optics, and protected telemetry and GNSS links. Cruises at 65–80 km/h.",
		"dry": 4.6, "batt": 1.2, "kv": 380, "torque": 2200.0, "rpm": 7500.0,
		"prop_d": 14.0, "prop_p": 8.0, "blades": 2, "rate": 260, "motor_size": 2814,
		"payload": 1, "payload_mass": 1.5, "combat": true, "has_drop": false,
		"kamikaze": true, "fixed_wing": true,
		"max_speed_loaded": 18.1, "max_speed_empty": 22.2,
		"twr": 2.6,
		"battery_chemistry": 1, "battery_mah": 6000.0,
		"battery_resistance": 0.025, "battery_max_current": 80.0,
		"cog_offset": Vector3(0.0, -0.01, 0.0),
		"dimensions": Vector3(2.0, 0.55, 1.2),
		"drag_area": Vector3(0.050, 0.030, 0.035),
		"model": "res://Assets/Drones/ua_norm/leleka_100.glb",
		"model_size": 2.0, "model_fit": false,
		"fpv_hide_model": true,
		"fpv_cam_pos": Vector3(0.0, 0.06, -0.56), "fpv_cam_pitch": -7.0,
	},
	{
		"id": "furia",
		"parts_profile": 14,
		"audio_kind": 3,
		"prop_tint": Color(0.42, 0.45, 0.46),
		"motor_tint": Color(0.20, 0.21, 0.22),
		"pusher": true,
		"composite_base": true,
		"no_ukraine_mark": true,
		"name": "«ФУРІЯ» A1-СМ",
		"name_en": "FURIA A1-SM",
		"tag": "ЛІТАЮЧЕ КРИЛО 2 м",
		"tag_en": "FLYING WING 2 m",
		"desc": "Тактичне літаюче крило, 130 км/год",
		"desc_en": "Tactical flying wing, 130 km/h",
		"info": "Український комплекс «Атлон Авіа»: тактичне літаюче крило розмахом 2 м зі штовхаючим гвинтом та денною/нічною оптикою наведення. Крейсерська швидкість 65 км/год, максимальна до 130 км/год.",
		"info_en": "Ukrainian Athlon Avia tactical flying wing with a 2 m wingspan, pusher prop, and day/night guidance optics. Cruises at 65 km/h with a top speed of 130 km/h.",
		"dry": 4.2, "batt": 1.3, "kv": 420, "torque": 2000.0, "rpm": 7950.0,
		"prop_d": 13.0, "prop_p": 7.0, "blades": 2, "rate": 250, "motor_size": 2812,
		"payload": 1, "payload_mass": 1.2, "combat": true, "has_drop": false,
		"kamikaze": true, "fixed_wing": true,
		"max_speed_loaded": 18.1, "max_speed_empty": 36.1,
		"twr": 2.7,
		"battery_chemistry": 1, "battery_mah": 7000.0,
		"battery_resistance": 0.025, "battery_max_current": 85.0,
		"cog_offset": Vector3(0.0, 0.0, 0.0),
		"dimensions": Vector3(2.0, 0.35, 0.9),
		"drag_area": Vector3(0.045, 0.025, 0.030),
		"model": "res://Assets/Drones/ua_norm/furia_a1sm.glb",
		"model_size": 2.0, "model_fit": false,
		"fpv_hide_model": true,
		"fpv_cam_pos": Vector3(0.0, 0.04, -0.42), "fpv_cam_pitch": -8.0,
	},
	{
		"id": "chaklun_jet",
		"parts_profile": 15,
		"audio_kind": 4,
		"prop_tint": Color(0.10, 0.11, 0.12),
		"motor_tint": Color(0.10, 0.11, 0.12),
		"composite_base": true,
		"no_ukraine_mark": true,
		"name": "«ЧАКЛУН JET»",
		"name_en": "CHAKLUN JET",
		"tag": "РЕАКТИВНИЙ ПЕРЕХОПЛЮВАЧ",
		"tag_en": "JET INTERCEPTOR",
		"desc": "320 км/год, перехоплення повітряних цілей",
		"desc_en": "320 km/h aerial target interceptor",
		"info": "Український реактивний дрон-перехоплювач для повітряних цілей на полігоні. Довжина 1,65 м, розмах 1,5 м, злітна маса 10,4 кг. Крейсерська 220 км/год, максимальна 320 км/год, політ 40–60 хвилин, стеля 6000 м, катапультний запуск.",
		"info_en": "Ukrainian jet interceptor platform for high-speed aerial target training. Length 1.65 m, wingspan 1.5 m, takeoff mass 10.4 kg. Cruises at 220 km/h with a 320 km/h top speed and 6000 m ceiling.",
		"dry": 8.8, "batt": 1.6, "kv": 0, "torque": 8000.0, "rpm": 15000.0,
		"prop_d": 14.0, "prop_p": 10.0, "blades": 4, "rate": 240, "motor_size": 5010,
		"payload": 1, "payload_mass": 1.6, "combat": true, "has_drop": false,
		"kamikaze": true, "fixed_wing": true, "is_jet": true, "interceptor": true,
		"fpv_hide_model": true,
		"max_speed_loaded": 61.1, "max_speed_empty": 88.9,
		"twr": 3.3,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.022, "battery_max_current": 100.0,
		"cog_offset": Vector3(0.0, -0.02, 0.0),
		"dimensions": Vector3(1.5, 0.4, 1.65),
		"drag_area": Vector3(0.030, 0.025, 0.022),
		"model": "res://Assets/Drones/ua_norm/chaklun_jet.glb",
		"model_size": 1.65, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.06, -0.78), "fpv_cam_pitch": -5.0,
	},
]


func preset(index: int) -> Dictionary:
	var idx := clampi(index, 0, PRESETS.size() - 1)
	var result: Dictionary = custom_presets[index] \
			if custom_presets.has(index) else PRESETS[idx]
	var preset_id := str(result.get("id", ""))
	if _is_mobile_platform() and preset_id in ["leleka100", "furia", "chaklun_jet"]:
		# iOS-only FPV framing so the wing does not fill the centre of the screen.
		result = result.duplicate(true)
		result["fpv_hide_model"] = true
		result.erase("fpv_show_airframe")
		match preset_id:
			"leleka100":
				result["fpv_cam_pos"] = Vector3(0.0, 0.06, -0.72)
				result["fpv_cam_pitch"] = -5.0
			"furia":
				result["fpv_cam_pos"] = Vector3(0.0, 0.04, -0.55)
				result["fpv_cam_pitch"] = -5.0
			_:
				result["fpv_cam_pos"] = Vector3(0.0, 0.10, -0.48)
				result["fpv_cam_pitch"] = -10.0
	return result


func _is_mobile_platform() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


func _is_en() -> bool:
	var loc := get_node_or_null("/root/Loc")
	return loc != null and int(loc.get("current_language")) == 1


func get_drone_name(index: int) -> String:
	var p := preset(index)
	if _is_en():
		return str(p.get("name_en", MenuUI.translate_text(str(p.get("name", "")))))
	return str(p.get("name", ""))


func get_drone_tag(index: int) -> String:
	var p := preset(index)
	if _is_en():
		return str(p.get("tag_en", MenuUI.translate_text(str(p.get("tag", "")))))
	return str(p.get("tag", ""))


func get_drone_desc(index: int) -> String:
	var p := preset(index)
	if _is_en():
		return str(p.get("desc_en", MenuUI.translate_text(str(p.get("desc", "")))))
	return str(p.get("desc", ""))


func get_drone_info(index: int) -> String:
	var p := preset(index)
	var base := str(p.get("info", p.get("desc", "")))
	if _is_en():
		return str(p.get("info_en", MenuUI.translate_text(base)))
	return base


func get_drone_drop_name(index: int) -> String:
	var p := preset(index)
	var base := str(p.get("drop_name", ""))
	if _is_en():
		return str(p.get("drop_name_en", base))
	return base


## True when the preset is a combat strike airframe.
func is_combat(index: int) -> bool:
	var p := preset(index)
	return bool(p.get("combat", false))


## Combat-ready payload activation: detachable stores and integrated kamikaze
## warheads share the in-flight action.
func supports_payload_actions(index: int) -> bool:
	var p := preset(index)
	return bool(p.get("combat", false)) \
			and (int(p.get("payload", 0)) > 0 or bool(p.get("has_drop", false)) \
				or bool(p.get("kamikaze", false)))


## First usable combat airframe (index 0).
func first_combat_index() -> int:
	for i in range(PRESETS.size()):
		if is_combat(i):
			return i
	return 0


## Preset index hosting custom modular builder assemblies ("quad5").
func custom_preset_index() -> int:
	for i in range(PRESETS.size()):
		if str(PRESETS[i].get("id", "")) == "quad5":
			return i
	return 0


func set_custom_preset(index: int, data: Dictionary) -> void:
	custom_presets[index] = data
	preset_changed.emit(index)


func _ready() -> void:
	# The in-game catalog now exposes only shipped ready-to-fly presets. Leave
	# any legacy builder JSON untouched, but do not load it into the fleet.
	var env := OS.get_environment("DRONE_PRESET").strip_edges()
	if env.is_valid_int():
		Global.drone_preset = clampi(int(env), 0, PRESETS.size() - 1)
		print("[DroneCatalog] preset override -> ", Global.drone_preset)


func _load_saved_builder_preset() -> void:
	var path := "user://custom_drone_builder.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		var cfg: Dictionary = json.data
		var ttx := DroneAssemblyBuilderScript.calculate_ttx(cfg)
		var frame: Dictionary = ttx.get("frame", {})
		var motor: Dictionary = ttx.get("motor", {})
		var prop: Dictionary = ttx.get("prop", {})
		var batt: Dictionary = ttx.get("battery", {})
		var payload: Dictionary = ttx.get("payload", {})
		var twr: float = float(ttx.get("twr", 5.0))
		var is_combat: bool = bool(ttx.get("is_combat", false))
		var has_drop: bool = bool(ttx.get("has_drop", false))
		
		var p: Dictionary = {
			"name": "«КАСТОМ БПЛА» [%s]" % str(frame.get("name", "5\"")),
			"name_en": "CUSTOM UAV [%s]" % str(frame.get("name_en", frame.get("name", "5\""))),
			"tag": "КОНСТРУКТОР %s\"" % str(frame.get("size_inch", 5.0)),
			"desc": "Індивідуальна збірка з модульного конструктора",
			"desc_en": "Custom modular drone assembly",
			"info": "Кастомний FPV-дрон, зібраний оператором у модульному конструкторі: Рама: %s, Мотори: %s, АКБ: %s, БЧ: %s." % [
				frame.get("name", ""), motor.get("name", ""), batt.get("name", ""), payload.get("name", "")
			],
			"info_en": "Custom FPV drone assembled from modular parts: frame %s, motors %s, battery %s, payload %s." % [
				frame.get("name_en", frame.get("name", "")), motor.get("name_en", motor.get("name", "")),
				batt.get("name_en", batt.get("name", "")), payload.get("name_en", payload.get("name", ""))
			],
			"dry": float(ttx.get("dry_mass_g", 410.0)) / 1000.0,
			"batt": float(ttx.get("battery_mass_g", 180.0)) / 1000.0,
			"kv": int(motor.get("kv_rating", 2450)),
			"torque": float(motor.get("thrust_g", 1600)) * 0.9,
			"rpm": float(motor.get("kv_rating", 2450)) * float(batt.get("voltage_v", 14.8)),
			"prop_d": float(prop.get("diameter_inch", 5.1)),
			"prop_p": float(prop.get("pitch_inch", 4.6)),
			"blades": int(prop.get("blades", 3)),
			"rate": 750 if twr > 4.0 else 550,
			"motor_size": 2207 if int(motor.get("kv_rating", 2450)) > 2000 else 2807,
			"payload": 1 if is_combat else 0,
			"payload_mass": float(ttx.get("payload_mass_g", 0.0)) / 1000.0,
			"combat": is_combat,
			"has_drop": has_drop,
			"drop_name": "ВОГ-17 ОФ (340г)" if has_drop else "",
			"twr": twr,
			"cog_offset": Vector3(0.0, 0.005, 0.0),
			"dimensions": Vector3(0.25, 0.08, 0.25),
			"drag_area": Vector3(0.015, 0.018, 0.008),
			"parts_profile": 9,
			"model_builder_config": cfg,
			"is_builder_custom": true,
			"model": str(frame.get("mesh_path", "")),
			"model_size": float(frame.get("size_inch", 5.0)) * 0.045,
			"model_fit": false,
			"fpv_cam_pos": Vector3(0.0, 0.025, -0.075),
			"fpv_cam_pitch": -8.0
		}
		var slot := custom_preset_index()
		set_custom_preset(slot, p)
		print("[DroneCatalog] Loaded custom builder drone into preset ", slot)


func count() -> int:
	return PRESETS.size()


## Writes the preset into the quad settings (mass, rates) and saves them.
func apply(index: int) -> void:
	var p := preset(index)
	QuadSettings.dry_weight = float(p["dry"])
	QuadSettings.battery_weight = float(p["batt"])
	QuadSettings.payload_weight = float(p.get("payload_mass", 0.0))
	# A pilot-tuned rate/expo setup survives level restarts and drone changes.
	# Picking a new drone in the menu clears the flag first, so its factory
	# rates still apply there.
	if not QuadSettings.custom_rates:
		QuadSettings.rate_pitch = int(p["rate"])
		QuadSettings.rate_roll = int(p["rate"])
		QuadSettings.rate_yaw = int(p["rate"])
	QuadSettings.save_quad_settings()
	Global.drone_preset = clampi(index, 0, PRESETS.size() - 1)
	Global.menu_settings["drone_preset"] = Global.drone_preset
	Global.save_menu_settings()
	preset_changed.emit(Global.drone_preset)


## Applies the preset to a live drone: motors, propellers, hover thrust.
func apply_to_drone(drone: Node, index: int) -> void:
	apply(index)
	var p := preset(index)
	if drone == null or not is_instance_valid(drone):
		return
	if drone.has_method("apply_preset_physics"):
		drone.call("apply_preset_physics", p)
	var motors: Array = drone.get("motors")
	if motors == null:
		return
	for motor in motors:
		if motor == null:
			continue
		motor.kv = int(p["kv"])
		motor.motor_size = int(p["motor_size"])
		motor.MAX_RPM = float(p["rpm"])
		motor.MAX_TORQUE = float(p["torque"]) / 1000.0
		motor.max_rpm_change = motor.MAX_TORQUE * motor.RPM_ACCELERATION
		# Large propellers must spool visibly slower than 5" racers.  The raw
		# torque*acceleration number made the 28" bomber reach 90% RPM in 0.03 s.
		var spool_class := str(drone.get("physics_class"))
		var target_spool := 0.07
		match spool_class:
			"micro":
				target_spool = 0.09
			"7inch":
				target_spool = 0.13
			"8inch":
				target_spool = 0.17
			"10inch":
				target_spool = 0.22
		var desired_rate := maxf(motor.MAX_RPM, 1.0) * 0.9 / target_spool
		if motor.max_rpm_change > desired_rate:
			motor.max_rpm_change = desired_rate
		var prop = motor.get("propeller")
		if prop != null:
			prop.diameter = float(p["prop_d"])
			prop.pitch = float(p["prop_p"])
			prop.num_blades = int(p["blades"])
			prop.scale = Vector3.ONE * (float(p["prop_d"]) / 5.0)
	_calibrate_propellers(drone, p)
	if drone.has_method("recalibrate_static_twr"):
		drone.call("recalibrate_static_twr")
	if drone.get("flight_controller") != null:
		drone.flight_controller.set_hover_thrust(drone.mass / 4.0 * 9.81)
	print("[DroneCatalog] applied '", p["name"], "' (mass ", drone.mass, "kg)")
	attach_model(drone, index)
	if drone.has_method("refresh_motor_audio"):
		drone.call("refresh_motor_audio")


## The blade-element model uses a fixed tip chord.  A 28" bomber prop therefore
## produced less than a third of its design thrust while a 5" racer was fine.
## Set a sane baseline chord, scale once to the catalog TWR, then refine once.
## No feedback loop: a negative intermediate would otherwise drive c_tip below
## zero and flip the thrust sign.
static func _calibrate_propellers(drone: Node, p: Dictionary) -> void:
	var motors: Array = drone.get("motors")
	if motors == null or motors.is_empty():
		return
	var target := float(p.get("twr", 0.0)) * float(drone.mass) * 9.81
	if target <= 0.0:
		return
	for motor in motors:
		if motor == null:
			continue
		var prop = motor.get("propeller")
		if prop != null:
			prop.c_tip = 0.01
	var base_total := _measure_static_thrust(motors)
	if base_total <= 0.0001:
		return
	var scale := clampf(target / base_total, 0.20, 6.0)
	for motor in motors:
		if motor == null:
			continue
		var prop = motor.get("propeller")
		if prop != null:
			prop.c_tip = clampf(0.01 * scale, 0.002, 0.12)
	var total := _measure_static_thrust(motors)
	if total > 0.0001:
		var refine := clampf(target / total, 0.5, 2.0)
		for motor in motors:
			if motor == null:
				continue
			var prop = motor.get("propeller")
			if prop != null:
				prop.c_tip = clampf(float(prop.c_tip) * refine, 0.002, 0.12)


static func _measure_static_thrust(motors: Array) -> float:
	var total := 0.0
	for motor in motors:
		if motor == null:
			continue
		var prop = motor.get("propeller")
		if prop != null:
			total += maxf(prop.static_thrust(float(motor.MAX_RPM)), 0.0)
	return total


# ------------------------------------------------------------------ 3D model
func _model_path(index: int) -> String:
	var p := preset(index)
	if bool(p.get("is_builder_custom", false)) or p.has("model_builder_config"):
		return ""
	return str(p.get("model", ""))


func _scene_cached(path: String):
	if path.is_empty():
		return null
	if _model_scene_cache.has(path):
		return _model_scene_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if packed is PackedScene:
		_model_scene_cache[path] = packed
		return packed
	return null


## Queue a model for background loading.  Called for the current/next/previous
## preview and, after the menu settles, for the rest of the roster.
func prefetch_model(index: int) -> void:
	var path := _model_path(index)
	if path.is_empty() or _model_scene_cache.has(path) \
			or _model_prefetch_failed.has(path) or _model_prefetch_active == path \
			or _model_prefetch_queue.has(index):
		return
	_model_prefetch_queue.append(index)


func prioritize_model(index: int) -> void:
	var path := _model_path(index)
	if path.is_empty() or _model_scene_cache.has(path) \
			or _model_prefetch_failed.has(path):
		return
	_model_prefetch_queue.erase(index)
	_model_prefetch_queue.push_front(index)


func is_model_ready(index: int) -> bool:
	var path := _model_path(index)
	return not path.is_empty() and _model_scene_cache.has(path)


## Advances exactly one background load.  Safe to call from _process: it never
## blocks the main thread.
func poll_model_prefetch() -> void:
	if _model_prefetch_active.is_empty():
		while not _model_prefetch_queue.is_empty():
			var index: int = _model_prefetch_queue.pop_front()
			var path := _model_path(index)
			if path.is_empty() or _model_scene_cache.has(path):
				continue
			var err := ResourceLoader.load_threaded_request(path)
			if err == OK:
				_model_prefetch_active = path
				break
			_model_prefetch_failed[path] = true
		return
	var status := ResourceLoader.load_threaded_get_status(_model_prefetch_active)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var res = ResourceLoader.load_threaded_get(_model_prefetch_active)
		if res is PackedScene:
			_model_scene_cache[_model_prefetch_active] = res
		else:
			_model_prefetch_failed[_model_prefetch_active] = true
		_model_prefetch_active = ""
	elif status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_model_prefetch_failed[_model_prefetch_active] = true
		_model_prefetch_active = ""


## Await the worker-thread load without blocking the frame.  Returns false on
## timeout/failure; the caller then falls back to the synchronous path.
func wait_for_model(index: int, timeout_ms: int = 6000) -> bool:
	var path := _model_path(index)
	if path.is_empty():
		return false
	if _model_scene_cache.has(path):
		return true
	prioritize_model(index)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		poll_model_prefetch()
		if _model_scene_cache.has(path):
			return true
		if _model_prefetch_failed.has(path):
			return false
		await get_tree().process_frame
	return _model_scene_cache.has(path)


func prefetch_all_models() -> void:
	for i in range(count()):
		prefetch_model(i)


func clear_model_cache() -> void:
	_model_scene_cache.clear()
	_model_prefetch_queue.clear()
	_model_prefetch_active = ""
	_model_prefetch_failed.clear()


func _exit_tree() -> void:
	if not _model_prefetch_active.is_empty():
		var st := ResourceLoader.load_threaded_get_status(_model_prefetch_active)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(_model_prefetch_active)
		_model_prefetch_active = ""
	clear_model_cache()


func attach_model(parent: Node3D, index: int) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var existing := parent.get_node_or_null("DroneModel")
	if existing != null:
		parent.remove_child(existing)
		existing.queue_free()
	var p := preset(index)
	
	# Custom modular builder drone
	if bool(p.get("is_builder_custom", false)) or p.has("model_builder_config"):
		var cfg: Dictionary = p.get("model_builder_config", {})
		var custom_model := DroneAssemblyBuilderScript.build_drone_node(cfg)
		if custom_model != null:
			parent.add_child(custom_model)
			GlbMaterialUtilsScript.ensure_pbr(custom_model)
			_strip_ukraine_markings(custom_model)
			DronePropellerSystem.setup_propellers(custom_model, index,
					float(p.get("prop_d", 5.0)), int(p.get("blades", 3)))
			print("[DroneCatalog] attached custom modular model preset=", index)
			return custom_model

	var path := str(p.get("model", ""))
	if path.is_empty():
		return null
	# Certain mobile airframes have many small static GLB objects. Use their
	# mobile-only join-by-material exports (originals remain for PC) to lower
	# scene nodes/draw submissions while keeping rotor/camera/warhead nodes.
	if OS.has_feature("mobile") or OS.get_name() == "iOS" \
			or OS.has_environment("MOBILE_UI"):
		var mobile_path := path.trim_suffix(".glb") + "_mobile.glb"
		if ResourceLoader.exists(mobile_path):
			path = mobile_path
	var model: Node3D = null
	if ResourceLoader.exists(path):
		var packed = _scene_cached(path)
		if packed is PackedScene:
			model = (packed as PackedScene).instantiate() as Node3D
	if model == null:
		var real_p := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or FileAccess.file_exists(real_p):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(real_p, state) == OK:
				var scene_node := doc.generate_scene(state)
				if scene_node is Node3D:
					model = scene_node as Node3D
	if model == null:
		return null
	model.name = "DroneModel"
	model.set_meta("source_glb", path)
	model.add_to_group("drone_model")
	parent.add_child(model)
	# Inherited GLBs may predate the PBR library; upgrade at generation time
	# so the menu stage, hangar preview and in-game model agree.
	GlbMaterialUtilsScript.ensure_pbr(model)
	model.rotation.y = float(p.get("model_yaw", 0.0))
	model.rotation_degrees.x = float(p.get("model_pitch", 0.0))
	for v in _visuals(model):
		if v is GeometryInstance3D:
			(v as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pre-normalised assets already carry their real-world scale and a centred
	# origin, so the runtime auto-fit is skipped for them.
	if bool(p.get("model_fit", true)):
		var target := float(p.get("model_size", 0.3))
		if target > 0.0001:
			var box := _combined_aabb(model)
			var max_dim := maxf(box.size.x, maxf(box.size.y, box.size.z))
			if max_dim > 0.0001:
				var factor := target / max_dim
				model.scale = Vector3.ONE * factor
				model.position = -(box.get_center() - parent.global_position) * factor
	DronePropellerSystem.setup_propellers(model, index,
			float(p.get("prop_d", 5.0)), int(p.get("blades", 3)))
	_apply_composite_detail(model, index)
	_strip_ukraine_markings(model)
	print("[DroneCatalog] model '", path.get_file(), "' preset=", index)
	return model


## Removes the blue-yellow flag markings from every airframe.  Older GLBs use
## the runtime UkraineMark decal; the newer Blender kits have dedicated flag
## meshes/materials.  Serial numbers and neutral stencils are left intact.
func _strip_ukraine_markings(model: Node3D) -> void:
	if model == null:
		return
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var lower_name := String(mi.name).to_lower()
		var hide := lower_name.contains("flag") or lower_name.contains("ukrainemark") \
				or lower_name.contains("ukraine_mark")
		if not hide:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat == null:
					continue
				var mat_name := String(mat.resource_name).to_lower()
				if mat_name.contains("ukraine_flag") or mat_name.contains("ukrain_flag") \
						or mat_name == "flag":
					hide = true
					break
		if hide:
			mi.visible = false


static var _composite_normal: NoiseTexture2D = null


## Add a subtle triplanar composite-weave normal and roughness to the new
## fixed-wing airframes so their large white/gray surfaces do not read as flat
## cardboard under the hangar lights.  Authored dark parts (cameras, props,
## nozzles, flag, stencils) are left untouched.
func _apply_composite_detail(model: Node3D, index: int) -> void:
	var p := preset(index)
	if not bool(p.get("composite_base", false)):
		return
	if _composite_normal == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.09
		noise.fractal_octaves = 4
		noise.fractal_gain = 0.55
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 2.2
		tex.noise = noise
		_composite_normal = tex
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var lower := String(mi.name).to_lower()
		if lower.contains("flag") or lower.contains("text") or lower.contains("stencil") \
				or lower.contains("prop") or lower.contains("camera") \
				or lower.contains("lens") or lower.contains("motor") \
				or lower.contains("nozzle") or lower.contains("turbine") \
				or lower.contains("glass") or lower.contains("irst") \
				or lower.contains("black") or lower.contains("canopy") \
				or lower.contains("gimbal") or lower.contains("wheel") \
				or lower.contains("skid"):
			continue
		# Only recolour the composite skin; carbon weave, black plastic, machined
		# alloy and the flag keep their authored materials and read as detail.
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var mat_name := String(src.resource_name).to_lower()
			if not mat_name.contains("composite"):
				continue
			var mat := StandardMaterial3D.new()
			var base := Color(0.34, 0.39, 0.36)
			if index == 14:
				base = Color(0.28, 0.31, 0.30)
			elif index == 15:
				base = Color(0.10, 0.11, 0.12)
			if mat_name.contains("grey"):
				base = base.darkened(0.18)
			mat.albedo_color = base
			mat.roughness = 0.56
			mat.metallic = 0.08
			mat.normal_enabled = true
			mat.normal_texture = _composite_normal
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3(7.0, 7.0, 7.0)
			mat.uv1_world_triplanar = false
			mi.set_surface_override_material(s, mat)


static var _ukraine_texture: ImageTexture = null


## Every Ukrainian airframe carries a small blue-yellow flag with a trident.
## The three new Blender models have it painted in; older GLBs get this compact
## runtime decal placed on a real broad top surface found by CPU raycasts.
## The old version used the merged AABB top, which put flags on antenna tips or
## left them hovering above a wing; the decal is now seated on geometry.
func _attach_ukraine_mark(model: Node3D, p: Dictionary, _index: int) -> void:
	if model == null or bool(p.get("no_ukraine_mark", false)):
		return
	var preset_name := str(p.get("name", ""))
	if preset_name.contains("ЛЕЛЕКА") or preset_name.contains("ФУРІЯ") \
			or preset_name.contains("ЧАКЛУН") or preset_name.contains("БАБА"):
		return
	if _ukraine_texture == null:
		_ukraine_texture = _make_ukraine_texture()
	var surfaces := _collect_mark_surfaces(model)
	var tris: Dictionary = surfaces["tris"]
	var box: AABB = surfaces["box"]
	if box.size == Vector3.ZERO:
		return
	var anchor := _pick_mark_anchor(tris, box)
	if anchor.is_empty():
		var center := box.get_center()
		anchor = {"point": Vector3(center.x, box.end.y, center.z),
				"normal": Vector3.UP}
	var point: Vector3 = anchor["point"]
	var normal: Vector3 = anchor["normal"]
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()
	# Deliberately small: a discreet marking, not a billboard.
	var w := clampf(maxf(box.size.x, box.size.z) * 0.17, 0.028, 0.085)
	var h := w * 0.58
	var mi := MeshInstance3D.new()
	mi.name = "UkraineMark"
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _ukraine_texture
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.88)
	mat.roughness = 0.62
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Basis with +Z on the surface normal and the texture "up" along the nose
	# (-Z), matching the old flat decal's reading direction.
	var up := Vector3(0.0, 0.0, -1.0)
	up -= normal * up.dot(normal)
	if up.length_squared() < 0.0001:
		up = Vector3(1.0, 0.0, 0.0) - normal * normal.x
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var right := up.cross(normal)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	up = normal.cross(right).normalized()
	model.add_child(mi)
	# Keep the decal close to the skin: a fixed 6 mm lift was visible as a
	# shadow gap on the smallest airframes in the hangar close-up.
	var lift := clampf(w * 0.05, 0.002, 0.004)
	mi.transform = Transform3D(Basis(right, up, normal), point + normal * lift)


## Parts that must never carry the flag: moving propellers, motors, antennas,
## wires, weapons and payloads.  Skipping them also keeps the cost down.
const _MARK_SKIP_PARTS := ["prop", "motor", "blade", "antenna", "ant_",
		"vtx_ant", "rx_ant", "wire", "provod", "bomb", "missile", "grenade",
		"payload", "ukrainemark"]


## Collect every visible airframe triangle in model space.  Transparent
## surfaces (canopies, camera domes) stay in the list as occluders but are
## marked non-solid so a flag can never be buried under glass.
func _collect_mark_surfaces(model: Node3D) -> Dictionary:
	var visuals: Array = []
	var box := AABB()
	var first := true
	for v in _visuals(model):
		var mi := v as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var visible := mi.visible
		if mi.is_inside_tree():
			visible = mi.is_visible_in_tree()
		if not visible:
			continue
		var xf := _model_relative_xf(model, mi)
		var lb: AABB = xf * mi.mesh.get_aabb()
		visuals.append({"mi": mi, "xf": xf, "box": lb})
		if first:
			box = lb
			first = false
		else:
			box = box.merge(lb)
	if visuals.is_empty():
		return {"tris": {}, "box": AABB()}
	var ta := PackedVector3Array()
	var tb := PackedVector3Array()
	var tc := PackedVector3Array()
	var centers := PackedVector3Array()
	var normals := PackedVector3Array()
	var areas := PackedFloat32Array()
	var solid := PackedByteArray()
	# Only top-side geometry can host the marking.  Hundreds of tiny bolts and
	# low frame parts on the detailed kits used to cost most of the attach
	# time without ever winning the anchor.
	var low_cut := box.position.y + box.size.y * 0.35
	var mesh_entries: Array = []
	for entry in visuals:
		var mi: MeshInstance3D = entry["mi"]
		var lb: AABB = entry["box"]
		if _mark_part_skipped(String(mi.name)):
			continue
		if maxf(lb.size.x, maxf(lb.size.y, lb.size.z)) < 0.008:
			continue
		if lb.end.y < low_cut:
			continue
		mesh_entries.append(entry)
	# The quad kit is split into hundreds of 8-24 triangle nodes; fetching
	# their arrays alone cost ~1.7 s.  Rank by height/size and keep the parts
	# that can actually form the visible top deck.
	if mesh_entries.size() > 48:
		mesh_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ba: AABB = a["box"]
			var bb: AABB = b["box"]
			var da: float = maxf(ba.size.x, maxf(ba.size.y, ba.size.z))
			var db: float = maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
			return ba.end.y + da * 0.15 > bb.end.y + db * 0.15)
		mesh_entries = mesh_entries.slice(0, 48)
	for entry in mesh_entries:
		var mi: MeshInstance3D = entry["mi"]
		var xf: Transform3D = entry["xf"]
		var mesh := mi.mesh
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			var is_solid := 1 if _mark_material_solid(mesh.surface_get_material(s)) else 0
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() >= 3:
				var indices: PackedInt32Array = idx
				var i := 0
				while i + 2 < indices.size():
					_append_mark_tri(xf, verts[indices[i]], verts[indices[i + 1]],
							verts[indices[i + 2]], ta, tb, tc, centers, normals,
							areas, solid, is_solid)
					i += 3
			else:
				var i := 0
				while i + 2 < verts.size():
					_append_mark_tri(xf, verts[i], verts[i + 1], verts[i + 2],
							ta, tb, tc, centers, normals, areas, solid, is_solid)
					i += 3
	var tris := {"a": ta, "b": tb, "c": tc, "center": centers,
			"normal": normals, "area": areas, "solid": solid}
	return {"tris": tris, "box": box}


func _mark_part_skipped(node_name: String) -> bool:
	var lname := node_name.to_lower()
	for part in _MARK_SKIP_PARTS:
		if lname.contains(part):
			return true
	return false


func _mark_material_solid(mat: Material) -> bool:
	if mat == null:
		return true
	var mat_name := String(mat.resource_name).to_lower()
	if mat_name.contains("glass") or mat_name.contains("canopy"):
		return false
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
		if bm.albedo_color.a < 0.90:
			return false
	return true


func _append_mark_tri(xf: Transform3D, va: Vector3, vb: Vector3, vc: Vector3,
		ta: PackedVector3Array, tb: PackedVector3Array, tc: PackedVector3Array,
		centers: PackedVector3Array, normals: PackedVector3Array,
		areas: PackedFloat32Array, solid: PackedByteArray, is_solid: int) -> void:
	var a := xf * va
	var b := xf * vb
	var c := xf * vc
	var cross := (b - a).cross(c - a)
	var area := cross.length() * 0.5
	if area < 0.000001:
		return
	ta.append(a)
	tb.append(b)
	tc.append(c)
	centers.append((a + b + c) / 3.0)
	normals.append(cross / (area * 2.0))
	areas.append(area)
	solid.append(is_solid)


## Pick a genuinely visible solid top surface.  Triangles are bucketed in a
## coarse XZ grid once; each cell keeps its highest solid top band.  Only the
## best few cells are verified with a real downward ray, which treats every
## mesh (including glass canopies) as an occluder.  This avoids the old
## 49 x all-triangles search that cost 1.5-3.5 s per model and could seat a
## flag on a deck hidden under a battery or canopy.
func _pick_mark_anchor(tris: Dictionary, box: AABB) -> Dictionary:
	var centers: PackedVector3Array = tris.get("center", PackedVector3Array())
	if centers.is_empty():
		return {}
	var normals: PackedVector3Array = tris["normal"]
	var areas: PackedFloat32Array = tris["area"]
	var solid: PackedByteArray = tris["solid"]
	var ta: PackedVector3Array = tris["a"]
	var tb: PackedVector3Array = tris["b"]
	var tc: PackedVector3Array = tris["c"]
	var size := box.size
	if size.x <= 0.0001 or size.z <= 0.0001:
		return {}
	var center := box.get_center()
	var span := maxf(size.x, size.z)
	var cell_size := clampf(span / 14.0, 0.008, 0.06)
	var nx := maxi(1, ceili(size.x / cell_size))
	var nz := maxi(1, ceili(size.z / cell_size))
	var origin := Vector2(box.position.x, box.position.z)
	var band := maxf(0.015, size.y * 0.10)
	var grid := {}
	for k in range(centers.size()):
		if solid[k] == 0:
			continue
		var n := normals[k]
		if absf(n.y) < 0.30:
			continue
		var c := centers[k]
		var gx := clampi(int(floor((c.x - origin.x) / cell_size)), 0, nx - 1)
		var gz := clampi(int(floor((c.z - origin.y) / cell_size)), 0, nz - 1)
		var key := gz * nx + gx
		var weighted := areas[k] * absf(n.y)
		var cell = grid.get(key)
		if cell == null:
			grid[key] = [c.y, weighted, k, areas[k]]
		else:
			if c.y > float(cell[0]) + band:
				cell[0] = c.y
				cell[1] = weighted
				cell[2] = k
				cell[3] = areas[k]
			elif absf(c.y - float(cell[0])) <= band:
				cell[1] = float(cell[1]) + weighted
				if areas[k] > float(cell[3]):
					cell[2] = k
					cell[3] = areas[k]
				cell[0] = maxf(float(cell[0]), c.y)
	var cands: Array = []
	for key in grid:
		var cell = grid[key]
		var k: int = cell[2]
		var p := centers[k]
		var dx := p.x - center.x
		var dz := p.z - center.z
		var radial := clampf(sqrt(dx * dx + dz * dz) / (span * 0.55 + 0.0001), 0.0, 1.0)
		var central := 1.0 - 0.50 * radial
		var hnorm := clampf((p.y - center.y) / (size.y * 0.5 + 0.0001), 0.0, 1.0)
		var height_bias := 0.70 + 0.30 * hnorm
		cands.append({"score": float(cell[1]) * central * height_bias, "point": p})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	var max_tries: int = mini(cands.size(), 10)
	for ci in range(max_tries):
		var p: Vector3 = cands[ci]["point"]
		var origin3 := Vector3(p.x, box.end.y + maxf(0.05, size.y * 0.20), p.z)
		var hit := _raycast_down(ta, tb, tc, normals, origin3)
		if hit.is_empty():
			continue
		var hi: int = hit["index"]
		if solid[hi] == 0:
			continue
		var hp: Vector3 = hit["point"]
		if absf(hp.y - p.y) > maxf(0.030, size.y * 0.22):
			continue
		var hn: Vector3 = hit["normal"]
		# A flat decal needs a flat seat.  The old 0.45 threshold let the
		# Пісун land on the 35-degree flank of its camera dome, where the
		# quad's edges visibly hover above the curved shell.  Airframe GLBs
		# mix winding orders, so judge the absolute slope and flip after.
		if absf(hn.y) < 0.88:
			continue
		if hn.y < 0.0:
			hn = -hn
		return {"point": hp, "normal": hn}
	return {}


func _raycast_down(ta: PackedVector3Array, tb: PackedVector3Array,
		tc: PackedVector3Array, normals: PackedVector3Array,
		origin: Vector3) -> Dictionary:
	var best_y := -INF
	var best: Dictionary = {}
	for i in range(ta.size()):
		var d := _ray_tri(origin, Vector3.DOWN, ta[i], tb[i], tc[i])
		if d < 0.0:
			continue
		var p := Vector3(origin.x, origin.y - d, origin.z)
		if p.y > best_y:
			best_y = p.y
			best = {"point": p, "normal": normals[i], "index": i}
	return best


func _ray_tri(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 0.0000001:
		return -1.0
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(p) * inv
	if u < -0.001 or u > 1.001:
		return -1.0
	var q := tv.cross(e1)
	var v := d.dot(q) * inv
	if v < -0.001 or u + v > 1.001:
		return -1.0
	var t := e2.dot(q) * inv
	return t if t > 0.0001 else -1.0


func _model_relative_xf(model: Node3D, node: Node3D) -> Transform3D:
	if model.is_inside_tree() and node.is_inside_tree():
		return model.global_transform.affine_inverse() * node.global_transform
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != model:
		var n3 := cur as Node3D
		if n3 == null:
			break
		xf = n3.transform * xf
		cur = cur.get_parent()
	return xf


static func _make_ukraine_texture() -> ImageTexture:
	var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	for y in range(40):
		for x in range(64):
			var col := Color(0.02, 0.10, 0.42) if y < 20 \
					else Color(0.92, 0.73, 0.05)
			img.set_pixel(x, y, col)
	# simple white trident silhouette
	for y in range(9, 32):
		for x in range(30, 34):
			img.set_pixel(x, y, Color(0.95, 0.95, 0.90))
	for x in range(20, 45):
		for y in range(18, 22):
			img.set_pixel(x, y, Color(0.95, 0.95, 0.90))
	for x in range(21, 25):
		for y in range(10, 19):
			img.set_pixel(x, y, Color(0.95, 0.95, 0.90))
	for x in range(39, 43):
		for y in range(10, 19):
			img.set_pixel(x, y, Color(0.95, 0.95, 0.90))
	return ImageTexture.create_from_image(img)


## Animate propellers on a drone model based on motor RPMs or idle spin
func animate_propellers(model: Node3D, delta: float, rpms: Array = []) -> void:
	DronePropellerSystem.animate_propellers(model, delta, rpms)


func _combined_aabb(node: Node3D) -> AABB:
	return model_bounds(node)


## Combined bounds of the mesh instances, ignoring huge outlier meshes (some
## downloaded GLBs ship with a big ground/backdrop object).
func model_bounds(root: Node3D) -> AABB:
	var boxes: Array = []
	var dims: Array = []
	for v in _visuals(root):
		var vi := v as VisualInstance3D
		var xf := vi.global_transform if vi.is_inside_tree() else vi.transform
		var b: AABB = xf * vi.get_aabb()
		boxes.append(b)
		dims.append(maxf(b.size.x, maxf(b.size.y, b.size.z)))
	if boxes.is_empty():
		return AABB()
	var sorted := dims.duplicate()
	sorted.sort()
	var median: float = float(sorted[sorted.size() / 2])
	var limit := maxf(median * 6.0, 0.0001)
	var result := AABB()
	var first := true
	for b in boxes:
		var d := maxf(b.size.x, maxf(b.size.y, b.size.z))
		if d > limit:
			continue
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result


## True combined bounds of every visual, no outlier filtering.
func model_bounds_full(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for v in _visuals(root):
		var vi := v as VisualInstance3D
		var xf := vi.global_transform if vi.is_inside_tree() else vi.transform
		var b: AABB = xf * vi.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result


func _visuals(node: Node) -> Array:
	var out := []
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		out += _visuals(child)
	return out
