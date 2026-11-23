# AI Workflow: Гібридна зв'язка (Antigravity Free + GitHub Copilot Pro)

Коротка шпаргалка для щоденної роботи над проєктом з трьох інструментів без перевитрати місячної квоти GitHub Copilot Pro.

---

## 1. Правило розподілу задач

| Тип задачі | Інструмент | Чому саме він |
| :--- | :--- | :--- |
| Рутинні правки, **Tab-автодоповнення**, швидкі фікси, локальні питання | **Безкоштовний агент Antigravity IDE / Antigravity 2.0 + Antigravity Tab** | Працює на тижневих лімітах Antigravity і не витрачає місячні кредити Copilot |
| Складні задачі, глибокий рефакторинг, багатофайлові зміни, моделі з підписки Copilot Pro | **`opencode` (`v2.2.5`)** або **`copilot` (`v1.0.114`)** у вбудованому терміналі Antigravity | Повний агентний режим у терміналі з доступом до моделей підписки GitHub Copilot Pro |
| Швидкий чат із моделями Copilot усередині інтерфейсу редактора | Розширення **`Copilot for VSCode OSS`** (`maxie-homrich.copilot-for-vscode-oss`) | Зручна бічна панель чату прямо в Antigravity IDE |

---

## 2. Готові команди запуску

### A. Antigravity IDE (основний редактор + безкоштовний агент + Tab)
```powershell
# Відкрити поточний проєкт у Antigravity IDE
antigravity-ide .
```
- **Antigravity Tab** (inline-доповнення коду): `Tab` — прийняти, `Ctrl+→` — прийняти слово, `Esc` — скасувати.
- **Inline Command** (точкові правки виділеного фрагмента): `Ctrl+I`.
- **Sidebar Chat / Agent**: бічна панель агента в Antigravity IDE (або паралельно **Antigravity 2.0** для керування агентами).

### B. OpenCode (`v2.2.5`, підключено до GitHub Copilot)
> У терміналі `opencode` налаштовано через обгортку на ваш уже авторизований **OpenCode Desktop CLI (`v2.2.5`)**.

```powershell
# Запустити інтерактивний TUI-агент OpenCode у поточній теці проєкту
opencode

# Продовжити останню сесію
opencode --continue

# Перевірити підключені провайдери (зокрема GitHub Copilot)
opencode auth list

# Переглянути доступні моделі (фільтр по github-copilot)
opencode models | Select-String "github-copilot"
```
Також можна відкривати GUI-застосунок **OpenCode Desktop** з меню «Пуск».

### C. GitHub Copilot CLI (`v1.0.114`, акаунт `movchan-educatio`)
```powershell
# Інтерактивна сесія Copilot у проєкті
copilot

# Одразу стартувати із задачею
copilot -i "Опис задачі"

# Автовибір моделі або вказання конкретної моделі
copilot --model auto

# Продовжити останню сесію
copilot --continue

# Повторна авторизація в GitHub (якщо сесія завершиться)
copilot login
```
Корисні слеш-команди всередині `copilot`:
- `/model` — змінити модель і подивитися її множник / вартість у кредитах;
- `/usage` — перевірити витрату кредитів / преміум-запитів у поточній сесії;
- `/login` — увійти або змінити акаунт GitHub.

### D. `Copilot for VSCode OSS` (усередині Antigravity IDE)
- Відкрийте **іконку Copilot** на лівій панелі **Activity Bar** в Antigravity IDE (`copilot-oss.sidebar`).
- Модель за замовчуванням можна змінити в інтерфейсі чату або в налаштуваннях (`Ctrl+,`) через параметр `copilot-oss.defaultModel` (зараз встановлено `"gpt-5.6-luna"`).

---

## 3. Автодоповнення Tab і відсутність конфліктів

- Єдиним активним Tab-автодоповненням залишено **Antigravity Tab** (`"editor.inlineSuggest.enabled": true` у налаштуваннях Antigravity IDE).
- Розширення **`Copilot for VSCode OSS`** працює **лише як бічна панель чату** і не реєструє inline-підказки чи перехоплення клавіші `Tab`, тому конфлікту з Antigravity Tab немає.
- Для роботи в чаті `Copilot for VSCode OSS` автоматично підхоплює авторизовану сесію **`copilot` CLI** (`@github/copilot-sdk`).

---

## 4. Контроль квоти GitHub Copilot Pro

- Щоб економити місячний ліміт Copilot Pro, залишайте щоденні дрібні правки та Tab-автодоповнення за **Antigravity**.
- Перед вибором важких моделей перевіряйте їхній множник через `/model` у `copilot` і стежте за витратами через `/usage`.
- Місячна квота GitHub Copilot Pro автоматично оновлюється **1-го числа кожного місяця**.
