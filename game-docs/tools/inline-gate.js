// Содержимое встроенного замка. Генератор build-inline-gate.js подставляет ${OWNER_HASH} и вставляет
// этот файл внутрь index.html между маркерами INLINE-GATE. Здесь только ES5, без внешних зависимостей.
// ВАЖНО: не начинать файл с /* … */ — открывающий блок-комментарий ломает инлайн-<script>.
// === INLINE-GATE (автосборка: node game-docs/tools/build-inline-gate.js) — не править вручную ===
(function () {
  var OWNER_HASH = "${OWNER_HASH}";
    function sha256Pure(text) {
    const isP = (n) => { for (let i = 2; i * i <= n; i++) if (!(n % i)) return false; return n > 1; };
    const K = (() => { const o = []; for (let i = 2, c = 0; c < 64; i++) if (isP(i)) { o.push(((Math.pow(i, 1 / 3) % 1) * 4294967296) | 0); c++; } return o; })();
    const H0 = (() => { const o = []; for (let i = 2, c = 0; c < 8; i++) if (isP(i)) { o.push(((Math.pow(i, 1 / 2) % 1) * 4294967296) | 0); c++; } return o; })();
    const H = H0.slice();
    const rotr = (x, n) => (x >>> n) | (x << (32 - n));
    const bytes = [];
    for (let i = 0; i < text.length; i++) {
      let c = text.charCodeAt(i);
      if (c < 0x80) bytes.push(c);
      else if (c < 0x800) bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      else if (c >= 0xd800 && c < 0xdc00 && i + 1 < text.length) {
        const cp = 0x10000 + (((c & 0x3ff) << 10) | (text.charCodeAt(i + 1) & 0x3ff));
        bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        i++;
      } else bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
    const bitLen = bytes.length * 8;
    bytes.push(0x80);
    const target = (Math.floor((bytes.length - 1) / 64) + 1) * 64 - 8;
    while (bytes.length < target) bytes.push(0);
    const hi = Math.floor(bitLen / 4294967296), lo = bitLen >>> 0;
    bytes.push((hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255,
               (lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255);
    const w = new Int32Array(64);
    for (let off = 0; off < bytes.length; off += 64) {
      for (let i = 0; i < 16; i++) {
        const j = off + i * 4;
        w[i] = ((bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3]) | 0;
      }
      for (let i = 16; i < 64; i++) {
        const x = w[i - 15], y = w[i - 2];
        const s0 = (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) | 0;
        const s1 = (rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10)) | 0;
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      let a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (let i = 0; i < 64; i++) {
        const S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) | 0;
        const ch = ((e & f) ^ (~e & g)) | 0;
        const t1 = (h + S1 + ch + K[i] + w[i]) | 0;
        const S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) | 0;
        const mj = ((a & b) ^ (a & c) ^ (b & c)) | 0;
        const t2 = (S0 + mj) | 0;
        h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
      H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
    }
    return H.map((x) => (x >>> 0).toString(16).padStart(8, "0")).join("");
  }
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
    if (ld) ld.textContent = "замок пройден (" + unlockedBy + ")" + (readonly ? (unlockedBy === "гостевая ссылка" ? " · только чтение, без GitHub-токена" : " · только чтение: конфигурация недоступна") : " · жду app.js…");
    // app.js подхватит window.__ZOMBI_GATE__ и сам отрисует содержимое;
    // здесь важнее не плодить переходы по таймеру (они и давали «затемнённый, но неактивный» экран).
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
    var view = /[?&]open=1(?:&|$)/.test(q) || /[#&]open=1(?:&|$)/.test(hash);
    if (view) { set(LS.ro, "1"); passGate("гостевая ссылка", false, true); wire(); return; }
    var saved = get(LS.tk);
    if (saved && saved === OWNER_HASH) { passGate("этот браузер", true, false); wire(); return; }
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
// === /INLINE-GATE ===
