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

console.log(fail ? "\nПРОВАЛ: " + fail + " проверок" : "\nвсе проверки пройдены");
process.exit(fail ? 1 : 0);
