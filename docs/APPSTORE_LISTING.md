# App Store Listing & Review Metadata — Nebesnyi Horizont (v1.20.0)

## 1. General App Metadata
- **Bundle Display Name (`CFBundleDisplayName`):** `NebesnyiHorizont`
- **Bundle Identifier (`CFBundleIdentifier`):** `com.nebesnyihorizont.game`
- **Marketing Version (`CFBundleShortVersionString`):** `1.20.0`
- **Build Number (`CFBundleVersion`):** `20`
- **Primary Category:** Games → Simulation / Action
- **Age Rating:** `12+` (Simulated tactical drone operations against military equipment and fortified positions; no graphic gore or real-world state/brand trademarks)
- **Copyright:** `© 2026 Nebesnyi Horizont. All Rights Reserved.`
- **Privacy Policy URL:** `https://movchan-educatio.github.io/NebesnyiHorizont/privacy.html` *(source file: `docs/privacy.html`, mirror: `PRIVACY_POLICY.md`)*
- **Support URL:** `https://movchan-educatio.github.io/NebesnyiHorizont/support.html` *(or `https://github.com/movchan-educatio/NebesnyiHorizont/issues`)*
- **Marketing URL (Optional):** `https://github.com/movchan-educatio/NebesnyiHorizont`
- **Export Compliance:** `ITSAppUsesNonExemptEncryption = false` (No custom cryptography; standard Apple OS HTTPS/networking only)
- **App Privacy Questionnaire (App Store Connect):** **Data Not Collected** (`NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes = []`; `ios/PrivacyInfo.xcprivacy` declares Godot runtime Required Reason APIs: `C617.1`, `CA92.1`, `35F9.1`, `E174.1`).

---

## 2. Ukrainian App Store Listing (UK)

### Назва (Title)
**Небесний горизонт — Симулятор FPV**

### Підзаголовок (Subtitle, до 30 символів)
**Школа пілота та тренажер БПЛА**

### Промо-текст (Promotional Text, до 170 символів)
Опануйте пілотування FPV-дронів у режимах ACRO, HORIZON та ANGLE! Школа пілота, траси з воротами, тактичні місії на 5 картах та підключення пульта через ELRS Wi-Fi.

### Опис (Description)
**«Небесний горизонт»** — це мобільний 3D-симулятор і тренажер оператора FPV-дронів, створений для тренування моторики стіків, точного проходження перешкод і виконання тактичних вильотів на iPhone та iPad.

**Основні можливості:**
• **Школа пілота (10 модулів):** покроковий інтерактивний курс від першого запуску двигунів і зависання до слалому, прольоту крізь вікно та м'якої посадки.
• **5 деталізованих карт:** Промзона і Плавні, Покинутий аеропорт, Індустріальні руїни, Лісовий масив та Нафтова платформа з воротами тренування та повторами.
• **Тактичні кампанії та спецоперації:** розвідка секторів, супровід колони, доставка вантажу, прорив крізь перешкоди РЕБ і перехоплення повітряних цілей.
• **Ангар із різними типами БПЛА:** легкі 5-дюймові квадрокоптери, 7–10-дюймові платформи, важкий нічний гексакоптер із системою скидання, крила розвідки та реактивний перехоплювач.
• **Реалістична фізика та Betaflight Rates:** точне налаштування RC Rate, Super Rate, Expo, кута нахилу FPV-камери, маси батареї, вітру та зон радіоелектронної протидії.
• **Підтримка апаратури керування (ELRS Wi-Fi та USB/Bluetooth):** вбудований приймач протоколу CRSF по Wi-Fi (UDP 11000) для підключення зовнішніх пультів керування без кабелів, а також сенсорне керування з плаваючими стіками.
• **Оптимізовано для iOS:** плавна робота у 60 FPS, автоматичний переворот екрана між лівим і правим горизонтальним положенням із врахуванням Dynamic Island / Safe Area.

### Ключові слова (Keywords, до 100 символів)
`fpv,дрон,симулятор,бпла,тренажер,квадрокоптер,elrs,acro,політ,школа пілота,drone,simulator`

---

## 3. English App Store Listing (EN-US)

### App Name (Title)
**Nebesnyi Horizont — FPV Sim**

### Subtitle (up to 30 characters)
**FPV Drone Trainer & Missions**

### Promotional Text (up to 170 characters)
Master FPV drone flight in ACRO, HORIZON, and ANGLE modes! Complete Flight School, time-trial gates across 5 maps, tactical missions, and ELRS Wi-Fi radio support.

### Description
**Nebesnyi Horizont** is a 3D FPV drone flight simulator and operator trainer engineered for iPhone and iPad. Practice stick control, precision obstacle navigation, and tactical scenarios offline anywhere.

**Key Features:**
• **10-Module Flight School:** Guided interactive lessons covering arming, altitude hold, yaw control, slalom gates, precision window pass, braking, and landing.
• **5 Distinct 3D Environments:** Fly through Promzona Wetlands, Abandoned Airport, Industrial Ruins, Pine Forest, and Offshore Oil Rig with sequential checkpoint rings.
• **Tactical Campaign & Special Operations:** Execute reconnaissance, convoy escort, cargo delivery, electronic-warfare (EW) navigation, and aerial target interception.
• **Diverse Aircraft Fleet:** From agile 5-inch freestyle quads and 7–10-inch tactical platforms to a 6-rotor heavy night hexacopter with wind-compensated payload release, fixed-wing recon UAVs, and a jet interceptor.
• **Authentic Flight Physics & Betaflight Rates:** Customize RC Rate, Super Rate, Expo, camera tilt angle, battery sag, wind turbulence, and link limits.
• **ELRS Wi-Fi & Controller Support:** Built-in CRSF-over-UDP (port 11000) receiver for wireless ExpressLRS RC transmitters, alongside Bluetooth/USB gamepads and customizable dual touch sticks.
• **Designed for iOS:** Adaptive 3D resolution for cool, sustained performance, full Ukrainian and English localization, and seamless 180° landscape rotation with Dynamic Island safe-area support.

### Keywords (up to 100 characters)
`fpv,drone,simulator,uav,quadcopter,trainer,acro,elrs,flight,racing,pilot,rc,betaflight,wings`

---

## 4. App Review Notes (For Apple App Store Reviewer)

- **No Account / Login Required:** All modes (Flight School, Training, Campaign, Special Ops, Hangar, Settings) are immediately playable offline with on-screen Touch Controls.
- **Why Local Network Permission is Requested (`NSLocalNetworkUsageDescription`):**
  The app does NOT trigger any Local Network permission prompt on startup. It requests Local Network access **only when the user opens "Radio 3D / ELRS" or taps the ELRS Wi-Fi guide**, solely to listen for local CRSF telemetry/channel packets on **UDP port `11000`** from an ExpressLRS Wi-Fi RC transmitter (`ExpressLRS TX`, `10.0.0.1`). Declining the prompt never blocks offline touch or MFi/Bluetooth gamepad play.
- **Third-Party Content & Privacy:** Zero ad SDKs, zero analytics/tracking (`NSPrivacyTracking = false`), `PrivacyInfo.xcprivacy` is bundled inside the app target.
