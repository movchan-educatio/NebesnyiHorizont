# Звіт v24 — збереження налаштувань і керування

Дата: 11.11.2026  
Платформа: iPhone / iPad (мобільна версія).

## 1. Проблема

У v23 налаштування HUD/ELRS, калібрування та частина керування після перезапуску виглядали скинутими до дефолтів.

Це не була втрата файлу: `GameSettings.cfg` та `InputMap.cfg` записувалися. Проблема була в **порядку завантаження**:

- мобільний запуск іде `StartScreen → MobileMenu`, минаючи `MainMenu`;
- `StartScreen._initialize_settings()` завантажував Graphics, Audio, Controls і Menu.cfg, але **не** `GameSettings.load_hud_config()`;
- `ElrsWifiInput` і `MobileInput` стартували раніше й читали `GameSettings.hud_config` ще з дефолтами;
- у результаті ELRS-канали, інверсії, калібрування та HUD-налаштування в меню показувалися як дефолтні, хоча файл на диску містив збережені значення.

## 2. Що виправлено

- `GameSettings._ready()` тепер завантажує `GameSettings.cfg` до ініціалізації `ElrsWifiInput` і `MobileInput`. Це головний фікс.
- `StartScreen._initialize_settings()` явно викликає `GameSettings.load_hud_config()`.
- `MobileMenu._ready()` додатково завантажує HUD/ELRS/калібрування перед побудовою рядків меню — навіть при прямому запуску MobileMenu.
- У `GameSettings.hud_config` додано ключі, яких там не було, через що `load_hud_config()` їх **викидав** навіть при наявності у файлі:
  - `elrs_channel_map` — призначення стіків на канали;
  - `elrs_invert_pitch`, `elrs_invert_yaw`, `elrs_invert_throttle` — інверсії;
  - `elrs_action_defaults_version` — версія міграції AUX (без неї міграція запускалася кожного разу);
  - `osd_palette` — палітра OSD;
  - `status` — видимість статусу HUD.
- Існуючі файли налаштувань не змінюються і не видаляються; після оновлення вони просто починають читатися правильно.

Шляхи збереження:

- `user://config_G3/GameSettings.cfg` — HUD, ELRS, калібрування, мобільні налаштування;
- `user://config_G3/InputMap.cfg` — прив'язки керування, deadzone, smoothing, gamepad.

## 3. QA

Двопроцесний тест (`test/qa_persist2_write.tscn` → `test/qa_persist2_read.tscn`):

1. Перший процес записує: `fps=37`, `mobile_render_scale=73`, калібрування-sentinel, `deploy_payload=CH10`, `deadzone=0.033`, `smoothing=0.11`, gamepad button 7.
2. Другий процес стартує **з нуля** і читає ці значення до відкриття меню.

```
[PERSIST2] fps=37 scale=73 pilot=PERSIST-TEST cal=true deploy_ch=10 pitch_ch=4 pitch_inv=true palette=2 status=false ver=2 deadzone=0.033 smoothing=0.11 gamepad_button7=true
[PERSIST2] PASS
```

Додатково: `VIDEOFIX` — PASS, `ACTION_BIND_QA` — PASS.

## 4. Важливо про AltStore

Якщо AltStore/Sideloadly **видаляє** застосунок перед встановленням нової версії, iOS видаляє його пісочницю разом із налаштуваннями. Тоді жодна версія гри не збереже дані між такими перевстановленнями.

Правильно: встановлювати нову версію **поверх** існуючої, не видаляючи app. Якщо AltStore пропонує "видалити та встановити" — дані будуть втрачені.

## 5. Збірка

- Версія: **v24** (persistence fix)
- IPA: `NebesnyiHorizont-unsigned-v24-fixed.ipa`
- Розмір / SHA-256 / посилання: заповнюються після збірки.
