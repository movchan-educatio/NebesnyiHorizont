# Звіт v22 — виправлення за відео IMG_6820

Дата: 10.11.2026  
Платформа: iPhone / iPad (мобільна версія). PC-версія та PC-меню не змінювалися.

## 1. Що було на відео

Я прослухав аудіо та покадрово розібрав `IMG_6820.MP4`. Проблеми, які ти назвав:

1. **ARM не спрацьовував.** Натискання кнопки `АРМ` не армувало дрон; іноді здавалося, що кнопка «мертва».
2. **ARM перемикав режим польоту.** Замість армування з'являвся `TURTLE` / інший режим, і дрон перевертався.
3. **Режими перемикалися самі.** Під час польоту з пультом змінювався режим, хоча ти рухав тільки стіки.
4. **Меню паузи відкривалося під час керування.** У режимі `ВВІД: ПУЛЬТ` натискання на стіки/екран відкривало паузу.
5. **Дрон був дуже маленький** на головному екрані / в ангарі після першого відкриття. Після «Наступний → Попередній» він ставав нормальним.
6. **Меню паузи занадто мале** для телефона.

## 2. Причини та що виправлено

### 2.1. ARM: подвійна дія

`TouchControls._on_arm_pressed()` спочатку викликав `request_arm()` напряму, а потім **ще й** відправляв синтетичну дію `toggle_arm`. `Level._input()` бачив другу подію в тому ж кадрі та одразу викликав `request_disarm()`.

**Виправлено:** ARM тепер виконується рівно один раз, напряму через flight controller. Додано короткий статус `АРМ` / `ДИСАРМ` / `АРМ НЕ ДОЗВОЛЕНО`.

### 2.2. ARM більше не змінює режим

`FlightController.request_arm()` автоматично перемикав режим на `TURTLE` або `LAUNCH`, якщо відповідна дія була затиснута (наприклад, AUX-перемикачем пульта). Через це ARM виглядав як «перемикання режиму».

**Виправлено (мобільна версія):** ARM тільки армує. Вибір режиму — окрема кнопка `РЕЖИМ`. На PC стара поведінка залишена.

### 2.3. Самовільні режими та пауза з пульта

У `ElrsWifiInput` усі 16 AUX-каналів були за замовчуванням призначені на дії:

- CH8 — цикл режимів,
- CH9 — TURTLE,
- CH13 — респавн,
- CH14 — погода,
- **CH15 — пауза**.

На звичайному EdgeTX/ELRS-пульті ці канали — це перемикачі. Тому рух/перемикання на пульті міг поставити паузу, змінити режим або перевернути дрон.

**Виправлено:**

- За замовчуванням призначений **тільки ARM на CH5**.
- Усі необов'язкові дії (`пауза`, `TURTLE`, `режими`, `скид`, `погода`, `респавн`) вимкнені, доки їх явно не призначити в екрані `ПУЛЬТ ТА ELRS`.
- Додано міграцію старих профілів: старі автоматичні значення скидаються, а справжні користувацькі прив'язки зберігаються.
- Пауза більше ніколи не призначається на AUX-канал автоматично.

### 2.4. Дрон-«крапка» в ангарі

Модель GLB підключалася та одразу вимірювалася в тому ж кадрі. Пропелери/моторні вузли ще не встигали оновити трансформи, тому AABB виходив неправильним і всю модель масштабувало до розміру крапки. Після перемикання «Наступний → Попередній» модель перезавантажувалася вже з коректними трансформами.

**Виправлено:**

- Вимірювання та підгонка моделі тепер виконуються після двох кадрів, коли вузли вже в дереві.
- Додано страхувальний перерахунок: якщо модель усе ж вийшла меншою за 65% цільового розміру, вона масштабується до нормального розміру й ставиться на п'єдестал.
- Це стосується і головного екрана, і ангару.

### 2.5. Замале меню паузи

Стара картка була 640 одиниць завширшки (приблизно 27% кадру 1280 px), рядки — 54 одиниці.

**Виправлено:**

- Картка: **1180 одиниць**.
- Рядки: **84 одиниці**, шрифт **26**.
- Заголовок: **38**, шапка: **20**.
- Розміри враховують safe-area; на 1080 одиницях висоти меню повністю вміщується.

### 2.6. Як саме працює призначення кнопок пульта

Призначення зроблено не «на око», а через явну таблицю `action_channels` у `ElrsWifiInput`:

- У списку дій є **тільки CH5–CH16** (AUX-перемикачі). CH1–CH4 — це стіки, тому їх більше не можна випадково призначити на дію.
- Пункт `ВИМК.` має окремий службовий id (99), який перетворюється на `-1`. Раніше Godot трактував `-1` як «автоматичний id 0», через що вимкнути дію було неможливо.
- Якщо призначити дію на канал, який уже займає ARM, ARM автоматично переїжджає на перший вільний AUX-канал (наприклад, CH5 → CH6). Якщо призначити ARM на зайнятий канал, попередня дія знімається.
- Після кожної зміни всі рядки оновлюються, тому в екрані не залишається «старий» канал.
- `АВТО` ігнорує стіки (`aux_only = true`) і ловить саме зміну AUX-каналу.
- Зчитування каналів має гістерезис (14000/18000) і реагує лише на **зміну рівня**, а не на кожен пакет. Тому один перемикач не «строчить» дію багато разів.
- Старі профілі при завантаженні проходять перевірку: прибираються дії на CH1–CH4, дублікати каналів і розбіжність `arm`/`toggle_arm`.

Це саме те, що перевіряє `ACTION_BIND_QA` (deploy → CH8, ARM → CH10, конфлікт CH5 → ARM переїхав на CH6) і новий `VIDEOFIX` (прив'язка через випадаючий список на CH7 та реальне вимкнення дії).

### 2.7. Повернення з місії

Екран результатів `BigLevel._on_menu_pressed()` на телефоні вів на старий desktop `MainMenu`. Тепер на мобільній версії він веде на `MobileMenu`, а PC — як і раніше, на `MainMenu`.

Кнопки паузи (`ПУЛЬТ ТА КАЛІБРУВАННЯ`, `РЕЙТИ ТА ЕКСПО`, `НАЛАШТУВАННЯ`) відкривають реальні мобільні вкладки, а не неіснуючий метод.

## 3. Скріншоти

### Пауза: до / після

| До (відео) | Після (v22) |
|---|---|
| ![Пауза до](v22_fix/before_pause.png) | ![Пауза після](v22_fix/pause_1280.png) |

### Головний екран: маленький дрон / нормальний дрон

| До (відео) | Після (v22) |
|---|---|
| ![Дрон до](v22_fix/before_tiny_drone.png) | ![Дрон після](v22_fix/main_1280.png) |

### Ангар після виправлення

![Ангар](v22_fix/hangar_1280.png)

### Режим TURTLE з відео (був наслідком AUX-мапінгу)

![TURTLE до](v22_fix/before_turtle_mode.png)

### Загальне порівняння

![Пауза: до і після](v22_fix/compare_pause.png)

![Дрон: до і після](v22_fix/compare_drone.png)

## 4. QA

Новий тест: `test/qa_video_fixes.tscn` (запускається з `MOBILE_UI=1`, `TOUCH_CONTROLS=1`).

```
[VIDEOFIX] PASS pause_menu is not on an AUX channel
[VIDEOFIX] PASS mode_turtle is not on an AUX channel
[VIDEOFIX] PASS flight-mode cycling is not on an AUX channel
[VIDEOFIX] PASS arm stays on CH5
[VIDEOFIX] PASS actions cannot bind to a stick channel
[VIDEOFIX] PASS mode action binds to an AUX channel
[VIDEOFIX] PASS disabled mode action stays disabled after save
[VIDEOFIX] PASS ARM button arms the drone
[VIDEOFIX] PASS ARM button keeps the flight mode
[VIDEOFIX] PASS second ARM press disarms
[VIDEOFIX] PASS ARM works while turtle input is held
[VIDEOFIX] PASS held turtle input cannot change mode during ARM
[VIDEOFIX] PASS touch on the left stick does not pause
[VIDEOFIX] PASS mobile pause card is wide
[VIDEOFIX] PASS mobile pause rows are tall
[VIDEOFIX] PASS pause can open the mobile sub-menus
[VIDEOFIX] PASS action dropdown lists only AUX channels CH5-CH16
[VIDEOFIX] PASS disabled row uses a safe sentinel id
[VIDEOFIX] PASS dropdown bind reaches CH7
[VIDEOFIX] PASS dropdown disable row really unbinds
[VIDEOFIX] PASS hero drone renders at full size
[VIDEOFIX] PASS hero camera stays close to the drone
[VIDEOFIX] PASS hangar drone renders at full size after reload
[VIDEOFIX] RESULT PASS failures=0
```

Додатково перевірено після змін:

```
[CTRLQA] mode_start=1  mode_after_1=7  mode_after_2=0  mode_after_3=1
[CTRLQA] video_before=1 video_after=2 overlay_visible=true
[CTRLQA] PASS

[STICKQA] left horizontal yaw=0.707  throttle=0.853
[STICKQA] right horizontal roll=0.707  pitch=-0.707
[STICKQA] roll plain=0.8 inverted=-0.8
[STICKQA] PASS

[INVQA] elrs sign +=0.343 -=-0.343
[INVQA] on elrs=true touch=true saved=true/true
[INVQA] PASS

[BINDQA] deploy_payload -> CH8
[BINDQA] dispatch pressed=true released=true
[BINDQA] setup arm -> CH10
[BINDQA] conflict deploy=CH5 arm=CH6
[BINDQA] PASS
```

Тобто старі перевірки контролів, стіків і прив'язки AUX не зламалися; конфлікт «скид на CH5» більше не залишає ARM на тому самому каналі — ARM переїжджає на CH6.

## 5. Збірка

- Коміт: `6a2a5d3` (гілка `main`, запушено)
- GitHub Actions: run **#20**, release `ios-build-20`
- IPA: `NebesnyiHorizont-unsigned-v22-fixed.ipa`
- Розмір: **935 174 369 байт** (891.9 MB)
- SHA-256: `bb73b80353682b01d75e6bd0d7551c0f12b7040aba8ce02df2a91ef124d90868`
- Посилання: **http://192.168.0.100:8000/NebesnyiHorizont-unsigned-v22-fixed.ipa**
- Сторінка завантаження: **http://192.168.0.100:8000/**
- Підпис: AltStore Classic / Sideloadly, безкоштовний Apple ID; термін 7 днів.
