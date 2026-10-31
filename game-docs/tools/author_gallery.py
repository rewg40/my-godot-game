#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Собирает витрину глазами:
  game-docs/src/content/preview.json   — вкладка «Картинки / превью»
  game-docs/src/content/images.json    — реестр картинок (по нему сайт рисует сетку)

Канон — «Пепел и Звёзды» (game-docs/src/content/scenario.json). Старый островный
мудборд и плейсхолдеры сняты: файлы лежат в game-docs/archive/, сайтом не читаются.

Запуск:  python3 game-docs/tools/author_gallery.py
Дальше:  node game-docs/tools/check-site.js && git add -A && git push
"""
import io
import json
import os
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = os.path.join(ROOT, "src", "content")

NOW = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
DAY = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")


def H(t):        return {"type": "h", "text": t}
def P(*t):       return {"type": "p", "text": list(t)}
def NOTE(t):     return {"type": "note", "text": t}
def L(*items, ordered=False): return {"type": "list", "ordered": ordered, "items": list(items)}
def TODO(*items): return {"type": "todo", "items": [{"text": t, "done": False} for t in items]}
def KV(head, *rows): return {"type": "kv", "head": list(head), "rows": [list(r) for r in rows]}
def IMG(src, caption): return {"type": "image", "src": src, "caption": caption}
def VIDEO(src, poster, caption):
    return {"type": "video", "src": src, "poster": poster, "caption": caption}
def CODE(lang, *lines):
    return {"type": "code", "lang": lang, "code": chr(10).join(lines)}


# ------------------------------------------------------------------ кадры галереи
# (slug, файл, имя в реестре, подпись на сайте, теги, что кадр обещает, зона, ссылка на вкладку)
SHOTS = [
    ("ash", "images/preview/01-ash-plains.webp",
     "К-01 · Пепельные равнины «Стекло»",
     "Один человек, один фонарь и 48 × 48 км пепла. На горизонте — Нулевой город и «Игла»: "
     "оба видны отовсюду, оба сейчас недосягаемы.",
     ["concept", "ключевой кадр", "обложка"],
     "На открытом месте тебя слышно. Поэтому герой идёт, а не бежит, и фонарь держит внизу.",
     "открытая местность", "«Погода», «Персонаж»"),
    ("sleep", "images/preview/05-fields-of-sleep.webp",
     "К-02 · Поля сна",
     "Заражённые, законсервированные холодом. Считывать с них лут можно, будить — нельзя. "
     "Кадр целиком про одно правило: тихий ужас без крови.",
     ["concept", "зомби", "тон"],
     "Спящий встаёт от тепла, звука и крови — но не от света. Трупы не восстают вообще.",
     "заражённые", "«Зомби», «Бой»"),
    ("null", "images/preview/02-null-city.webp",
     "К-03 · Нулевой город",
     "Затопленная метролия, в которой в 3600-м вскрыли «Сито» на расстоянии. Команда на льду "
     "в обвязке — не подвиг, а единственный безопасный способ пересечь зеркало.",
     ["concept", "город", "затопление"],
     "Вертикальные переходы, лёд под ногами, дозор Совета на каждом выходе из воды.",
     "город Советa", "«Локации», «Физика»"),
    ("sito", "images/preview/04-sito-lab.webp",
     "К-04 · Станция «Сито»",
     "Восемь уровней подо льдом, ржавые лестницы и один тёплый жёлтый свет внизу — там нулевой "
     "образец и там же ты просыпаешься.",
     ["concept", "лаборатория", "крафт"],
     "Техника старая, но живая: здесь учат чинить, а не стрелять. 36 часов Порога считают здесь.",
     "изоляция", "«Исследование», «Крафт»"),
    ("needle", "images/preview/03-needle.webp",
     "К-05 · «Игла»",
     "Недостроенный орбитальный лифт, 3,2 км, на конце — станция «Кошелёк» и то, что там "
     "осталось: «Эхо Велума». Отряд идёт к нему пешком четыре дня.",
     ["concept", "финал", "чужое"],
     "Чужое не торгуется. Протокол «объект закрыт» — не враг, а дверь, у которой нет звонка.",
     "чужие", "«NPC и фракции», «Сетевая игра»"),
    ("wake", "images/preview/06-awakening.webp",
     "К-06 · Пробуждение (старт игры)",
     "Тот самый первый кадр: POV, треснутое стекло иллюминатора, рука, красный светодиод "
     "ремня. Ни оружия, ни плана — только 36 часов.",
     ["concept", "старт", "POV"],
     "Ты — техник-сварщик с «Горизонта». Первые полчаса игра ничему не учит, кроме тишины.",
     "пролог", "«Квесты», «Сценарий»"),
]

# ------------------------------------------------------------------ превью-документ
blocks = []

blocks.append(NOTE(
 "Всё, что можно показать глазами. Картинки, видео и модели лежат в репозитории "
 "(`game-docs/src/content/images/`, `.../content/video/`, `.../content/models/`), а список — в "
 "`images.json` / `models.json`. Добавить можно прямо из браузера: загрузил → закоммитил в репозиторий → "
 "через минуту на сайте видно. Все кадры здесь — уже **новый мир**, «Пепел и Звёзды»; островной мудборд "
 "v0.1 снят и лежит в `game-docs/archive/`."))

blocks.append(H("Как это работает"))
blocks.append(L(
 "Кнопка «＋ картинка» сжимает файл до ≤ 1400 px (WebP/PNG), кладёт в `content/images/` и дописывает "
 "запись в `images.json`.",
 "Кнопка «＋ 3D-модель» принимает GLB/GLTF/FBX/OBJ: файл едет в `content/models/`, в `models.json` "
 "появляется запись; GLB можно покрутить прямо на сайте (three.js).",
 "Каждая запись имеет поля: `name`, `caption`, `tags`, `tab` (к какой вкладке привязана), `file` "
 "(путь относительно `content/`), `author`, `date`.",
 "Если токена нет — можно просто добавить URL: `https://github.com/rewg40/my-godot-game/raw/main/...`.",
 "Вся эта страница собирается генератором `game-docs/tools/author_gallery.py`. Править один абзац "
 "можно и руками, но после ручной правки не запускай генератор повторно — он перезапишет файл целиком.",
 "Видео-блок (`type: video`) показывается плеером с постером; сам файл при этом живёт в "
 "`content/video/`, а мастер-исходник для движка — в `media/splash/`."))

blocks.append(H("Ключевые кадры мира"))
blocks.append(P(
 "Шесть кадров, по которым равняется весь визуал: тон, масштаб, свет и — главное — то правило игры, "
 "которое кадр объясняет без слов. Пока рендеров из движка нет, это рабочие концепты: они рисовались "
 "агентом по плейлисту ниже и не обещают ничего, чего нет в описаниях механик.",
 "Смотреть целиком — клик по картинке. Вес каждого файла ≤ 1.4 МБ, длинная сторона ≤ 1400 px: больше "
 "не смысл — сайт показывает их в 460 px, а в репозитории файл живёт вечно и его кто-то скачает."))
for slug, f, name, cap, tags, promise, zone, links in SHOTS:
    blocks.append(IMG(f, "**" + name + "** — " + cap))

blocks.append(H("Что кадр обещает игроку"))
blocks.append(P(
 "Правило витрины: у каждого ключевого кадра есть строка «что игрок увидит, когда дойдёт». Если под "
 "кадром нет игрового правила — это открытка, а не превью, и в галерею она не идёт."))
blocks.append(KV(["Кадр", "Зона", "Правило, которое он показывает", "Где проверять"],
                *[["**" + n.split(" · ")[1] + "**", z, pr, ln] for _, _, n, _, _, pr, z, ln in SHOTS]))

blocks.append(H("Заставка перед главным меню"))
blocks.append(P(
 "**«Пепел и Звёзды» · 39,4 с · 1280×720 · 24 fps · титры внутри ролика.** Играет один раз при "
 "запуске, до главного меню: чёрный экран → шесть зон мира → карточка названия с титрами → «нажми "
 "любую кнопку». Любой ввод после 1,2 с пропускает её целиком — второй раз за сеанс она не показывается.",
 "Почему видео, а не сцена на движке: ролик стоит 0 строк шейдеров, одинаково выглядит на всех "
 "платформах, не лагает на слабом железе и меняется без пересборки игры. Дорожку меню это не тормозит — "
 "главное меню грузится параллельно, а заставка в это время просто идёт."))
blocks.append(IMG("images/preview/splash-title-card.webp",
 "Кадр титров: название, строка под ним и четыре блока создателей. Затемнённый и размытый «Стекло» — "
 "тот же кадр К-01, чтобы переход из ролика в меню не был скачком по цвету."))
blocks.append(VIDEO("video/splash-intro.mp4", "images/preview/splash-title-card.webp",
 "Заставка целиком (веб-версия, 960 px, звук — ветер и дрон 53 Гц). Мастер для движка: "
 "`media/splash/splash-intro.ogv` — Godot 4 играет Theora без плагинов."))
blocks.append(IMG("images/preview/splash-intro-loop.webp",
 "Петля 4,8 с (15 кадров, 600 px) — на случай, если видео не открылось: движение кадра видно даже "
 "в `<img>`, и плеер на сайте не оставляет чёрную дыру."))
blocks.append(KV(["Секунда", "Кадр", "Что на экране", "Звук"],
 ["0.0 – 3.6", "чёрное поле", "«ЗЕМЛЯ · 3610 ГОД» → «пепел помнит всех, кто дышал слишком громко»", "ветер, ещё тихо"],
 ["3.6 – 9.0", "К-01 «Стекло»", "наезд 1,00 → 1,09 · подпись зоны у нижнего края", "ветер + низкий дрон 53 Гц"],
 ["9.0 – 13.8", "К-02 поля сна", "«спящие встают не на свет, а на звук»", "дрон, реже"],
 ["13.8 – 18.6", "К-03 Нулевой город", "«затопленная метролия · «Игла» в четырёх километрах»", "дрон + далёкий металл"],
 ["18.6 – 23.4", "К-04 «Сито»", "«36 часов до Порога · изоляция, а не лечение»", "дрон"],
 ["23.4 – 28.2", "К-05 «Игла»", "«орбитальный лифт · протокол „объект закрыт“»", "дрон на 79,5 Гц"],
 ["28.2 – 36.6", "К-01, blur 2 px ×0.5", "«ПЕПЕЛ И ЗВЁЗДЫ» / Ash & Stars / 4 строки титров / 2 строки про репозиторий", "дрон затихает"],
 ["36.6 – 39.4", "чёрное поле", "«НАЖМИ ЛЮБУЮ КНОПКУ · → ГЛАВНОЕ МЕНЮ»", "тишина"]))
blocks.append(L(
 "Пропуск: любой `InputEventKey`/клик, но **не раньше 1,2 с** — иначе первое нажатие «вхолостую» "
 "выглядит как сломанная кнопка.",
 "Заставка не блокирует загрузку: `main_menu.tscn` грузится параллельно (`call_deferred`), к 36-й "
 "секунде она всегда готова.",
 "Нет файла `.ogv` (например, при лёгкой сборке для веба) — показываем `boot_splash.png` + тот же "
 "текст титров. Чёрного квадрата быть не может ни при каком раскладе.",
 "Звук: автоплей разрешён только после первого жеста; до него ролик идёт без дорожки, иконок «включить "
 "звук» не добавляем. Дорожка интро — шина `World` (амбиент), дорожка пробуждения — `Danger` "
 "(там уже живут сердцебиение и tinnitus); глобальный mute глушит и ролик.",
 "Alt+Tab не паузит ролик (иначе окно «зависает» на середине); `get_tree().paused` заставка не "
 "использует вовсе.",
 "Просадка кадров: если средний FPS за первые 4 с < 40 — доигрываем только последние 6 с, остальное "
 "склеиваем постером. Решает `Performance.get_monitor(TIME_FPS)` в `_ready`."))
blocks.append(CODE("gdscript",
 "# scenes/ui/splash_title.gd — заставка до главного меню. Loader (scenes/boot/) меняет сцену не на меню, а на неё",
 "extends Node2D",
 "",
 "const MASTER_OGV := \"res://media/splash/splash-intro.ogv\"   # Theora: Godot 4 читает без плагинов",
 "const POSTER := \"res://media/splash/boot_splash.png\"        # тот же кадр титров, но без «нажми любую кнопку»",
 "const MENU := \"res://scenes/boot/main_menu.tscn\"",
 "const MIN_WATCH := 1.2        # сек.: раньше не пропускаем — первое нажатие обычно «до окна»",
 "const LOW_FPS := 40.0         # порог деградации",
 "const TAIL := 6.0             # сек., которые досматриваем на слабом железе",
 "",
 "@onready var _video: VideoStreamPlayer = $Layer/Video",
 "@onready var _poster: TextureRect = $Layer/Poster",
 "@onready var _fade: ColorRect = $Layer/Fade",
 "",
 "var _t := 0.0",
 "var _frames := 0",
 "var _skip_armed := false",
 "var _degraded := false",
 "",
 "",
 "func _ready() -> void:",
 "    process_mode = Node.PROCESS_MODE_ALWAYS     # Alt+Tab и пауза не должны замораживать ролик",
 "    _poster.texture = load(POSTER) if ResourceLoader.exists(POSTER) else null",
 "    _poster.visible = true",
 "    _video.visible = false",
 "    _fade.color.a = 0.0",
 "    if ResourceLoader.exists(MASTER_OGV):",
 "        _video.stream = load(MASTER_OGV)",
 "        _video.bus = &\"World\"                   # дрон и ветер — в шину амбиента («Аудио, UI, проект»)",
 "        _video.visible = true",
 "        _poster.visible = false",
 "        _video.play()",
 "        _video.finished.connect(_finish)",
 "    else:",
 "        # нет видео (лёгкая сборка) — статичный кадр + 4 с, чтобы титры успели прочитать",
 "        get_tree().create_timer(4.0).timeout.connect(_finish)",
 "    ResourceLoader.load_threaded_request(MENU)  # меню грузится ПОКА идёт ролик",
 "",
 "",
 "func _process(delta: float) -> void:",
 "    _t += delta",
 "    _frames += 1",
 "    if not _skip_armed and _t >= MIN_WATCH:",
 "        _skip_armed = true",
 "    if not _degraded and _t >= 4.0 and float(_frames) / _t < LOW_FPS:",
 "        _degrade()                              # слабое железо: 39 с не крутим, досматриваем хвост",
 "",
 "",
 "func _unhandled_input(event: InputEvent) -> void:",
 "    if not _skip_armed:",
 "        get_viewport().set_input_as_handled()",
 "        return",
 "    if (event is InputEventKey and event.pressed and not event.echo) \\",
 "            or (event is InputEventMouseButton and event.pressed):",
 "        _finish()",
 "",
 "",
 "func _degrade() -> void:",
 "    _degraded = true",
 "    _video.stop()",
 "    _video.visible = false",
 "    _poster.visible = true",
 "    get_tree().create_timer(TAIL * 0.4).timeout.connect(_finish)",
 "",
 "",
 "func _finish() -> void:",
 "    set_process(false)",
 "    _video.stop()",
 "    UserSettings.set_flag(\"splash_seen\", true)  # второго показа за установку не будет",
 "    var tw := create_tween()",
 "    tw.tween_property(_fade, \"color:a\", 1.0, 0.35)",
 "    tw.tween_callback(_swap_menu)",
 "",
 "",
 "func _swap_menu() -> void:",
 "    while ResourceLoader.load_threaded_get_status(MENU) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:",
 "        await get_tree().process_frame",
 "    get_tree().change_scene_to_file(MENU)",
 "",
 "# Сигналов заставка не шлёт: она никого не интересует, кроме порядка смены сцен.",
 "# Глобальный mute (`AudioMgr`) глушит и ролик: он сидит на той же шине `World`, что и весь мир.",
 "# `UserSettings.set_flag` — единственная новая строка в системах; остальное уже описано в «Аудио, UI, проекте»."))

blocks.append(H("Заставка пробуждения героя"))
blocks.append(P(
 "**12,8 с · 1280×720 · 24 fps · без титров.** Отдельная заставка на «Новую игру»: игрок жмёт «начать» "
 "и получает не меню, а чужое пробуждение — POV под треснувшим стеклом, рука, красный светодиод ремня, "
 "строка HUD и «дыши тише». Кончается резкой склейкой на игру: затемнений в этом месте нет намеренно, "
 "момент пробуждения не должен быть вежливым.",
 "Тот же мир, тот же дрон, но без музыки и без логотипа: название игрок видел 30 секунд назад, "
 "повторять его в момент, когда тебя только что вынули из криокапсулы, — значит объяснять не то."))
blocks.append(IMG("images/preview/splash-awakening-frame.webp",
 "Кадр на 5,5 с: стекло, рука, светодиод. Этот же файл — постер плеера и картинка деградации, если "
 "видео не играет."))
blocks.append(VIDEO("video/splash-awakening.mp4", "images/preview/splash-awakening-frame.webp",
 "Заставка пробуждения целиком (веб-версия). Сердцебиение 60 → 84 удара в минуту, дыхание — фильтрованный "
 "розовый шум, никаких ударных."))
blocks.append(IMG("images/preview/splash-awakening-loop.webp", "Петля 4,8 с для случая «видео не открылось»."))
blocks.append(KV(["Секунда", "Что видно", "Текст", "Звук"],
 ["0.0 – 2.5", "полная чернота, 24 fps, ни вспышки", "«ЗЕМЛЯ · ПЕЛЕНА · 3610 · СУТКИ 1»", "только дыхание, гул станций на −34 дБ"],
 ["2.5 – 4.2", "стекло проступает из чёрного (fade 1,7 с)", "—", "первый удар сердца"],
 ["4.2 – 6.0", "рука тянется к стеклу", "строка HUD: `кислород 6:20:14 · скафандр 62% · фонарь 1/4`", "сердцебиение 60/мин"],
 ["6.0 – 9.0", "кадр открыт целиком, наезд 1,00 → 1,14", "«дыши тише» — единственный приказ за всю заставку", "84/мин, дыхание чаще"],
 ["9.0 – 12.3", "через fadeblack — карточка акта", "«ПРОБУЖДЕНИЕ» + «АКТ I · «ПЕПЕЛ И ЖЕТОН»»", "обрыв на 12,3 с"],
 ["12.3 – 12.8", "чёрное поле 0,5 с", "—", "тишина, затем щелчок шлема (это уже игра)"]))
blocks.append(L(
 "Skip — только `Esc`, и не раньше 6 с: игрок, пропустивший «дыши тише», потом не поймёт, почему его "
 "убил шум шагов. Пробел/клик здесь **не** пропускают.",
 "Доступность: нужен режим «Спокойный образ» — те же 12,8 с, но без строб-эффекта на 2,5 с и без мигающего "
 "светодиода (замена — равномерная подсветка). Пункт настроек ещё не заведён: он стоит в «Открытых "
 "вопросах» и в `mech_inventory.json` его пока нет.",
 "Если `splash-intro.ogv` ещё не доиграл в этом сеансе, пробуждение не ставится на повтор: после "
 "`Новая игра` → заставка один раз, дальше — сразу сцена.",
 "Набор правил `Плот` (PvE, `mech_multiplayer.json`) заставку не укорачивает: 12,8 с — часть обучения, а "
 "не украшение.",
 "В сетевой части заставка не синхронизируется: хост запускает сцену сразу, гость досматривает. Играть "
 "одновременно — не обязательство клиента."))
blocks.append(CODE("gdscript",
 "# scenes/ui/splash_awakening.gd — заставка пробуждения: отдельная сцена, свой тайминг, свои правила skip",
 "extends Node2D",
 "",
 "const MASTER_OGV := \"res://media/splash/splash-awakening.ogv\"",
 "const STILL := \"res://media/splash/splash-awakening-frame.webp\"   # та же картинка, что в реестре галереи",
 "const CELL := \"res://scenes/world/cryo/awakening_cell.tscn\"       # куда склеиваем",
 "const MIN_WATCH := 6.0        # раньше Esc не работает: «дыши тише» обязано дойти",
 "const HUD_FROM := 4.2",
 "const HUD_TO := 6.0",
 "",
 "@onready var _video: VideoStreamPlayer = $Layer/Video",
 "@onready var _still: TextureRect = $Layer/Still",
 "@onready var _hud: Label = $Layer/Hud/Line",
 "",
 "var _t := 0.0",
 "var _hud_shown := false",
 "",
 "",
 "func _ready() -> void:",
 "    process_mode = Node.PROCESS_MODE_ALWAYS",
 "    get_tree().paused = true                    # мир ждёт заставки: никто не встанет и не зашумит",
 "    # цвет сцены = чёрный кадр заставки, чтобы склейка «пробуждение → кубрик» была невидимой",
 "    RenderingServer.set_default_clear_color(Color(0.02, 0.03, 0.04))",
 "    ResourceLoader.load_threaded_request(CELL)",
 "    _still.texture = load(STILL) if ResourceLoader.exists(STILL) else null",
 "    if ResourceLoader.exists(MASTER_OGV):",
 "        _video.stream = load(MASTER_OGV)",
 "        _video.bus = &\"Danger\"                  # сердцебиение и tinnitus уже живут на этой шине",
 "        _video.play()",
 "        _video.finished.connect(_to_game)",
 "    else:",
 "        # нет видео: тот же кадр + строка HUD, 9 с — и в игру",
 "        _hud.text = _hud_line(62)",
 "        _hud.visible = true",
 "        get_tree().create_timer(9.0).timeout.connect(_to_game)",
 "    if Env.get_bool(\"calm_mode\"):",
 "        _still.self_modulate = Color(0.85, 0.9, 1.0)   # «Спокойный образ»: без строба и без мигания диода",
 "",
 "",
 "func _process(delta: float) -> void:",
 "    _t += delta",
 "    if not _hud_shown and _t >= HUD_FROM:",
 "        _hud_shown = true",
 "        _hud.text = _hud_line(62)",
 "        _hud.modulate.a = 0.0",
 "        _hud.visible = true",
 "        var tw := create_tween()",
 "        tw.tween_property(_hud, \"modulate:a\", 1.0, 0.6)",
 "        tw.tween_interval(maxf(HUD_TO - _t, 0.2))",
 "        tw.tween_property(_hud, \"modulate:a\", 0.0, 0.5)",
 "",
 "",
 "func _unhandled_input(event: InputEvent) -> void:",
 "    if _t >= MIN_WATCH and event.is_action_pressed(\"ui_cancel\"):",
 "        _to_game()",
 "    else:",
 "        get_viewport().set_input_as_handled()   # клик и пробел здесь ничего не пропускают",
 "",
 "",
 "func _hud_line(suit_pct: int) -> String:",
 "    # цифры обязаны совпасть с HUD после склейки: расхождение в одну минуту видно сразу.",
 "    # когда `Needs.oxygen_left_h()` будет зафиксирован (вкладка «Инвентарь»), подставить его сюда;",
 "    # до этого — константа акта I: 6 ч 20 мин кислорода, скафандр 62%, фонарь 1/4.",
 "    return \"кислород 6:20:00 · скафандр %d%% · фонарь 1/4\" % suit_pct",
 "",
 "",
 "func _to_game() -> void:",
 "    set_process(false)",
 "    _video.stop()",
 "    while ResourceLoader.load_threaded_get_status(CELL) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:",
 "        await get_tree().process_frame",
 "    get_tree().paused = false",
 "    get_tree().change_scene_to_file(CELL)",
 "    # без fade: резкая склейка — часть режиссуры (см. «Тон и правила показа» в «Сценарии»)",
 "",
 "# Из незафиксированного остаётся две строки в системах: `Needs.oxygen_left_h()` и `Env.get_bool(\"calm_mode\")`.",
 "# Сцены и ресурсы заставок в проект кладёт `game-docs/tools/make-splash.sh` — руками их не трогать."))

blocks.append(H("Как собрать заново"))
blocks.append(P(
 "Обе заставки — не ручная работа в видеоредакторе, а скрипт. Хочешь другой текст титров, другой порядок "
 "кадров, другую длительность — правь `game-docs/tools/make-splash.sh` и запускай его заново; он соберёт "
 "и masters, и веб-копии, и петли."))
blocks.append(L(
 "Нужны: `ffmpeg` (пойдёт static-сборка из `pip install imageio-ffmpeg`) и ImageMagick `convert` со "
 "шрифтами DejaVu. В static-сборках ffmpeg **нет** фильтра `drawtext` — поэтому весь текст рендерится "
 "PNG-плашками (`convert -annotate`) и накладывается фильтром `overlay`. Кириллица, переносы и «ё» "
 "работают, fontconfig не нужен.",
 "Ключевые кадры-источники: 1376×768 PNG, по умолчанию берутся из `$SRC_ART` (у агента — "
 "`~/.th/art`). `SRC_ART=/path/to/png ./game-docs/tools/make-splash.sh`.",
 "Команды: `--stills` (только WebP галереи), `--no-webp` (не делать анимированные петли), без флага — "
 "всё.",
 "Находы: `media/splash/*.{mp4,ogv}` + `media/splash/boot_splash.png` (для движка, на Pages не "
 "публикуется) и `game-docs/src/content/video/*.mp4` + "
 "`game-docs/src/content/images/preview/*.webp` (это уже сайт).",
 "Лимиты на публикуемое: ≤1400 px и ≤1.4 МБ на картинку (`MAX_IMG` в `config.json`), веб-версии "
 "заставок — 960 px, `crf 33`, 64 кбит/с моно. Мастер для Godot — Theora `q:v 5`: у Godot 4 это "
 "единственный видеоформат, который играется без плагинов.",
 "После пересборки — `python3 game-docs/tools/author_gallery.py`, чтобы в реестр попали новые веса и "
 "подписи, и `node game-docs/tools/check-site.js`."))
blocks.append(NOTE(
 "Длительности и порядок сегментов лежат в переменных скрипта (`D0`, `DL`, `D6`, `D7`, `XFADE`), а не "
 "в голове монтажера: поменять тайминг титров = поменять одно число. Тексты титров тоже в скрипте — "
 "правь их там, а не в mp4."))

blocks.append(H("Плейлист кадров"))
blocks.append(P(
 "Список того, чем галерея должна закрыться. Концепты 1–6 нарисованы, 7–12 — очередь: часть из них "
 "появится только после вертикального среза, и это нормально: превью не должно обещать то, чего ещё нет "
 "в коде."))
blocks.append(KV(["N", "Кадр", "Зачем", "Статус"],
 [1, "Пепельные равнины, фигура с фонарём", "обложка стима", "есть (К-01); для стима нужен кроп 1920×620"],
 [2, "Поля сна: ряды спящих в сугробах", "витрина «тихого» ужаса", "есть (К-02)"],
 [3, "Нулевой город: команда на льду в обвязке", "масштаб и затопление", "есть (К-03)"],
 [4, "«Сито»: шахта подо льдом, один тёплый свет", "быт техники", "есть (К-04)"],
 [5, "«Игла» под сиянием, отряд пешком", "финал акта IV", "есть (К-05)"],
 [6, "Пробуждение: POV, стекло, рука", "старт игры + заставка", "есть (К-06)"],
 [7, "Карта Пелены 48 × 48 км, от руки, с пометками", "навигация, обложка вики", "нет — рисовать по `data/world/`"],
 [8, "UI-мокап: часы Порога, инвентарь, шум-метр", "интерфейс", "нет — Figma → PNG"],
 [9, "Барак Артели: огонь, верстак, лица", "обучение и быт", "нет — скриншот после MVP крафта"],
 [10, "Обломок «Горизонта»: дома в его рёбрах", "мир уже разобран", "нет — концепт"],
 [11, "Тихий переход: силуэты в пепеле, шкала шума", "ядро геймплея", "нет — скриншот"],
 [12, "Баркас «Сухарь» у понтона Артели", "вода и торговля", "нет — концепт"],
 [13, "Рендер из движка кадра К-02 «как есть»", "честность витрины", "нет — после MVP: тот же кадр, 0 стилизации"]))

blocks.append(H("Наследие: что лежит в корне репозитория"))
blocks.append(NOTE(
 "`ZOMBI.7z.00*`, `остров 1.7z.00*`, `персонаж 1.7z.00*` — старая островная сборка, от мира, который "
 "снят с игры. Их **не** распакуем, не правим и не цитируем как источник канона или как источник "
 "картинок для галереи. Максимум, что из них законно брать — геометрию и текстуры как сырьё, и только "
 "после того, как автор разрешит явно."))
blocks.append(KV(["Файл в репо", "Размер", "Что это", "Что с ним"],
 ["`ZOMBI.7z.001..004`", "≈68 МБ", "старая сборка/проект (остров, «Горечь»)", "не трогаем; архив"],
 ["`остров 1.7z.001..002`", "≈40 МБ", "окружение острова", "не трогаем; из модели-библики не следует"],
 ["`персонаж 1.7z.001..003`", "≈62 МБ", "модели персонажа прошлого прототипа", "не трогаем; если понадобится — только меш, без имён и позы старого героя"]))

blocks.append(H("Реестр ассетов: библиотека моделей"))
blocks.append(NOTE(
 "В репозитории уже лежит **862 самодостаточных .glb** (Kenney + KayKit, CC0; 479 133 треугольника, "
 "~34 МБ) — они в PR #1, папка `модели/`. Всё в метрах, Y вверх, текстуры вшиты внутрь файла: модель "
 "копируется одним .glb и не ломается. «Иглу» и «Сито» из этих пакетов не собрать — они годятся на "
 "серую блокировку, быт и масштаб, и это как раз то, что нужно до появления авторских моделей. Ниже — "
 "по одному образцу на категорию: «👁 превью» крутит модель прямо на сайте."))
blocks.append(KV(["Категория", "Что внутри", "Моделей", "Пример (крутится на сайте)"],
 ["01_terrain_ground/", "Местность: грунт, трава, песок, склоны, дороги и тропы — «пол» уровня", "149", "модели/01_terrain_ground/gen_hex_tiles.glb"],
 ["02_islands/", "Острова целиком с подводным основанием, берег, вода, реки, водопады", "97", "модели/02_islands/gen_atoll.glb"],
 ["03_cliffs_rocks/", "Скалы, утёсы, обрывы, валуны, входы в пещеры", "143", "модели/03_cliffs_rocks/hex_stone-hill.glb"],
 ["04_vegetation/", "Деревья, пальмы, трава, цветы, пни, посевы", "148", "модели/04_vegetation/hex_unit-tree.glb"],
 ["05_buildings_structures/", "Дома, башни, стены, заборы, ворота, доки, мосты, маяки, статуи", "250", "модели/05_buildings_structures/hex_bridge.glb"],
 ["06_props_decor/", "Бочки, ящики, сундуки, корабли, пушки, оружие, облака", "75", "модели/06_props_decor/hex_unit-ship-large.glb"]))
blocks.append(NOTE(
 "Категория `02_islands` называется «острова» только по имени исходного набора Kenney: в новом мире это "
 "плоские участки суши посреди затопленного Нулевого города и острова наледью в карьерах «Стекла»."))

blocks.append(H("Открытые вопросы"))
blocks.append(TODO(
 "Логотип: сейчас в титрах просто DejaVu Bold. Нужен знак — буква «П» с трещиной и одна точка-звезда.",
 "Обложка стима 1920×620 из К-01 (сейчас кадр 16:9, композиция не тянется на широкий формат).",
 "Озвучка титров одним голосом (12 слов) или остаёмся в тишине с дроном?",
 "Версия 1920×1080: исходники 1376×768, апскейл даст мыло — значит перерисовать кадры, а не растягивать.",
 "Английский набор титров: тот же рендер, другие PNG-плашки → сделать флаг `--lang en` в "
 "`make-splash.sh`.",
 "Рендеры из движка вместо концептов — после вертикального среза, кадры 2, 9, 11.",
 "Скриншот-сетка «кадр → правило» для страницы в Steam: 6 кадров К-01…К-06 + 6 подписи из таблицы "
 "«Что кадр обещает игроку».",
 "Завести пункт «Спокойный образ» в настройках (`mech_inventory.json`) — без него заставку с "
 "мерцанием нельзя показать игрокам с фотосенситивностью."))

preview = {
 "id": "preview",
 "kind": "preview",
 "title": "Картинки и превью",
 "subtitle": "Ключевые кадры, заставки и реестр ассетов «Пепел и Звёзды»",
 "status": "wip",
 "updated": NOW,
 "blocks": blocks,
 "glossary": [
  ["ключевой кадр", "концепт, по которому равняют весь визуал; у каждого есть строка «что игрок увидит»"],
  ["заставка", "видео до главного меню (39,4 с) или до старта партии (12,8 с); для движка — Theora .ogv"],
  ["петля", "анимированный WebP 4,8 с в `<img>`: показывает движение, если `<video>` не открылся"],
  ["boot_splash", "PNG, которую Godot показывает до первой сцены; в ней не должно быть «нажми любую кнопку»"],
  ["playlist", "плейлист кадров — очередь того, чем галерея обязана закрыться"],
 ],
}

# ------------------------------------------------------------------ реестр картинок
items = []
for slug, f, name, cap, tags, promise, zone, links in SHOTS:
    items.append({
        "id": "key-" + slug,
        "name": name,
        "file": f,
        "caption": cap + " Правило кадра: " + promise,
        "tags": tags + [zone],
        "tab": "preview",
        "author": "agent",
        "date": DAY,
    })

EXTRA = [
 ("splash-title-card", "images/preview/splash-title-card.webp", "Заставка · кадр титров",
  "Карточка «ПЕПЕЛ И ЗВЁЗДЫ» + 4 строки титров поверх затемнённого К-01. Работает и постером `<video>`, "
  "и деградацией заставки, если видео не играет.", ["splash", "постер"]),
 ("splash-intro-loop", "images/preview/splash-intro-loop.webp", "Заставка · петля 4,8 с",
  "Анимированный WebP первого наезда: `<video>` не открылся — движение всё равно видно.",
  ["splash", "webp-анимация"]),
 ("splash-awakening-frame", "images/preview/splash-awakening-frame.webp", "Пробуждение · кадр 5,5 с",
  "POV, треснутое стекло, рука, светодиод ремня. Постер и запасной кадр заставки пробуждения.",
  ["splash", "старт", "постер"]),
 ("splash-awakening-loop", "images/preview/splash-awakening-loop.webp", "Пробуждение · петля 4,8 с",
  "Петля пробуждения для случая «видео не открылось».", ["splash", "webp-анимация"]),
]
for iid, f, name, cap, tags in EXTRA:
    items.append({"id": iid, "name": name, "file": f, "caption": cap, "tags": tags,
                  "tab": "preview", "author": "agent", "date": DAY})

for it in items:
    p = os.path.join(CONTENT, it["file"])
    if os.path.exists(p):
        it["size_kb"] = round(os.path.getsize(p) / 1024.0, 1)

images = {"version": 1, "updated": NOW, "items": items,
          "note": ("Канон кадров — «Пепел и Звёзды». Островный мудборд v0.1 и плейсхолдер "
                   "«остров в тумане» сняты с витрины и лежат в `game-docs/archive/`. Поле `file` — путь "
                   "относительно `content/`; `size_kb` считает генератор, руки ему не нужны."),
          "video": [
              {"id": "splash-intro", "name": "Заставка перед главным меню", "file": "video/splash-intro.mp4",
               "poster": "images/preview/splash-title-card.webp", "duration_s": 39.4, "fps": 24,
               "size_kb": round(os.path.getsize(os.path.join(CONTENT, "video", "splash-intro.mp4")) / 1024.0, 1)
               if os.path.exists(os.path.join(CONTENT, "video", "splash-intro.mp4")) else None,
               "master_ogv": "media/splash/splash-intro.ogv", "tool": "game-docs/tools/make-splash.sh",
               "caption": "39,4 с · 6 зон мира + титры. В движке играет VideoStreamPlayer из .ogv."},
              {"id": "splash-awakening", "name": "Заставка пробуждения героя", "file": "video/splash-awakening.mp4",
               "poster": "images/preview/splash-awakening-frame.webp", "duration_s": 12.8, "fps": 24,
               "size_kb": round(os.path.getsize(os.path.join(CONTENT, "video", "splash-awakening.mp4")) / 1024.0, 1)
               if os.path.exists(os.path.join(CONTENT, "video", "splash-awakening.mp4")) else None,
               "master_ogv": "media/splash/splash-awakening.ogv", "tool": "game-docs/tools/make-splash.sh",
               "caption": "12,8 с · старт партии: стекло, рука, «дыши тише», склейка на игру."},
          ]}

io.open(os.path.join(CONTENT, "preview.json"), "w", encoding="utf-8").write(
 json.dumps(preview, ensure_ascii=False, indent=2) + "\n")
io.open(os.path.join(CONTENT, "images.json"), "w", encoding="utf-8").write(
 json.dumps(images, ensure_ascii=False, indent=2) + "\n")

bad = [it["file"] for it in items if not os.path.exists(os.path.join(CONTENT, it["file"]))]
print("preview.json:", len(blocks), "блоков ·",
      os.path.getsize(os.path.join(CONTENT, "preview.json")), "байт")
print("images.json:", len(items), "картинок ·", len(images["video"]), "видео")
if bad:
    print("⚠ нет файлов:", bad)
