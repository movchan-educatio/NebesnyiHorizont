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


const PRESETS := [
	{
		"name": "«ГОЛКА»",
		"tag": "ФРІСТАЙЛ 5\"",
		"desc": "Легкий фрістайл, миттєвий відгук",
		"info": "Легка каркасна X-рама з відкритими пропелерами та високою «грибковою» антеною на задній частині. Мінімальна злітна вага й жвава реакція на стіки — для тренувань, фрістайлу та точного калібрування пульта.",
		"dry": 0.38, "batt": 0.22, "kv": 2500, "torque": 1300.0, "rpm": 35000.0,
		"prop_d": 5.1, "prop_p": 4.9, "blades": 3, "rate": 900, "motor_size": 2207,
		"payload": 0, "payload_mass": 0.0, "combat": false, "has_drop": false,
		"twr": 8.5,
		"cog_offset": Vector3(0.0, 0.0, 0.0),
		"dimensions": Vector3(0.22, 0.06, 0.22),
		"drag_area": Vector3(0.012, 0.014, 0.006),
		"model": "res://Assets/Drones/ua_norm/holka.glb",
		"model_size": 0.260, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, -0.012, -0.068), "fpv_cam_pitch": -6.0,
	},
	{
		"name": "PinaPipe",
		"tag": "ФРІСТАЙЛ 5\"",
		"desc": "Класична 5\" рама, відкриті пропелери",
		"info": "Готовий FPV-квадрокоптер: рама з відкритими пропелерами та верхнім розташуванням акумулятора й навантаження. Легка модель на ~28 тис. трикутників — мінімальне навантаження на систему.",
		"dry": 0.42, "batt": 0.24, "kv": 1950, "torque": 1250.0, "rpm": 30000.0,
		"prop_d": 5.1, "prop_p": 4.3, "blades": 3, "rate": 667, "motor_size": 2207,
		"payload": 0, "payload_mass": 0.0, "combat": false, "has_drop": false,
		"twr": 5.5,
		"cog_offset": Vector3(0.0, 0.006, 0.0),
		"dimensions": Vector3(0.22, 0.07, 0.22),
		"drag_area": Vector3(0.013, 0.015, 0.007),
		"model": "res://Assets/Drones/ua_norm/pinapipe.glb",
		"model_size": 0.218, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.005, -0.024), "fpv_cam_pitch": -6.0,
	},
	{
		"name": "DJI AVATA 2",
		"tag": "КІНОДРОН 3\"",
		"desc": "Кінодрон із захистом пропелерів",
		"info": "Кінодрон для польотів у приміщеннях і плавних кадрів. Габарити 212 × 184 × 64 мм, захисні дуги, підвіс камери та фірмові помаранчеві акценти. Плавний і стабільний.",
		"dry": 0.26, "batt": 0.15, "kv": 1600, "torque": 700.0, "rpm": 34000.0,
		"prop_d": 3.2, "prop_p": 3.0, "blades": 3, "rate": 500, "motor_size": 1404,
		"payload": 0, "payload_mass": 0.0, "combat": false, "has_drop": false,
		"twr": 2.4,
		"cog_offset": Vector3(0.0, 0.002, 0.0),
		"dimensions": Vector3(0.18, 0.06, 0.18),
		"drag_area": Vector3(0.018, 0.020, 0.010),
		"model": "res://Assets/Drones/ua_norm/avata2.glb",
		"model_size": 0.212, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.011, -0.083), "fpv_cam_pitch": -4.0,
	},
	{
		"name": "«ПІСЮН» VTOL",
		"tag": "VTOL 7\"",
		"desc": "Вертикальний зліт, ударний камікадзе",
		"info": "Ударний FPV-камікадзе на витягнутій карбоновій деці з подовженим центральним відсіком. Злітає вертикально й переходить у горизонтальний політ; батарея 6S і швидкі безщіткові мотори. Центр ваги зміщується разом із боєкомплектом.",
		"dry": 0.75, "batt": 0.40, "kv": 1300, "torque": 2200.0, "rpm": 27000.0,
		"prop_d": 7.0, "prop_p": 5.0, "blades": 2, "rate": 550, "motor_size": 2806,
		"payload": 2, "payload_mass": 0.65, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 3.4,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.065, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.040, -0.020),
		"dimensions": Vector3(0.32, 0.12, 0.38),
		"drag_area": Vector3(0.025, 0.028, 0.015),
		"model": "res://Assets/Drones/ua_norm/pisun_vtol.glb",
		"model_size": 0.450, "model_fit": false,
		"model_pitch": 0.0,
		"fpv_cam_pos": Vector3(0.0, 0.088, -0.060), "fpv_cam_pitch": -12.0,
	},
	{
		"name": "«ПЕЛЕНГ»",
		"tag": "РОЗВІДКА 5\"",
		"desc": "Розвідник із панельною антеною",
		"info": "Розвідувальний FPV-квадрокоптер із посиленим комплексом зв'язку: спрямована панельна антена та кругова антена на задній виносній штанзі. Виносні елементи створюють додаткову парусність на швидкості — тренування точного пілотування.",
		"dry": 0.46, "batt": 0.26, "kv": 1800, "torque": 1200.0, "rpm": 35000.0,
		"prop_d": 5.1, "prop_p": 4.3, "blades": 2, "rate": 700, "motor_size": 2207,
		"payload": 0, "payload_mass": 0.16, "combat": false, "has_drop": false,
		"twr": 4.5,
		"cog_offset": Vector3(0.0, 0.015, 0.025),
		"dimensions": Vector3(0.24, 0.10, 0.26),
		"drag_area": Vector3(0.020, 0.022, 0.012),
		"model": "res://Assets/Drones/ua_norm/peleng.glb",
		"model_size": 0.300, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.014, -0.072), "fpv_cam_pitch": -6.0,
	},
	{
		"name": "«ГРІМ-7»",
		"tag": "УДАРНИЙ 8–10\"",
		"desc": "Важкий ударний дальньої дії",
		"info": "Важкий квадрокоптер-камікадзе дальньої дії, рама 8–10 дюймів. Потужна батарея на верхній деці та видовжений боєприпас із хвостовим оперенням під днищем зміщують центр мас: дрон інертний у віражах і потребує точного розрахунку на заході на ціль.",
		"dry": 0.90, "batt": 0.50, "kv": 1350, "torque": 2800.0, "rpm": 23000.0,
		"prop_d": 8.0, "prop_p": 4.5, "blades": 3, "rate": 600, "motor_size": 2808,
		"payload": 3, "payload_mass": 1.30, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 3.5,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.065, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.055, -0.015),
		"dimensions": Vector3(0.36, 0.14, 0.36),
		"drag_area": Vector3(0.032, 0.035, 0.020),
		"model": "res://Assets/Drones/ua_norm/grim7.glb",
		"model_size": 0.391, "model_fit": false,
		"fpv_cam_pos": Vector3(-0.0146, 0.007, -0.095), "fpv_cam_pitch": -14.0,
	},
	{
		"name": "«ГРІМ-7М»",
		"tag": "УДАРНИЙ + СКИД",
		"desc": "Ударний із системою скидання",
		"info": "Модифікована повна комплектація: велика акумуляторна збірка зверху з ременем, видимий силовід і XT60, виносна антена VTX та нижня захисна дуга-лижа. Система скидання й важка бойова частина під рамою.",
		"dry": 0.88, "batt": 0.48, "kv": 1400, "torque": 2600.0, "rpm": 20500.0,
		"prop_d": 8.0, "prop_p": 4.3, "blades": 3, "rate": 620, "motor_size": 2808,
		"payload": 4, "payload_mass": 0.80, "combat": true, "has_drop": true,
		"drop_name": "2x ВОГ-17 (800г)",
		"twr": 3.5,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.065, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.048, 0.0),
		"dimensions": Vector3(0.36, 0.14, 0.36),
		"drag_area": Vector3(0.030, 0.032, 0.018),
		"model": "res://Assets/Drones/ua_norm/grim7m.glb",
		"model_size": 0.420, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.002, -0.120), "fpv_cam_pitch": -14.0,
	},
	{
		"name": "«СТРІЛА-8»",
		"tag": "КАМІКАДЗЕ",
		"desc": "Важкий камікадзе з виносним підвісом",
		"info": "Важкий ударний дрон із унікальною системою підвісу та детонації. Під днищем — бойовий елемент видовженої форми з детонаційним шнуром-петлею попереду, зверху вертикально орієнтований акумулятор. Високий момент інерції по вертикальній осі.",
		"dry": 1.00, "batt": 0.60, "kv": 1100, "torque": 4200.0, "rpm": 23500.0,
		"prop_d": 8.5, "prop_p": 4.6, "blades": 3, "rate": 580, "motor_size": 3115,
		"payload": 4, "payload_mass": 1.40, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 4.2,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.065, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.060, -0.025),
		"dimensions": Vector3(0.38, 0.15, 0.38),
		"drag_area": Vector3(0.034, 0.038, 0.022),
		"model": "res://Assets/Drones/ua_norm/strila8.glb",
		"model_size": 0.376, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.004, -0.053), "fpv_cam_pitch": -10.0,
	},
	{
		"name": "«FALCON-X» DIGITAL",
		"tag": "ЦИФРОВИЙ FPV",
		"desc": "Цифровий швидкісний FPV, обтічний фюзеляж",
		"info": "Швидкісний цифровий FPV-дрон з аеродинамічним обтічним фюзеляжем. Розгін 0–100 км/год за 2.0 секунди, максимальна швидкість 140 км/год (39 м/с). Політна вага 795 г створює стабільну інерцію на віражах, а низький опір повітря забезпечує стрімкий політ.",
		"dry": 0.50, "batt": 0.295, "kv": 2000, "torque": 1800.0, "rpm": 28000.0,
		"prop_d": 5.1, "prop_p": 4.8, "blades": 4, "rate": 650, "motor_size": 2207,
		"payload": 0, "payload_mass": 0.0, "combat": false, "has_drop": false,
		"twr": 4.9,
		"cog_offset": Vector3(0.0, 0.005, 0.0),
		"dimensions": Vector3(0.24, 0.12, 0.24),
		"drag_area": Vector3(0.010, 0.012, 0.005),
		"model": "res://Assets/Drones/ua_norm/falcon_x.glb",
		"model_size": 0.240, "model_fit": false, "model_yaw": PI,
		"fpv_cam_pos": Vector3(0.0, 0.024, -0.068), "fpv_cam_pitch": -8.0,
	},
	{
		"name": "«КВАД-5»",
		"tag": "ФРІСТАЙЛ 5\"",
		"desc": "Готовий квадрокоптер на карбоновій X-рамі 225 мм",
		"info": "Готовий 5-дюймовий FPV-квадрокоптер на посиленій карбоновій рамі Mark4. Збалансований центр ваги, верхнє розташування LiPo 6S, миттєвий відгук на стіки та тяга 6.5:1 для фрістайлу й тренувальних місій.",
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
		"name": "USV «МАГУРА-Х»",
		"tag": "МОРСЬКИЙ ДРОН",
		"desc": "Швидкісний морський ударний дрон-камікадзе",
		"info": "Швидкісний маневрений безпілотний катер з глісерним корпусом, призначений для ураження ворожих надводних цілей у відкритому морі та прибережній зоні. Водометний рушій, швидкість до 45–50 вузлів (85 км/г), низький профіль радіолокаційної помітності та потужна 320-кг бойова частина.",
		"dry": 680.0, "batt": 320.0, "kv": 1200, "torque": 8500.0, "rpm": 6000.0,
		"prop_d": 0.0, "prop_p": 0.0, "blades": 0, "rate": 350, "motor_size": 5010,
		"payload": 1, "payload_mass": 320.0, "combat": true, "has_drop": false,
		"is_naval": true,
		"twr": 3.8,
		"cog_offset": Vector3(0.0, -0.15, -0.2),
		"dimensions": Vector3(1.60, 1.04, 5.50),
		"drag_area": Vector3(0.18, 0.45, 0.08),
		"model": "res://Assets/Drones/ua_norm/magura_x.glb",
		"model_size": 5.50, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.70, -0.15), "fpv_cam_pitch": -3.0,
	},
	{
		"name": "Військовий дрон (Камікадзе / Скид)",
		"tag": "ВІЙСЬКОВИЙ БПЛА 8–10\"",
		"desc": "Важкий ударний дрон із бойовою частиною",
		"info": "Великий камікадзе або скидувач 8–10 дюймів із важкою бойовою частиною під днищем. Збільшена маса та інерція, центр-mass зміщений вниз і вперед, низьке співвідношення тяги до ваги та значна парусність бойового комплекту.",
		"dry": 1.4, "batt": 0.8, "kv": 1100, "torque": 5500.0, "rpm": 18000.0,
		"prop_d": 10.0, "prop_p": 5.5, "blades": 3, "rate": 550, "motor_size": 3115,
		"payload": 1, "payload_mass": 2.1, "combat": true, "has_drop": false,
		"kamikaze": true,
		"twr": 2.8,
		"battery_chemistry": 1, "battery_mah": 6000.0,
		"battery_resistance": 0.045, "battery_max_current": 90.0,
		"cog_offset": Vector3(0.0, -0.100, -0.050),
		"dimensions": Vector3(0.45, 0.18, 0.45),
		"drag_area": Vector3(0.050, 0.060, 0.035),
		"model": "res://Assets/Drones/ua_norm/strila8.glb",
		"model_size": 0.450, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.004, -0.090), "fpv_cam_pitch": -14.0,
	},
	{
		"name": "«БАБА ЯГА»",
		"name_en": "BABA YAGA",
		"tag": "ВАЖКИЙ БОМБЕР 6×",
		"desc": "Нічний бомбер: 6 моторів, 20 кг, Starlink",
		"info": "Важка шестимоторна платформа нічних операцій. Несе до 20 кг: 82-мм і 120-мм мінометні міни або ТМ-62. Два тепловізійні канали, захищені GNSS-антени та супутниковий термінал Starlink зберігають зв'язок в умовах РЕБ. З повним навантаженням летить близько 40 км/год, після скиду — до 80 км/год. Скид з висоти 100–400 м, бомбовий приціл з поправкою на вітер.",
		"dry": 26.0, "batt": 12.0, "kv": 120, "torque": 12000.0, "rpm": 5600.0,
		"prop_d": 28.0, "prop_p": 8.0, "blades": 3, "rate": 240, "motor_size": 8318,
		"payload": 4, "payload_mass": 12.8, "combat": true, "has_drop": true,
		"drop_name": "4× 82-мм міни",
		"heavy_bomber": true, "fpv_hide_model": true,
		"max_speed_loaded": 11.11, "max_speed_empty": 22.22,
		"twr": 2.25,
		"battery_chemistry": 1, "battery_mah": 30000.0,
		"battery_resistance": 0.035, "battery_max_current": 180.0,
		"cog_offset": Vector3(0.0, -0.20, 0.0),
		"dimensions": Vector3(2.80, 0.95, 1.55),
		"drag_area": Vector3(0.28, 0.58, 0.40),
		"model": "res://Assets/Drones/ua_norm/baba_yaga.glb",
		"model_size": 2.80, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.16, -0.62), "fpv_cam_pitch": -18.0,
		"bomb_cam_pos": Vector3(0.0, 0.82, 0.10), "bomb_cam_pitch": -78.0,
	},
	{
		"name": "«ЛЕЛЕКА-100»",
		"name_en": "LELEKA-100",
		"tag": "РОЗВІДНИК 2 м",
		"desc": "Оперативно-тактичний БАК, день/ніч",
		"info": "Український розвідувальний БАК оперативно-тактичного рівня: високоплан із двома хвостовими балками, штовхаючим гвинтом, гіростабілізованою денною/тепловізійною оптикою, захищеними каналами зв’язку та GNSS. Радіус до 50 км, маршрут до 100 км, до 2,5 годин у повітрі, крейсерська швидкість 60–70 км/год, стеля 1500 м.",
		"dry": 4.6, "batt": 1.2, "kv": 380, "torque": 2200.0, "rpm": 7000.0,
		"prop_d": 14.0, "prop_p": 8.0, "blades": 2, "rate": 260, "motor_size": 2814,
		"payload": 0, "payload_mass": 0.0, "combat": true, "has_drop": false,
		"fixed_wing": true, "max_speed_loaded": 18.1, "max_speed_empty": 22.2,
		"twr": 2.2,
		"battery_chemistry": 1, "battery_mah": 6000.0,
		"battery_resistance": 0.075, "battery_max_current": 80.0,
		"cog_offset": Vector3(0.0, -0.01, 0.0),
		"dimensions": Vector3(2.0, 0.55, 1.2),
		"drag_area": Vector3(0.050, 0.030, 0.035),
		"model": "res://Assets/Drones/ua_norm/leleka_100.glb",
		"model_size": 2.0, "model_fit": false,
		# Fixed-wing airframe: its 2 m wing/boom sits inside the FPV lens and
		# filled the whole screen.  Keep the lens clean; the model still flies
		# and is fully visible to external cameras/QA capture.
		"fpv_hide_model": true,
		"fpv_cam_pos": Vector3(0.0, 0.06, -0.56), "fpv_cam_pitch": -7.0,
	},
	{
		"name": "«ФУРІЯ» A1-СМ",
		"name_en": "FURIA A1-SM",
		"tag": "РОЗВІДНИК-КРИЛО 2 м",
		"desc": "Літаюче крило, 3–4 години в повітрі",
		"info": "Український комплекс «Атлон Авіа»: літаюче крило розмахом 2 м, довжина 0,9 м, злітна маса 5,5–6 кг, електродвигун із штовхаючим гвинтом, денні та нічні модулі, радіус до 50 км. Крейсерська 65 км/год, максимальна 130 км/год, до 3–4 годин польоту, стеля 2500 м.",
		"dry": 4.2, "batt": 1.3, "kv": 420, "torque": 2000.0, "rpm": 7200.0,
		"prop_d": 13.0, "prop_p": 7.0, "blades": 2, "rate": 250, "motor_size": 2812,
		"payload": 0, "payload_mass": 0.0, "combat": true, "has_drop": false,
		"fixed_wing": true, "max_speed_loaded": 18.1, "max_speed_empty": 36.1,
		"twr": 2.3,
		"battery_chemistry": 1, "battery_mah": 7000.0,
		"battery_resistance": 0.070, "battery_max_current": 85.0,
		"cog_offset": Vector3(0.0, 0.0, 0.0),
		"dimensions": Vector3(2.0, 0.35, 0.9),
		"drag_area": Vector3(0.045, 0.025, 0.030),
		"model": "res://Assets/Drones/ua_norm/furia_a1sm.glb",
		"model_size": 2.0, "model_fit": false,
		"fpv_hide_model": true,
		"fpv_cam_pos": Vector3(0.0, 0.04, -0.42), "fpv_cam_pitch": -8.0,
	},
	{
		"name": "«ЧАКЛУН JET»",
		"name_en": "CHAKLUN JET",
		"tag": "РЕАКТИВНИЙ ПЕРЕХОПЛЮВАЧ",
		"desc": "320 км/год, перехоплення Shahed",
		"info": "Український реактивний дрон-перехоплювач для знищення ворожих БПЛА та тактичних повітряних цілей. Довжина 1,65 м, розмах 1,5 м, злітна маса 10,4 кг, бойова частина 1,6 кг. Крейсерська 220 км/год, максимальна 320 км/год, до 40–60 хвилин, стеля 6000 м, дальність до 30 км, катапультний запуск.",
		"dry": 8.8, "batt": 1.6, "kv": 0, "torque": 8000.0, "rpm": 15000.0,
		"prop_d": 14.0, "prop_p": 10.0, "blades": 4, "rate": 180, "motor_size": 5010,
		"payload": 1, "payload_mass": 1.6, "combat": true, "has_drop": false,
		"kamikaze": true, "fixed_wing": true, "is_jet": true, "interceptor": true,
		"fpv_hide_model": true,
		"max_speed_loaded": 61.1, "max_speed_empty": 88.9,
		"twr": 3.0,
		"battery_chemistry": 1, "battery_mah": 5000.0,
		"battery_resistance": 0.060, "battery_max_current": 100.0,
		"cog_offset": Vector3(0.0, -0.02, 0.0),
		"dimensions": Vector3(1.5, 0.4, 1.65),
		"drag_area": Vector3(0.030, 0.025, 0.022),
		"model": "res://Assets/Drones/ua_norm/chaklun_jet.glb",
		"model_size": 1.65, "model_fit": false,
		"fpv_cam_pos": Vector3(0.0, 0.06, -0.78), "fpv_cam_pitch": -5.0,
	},
]


func preset(index: int) -> Dictionary:
	if custom_presets.has(index):
		return custom_presets[index]
	return PRESETS[clampi(index, 0, PRESETS.size() - 1)]


## True when the preset is a combat airframe (armed, non-naval).
func is_combat(index: int) -> bool:
	var p := preset(index)
	return bool(p.get("combat", false)) and not bool(p.get("is_naval", false))


## First usable combat airframe, used as the fallback when a sport/recon drone
## is somehow selected for a combat sortie.
func first_combat_index() -> int:
	for i in range(PRESETS.size()):
		if is_combat(i):
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
			"model_builder_config": cfg,
			"is_builder_custom": true,
			"model": str(frame.get("mesh_path", "")),
			"model_size": float(frame.get("size_inch", 5.0)) * 0.045,
			"model_fit": false,
			"fpv_cam_pos": Vector3(0.0, 0.025, -0.075),
			"fpv_cam_pitch": -8.0
		}
		set_custom_preset(9, p)
		print("[DroneCatalog] Loaded custom builder drone into preset 9")


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
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	model.name = "DroneModel"
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
	if index < 13 or index > 15:
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
func _attach_ukraine_mark(model: Node3D, p: Dictionary, index: int) -> void:
	if model == null or bool(p.get("is_naval", false)):
		return
	# Only genuine Ukrainian airframes carry the marking.  Preset 2 is a DJI
	# Avata and preset 11 is the Shahed-136, so they stay clean.
	if index == 2 or index == 11:
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
