# ZOMBI · библия проекта

Игры ещё нет — есть **сайт-библия**, где живёт сценарий, механика и превью. Всё хранится только
в этом репозитории, отдельная папка [`game-docs/`](game-docs/README.md).

Игра: **«Пепел и Звёзды»** (рабочее название, 31.10.2026) — survival/craft/research на Земле 3610 года:
планету эвакуировали и сожгли галактический совет в 3071-м, колония вернулась, вирус выпущен снова,
ты просыпаешься на материке. Полный канон — `game-docs/src/content/scenario.json`; он важнее любой
механики: если вкладка «Механика» противоречит сценарию, правят вкладку. Прежняя история про остров
снята с игры и лежит вне сайта: `game-docs/archive/scenario.2026-10-30.json`.

Архивы `*.7z.*` в корне — исходники острова/персонажа из старой версии, их не правим.

- **Витрина и заставки:** 6 ключевых кадров нового мира + 4 служебных кадра заставок (постеры и петли на случай «видео не открылось») + две видеозаставки (перед меню — 39,4 с с титрами; пробуждение героя — 12,8 с). Собираются одной командой: `./game-docs/tools/make-splash.sh`, страница — `python3 game-docs/tools/author_gallery.py`.
- **Читать без сайта:** `game-docs/archive/zombi-chitalka.html` — вся библия одним файлом, открывается двойным кликом; пересборка `python3 game-docs/tools/build_offline_reader.py`.
- **Сайт:** https://rewg40.github.io/my-godot-game/
- **Вход:** код `ZOMBI-2026` (или сразу `https://rewg40.github.io/my-godot-game/#code=ZOMBI-2026`)
- **Быстрый путь:** https://rewg40.github.io/my-godot-game/?open=1 — просмотр без кода, запись недоступна

Если у автора github.io вырезан провайдером: страница сама ищет файлы — сначала
  `https://github.com/rewg40/my-godot-game/raw/gh-pages/game-docs/src/` (github.com обычно жив),
  затем `cdn.jsdelivr.net`, `rawcdn.githack.com`, затем сам origin. Пользователь может задать
  своё зеркало `?mirror=<url>/` и путь внутри репозитория `?src=game-docs/src/` (сброс — `?mirror=0`,
  `?src=0`); если недоступно всё — кнопка «Офлайн-копия» в красной карточке сторожа выкачивает
  все `content/*.json` в один текстовый файл.

Сайт — статичный, базы данных у него нет. **Заполнить сайт = отредактировать JSON в репозитории и
запушить**: GitHub Actions сам пересоберёт Pages (10–60 с). Адрес самого сайта для правки не нужен —
нужен адрес репозитория и папки `game-docs/src/`.

| Что просит автор | Куда писать |
| --- | --- |
| «допиши в Сценарий / в акты / в диалоги» | `game-docs/src/content/scenario.json` |
| «добавь в Погоду / Бой / Инвентарь / Физику / Исследование / Сеть …» | `game-docs/src/content/mech_<раздел>.json` (15 файлов, соответствие — ниже) |
| «картинку в превью», «3D-модель» | `game-docs/src/content/preview.json` + реестры `images.json` / `models.json` + сами файлы в `content/images/`, `content/models/` |
| «заставку», «видео с титрами», «кадр пробуждения» | `game-docs/tools/make-splash.sh` (собирает `content/video/*.mp4` для сайта и `media/splash/*.ogv` для движка) + `game-docs/tools/author_gallery.py` (вся страница «Картинки / превью») |
| заявка не из чата, а с сайта | `game-docs/src/content/agent-inbox/NNNN-slug.md` → после выполнения в `agent-inbox/done/` |
| доступ гостю | `game-docs/src/config.json` → `gate.allowed` (только SHA-256 хеш кода, никогда сам код) |
| «дай почитать без сайта» | `python3 game-docs/tools/build_offline_reader.py` → `game-docs/archive/zombi-chitalka.html` |
| «скинь всё, что сделал, архивом» | `bash game-docs/tools/make_handoff_archive.sh` (читалка + документация + мастера заставок одним zip; в git не кладётся) |

Полная инструкция (формат блоков, стандарт детализации, правила Godot-кода, приёмка):
[`game-docs/src/docs/AGENT-GUIDE.md`](game-docs/src/docs/AGENT-GUIDE.md).

### Вкладки «Механика» → файлы

`character`→`mech_character.json` · `craft`→`mech_craft.json` · `research`→`mech_research.json` ·
`multiplayer`→`mech_multiplayer.json` · `weather`→`mech_weather.json` ·
`npc`→`mech_npc.json` · `quests`→`mech_quests.json` · `locations`→`mech_locations.json` ·
`destruction`→`mech_destruction.json` · `physics`→`mech_physics.json` · `zombies`→`mech_zombies.json` ·
`combat`→`mech_combat.json` · `inventory`→`mech_inventory.json` · `assets`→`mech_assets.json` ·
`production`→`mech_production.json`

### Порядок действий (обязательный)

```bash
git pull --rebase                                                              # всегда свежее состояние
# ... правка content/*.json: блоки append, пустые не удалять, текст не переводить ...
# сценарий, витрина и новые механики не латай наивными заменами — перегенери:
#   python3 game-docs/tools/author_scenario.py      # -> content/scenario.json
#   python3 game-docs/tools/author_mech_new.py      # -> mech_research.json + mech_multiplayer.json
#   python3 game-docs/tools/author_gallery.py       # -> preview.json + images.json (галерея и заставки)
#   ./game-docs/tools/make-splash.sh                # -> key-art webp, 2 заставки, веб-копии, петли
#   python3 game-docs/tools/relore_mech.py --check  # старая островная лексика в 13 mech-файлах (0 = чисто)
node game-docs/tools/build-inline-gate.js                                     # если трогал app.js/config.json/inline-*.js
node game-docs/tools/check-site.js                                             # валидация JSON, схем, доступа, инлайн-блоков
git add -A && git commit -m "docs(<раздел>): <что добавлено>" && git push
```

Пуш в ветку, из которой публикуется Pages, — и есть «публикация». Текущая ветка публикации:
`arena/73c7370f-my-godot-game` (значение — в `game-docs/src/config.json`, `origin.branch`).
Не трогать: `*.7z.*` в корне, `.github/workflows/deploy-docs-site.yml`, замок доступа (кроме `gate.allowed`).

### Интерактив сайта: правила, без которых «вкладки перестают реагировать»

`index.html` содержит два самодостаточных куска кода, сгенерированных из `game-docs/tools/`:

- **замок** (`inline-gate.js`) в `<head>` — открывает сайт даже если `app.js` не загрузился;
- **сторож** (`inline-watchdog.js`) перед `</body>` — считает клики по вкладкам и показывает
  красную карточку с причиной поломки и кнопкой «Перезагрузить начисто».

После правки `src/app.js` (`SITE_BUILD`), `src/config.json` (`gate.ownerCode`) или любого из
`tools/inline-*.js` ОБЯЗАТЕЛЬНО:

```bash
node game-docs/tools/build-inline-gate.js   # вставляет замок+сторож и штамп data-build
node game-docs/tools/check-site.js          # §7 проверяет, что блоки целы и компилируются
```

Ограничения этих двух файлов (иначе ломается вся страница, а не только украшение):

- только ES5, без `async`/стрелок/шаблонных литералов;
- **никаких** `/* … */` в коде — закрывающая последовательность обрывает `<script>`; комментарии только `//`;
- никаких переводов строк внутри строковых литералов — нужен перенос, пиши `String.fromCharCode(10)`;
- генератор проверяет всё это через `vm.Script` и не даст записать битый инлайн — не обходи проверку.

Обработчики вкладок в `app.js` навешиваются в `boot()` ПЕРВЫМИ строками (до стража кэша и до
загрузки конфига): «клик ну ничего не делает» — это баг, который `check-site.js` ловит (§7, п.5).

### Как автору ставить задачу

1. **Здесь, в чате Arena** — адрес сайта писать не нужно: файлы, ветка и деплой мне известны.
   Достаточно: «добавь в Погоду 4 сезона таблицей эффектов и привяжи к суточному циклу».
2. **Через сайт** — «Запросы агенту» внизу → текст → «Отправить агенту»: появится файл в
   `content/agent-inbox/`. Потом в чате: «разбери inbox».
3. **Другому агенту** (Claude/Copilot/Cursor в этом репозитории) — одной строки достаточно:
   «работай по `README.md` в корне репозитория `rewg40/my-godot-game`».
