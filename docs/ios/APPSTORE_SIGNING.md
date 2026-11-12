# Підписання TestFlight / App Store — інструкція та блокери

Цей файл описує, що потрібно для підписаного релізу. Поточний workflow
`.github/workflows/ios.yml` навмисно зберігає **unsigned IPA для AltStore** —
це особистий тестовий шлях власника, його не слід ламати.

## Поточний стан

- `export_presets.cfg` → preset `iOS`: `short_version=1.18.0`, `version=18`.
- Team ID у preset — placeholder `ABCDE12345`. Його **не можна** використати
  для App Store; треба замінити на реальний Team ID власника.
- CI використовує Godot `4.7.2-stable`, як і локальна перевірка QA.

## Що потрібно від власника

1. Платний Apple Developer Program із доступом до App Store Connect.
2. Team ID (10 символів) та роль з правами на signing.
3. Bundle ID `com.nebesnyihorizont.game` має бути зареєстрований у цьому
   акаунті. Якщо він зайнятий іншим розробником — обрати новий і змінити
   його у preset.
4. App Store Connect:
   - Privacy Policy URL;
   - Support URL / контактна електронна пошта;
   - App Privacy Details і age rating;
   - скриншоти та опис сторінки;
   - Review notes і демо-режим без входу (якщо акаунтів немає, вказати це).
5. Рішення щодо ліцензій: перевірити кожен успадкований GLB/звук згідно з
   `CREDITS.md`; частина походжень не задокументована і може потребувати
   заміни або окремого дозволу перед комерційною публікацією.

## Як підписати

Варіант A (рекомендовано, ручний):

1. На macOS відкрити проєкт у Godot 4.7.2.
2. `Project → Export → iOS`: ввести реальний Team ID і Bundle ID.
3. Експортувати Xcode-проєкт, відкрити `.xcodeproj`, налаштувати Signing &
   Capabilities через Xcode (автоматичне керування підписом).
4. `Product → Archive`, завантажити архів в App Store Connect через Organizer.
5. Створити TestFlight build і відправити на review.

Варіант B (CI, після налаштування секретів):

- Додати в GitHub репозиторій секрети:
  `APPLE_TEAM_ID`, `APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`,
  `APPLE_PROVISIONING_PROFILE_BASE64`, `APPSTORE_KEY_*`.
- Створити окремий workflow `ios-signed.yml`, який не використовує
  `CODE_SIGNING_REQUIRED=NO` і виконує `xcodebuild` з профілем.
- Секрети ніколи не комітити в репозиторій.

## Критерій готовності до review

- Підписаний TestFlight build встановився на iPhone власника.
- Всі чотири карти прогнані на пристрої без нових помилок.
- Privacy metadata заповнена; іконка та скриншоти відповідають правилам.
- Розмір збірки виміряний; ліцензії перевірені.

До виконання цих пунктів проєкт не можна називати App Store-ready.
