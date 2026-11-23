# TikFinity — добірка віджетів для FPV-стріму

Усі URL нижче — реальні, взяті з залогіненого акаунта TikFinity
(Overlay Gallery: https://tikfinity.zerody.one/tiktok/obsoverlays).

Додаються в TikTok LIVE Studio через **Додати джерело → Посилання (Link)**.
Після додавання кожен віджет розтягніть у кут і **не закривайте** центр екрана —
там має бути дрон і траса.

---

## Рекомендований мінімальний набір (4 віджети)

| Віджет | URL | Куди поставити |
|---|---|---|
| **Activity Feed** (все в одному: фоловери, лайки, подарунки, коментарі) | `https://tikfinity.zerody.one/widget/activity-feed?cid=0&did=1` | Вгорі зліва, вузька колонка ~300×400 |
| **Top Gifter** (топ дарителі — мотивує дарити) | `https://tikfinity.zerody.one/widget/topgifter?cid=0` | Вгорі справа, ~280×300 |
| **Timer** (час стріму) | `https://tikfinity.zerody.one/widget/timer?cid=0` | Внизу зліва, маленький ~200×60 |
| **Viewer Count** (глядачі) | `https://tikfinity.zerody.one/widget/viewercount?cid=0` | Внизу справа, маленький ~200×60 |

Чому саме так: центральні 60% екрана лишаються чистими для польоту,
а вся інтерактивність зібрана по краях. Activity Feed заміняє собою
одразу кілька окремих алертів — менше безладу.

---

## Додаткові віджети (за бажанням)

| Віджет | URL | Коментар |
|---|---|---|
| Recent Follower / User Info | `https://tikfinity.zerody.one/widget/userinfo?cid=0` | Останній підписник |
| Top Liker | `https://tikfinity.zerody.one/widget/topliker?cid=0` | Топ за лайками |
| Gifts (окремо) | `https://tikfinity.zerody.one/widget/gifts?cid=0` | Якщо хочете окремий рядок дарів |
| Chat | `https://tikfinity.zerody.one/widget/chat?cid=0` | LIVE Studio і так показує чат — зазвичай зайве |
| My Actions | `https://tikfinity.zerody.one/widget/myactions?cid=0&screen=1` | Ваші кастомні алерти з Actions & Events |
| Song Requests | `https://tikfinity.zerody.one/widget/songrequests?cid=0` | Музика зі Spotify |
| Wheel of Fortune | `https://tikfinity.zerody.one/widget/wheel?cid=0` | Колесо для дарів/челенджів |
| Coin Drop | `https://tikfinity.zerody.one/widget/coindrop?cid=0` | Монети, що падають |
| Fireworks | `https://tikfinity.zerody.one/widget/firework?cid=0` | Ефект для великих дарів |
| Falling Snow | `https://tikfinity.zerody.one/widget/fallingsnow?cid=0` | Декоративний сніг |
| Social Media Rotator | `https://tikfinity.zerody.one/widget/socialmediarotator?cid=0` | Посилання на соцмережі |
| Emojify | `https://tikfinity.zerody.one/widget/emojify?cid=0` | Емодзі з чату |
| Ranking | `https://tikfinity.zerody.one/widget/ranking?cid=0` | Загальний рейтинг |
| Stream Buddies | `https://tikfinity.zerody.one/widget/streambuddies?cid=0` | Персонажі глядачів |
| Carousel | `https://tikfinity.zerody.one/widget/carousel?cid=0` | Карусель контенту |
| World Cup Ticker | `https://tikfinity.zerody.one/widget/worldcupticker?cid=0` | Біжуча стрічка подій |
| Activity Feed (вар. 2) | `https://tikfinity.zerody.one/widget/activity-feed?cid=0&did=2` | Другий вигляд фіду |
| Transaction Viewer | `https://tikfinity.zerody.one/widget/transactionviewer?cid=0` | Історія транзакцій |

---

## Як додати віджет у LIVE Studio

1. LIVE Studio → вибрати сцену **FPV** → **Додати джерело**.
2. **Посилання (Link)**.
3. Вставити один із URL вище → підтвердити.
4. Потягнути кути джерела, щоб поставити у потрібний кут.
5. Повторити для наступного віджета.
6. Перевірити в прев'ю **до** ефіру.

> Кожен віджет = окреме джерело «Посилання». Не вставляйте всі URL в одне джерело.

---

## Налаштування вигляду

У TikFinity → **Overlays** → біля потрібного віджета кнопка **Customize**:
кольори, шрифт, розмір, тривалість алерту. Зміни застосовуються до URL одразу.

**Sound Alerts і TTS** налаштовуються окремо в розділах **Sounds / Chat** TikFinity —
це не оверлей, а звук. Перевірте, чи LIVE Studio захоплює звук із Link-джерел;
якщо ні — використовуйте **TikFinity Desktop App** (https://tikfinity.zerody.one/app)
як джерело звуку в мікшері LIVE Studio.

---

## Важливо перед ефіром

- TikFinity має бути **підключено до вашого LIVE** (кнопка Connect після старту стріму).
- Віджети з `cid=0` працюють з активним підключенням акаунта; якщо з'явиться помилка —
  у TikFinity → Setup перевірте підключений TikTok-акаунт і скопіюйте свій CID,
  замінивши `cid=0` у URL.
- Не перевантажуйте екран: для FPV достатньо 4 віджетів вище.
