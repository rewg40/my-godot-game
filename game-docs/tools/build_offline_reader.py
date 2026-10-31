#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Собирает «читалку»: один HTML-файл, в котором живёт вся библия целиком —
сценарий, 15 разделов механики, витрина и обе инструкции. Без сайта, без
интернета, без app.js: открыл двойным кликом и читаешь.

Зачем: у автора github.io может не открываться, а читать надо и офлайн, и с телефона.
Картинки вшиты base64, видео — ссылкой на github.com (файл лежит в репозитории).

Запуск:  python3 game-docs/tools/build_offline_reader.py
Выход:   game-docs/archive/zombi-chitalka.html
"""
import base64
import html
import io
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))          # game-docs/
SRC = os.path.join(ROOT, "src")
CONTENT = os.path.join(SRC, "content")
OUT = os.path.join(ROOT, "archive", "zombi-chitalka.html")
RAW = "https://github.com/rewg40/my-godot-game/raw/arena/73c7370f-my-godot-game/game-docs/src/content"


def _opt(flag, dflt):
    """--flag ЗНАЧЕНИЕ из командной строки; сборщик архива передаёт свои пути."""
    a = sys.argv
    k = a.index(flag) if flag in a else -1
    return a[k + 1] if 0 <= k and k + 1 < len(a) else dflt


# Куда писать и где брать видео. Если задано --video-dir, ролик кладётся рядом
# с HTML и играется без сети; иначе в файле остаётся ссылка на github.com.
OUT = os.path.abspath(_opt("--out", OUT))
VIDEO_DIR = _opt("--video-dir", "")
VIDEOS = []          # что скопировать рядом с HTML (собирается по ходу рендера)

DOCS = [("scenario.json", "Сценарий")]
MECH_ORDER = ["character", "craft", "research", "weather", "npc", "quests", "locations",
              "destruction", "physics", "zombies", "combat", "inventory", "assets",
              "production", "multiplayer"]
MECH_TITLES = {"character": "Персонаж", "craft": "Крафт", "research": "Исследование",
               "weather": "Погода и свет", "npc": "NPC и фракции", "quests": "Квесты",
               "locations": "Локации", "destruction": "Разрушаемость", "physics": "Физика",
               "zombies": "Зомби", "combat": "Бой", "inventory": "Инвентарь и лут",
               "assets": "3D-модели и ассеты", "production": "Аудио, UI, проект",
               "multiplayer": "Сетевая игра"}


def esc(s):
    return html.escape(str(s), quote=False)


def inline_md(s):
    """**жирный**, *курсив*, `код`, [текст](url) и голые URL — как на сайте, только без JS.

    Каждый найденный фрагмент прячется в keep и возвращается на место в конце,
    но уже одним проходом по готовой строке: так `код` и ссылки не склеиваются
    с соседним курсивом и не лезут внутрь чужого тега
    и не рождается битая вложенность вида <code><i></code></i>.
    """
    keep = []

    def stash(tag):
        keep.append(tag)
        return chr(0) + str(len(keep) - 1) + chr(0)

    out = esc(s)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
                 lambda m: stash('<a href="%s">%s</a>' % (m.group(2), m.group(1))), out)
    out = re.sub(r"`([^`]+)`", lambda m: stash("<code>%s</code>" % m.group(1)), out)
    out = re.sub(r"\*\*([^*]+)\*\*", lambda m: stash("<b>%s</b>" % m.group(1)), out)
    out = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", lambda m: stash("<i>%s</i>" % m.group(1)), out)
    out = re.sub(r'(?<!href=")(?<!">)(?<![\w/])((?:https?://)[^\s<>()]+[^\s<>().,;])',
                 lambda m: stash('<a href="%s">%s</a>' % (m.group(1), m.group(1))), out)
    # Возвращаем спрятанное в несколько проходов: фрагмент может содержать
    # другой фрагмент (ссылка внутри `кода`), и после первой замены в тексте
    # остаётся сирота-плейсхолдер, который больше никто не подставит.
    for _ in range(6):
        nxt = re.sub(chr(0) + r"(\d+)" + chr(0), lambda m: keep[int(m.group(1))], out)
        if nxt == out:
            break
        out = nxt
    if chr(0) in out:
        raise SystemExit("inline_md: плейсхолдеры не разошлись: " + repr(s)[:140])
    return out


def img_tag(rel):
    """Картинку тащим внутрь файла; не смогли — ссылка на репозиторий."""
    if not rel:
        return ""
    if re.match(r"^https?://", rel):
        return '<a href="%s">картинка в репозитории ↗</a>' % esc(rel)
    p = os.path.join(CONTENT, rel)
    if os.path.exists(p):
        data = base64.b64encode(io.open(p, "rb").read()).decode("ascii")
        mime = "image/svg+xml" if rel.endswith(".svg") else "image/webp"
        return '<img src="data:%s;base64,%s" alt="%s">' % (mime, data, esc(os.path.basename(rel)))
    return '<a href="%s/%s">файл картинки в репозитории ↗</a>' % (RAW, esc(rel))


def video_src(rel):
    """(что подставить в src, что дать в ссылку «скачать»).

    В режиме архива src локальный — ролик играется прямо с диска; ссылка при
    этом ведёт в репозиторий, чтобы файл можно было достать и оттуда.
    """
    if re.match(r"^https?://", rel):
        return rel, rel
    if VIDEO_DIR:
        VIDEOS.append(rel)
        return "%s/%s" % (VIDEO_DIR, os.path.basename(rel)), "%s/%s" % (RAW, rel)
    return "%s/%s" % (RAW, rel), "%s/%s" % (RAW, rel)


def site_stamp():
    """Сборка сайта из app.js — тогда в читалке тот же номер, что в шапке."""
    m = re.search(r'SITE_BUILD\s*=\s*' + '"([^"]+)"',
                  io.open(os.path.join(SRC, "app.js"), encoding="utf-8").read())
    return m.group(1) if m else ""


def render_block(b):
    t = b.get("type")
    if t == "h":
        return '<h3 id="%s">%s</h3>' % (slug(b.get("text", "")), inline_md(b.get("text", "")))
    if t == "p":
        txt = b.get("text") or []
        if isinstance(txt, str):
            txt = [txt]
        return "".join("<p>%s</p>" % inline_md(x) for x in txt)
    if t == "note":
        return '<div class="note">%s</div>' % inline_md(b.get("text", ""))
    if t == "list":
        tag = "ol" if b.get("ordered") else "ul"
        return "<%s class='blocks'>%s</%s>" % (tag, "".join("<li>%s</li>" % inline_md(i) for i in b.get("items", [])), tag)
    if t == "todo":
        items = b.get("items", [])
        return "<ul class='todo'>%s</ul>" % "".join(
            "<li><span>%s</span>%s</li>" % ("☑" if i.get("done") else "☐", inline_md(i.get("text", "")))
            for i in items)
    if t == "kv":
        head = "".join("<th>%s</th>" % inline_md(h) for h in b.get("head", []))
        rows = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline_md(c) for c in r) for r in b.get("rows", []))
        return "<div class='tw'><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>" % (head, rows)
    if t == "code":
        return '<pre class="code"><code>%s</code></pre>' % esc(b.get("code", ""))
    if t == "image":
        return "<figure>%s<figcaption>%s</figcaption></figure>" % (img_tag(b.get("src")), inline_md(b.get("caption", "")))
    if t == "video":
        rel = b.get("src", "")
        url, dl = video_src(rel)
        poster = ""
        if b.get("poster") and os.path.exists(os.path.join(CONTENT, b["poster"])):
            data = base64.b64encode(io.open(os.path.join(CONTENT, b["poster"]), "rb").read()).decode("ascii")
            poster = ' poster="data:image/webp;base64,%s"' % data
        return ("<figure class='vid'><video controls playsinline preload=\"none\"%s src=\"%s\"></video>"
                "<figcaption>%s · <a href=\"%s\">скачать файл ↗</a></figcaption></figure>"
                % (poster, esc(url), inline_md(b.get("caption", "")), esc(dl)))
    return "<p>%s</p>" % inline_md(b.get("text", "") if isinstance(b.get("text"), str) else "")


def slug(s):
    m = {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z",
         "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
         "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch",
         "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya", " ": "-", "«": "", "»": "",
         "·": "-", "—": "-", ":": "", ",": "", ".": "", "!": "", "?": "", "(": "", ")": ""}
    out = "".join(m.get(c, c) for c in str(s).lower())
    out = re.sub(r"[^a-z0-9-]", "", out)
    out = re.sub(r"-+", "-", out).strip("-")
    return out[:48] or "s"


def render_doc(path, fallback_title):
    d = json.load(io.open(path, encoding="utf-8"))
    anchor = slug(d.get("id") or fallback_title)
    parts = ['<section class="doc" id="%s">' % anchor,
             '<h2>%s</h2>' % esc(d.get("title") or fallback_title)]
    if d.get("subtitle"):
        parts.append('<p class="sub">%s</p>' % inline_md(d["subtitle"]))
    bits = ["статус: " + esc(d.get("status", "?")), "обновлён: " + esc(d.get("updated", "?")),
            "файл: " + esc(os.path.basename(path))]
    parts.append('<p class="meta">%s</p>' % " · ".join(bits))
    for b in d.get("blocks", []):
        parts.append(render_block(b))
    if d.get("glossary"):
        gl = "".join("<dt>%s</dt><dd>%s</dd>" % (inline_md(k), inline_md(v)) for k, v in d["glossary"])
        parts.append("<div class='gloss'><h4>Словарь</h4><dl>%s</dl></div>" % gl)
    parts.append("</section>")
    return d.get("title") or fallback_title, anchor, "".join(parts)


def render_md(path, title):
    """USAGE.md и AGENT-GUIDE.md — маленький конвертер: заголовки, списки, таблицы, код."""
    src = io.open(path, encoding="utf-8").read().replace(chr(13), "").split(chr(10))
    out, i, in_code = [], 0, False
    while i < len(src):
        line = src[i]
        if line.startswith("```"):
            if not in_code:
                buf = []
                i += 1
                while i < len(src) and not src[i].startswith("```"):
                    buf.append(src[i]); i += 1
                out.append('<pre class="code"><code>%s</code></pre>' % esc("\n".join(buf)))
                i += 1
                continue
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            lvl = min(len(m.group(1)) + 1, 5)
            out.append("<h%d>%s</h%d>" % (lvl, inline_md(m.group(2)), lvl))
        elif re.match(r"^\|", line):
            buf = []
            while i < len(src) and re.match(r"^\|", src[i]):
                buf.append(src[i]); i += 1
            i -= 1
            rows = [[c.strip() for c in r.strip().strip("|").split("|")] for r in buf]
            rows = [r for r in rows if not all(re.match(r"^:?-{2,}:?$", c or "-") for c in r)]
            if rows:
                head = "".join("<th>%s</th>" % inline_md(c) for c in rows[0])
                body = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline_md(c) for c in r) for r in rows[1:])
                out.append("<div class='tw'><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>" % (head, body))
        elif re.match(r"^\s*[-*]\s+", line):
            buf = []
            while i < len(src) and re.match(r"^\s*[-*]\s+", src[i]):
                buf.append(re.sub(r"^\s*[-*]\s+", "", src[i])); i += 1
            i -= 1
            out.append("<ul class='blocks'>%s</ul>" % "".join("<li>%s</li>" % inline_md(x) for x in buf))
        elif re.match(r"^\s*\d+\.\s+", line):
            buf = []
            while i < len(src) and re.match(r"^\s*\d+\.\s+", src[i]):
                buf.append(re.sub(r"^\s*\d+\.\s+", "", src[i])); i += 1
            i -= 1
            out.append("<ol class='blocks'>%s</ol>" % "".join("<li>%s</li>" % inline_md(x) for x in buf))
        elif line.strip() == "":
            pass
        else:
            out.append("<p>%s</p>" % inline_md(line))
        i += 1
    return ('<section class="doc" id="%s"><h2>%s</h2><p class="meta">файл: %s</p>%s</section>'
            % (slug(title), esc(title), esc(os.path.relpath(path, ROOT)), "".join(out)))


CSS = """
:root{--bg:#0b1016;--bg2:#111a24;--tx:#dbe6f2;--tx2:#9fb0c6;--tx3:#6f849c;--line:#1e2a38;--acc:#7fd1ae}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--tx);font:16px/1.6 -apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif}
.wrap{display:grid;grid-template-columns:260px 1fr;gap:26px;max-width:1180px;margin:0 auto;padding:22px 18px 60px}
header.top{grid-column:1/-1;border-bottom:1px solid var(--line);padding-bottom:14px}
header.top h1{margin:0 0 6px;font-size:26px}
header.top p{margin:0;color:var(--tx2);font-size:14px}
nav{position:sticky;top:14px;align-self:start;font-size:13.5px;max-height:calc(100vh - 40px);overflow:auto}
nav a{display:block;color:var(--tx2);text-decoration:none;padding:4px 8px;border-radius:7px}
nav a:hover{background:var(--bg2);color:var(--tx)}
nav .grp{color:var(--tx3);text-transform:uppercase;letter-spacing:.7px;font-size:11px;margin:12px 0 4px 8px}
main{min-width:0}
section.doc{background:var(--bg2);border:1px solid var(--line);border-radius:14px;padding:6px 22px 20px;margin:0 0 22px;scroll-margin-top:14px}
section.doc h2{font-size:22px;margin:18px 0 4px}
section.doc h3{font-size:17px;margin:26px 0 6px;color:var(--acc);border-bottom:1px dashed var(--line);padding-bottom:6px}
section.doc h4,section.doc h5{margin:18px 0 6px;color:var(--tx2);font-size:14px;text-transform:uppercase;letter-spacing:.6px}
.sub{color:var(--tx2);margin:0 0 6px}
.meta{color:var(--tx3);font-size:12.5px;margin:0 0 10px}
.note{background:#0e1a24;border-left:3px solid var(--acc);border-radius:0 10px 10px 0;padding:10px 14px;margin:12px 0;color:#c6d6e6;font-size:15px}
ul.blocks,ol.blocks{margin:10px 0;padding-left:22px}
ul.blocks li,ol.blocks li{margin:0 0 7px}
ul.todo{list-style:none;padding-left:2px;margin:10px 0}
ul.todo li{margin:0 0 6px}
ul.todo span{color:var(--acc);margin-right:8px}
code{background:#0a1118;border:1px solid var(--line);border-radius:5px;padding:1px 5px;font-family:ui-monospace,"Cascadia Mono",Menlo,Consolas,monospace;font-size:13px;color:#cdd9e5}
pre.code{background:#080e14;border:1px solid var(--line);border-radius:10px;padding:12px 14px;overflow:auto;margin:12px 0}
pre.code code{border:0;background:none;padding:0;font-size:12.8px;line-height:1.55;color:#c3d2e2;white-space:pre}
.tw{overflow:auto;margin:12px 0;border:1px solid var(--line);border-radius:10px}
table{border-collapse:collapse;width:100%;font-size:13.6px}
th,td{padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}
th{background:#0d1520;color:var(--tx2);font-weight:600;position:sticky;top:0}
tr:last-child td{border-bottom:0}
figure{margin:14px 0;background:#0d141c;border:1px solid var(--line);border-radius:12px;padding:10px}
figure img{max-width:min(560px,100%);border-radius:8px;display:block}
figcaption{color:var(--tx2);font-size:13px;margin-top:8px}
figure.vid video{width:100%;max-width:820px;border-radius:8px;display:block;background:#000}
.gloss{margin-top:18px;padding:12px 14px;background:#0e1621;border:1px dashed var(--line);border-radius:10px}
.gloss h4{margin:0 0 8px;font-size:12px;letter-spacing:.7px;text-transform:uppercase;color:var(--tx3)}
.gloss dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:0;font-size:13.5px}
.gloss dt{color:var(--acc)}
.gloss dd{margin:0;color:var(--tx2)}
a{color:#8fc7ff}
footer{grid-column:1/-1;color:var(--tx3);font-size:12.5px;border-top:1px solid var(--line);padding-top:14px;margin-top:8px}
@media print{body{background:#fff;color:#111}.wrap{grid-template-columns:1fr}nav{display:none}section.doc{border-color:#ccc;background:#fff}}
@media (max-width:900px){.wrap{grid-template-columns:1fr}nav{position:static;max-height:none}}
"""

parts = [CSS and "<style>%s</style>" % CSS]
toc, body = ['<div class="grp">Документы</div>'], []

title, anchor, doc = render_doc(os.path.join(CONTENT, "scenario.json"), "Сценарий")
toc.append('<a href="#%s">%s</a>' % (anchor, esc(title)))
body.append(doc)

toc.append('<div class="grp">Механика</div>')
for mid in MECH_ORDER:
    p = os.path.join(CONTENT, "mech_%s.json" % mid)
    if not os.path.exists(p):
        continue
    title, anchor, doc = render_doc(p, MECH_TITLES.get(mid, mid))
    toc.append('<a href="#%s">%s</a>' % (anchor, esc(MECH_TITLES.get(mid, title))))
    body.append(doc)

toc.append('<div class="grp">Витрина</div>')
title, anchor, doc = render_doc(os.path.join(CONTENT, "preview.json"), "Картинки и превью")
toc.append('<a href="#%s">%s</a>' % (anchor, esc(title)))
body.append(doc)

toc.append('<div class="grp">Инструкции</div>')
for f, t in [("docs/USAGE.md", "Как пользоваться сайтом"), ("docs/AGENT-GUIDE.md", "Инструкция для агента")]:
    p = os.path.join(SRC, f)
    if os.path.exists(p):
        toc.append('<a href="#%s">%s</a>' % (slug(t), esc(t)))
        body.append(render_md(p, t))

stamp = site_stamp() or json.load(io.open(os.path.join(CONTENT, "scenario.json"),
                                          encoding="utf-8")).get("updated", "?")
# Строчка про видео зависит от режима сборки: в архиве ролик лежит рядом,
# в репозитории — качается с github.com.
VNOTE = ("Видео лежат рядом, в папке <code>" + VIDEO_DIR + "/</code> — играются без интернета."
         if VIDEO_DIR else
         ("Видео подгружаются с github.com — если сеть не отдает, файл лежит в репозитории, "
          "папка <code>game-docs/src/content/video/</code>."))
SENT = ("Видео подгружаются с github.com — если сеть не отдает, файл лежит в репозитории, "
        "папка <code>game-docs/src/content/video/</code>.")
html_doc = (
 "<!doctype html><html lang='ru'><head><meta charset='utf-8'>"
 "<meta name='viewport' content='width=device-width,initial-scale=1'>"
 "<title>Пепел и Звёзды · вся библия (офлайн-читалка)</title>%s</head><body><div class='wrap'>"
 "<header class='top'><h1>Пепел и Звёзды · вся библия одним файлом</h1>"
 "<p>Сценарий, 15 разделов механики, витрина с заставками и обе инструкции — без сайта и без интернета. "
 "Собрано из <code>game-docs/src/content/*.json</code> генератором "
 "<code>game-docs/tools/build_offline_reader.py</code>; состояние на %s. "
 "Видео подгружаются с github.com — если сеть не отдает, файл лежит в репозитории, "
 "папка <code>game-docs/src/content/video/</code>.</p></header>"
 "<nav>%s</nav><main>%s</main>"
 "<footer>Это собранная копия, не правьте её руками: источник — JSON в репозитории, "
 "пересборка — <code>python3 game-docs/tools/build_offline_reader.py</code>.</footer>"
 "</div></body></html>" % (parts[0], esc(stamp), "".join(toc), "".join(body)))

html_doc = html_doc.replace(SENT, VNOTE)
if VIDEO_DIR:
    dst = os.path.join(os.path.dirname(OUT), VIDEO_DIR)
    os.makedirs(dst, exist_ok=True)
    for rel in sorted(set(VIDEOS)):
        srcf = os.path.join(CONTENT, rel)
        if os.path.exists(srcf):
            shutil.copy2(srcf, os.path.join(dst, os.path.basename(rel)))

io.open(OUT, "w", encoding="utf-8").write(html_doc)
print("читалка:", OUT, "·", round(len(html_doc) / 1024.0), "КБ ·", len(body), "документов")
