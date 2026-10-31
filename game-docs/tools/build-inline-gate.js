#!/usr/bin/env node
/* Собирает встроенный замок в index.html: берёт sha256Pure из app.js (один источник истины)
   и вставляет в <head> self-contained скрипт, который проверяет код доступа СОВСЕМ БЕЗ
   app.js, config.json и сети. Запуск: node game-docs/tools/build-inline-gate.js
   Нужен, потому что браузер может держать старый/битый app.js, а замок — единственное,
   что тогда видит человек. */
const fs = require("fs"), path = require("path");
const SRC = path.join(__dirname, "..", "src");
const app = fs.readFileSync(path.join(SRC, "app.js"), "utf8");
const cfg = JSON.parse(fs.readFileSync(path.join(SRC, "config.json"), "utf8"));

const i = app.indexOf("function sha256Pure");
const j = app.indexOf("\nasync function sha256Hex");
if (i < 0 || j < 0) { console.error("не нашёл sha256Pure в app.js"); process.exit(1); }
const shaFn = app.slice(i, j).trim();

const OWNER = (cfg.gate.ownerCode || "").toLowerCase();
const escAttr = (t) => String(t).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const SITE_BUILD = (app.match(/const SITE_BUILD = "([^"]*)"/) || [, "?"])[1];
if (!/^[0-9a-f]{64}$/.test(OWNER)) { console.error("ownerCode в config.json не 64-символьный hex"); process.exit(1); }

const START = "/* === INLINE-GATE (автосборка: game-docs/tools/build-inline-gate.js) — не править вручную === */";
const END = "/* === /INLINE-GATE === */";
const block = `<script>
${START}
(function () {
  var OWNER_HASH = "${OWNER}";
  ${shaFn}
  window.__ZOMBI_INLINE_GATE__ = 1;   // app.js: обработчик встроенного замка важнее
  var LS = { tk: "zombi-docs:unlocked", ad: "zombi-docs:admin", ro: "zombi-docs:readonly-gate", stamp: "zombi-docs:build" };
  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v) { try { if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} }
  function passGate(unlockedBy, admin, readonly) {
    window.__ZOMBI_GATE__ = { unlockedBy: unlockedBy, admin: !!admin, readonly: !!readonly };
    set(LS.stamp, "inline");
    var g = document.getElementById("gate"), a = document.getElementById("app");
    if (g) { g.hidden = true; g.style.display = "none"; }        // скрытие и атрибутом, и стилем: .gate имеет display:grid
    if (a) { a.hidden = false; a.style.display = "flex"; }
    var ld = document.getElementById("gate-loader");
    if (ld) ld.textContent = "замок пройден (" + unlockedBy + ")" + (readonly ? " · только чтение: сеть до репозитория недоступна" : " · жду app.js…");
    /* app.js подхватит window.__ZOMBI_GATE__ и сам отрисует содержимое; здесь важнее
       не плодить переходы по таймеру (они и давали «затемнённый, но неактивный» экран). */
    return true;
  }
  function stampLine(text, warn) {
    var el = document.getElementById("gate-fallback");
    if (el) { el.textContent = text; el.style.color = warn ? "#e2703a" : ""; }
  }
  function msg(text, bad) {
    var m = document.getElementById("gate-msg");
    if (!m) return;
    m.textContent = text || ""; m.hidden = !text; m.style.color = bad ? "#e2703a" : "var(--tx3)";
  }
  function tryCode(raw, silent) {
    var code = String(raw || "").trim();
    if (window.String && code.normalize) code = code.normalize("NFC");
    if (!code) { if (!silent) msg("Введи код доступа."); return false; }
    var h = "";
    try { h = sha256Pure(code).toLowerCase(); } catch (e) { stampLine("SHA-256 в этом браузере не работает: " + e.message, true); return false; }
    if (h === OWNER_HASH) { set(LS.tk, h); set(LS.ad, "1"); passGate("код владельца", true, false); return true; }
    var saved = get(LS.tk);
    if (saved && saved === h) { passGate("этот браузер", get(LS.ad) === "1", get(LS.ro) === "1"); return true; }
    if (silent) return false;
    msg("Код не подходит. Хеш введённого: " + h.slice(0, 12) + "… — сверяю гостевые списки…");
    tryCheckGuest(h);
    return false;
  }
  function tryCheckGuest(h) {
    var ctl = null;
    try { ctl = new AbortController(); setTimeout(function () { try { ctl.abort(); } catch (e) {} }, 3500); } catch (e) {}
    fetch("config.json?nc=" + Date.now().toString(36), { cache: "no-store", signal: ctl && ctl.signal })
      .then(function (r) { if (!r.ok) throw new Error("http"); return r.json(); })
      .then(function (cfg) {
        var g = (cfg && cfg.gate) || {};
        if (String(g.ownerCode || "").toLowerCase() === h) { set(LS.tk, h); set(LS.ad, "1"); passGate("код владельца (config)", true, false); return; }
        var list = (g.allowed || []).map(function (x) { return String(x).toLowerCase(); });
        if (list.indexOf(h) >= 0) { set(LS.tk, h); set(LS.ad, "0"); passGate("гостевой код", false, false); return; }
        msg("Код не подходит: хеш " + h.slice(0, 12) + "… есть ни в ownerCode, ни в allowed (" + list.length + " шт.) config.json. Владелец добавляет гостей: ⚙ → Доступ.");
      })
      .catch(function () {
        set(LS.ro, "1");
        msg("Код не подошёл под встроенный код владельца, а config.json сейчас не читается — для гостевого кода нужен доступ к репозиторию. Кнопка «⟳ Перепроверить конфиг» повторит попытку.");
      });
  }
  function wire() {
    var f = document.getElementById("gate-form");
    if (f && !f.__ig) {
      f.__ig = 1;
      function val() { var el = document.getElementById("gate-code"); return el ? el.value : ""; }
      f.addEventListener("submit", function (e) { e.preventDefault(); tryCode(val(), false); }, false);
      // живая проверка: как только код совпал — вход без нажатия кнопки
      setInterval(function () { var v = val(); if (v && v.length > 3) tryCode(v, true); }, 700);
      var eye = document.getElementById("gate-eye");
      if (eye) eye.onclick = function () { var el = document.getElementById("gate-code"); el.type = el.type === "password" ? "text" : "password"; };
    }
    var rt = document.getElementById("gate-retry");
    if (rt && !rt.__ig) { rt.__ig = 1; rt.onclick = function () { location.reload(); }; }
    var rb = document.getElementById("gate-hardreload");
    if (rb && !rb.__ig) { rb.__ig = 1; rb.onclick = function () { set(LS.tk, null); set(LS.ro, null); location.href = location.pathname + "?nc=" + Date.now().toString(36); }; }
  }
  function boot() {
    var q = (location.search || ""), hash = (location.hash || "");
    if (q.indexOf("reset=1") >= 0) {
      set(LS.tk, null); set(LS.ro, null); set(LS.stamp, null); try { localStorage.clear(); } catch (e) {}
      try { history.replaceState(null, "", location.pathname); } catch (e) {}   // убираем ?reset=1 из адреса, не перезагружаясь
      q = "";
    }
    var saved = get(LS.tk);
    if (saved && saved === OWNER_HASH) { passGate("этот браузер", true, get(LS.ro) === "1"); wire(); return; }
    if (q.indexOf("open=1") >= 0) { set(LS.ro, "1"); passGate("?open=1", false, true); wire(); return; }
    var m = hash.match(/[#&]code=([^&]+)/);
    var g = document.getElementById("gate");
    if (g) { g.hidden = false; g.style.display = ""; }
    stampLine("сайт открылся · код проверяется здесь, без app.js и без сети");
    if (m) { var code = decodeURIComponent(m[1]); var el = document.getElementById("gate-code"); if (el) el.value = code; tryCode(code, false); wire(); return; }
    wire();
    var input = document.getElementById("gate-code");
    if (input) { input.type = "text"; input.setAttribute("placeholder", "код доступа"); input.focus(); }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, false);
  else boot();
})();
${END}
</script>`;

const p = path.join(SRC, "index.html");
let html = fs.readFileSync(p, "utf8");
const a = html.indexOf("<!-- INLINE-GATE:START -->"), b = html.indexOf("<!-- INLINE-GATE:END -->");
if (a >= 0 && b > a) {
  html = html.slice(0, a) + "<!-- INLINE-GATE:START -->\n" + block + "\n    <!-- INLINE-GATE:END -->" + html.slice(b + "<!-- INLINE-GATE:END -->".length);
} else {
  const anchor = "</script>\n</head>";
  if (html.indexOf(anchor) < 0) { console.error('нет якоря </script>\\n</head> в index.html'); process.exit(1); }
  html = html.replace(anchor, "</script>\n    <!-- INLINE-GATE:START -->\n" + block + "\n    <!-- INLINE-GATE:END -->\n</head>", 1);
}
/* штамп в <html data-build> — app.js по нему видит, что HTML свежий, а JS из кэша (или наоборот) */
html = html.replace(/<html\b[^>]*>/, (m) => m.replace(/\s*data-build="[^"]*"/, "")
  .replace(/>$/, ` data-build="${escAttr(SITE_BUILD)}">`));
fs.writeFileSync(p, html);
console.log("inline-gate встроен (" + block.length + " байт, owner " + OWNER.slice(0, 10) + "…)");
