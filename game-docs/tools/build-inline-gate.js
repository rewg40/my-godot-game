#!/usr/bin/env node
// Собирает self-contained сторож index.html из tools/inline-watchdog.js.
// Код доступа удалён: рабочая ссылка сразу открывает редактор. Сторож остаётся,
// чтобы старый/незагруженный app.js не выглядел как «вкладки не реагируют».
// Запуск после правки src/app.js или tools/inline-watchdog.js:
//   node game-docs/tools/build-inline-gate.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const NL = String.fromCharCode(10);
const SRC = path.join(__dirname, "..", "src");
const app = fs.readFileSync(path.join(SRC, "app.js"), "utf8");
const SITE_BUILD = (app.match(/const SITE_BUILD = "([^"]*)"/) || [, "?"])[1];
const escAttr = (t) => String(t).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const watchdog = fs.readFileSync(path.join(__dirname, "inline-watchdog.js"), "utf8").trim();

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
    i++;
  }
  return 0;
}
const ln = findBlockComment(watchdog);
if (ln) { console.error("inline-watchdog.js: блок-комментарий в коде на строке " + ln); process.exit(1); }
try { new vm.Script(watchdog, { filename: "inline-watchdog.js" }); }
catch (e) { console.error("СИНТАКСИС inline-watchdog.js: " + e.message); process.exit(1); }

const p = path.join(SRC, "index.html");
let html = fs.readFileSync(p, "utf8");
html = html.replace(/\s*<!-- INLINE-GATE:START -->[\s\S]*?<!-- INLINE-GATE:END -->\s*/g, "\n");
if (/id="gate"/.test(html)) { console.error("index.html всё ещё содержит #gate — удали экран кода"); process.exit(1); }

function insertBlock(startMark, endMark, inner) {
  const a = html.indexOf(startMark);
  if (a < 0) throw new Error("в index.html нет маркера " + startMark);
  const after = a + startMark.length;
  const b = html.indexOf(endMark, after);
  if (b < 0) throw new Error("в index.html нет парного " + endMark);
  const s0 = html.indexOf("<script>", after);
  const e1 = s0 >= 0 && s0 < b ? html.indexOf("</script>", s0) : -1;
  const from = s0 >= 0 && s0 < b ? s0 : after;
  const to = e1 > 0 ? e1 + 9 : b;
  html = html.slice(0, from) + "<script>" + NL + inner + NL + "</script>" + NL + html.slice(to);
}
if (html.indexOf("<!-- ZOMBI-WATCHDOG:START -->") < 0) {
  html = html.replace("</body>", "  <!-- ZOMBI-WATCHDOG:START -->" + NL + "  <!-- ZOMBI-WATCHDOG:END -->" + NL + "</body>", 1);
}
insertBlock("<!-- ZOMBI-WATCHDOG:START -->", "<!-- ZOMBI-WATCHDOG:END -->", watchdog);
html = html.replace(/<html\b[^>]*>/, (m) => m.replace(/\s*data-build="[^"]*"/, "").replace(/>$/, ' data-build="' + escAttr(SITE_BUILD) + '">'));
if (/<script>\s*<script>/.test(html)) { console.error("в index.html дубль <script>"); process.exit(1); }
const a2 = html.indexOf("<!-- ZOMBI-WATCHDOG:START -->"), b2 = html.indexOf("<!-- ZOMBI-WATCHDOG:END -->", a2);
const s0 = html.indexOf("<script>", a2), e1 = s0 > 0 && s0 < b2 ? html.indexOf("</script>", s0) : -1;
if (s0 < 0 || e1 < 0) { console.error("сторож: между маркерами нет целого <script>"); process.exit(1); }
const body = html.slice(s0 + 8, e1);
try { new vm.Script(body, { filename: "watchdog (index.html)" }); }
catch (e) { console.error("сторож: код между маркерами не компилируется - " + e.message); process.exit(1); }
if (body.trim() !== watchdog.trim()) { console.error("сторож: в index.html попала другая версия"); process.exit(1); }
html = html.replace(/\n{3,}/g, "\n\n");
fs.writeFileSync(p, html);
console.log("сторож " + watchdog.length + " B встроен; код доступа удалён; build " + SITE_BUILD);
