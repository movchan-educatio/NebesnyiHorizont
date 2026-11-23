---
trigger: always_on
description: "Гібридна схема економії лімітів: делегування генерації об'ємного коду безкоштовним моделям OpenCode (пріоритет opencode/hy4-flash-free#high) та резервним моделям GitHub Copilot із обов'язковою перевіркою результату."
---

# Гібридна схема роботи (Antigravity + безкоштовні моделі OpenCode + GitHub Copilot)

## Розподіл ролей
- **Я (ручний набір коду):** користуюся безлімітним Tab-автодоповненням Antigravity IDE.
- **Ти (агент Antigravity):** працюєш як координатор і рев'юер — не витрачай власний тижневий ліміт на великі обсяги коду з нуля, а делегуй генерацію зовнішнім CLI-моделям і перевіряй їхню роботу.

## Правила делегування
1. **Безкоштовні моделі OpenCode (основний виконавець для об'ємного коду):**
   - Для написання нових модулів, великих правок, шаблонів і рефакторингу запускай:
     `opencode run -m opencode/hy4-flash-free#high "<чітке завдання з точними шляхами до файлів>"`
     *(Примітка: для неінтерактивного редагування файлів додавай `--auto`; при запуску через `cmd.exe` додавай `< NUL`, щоб закрити stdin.)*
   - Актуальні ID доступних безкоштовних моделей OpenCode:
     - **Пріоритетна #1 (основна):** `opencode/hy4-flash-free#high` (**Hy4 flash Free**, режим `High`; також `opencode-go/hy4-flash-free#high`)
     - **Альтернативи OpenCode Free:** `opencode/deepseek-v4.1-flash-free`, `opencode/mimo-v2.6-flash-free`, `opencode/nemotron-3.5-super-vl-free`, `opencode/nemotron-3.5-lightning-free`, `opencode/beam-free`, `opencode/flint-40b-free`, `opencode/iceman-free`, `opencode/tidepool-alpha-free`
     - **Резервні безкоштовні OpenRouter (`:free`):** `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free`, `openrouter/google/gemma-4-31b-it:free`, `openrouter/google/gemma-4-26b-a4b-it:free`, `openrouter/nvidia/nemotron-3.5-super-vl:free`, `openrouter/openrouter/free`
   - Ніколи не передавай у безкоштовні моделі паролі, токени, `.env` чи приватні ключі.

2. **GitHub Copilot CLI / Copilot-моделі в OpenCode (резерв для складних задач):**
   - Запускай `copilot -p "<завдання>"` (або `opencode run -m <copilot-модель> "<завдання>"`), коли я явно прошу використати Copilot або коли безкоштовна модель не впоралася зі складним багом чи архітектурою.
   - Актуальні Copilot-моделі в OpenCode: `github-copilot/gpt-5.6-luna` (економічна), `github-copilot/claude-sonnet-5.5`, `github-copilot/claude-haiku-5.5`, `github-copilot/gpt-5.3-codex`, `github-copilot/gpt-6-luna`, `github-copilot/gpt-6.1-terra`, `github-copilot/gemini-4-hydrogen`, `github-copilot/mai-code-2`.

3. **Дрібні точкові правки:**
   - Лише короткі виправлення на кілька рядків (наприклад, після перевірки коду) роби самостійно.

## Обов'язкова перевірка після кожного делегування
Після кожного запуску `opencode run` або `copilot -p` ти ПОВИНЕН:
1. Перевірити всі змінені файли через `git diff` (синтаксис, логіка, імпорти, крайові випадки).
2. Переконатися, що нічого зайвого не зламано і не видалено.
3. Якщо в проєкті є тести, лінтер або збірка — запустити їх.
4. Виправити знайдені помилки сам або повторним запитом, і лише після перевірки звітувати мені.
