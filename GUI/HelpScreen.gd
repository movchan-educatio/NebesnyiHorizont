## Controls and game-modes reference.
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"

signal back
var embedded := false

const CONTROLS_TEXT := """[b]ПОЛІТ ТА КЕРУВАННЯ[/b]
SPACE — увімкнути / вимкнути двигуни
W / S — газ (лівий стік ↕)
A / D — рискання (лівий стік ↔)
← / → — крен (правий стік)
↑ / ↓ — тангаж (правий стік)
C / V — нахил FPV-камери
ESC — пауза
R / LB — респавн; у школі T / B — повторити модуль

[b]БОЙОВІ ФУНКЦІЇ[/b]
G / X — скинути бомбу (дрони зі скидом)
F / Y — активувати БЧ / ручна детонація контактної БЧ
T — тепловізор (бомбер)
F3 — якість графіки
F6 — FPV-ефекти (за бажанням)
F4 — день / ніч / тепловізор
F5 — погода
F2 / Start — довідка школи (у навчанні)

[b]ПУЛЬТИ ТА ГЕЙМПАДИ[/b]
Лівий стік — газ і рискання; правий стік — тангаж і крен
RS — двигуни · X — скид · Y — БЧ
LB — респавн · Back — пауза · Start — довідка
A — цикл режимів · LS — утримання висоти
D-pad: ↑ горизонт · → кут · ↓ швидкість · ← позиція
Підтримка RC-пультів (Mode 2, ExpressLRS Wi-Fi / USB)
та стандартних геймпадів з автокалібруванням осей.
У меню «Керування» рядок «Активація БЧ / миттєва детонація»
призначається кнопкою «Авто» на будь-який тумблер пульта.

[b]ПІДКЛЮЧЕННЯ ELRS Wi-Fi / USB[/b]
• Wi-Fi: увімкніть на пульті ExpressLRS → WiFi Connectivity → Enable WiFi, підключіть пристрій до Wi-Fi «ExpressLRS TX» (пароль: expresslrs), порт UDP 11000 (10.0.0.1).
• Канали AETR: CH1 Крен, CH2 Тангаж, CH3 Газ, CH4 Рискання, CH5 Армування, CH6 Режим, CH7 Скид, CH8 Детонація."""

const TOUCH_TEXT := """[b]СЕНСОРНИЙ ЕКРАН[/b]
Лівий стік — газ / рискання; правий — тангаж / крен
АРМ — увімкнути / вимкнути двигуни
РЕЖИМ — поточний режим (ANGLE, ACRO, SPEED…)
СКИД — кругла кнопка праворуч від лівого стіка
ВІДЕО — цикл FPV-фільтра: аналог / цифровий / тепловізор
МЕНЮ — пауза; РЕСЕТ — респавн
ВВІД: СЕНСОР / ПУЛЬТ — перемикання джерела
Екран повертається за пристроєм; інтерфейс враховує виріз камери.

[b]ПУЛЬТИ[/b]
RC-передавачі Mode 2 (ELRS Wi-Fi / USB) та стандартні геймпади.

[b]ПІДКЛЮЧЕННЯ ПУЛЬТА ЧЕРЕЗ ELRS Wi-Fi (ПОКРОКОВО)[/b]
1. На RC-пульті відкрийте меню системних скриптів → [b]ExpressLRS → WiFi Connectivity → Enable WiFi[/b].
2. На iPhone / iPad відкрийте [b]Налаштування → Wi-Fi[/b] та підключіться до мережі [b]ExpressLRS TX[/b] (стандартний пароль: [b]expresslrs[/b]).
3. Переконайтеся, що для гри дозволено доступ до [b]Локальної мережі[/b] (iOS Налаштування → Небесний горизонт → Локальна мережа).
4. У грі відкрийте [b]Керування / Пульт та ELRS[/b] — гра автоматично прийматиме телеметрію CRSF по UDP (порт 11000, IP 10.0.0.1).
5. Стандартна розкладка каналів AETR (Mode 2):
   • CH1: Крен (Roll) · CH2: Тангаж (Pitch) · CH3: Газ (Throttle) · CH4: Рискання (Yaw)
   • CH5: Армування двигунів (ARM) · CH6: Режими польоту · CH7: Скид вантажу · CH8: Детонація БЧ"""

const TOUCH_TEXT_EN := """[b]TOUCH SCREEN[/b]
Left stick — throttle / yaw; right stick — pitch / roll
ARM — arm / disarm the motors
MODE — current flight mode (ANGLE, ACRO, SPEED…)
DROP — round button to the right of the left stick
VIDEO — cycles the FPV filter: analog / digital / thermal
MENU — pause; RESET — respawn
INPUT: TOUCH / RADIO — switch control source
The screen rotates with the device and respects the camera notch.

[b]CONTROLLERS[/b]
RC transmitters Mode 2 (ELRS Wi-Fi / USB) and standard gamepads.

[b]ELRS Wi-Fi TRANSMITTER SETUP (STEP BY STEP)[/b]
1. On your RC transmitter, open system tools → [b]ExpressLRS → WiFi Connectivity → Enable WiFi[/b].
2. On your iPhone / iPad, open [b]Settings → Wi-Fi[/b] and join the [b]ExpressLRS TX[/b] network (default password: [b]expresslrs[/b]).
3. Ensure [b]Local Network[/b] permission is enabled for the app in iOS Settings.
4. Open [b]Controls / Radio & ELRS[/b] in the game — CRSF channels stream automatically over UDP (port 11000, IP 10.0.0.1).
5. Standard AETR (Mode 2) channel mapping:
   • CH1: Roll · CH2: Pitch · CH3: Throttle · CH4: Yaw
   • CH5: Arm Motors · CH6: Flight Modes · CH7: Payload Drop · CH8: Warhead Detonate"""

const MODES_TEXT := """[b]БОЙОВІ МІСІЇ (КАМПАНІЯ 1–4)[/b]
• TAC-01: Піхота (виявлення та ліквідація живої сили)
• TAC-02: Танк і БТР (знищення броньованої колони)
• TAC-03: Гелікоптер (перехоплення низьковисотної авіації)
• TAC-04: БПЛА «Дельта-136» (перехоплення швидкісного ударного БПЛА)
Місії відкриваються послідовно: наступна — лише після завершення
попередньої. Брифінг → виліт → дебрифінг ідуть безперервно, а кнопка
«ПРОДОВЖИТИ КАМПАНІЮ» веде до першої незавершеної місії.

[b]ФАЗИ БОЙОВОГО ВИЛЬОТУ[/b]
1/3 РОЗВІДКА — підлетіти до зони й утримати 3 секунди.
2/3 УДАР — знищити всі цілі, позначені маркерами.
3/3 ВИХІД — повернутися в зону евакуації та утримати 3 секунди.
Маркер фази показує відстань і відсоток утримання зони.

[b]ЕФЕКТИ ВЛУЧАНЬ[/b]
Кожен тип цілі має власну Blender-сцену влучання: танк, БМП, БТР,
вантажівка, ЗРК, гелікоптер, «Дельта-136» і піхота. Додатково працюють
іскри, пил, дим і спалах, тому влучання читається навіть у русі.

[b]ШКОЛА ПІЛОТА (10 МОДУЛІВ)[/b]
1. Увімкнення та вимкнення двигунів на землі
2. Газ і висіння на 2–4 м
3. Правий стік: тангаж, крен і повернення в центр
4. Рискання на 70° і повернення на початковий курс
5. Перший політ крізь широкі ворота
6. Слалом: два зміщені ворота
7. Висота: низькі та високі ворота
8. Точний проліт крізь вікно 3.6 × 3.2 м
9. Гальмування у позначеній зоні
10. М'яка посадка та вимкнення двигунів
Асистент підказує перегазовку, втрату горизонту, VRS і бічний знос.
Пульт: B — повторити модуль, Start — довідка.

[b]ФРІСТАЙЛ / ВІЛЬНИЙ ПОЛІТ[/b]
4 карти без супротивника: Умань (Софіївка), Промзона + Плавні, Аеропорт. Практика стіків, 24 неонових воріт, Привид і запис DVR.

[b]ЗЛІТ[/b]
Бойові БПЛА стартують з тактичної пускової бочки.

[b]ВИБІР ДРОНА[/b]
Стрілки ◄ / ►, ангар або миша. Один клік мишею перемикає рівно на один борт.

[b]ПОЛІТ НА ЧАС[/b]
Траса з неонових воріт із хронометражем.

[b]РЕЙТИ ТА ФІЗИКА[/b]
ESC → «Параметри борту та рейти»: кут FPV-камери, маса акумулятора, FPV Rates (RC / Super / Expo)."""


const CONTROLS_TEXT_EN := """[b]FLIGHT & CONTROLS[/b]
SPACE — start / stop engines
W / S — throttle (left stick ↕)
A / D — yaw (left stick ↔)
← / → — roll (right stick)
↑ / ↓ — pitch (right stick)
C / V — FPV camera tilt
ESC — pause
R / LB — respawn; in school T / B — retry module

[b]COMBAT ACTIONS[/b]
G / X — release bomb (drones with a drop payload)
F / Y — arm / trigger the contact payload
T — thermal camera (bomber)
F3 — graphics quality
F6 — FPV downlink effects (optional)
F4 — day / night / thermal vision
F5 — weather
F2 / Start — flight-school help

[b]CONTROLLERS[/b]
Left stick — throttle and yaw; right stick — pitch and roll
RS — engines · X — release · Y — warhead
LB — respawn · Back — pause · Start — help
A — cycle flight modes · LS — altitude hold
D-pad: ↑ horizon · → angle · ↓ speed · ← position
RC transmitters (Mode 2, ExpressLRS Wi-Fi / USB) and standard
gamepads are supported with axis calibration.
In Controls, the row “Activate warhead / instant detonation”
can be bound to any transmitter switch with the “Auto” button.

[b]ELRS Wi-Fi / USB SETUP[/b]
• Wi-Fi: enable ExpressLRS → WiFi Connectivity → Enable WiFi on your radio, join Wi-Fi “ExpressLRS TX” (password: expresslrs), UDP port 11000 (10.0.0.1).
• Channels (AETR): CH1 Roll, CH2 Pitch, CH3 Throttle, CH4 Yaw, CH5 Arm, CH6 Mode, CH7 Drop, CH8 Detonate."""

const MODES_TEXT_EN := """[b]COMBAT CAMPAIGN 1–4[/b]
• TAC-01: infantry
• TAC-02: tank and APC
• TAC-03: helicopter
• TAC-04: Delta-136 UAV
Missions unlock sequentially. The next sortie opens only after the previous
one is completed. Briefing → mission → debriefing flows continuously, and
“CONTINUE CAMPAIGN” jumps to the first unfinished mission.

[b]MISSION PHASES[/b]
1/3 RECON — reach the zone and hold it for 3 seconds.
2/3 STRIKE — destroy every primary target.
3/3 EXTRACT — return to the evacuation zone and hold it for 3 seconds.
The phase marker shows distance and hold percentage.

[b]HIT EFFECTS[/b]
Every target class has its own authored Blender hit scene: tank, BMP, APC,
truck, SAM, helicopter, Delta-136 and infantry. Additive sparks, dust, smoke
and a flash layer make the impact readable even at speed.

[b]FLIGHT SCHOOL (10 MODULES)[/b]
1. Start and stop the engines on the ground
2. Throttle and a steady 2–4 m hover
3. Right stick: pitch, roll and centring
4. Yaw 70° and return to the start heading
5. First flight through a wide gate
6. Slalom through two offset gates
7. Altitude: low gate, then high gate
8. Precision pass through a 3.6 × 3.2 m window
9. Brake inside the marked zone
10. Soft landing and disarm
The coach warns about throttle spikes, lost horizon, VRS and side slip.
Gamepad: B — retry module, Start — help.

[b]FREE FLIGHT[/b]
Four maps without opponents: Uman (Sofiyivka), Industrial Zone + Wetlands and Airport. Practise sticks, 24 neon gates, Ghost lap and DVR replay.

[b]TAKEOFF[/b]
Combat drones launch from a field tube.

[b]AIRCRAFT SELECTION[/b]
◄ / ►, the Hangar or the mouse. One mouse click now moves exactly one aircraft.

[b]TIME TRIAL[/b]
Neon checkpoint course with a precise timer.

[b]RATES & PHYSICS[/b]
ESC → Aircraft & Rates: FPV camera tilt, battery mass, FPV rates (RC / Super / Expo)."""


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()
	MenuUI.localize_tree(self)


func _build() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var center := CenterContainer.new()
	MenuUI.full_rect(center)
	var viewport_size := get_viewport_rect().size
	if MenuUI.is_mobile_ui():
		var edges := MenuUI.mobile_edge_margins(viewport_size)
		center.offset_top = int(edges.y)
		center.offset_bottom = -int(edges.w)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_width := minf(980.0, viewport_size.x - 24.0)
	var column_width := maxf(250.0, (panel_width - 100.0) * 0.5)
	panel.custom_minimum_size = Vector2(panel_width, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	box.add_child(MenuUI.title("ДОВІДКА ТА КЕРУВАННЯ", 30))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col_left := VBoxContainer.new()
	col_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_left.add_theme_constant_override("separation", 10)
	col_left.add_child(MenuUI.section("РОЗКЛАДКА КЕРУВАННЯ", "ПІЛОТ"))
	var controls := RichTextLabel.new()
	controls.bbcode_enabled = true
	var controls_body := CONTROLS_TEXT_EN if MenuUI.is_english() else CONTROLS_TEXT
	if MenuUI.is_mobile_ui():
		# The phone help must not send the pilot to PC keyboard shortcuts.
		controls_body = TOUCH_TEXT_EN if MenuUI.is_english() else TOUCH_TEXT
	controls.text = controls_body
	controls.fit_content = true
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.custom_minimum_size = Vector2(column_width, 0)
	controls.add_theme_font_size_override("normal_font_size", 16)
	col_left.add_child(controls)
	columns.add_child(col_left)

	var col_right := VBoxContainer.new()
	col_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_right.add_theme_constant_override("separation", 10)
	col_right.add_child(MenuUI.section("РЕЖИМИ ВИЛЬОТУ ТА ПОЛІГОНИ", "РЕЖИМ"))
	var modes := RichTextLabel.new()
	modes.bbcode_enabled = true
	modes.text = MODES_TEXT_EN if MenuUI.is_english() else MODES_TEXT
	modes.fit_content = true
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.custom_minimum_size = Vector2(column_width, 0)
	modes.add_theme_font_size_override("normal_font_size", 16)
	col_right.add_child(modes)
	columns.add_child(col_right)

	var scroll := ScrollContainer.new()
	var help_scroll_height := viewport_size.y - (260.0 if MenuUI.is_mobile_ui() else 170.0)
	scroll.custom_minimum_size = Vector2(0, maxf(150.0, minf(480.0, help_scroll_height)))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(columns)
	box.add_child(scroll)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 14)

	var tut_btn := Button.new()
	tut_btn.text = "🎓  РОЗПОЧАТИ КУРС ПІЛОТА"
	tut_btn.custom_minimum_size = Vector2(0, 48)
	tut_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if MenuUI.is_mobile_ui():
		tut_btn.add_theme_stylebox_override("normal", MenuUI._style(Color(0.62, 0.74, 0.55, 1.0), MenuUI.FPV_GREEN, 2, 12, 16, 10, 4))
		tut_btn.add_theme_stylebox_override("hover", MenuUI._style(Color(0.70, 0.82, 0.62, 1.0), MenuUI.FPV_GREEN, 2, 12, 16, 10, 4))
		tut_btn.add_theme_stylebox_override("focus", MenuUI._style(Color(0.70, 0.82, 0.62, 1.0), MenuUI.FPV_GREEN, 2, 12, 16, 10, 4))
		tut_btn.add_theme_stylebox_override("pressed", MenuUI._style(Color(0.10, 0.22, 0.15, 1.0), MenuUI.FPV_GREEN, 2, 12, 16, 10, 4))
		tut_btn.add_theme_font_size_override("font_size", 18)
		tut_btn.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07))
		tut_btn.add_theme_color_override("font_hover_color", Color(0.06, 0.09, 0.07))
		tut_btn.add_theme_color_override("font_focus_color", Color(0.06, 0.09, 0.07))
		tut_btn.add_theme_color_override("font_pressed_color", MenuUI.FPV_TEXT)
	else:
		tut_btn.add_theme_stylebox_override("normal", MenuUI._style(MenuUI.BUTTON_ACTIVE, MenuUI.ACCENT, 2, 1, 14, 8, 4))
		tut_btn.add_theme_stylebox_override("hover", MenuUI._style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.ACCENT, 2, 1, 14, 8, 4))
		# The button is focused on entry; without a matching focus style the theme's
		# white focus box hid the white label completely.
		tut_btn.add_theme_stylebox_override("focus", MenuUI._style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.ACCENT, 2, 1, 14, 8, 4))
		tut_btn.add_theme_stylebox_override("pressed", MenuUI._style(MenuUI.BUTTON_ACTIVE.darkened(0.08), MenuUI.ACCENT, 2, 1, 14, 8, 4))
		tut_btn.add_theme_font_size_override("font_size", 16)
		tut_btn.add_theme_color_override("font_color", Color.WHITE)
		tut_btn.add_theme_color_override("font_hover_color", Color.WHITE)
		tut_btn.add_theme_color_override("font_focus_color", Color.WHITE)
	tut_btn.pressed.connect(_launch_tutorial)
	action_row.add_child(tut_btn)

	var back_btn := MenuUI.button("←  НАЗАД", 38)
	back_btn.custom_minimum_size = Vector2(200, 48)
	back_btn.pressed.connect(_go_back)
	action_row.add_child(back_btn)

	box.add_child(action_row)
	tut_btn.grab_focus()


func _launch_tutorial() -> void:
	Global.play_mode = Global.PlayMode.TUTORIAL
	# Same persistent loading card as the main menu, including the authored
	# battlefield photograph, so the tutorial does not flash a black screen.
	var overlay: Dictionary = LoadingScreen.build(Global.PlayMode.TUTORIAL, 0,
			"promzona_plavni", Global.get_difficulty_name(), false)
	get_tree().root.add_child.call_deferred(overlay["layer"])
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://sceneries/PromzonaPlavniLevel.tscn")


func _go_back() -> void:
	if embedded:
		back.emit()
		return
	if OS.has_feature("mobile"):
		get_tree().change_scene_to_file("res://GUI/mobile/MobileMenu.tscn")
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_back()
