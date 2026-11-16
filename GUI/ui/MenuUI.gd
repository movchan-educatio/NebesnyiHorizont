## Shared helpers for the Ukrainian FPV menus: charcoal surfaces, clear paper-white
## buttons, and restrained sage, amber, and red selection accents.
class_name MenuUI
extends RefCounted

const FONT_PATH := "res://GUI/NotoSans-Regular.ttf"
const LocScript = preload("res://scripts/util/localization_manager.gd")

const EN_TEXT: Dictionary = {
	# Home and navigation
	"НЕБЕСНИЙ ГОРИЗОНТ": "HEAVENLY HORIZON",
	"БОЙОВИЙ ТАКТИЧНИЙ СИМУЛЯТОР FPV-ДРОНА": "TACTICAL FPV DRONE SIMULATOR",
	"ВХІД У ТАКТИЧНИЙ ТЕРМІНАЛ": "TACTICAL TERMINAL",
	"ВИХІД З СИСТЕМИ": "EXIT SIMULATOR",
	"Звук відео": "INTRO AUDIO",
	"ЗВУК ЗАСТАВКИ": "INTRO AUDIO",
	"TACTICAL TERMINAL": "TACTICAL TERMINAL",
	"DRONE BUILDER LAB": "DRONE BUILDER LAB",
	"FLIGHT OPERATIONS": "FLIGHT OPERATIONS",
	"SETTINGS": "SETTINGS",
	"Головне меню": "Main Menu",
	"Головна сторінка": "Home",
	"Ангар": "Fleet Hangar",
	"Калібрування": "Calibration",
	"Налаштування": "Settings",
	"Довідка": "Help",
	"Вихід": "Exit",
	"←  Головне меню": "←  Main Menu",
	"←  НАЗАД В МЕНЮ": "← BACK TO MENU",
	"←  НАЗАД": "← BACK",
	"←  ПОВЕРНУТИСЯ": "← BACK",
	"←  ПОВЕРНУТИСЯ НАЗАД": "← GO BACK",
	"✕  ВИЙТИ З СИМУЛЯТОРА": "✕  EXIT SIMULATOR",
	"⌂  ПОВЕРНУТИСЯ ДО ШТАБУ (МЕНЮ)": "⌂  RETURN TO HEADQUARTERS",
	"▶  ПРОДОВЖИТИ ПОЛІТ": "▶  RESUME FLIGHT",
	"⚙  НАЛАШТУВАННЯ ТА КЕРУВАННЯ": "⚙  SETTINGS & CONTROLS",
	"✈  ПАРАМЕТРИ БОРТУ ТА РЕЙТИ": "✈  AIRCRAFT & RATE SETTINGS",
	"ПОВЕРНУТИСЯ ДО ПАУЗИ": "RETURN TO PAUSE",
	"←   ПОВЕРНУТИСЯ ДО ПАУЗИ": "←   RETURN TO PAUSE",
	"Зараз обрано: %s": "Selected: %s",
	"Перегляд: %s. Натисніть «ОБРАТИ ЦЕЙ ДРОН».": "Previewing %s. Select this drone to confirm.",
	"ОБРАТИ ЦЕЙ ДРОН": "SELECT THIS DRONE",
	"ОБРАНО ✓": "SELECTED ✓",
	"ОБРАТИ": "SELECT",
	"ГЛЯНУ": "PREVIEW",
	"ОБРАНО": "SELECTED",
	"← НАЗАД В МЕНЮ": "← BACK TO MENU",
	"TACTICAL MENU": "TACTICAL MENU",
	"ПЕРЕГЛЯД БОРТУ  //  3D": "LIVE AIRCRAFT  //  3D INSPECTION",
	"СИСТЕМИ ПРАЦЮЮТЬ": "SYSTEMS ONLINE",
	"СИСТЕМИ: ГОТОВІ  ·  КАНАЛ КЕРУВАННЯ: АКТИВНИЙ  ·  ЗБІРКА 1.4.0": "SYSTEMS: READY  ·  CONTROL LINK: ACTIVE  ·  BUILD 1.4.0",
	"Підготовка до вильоту": "SORTIE SETUP",
	"ВИБІР ВИЛЬОТУ": "SORTIE SETUP",
	"Місія": "Mission",
	"Режим": "Mode",
	"Огляд вильоту": "Sortie overview",
	"Дрон": "Drone",
	"⚙ Налаштування": "⚙ Settings",
	"Вийти з гри": "Quit game",
	"Попередній дрон": "Previous drone",
	"Наступний дрон": "Next drone",
	"ПЕРЕТЯГНІТЬ, ЩОБ ОБЕРТАТИ · КОЛЕСО — МАСШТАБ": "DRAG TO ROTATE · SCROLL TO ZOOM",
	"Автообертання": "Auto-rotate",
	"Обертання призупинено": "Rotation paused",

	# Flight operations / main menu
	"Режими польоту": "Flight Modes",
	"Бойові завдання": "Combat Missions",
	"План вильоту": "Mission Plan",
	"Активний дрон": "Active Drone",
	"Складність:": "Difficulty:",
	"📋  Брифінг": "📋  BRIEFING",
	"📖 Довідка": "📖 Help",
	"✕  Вихід": "✕  Exit",
	"Бойові": "Combat",
	"Школа": "Flight School",
	"Вільний": "Free Flight",
	"Гонка": "Time Trial",
	"Піхота в окопах": "Infantry in Trenches",
	"Колона бронетехніки": "Armored Column",
	"Гелікоптер у русі": "Moving Helicopter",
	"БПЛА «Дельта-136»": "Delta-136 UAV",
	"БПЛА «Шахед-136»": "Delta-136 UAV",
	"Навчальна гребля-ГЕС": "Training Hydro Dam",
	"Кримська ГЕС": "Training Hydro Dam",
	"1. Піхота в окопах": "1. Infantry in Trenches",
	"2. Колона бронетехніки": "2. Armored Column",
	"3. Гелікоптер у русі": "3. Moving Helicopter",
	"4. БПЛА «Дельта-136»": "4. Delta-136 UAV",
	"4. БПЛА «Шахед-136»": "4. Delta-136 UAV",
	"5. Навчальна гребля-ГЕС": "5. Training Hydro Dam",
	"5. Кримська ГЕС": "5. Training Hydro Dam",
	"Виявлення та ліквідація живої сили": "Locate and mark tactical range targets",
	"Знищення танка Т-72Б та бронетранспортера БТР-82А на марші": "Engage moving T-72B tank and BTR-82A APC range targets",
	"Перехоплення низьковисотної авіації": "Intercept low-flying aerial range targets",
	"Швидкісне знищення камікадзе": "High-speed aerial target interception",
	"Морський удар катером «МАГУРА-Х»": "MAGURA-X maritime interception sortie",
	"5 завдань": "5 missions",
	"6 модулів": "6 modules",
	"10 модулів": "10 modules",
	"КП трек": "Checkpoint course",
	"FPV СИМУЛЯТОР · UKRAINE · v1.6.0-test": "FPV SIMULATOR · UKRAINE · v1.6.0-test",
	"Піхаота": "Infantry",
	"Окопна лінія": "Trench line",
	"Водомет": "Waterjet",
	"Час: %s": "Time: %s",
	"РЕКРУТ": "RECRUIT",
	"ОПЕРАТОР": "OPERATOR",
	"АС": "ACE",
	"КРОК": "STEP",
	"ПАУЗА": "PAUSE",
	"РЕЖИМ": "MODE",
	"БОРТ": "AIRCRAFT",
	"ТТХ": "SPECS",
	"ТЕЛЕМЕТРІЯ": "TELEMETRY",
	"TX12": "TX12",
	"« ТАКТИЧНА ПАУЗА »": "« TACTICAL PAUSE »",
	"ПІЛОТ": "PILOT",
	"СТАТУТ": "PROTOCOL",
	"БРИФІНГ": "BRIEFING",
	"СЕКТОР": "SECTOR",
	"Ураження танка Т-72Б та БТР-82А": "Engage a T-72B tank and BTR-82A APC",
	"Легка": "Easy",
	"Середня": "Medium",
	"Важка": "Hard",
	"Екстрим": "Extreme",
	"Спец": "Special",
	"Рекрут: +25% часу (25 хв) · Помірний вітер · Знижена шкода · Бал x1.0": "Recruit: +25% time (25 min) · Light wind · Reduced damage · Score x1.0",
	"Оператор: Час 20 хв · Реалістичний вітер · Бойова шкода · Бал x1.25": "Operator: 20 min · Realistic wind · Full damage · Score x1.25",
	"Ас: Жорсткий час 15 хв · Шквальний вітер · Точне ППО · Бал x1.75": "Ace: 15 min · Gusting wind · Accurate air defenses · Score x1.75",
	"РЕЖИМИ ВИЛЬОТУ": "FLIGHT MODES",
	"БОЙОВІ МІСІЇ": "COMBAT MISSIONS",
	"ЗВЕРХУ": "TOP",
	"СПЕРЕДУ": "FRONT",
	"ЗБОКУ": "SIDE",
	"3D ОГЛЯД": "3D VIEW",
	"🔄 Авто: Увімк": "🔄 AUTO: ON",
	"⏸️ Авто: Вимк": "⏸️ AUTO: OFF",
	"Перехрестя": "Crosshair",
	"Натисніть ПОЧАТИ, щоб перейти до меню": "Select a panel to continue",

	# Drone builder
	"КОНСТРУКТОР ТАКТИЧНИХ ТА СПОРТИВНИХ БПЛА": "DRONE BUILDER LAB",
	"МОДУЛЬНА ЗБІРКА З 3D-ДЕТАЛЕЙ · РОЗРАХУНОК ТЯГИ ТА БАЛАНСУ · ТЕСТОВИЙ ВИЛІТ": "MODULAR ASSEMBLY · LIVE SPECS · TEST FLIGHT",
	"ВИБІР КОМПОНЕНТА": "COMPONENTS",
	"МОДУЛІ": "MODULES",
	"РАМА": "FRAME",
	"ДВИГУНИ (4x)": "MOTORS (4x)",
	"ГВИНТИ (4x)": "PROPS (4x)",
	"БАТАРЕЯ": "BATTERY",
	"КАМЕРА": "CAMERA",
	"БОЙОВА ЧАСТИНА": "PAYLOAD",
	"СТАНДАРТНИЙ 5\"": "DEFAULT 5\" BUILD",
	"ЗБЕРЕГТИ В АНГАР": "SAVE TO HANGAR",
	"ТЕСТОВИЙ ВИЛІТ (БОЙОВИЙ ПОЛІГОН)": "TEST FLIGHT · RANGE",
	"Характеристики деталі": "Component specifications",
	"ФАРБУВАННЯ": "PAINT SCHEME",
	"ТАКТИЧНА ОЛИВА": "TACTICAL OLIVE",
	"ГОНОЧНИЙ ОРАНЖ": "RACING ORANGE",
	"ПІСОЧНИЙ ПОШУК": "SAND / SEARCH",
	"ТТХ ТА БАЛАНС ДРОНУ": "LIVE AIRCRAFT SPECS",
	"ІНТЕЛ": "INTEL",
	"БОЙОВИЙ ПРОФІЛЬ ТА БЧ": "MISSION PROFILE & PAYLOAD",
	"ЗСУ": "AFU",
	"ПЕРЕВІРКА СУМІСНОСТІ": "COMPATIBILITY CHECK",
	"КОНТРОЛЬ": "SYSTEM CHECK",
	"⚡ ТЕСТ МОТОРІВ": "⚡ MOTOR TEST",
	"🔄 АВТО-ОБЕРТАННЯ": "🔄 AUTO ROTATE",
	"ПРОПЕЛЕРИ": "PROPELLERS",
	"ОБЕРТАННЯ": "SPIN",
	"Деталь": "Component",
	"ЗБАЛАНСОВАНИЙ ФРІСТАЙЛ": "BALANCED FREESTYLE",
	"ДЕТОНАТОР: ВІДСУТНІЙ": "PAYLOAD: NONE",
	"УДАРНИЙ КАМІКАДЗЕ": "TACTICAL STRIKE",
	"БОМБАРДУВАЛЬНИК": "BOMBER",
	"СПОРТИВНИЙ / РОЗВІДКА": "SPORT / RECON",
	"СХЕМУ ФАРБУВАННЯ ЗАСТОСОВАНО": "PAINT SCHEME APPLIED",
	"ЗБІРКУ СКИНУТО ДО СТАНДАРТУ": "BUILD RESET TO DEFAULT",
	"КОНФІГУРАЦІЮ ЗБЕРЕЖЕНО В АНГАР": "BUILD SAVED TO HANGAR",
	"ВСІ КОМПОНЕНТИ СУМІСНІ": "ALL COMPONENTS COMPATIBLE",

	# General settings and help
	"ІНШІ НАЛАШТУВАННЯ": "OTHER SETTINGS",
	"ЗВУК": "AUDIO",
	"Загальна гучність": "Master volume",
	"Звук у вступному відео": "Intro video audio",
	"ІНТЕРФЕЙС (HUD)": "INTERFACE (HUD)",
	"Лічильник FPS": "FPS counter",
	"СКИНУТИ HUD": "RESET HUD",
	"ТАКТИЧНІ НАЛАШТУВАННЯ": "TACTICAL SETTINGS",
	"Конфігурація пульта, графіки, аудіо та бойових систем": "Configure controls, graphics, audio, and flight systems",
	"🎮   КЕРУВАННЯ ТА ПРИЗНАЧЕННЯ КНОПОК": "🎮   CONTROLS & BINDINGS",
	"🕹   КАЛІБРУВАННЯ СТІКІВ ПУЛЬТА": "🕹   CONTROLLER CALIBRATION",
	"🖥   ГРАФІКА ТА FPS (ДО 120 FPS)": "🖥   GRAPHICS & FPS (UP TO 120 FPS)",
	"⚙   ПАРАМЕТРИ СИМУЛЯЦІЇ ТА ЗВУК": "⚙   SIMULATION & AUDIO",
	"📖   ТАКТИЧНА ДОВІДКА ТА ГАРЯЧІ КЛАВІШІ": "📖   HELP & KEYBOARD SHORTCUTS",
	"ГРАФІКА": "GRAPHICS",
	"СКИНУТИ ГРАФІКУ": "RESET GRAPHICS",
	"КЕРУВАННЯ": "CONTROLS",
	"ТАКТИЧНА ДОВІДКА ТА КЕРУВАННЯ": "TACTICAL HELP & CONTROLS",
	"КАЛІБРУВАННЯ СТІКІВ ПУЛЬТА": "CONTROLLER STICK CALIBRATION",
	"ПУЛЬТ RADIOMASTER TX12": "RADIOMASTER TX12 CONTROLLER",
	"ПРИСТРІЙ": "DEVICE",
	"ПРИВ’ЯЗКИ": "BINDINGS",
	"СТІКИ": "STICKS",
	"КНОПКИ ТА ПЕРЕМИКАЧІ": "BUTTONS & SWITCHES",
	"Використовувати за замовчуванням": "Use as default",
	"ГАЗ": "THROTTLE",
	"РИСКАННЯ": "YAW",
	"ТАНГАЖ": "PITCH",
	"КРЕН": "ROLL",
	"НЕБЕЗПЕЧНИЙ РЕЖИМ": "UNSAFE CONFIGURATION",
	"ПІХОТА В УКРИТТЯХ": "INFANTRY IN COVER",
	"КОЛОНА БРОНЕТЕХНІКИ": "ARMORED COLUMN",
	"УДАРНИЙ ГЕЛІКОПТЕР": "ATTACK HELICOPTER",
	"КРИМСЬКА ГЕС": "CRIMEAN HPP",
	"АНГАР БОЙОВИХ ТА СПОРТИВНИХ ДРОНІВ": "FLEET HANGAR · COMBAT & SPORT",
	"ТАКТИЧНИЙ ПАРК БПЛА: маневреність, тяга, маса та бойове навантаження": "UAV FLEET: agility, thrust, mass, and payload",
	"ВІДКРИТИ КОНСТРУКТОР (МОДУЛЬНА ЗБІРКА)": "OPEN DRONE BUILDER LAB",
	"✓ ВСІ КОМПОНЕНТИ СУМІСНІ 100%": "✓ ALL COMPONENTS COMPATIBLE",
	"Вибір дрона": "Select a drone",
	"Розвіддані та обстановка": "INTELLIGENCE & SITUATION",
	"Завдання операції": "MISSION OBJECTIVES",
	"Виявлені загрози": "IDENTIFIED THREATS",
	"Рекомендований дрон": "RECOMMENDED AIRCRAFT",
	"Метеоумови": "WEATHER CONDITIONS",
	"Мапа сектору": "SECTOR MAP",
	"Складність вильоту": "SORTIE DIFFICULTY",
	"Рекорди та нагороди": "RECORDS & AWARDS",
	"Брифінг": "Briefing",
	"ПОЧАТИ ВИЛІТ": "START SORTIE",
	"🇺🇦 FPV СИМУЛЯТОР": "🇺🇦 FPV SIMULATOR",
	"СИСТЕМНА НАВІГАЦІЯ": "SYSTEM NAVIGATION",
	"ПОЧАТИ КУРС ПІЛОТА FPV": "START FPV PILOT COURSE",
	"FPV FLIGHT SCHOOL · PILOT TRAINING": "FPV FLIGHT SCHOOL · PILOT TRAINING",
	"Виявити та ліквідувати живу силу": "Locate and neutralize enemy personnel",
	"Полігон": "Range",
	"ТАКТИЧНА ПАУЗА": "TACTICAL PAUSE",
	"СЕКТОР УПРАВЛІННЯ ПОЛЬОТОМ": "FLIGHT CONTROL SECTOR",
	"ПОВЕРНУТИСЯ ДО ШТАБУ (МЕНЮ)": "RETURN TO HEADQUARTERS",
	"ПАРАМЕТРИ БОРТУ ТА РЕЙТИ": "AIRCRAFT & RATE SETTINGS",
	"СТАРТ FPV": "FPV START",
	"ПІХ-%d": "INF-%d",
	"СЕКТОР: ОКОПНА ЛІНІЯ / ПОСАДКА": "SECTOR: TRENCH LINE / TREE LINE",
	"КОЛОНА НА МАРШІ (ЗАГРОЗА ППО)": "COLUMN ON THE MOVE (AIR-DEFENSE THREAT)",
	"МІ-8 / КА-52": "MI-8 / KA-52",
	"ПЕРЕХОПЛЕННЯ В ПОВІТРІ": "AERIAL INTERCEPTION",
	"ДЕЛЬТА-136": "DELTA-136",
	"ШАХЕД-136": "DELTA-136",
	"185 km/h · КУРС 240°": "185 km/h · HEADING 240°",
	"ВИСОКОШВИДКІСНИЙ ПЕРЕХОПЛЮВАЧ": "HIGH-SPEED INTERCEPTOR",
	"АКВАТОРІЯ ГЕС": "HYDROELECTRIC PLANT WATERS",
	"МАШИННИЙ ЗАЛ": "TURBINE HALL",
	"СТРАТЕГІЧНИЙ УДАР: НАВЧАЛЬНА ГРЕБЛЯ-ГЕС": "TACTICAL DRILL: TRAINING HYDRO DAM",
	"СТРАТЕГІЧНИЙ УДАР: ЗНИЩИТИ КРИМСЬКУ ГЕС": "TACTICAL DRILL: TRAINING HYDRO DAM",
	"ЗОНА ВІЛЬНОГО ПОЛЬОТУ": "FREE FLIGHT AREA",
	"РУСЛО ДОЛИНИ": "VALLEY ROUTE",
	"БЕЗ БОЙОВИХ ЗАГРОЗ · ВІЛЬНЕ ПІЛОТУВАННЯ": "NO COMBAT THREATS · FREE FLIGHT",
	"КП-%d": "CP-%d",
	"ГОНОЧНИЙ ТРЕК: 6 КОНТРОЛЬНИХ ВОРІТ": "RACE TRACK: 6 CHECKPOINT GATES",
	"1.ВИСІННЯ": "1.HOVER",
	"2.ВОР-1": "2.GATE-1",
	"3.ВІРАЖ": "3.TURN",
	"5.ПОСАДКА [H]": "5.LAND [H]",
	"ПОЛІГОН FPV: 6 ІНТЕРАКТИВНИХ МОДУЛІВ": "FPV RANGE: 6 INTERACTIVE LESSONS",
	"ЛЕГКА": "EASY",
	"СЕРЕДНЯ": "MEDIUM",
	"ВАЖКА": "HARD",
	"ЕКСТРЕМ": "EXTREME",
	"СПЕЦ": "SPECIAL",
	"ЗСУ // ІНЖЕНЕРНИЙ ТЕРМІНАЛ НАЛАШТУВАННЯ БПЛА ТА PID-РЕЙТІВ": "AFU // UAV FLIGHT-CONTROLLER & RATE CONFIGURATION",
	"КОНФІГУРАЦІЯ ПОЛЬОТНОГО КОНТРОЛЕРА": "FLIGHT CONTROLLER CONFIGURATION",
	"НАЛАШТУВАННЯ БОРТУ ТА ПРОФІЛЮ РЕЙТІВ": "AIRCRAFT & RATE PROFILE",
	"Кут камери FPV:": "FPV camera angle:",
	"Суха маса борту:": "Dry aircraft mass:",
	"Маса акумулятора:": "Battery mass:",
	"ПРОФІЛЬ КУТОВИХ ШВИДКОСТЕЙ (RATES / EXPO)": "ANGULAR RATE PROFILE (RATES / EXPO)",
	"Тангаж (Pitch)": "Pitch",
	"Крен (Roll)": "Roll",
	"Рискання (Yaw)": "Yaw",
	"СКИНУТИ ПАРАМЕТРИ БОРТУ": "RESET AIRCRAFT SETTINGS",
	"СКИНУТИ РЕЙТИ": "RESET RATES",
	"ФІЗИЧНІ ПАРАМЕТРИ БОРТУ": "AIRCRAFT PHYSICAL PARAMETERS",
	"ТАКТИКО-ТЕХНІЧНЕ ЗВЕДЕННЯ (ТТХ)": "PERFORMANCE SUMMARY",
	"ПРЕСЕТ ПОЛЬОТУ:": "FLIGHT PRESET:",
	"ІНДИВІДУАЛЬНИЙ ПРОФІЛЬ: ручне налаштування рейтів та експоненти": "CUSTOM PROFILE: manually tune rates and expo",
	"ГАЗ ДОНИЗУ": "THROTTLE DOWN",
	"Підніміть лівий стік ГАЗУ ВГОРУ (100%)": "Move the left throttle stick fully UP (100%)",
	"Потягніть правий стік ДО СЕБЕ": "Pull the right stick TOWARD you",
	"ПІДКЛЮЧЕНИХ ПЕРЕДАВАЧІВ: 0": "CONNECTED CONTROLLERS: 0",
	"СТАТУС USB-HID: ОЧІКУВАННЯ ПІДКЛЮЧЕННЯ": "USB HID STATUS: WAITING FOR CONNECTION",
	"Осі 0–7:  немає активного сигналу": "Axes 0–7: no active signal",
	"ПЕРЕВІРИТИ ПУЛЬТ": "TEST CONTROLLER",
	"ПОЧАТИ СПОЧАТКУ": "START OVER",
	"Низька (120+ FPS)": "Low (120+ FPS)",
	"Середня (баланс)": "Medium (balanced)",
	"Висока (Ультра, нативно)": "High (Ultra, native)",
	"UFDS (FPV 120, FSR)": "UFDS (FPV 120, FSR)",
	"120 FPS (макс. швидкість)": "120 FPS (max speed)",
	"Плавно 60 (слабкі ПК)": "Smooth 60 (low-end)",
	"Середня (Баланс)": "Medium (Balanced)",
	"Висока (Ультра)": "High (Ultra)",
	"Повноекранний": "Fullscreen",
	"Повноекранний (вікно)": "Borderless fullscreen",
	"Вікно": "Windowed",
	"Вікно без рамки": "Borderless window",
	"Вимкнено": "Off",
	"Низька": "Low",
	"Висока": "High",
	"Ультра": "Ultra",
	"Повний": "Full",
	"Швидкий": "Fast",
	"Як у грі": "Use game setting",
	"Без обмежень": "Unlimited",
	"Рівень графіки (3 рівні)": "Graphics quality (3 presets)",
	"Рівень графіки (5 рівнів)": "Graphics quality (5 presets)",
	"Рівень графіки (6 рівнів)": "Graphics quality (6 presets)",
	"Режим вікна": "Window mode",
	"Масштаб роздільності": "Render scale",
	"Згладжування (MSAA)": "Anti-aliasing (MSAA)",
	"Анізотропна фільтрація": "Anisotropic filtering",
	"Якість тіней": "Shadow quality",
	"FPV-об'єктив (риб'яче око)": "FPV lens (fisheye)",
	"Роздільність об'єктива": "Lens resolution",
	"MSAA об'єктива": "Lens MSAA",
	"Вертикальна синхронізація": "Vertical sync",
	"Обмеження FPS": "FPS limit",
	"Штучний горизонт": "Artificial horizon",
	"Шкала тангажу": "Pitch ladder",
	"Позиція стіків": "Stick positions",
	"Оберти моторів": "Motor RPM",
	"Увесь OSD (H)": "Full OSD (H)",
	"ТРЕНАЖЕР / СИМУЛЯЦІЯ": "TRAINING / SIMULATION",
	"Полегшення діють одразу, у тому числі під час польоту.": "Aids apply immediately, including in flight.",
	"Обмеження зв'язку та REB": "Link and EW limits",
	"Вимкніть, щоб літати без втрати відео та керування на будь-якій відстані.": "Disable to fly without video or control loss at any distance.",
	"Імітація вітру та поривів": "Wind and gust simulation",
	"Вимкніть, щоб прибрати знос дрона вітром, пориви й турбулентність.": "Disable to remove wind drift, gusts and turbulence.",
	"Режим Angle (стабілізація)": "Angle mode (self-level)",
	"Режим Acro (ручний)": "Acro mode (manual)",
	"Дозволити самовирівнювання. Якщо вимкнути Angle і Acro, лишиться HORIZON.": "Allow self-levelling. Disabling both Angle and Acro leaves HORIZON.",
	"Дозволити ручний режим. Якщо вимкнути Angle і Acro, лишиться HORIZON.": "Allow manual control. Disabling both Angle and Acro leaves HORIZON.",
	"Нескінченна батарея (тренажер)": "Infinite battery (training)",
	"Батарея не розряджається під час польоту.": "The battery does not discharge in flight.",
	"Керування, графіка, звук і симуляція": "Controls, graphics, audio and simulation",
	"ЗВУК, HUD І СИМУЛЯЦІЯ": "AUDIO, HUD & SIMULATION",
	"FPV-обвіс: вусики + бомба (J)": "FPV rig: antenna + payload (J)",
	"БЕЗ ПУЛЬТА ПРАЦЮЮТЬ КЛАВІАТУРА ТА МИШКА": "KEYBOARD AND MOUSE AVAILABLE WITHOUT A CONTROLLER",
	"ПІДКЛЮЧІТЬ USB-ПУЛЬТ, ГЕЙМПАД АБО RC-ПЕРЕДАВАЧ.": "CONNECT A USB CONTROLLER, GAMEPAD, OR RC TRANSMITTER.",
	"←   НАЗАД": "←   BACK",
	"ОПЕРАЦІЯ TAC-01": "OPERATION TAC-01",
	"Розкладка керування": "CONTROL LAYOUT",
	"ПУЛЬТ  RADIOMASTER  TX12": "RADIOMASTER TX12 CONTROLLER",
	"СІТКА ОСЕЙ": "AXIS GRID",
	"КАНАЛИ ПУЛЬТА": "CONTROLLER CHANNELS",
	"Авто": "Auto",
	"Геймпад Xbox/PS": "Xbox / PlayStation Controller",
	"Клавіатура": "Keyboard",
	"Без пульта працюють клавіатура та мишка.": "Keyboard and mouse are available without a controller.",
	"КАЛІБРУВАННЯ УСПІШНО ЗАВЕРШЕНО!\nПрофіль передавача збережено в системі.": "CALIBRATION COMPLETE!\nController profile saved.",
	"✓ ГОТОВО ДО БОЙОВОГО ВИЛЬОТУ": "✓ READY FOR SORTIE",
	"ДОСТУПНІСТЬ ТА МОВА / ACCESSIBILITY": "ACCESSIBILITY & LANGUAGE",
	"Палітра OSD: ": "OSD palette: ",
	"Мова: ": "Language: ",
	"Українська (UA)": "Ukrainian (UA)",
	"КОНТРАСТ (B/W)": "HIGH CONTRAST (B/W)",
	"ДАЛЬТОНІЗМ (CYAN/AMBER)": "COLORBLIND (CYAN/AMBER)",
	"ФОСФОР (NVG GREEN)": "PHOSPHOR (NVG GREEN)",
	"НІЧНИЙ ЧЕРВОНИЙ": "NIGHT RED",
	"СТАНДАРТ ЗСУ": "STANDARD TACTICAL",
	"ВИХІД З СИМУЛЯТОРА": "EXIT SIMULATOR",
	"«ГОЛКА»": "HOLKA",
	"ФРІСТАЙЛ 5\"": "FREESTYLE 5\"",
	"Легкий фрістайл, миттєвий відгук": "Light freestyle quad with instant response",
	"Класична 5\" рама, відкриті пропелери": "Classic 5-inch frame with exposed propellers",
	"Cinewhoop із захистом пропелерів": "Cinewhoop with guarded propellers",
	"VTOL-качка, ударний камікадзе": "VTOL tailsitter tactical quad",
	"Розвідник із панельною антеною": "Recon quad with a directional antenna",
	"Важкий ударний дальньої дії": "Heavy long-range tactical quad",
	"Ударний із системою скидання": "Tactical quad with a payload-release system",
	"Важкий камікадзе з виносним підвісом": "Heavy tactical quad with an external payload mount",
	"Цифровий швидкісний FPV, обтічний фюзеляж": "High-speed digital FPV with an aerodynamic fuselage",
	"Карбонова X-рама 225 мм, висока тяга 6.5:1": "225 mm carbon X-frame · high 6.5:1 thrust-to-weight",
	"Морський ударний дрон-камікадзе": "High-speed unmanned surface craft",
	"КАСТОМ 5\"": "CUSTOM 5\"",
	"РОЗВІДКА 5\"": "RECON 5\"",
	"УДАРНИЙ 8–10\"": "TACTICAL 8–10\"",
	"УДАРНИЙ + СКИД": "TACTICAL + DROP",
	"КАМІКАДЗЕ": "INTERCEPTOR",
	"МОРСЬКИЙ USV": "MARITIME USV",
	"Швидкісний морський ударний дрон-камікадзе": "High-speed unmanned surface craft",
	"ЗБІРКА КАСТОМНОГО ДРОНА": "CUSTOM DRONE BUILD",
	"Легка каркасна X-рама з відкритими пропелерами та високою «грибковою» антеною на задній частині. Мінімальна злітна вага й жвава реакція на стіки — для тренувань, фрістайлу та точного калібрування пульта.": "Lightweight open-prop X-frame with a raised antenna. Low takeoff weight and responsive controls make it ideal for training, freestyle, and precise controller calibration.",
	"Класичний кастомний FPV-квадрокоптер: рама з відкритими пропелерами та верхнім розташуванням акумулятора й навантаження. Легка модель на ~28 тис. трикутників — мінімальне навантаження на систему.": "Classic custom FPV quad with exposed propellers and top-mounted battery and payload. Lightweight model with approximately 28k triangles for low rendering cost.",
	"Cinewhoop для польотів у приміщеннях і кінематографічних кадрів. Реальні габарити 212 × 184 × 64 мм, захисні дуги, підвіс камери та фірмові помаранчеві акценти. Плавний, стабільний, із м'якими стіками.": "Indoor cinewhoop for smooth cinematic footage. Real dimensions: 212 × 184 × 64 mm, with prop guards, a camera gimbal, and signature orange accents. Stable and tuned for gentle control.",
	"Ударний FPV-камікадзе на витягнутій карбоновій деці з подовженим центральним відсіком. Tailsitter VTOL: вертикальний зліт, збірка 6S і високооборотні безщіткові мотори. Центр ваги зміщується разом із «боєкомплектом».": "Strike FPV tailsitter with an extended carbon deck and central bay. VTOL takeoff, 6S power, and high-RPM brushless motors. Payload mass shifts the center of gravity.",
	"Розвідувальний FPV-квадрокоптер із посиленим комплексом зв'язку: спрямована панельна антена та кругова антена на задній виносній штанзі. Виносні елементи створюють додаткову парусність на швидкості — тренування точного пілотування.": "Recon FPV quad with an upgraded radio package: directional panel antenna and an elevated omnidirectional antenna. The added drag rewards precise piloting at speed.",
	"Важкий квадрокоптер-камікадзе дальньої дії, рама 8–10 дюймів. Потужна батарея на верхній деці та видовжений боєприпас із хвостовим оперенням під днищем зміщують центр мас: дрон інертний у віражах і потребує точного розрахунку на заході на ціль.": "Heavy long-range strike quad on an 8–10-inch frame. The top-mounted battery and extended underbody payload shift the center of mass, making turns sluggish and approach planning critical.",
	"Модифікована повна комплектація: велика акумуляторна збірка зверху з ременем, видимий силовід і XT60, виносна антена VTX та нижня захисна дуга-лижа. Система скидання й важка бойова частина під рамою.": "Fully equipped variant with a strapped battery pack, visible power lead and XT60 connector, elevated VTX antenna, and lower skid guard. Includes a payload-release system and heavy underframe payload.",
	"Важкий ударний дрон із унікальною системою підвісу та детонації. Під днищем — бойовий елемент видовженої форми з детонаційним шнуром-петлею попереду, зверху вертикально орієнтований акумулятор. Високий момент інерції по вертикальній осі.": "Heavy strike quad with a specialized payload mount and fuze assembly. The elongated underbody payload and upright top battery create high yaw inertia.",
	"Швидкісний цифровий FPV-дрон з аеродинамічним обтічним фюзеляжем. Розгін 0–100 км/год за 2.0 секунди, максимальна швидкість 140 км/год (39 м/с). Політна вага 795 г створює стабільну інерцію на віражах, а низький опір повітря забезпечує стрімкий політ.": "High-speed digital FPV with a streamlined fuselage. Accelerates from 0–100 km/h in 2.0 seconds and reaches 140 km/h (39 m/s). Its 795 g flight weight provides stable cornering while the low-drag body maintains speed.",
	"Класичний кастомний 5-дюймовий FPV-квадрокоптер на посиленій карбоновій рамі Mark4. Збалансований центр ваги, верхнє розташування LiPo 6S, миттєвий відгук на стіки та тягооснащеність 6.5:1 для впевненого фрістайлу та бойових завдань.": "Custom 5-inch FPV quad on a reinforced Mark4 carbon frame. Balanced center of gravity, top-mounted 6S LiPo, responsive controls, and a 6.5:1 thrust-to-weight ratio for freestyle and mission flying.",
	"Швидкісний маневрений безпілотний катер з глісерним корпусом, призначений для ураження ворожих надводних цілей у відкритому морі та прибережній зоні. Водометний рушій, швидкість до 45–50 вузлів (85 км/г), низький профіль радіолокаційної помітності та потужна 320-кг бойова частина.": "High-speed, maneuverable unmanned surface vessel with a planing hull for open-water and coastal operations. Features a waterjet, 45–50-knot speed, a low radar profile, and a 320 kg payload.",
	"Ультралегка симетрична True-X рама для FPV-перегонів.": "Ultra-light symmetrical True-X frame for FPV racing.",
	"Подовжена рама Stretched-X для далеких польотів та носіння важких акумуляторів.": "Stretched-X frame for long-range flights and heavy batteries.",
	"Посилена військова рама з 8-мм фермовими променями для важких дронів-камікадзе.": "Reinforced tactical frame with 8 mm arms for heavy strike quads.",
	"Рама з захисними кільцевими дактами для безпечних зйомок та польотів у приміщенні.": "Ducted frame for safer indoor flying and close-proximity filming.",
	"Високооборотний гоночний двигун для 5-дюймових гвинтів.": "High-KV racing motor for 5-inch propellers.",
	"Тяговитий мотор зі сталевим валом для 7-10 дюймових ударних FPV.": "High-thrust motor with a steel shaft for 7–10-inch strike quads.",
	"Швидкісний полікарбонатний гвинт для агресивного фрістайлу.": "Fast polycarbonate propeller for aggressive freestyle.",
	"Ефективний гвинт великого радіусу дії з низьким рівнем шуму.": "Efficient long-range propeller with reduced noise.",
	"Вантажний армований гвинт для підйому бойової частини.": "Reinforced heavy-lift propeller for payload builds.",
	"Легкий гоночний LiPo акумулятор із миттєвою струмовіддачею.": "Lightweight racing LiPo with high burst-current delivery.",
	"Важка збірка з елементів 21700 для бойових операцій на великих дистанціях.": "High-capacity 21700-cell battery pack for long-range operations.",
	"Ультранизька затримка сигналу для швидкісного пілотування.": "Ultra-low video latency for high-speed piloting.",
	"Тепловізійний бойовий модуль для виявлення замаскованої техніки вночі.": "Thermal camera module for detecting concealed equipment at night.",
	"Стандартний монтажний замок без боєприпасу.": "Standard mounting latch with no payload installed.",
	"30-мм осколкова граната з хвостовиком та сервоприводом дистанційного скиду.": "30 mm fragmentation grenade with a tail assembly and remote-release servo.",
	"Важка бронебійна кумулятивна бойова частина для знищення танків прямим ударом.": "Heavy shaped-charge payload for direct-attack missions against armored targets.",
	"Швидкість": "Speed",
	"На Час": "Time Trial",
	"Висота": "Altitude",
	"Курс": "Heading",
	"Режим гри": "Game mode",
	"Школа пілота": "Flight School",
	"Школа пілотів": "Flight School",
	"Вільний політ": "Free Flight",
	"Швидкісна траса": "Speed Course",
	"Траса на час": "Time Trial Course",
	"БАРАЖУЮЧИЙ БПЛА-136": "LOITERING UAV-136",
	"БПЛА SHAHED-136": "LOITERING UAV-136",
	"Калібрування передавача": "Controller calibration",
	"СТАБІЛЬНИЙ": "STABLE",
	"СПОРТ": "SPORT",
	"ГОНКА": "RACE",
	"НА ЧАС": "TIME TRIAL",
	"КІНО": "CINEMATIC",
	"Плавний, малий нахил — для навчання й зйомки": "Smooth, low bank angle for training and filming.",
	"Звичний баланс швидкості й контролю": "Balanced speed and control.",
	"Швидкі оберти, великий нахил, мінімум експо": "Fast rates, steep bank angle and minimal expo.",
	"Дуже м'які реакції для плавних прольотів": "Soft response for smooth, cinematic flight.",
	"Пульт TX12 повторює рухи стіків — сітка осей показує живий вхід": "The TX12 preview mirrors your stick inputs; the axis grid shows live signals.",
	"ЛІВИЙ СТІК (ГАЗ/YAW)": "LEFT STICK (THROTTLE/YAW)",
	"ПРАВИЙ СТІК (PITCH/ROLL)": "RIGHT STICK (PITCH/ROLL)",
	"← ПОПЕРЕДНІЙ КРОК": "← PREVIOUS STEP",
	"← ПОВЕРНУТИСЯ НАЗАД": "← BACK",
	"🛠️ ВІДКРИТИ КОНСТРУКТОР (МОДУЛЬНА ЗБІРКА)": "🛠️ OPEN DRONE BUILDER",
	"Пульт не знайдено": "No controller found",
	"ШВИДКІ ПРИЗНАЧЕННЯ:": "QUICK BINDINGS:",
	"Інвертувати напрямок стіка": "Invert stick direction",
	"ВИБІР МІСІЇ": "MISSION SELECT",
	"ПІДГОТОВКА ДО ВИЛЬОТУ": "SORTIE SETUP",
	"Обробка": "Rendering",
	"ПІХОТНИЙ РЕЖИМ": "INFANTRY MODE",
	"ШКОЛА ПІЛОТІВ FPV · КУРС ОПЕРАТОРА": "FPV FLIGHT SCHOOL · PILOT COURSE",
	"ШКОЛА ПІЛОТА · КУРС ОПЕРАТОРА": "FLIGHT SCHOOL · PILOT COURSE",
	"Модулі: 6/6 · Асистент помилок: активний · Сертифікат: доступний": "Modules: 6/6 · Error coach: active · Certificate: available",
	"МОДУЛІВ: 10/10  •  АСИСТЕНТ ПОМИЛОК: АКТИВНИЙ  •  СЕРТИФІКАТ: ДОСТУПНИЙ": "MODULES: 10/10  •  ERROR COACH: ACTIVE  •  CERTIFICATE: AVAILABLE",
	"Операція: «Чисте поле»": "Operation: Clear Field",
	"Завдання: TAC-01": "Mission: TAC-01",
	"Підключіть USB-пульт, геймпад або RC-передавач.": "Connect a USB controller, gamepad, or RC transmitter.",
	"Газ": "Throttle",
	"Рискання (yaw)": "Yaw",
	"Тангаж (pitch)": "Pitch",
	"Крен (roll)": "Roll",
	"Арм / Дизарм": "Arm / Disarm",
	"Арм (утрим.)": "Arm (hold)",
	"Скид бомби": "Payload release",
	"Респавн": "Respawn",
	"Режим польоту": "Flight mode",
	"Активація БЧ": "Activate warhead",
	"Активація БЧ / миттєва детонація": "Activate warhead / instant detonation",
	"FPV-фільтр": "FPV filter",
	"Пауза": "Pause",

	# Touch controls, flight HUD, and end-of-sortie screens
	"АРМ": "ARM",
	"ДИСАРМ": "DISARM",
	"БЧ": "WARHEAD",
	"СКИД": "DROP",
	"МЕНЮ": "MENU",
	"ОПЦ": "OPTIONS",
	"ВВІД: СЕНСОР": "INPUT: TOUCH",
	"ВВІД: ПУЛЬТ": "INPUT: RC",
	"ПЛАВ. СТІК: ВИКЛ": "FLOATING STICK: OFF",
	"ПЛАВ. СТІК: ВКЛ": "FLOATING STICK: ON",
	"ГАЗ: КЛАСИК": "THROTTLE: CLASSIC",
	"ГАЗ: ПРУЖИНА": "THROTTLE: SPRING",
	"КАМЕРА -5°": "CAMERA -5°",
	"КАМЕРА +5°": "CAMERA +5°",
	"ВІДЕО": "VIDEO",
	"РЕСЕТ": "RESET",
	"МЕНЮ / ПАУЗА": "MENU / PAUSE",
	"НАЛАШТУВАННЯ ELRS / СЕНСОРА": "ELRS / TOUCH SETUP",
	"Канал ARM": "ARM CHANNEL",
	"Канал режимів": "FLIGHT MODE CHANNEL",
	"Канал відео": "VIDEO CHANNEL",
	"Інверсія крену (ELRS)": "Invert ELRS roll",
	"Інверсія крену (сенсор)": "Invert touch roll",
	"Інверсія тангажу (сенсор)": "Invert touch pitch",
	"ЗАКРИТИ": "CLOSE",
	"РЕЖИМ: ANGLE": "MODE: ANGLE",
	"РЕЖИМ: ACRO": "MODE: ACRO",
	"РЕЖИМ: SPEED": "MODE: SPEED",
	"РЕЖИМ: TRACK": "MODE: TRACK",
	"РЕЖИМ: LAUNCH": "MODE: LAUNCH",
	"РЕЖИМ: TURTLE": "MODE: TURTLE",
	"РЕЖИМ: AUTO": "MODE: AUTO",
	"РЕЖИМ: HORIZON": "MODE: HORIZON",
	"ЧАС %s": "TIME %s",
	"МІСІЮ ВИКОНАНО": "MISSION COMPLETE",
	"РЕЗУЛЬТАТИ ВИЛЬОТУ": "SORTIE RESULTS",
	"ПІДСУМКИ МІСІЇ": "MISSION DEBRIEF",
	"ЗАВЕРШИТИ": "END SORTIE",
	"СКИД: ВІДСУТНІЙ": "PAYLOAD: NONE",
	"СКИД %d/%d": "DROP %d/%d",
	"ПРОЛЕТІТИ ЩЕ РАЗ  [ENTER]": "FLY AGAIN  [ENTER]",
	"НАТИСНІТЬ ENTER АБО КНОПКУ, ЩОБ ПОЧАТИ ЗНОВУ": "PRESS ENTER OR THE BUTTON TO RESTART",
	"ЧАС ПОЛЬОТУ       ": "FLIGHT TIME       ",
	"ОЧКИ              ": "SCORE             ",
	"ЦІЛІ              ": "TARGETS           ",
	"ЗЕНІТКИ           ": "AIR DEFENSE       ",
	"ПІХОТА            ": "INFANTRY          ",
	"ТОЧНІСТЬ          ": "ACCURACY          ",
	"ЗВАННЯ            ": "RANK              ",
	"ЗНИЩЕНО ЦІЛЕЙ   ": "TARGETS DESTROYED ",
	"ЗАВДАННЯ ВИКОНАНО": "MISSION ACCOMPLISHED",
	"ОПЕРАЦІЮ ЗАВЕРШЕНО — КАМПАНІЮ ПРОЙДЕНО!": "OPERATION COMPLETE — CAMPAIGN FINISHED!",
	"ДВИГУНИ ВИМКНЕНО": "MOTORS DISARMED",
	"ДВИГУНИ ВИМКНЕНО  (АРМ — увімкнути)": "MOTORS DISARMED  (TAP ARM TO START)",
	"ДВИГУНИ ВИМКНЕНО  (ПРОБІЛ — увімкнути)": "MOTORS DISARMED  (SPACE TO ARM)",
	"ДВИГУНИ УВІМКНЕНО — ГАЗ УГОРУ": "MOTORS ARMED — RAISE THROTTLE",
	"ЗАПУСК": "LAUNCH",
	"ПЕРЕВЕРНУТО": "TURTLE MODE",
	"АВТОВІДНОВЛЕННЯ": "AUTO RECOVERY",
	"ГАЗ НЕ В НУЛІ — ОПУСТІТЬ ГАЗ": "THROTTLE NOT ZERO — LOWER THROTTLE",
	"РЕЖИМ ВІДНОВЛЕННЯ": "RECOVERY MODE",
	"ОПУСТІТЬ ГАЗ, ЩОБ УВІМКНУТИ ДВИГУНИ": "LOWER THROTTLE TO ARM MOTORS",
	"НЕМАЄ БОЄПРИПАСУ": "NO PAYLOAD AVAILABLE",
	"АРМ НЕ ДОЗВОЛЕНО": "ARMING NOT ALLOWED",
	"БЧ АКТИВОВАНО": "WARHEAD DETONATED",
	"ПІДКРІПЛЕННЯ ПРОТИВНИКА · ПІХОТА": "ENEMY REINFORCEMENTS · INFANTRY",
	"ПІДКРІПЛЕННЯ": "REINFORCEMENTS",
	"ЗОНУ ПРОЙДЕНО — РУХАЙТЕСЬ ДАЛІ": "ZONE CLEARED — MOVE TO THE NEXT",
	"ОПЕРАЦІЮ ВИКОНАНО — ГАРНА РОБОТА": "OPERATION COMPLETE — GOOD WORK",
	"ОПЕРАЦІЮ ПРОВАЛЕНО — ПОВЕРТАЙСЯ НА БАЗУ": "MISSION FAILED — RETURN TO BASE",
	"ЗВ'ЯЗОК ВІДНОВЛЕНО": "LINK RESTORED",
	"БЕЗ ОБМЕЖЕНЬ": "UNLIMITED",
	"ФЕЙЛСЕЙФ": "FAILSAFE",
	"КРИТИЧНО": "CRITICAL",
	"СЛАБКИЙ": "WEAK",
	"НОРМА": "NOMINAL",
	"ЗВ'ЯЗОК": "LINK",
	"НИЗЬКА НАПРУГА БАТАРЕЇ — ПРИЗЕМЛЮЙТЕСЬ": "LOW BATTERY — LAND NOW",
	"РЕБ! ГЛУШІННЯ — ВТРАТА ЗВ'ЯЗКУ": "EW JAMMING — CONTROL LINK DEGRADED",
	"БАТАРЕЯ КРИТИЧНА — ПОВЕРТАЙСЯ НА БАЗУ": "BATTERY CRITICAL — RETURN TO BASE",
	"ЦІЛІ УРАЖЕНО — ПОВЕРТАЙСЯ НА БАЗУ": "TARGETS DESTROYED — RETURN TO BASE",
	"ЦІЛЬ УРАЖЕНО": "TARGET HIT",
	"ТАНК": "TANK",
	"БТР": "APC",
	"ВАНТАЖІВКА": "TRUCK",
	"БМП": "IFV",
	"ЗРК": "SAM",
	"ГЕЛІКОПТЕР": "HELICOPTER",
	"ШАХЕД": "SHAHED-136",
	"ЦІЛЬ": "TARGET",
	"РОЗВІДКА 1/3": "RECON 1/3",
	"РОЗВІДКА 2/3": "RECON 2/3",
	"РОЗВІДКА 3/3": "RECON 3/3",
	"ЕВАКУАЦІЯ · ПІЛОТ": "PILOT EXTRACTION",
	"ЕВАКУАЦІЯ · БАЗА": "EXFIL · BASE",
	"ВАНТАЖ · ЗАБРАТИ": "CARGO · PICK UP",
	"ВАНТАЖ · ДОСТАВИТИ": "CARGO · DELIVER",
	"ВИХІД · БАЗА": "EXFIL · BASE",
	"КОЛОНА": "CONVOY",
	"КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО": "CONVOY DESTROYED — ESCORT FAILED",
	"КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО": "CONVOY LOST — ESCORT FAILED",
	"НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОНИ!": "STAY WITH THE CONVOY!",
	"ТРИМАЙТЕСЬ БЛИЖЧЕ ДО КОЛОНИ": "KEEP CLOSER TO THE CONVOY",
	"СЕЛО": "VILLAGE",
	"СТЕП": "STEPPE",
	"ПРОМЗОНА": "INDUSTRIAL ZONE",
	"БОЛОТА": "WETLANDS",
	"ВІДКРИТА МІСЦЕВІСТЬ": "OPEN TERRAIN",
	"МІСЬКА ЗАБУДОВА": "BUILT-UP AREA",
	"ЗАВОДИ Й ТРУБИ": "FACTORY COMPLEX",
	"ВОДА Й ОЧЕРЕТ": "WATER & REEDS",
	"СКЛАДНІСТЬ: ЛЕГКА": "DIFFICULTY: EASY",
	"СКЛАДНІСТЬ: СЕРЕДНЯ": "DIFFICULTY: MEDIUM",
	"СКЛАДНІСТЬ: СКЛАДНА": "DIFFICULTY: HARD",
	"НАСТУПНА МІСІЯ": "NEXT MISSION",
	"Брифінг кампанії": "Campaign briefing",
	"Тут — ARM, режими й відео. Скид, застосування БЧ, ресет та інші дії призначаються в «Налаштування → КЕРУВАННЯ» (працює з ELRS на телефоні).": "Configure ARM, flight modes, and video here. Payload release, warhead activation, reset, and other actions are assigned under Settings → Controls. ELRS works over your phone's local Wi-Fi.",
	"Спецоперації": "SPECIAL OPERATIONS",
	"Окремі вильоти поза кампанією: розвідка, супровід, евакуація, доставка, нічний удар, прорив РЕБ, тилова колона, «Орешник» і глибокий тил.": "Standalone sorties outside the campaign: reconnaissance, convoy escort, pilot extraction, cargo delivery, night strike, EW breach, rear-area convoy, Oreshnik strike, and deep strike.",
	"ВИБІР ВИЛЬОТУ ТА РЕЖИМУ": "SORTIE & MODE SELECT",
	"ПЛАН ВИЛЬОТУ": "SORTIE PLAN",
	"Карта / Frontline": "MAP / FRONTLINE",
	"КУРС ЗАВЕРШЕНО": "COURSE COMPLETE",
	"✓ ВОРОТА 1 ПРОЙДЕНО. Тепер слалом — крен ліворуч/праворуч.": "✓ GATE 1 CLEARED. Next is the slalom: bank left, then right.",
	"✓ СЛАЛОМ A. Тепер праві ворота — крен праворуч.": "✓ SLALOM A CLEARED. Bank right through the next gate.",
	"✓ СЛАЛОМ ПРОЙДЕНО. Далі — низькі та високі ворота.": "✓ SLALOM COMPLETE. Next: the low and high gates.",
	"✓ НИЗЬКІ ВОРОТА. Тепер підніміться до 5 м — високі ворота.": "✓ LOW GATE CLEARED. Climb to 5 m for the high gate.",
	"✓ ВИСОТА ПРОЙДЕНА. Попереду стіна з вікном.": "✓ ALTITUDE GATES CLEARED. A window wall is ahead.",
	"✓ ВІКНО ПРОЙДЕНО! Тепер загальмуйте в жовтій зоні.": "✓ WINDOW CLEARED! Now brake inside the yellow zone.",
	"✓ Двигуни увімкнено. Тепер вимкніть їх (ПРОБІЛ), не злітаючи.": "✓ Motors armed. Disarm with SPACE without taking off.",
	"⚠ Спочатку приземліться, потім вимикайте двигуни.": "⚠ Land before disarming the motors.",
	"✓ Двигуни вимкнено. Тепер увімкніть їх знову — і до зльоту.": "✓ Motors disarmed. Arm once more, then take off.",
	"✓ УВІМКНЕННЯ ЗАСВОЄНО. Плавно додайте газ — дрон має піднятися.": "✓ ARMING COMPLETE. Increase throttle smoothly to lift off.",
	"✓ ВИСОТУ УТРИМАНО. Тепер спробуйте правий стік — тангаж і крен.": "✓ HOVER STABLE. Now practise pitch and roll with the right stick.",
	"✓ Тангаж і центрування засвоєно. Тепер крен.": "✓ Pitch and stick centring complete. Now practise roll.",
	"✓ Правий стік засвоєно. Тепер рискання лівим стіком.": "✓ Right-stick control complete. Now practise yaw with the left stick.",
	"✓ Поворот виконано. Тепер поверніться на початковий курс.": "✓ Turn complete. Return to your original heading.",
	"✓ Рискання засвоєно. Тепер перший політ уперед — ворота 1.": "✓ Yaw control complete. Now fly forward through Gate 1.",
	"✓ Інерцію погашено. Тепер посадка на майданчик [H].": "✓ Inertia arrested. Now land on the pad [H].",
	"⚠ Пролетіли повз отвір. R — повторити модуль або розверніться.": "⚠ You missed the opening. Press R to retry the module or turn around.",
	"Камера FPV увімкнена · C/V — нахил об'єктива": "FPV camera active · C/V adjusts camera tilt",
	"↻ Модуль перезапущено. Не поспішайте.": "↻ Module restarted. Take your time.",
	"⚠ ПЕРЕГАЗОВКА: ви занадто різко додали газ. Скиньте до 45% і вирівняйте дрон.": "⚠ WHISKEY THROTTLE: throttle was raised too quickly. Reduce to 45% and level the drone.",
	"⚠ ВТРАТА ГОРИЗОНТУ: дрон перевернувся. Відхиліть правий стік у протилежний бік.": "⚠ INVERTED DISORIENTATION: the drone is upside down. Apply opposite input on the right stick.",
	"⚠ ВИХРОВЕ КІЛЬЦЕ: не спускайтесь вертикально. Додайте трохи нахилу вперед.": "⚠ VORTEX RING STATE: avoid a vertical descent. Pitch forward slightly.",
	"💡 БІЧНИЙ ЗНОС: у повороті додавайте крен правим стіком, а не лише рискання.": "💡 YAW SKID: add right-stick roll in the turn instead of using yaw alone.",
	"ЛІВИЙ СТІК": "LEFT STICK",
	"ПРАВИЙ СТІК": "RIGHT STICK",
	"СТАРТ": "START",
	"МАЯК ВИСІННЯ": "HOVER BEACON",
	"ЗОНА СТІКІВ": "STICK CONTROL ZONE",
	"ВІКНО": "WINDOW",
	"ЗОНА ГАЛЬМУВАННЯ": "BRAKING ZONE",
	"МАЙДАНЧИК": "LANDING PAD",
	"СЛАЛОМ A": "SLALOM A",
	"СЛАЛОМ B": "SLALOM B",
	"НИЗЬКІ": "LOW GATE",
	"ВИСОКІ": "HIGH GATE",
	"ВОРОТА 1": "GATE 1",
	"ВІКНО 3.6x3.2": "WINDOW 3.6×3.2",
	"G — скид    F — активація БЧ    F6 — FPV-ефекти    R — респавн    M — режим": "G — DROP    F — DETONATE WARHEAD    F6 — FPV EFFECTS    R — RESPAWN    M — MODE",
	"НЕ БОЙОВИЙ ДРОН — БОЙОВИЙ СКИД ВІДСУТНІЙ": "NON-COMBAT AIRCRAFT — NO PAYLOAD DROP",
	"КАМІКАДЗЕ — СКИД ВІДСУТНІЙ (ДЕТОНАЦІЯ ПРИ УДАРІ)": "KAMIKAZE AIRCRAFT — NO DROP (WARHEAD DETONATES ON IMPACT)",
	"СПОЧАТКУ УВІМКНІТЬ ДВИГУНИ (ПРОБІЛ)": "ARM THE MOTORS FIRST (SPACE)",
	"НЕМАЄ БОЄПРИПАСІВ — R ДЛЯ ПЕРЕЗАРЯДКИ": "NO PAYLOAD LEFT — PRESS R TO REARM",
	"УДАР КАМІКАДЗЕ!": "KAMIKAZE IMPACT!",
	"ДРОН ВТРАЧЕНО — РЕСПАВН": "DRONE LOST — RESPAWNING",
	"ДРОН ВТРАЧЕНО — ПОВТОРНИЙ ВИЛІТ": "DRONE LOST — RESPAWNING",
	"СКИД: -%.2f кг (ТЯГА ЗРОСЛА)": "PAYLOAD DROP: -%.2f kg (THRUST INCREASED)",
	"ОКРЕМІ ВИЛЬОТИ ПОЗА КАМПАНІЄЮ": "STANDALONE SORTIES OUTSIDE THE CAMPAIGN",
	" НАЗАД": " BACK",
	"ТАКТИЧНИЙ FPV-СИМУЛЯТОР  •  МОБІЛЬНИЙ ТЕРМІНАЛ": "TACTICAL FPV SIMULATOR  •  MOBILE OPERATIONS TERMINAL",
	"ТАКТИЧНИЙ FPV-СИМУЛЯТОР": "TACTICAL FPV SIMULATOR",
	"ВХІД: СЕНСОР": "INPUT: TOUCH",
	"ОДИНОЧНА ГРА": "SINGLE PLAYER",
	"ПУЛЬТ ТА ELRS": "CONTROLLER & ELRS",
	"РЕЙТИ ТА ЕКСПО": "RATES & EXPO",
	"АНГАР ДРОНІВ": "AIRCRAFT HANGAR",
	"НАЛАШТУВАННЯ": "SETTINGS",
	"ПРОДОВЖИТИ ПОЛІТ": "RESUME FLIGHT",
	"ОНОВЛЕННЯ // СПИСОК ЗМІН": "UPDATES // CHANGELOG",
	"• Траса тренування: пройдіть 6 воріт на ★ / S–B (з Привидом)": "• Training course: clear 6 gates for ★ / S–B (with Ghost)",
	"• Режими: Туторіал (м’яка Angle) → Тренування → Бойовий": "• Modes: Tutorial (gentle Angle) → Training → Combat",
	"• Пресети Xbox / PS / MFi / USB-C ELRS, UA/EN та Safe Area": "• Xbox / PS / MFi / USB-C ELRS presets, UA/EN, and safe areas",
	"ВИХІД З ГРИ": "QUIT GAME",
	"ТАКТИЧНИЙ 8–10\"": "TACTICAL 8–10\"",
	"ПОПЕРЕДНІЙ": "PREVIOUS",
	"НАСТУПНИЙ": "NEXT",
	"НАЛАШТУВАННЯ ПУЛЬТА ТА СТІКІВ": "CONTROLLER & STICK SETUP",
	"Канали AETR/TAER, інверсія, калібрування та тумблери": "AETR/TAER channels, inversion, calibration, and switches",
	"ELRS: ПОШУК": "ELRS: SEARCHING",
	"ELRS: ПОТІК": "ELRS: STREAMING",
	"ВХІД: ELRS (POCKET)": "INPUT: ELRS (POCKET)",
	"ELRS: ВИМК.": "ELRS: OFF",
	"ПУЛЬТ RADIOMASTER TX12 (MODE 2)": "RADIOMASTER TX12 CONTROLLER (MODE 2)",
	"ГАЗ: 0%  •  РИСКАННЯ: +0%  •  ТАНГАЖ: +0%  •  КРЕН: +0%": "THROTTLE: 0%  •  YAW: +0%  •  PITCH: +0%  •  ROLL: +0%",
	"Стіки мають досягати 100% у кутах та повертатися в 0%": "Sticks should reach 100% at the corners and return to 0% at centre",
	"КАЛІБРУВАТИ СТІКИ": "CALIBRATE STICKS",
	"Мертва зона: 2%": "Deadzone: 2%",
	"Згладжування: 0.10": "Smoothing: 0.10",
	"ОСНОВНІ КАНАЛИ СТІКІВ": "PRIMARY STICK CHANNELS",
	"КРЕН (ROLL)": "ROLL",
	"ТАНГАЖ (PITCH)": "PITCH",
	"ГАЗ (THROTTLE)": "THROTTLE",
	"РИСКАННЯ (YAW)": "YAW",
	"АВТО": "AUTO",
	"ІНВЕРТ": "INVERT",
	"ДИЗАРМ": "DISARM",
	"БОЙОВІ ФУНКЦІЇ, СКИД ТА ПІДРИВ": "PAYLOAD & WARHEAD ACTIONS",
	"АРМУВАННЯ ДВИГУНІВ (ARM)": "ARM MOTORS",
	"СКИД БОЄПРИПАСУ (DROP)": "DROP PAYLOAD",
	"ПІДРИВ ДРОНА / БЧ (DETONATE)": "DRONE / WARHEAD DETONATION",
	"РЕЖИМИ ПОЛЬОТУ ТА АСИСТЕНТИ": "FLIGHT MODES & ASSISTS",
	"ЦИКЛ РЕЖИМІВ (CYCLE MODES)": "CYCLE FLIGHT MODES",
	"РЕЖИМ TURTLE (ПЕРЕВЕРТАННЯ)": "TURTLE MODE",
	"РЕЖИМ ANGLE (СТАБІЛІЗАЦІЯ)": "ANGLE MODE (SELF-LEVEL)",
	"РЕЖИМ HORIZON (ГОРИЗОНТ+АКРО)": "HORIZON MODE (ANGLE + ACRO)",
	"УТРИМАННЯ ВИСОТИ (ASSIST)": "ALTITUDE HOLD (ASSIST)",
	"СИСТЕМНІ ТА ОПТИЧНІ ТУМБЛЕРИ": "SYSTEM & OPTICS SWITCHES",
	"ВІДЕО / ПНБ / ТЕПЛОВІЗОР": "VIDEO / NVG / THERMAL",
	"ШВИДКИЙ РЕСПАВН (RESPAWN)": "QUICK RESPAWN",
	"ЗМІНА ПОГОДИ / ВІТЕР": "WEATHER / WIND",
	"МЕНЮ ПАУЗИ (PAUSE)": "PAUSE MENU",
	"ПЕРЕМИКАННЯ OSD (HUD)": "TOGGLE OSD (HUD)",
	"РЕЙТИ ТА ЕКСПОНЕНТА (BETAFLIGHT)": "RATES & EXPO (BETAFLIGHT)",
	"КРИВА ВІДГУКУ СТІКІВ": "STICK RESPONSE CURVE",
	"ГОТОВІ ПРЕСЕТИ РЕЙТІВ": "RATE PRESETS",
	"🎓 ТРЕНУВАННЯ": "🎓 TRAINING",
	"⚡ ФРІСТАЙЛ": "⚡ FREESTYLE",
	"🏁 ГОНКИ": "🏁 RACING",
	"🎬 КІНОДРОН": "🎬 CINEMATIC",
	"✓  ЗБЕРЕГТИ РЕЙТИ ДЛЯ ПОЛЬОТУ": "✓ SAVE FLIGHT RATES",
	"✓  ЗБЕРЕЖЕНО!": "✓ SAVED!",
	"Оберіть борт для бойових завдань та тренувань": "Select an aircraft for combat sorties and training",
	"«ГРІМ-7»": "GRIM-7",
	"«ГРІМ-7М»": "GRIM-7M",
	"«СТРІЛА-8»": "STRILA-8",
	"«КВАД-5»": "QUAD-5",
	"«СОКІЛ»": "SOKIL",
	"«БАБА ЯГА»": "BABA YAGA",
	"«ЛЕЛЕКА-100»": "LELEKA-100",
	"«ФУРІЯ» A1-СМ": "FURIA A1-SM",
	"«ЧАКЛУН JET»": "CHAKLUN JET",
	"ТАКТИЧНИЙ + СКИД": "TACTICAL + DROP",
	"ПЕРЕХОПЛЮВАЧ 8\"": "8\" INTERCEPTOR",
	"ШВИДКІСНИЙ FPV 5\"": "HIGH-SPEED 5\" FPV",
	"ТАКТИЧНИЙ БПЛА 8–10″": "TACTICAL 8–10\" UAV",
	"ВАЖКИЙ ГЕКСАКОПТЕР 6×": "HEAVY 6-ROTOR HEXACOPTER",
	"РОЗВІДУВАЛЬНИЙ БПЛА 2 М": "2 m RECON UAV",
	"ЛІТАЮЧЕ КРИЛО 2 М": "2 m FLYING WING",
	"РЕАКТИВНИЙ ПЕРЕХОПЛЮВАЧ": "JET INTERCEPTOR",
	"НАЛАШТУВАННЯ ТА СИМУЛЯЦІЯ": "SETTINGS & SIMULATION",
	"СИМУЛЯЦІЯ ТА РЕБ": "SIMULATION & EW",
	"ГРАФІКА ТА FPS": "GRAPHICS & FPS",
	"ЗВУК ТА СИСТЕМА": "AUDIO & SYSTEM",
	"ТРЕНАЖЕР / СИМУЛЯЦІЯ РЕАЛІЗМУ": "TRAINING / REALISM SIMULATION",
	"Полегшення та фізика діють одразу під час польоту": "Aids and physics settings apply immediately in flight",
	"Профіль реалізму:": "Realism profile:",
	"АРКАДА (ПОЛЕГШЕНА)": "ARCADE (ASSISTED)",
	"БОЙОВИЙ РЕАЛІЗМ": "COMBAT REALISM",
	"Обмеження зв'язку (дальність/рельєф)": "Link limits (range/terrain)",
	"Зони РЕБ (глушіння)": "EW zones (jamming)",
	"СЕНСОРНЕ КЕРУВАННЯ (TOUCH)": "TOUCH CONTROLS",
	"Плаваючий стік": "Floating stick",
	"Авто-центр газу (Angle)": "Throttle spring (Angle mode)",
	"Режим пульта (вимкнути сенсорні стіки)": "Controller mode (disable touch sticks)",
	"Чутливість сенсора:": "Touch sensitivity:",
	"Експо сенсора:": "Touch expo:",
	"ЕЛЕМЕНТИ БОЙОВОГО ТА ПОЛЬОТНОГО ІНТЕРФЕЙСУ (HUD / OSD)": "FLIGHT & COMBAT HUD / OSD",
	"Лічильник FPS:": "FPS counter:",
	"СКИНУТИ HUD ДО СТАНДАРТНИХ": "RESET HUD TO DEFAULTS",
	"ГРАФІКА ТА ОПТИМІЗАЦІЯ ДЛЯ IPHONE 14": "GRAPHICS & OPTIMIZATION FOR IPHONE 14",
	"1. НИЗЬКА (120+ FPS)": "1. LOW (120+ FPS)",
	"2. СЕРЕДНЯ (БАЛАНС)": "2. MEDIUM (BALANCED)",
	"3. ВИСОКА (МАКСИМУМ)": "3. HIGH (MAXIMUM)",
	"FPV-канал (відеолінк):": "FPV channel (video link):",
	"Аналог 5.8 GHz": "Analog 5.8 GHz",
	"Масштаб роздільності:": "Render scale:",
	"Якість тіней:": "Shadow quality:",
	"Згладжування (MSAA):": "Anti-aliasing (MSAA):",
	"FPV-об'єктив (риб'яче око):": "FPV lens (fisheye):",
	"Обмеження FPS:": "FPS cap:",
	"Вертикальна синхронізація (V-Sync):": "Vertical sync (V-Sync):",
	"СКИНУТИ ГРАФІКУ ДО СТАНДАРТНИХ": "RESET GRAPHICS TO DEFAULTS",
	"ВИМК. (-)": "OFF (-)",
	"5. «СОКІЛ» VTOL": "5. SOKIL VTOL",
	"6. Тактичний БПЛА (Полігон / Скид)": "6. Tactical UAV (Range / Payload Drop)",
	"Швидкісне перехоплення БПЛА": "High-speed UAV interception",
	"Реалізм:": "Realism:",
	"АРКАДА": "ARCADE",
	"Бойовий": "Combat",
	"БОЙОВИЙ": "COMBAT",
	"Вплив вітру": "Wind effects",
	"Зони РЕБ": "EW zones",
	"Обмеження зв’язку та батареї": "Link and battery limits",
	"Аркада: штиль, без РЕБ, запас батареї та чисті 100% зв’язку.": "Arcade: calm conditions, no EW, extra battery reserve, and a stable 100% link.",
	"БОЙОВЕ ЗАВДАННЯ: [ TAC-01 ] ПІХОТА В УКРИТТЯХ": "MISSION BRIEFING: [TAC-01] INFANTRY IN COVER",
	"[ БОЙОВА ОПЕРАЦІЯ ЗСУ ]": "[ AFU COMBAT OPERATION ]",
	"ОПЕРАЦІЯ: ...  •  СЕКТОР: ...": "OPERATION: ...  •  SECTOR: ...",
	"←  Назад до меню": "←  Back to menu",
	"▶  ПІДТВЕРДИТИ ТА ПОЧАТИ ВИЛІТ": "▶  CONFIRM & LAUNCH SORTIE"
}

# Authentic Military Tactical C2 Palette (Olive-Drab / Field Black / Tactical Amber)
const BG := Color("080f0c")
const BG_2 := Color("0d1711")
const PANEL := Color("101a14")
const PANEL_HEADER := Color("17221a")
const CARD := Color("111a15")
const CARD_HOVER := Color("1b2b20")
const CARD_ACTIVE := Color("5f9078")
const BORDER := Color("36463c")
const BORDER_HIGHLIGHT := Color("7ca88c")
const TEXT := Color("f1f3ee")
const MUTED := Color("a2aca4")
const ACCENT := Color("79a58a")
const ACCENT_DEEP := Color("1b3527")
const MIL_GREEN := Color("618b72")
const MIL_GREEN_LIGHT := Color("a9c6b2")
const WARN_AMBER := Color("e2c276")
const DANGER := Color("c96f67")
const BUTTON_BG := Color("eef0eb")
const BUTTON_HOVER := Color("ffffff")
const BUTTON_ACTIVE := Color("5f9078")
const BUTTON_TEXT := Color("172019")
const BUTTON_ACTIVE_TEXT := Color("ffffff")

# Modern UFDS (Ukrainian Fight Drone Simulator) Cyber-Military Aesthetics
const UFDS_BG := Color("0a0f16")           # Stealth Aerospace Navy-Black
const UFDS_BG_CARD := Color("0e1622")      # Translucent Dark Glass Card
const UFDS_PANEL := Color("121b28")        # Heavy Armor Module Panel
const UFDS_PANEL_HEADER := Color("172334") # Header Strip
const UFDS_BORDER := Color("23354a")       # Precision Steel Border
const UFDS_BORDER_GLOW := Color("00d4ff")  # Electric Cyan Outline
const UFDS_CYAN := Color("00d4ff")         # High-Tech Cyber Cyan
const UFDS_AMBER := Color("f59e0b")        # Tactical Alert Gold
const UFDS_GREEN := Color("10b981")        # Operational Status Emerald
const UFDS_RED := Color("ef4444")          # Danger / Hostile Red

# Feel FPV Modern Minimalist Unified Palette
const FPV_BG := Color("080f0c")
const FPV_BG_CARD := Color("111a15")
const FPV_BG_ACTIVE := Color("20372a")
const FPV_PANEL := Color("0b120e")
const FPV_PANEL_HEADER := Color("141f17")
const FPV_BORDER := Color("304139")
const FPV_BORDER_ACTIVE := Color("79a58a")
const FPV_BLUE := Color("618f76")
const FPV_CYAN := Color("a7c4af")
const FPV_AMBER := Color("e2c276")
const FPV_GREEN := Color("79a58a")
const FPV_RED := Color("c96f67")
const FPV_TEXT := Color("f1f3ee")
const FPV_MUTED := Color("a2aca4")

static var _theme: Theme = null


static func is_english() -> bool:
	return LocScript.get_language() == LocScript.Language.EN


static func translate_text(text: String) -> String:
	if is_english():
		return str(EN_TEXT.get(text, text))
	for source in EN_TEXT.keys():
		if str(EN_TEXT[source]) == text:
			return str(source)
	return text


static func localize_tree(root: Node) -> void:
	if root == null:
		return
	if root is ScrollContainer and is_mobile_ui():
		# Keyboard/gamepad focus moves the active control into view, and the
		# visible themed scrollbar lets a finger drag the list directly.
		(root as ScrollContainer).follow_focus = true
	if root is OptionButton:
		var option := root as OptionButton
		for i in range(option.item_count):
			option.set_item_text(i, translate_text(option.get_item_text(i)))
	if root is Button:
		var button := root as Button
		button.text = translate_text(button.text)
		if not button.tooltip_text.is_empty():
			button.tooltip_text = translate_text(button.tooltip_text)
	elif root is Label:
		var label := root as Label
		label.text = translate_text(label.text)
	elif root is RichTextLabel:
		var rich := root as RichTextLabel
		rich.text = translate_text(rich.text)
	elif root is LineEdit:
		var line_edit := root as LineEdit
		if not line_edit.placeholder_text.is_empty():
			line_edit.placeholder_text = translate_text(line_edit.placeholder_text)
	for child in root.get_children():
		localize_tree(child)


class _TacticalBackdrop extends Control:
	var base_color: Color = BG
	var show_c2_chrome: bool = true

	func _init(c: Color = BG, chrome: bool = true) -> void:
		base_color = c
		show_c2_chrome = chrome
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var sz := size
		if sz.x <= 4.0 or sz.y <= 4.0:
			return
		# 1. Base fill
		draw_rect(Rect2(Vector2.ZERO, sz), base_color, true)

		var is_feel := (base_color == FPV_BG or (base_color.r < 0.05 and base_color.b > 0.07))
		if is_feel or not show_c2_chrome:
			# Pure, clean, elegant studio vignette - zero grid clutter!
			var center := Vector2(sz.x * 0.65, sz.y * 0.46)
			for r_step in [0.75, 0.55, 0.35]:
				draw_circle(center, sz.y * r_step, Color(0.02, 0.45, 0.85, 0.015))
			return

		var is_ufds := (base_color == UFDS_BG or (base_color.r < 0.08 and base_color.b > 0.07))

		# 2. Minor MGRS / Cyber tactical grid (40px cells)
		var minor_col := Color(0.0, 0.72, 0.95, 0.05) if is_ufds else Color(0.28, 0.42, 0.22, 0.08)
		var major_col := Color(0.0, 0.83, 1.0, 0.12) if is_ufds else Color(0.36, 0.54, 0.28, 0.17)
		var step := 40.0
		var x := step
		var ix := 1
		while x < sz.x:
			var is_maj := (ix % 4 == 0)
			draw_line(Vector2(x, 0.0), Vector2(x, sz.y), major_col if is_maj else minor_col, 1.0)
			x += step
			ix += 1
		var y := step
		var iy := 1
		while y < sz.y:
			var is_maj := (iy % 4 == 0)
			draw_line(Vector2(0.0, y), Vector2(sz.x, y), major_col if is_maj else minor_col, 1.0)
			y += step
			iy += 1

		# 3. Tactical '+' calibration crosses at major 160px intersections
		var cross_col := Color(0.0, 0.83, 1.0, 0.24) if is_ufds else Color(0.55, 0.76, 0.44, 0.24)
		var cx := 160.0
		while cx < sz.x - 40.0:
			var cy := 160.0
			while cy < sz.y - 40.0:
				draw_line(Vector2(cx - 4.0, cy), Vector2(cx + 4.0, cy), cross_col, 1.0)
				draw_line(Vector2(cx, cy - 4.0), Vector2(cx, cy + 4.0), cross_col, 1.0)
				cy += 160.0
			cx += 160.0

		# 4. Subtle C2 / Aerospace radar range rings & azimuth crosshairs in background
		var radar_c := Vector2(sz.x * 0.72, sz.y * 0.52)
		var ring_col := Color(0.0, 0.83, 1.0, 0.08) if is_ufds else Color(0.38, 0.58, 0.30, 0.11)
		for r in [140.0, 260.0, 380.0, 500.0]:
			draw_arc(radar_c, r, 0.0, TAU, 64, ring_col, 1.2)
		draw_line(radar_c - Vector2(540.0, 0.0), radar_c + Vector2(540.0, 0.0), ring_col, 1.0)
		draw_line(radar_c - Vector2(0.0, 540.0), radar_c + Vector2(0.0, 540.0), ring_col, 1.0)

		if not show_c2_chrome:
			return

		# 5. Outer armored perimeter frame & L-brackets
		var pad := 10.0
		var frame_rect := Rect2(Vector2(pad, pad), sz - Vector2(pad * 2.0, pad * 2.0))
		draw_rect(frame_rect, Color(0.14, 0.21, 0.29, 0.65) if is_ufds else Color(0.26, 0.38, 0.21, 0.55), false, 1.0)

		var br_len := 28.0
		var br_col := UFDS_AMBER if is_ufds else Color(0.92, 0.69, 0.21, 0.80)
		var tl := frame_rect.position
		var tr := Vector2(frame_rect.end.x, frame_rect.position.y)
		var bl := Vector2(frame_rect.position.x, frame_rect.end.y)
		var br := frame_rect.end
		# Top-Left bracket
		draw_line(tl, tl + Vector2(br_len, 0.0), br_col, 2.5)
		draw_line(tl, tl + Vector2(0.0, br_len), br_col, 2.5)
		# Top-Right bracket
		draw_line(tr, tr + Vector2(-br_len, 0.0), br_col, 2.5)
		draw_line(tr, tr + Vector2(0.0, br_len), br_col, 2.5)
		# Bottom-Left bracket
		draw_line(bl, bl + Vector2(br_len, 0.0), br_col, 2.5)
		draw_line(bl, bl + Vector2(0.0, -br_len), br_col, 2.5)
		# Bottom-Right bracket
		draw_line(br, br + Vector2(-br_len, 0.0), br_col, 2.5)
		draw_line(br, br + Vector2(0.0, -br_len), br_col, 2.5)

		# Top azimuth compass scale ticks along center top edge
		var mid_x := sz.x * 0.5
		var tick_col := Color(0.0, 0.83, 1.0, 0.35) if is_ufds else Color(0.58, 0.76, 0.48, 0.38)
		for t_i in range(-12, 13):
			var tx := mid_x + float(t_i) * 24.0
			var th := 7.0 if (t_i % 4 == 0) else 4.0
			draw_line(Vector2(tx, pad), Vector2(tx, pad + th), tick_col, 1.2)


static func _style(bg: Color, border: Color, border_w: int, radius: int,
		pad_x: int = 18, pad_y: int = 12, left_accent: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	if left_accent >= 0:
		sb.border_width_left = left_accent
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## True on iOS/Android, or when a desktop QA run asks for the phone skin.
## The PC layout and the phone layout intentionally use separate styles.
static func is_mobile_ui() -> bool:
	return OS.has_feature("mobile") or OS.has_environment("MOBILE_UI")


## Empty space between the screen edge and any tappable control.  Around 3%
## of the short side keeps thumbs away from the display edge on phones.
static func mobile_safe_margin(viewport_size: Vector2) -> float:
	return maxf(32.0, minf(viewport_size.x, viewport_size.y) * 0.06)


## Display safe-area margins (`left`, `top`, `right`, `bottom`) scaled into
## `viewport_size` (or current window size when omitted) from DisplayServer.
static func get_safe_margins(viewport_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		win = DisplayServer.screen_get_size()
	if win.x <= 0 or win.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var target := viewport_size if viewport_size.x > 0.0 and viewport_size.y > 0.0 else Vector2(win)
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var sx := target.x / float(win.x)
	var sy := target.y / float(win.y)
	return {
		"left": maxf(0.0, float(safe.position.x) * sx),
		"top": maxf(0.0, float(safe.position.y) * sy),
		"right": maxf(0.0, float(win.x - safe.end.x) * sx),
		"bottom": maxf(0.0, float(win.y - safe.end.y) * sy),
	}


## Camera notch / rounded-corner insets, converted from screen pixels into the
## current viewport.  In sensor-landscape the notch can end up on either side.
static func mobile_notch_insets(viewport_size: Vector2) -> Vector4:
	if not is_mobile_ui():
		return Vector4.ZERO
	var safe := get_safe_margins(viewport_size)
	return Vector4(
		float(safe["left"]),
		float(safe["top"]),
		float(safe["right"]),
		float(safe["bottom"]))


## Base breathing room plus the notch/home-indicator safe area.
static func mobile_edge_margins(viewport_size: Vector2) -> Vector4:
	var base := mobile_safe_margin(viewport_size)
	var notch := mobile_notch_insets(viewport_size)
	# Reserve the cutout symmetrically.  This keeps the layout safe after the
	# phone is rotated 180° and the notch swaps sides, without rebuilding every
	# screen on an orientation change.
	var horizontal := maxf(notch.x, notch.z)
	var vertical := maxf(notch.y, notch.w)
	return Vector4(base + horizontal, base + vertical,
			base + horizontal, base + vertical)


## Soft cut-off for a scrolling card list.  Keeps a half-visible row from
## looking like a layout bug at the bottom edge of the viewport.
static func bottom_fade(color: Color, height: int = 48) -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.97),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = maxi(16, height)
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var font := load(FONT_PATH)
	if font != null:
		t.default_font = font
	t.default_font_size = 19

	# Paper-white buttons, sage selection, and a narrow state stripe.
	t.set_stylebox("normal", "Button", _style(BUTTON_BG, BORDER, 1, 1, 16, 10, 4))
	t.set_stylebox("hover", "Button", _style(BUTTON_HOVER, ACCENT, 2, 1, 16, 10, 5))
	t.set_stylebox("pressed", "Button", _style(BUTTON_ACTIVE, ACCENT, 2, 1, 16, 10, 5))
	t.set_stylebox("focus", "Button", _style(BUTTON_HOVER, ACCENT, 2, 1, 16, 10, 5))
	t.set_stylebox("disabled", "Button", _style(PANEL, BORDER, 1, 1, 16, 10, 2))
	t.set_color("font_color", "Button", BUTTON_TEXT)
	t.set_color("font_hover_color", "Button", BUTTON_TEXT)
	t.set_color("font_pressed_color", "Button", BUTTON_ACTIVE_TEXT)
	t.set_color("font_focus_color", "Button", BUTTON_TEXT)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", 19)

	t.set_stylebox("panel", "PanelContainer", _style(PANEL, BORDER, 2, 3, 20, 18, 4))
	t.set_stylebox("panel", "Panel", _style(PANEL, BORDER, 2, 3, 20, 18, 4))

	t.set_stylebox("normal", "OptionButton", _style(BUTTON_BG, BORDER, 1, 1, 14, 8, 4))
	t.set_stylebox("hover", "OptionButton", _style(BUTTON_HOVER, ACCENT, 1, 1, 14, 8, 4))
	t.set_stylebox("pressed", "OptionButton", _style(BUTTON_ACTIVE, ACCENT, 1, 1, 14, 8, 4))
	t.set_stylebox("focus", "OptionButton", _style(BUTTON_HOVER, ACCENT, 1, 1, 14, 8, 4))
	t.set_color("font_color", "OptionButton", BUTTON_TEXT)
	t.set_color("font_hover_color", "OptionButton", BUTTON_TEXT)
	t.set_font_size("font_size", "OptionButton", 17)

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 19)

	t.set_stylebox("slider", "HSlider", _style(Color("070b07"), BORDER, 1, 2, 4, 4))
	t.set_stylebox("grabber_area", "HSlider", _style(MIL_GREEN, MIL_GREEN_LIGHT, 1, 2, 4, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _style(WARN_AMBER, WARN_AMBER, 1, 2, 4, 4))

	t.set_stylebox("normal", "CheckButton", _style(BUTTON_BG, BORDER, 1, 1, 14, 8, 4))
	t.set_stylebox("hover", "CheckButton", _style(BUTTON_HOVER, ACCENT, 2, 1, 14, 8, 4))
	t.set_stylebox("pressed", "CheckButton", _style(BUTTON_ACTIVE, ACCENT, 2, 1, 14, 8, 4))
	t.set_stylebox("focus", "CheckButton", _style(BUTTON_HOVER, ACCENT, 2, 1, 14, 8, 4))
	t.set_color("font_color", "CheckButton", BUTTON_TEXT)
	t.set_color("font_hover_color", "CheckButton", BUTTON_TEXT)
	t.set_color("font_pressed_color", "CheckButton", BUTTON_ACTIVE_TEXT)
	t.set_font_size("font_size", "CheckButton", 18)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font_size("font_size", "CheckBox", 18)

	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_font_size("font_size", "RichTextLabel", 19)
	if is_mobile_ui():
		_apply_mobile_theme(t)
	_theme = t
	return t


## Phone skin: the same olive/sage/amber language as the mobile operations
## shell.  PC menus keep the original paper-white controls.
static func _apply_mobile_theme(t: Theme) -> void:
	var panel_bg := Color(0.025, 0.060, 0.048, 0.92)
	var border := Color(0.30, 0.44, 0.36, 0.60)
	var button_bg := Color(0.040, 0.080, 0.065, 0.90)
	var button_hover := Color(0.080, 0.150, 0.110, 0.98)
	var active_bg := Color(0.62, 0.74, 0.55, 1.0)
	var active_text := Color(0.06, 0.09, 0.07)

	t.default_font_size = 22

	t.set_stylebox("normal", "Button", _style(button_bg, border, 1, 12, 18, 12))
	t.set_stylebox("hover", "Button", _style(button_hover, FPV_GREEN, 1, 12, 18, 12))
	t.set_stylebox("pressed", "Button", _style(active_bg, Color(0.75, 0.85, 0.65, 0.95), 1, 12, 18, 12))
	t.set_stylebox("focus", "Button", _style(button_hover, FPV_GREEN, 1, 12, 18, 12))
	t.set_stylebox("disabled", "Button", _style(Color(0.03, 0.05, 0.04, 0.62), Color(0.22, 0.30, 0.25, 0.5), 1, 12, 18, 12))
	t.set_color("font_color", "Button", FPV_TEXT)
	t.set_color("font_hover_color", "Button", FPV_TEXT)
	t.set_color("font_pressed_color", "Button", active_text)
	t.set_color("font_focus_color", "Button", FPV_TEXT)
	t.set_color("font_disabled_color", "Button", FPV_MUTED)
	t.set_font_size("font_size", "Button", 22)

	t.set_stylebox("panel", "PanelContainer", _style(panel_bg, border, 1, 16, 22, 18))
	t.set_stylebox("panel", "Panel", _style(panel_bg, border, 1, 16, 22, 18))

	t.set_stylebox("normal", "OptionButton", _style(button_bg, border, 1, 12, 16, 10))
	t.set_stylebox("hover", "OptionButton", _style(button_hover, FPV_GREEN, 1, 12, 16, 10))
	t.set_stylebox("pressed", "OptionButton", _style(active_bg, Color(0.75, 0.85, 0.65, 0.95), 1, 12, 16, 10))
	t.set_stylebox("focus", "OptionButton", _style(button_hover, FPV_GREEN, 1, 12, 16, 10))
	t.set_color("font_color", "OptionButton", FPV_TEXT)
	t.set_color("font_hover_color", "OptionButton", FPV_TEXT)
	t.set_color("font_pressed_color", "OptionButton", active_text)
	t.set_font_size("font_size", "OptionButton", 20)

	t.set_color("font_color", "Label", FPV_TEXT)
	t.set_font_size("font_size", "Label", 22)
	t.set_color("font_color", "RichTextLabel", FPV_TEXT)
	t.set_font_size("font_size", "RichTextLabel", 22)

	t.set_stylebox("slider", "HSlider", _style(Color(0.02, 0.04, 0.032, 0.92), border, 1, 4, 6, 8))
	t.set_stylebox("grabber_area", "HSlider", _style(Color(0.38, 0.56, 0.43, 1.0), FPV_GREEN, 1, 4, 6, 8))
	t.set_stylebox("grabber_area_highlight", "HSlider", _style(FPV_AMBER, FPV_AMBER, 1, 4, 6, 8))

	t.set_stylebox("normal", "CheckButton", _style(button_bg, border, 1, 12, 16, 10))
	t.set_stylebox("hover", "CheckButton", _style(button_hover, FPV_GREEN, 1, 12, 16, 10))
	t.set_stylebox("pressed", "CheckButton", _style(Color(0.10, 0.22, 0.15, 1.0), FPV_GREEN, 1, 12, 16, 10))
	t.set_stylebox("focus", "CheckButton", _style(button_hover, FPV_GREEN, 1, 12, 16, 10))
	t.set_color("font_color", "CheckButton", FPV_TEXT)
	t.set_color("font_hover_color", "CheckButton", FPV_TEXT)
	t.set_color("font_pressed_color", "CheckButton", FPV_TEXT)
	t.set_font_size("font_size", "CheckButton", 21)
	t.set_color("font_color", "CheckBox", FPV_TEXT)
	t.set_color("font_hover_color", "CheckBox", FPV_TEXT)
	t.set_color("font_pressed_color", "CheckBox", FPV_TEXT)
	t.set_font_size("font_size", "CheckBox", 21)
	t.set_stylebox("normal", "CheckBox", _style(button_bg, border, 1, 10, 12, 8))
	t.set_stylebox("hover", "CheckBox", _style(button_hover, FPV_GREEN, 1, 10, 12, 8))
	t.set_stylebox("pressed", "CheckBox", _style(Color(0.10, 0.22, 0.15, 1.0), FPV_GREEN, 1, 10, 12, 8))
	t.set_stylebox("focus", "CheckBox", _style(button_hover, FPV_GREEN, 1, 10, 12, 8))

	t.set_stylebox("normal", "LineEdit", _style(Color(0.02, 0.05, 0.04, 0.96), border, 1, 10, 14, 10))
	t.set_stylebox("focus", "LineEdit", _style(Color(0.04, 0.09, 0.07, 1.0), FPV_GREEN, 1, 10, 14, 10))
	t.set_color("font_color", "LineEdit", FPV_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", FPV_MUTED)
	t.set_color("caret_color", "LineEdit", FPV_GREEN)
	t.set_font_size("font_size", "LineEdit", 21)

	t.set_stylebox("panel", "PopupMenu", _style(panel_bg, border, 1, 12, 14, 10))
	t.set_stylebox("hover", "PopupMenu", _style(Color(0.10, 0.22, 0.15, 1.0), FPV_GREEN, 1, 8, 10, 8))
	t.set_color("font_color", "PopupMenu", FPV_TEXT)
	t.set_color("font_hover_color", "PopupMenu", FPV_TEXT)
	t.set_font_size("font_size", "PopupMenu", 20)

	t.set_stylebox("panel", "TooltipPanel", _style(panel_bg, FPV_AMBER, 1, 8, 10, 6))
	t.set_color("font_color", "TooltipLabel", FPV_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 17)

	# 14 px thumb + 4 px breathing room: a visible, finger-draggable scrollbar.
	t.set_stylebox("scroll", "VScrollBar", _style(Color(0.02, 0.04, 0.032, 0.55), Color(0, 0, 0, 0), 0, 7, 7, 0))
	t.set_stylebox("grabber", "VScrollBar", _style(Color(0.36, 0.50, 0.42, 0.92), Color(0, 0, 0, 0), 0, 7, 7, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _style(FPV_GREEN, Color(0, 0, 0, 0), 0, 7, 7, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _style(FPV_AMBER, Color(0, 0, 0, 0), 0, 7, 7, 0))
	t.set_stylebox("scroll", "HScrollBar", _style(Color(0.02, 0.04, 0.032, 0.55), Color(0, 0, 0, 0), 0, 7, 0, 7))
	t.set_stylebox("grabber", "HScrollBar", _style(Color(0.36, 0.50, 0.42, 0.92), Color(0, 0, 0, 0), 0, 7, 0, 7))
	t.set_stylebox("grabber_highlight", "HScrollBar", _style(FPV_GREEN, Color(0, 0, 0, 0), 0, 7, 0, 7))
	t.set_stylebox("grabber_pressed", "HScrollBar", _style(FPV_AMBER, Color(0, 0, 0, 0), 0, 7, 0, 7))


static func background(color: Color = BG, show_chrome: bool = true) -> Control:
	if is_mobile_ui():
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full_rect(holder)
		var bg := TextureRect.new()
		var tex := load("res://Assets/Branding/mobile_menu_bg_blur.png") as Texture2D
		if tex != null:
			bg.texture = tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full_rect(bg)
		holder.add_child(bg)
		var scrim := ColorRect.new()
		scrim.color = Color(0.012, 0.035, 0.026, 0.74)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full_rect(scrim)
		holder.add_child(scrim)
		return holder
	return _TacticalBackdrop.new(color, show_chrome)


static func title(text: String, size: int = 38) -> Label:
	var label := Label.new()
	var translated := translate_text(text)
	label.text = translated
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FPV_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_mobile_ui() \
			else HORIZONTAL_ALIGNMENT_CENTER
	return label


static func subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = translate_text(text)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MIL_GREEN_LIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_mobile_ui() \
			else HORIZONTAL_ALIGNMENT_CENTER
	return label


static func section(text: String, tag: String = "СЕКТОР") -> Control:
	if is_mobile_ui():
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 10)
		var mlabel := Label.new()
		mlabel.text = translate_text(text)
		mlabel.add_theme_font_size_override("font_size", 15)
		mlabel.add_theme_color_override("font_color", FPV_AMBER)
		mrow.add_child(mlabel)
		var mline := HSeparator.new()
		mline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var msb := StyleBoxFlat.new()
		msb.bg_color = FPV_BORDER
		msb.content_margin_top = 1
		mline.add_theme_stylebox_override("separator", msb)
		mrow.add_child(mline)
		return mrow

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var badge_panel := PanelContainer.new()
	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = FPV_BG_CARD
	b_sb.border_color = FPV_CYAN
	b_sb.border_width_left = 3
	b_sb.set_border_width_all(1)
	b_sb.border_width_left = 3
	b_sb.set_corner_radius_all(2)
	b_sb.content_margin_left = 7
	b_sb.content_margin_right = 7
	b_sb.content_margin_top = 2
	b_sb.content_margin_bottom = 2
	if is_mobile_ui():
		b_sb.bg_color = Color(0.36, 0.26, 0.10, 0.22)
		b_sb.border_color = FPV_AMBER
		b_sb.set_corner_radius_all(6)
		b_sb.content_margin_left = 10
		b_sb.content_margin_right = 10
		b_sb.content_margin_top = 3
		b_sb.content_margin_bottom = 3
	badge_panel.add_theme_stylebox_override("panel", b_sb)

	var badge := Label.new()
	badge.text = translate_text(tag)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", FPV_AMBER if is_mobile_ui() else FPV_CYAN)
	badge_panel.add_child(badge)
	row.add_child(badge_panel)

	var label := Label.new()
	label.text = translate_text(text)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT)
	row.add_child(label)

	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = FPV_BORDER
	sb.content_margin_top = 1
	line.add_theme_stylebox_override("separator", sb)
	row.add_child(line)

	return row


static func body(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = translate_text(text)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func button(text: String, min_height: float = 46.0,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Button:
	var b := Button.new()
	b.text = translate_text(text)
	if is_mobile_ui():
		# Keep every phone button finger-sized even when an old screen asks
		# for its desktop 38–46 px height.
		min_height = maxf(min_height, 58.0)
	b.custom_minimum_size = Vector2(0, min_height)
	b.alignment = align
	return b


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(240, 56 if is_mobile_ui() else 40)
	for item in items:
		o.add_item(translate_text(str(item)))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	return o


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hline() -> HSeparator:
	var line := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BORDER
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	line.add_theme_stylebox_override("separator", style)
	return line


static func full_rect(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


## Uniformly frames a 3D preview on a known display size and seats its lowest
## point at bottom_y. It uses mesh bounds in model-local space, so model yaw and
## non-zero GLB origins do not push the aircraft out of frame.
static func fit_preview_model(model: Node3D, target_size: float, bottom_y: float = 0.0) -> AABB:
	if model == null or not is_instance_valid(model) or target_size <= 0.0:
		return AABB()
	var root_inverse := model.global_transform.affine_inverse()
	var visuals: Array[VisualInstance3D] = []
	if model is VisualInstance3D:
		visuals.append(model as VisualInstance3D)
	for node in model.find_children("*", "VisualInstance3D", true, false):
		visuals.append(node as VisualInstance3D)
	if visuals.is_empty():
		return AABB()
	var local_bounds := AABB()
	var first := true
	for visual in visuals:
		var local_box: AABB = (root_inverse * visual.global_transform) * visual.get_aabb()
		if first:
			local_bounds = local_box
			first = false
		else:
			local_bounds = local_bounds.merge(local_box)
	if local_bounds.size.length_squared() < 0.000001:
		return AABB()
	var max_dimension := maxf(local_bounds.size.x, maxf(local_bounds.size.y, local_bounds.size.z))
	var factor := target_size / max_dimension
	var rotation_basis := model.transform.basis.orthonormalized()
	var local_center := local_bounds.get_center()
	var min_projected_y := INF
	for x in [local_bounds.position.x, local_bounds.end.x]:
		for y in [local_bounds.position.y, local_bounds.end.y]:
			for z in [local_bounds.position.z, local_bounds.end.z]:
				var offset := rotation_basis * (Vector3(x, y, z) * factor)
				min_projected_y = minf(min_projected_y, offset.y)
	model.scale = Vector3.ONE * factor
	var rotated_center: Vector3 = rotation_basis * (local_center * factor)
	model.position = Vector3(-rotated_center.x, bottom_y - min_projected_y, -rotated_center.z)
	model.force_update_transform()
	var result := AABB()
	first = true
	for visual in visuals:
		var world_box: AABB = visual.global_transform * visual.get_aabb()
		if first:
			result = world_box
			first = false
		else:
			result = result.merge(world_box)
	return result


static func ufds_style(bg: Color = UFDS_BG_CARD, border: Color = UFDS_BORDER,
		border_w: int = 1, radius: int = 4, pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func ufds_button(text: String, min_height: float = 42.0, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = translate_text(text)
	b.custom_minimum_size = Vector2(0, min_height)
	var bg := Color("182c3c") if primary else UFDS_BG_CARD
	var border := UFDS_CYAN if primary else UFDS_BORDER
	var border_hover := UFDS_CYAN if primary else UFDS_AMBER
	b.add_theme_stylebox_override("normal", ufds_style(bg, border, 2 if primary else 1, 4))
	b.add_theme_stylebox_override("hover", ufds_style(bg.lightened(0.08), border_hover, 2, 4))
	b.add_theme_stylebox_override("pressed", ufds_style(bg.lightened(0.15), border_hover, 2, 4))
	b.add_theme_stylebox_override("focus", ufds_style(bg.lightened(0.08), border_hover, 2, 4))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", UFDS_CYAN if primary else UFDS_AMBER)
	return b


# Feel FPV Modern Minimalist UI Components
static func feel_style(bg: Color = FPV_BG_CARD, border: Color = FPV_BORDER,
		border_w: int = 1, radius: int = 8, pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func feel_button(text: String, min_height: float = 38.0, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = translate_text(text)
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if is_mobile_ui():
		var mobile_bg := Color(0.62, 0.74, 0.55, 1.0) if primary else Color(0.04, 0.08, 0.065, 0.90)
		var mobile_hover := Color(0.70, 0.82, 0.62, 1.0) if primary else Color(0.08, 0.15, 0.11, 0.98)
		var mobile_text := Color(0.06, 0.09, 0.07) if primary else FPV_TEXT
		b.add_theme_stylebox_override("normal", feel_style(mobile_bg, FPV_GREEN if primary else FPV_BORDER, 2 if primary else 1, 12, 16, 10))
		b.add_theme_stylebox_override("hover", feel_style(mobile_hover, FPV_GREEN, 2, 12, 16, 10))
		b.add_theme_stylebox_override("pressed", feel_style(Color(0.10, 0.22, 0.15, 1.0), FPV_GREEN, 2, 12, 16, 10))
		b.add_theme_stylebox_override("focus", feel_style(mobile_hover, FPV_GREEN, 2, 12, 16, 10))
		b.add_theme_color_override("font_color", mobile_text)
		b.add_theme_color_override("font_hover_color", mobile_text)
		b.add_theme_color_override("font_pressed_color", FPV_TEXT)
		if min_height < 58.0:
			b.custom_minimum_size.y = 58.0
		return b
	var bg := BUTTON_ACTIVE if primary else BUTTON_BG
	var border := ACCENT if primary else FPV_BORDER
	b.add_theme_stylebox_override("normal", feel_style(bg, border, 2 if primary else 1, 1, 12, 6))
	b.add_theme_stylebox_override("hover", feel_style(BUTTON_HOVER if not primary else bg.lightened(0.08), ACCENT, 2, 1, 12, 6))
	b.add_theme_stylebox_override("pressed", feel_style(BUTTON_ACTIVE, ACCENT, 2, 1, 12, 6))
	b.add_theme_stylebox_override("focus", feel_style(BUTTON_HOVER if not primary else bg.lightened(0.08), ACCENT, 2, 1, 12, 6))
	b.add_theme_color_override("font_color", BUTTON_ACTIVE_TEXT if primary else BUTTON_TEXT)
	b.add_theme_color_override("font_hover_color", BUTTON_TEXT if not primary else BUTTON_ACTIVE_TEXT)
	if not b.mouse_entered.is_connected(b.grab_focus):
		b.mouse_entered.connect(b.grab_focus)
	return b


static func feel_section(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var dot := Label.new()
	dot.text = "•"
	dot.add_theme_font_size_override("font_size", 16)
	dot.add_theme_color_override("font_color", FPV_CYAN)
	row.add_child(dot)

	var label := Label.new()
	label.text = translate_text(text)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", FPV_TEXT)
	row.add_child(label)

	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = FPV_BORDER
	sb.content_margin_top = 1
	line.add_theme_stylebox_override("separator", sb)
	row.add_child(line)

	return row
