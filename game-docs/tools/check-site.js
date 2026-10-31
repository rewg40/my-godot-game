#!/usr/bin/env node
/* Самопроверка сайта перед деплоем.
   node game-docs/tools/check-site.js
   1) app.js синтаксически валиден и шапка IIFE цела;
   2) нет вызовов функций, которые нигде не определены (ловит класс багов «patch съел определение»);
   3) все id из app.js есть в index.html (или создаются самим app.js);
   4) sha256Pure совпадает с эталоном на 8 кейсах;
   5) все content/*.json парсятся. */
const fs = require("fs"), path = require("path"), vm = require("vm"), crypto = require("crypto");
const SRC = process.env.SITE_DIR || path.join(__dirname, "..", "src");
const rd = (f) => fs.readFileSync(path.join(SRC, f), "utf8");
let fail = 0;
const ok = (cond, name, extra) => { console.log((cond ? "  ok  " : "  FAIL ") + name + (extra ? " — " + extra : "")); if (!cond) fail++; };

/* 1 */
const app = rd("app.js");
let syntax = true, err = "";
try { new vm.Script(app, { filename: "app.js" }); } catch (e) { syntax = false; err = e.message; }
ok(syntax, "app.js: синтаксис", err);
ok(/^\s*\/\*[\s\S]*?\*\/\s*\(\(\)\s*=>\s*\{[\s\S]{0,80}?"use strict";/.test(app), "app.js: шапка IIFE цела");
ok(/\n\}\)\(\);?\s*$/.test(app) || /\}\)\(\);\s*$/.test(app), "app.js: IIFE закрыта в конце файла");

/* 2 */
const called = new Set([...app.matchAll(/(?<![\w.$])([A-Za-z_$][\w$]*)\s*\(/g)].map((m) => m[1]));
const defined = new Set([
  ...[...app.matchAll(/function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map((m) => m[1]),
  ...[...app.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\(|function)/g)].map((m) => m[1]),
  ...[...app.matchAll(/([A-Za-z_$][\w$]*)\s*\(.*\)\s*=>/g)].map((m) => m[1]),
]);
const GLOBALS = new Set(["if","for","while","switch","catch","return","typeof","function","new","await","console","require","parseInt","parseFloat","isNaN","String","Number","Boolean","Array","Object","JSON","Math","Date","Set","Map","Promise","Error","RegExp","Uint8Array","Uint16Array","Uint32Array","Int8Array","Int16Array","Int32Array","Float32Array","Float64Array","ArrayBuffer","DataView","TextEncoder","TextDecoder","encodeURIComponent","decodeURIComponent","encodeURI","decodeURI","fetch","setTimeout","clearTimeout","setInterval","clearInterval","AbortController","FormData","Blob","File","FileReader","Image","URL","URLSearchParams","Response","Request","Headers","Event","CustomEvent","DOMParser","XMLHttpRequest","Audio","Worker","crypto","localStorage","document","window","navigator","location","history","alert","confirm","prompt","structuredClone","queueMicrotask","requestAnimationFrame","createImageBitmap","matchMedia","getComputedStyle","ResizeObserver","IntersectionObserver","MutationObserver","EventSource","Symbol","BigInt","Proxy","Reflect","escape","unescape","globalThis","addEventListener","removeEventListener","btoa","atob","import","async","var","fn","res","ok","b","content","docs"]);
const missing = [...called].filter((c) => !defined.has(c) && !GLOBALS.has(c) && !/^[A-Z]/.test(c)).sort();
ok(missing.length === 0, "app.js: нет вызовов без определения", missing.slice(0, 8).join(", "));

/* 3 */
const html = rd("index.html");
const htmlIds = new Set([...html.matchAll(/id="([\w-]+)"/g)].map((m) => m[1]));
const jsIds = new Set([...app.matchAll(/getElementById\("([\w-]+)"\)/g)].map((m) => m[1]).concat([...app.matchAll(/\$\("#([\w-]+)"/g)].map((m) => m[1])));
const madeInJs = new Set([...app.matchAll(/id="([\w-]+)"/g)].map((m) => m[1]));
const dynamic = new Set([...app.matchAll(/\$\(`#([\w-]+)(?:-|"|\$\{|")/g)].map((m) => m[1]));
const absent = [...jsIds].filter((i) => !htmlIds.has(i) && !madeInJs.has(i) && !dynamic.has(i) && !/^st-|^dg-|^ed-|^im-|^up-|^m-/.test(i)).sort();
ok(absent.length === 0, "id из app.js существуют в index.html", absent.slice(0, 8).join(", "));

/* 4 */
const i = app.indexOf("function sha256Pure"), j = app.indexOf("async function sha256Hex");
let hashOk = false, note = "не найдены якоря";
if (i >= 0 && j > i) {
  const ctx = {}; vm.createContext(ctx);
  try {
    vm.runInContext(app.slice(i, j) + "\nthis.f = sha256Pure;", ctx);
    const cases = ["", "abc", "ZOMBI-2026", "Привет, мир · 🧟", "a".repeat(55), "b".repeat(64), "c".repeat(119), "d".repeat(10000)];
    hashOk = cases.every((t) => ctx.f(t) === crypto.createHash("sha256").update(Buffer.from(t, "utf8")).digest("hex"));
    note = hashOk ? "8/8 кейсов" : "расхождение с эталоном";
  } catch (e) { note = e.message; }
}
ok(hashOk, "sha256Pure == эталон", note);

/* 5 */
const dir = path.join(SRC, "content");
let badjson = [];
if (!fs.existsSync(dir)) { console.log("  skip  content/*.json — каталог не задан (SITE_DIR без content)"); }
else for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".json"))) {
  try { JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); } catch (e) { badjson.push(f); }
}
ok(badjson.length === 0, "content/*.json парсятся", badjson.join(", "));

let cfg = { gate: {} }; try { cfg = JSON.parse(rd("config.json")); } catch (e) {}
const owner = crypto.createHash("sha256").update("ZOMBI-2026", "utf8").digest("hex");
ok(cfg.gate.ownerCode === owner, "config: ownerCode == sha256(ZOMBI-2026)");
ok(app.includes('FALLBACK_OWNER_HASH') && /h === FALLBACK_OWNER_HASH/.test(app), "вход не зависит от config.json (есть синхронная сверка)");
ok(/nc=/.test(html) && /gate-fallback/.test(html), "index.html: анти-кэш загрузчик на месте");
ok(/INLINE-GATE:START/.test(html) && /OWNER_HASH/.test(html) && /function sha256Pure/.test(html), "index.html: встроенный замок собран (свой sha256Pure + ownerCode)");
ok(/<!-- INLINE-GATE:START -->[\s\S]*OWNER_HASH = "([0-9a-f]{64})"/.test(html) && RegExp.$1 === owner, "index.html: ownerCode встроенного замка == sha256(ZOMBI-2026)");
ok(html.lastIndexOf("INLINE-GATE:START") < html.lastIndexOf("INLINE-GATE:END"), "index.html: разметка inline-замка не размножилась");
const mBuild = html.match(/<html[^>]*data-build="([^"]*)"/);
const mJs = app.match(/const SITE_BUILD = "([^"]*)"/);
ok(!!mBuild && !!mJs && mBuild[1].replace(/&quot;/g, '"') === mJs[1], "index.html: штамп data-build == SITE_BUILD в app.js",
   (mBuild ? mBuild[1] : "нет data-build") + " vs " + (mJs ? mJs[1] : "нет SITE_BUILD"));

/* 6. [hidden] должен побеждать display из классов: без этого .gate/.modal-root оставались
   полупрозрачным слоем поверх страницы — «экран затемнён, вход есть, но не активен». */
let css = "";
try { css = fs.readFileSync(path.join(SRC, "app.css"), "utf8"); } catch (e) {}
if (css) {
  ok(/\[hidden\]\s*\{\s*display:\s*none\s*!important\s*;?\s*\}/.test(css), "app.css: [hidden]{display:none !important} есть");
  const toggled = new Set([
    ...[...html.matchAll(/id="([\w-]+)"[^>]*\bhidden\b/g)].map((m) => m[1]),
    ...[...app.matchAll(/\$\("#([\w-]+)"\)\.hidden\s*=/g)].map((m) => m[1]),
  ]);
  const hiddenWins = /\[hidden\]\s*\{\s*display:\s*none\s*!important/.test(css);
  const risky = new Set();
  for (const m of css.matchAll(/([^{}]+)\{([^}]*)\}/g)) {
    const body = m[2];
    if (!/display:\s*(grid|flex|block|inline-flex|inline-block)/.test(body)) continue;
    for (const one of m[1].split(",")) {
      const t = one.trim().match(/^#([\w-]+)$/);
      if (t && toggled.has(t[1])) risky.add("#" + t[1]);
      const c = one.trim().match(/^\.([\w-]+)$/);
      if (c) for (const id of toggled) {
        const el = html.match(new RegExp('id="' + id + '"[^>]*class="([^"]*)"'));
        if (el && el[1].split(/\s+/).includes(c[1])) risky.add("." + c[1] + " ↔ #" + id);
      }
    }
  }
  ok(hiddenWins || risky.size === 0, "app.css: скрытые слоем элементы реально display:none",
     hiddenWins ? "конфликты " + risky.size + " шт. закрыты правилом [hidden]{…!important}" : [...risky].slice(0, 6).join(", "));
} else { console.log("  skip  app.css не найден (SITE_DIR без стилей)"); }

/* 7. самодостаточные блоки в index.html: замок в <head> и сторож кликов перед </body>.
      Они обязаны пережить старый/незагруженный app.js — иначе «вкладки не реагируют»
      и человек не получает никакого объяснения. */
{
  const vm = require("vm");
  const block = (startMark, endMark) => {
    const a = html.indexOf(startMark), b = html.indexOf(endMark, a);
    if (a < 0 || b < 0) return null;
    const s0 = html.indexOf("<script>", a), e1 = s0 > 0 ? html.indexOf("</script>", s0) : -1;
    if (s0 < 0 || e1 < 0 || e1 > b) return "";
    return html.slice(s0 + 8, e1);
  };
  const N = (x) => (html.match(new RegExp(x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) || []).length;
  ok(N("<!-- INLINE-GATE:START -->") === 1 && N("<!-- INLINE-GATE:END -->") === 1, "index.html: замок встроен ровно один раз");
  ok(N("<!-- ZOMBI-WATCHDOG:START -->") === 1 && N("<!-- ZOMBI-WATCHDOG:END -->") === 1, "index.html: сторож встроен ровно один раз");
  const gateCode = block("<!-- INLINE-GATE:START -->", "<!-- INLINE-GATE:END -->");
  const wdCode = block("<!-- ZOMBI-WATCHDOG:START -->", "<!-- ZOMBI-WATCHDOG:END -->");
  for (const [name, code, must] of [
    ["замок", gateCode, /OWNER_HASH = "[0-9a-f]{64}"/],
    ["сторож", wdCode, /__ZOMBI_CLICKS__|__ZOMBI_DIAG__/],
  ]) {
    if (code === null) { ok(false, name + ": между маркерами нет <script>", "сгенерируй: node game-docs/tools/build-inline-gate.js"); continue; }
    ok(code !== "", name + ": <script> цел (не обрезан блок-комментарием)");
    let parsed = false, err = "";
    try { new vm.Script(code, { filename: name }); parsed = true; } catch (e) { err = e.message; }
    ok(parsed, name + ": синтаксис чистый", err || (code.length + " B"));
    ok(must.test(code), name + ": нужная логика на месте", must.source.slice(0, 28));
  }
  const wPos = html.indexOf("<!-- ZOMBI-WATCHDOG:START -->");
  ok(wPos > html.indexOf('id="main-tabs"') && wPos < html.indexOf("</body>"), "сторож стоит после разметки и перед </body>");
  const boot = app.slice(app.indexOf("function earlyBoot()"));
  const wireAt = boot.search(/wireChrome\(\);\s*buildMainTabs\(\)/);
  const guardAt = boot.indexOf("guardStaleBuild()");
  ok(wireAt >= 0 && (guardAt < 0 || wireAt < guardAt), "app.js: вкладки wire-ятся ДО стража кэша (в earlyBoot)", guardAt < 0 ? "стража нет" : "wire=" + wireAt + " guard=" + guardAt);
  ok(/document\.readyState === "loading"/.test(app) && /else boot\(\);/.test(app), "app.js: запуск и при loading, и при готовом документе");
}

/* 8. загрузчик в index.html: без app.js страница обязана остаться объясняющей,
      а с app.js из зеркала — обязана запускаться (DOMContentLoaded мог уже пройти). */
{
  const a = html.indexOf("// === SITE-LOADER");
  ok(a > 0, "index.html: блок SITE-LOADER на месте");
  const ldr = a > 0 ? html.slice(a, html.indexOf("</script>", a)) : "";
  ok(/__ZOMBI_SOURCES__/.test(ldr) && /MIRRORS\.length/.test(ldr), "загрузчик перебирает зеркала (app.js/app.css не только с github.io)");
  ok(/__ZOMBI_BASE__/.test(ldr), "загрузчик сообщает сайту, откуда приехали файлы (window.__ZOMBI_BASE__)");
  ok(/mirror=/.test(ldr), "загрузчик понимает ?mirror=<адрес>/ для ручного зеркала");
  ok(ldr.indexOf("/raw/") > 0 && ldr.indexOf("github.com/") > 0,
     "загрузчик пробует github.com/raw (живёт, когда github.io вырезан)");
  ok(/zombi-docs:src/.test(ldr), "загрузчик умеет ?src=<путь-в-репозитории>/ (для github.com/raw)");
  ok(/data-zombi-ok/.test(ldr), "загрузчик помечает удачно загруженный скрипт (сторож не паникует зря)");
  ok(/else boot\(\);/.test(app), "app.js: запуск не привязан к DOMContentLoaded (else boot())");
  ok(/window\.__ZOMBI_BASE__/.test(app), "app.js: знает адрес зеркала (window.__ZOMBI_BASE__)");
  ok(/const base = S\.base \|\| USER_BASE/.test(app), "app.js: loadText бьёт в зеркало первым запросом (до boot())");
}

console.log(fail ? "\nПРОВАЛ: " + fail + " проверок" : "\nвсе проверки пройдены");
process.exit(fail ? 1 : 0);
