# Підписання TestFlight / App Store — чеклист готовності

Цей файл описує поточний стан iOS-збірки та кроки після придбання акаунту Apple Developer Program.
Workflow [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml) **зберігає unsigned IPA для AltStore/Sideloadly**, але також повністю готовий до підписаної збірки та автозавантаження в TestFlight.

---

## Поточний стан (v1.20.0 · Build 20)

- **`export_presets.cfg`:** `short_version="1.20.0"`, `version="20"`, `bundle_identifier="com.nebesnyihorizont.game"`, `min_ios_version="15.0"`, `ITSAppUsesNonExemptEncryption=false`, `UIRequiresFullScreen=true`.
- **Privacy Manifest (`ios/PrivacyInfo.xcprivacy`):** створений і автоматично інтегрується в `.app` під час CI-збірки (FileTimestamp `C617.1`, UserDefaults `CA92.1`, SystemBootTime `35F9.1`, DiskSpace `E174.1`; `NSPrivacyTracking=false`, `NSPrivacyCollectedDataTypes=[]`).
- **Local Network (ELRS Wi-Fi UDP 11000):** на iOS сокет не відкривається на холодному старті — дозвіл запитується лише коли користувач сам відкриває `Пульт 3D / Radio 3D` або інструкцію ELRS.
- **App Store вимоги UI:** приховані кнопки `Quit / Вихід` на iOS у `StartScreen.gd`, `MainMenu.gd`, `PauseMenu.gd`; додано модальне вікно `Конфіденційність та ліцензії` в `MobileMenu.gd` → Система; оптимізовано розмір бандлу (~112 МБ мертвих активів виключено).
- **Публічні сторінки та скриншоти:** готові [`PRIVACY_POLICY.md`](../../PRIVACY_POLICY.md), [`docs/privacy.html`](../privacy.html), [`docs/support.html`](../support.html), метадані [`docs/APPSTORE_LISTING.md`](../APPSTORE_LISTING.md) та скриншоти iPhone 6.7" / iPad 13" у `docs/appstore_screenshots/`.
- **Team ID у preset:** тимчасовий placeholder `ABCDE12345` — треба замінити на реальний 10-символьний Team ID власника перед App Store релізом.

---

## Що зробити в день покупки Apple Developer Account

1. **Зареєструвати Bundle ID:** в Apple Developer → Identifiers створити `com.nebesnyihorizont.game` (або обрати інший, оновивши `export_presets.cfg` та `.github/workflows/ios.yml`).
2. **Створити сертифікат та профіль:**
   - Apple Distribution Certificate → експортувати `.p12` (закодувати в Base64).
   - App Store Provisioning Profile для `com.nebesnyihorizont.game` → завантажити `.mobileprovision` (закодувати в Base64).
3. **Додати GitHub Repository Secrets:**
   - `IOS_TEAM_ID` — 10-символьний Team ID.
   - `IOS_P12_BASE64` — Base64 сертифіката Apple Distribution.
   - `IOS_P12_PASSWORD` — пароль до `.p12`.
   - `IOS_MOBILEPROVISION_BASE64` — Base64 App Store Provisioning Profile.
   - *(Для авто-відправки в TestFlight прямо з CI)*: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`.
4. **Оновити `export_presets.cfg`:** вписати реальний `application/app_store_team_id` замість `ABCDE12345`.
5. **Опублікувати `docs/privacy.html` та `docs/support.html`:** увімкнути GitHub Pages (Settings → Pages → branch/docs) і вказати URL в App Store Connect.
6. **Запустити `ios.yml` workflow:** завантажити скриншоти з `docs/appstore_screenshots/`, вставити тексти з `docs/APPSTORE_LISTING.md`, заповнити App Privacy (**Data Not Collected**), протестувати TestFlight-збірку на реальному iPhone та відправити на App Review.
7. **Юридична ревізія асетів:** перед комерційним релізом переглянути походження сторонніх моделей/звуків із [`CREDITS.md`](../../CREDITS.md).
