# iOS + ELRS WiFi: збірка через GitHub Actions

Ціль: зібрати **unsigned IPA** у GitHub Actions (macOS-раннер), підписати й
встановити на **iPhone 14** через Sideloadly з безкоштовним Apple ID, а пульт
Radiomaster Pocket підключити **по Wi-Fi ELRS** (без USB/Bluetooth, які Apple
блокує для RC-пультів).

## 1. Що потрібно

- GitHub-акаунт (репозиторій можна зробити приватним).
- Git + Git LFS на Windows.
- iPhone 14 + Lightning-кабель.
- Sideloadly (Windows) + iTunes/Apple Devices.
- Безкоштовний Apple ID.
- Pocket з ELRS **3.4+** (перевір у Lua: WiFi Connectivity → Enable WiFi).
- Інтернет для GitHub; для польоту інтернет не потрібен.

## 2. Репозиторій

Проєкт уже ініціалізовано та підключено до приватного репозиторію:

**https://github.com/movchan-educatio/NebesnyiHorizont**

Локальна гілка `main`. Оновлення:

```powershell
git add -A
git commit -m "опис змін"
git push
```

Важливо:

- `Assets/**` та великі файли зберігаються в Git LFS (`.gitattributes`).
- Ассети важать ~1.9 ГБ. GitHub Free станом на 2026 рік дає **10 GiB LFS
  storage + 10 GiB/місяць bandwidth**, тому одного пушу і кількох збірок
  вистачає. Якщо квота вичерпається — дочекайся скидання на початку місяця
  або зменш ассети.
- `dist_*`, `build`, `.godot`, `qa_shots`, EXE та відео виключені.
- Репозиторій **приватний**: ассети не публікуються.

## 3. Збірка

Workflow: `.github/workflows/ios.yml`.

**https://github.com/movchan-educatio/NebesnyiHorizont/actions/workflows/ios.yml**

1. Збірка стартує автоматично після пушу в `main` (або вручну:
   **Actions → Build iOS (unsigned IPA) → Run workflow**).
2. Раннер `macos-15` сам завантажує Godot 4.6.1 + iOS export templates.
3. Godot експортує Xcode-проєкт, `xcodebuild` збирає **unsigned** архів.
4. Готовий `.ipa` публікується в **Releases** під тегом `ios-build-<номер>`.

Перший запуск довший (checkout 1.9 ГБ LFS + імпорт ассетів + Xcode archive):
орієнтовно 25–45 хв. Наступні — швидші завдяки кешу Godot/templates; кеш
`.godot` не зберігається, тому імпорт повторюється.

Приватний репозиторій витрачає Actions-хвилини; macOS-раннер множиться на 10.
На GitHub Free це ~200 macOS-хвилин/місяць, тобто 4–6 збірок. Для однієї-двох
ітерацій цього достатньо.

## 4. Встановлення на iPhone 14

1. Встанови [Sideloadly](https://sideloadly.io/) та iTunes/Apple Devices на
   Windows (iTunes потрібен для драйверів/довіри).
2. Підключи iPhone 14 Lightning-кабелем, довір комп’ютеру.
3. Завантаж `.ipa` з GitHub **Releases** (тег `ios-build-<номер>`).
4. У Sideloadly: вибери iPhone, перетягни `.ipa`, введи Apple ID.
   Якщо на Apple ID увімкнена 2FA — Sideloadly попросить код або
   app-specific password.
5. Після установки: **Settings → General → VPN & Device Management** →
   довір сертифікату розробника.
6. iOS 16+: **Settings → Privacy & Security → Developer Mode** → увімкнути,
   перезавантажити iPhone.

Безкоштовний підпис діє **7 днів**, потім Sideloadly перепідписує IPA. Платний
Apple Developer ($99/рік) для цього не потрібен. Обмеження безкоштовного
акаунта: до 3 активних застосунків і 10 App ID на тиждень.

Якщо Sideloadly скаржиться, що bundle ID зайнятий, дозволь йому змінити
`com.nebesnyihorizont.game` на унікальний — гра все одно запуститься.

## 5. ELRS WiFi у грі

1. На пульті: `Lua → WiFi Connectivity → Enable WiFi`. Модуль створить
   `ExpressLRS TX` (пароль `expresslrs`) або підключиться до домашньої Wi-Fi.
2. iPhone → Wi-Fi → `ExpressLRS TX` (або та сама домашня мережа). Якщо iOS
   пише «No Internet Connection», вибери **Use Without Internet** / залиш
   Wi-Fi активним.
3. Запусти гру. iOS запитає **Local Network** — дозволь.
4. У HUD з’явиться `ELRS: STREAMING`.
5. Канали (стандартний порядок AETR):
   - CH1 — roll;
   - CH2 — pitch;
   - CH3 — throttle;
   - CH4 — yaw;
   - CH5 — Arm/Disarm (перемикач);
   - CH6 — перемикання режимів польоту;
   - CH7 — режим відео.
6. На екрані також є кнопка **ARM** — запасний варіант, якщо CH5 не налаштований.

Якщо модуль підключений до домашньої Wi-Fi, гра знаходить його по UDP-beacon.
Якщо ні — використовується `10.0.0.1` (точка доступу модуля).

Поради:

- Вимкни **Wi-Fi Assist** (Settings → Cellular) і не перемикайся на мобільну
  мережу під час польоту — інакше iOS розірве Wi-Fi з модулем.
- У EdgeTX перевір, що CH5 призначений на 2-позиційний перемикач, а CH6/CH7 —
  на 3-позиційні; інакше режими будуть перемикатися непередбачувано.
- Перший запуск після встановлення роби без польоту: переконайся, що
  `ELRS: STREAMING`, і лише потім злітай.

## 6. Якщо немає даних

- Перевір ELRS firmware ≥ 3.4 (у Lua видно версію).
- iPhone дійсно підключений до `ExpressLRS TX`, а не до мобільного інтернету.
- Дозволений **Local Network** для гри (Settings → Privacy → Local Network).
  Якщо пункту немає — перевстанови гру або скинь дозволи (Settings → General →
  Transfer or Reset iPhone → Reset → Reset Location & Privacy).
- UDP 11000 не блокується; на iOS це вирішує local network permission.
- Після виходу з гри модуль має отримати `joystick_end`; якщо інша програма
  «забрала» потік — перезапусти модуль або зайди в його WebUI.
- `0xF26A` у кадрах = «немає даних»; гра такі кадри відкидає.
- Якщо HUD показує `ELRS: NO MODULE`, але iPhone в мережі модуля: відкрий
  `http://10.0.0.1/` у Safari — переконайся, що WebUI відповідає. Якщо ні,
  перезавантаж модуль (живлення/кнопка).
- Якщо модуль у домашній Wi-Fi, а гра не бачить beacon: вимкни ізоляцію
  клієнтів (AP isolation) на роутері; beacon — UDP broadcast.
- Якщо канали є, але дрон не реагує: перевір порядок каналів AETR і що CH5
  дійсно змінюється в ELRS Lua → Channels.

## 7. Обмеження

- Це **не TestFlight і не App Store**: тільки особистий підпис на 7 днів.
- Для TestFlight/App Store потрібен платний Apple Developer і підписаний
  архів; GitHub Actions може це робити, але потрібні сертифікати/профілі.
- iPhone 14 — Lightning; ELRS WiFi не потребує USB-OTG, але Sideloadly
  потребує кабелю для встановлення.
- iOS може переривати Wi-Fi при переході на мобільну мережу; для польоту
  тримай режим польоту/Do Not Disturb.
- Застосунок великий (~1 ГБ PCK): установка через Lightning може зайняти
  кілька хвилин, а вільне місце на iPhone має бути з запасом.
- Перша збірка в Actions може впасти через квоту LFS/Actions — подивись лог
  кроку `Checkout` або `Import project`; після скидання квоти просто
  перезапусти workflow.

## 8. Файли

- `.github/workflows/ios.yml` — збірка unsigned IPA.
- `export_presets.cfg` → preset **iOS**.
- `Assets/ios_icons/` — іконки.
- `autoloads/ElrsWifiInput.gd` — UDP/HTTP ELRS WiFi.
- `drone/RadioController.gd` — пріоритет WiFi-каналів.
- `test/fake_elrs.py` — QA-емулятор модуля без заліза.
