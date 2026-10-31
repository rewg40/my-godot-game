//Сторожевой скрипт, встраивается в <head> index.html генератором build-inline-gate.js.
//Живёт ВНЕ app.js: если тот устарел (кэш), не загрузился или упал — человек всё равно
//видит причину и кнопку лечения, вместо «нажимаю, ничего не происходит».
//Здесь только ES5: никакого async/await, стрелок и шаблонных литералов.
(function () {
  window.__ZOMBI_CLICKS__ = 0;
  // «жив» ли настоящий app.js: он сам сообщает о себе флагом при старте
  window.__ZOMBI_APP__ = 0;
  window.__ZOMBI_ERRS__ = [];

  function showErr(msg) {
    var box = document.getElementById("zombi-err");
    if (!box) {
      box = document.createElement("div");
      box.id = "zombi-err";
      box.style.cssText = "position:fixed;left:12px;bottom:12px;z-index:9999;max-width:min(600px,92vw);" +
        "background:#2a1416;border:1px solid #7c3a3a;color:#ffd9d9;padding:10px 12px;border-radius:10px;" +
        "font:12.5px/1.5 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;box-shadow:0 10px 30px rgba(0,0,0,.5)";
      (document.body || document.documentElement).appendChild(box);
    }
    if (box.getAttribute("data-seen") === msg) return;
    box.setAttribute("data-seen", msg);
    box.textContent = "";
    var b = document.createElement("b");
    b.textContent = "Сторож сайта: вот что не так";
    box.appendChild(b);
    box.appendChild(document.createTextNode(String.fromCharCode(10) + msg));
    var row = document.createElement("div");
    row.style.cssText = "display:flex;gap:8px;margin-top:8px;flex-wrap:wrap";
    function btn(label, fn) {
      var el = document.createElement("button");
      el.textContent = label;
      el.style.cssText = "font:12px sans-serif;cursor:pointer;padding:4px 9px;border-radius:7px;border:1px solid #7c3a3a;background:#1b0f11;color:#ffd9d9";
      el.onclick = fn;
      row.appendChild(el);
    }
    btn("Перезагрузить начисто", function () {
      try { localStorage.removeItem("zombi-docs:build"); localStorage.removeItem("zombi-docs:loader"); } catch (e) {}
      var u = location.href.split("?")[0].split("#")[0];
      location.href = u + "?fresh=1" + (location.hash || "");
    });
    btn("Офлайн-копия", function () { downloadOffline(this); });
    btn("Скопировать", function () {
      var ta = document.createElement("textarea");
      ta.value = diagText();
      ta.style.cssText = "position:fixed;left:-9999px";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); } catch (e) {}
      ta.remove();
    });
    btn("Скрыть", function () { box.parentNode && box.parentNode.removeChild(box); });
    box.appendChild(row);
  }

  function srcList() {
    var arr = (window.__ZOMBI_SOURCES__ || [""]).slice();
    for (var i = 0; i < arr.length; i++) if (arr[i] === "") arr[i] = location.href.split("/").slice(0, 3).join("/") + "/";
    return arr;
  }
  function getTxt(u) {
    return fetch(u, { cache: "no-store", mode: "cors" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.text();
    });
  }
  // Список = content/*.json в репозитории; чего нет — то просто пропустится.
  var FILES = ["scenario.json", "mech_character.json", "mech_craft.json", "mech_research.json", "mech_weather.json", "mech_npc.json",
    "mech_quests.json", "mech_locations.json", "mech_destruction.json", "mech_physics.json", "mech_zombies.json",
    "mech_combat.json", "mech_inventory.json", "mech_assets.json", "mech_production.json", "mech_multiplayer.json", "images.json",
    "models.json", "config.json"];
  function downloadOffline(btn) {
    var srcs = srcList(), out = [], done = 0, label0 = btn && btn.textContent;
    if (btn) { btn.disabled = true; btn.textContent = "Скачиваю из зеркала..."; }
    function finish() {
      if (btn) { btn.disabled = false; btn.textContent = label0 || "Офлайн-копия"; }
      if (!out.length) { showErr("Ни одно зеркало не отдало файлы. Открой сайт через VPN или попроси агента выложить копию архивом."); return; }
      var head = "ZOMBI - офлайн-копия библии - собрано " + new Date().toISOString() + String.fromCharCode(10) +
        "источник: " + srcs.join(", ") + String.fromCharCode(10) + String.fromCharCode(10);
      var blob = new Blob([head + out.join(String.fromCharCode(10) + String.fromCharCode(10))], { type: "text/plain;charset=utf-8" });
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "zombi-bible.txt";
      document.body.appendChild(a); a.click(); a.remove();
      showErr("Офлайн-копия собрана: " + out.length + " из " + FILES.length + " файлов. Файл zombi-bible.txt сохранён в загрузки.");
    }
    function step() {
      if (done >= FILES.length) { finish(); return; }
      var f = FILES[done++], k = 0;
      (function tryOne() {
        if (k >= srcs.length) { step(); return; }
        getTxt(srcs[k] + "content/" + f).then(function (t) {
          out.push("=== " + f + " ===" + String.fromCharCode(10) + t);
          step();
        })["catch"](function () { k++; tryOne(); });
      })();
    }
    step();
  }
  window.__ZOMBI_DOWNLOAD__ = downloadOffline;

  window.__ZOMBI_SHOWERR__ = showErr;

  function diagText() {
    var doc = document.getElementById("doc");
    var st = [];
    st.push("href: " + location.href);
    st.push("userAgent: " + navigator.userAgent);
    st.push("app.js штамп: " + (window.__ZOMBI_STAMP__ || "не прочитан (app.js не загрузился)"));
    st.push("HTML штамп: " + (document.documentElement.getAttribute("data-build") || "нет"));
    st.push("кликов по вкладкам: " + window.__ZOMBI_CLICKS__ + (window.__ZOMBI_LASTTAB__ ? " (последний: " + window.__ZOMBI_LASTTAB__ + ")" : ""));
    st.push("ошибок: " + (window.__ZOMBI_ERRS__.join(" | ") || "нет"));
st.push("зеркала: " + srcList().join(" ; "));
    try { var ds = JSON.parse(localStorage.getItem("zombi-docs:dead-sources") || "null"); if (ds) st.push("не ответили: " + ds.join(" ; ")); } catch (e) {}
        st.push("файлов не доехало: " + (window.__ZOMBI_RES_FAIL__ || 0));
    st.push("состояние #doc: " + ((doc && doc.textContent) || "пусто").replace(/\s+/g, " ").slice(0, 220));
    return st.join("\n");
  }
  window.__ZOMBI_DIAG__ = diagText;

  function selftest() {
    var htmlStamp = (document.documentElement.getAttribute("data-build") || "нет в HTML");
    var out = document.getElementById("selftest-out");
    var t = document.getElementById("lnk-selftest");
    if (t) t.textContent = "Проверить клики ещё раз";
    var msg = [
      "Клик по этой ссылке браузер поймал (всего кликов по сайту: " + window.__ZOMBI_CLICKS__ + ").",
      "JS в index.html выполняется. app.js: " + (window.__ZOMBI_APP__ ? "жив, версия " + window.__ZOMBI_APP__ : "НЕ загрузился или заблокирован (в HTML версия " + htmlStamp + ")"),
      "HTML: " + htmlStamp,
    ];
    if (out) out.textContent = msg.join(String.fromCharCode(10));
    if (!window.__ZOMBI_APP__) {
      showErr("Клики браузер ловит, но app.js не работает: браузер, прокси или блокировщик не даёт скачать app.js." +
        String.fromCharCode(10) + "Открой страницу с ?fresh=1, отключи «турбо»/блокировщик для this сайта." +
        String.fromCharCode(10) + "HTML: " + htmlStamp);
    }
    return true;
  }
  window.__ZOMBI_SELFTEST__ = selftest;

  document.addEventListener("click", function (e) {
    var st = e.target && e.target.closest ? e.target.closest("[data-selftest]") : null;
    if (st) { e.preventDefault(); selftest(); return; }
    var t = e.target && e.target.closest ? e.target.closest("#main-tabs [data-tab], #subtabs .subtab") : null;
    if (!t) return;
    window.__ZOMBI_CLICKS__++;
    window.__ZOMBI_LASTTAB__ = (t.getAttribute("data-tab") || t.textContent || "").replace(/\s+/g, " ").trim().slice(0, 24);
    var ld = document.getElementById("gate-loader");
    if (ld) ld.textContent = "клик #" + window.__ZOMBI_CLICKS__ + " · " + window.__ZOMBI_LASTTAB__;
  }, true);

  // Разделяем два класса: «скрипт не приехал» (ресурс) и «скрипт упал» (исполнение).
  // Картинка/шрифт/стиль не доехали — это не повод показывать красную карточку.
  window.addEventListener("error", function (e) {
    var tgt = e && e.target;
    var isRes = !!(tgt && tgt.tagName && /^(LINK|IMG|SCRIPT|LINK|SOURCE|VIDEO|AUDIO|IMG)$/.test(tgt.tagName) && !e.message);
    if (isRes) {
      window.__ZOMBI_RES_FAIL__ = (window.__ZOMBI_RES_FAIL__ || 0) + 1;
      var tag = tgt.tagName, nm = (tgt.src || tgt.href || "").split("/").pop().split("?")[0];
      var ld = document.getElementById("gate-loader");
      if (ld) ld.textContent = "не доехали файлы: " + window.__ZOMBI_RES_FAIL__ + " (последний: " + tag + " " + nm + ")";
      if (tag === "SCRIPT" && !window.__ZOMBI_APP__) {
        setTimeout(function () {
          if (window.__ZOMBI_APP__) return;                 // зеркало подключилось чуть позже
          if (document.querySelector("script[src][data-zombi-ok]")) return;
          showErr("Скрипт app.js не пришёл ни с одного адреса (блокировка github.io и зеркал или заглушка провайдера)." + String.fromCharCode(10) +
                  "перепробовано: " + ((window.__ZOMBI_SOURCES__ || []).join(String.fromCharCode(10)) || "нет списка") + String.fromCharCode(10) +
                  "Лечение: «Офлайн-копия» ниже или ?mirror=<рабочий адрес>/");
        }, 1500);
      }
      return;
    }
    var src = e && e.filename ? String(e.filename).split("/").pop().split("?")[0] : "?";
    var line = (e && e.message ? e.message : "скрипт упал без сообщения") + "  (" + src + ":" + (e && e.lineno) + ":" + (e && e.colno) + ")";
    window.__ZOMBI_ERRS__.push(line);
    showErr(line + String.fromCharCode(10) + "app.js: " + (window.__ZOMBI_APP__ || "штамп не прочитан"));
  }, true);

  window.addEventListener("unhandledrejection", function (e) {
    var r = e && e.reason;
    var line = "Promise: " + ((r && (r.message || r.stack)) || r || "без причины");
    window.__ZOMBI_ERRS__.push(line);
    showErr(line);
  });

  // если документ так и не загрузился — объясняем вместо вечной «Загрузки…»;
  // пока приложение живёт (app.js с зеркала может подключиться позже) — перепроверяем, а не кричим
  (function watchDoc(n) {
    setTimeout(function () {
      var doc = document.getElementById("doc");
      var t = doc ? String(doc.textContent || "") : "";
      var failed = /Не удалось загрузить|не загружен/i.test(t);
      var stuck = /Загрузка/.test(t) && !failed;
      if (!stuck && !failed) return;                   // документ отрисован — всё хорошо
      if (failed) {
        showErr(["Документ не загружен (один клик по вкладке уже что-то сделал, но файлы не приходят).",
                 t.replace(/\s+/g, " ").slice(0, 200),
                 "app.js: " + (window.__ZOMBI_APP__ || "не загрузился"),
                 "лечение: «Перезагрузить начисто», «Офлайн-копия» или ?mirror=<адрес>/"].join(String.fromCharCode(10)));
        return;
      }
      var loaded = !!document.querySelector("script[src][data-zombi-ok]");
      if (!window.__ZOMBI_APP__ && !loaded && n < 6) { watchDoc(n + 1); return; }   // app.js ещё может приехать с зеркала
      showErr(["Документ не загружен: content/*.json недоступен (кэш браузера, блокировка github.io или Pages ещё не пересобрался).", t.replace(/\s+/g, " ").slice(0, 180), "app.js: " + (window.__ZOMBI_APP__ || "не загрузился ни с одного адреса")].join(String.fromCharCode(10)));
    }, 7000);
  })(0);
})();
