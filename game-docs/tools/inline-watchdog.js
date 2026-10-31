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

  function diagText() {
    var doc = document.getElementById("doc");
    var st = [];
    st.push("href: " + location.href);
    st.push("userAgent: " + navigator.userAgent);
    st.push("app.js штамп: " + (window.__ZOMBI_STAMP__ || "не прочитан (app.js не загрузился)"));
    st.push("HTML штамп: " + (document.documentElement.getAttribute("data-build") || "нет"));
    st.push("кликов по вкладкам: " + window.__ZOMBI_CLICKS__ + (window.__ZOMBI_LASTTAB__ ? " (последний: " + window.__ZOMBI_LASTTAB__ + ")" : ""));
    st.push("ошибок: " + (window.__ZOMBI_ERRS__.join(" | ") || "нет"));
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

  window.addEventListener("error", function (e) {
    var src = e && e.filename ? String(e.filename).split("/").pop().split("?")[0] : "?";
    var line = (e && e.message ? e.message : "скрипт упал") + "  (" + src + ":" + (e && e.lineno) + ":" + (e && e.colno) + ")";
    window.__ZOMBI_ERRS__.push(line);
    showErr(line + "\napp.js: " + (window.__ZOMBI_STAMP__ || "штамп не прочитан"));
  }, true);

  window.addEventListener("unhandledrejection", function (e) {
    var r = e && e.reason;
    var line = "Promise: " + ((r && (r.message || r.stack)) || r || "без причины");
    window.__ZOMBI_ERRS__.push(line);
    showErr(line);
  });

  // если документ так и не загрузился — объясняем вместо вечной «Загрузки…»
  setTimeout(function () {
    var doc = document.getElementById("doc");
    var t = doc ? String(doc.textContent || "") : "";
    if (!/Загрузка|Не удалось загрузить|ошибк/i.test(t)) return;
    showErr(["Документ не загружен: content/*.json недоступен (кэш браузера, блокировка github.io или Pages ещё не пересобрался).", t.replace(/\s+/g, " ").slice(0, 180), "app.js: " + (window.__ZOMBI_STAMP__ || "штамп не прочитан")].join(String.fromCharCode(10)));
  }, 7000);
})();
