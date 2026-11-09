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

У папці проєкту:

```powershell
git init
git lfs install
git add .
git commit -m "iOS build + ELRS WiFi input"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

Важливо:

- `Assets/**` и великі файли вже позначені в `.gitattributes` для Git LFS.
- Ассети важать ~1.8 ГБ; безкоштовний LFS-ліміт 1 ГБ. Потрібен data pack
  (~$5/міс) або публічний репозиторій з урахуванням ліцензій.
- `dist_*`, `build`, `.godot`, `qa_shots`, EXE та відео виключені.

## 3. Збірка

Workflow: `.github/workflows/ios.yml`.

1. GitHub → Actions → **Build iOS (unsigned IPA)** → **Run workflow**.
2. Раннер `macos-15` сам завантажує Godot 4.6.1 + iOS export templates.
3. Godot експортує Xcode-проєкт, `xcodebuild` збирає **unsigned** архів.
4. Готовий `.ipa` публікується в **Releases** під тегом `ios-build-<номер>`.

Перший запуск довший (імпорт 1.8 ГБ ассетів), наступні — швидші завдяки кешу
Godot/templates; кеш `.godot` не зберігається, тому імпорт повторюється.

## 4. Встановлення на iPhone 14

1. Встанови Sideloadly та iTunes/Apple Devices на Windows.
2. Підключи iPhone 14 Lightning-кабелем, довір комп’ютеру.
3. Завантаж `.ipa` з GitHub Releases.
4. У Sideloadly: вибери iPhone, перетягни `.ipa`, введи Apple ID.
5. Після установки: **Settings → General → VPN & Device Management** →
   довір сертифікату розробника.
6. iOS 16+: **Settings → Privacy & Security → Developer Mode** → увімкнути,
   перезавантажити iPhone.

Безкоштовний підпис діє **7 днів**, потім Sideloadly перепідписує IPA. Платний
Apple Developer ($99/рік) для цього не потрібен.

## 5. ELRS WiFi у грі

1. На пульті: `Lua → WiFi Connectivity → Enable WiFi`. Модуль створить
   `ExpressLRS TX` (пароль `expresslrs`) або підключиться до домашньої Wi-Fi.
2. iPhone → Wi-Fi → `ExpressLRS TX` (або та сама домашня мережа).
3. Запусти гру. iOS запитає **Local Network** — дозволь.
4. У HUD з’явиться `ELRS: STREAMING`.
5. Канали:
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

## 6. Якщо немає даних

- Перевір ELRS firmware ≥ 3.4.
- iPhone дійсно підключений до `ExpressLRS TX`, а не до мобільного інтернету.
- Дозволений **Local Network** для гри (Settings → Privacy → Local Network).
- UDP 11000 не блокується; на iOS це вирішує local network permission.
- Після виходу з гри модуль має отримати `joystick_end`; якщо інша програма
  «забрала» потік — перезапусти модуль або зайди в його WebUI.
- `0xF26A` у кадрах = «немає даних»; гра такі кадри відкидає.

## 7. Обмеження

- Це **не TestFlight і не App Store**: тільки особистий підпис на 7 днів.
- Для TestFlight/App Store потрібен платний Apple Developer і підписаний
  архів; GitHub Actions може це робити, але потрібні сертифікати/профілі.
- iPhone 14 — Lightning; ELRS WiFi не потребує USB-OTG, але Sideloadly
  потребує кабелю для встановлення.
- iOS може переривати Wi-Fi при переході на мобільну мережу; для польоту
  тримай режим польоту/Do Not Disturb.

## 8. Файли

- `.github/workflows/ios.yml` — збірка unsigned IPA.
- `export_presets.cfg` → preset **iOS**.
- `Assets/ios_icons/` — іконки.
- `autoloads/ElrsWifiInput.gd` — UDP/HTTP ELRS WiFi.
- `drone/RadioController.gd` — пріоритет WiFi-каналів.
- `test/fake_elrs.py` — QA-емулятор модуля без заліза.
