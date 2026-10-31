#!/usr/bin/env node
// Собирает self-contained код index.html из двух исходников в game-docs/tools/:
//   inline-gate.js     -> в <head> между маркерами INLINE-GATE (замок: работает без app.js и без сети)
//   inline-watchdog.js -> перед </body> между маркерами ZOMBI-WATCHDOG (сторож кликов и ошибок)
// плюс пишет актуальный штамп версии в <html data-build="...">.
// Зачем: браузер может держать старый app.js (кэш github.io) или не загрузить его вовсе
// (блокировка). Тогда человек видит «вкладки не реагируют» и не может ничего сделать.
// Замок и сторож в самом HTML переживают такой исход: страница открывается, клики считаются,
// причина показана русским текстом с кнопкой «Перезагрузить начисто».
// Запуск после правки src/app.js или tools/inline-*.js:
//   node game-docs/tools/build-inline-gate.js
// Правила исходников: только ES5, внутри <script>, поэтому НИКАКИХ блок-комментариев в коде
// (они обрывают скрипт) и никаких переводов строки внутри строковых литералов (перенос в
// исходнике = синтаксическая ошибка). Нужен перевод строки - String.fromCharCode(10).
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const NL = String.fromCharCode(10);

const SRC = path.join(__dirname, "..", "src");
const app = fs.readFileSync(path.join(SRC, "app.js"), "utf8");
const cfg = JSON.parse(fs.readFileSync(path.join(SRC, "config.json"), "utf8"));

const OWNER = (cfg.gate.ownerCode || "").toLowerCase();
if (!/^[0-9a-f]{64}$/.test(OWNER)) {
  console.error("gate.ownerCode в config.json должен быть 64-символьным hex - встраивать нечего");
  process.exit(1);
}
const SITE_BUILD = (app.match(/const SITE_BUILD = "([^"]*)"/) || [, "?"])[1];

// хэш кода доступа считается одной и той же функцией, что и в app.js
function shaSource() {
  const i = app.indexOf(NL + "function sha256Pure");
  const j = app.indexOf(NL + "async function sha256Hex");
  if (i < 0 || j < 0) throw new Error("не нашёл sha256Pure / sha256Hex в app.js");
  return app.slice(i + 1, j).trim();
}

const escAttr = (t) => String(t).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const readTool = (f) => fs.readFileSync(path.join(__dirname, f), "utf8").trim();

const gate = readTool("inline-gate.js")
  .replace(/\$\{shaFn\}/g, shaSource())
  .replace(/\$\{OWNER_HASH\}/g, OWNER);
const watchdog = readTool("inline-watchdog.js");

if (!new RegExp('OWNER_HASH = "' + OWNER + '"').test(gate)) {
  console.error("в inline-gate.js не подставился OWNER_HASH - проверь плейсхолдер");
  process.exit(1);
}

// поиск блок-комментария в КОДЕ (строки, регулярки и строчные комментарии не считаем)
function findBlockComment(code) {
  let i = 0, line = 1;
  const n = code.length;
  while (i < n) {
    const c = code[i];
    if (c === NL) { line++; i++; continue; }
    if (c === "/" && code[i + 1] === "/") { const e = code.indexOf(NL, i); i = e < 0 ? n : e; continue; }
    if (c === '"' || c === "'") {
      const q = c; i++;
      while (i < n && code[i] !== q) { if (code[i] === "\\") i++; if (code[i] === NL) line++; i++; }
      i++; continue;
    }
    if (c === "/" && code[i + 1] === "*") return line;
    if (c === "/") {
      let k = i - 1;
      while (k >= 0 && /\s/.test(code[k])) k--;
      if (k < 0 || "=([{,;:&|!?+".indexOf(code[k]) >= 0) {
        i += 2;
        let cls = false;
        while (i < n) {
          const d = code[i];
          if (d === "\\") { i += 2; continue; }
          if (d === NL) return line;
          if (d === "[") cls = true;
          else if (d === "]") cls = false;
          else if (d === "/" && !cls) break;
          i++;
        }
        i++; continue;
      }
    }
    if (c === NL) line++;
    i++;
  }
  return 0;
}

for (const [name, code] of [["inline-gate.js", gate], ["inline-watchdog.js", watchdog]]) {
  const ln = findBlockComment(code);
  if (ln) {
    console.error(name + ": блок-комментарий в коде на строке " + ln + " - внутри <script> он оборвёт скрипт, замени на //");
    process.exit(1);
  }
  try {
    new vm.Script(code, { filename: name });
  } catch (e) {
    console.error("СИНТАКСИС " + name + ": " + e.message);
    process.exit(1);
  }
}

const p = path.join(SRC, "index.html");
let html = fs.readFileSync(p, "utf8");

function insertBlock(startMark, endMark, inner) {
  const a = html.indexOf(startMark);
  if (a < 0) throw new Error("в index.html нет маркера " + startMark);
  const after = a + startMark.length;
  const b = html.indexOf(endMark, after);
  if (b < 0) throw new Error("в index.html нет парного " + endMark);
  // если между маркерами уже есть <script>...</script> - заменяем его целиком, иначе вставляем новый
  const s0 = html.indexOf("<script>", after);
  const e1 = s0 >= 0 && s0 < b ? html.indexOf("</script>", s0) : -1;
  const from = s0 >= 0 && s0 < b ? s0 : after;
  const to = e1 > 0 ? e1 + 9 : b;
  html = html.slice(0, from) + "<script>" + NL + inner + NL + "</script>" + NL + html.slice(to);
}

if (html.indexOf("<!-- INLINE-GATE:START -->") < 0) {
  html = html.replace(/<head>/, (m) => m + NL + "  <!-- INLINE-GATE:START -->" + NL + "  <!-- INLINE-GATE:END -->" + NL);
}
insertBlock("<!-- INLINE-GATE:START -->", "<!-- INLINE-GATE:END -->", gate);

if (html.indexOf("<!-- ZOMBI-WATCHDOG:START -->") < 0) {
  html = html.replace("</body>", "  <!-- ZOMBI-WATCHDOG:START -->" + NL + "  <!-- ZOMBI-WATCHDOG:END -->" + NL + "</body>", 1);
}
insertBlock("<!-- ZOMBI-WATCHDOG:START -->", "<!-- ZOMBI-WATCHDOG:END -->", watchdog);

// штамп сборки: app.js сверяет его со своим SITE_BUILD и видит устаревший кэш
html = html.replace(/<html\b[^>]*>/, (m) => m.replace(/\s*data-build="[^"]*"/, "")
  .replace(/>$/, ' data-build="' + escAttr(SITE_BUILD) + '">'));

if (/<script>\s*<script>/.test(html)) { console.error("в index.html дубль <script> - генератор сломался"); process.exit(1); }
/* финальная самопроверка: перечитываем то, что реально лежит между маркерами, и компилируем.
   Так ловится и «скрипт обрезался досрочно», и лишний </script> внутри строки. */
for (const [name, startMark, endMark] of [["замок", "<!-- INLINE-GATE:START -->", "<!-- INLINE-GATE:END -->"],
                                         ["сторож", "<!-- ZOMBI-WATCHDOG:START -->", "<!-- ZOMBI-WATCHDOG:END -->"]]) {
  const a2 = html.indexOf(startMark), b2 = html.indexOf(endMark, a2);
  const s0 = html.indexOf("<script>", a2), e1 = s0 > 0 && s0 < b2 ? html.indexOf("</script>", s0) : -1;
  if (s0 < 0 || e1 < 0) { console.error(name + ": между маркерами нет целого <script>"); process.exit(1); }
  const body = html.slice(s0 + 8, e1);
  try { new vm.Script(body, { filename: name + " (index.html)" }); }
  catch (e) { console.error(name + ": код между маркерами не компилируется - " + e.message); process.exit(1); }
  const want = name === "замок" ? gate : watchdog;
  if (body.trim() !== want.trim()) { console.error(name + ": в index.html попала другая версия (длина " + body.length + " против " + want.length + ")"); process.exit(1); }
}
// идемпотентность: повторный запуск не должен оставлять пустые строки между маркерами
html = html.replace(/\n{3,}/g, "\n\n");
fs.writeFileSync(p, html);
console.log("inline-gate " + gate.length + " B + сторож " + watchdog.length + " B встроены; build " + SITE_BUILD);
