/* ============================================================================
   ZOMBI · Библия проекта — одностраничный сайт-документация
   Хранение: GitHub Contents API (репозиторий rewg40/my-godot-game)
   Доступ: рабочая ссылка сразу открывает редактор. Публикация в GitHub: только с действующим токеном.
   Автор:   редактирует в браузере; агент правит те же JSON в репозитории.
   ========================================================================== */
(() => {
"use strict";

/* ----------------------------- константы ---------------------------------- */
const API = "https://api.github.com";
const REPO_DEFAULT = { owner: "rewg40", repo: "my-godot-game", branch: "arena/d4678daa-my-godot-game" };
const MIRRORS = [
  (o) => `https://rewg40.github.io/my-godot-game/${o}`,
  (o) => `https://github.com/rewg40/my-godot-game/raw/gh-pages/${SRC_PREFIX}/${o}`,   // когда github.io вырезан
  (o) => `https://cdn.jsdelivr.net/gh/rewg40/my-godot-game@gh-pages/${o}`,
];
function userMirror() {                  // адрес, который автор задал через ?mirror=… (см. index.html)
  try { const m = localStorage.getItem("zombi-docs:mirror"); return m ? (m.replace(/\/$/, "") + "/") : ""; } catch (e) { return ""; }
}
const MIRRORS_USER = [userMirror()].filter(Boolean).map((b) => (o) => b + o);
const ALL_MIRRORS = [...MIRRORS_USER, ...MIRRORS].concat((typeof window !== "undefined" && window.__ZOMBI_BASE__) ? [(o) => window.__ZOMBI_BASE__ + o] : []);   // зеркало + то, откуда приехал сам app.js
const SRC_PREFIX = "game-docs/src";
// загрузчик в index.html уже нашёл рабочий адрес (github.io может быть вырезан) —
// читаем контент оттуда же. Присваивание ДО boot(): иначе первые запросы уходят в origin и висят.
const USER_BASE = (typeof window !== "undefined" && window.__ZOMBI_BASE__) || "";
const MAX_IMG = 1_400_000;      // байт после сжатия
const MAX_MODEL = 24_000_000;  // байт (GitHub limit ~25 МБ на файл)
const LS = { draft: "zombi-docs:draft:", origin: "zombi-docs:origin", token: "zombi-docs:token", refresh: "zombi-docs:refresh" };

const TABS = [
  { id: "scenario",  label: "Сценарий",           file: "scenario.json" },
  { id: "mechanics", label: "Механика",            file: null },
  { id: "preview",   label: "Картинки / превью",   file: "preview.json" },
];
const MECH = [
  { id: "character",   label: "Персонаж",            file: "mech_character.json" },
  { id: "craft",       label: "Крафт",               file: "mech_craft.json" },
  { id: "research",    label: "Исследование",         file: "mech_research.json" },
  { id: "weather",     label: "Погода",              file: "mech_weather.json" },
  { id: "npc",         label: "NPC и фракции",       file: "mech_npc.json" },
  { id: "quests",      label: "Квесты",              file: "mech_quests.json" },
  { id: "locations",   label: "Локации",             file: "mech_locations.json" },
  { id: "destruction", label: "Разрушаемые объекты", file: "mech_destruction.json" },
  { id: "physics",     label: "Физика",              file: "mech_physics.json" },
  { id: "zombies",     label: "ИИ монстров",         file: "mech_zombies.json" },
  { id: "combat",      label: "Бой и оружие",        file: "mech_combat.json" },
  { id: "inventory",   label: "Инвентарь и лут",     file: "mech_inventory.json" },
  { id: "assets",      label: "3D-модели и ассеты",  file: "mech_assets.json" },
  { id: "production",  label: "Аудио, UI, проект",   file: "mech_production.json" },
  { id: "multiplayer", label: "Сетевая игра",         file: "mech_multiplayer.json" },
];
const STATUS = { draft: "черновик", wip: "в работе", done: "готово", idea: "идея" };

/* ----------------------------- утилиты ------------------------------------ */
const $ = (s, r = document) => r.querySelector(s);
const copyText = async (t) => {
  let ok = false;
  try {
    const ta = document.createElement("textarea");
    ta.value = t; ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    ok = document.execCommand("copy"); ta.remove();
  } catch (e) { ok = false; }
  if (!ok && navigator.clipboard) { try { await navigator.clipboard.writeText(t); ok = true; } catch (e) { ok = false; } }
  toast(ok ? "Скопировано" : "Не скопировалось — выдели вручную", ok ? "ok" : "warn", 2200);
  return ok;
};
function fileUrl(file) {   // ссылка на файл в веб-интерфейсе GitHub (необязательно авторизованной)
  if (!file) return "#";
  return `https://github.com/${S.origin.owner}/${S.origin.repo}/blob/${S.origin.branch}/${SRC_PREFIX}/content/${file}`;
}
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const el = (tag, cls, html) => { const n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; };
const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const nowIso = () => new Date().toISOString().slice(0, 19) + "Z";
const copy = async (text) => {
  try { if (navigator.clipboard && window.isSecureContext !== false) { await navigator.clipboard.writeText(text); return true; } } catch (e) { /* ниже */ }
  try {
    const ta = el("textarea"); ta.value = text; ta.style.cssText = "position:fixed;left:-9999px"; document.body.appendChild(ta); ta.select();
    const ok = document.execCommand("copy"); ta.remove(); return ok;
  } catch (e) { return false; }
};
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

function toast(msg, kind = "", ms = 3800) {
  const t = el("div", "toast " + kind, msg);
  $("#toast-root").appendChild(t);
  setTimeout(() => { t.style.opacity = "0"; t.style.transition = "opacity .3s"; setTimeout(() => t.remove(), 320); }, ms);
  return t;
}
const SITE_BUILD = "2026-10-31.14 · полный доступ по ссылке";
function b64FromBytes(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
function bytesFromB64(b64) {
  const bin = atob(b64.replace(/\s/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const utf8 = {
  enc: (s) => new TextEncoder().encode(s),
  dec: (bytes) => new TextDecoder().decode(bytes),
};

/* ----------------------------- состояние ----------------------------------- */
const S = {
  config: { contentPath: SRC_PREFIX + "/content", imagesPath: SRC_PREFIX + "/content/images", modelsPath: SRC_PREFIX + "/content/models", inboxPath: SRC_PREFIX + "/content/agent-inbox", origin: { ...REPO_DEFAULT } },
  origin: { ...REPO_DEFAULT },
  token: "", cfgLoaded: false, cfgOk: false, cfgFailed: false, inside: false, mirror: null, base: (typeof window !== "undefined" && window.__ZOMBI_BASE__) || "", readonlyGate: false, docReady: false, lastErr: "",
  mainTab: "scenario", mechIndex: MECH.map((m) => m.id), sub: "character",
  content: null, contentFile: null, contentSha: null, contentName: "",
  images: null, models: null, dirty: new Set(), draftErrors: new Set(), publishing: false, revision: 0,
};
const draftKey = (file) => LS.draft + file;
const hasDraft = (file) => { try { return !!localStorage.getItem(draftKey(file)); } catch (e) { return false; } };
function cleanDoc(d) { const copy = { ...d }; delete copy._banner; return copy; }

/* ----------------------------- GitHub API ---------------------------------- */
function normalizeEditorLink() {
  const u = new URL(location.href);
  let changed = false;
  for (const key of ["open", "code", "token"]) {
    if (u.searchParams.has(key)) { u.searchParams.delete(key); changed = true; }
  }
  if (/(^#|&)code=/.test(u.hash)) {
    const parts = u.hash.replace(/^#/, "").split("&").filter((x) => x && !x.startsWith("code="));
    u.hash = parts.length ? "#" + parts.join("&") : "";
    changed = true;
  }
  if (!u.searchParams.has("edit")) { u.searchParams.set("edit", "1"); changed = true; }
  if (changed) history.replaceState(null, "", u.href);
}
function writeBlockReason() {
  if (S.readonlyGate) return "Конфигурация ещё не проверена: локальное редактирование доступно, публикация временно отключена. Нажми «Повторить проверку» в полосе над документом.";
  if (!S.token) return "Локальное редактирование доступно. Чтобы опубликовать изменения для всех, подключи GitHub с правом записи.";
  return "";
}
function canWrite() { return !writeBlockReason(); }
function assertWriteAccess() {
  const reason = writeBlockReason();
  if (reason) { const err = new Error(reason); err.code = "READ_ONLY"; throw err; }
}
function canEdit() { return true; }
function assertEditable() { return true; }
function sectionHash() {
  if (S.mainTab === "mechanics") return "#mechanics/" + (MECH.some((m) => m.id === S.sub) ? S.sub : MECH[0].id);
  return "#" + (TABS.some((t) => t.id === S.mainTab) ? S.mainTab : "scenario");
}
function makeSectionLink(mode) {
  // Never copy credentials, access codes, mirror settings or arbitrary query parameters.
  const local = ["localhost", "127.0.0.1", ""].includes(location.hostname);
  const base = location.protocol === "file:" || local ? "https://rewg40.github.io/my-godot-game/" : new URL(location.pathname, location.origin).href;
  const u = new URL(base);
  u.searchParams.set(mode, "1");
  u.hash = sectionHash();
  return u.href;
}
function makeEditLink() { return makeSectionLink("edit"); }
function ghHeaders(withBody) {
  const h = { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
  if (S.token) h.Authorization = "Bearer " + S.token;
  if (withBody) h["Content-Type"] = "application/json";
  return h;
}
function api(path) { return S.origin.owner && S.origin.repo ? `${API}/repos/${S.origin.owner}/${S.origin.repo}${path}` : null; }
async function ghFetch(path, opts = {}) {
  const url = api(path);
  if (!url) throw new Error("Не задан репозиторий");
  const res = await fetch(url, { ...opts, headers: { ...ghHeaders(!!opts.body), ...(opts.headers || {}) } });
  if (!res.ok) {
    let detail = "";
    try { detail = (await res.json()).message || ""; } catch (e) { /* ignore */ }
    const err = new Error(`GitHub ${res.status}: ${detail || res.statusText}`);
    err.status = res.status;
    if (res.status === 401) err.hint = "GitHub 401: токен не принят — он отсутствует, истёк или отозван. Для локального редактирования токен не нужен. Для публикации нужен новый токен с Contents: Read and write.";
    if (res.status === 403) err.hint = "GitHub запретил запись. У токена должны быть доступ к этому репозиторию и Contents: Read and write. Локальное редактирование доступно без токена.";
    throw err;
  }
  if (res.status === 204) return null;
  const ct = res.headers.get("content-type") || "";
  return ct.includes("json") ? res.json() : res.text();
}
async function ghGetFile(path, ref) {
  const d = await ghFetch(`/contents/${encodeURI(path)}?ref=${encodeURIComponent(ref || S.origin.branch)}`);
  return { sha: d.sha, text: d.encoding === "base64" ? utf8.dec(bytesFromB64(d.content)) : d.content };
}
async function ghGetSha(path) {
  try { const d = await ghFetch(`/contents/${encodeURI(path)}?ref=${encodeURIComponent(S.origin.branch)}`); return d.sha; }
  catch (e) { if (e.status === 404) return null; throw e; }
}
async function ghPutText(path, text, message) {
  assertWriteAccess();
  const sha = await ghGetSha(path);
  const body = { message, content: b64FromBytes(utf8.enc(text)), branch: S.origin.branch };
  if (sha) body.sha = sha;
  return ghFetch(`/contents/${encodeURI(path)}`, { method: "PUT", body: JSON.stringify(body) });
}
async function ghPutBytes(path, bytes, message) {
  assertWriteAccess();
  const sha = await ghGetSha(path);
  const body = { message, content: b64FromBytes(bytes), branch: S.origin.branch };
  if (sha) body.sha = sha;
  return ghFetch(`/contents/${encodeURI(path)}`, { method: "PUT", body: JSON.stringify(body) });
}
async function ghListDir(path) {
  try {
    const d = await ghFetch(`/contents/${encodeURI(path)}?ref=${encodeURIComponent(S.origin.branch)}`);
    return Array.isArray(d) ? d : [];
  } catch (e) { if (e.status === 404) return []; throw e; }
}

/* loadText(sitePath): sitePath — путь относительно корня сайта (= game-docs/src при деплое).
   Сначала пробуем файл рядом с сайтом (Pages и локальный сервер), затем — репозиторий через API. */
async function fetchText(url, mode, ms) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms || 4000);
  try {
    const r = await fetch(url, { cache: "no-store", mode: mode || "cors", signal: ctrl.signal });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return await r.text();
  } finally { clearTimeout(t); }
}
/* Ищем файл: рядом с сайтом → Pages → jsDelivr → GitHub API (с токеном).
   Первый successful источник запоминается, чтобы не дёргать все подряд на каждый раздел. */
async function loadText(sitePath) {
  // Порядок: 1) адрес зеркала, с которого приехал интерфейс (загрузчик в index.html нашёл рабочий);
  // 2) рядом со страницей; 3) список зеркал; 4) GitHub API с токеном.
  const base = S.base || USER_BASE;
  if (base) {
    try { return await fetchText(base + encodeURI(sitePath) + "?v=" + Date.now(), "cors", 4000); } catch (e) { /* дальше */ }
  }
  if (location.protocol === "http:" || location.protocol === "https:") {
    try { return await fetchText(encodeURI(sitePath) + "?v=" + Date.now(), "same-origin", 4000); } catch (e) { /* следующее зеркало */ }
  }
  const list = ALL_MIRRORS;
  if (S.mirror != null && list[S.mirror]) {
    try { return await fetchText(list[S.mirror](sitePath), "cors", 3500); } catch (e) { /* следующее */ }
  }
  for (let i = 0; i < list.length; i++) {
    if (i === S.mirror) continue;
    try { const t = await fetchText(list[i](sitePath), "cors", 3500); S.mirror = i; return t; } catch (e) { /* следующее */ }
  }
  if (S.origin.owner) return (await ghGetFile(`${SRC_PREFIX}/${sitePath}`)).text;
  throw new Error("файл недоступен ни локально, ни через репозиторий");
}


/* ----------------------------- блок: рендер -------------------------------- */
function inline(text) {
  let s = esc(text);
  s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>");
  s = s.replace(/(https?:\/\/[^\s<)"']+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');
  return s;
}
function hl(code) {
  const lines = esc(code).split("\n").map((line) => {
    const i = line.indexOf("#");
    let head = line, tail = "";
    if (i >= 0 && !/`/.test(line.slice(0, i))) { head = line.slice(0, i); tail = '<span class="cm">' + line.slice(i) + "</span>"; }
    head = head.replace(/(&quot;.*?&quot;|&#39;.*?&#39;)/g, (m) => `<span class="st">${m}</span>`);
    head = head.replace(/\b(func|var|const|if|elif|else|for|while|return|class|extends|signal|await|match|in|not|and|or|true|false|null|self|super|static|export|onready|break|continue|pass|enum|is|as)\b/g, '<span class="kw">$1</span>');
    head = head.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="nm">$1</span>');
    return head + tail;
  });
  return lines.join("\n");
}
function renderBlock(b, sectIdx, blkIdx) {
  const tool = (label, act, title) => `<button class="tiny" data-act="${act}" data-s="${sectIdx}" data-b="${blkIdx}" title="${esc(title || "")}">${label}</button>`;
  let inner = "";
  switch (b.type) {
    case "h": inner = `<h2>${inline(b.text)}</h2>`; break;
    case "p": inner = (b.text || []).map((t) => `<p>${inline(t)}</p>`).join(""); break;
    case "note": inner = `<div class="note">${inline(b.text)}</div>`; break;
    case "list": {
      const items = (b.items || []).map((it) => `<li class="blk">${inline(it)}</li>`).join("");
      inner = b.ordered ? `<ol class="blocks">${items}</ol>` : `<ul class="blocks">${items}</ul>`;
      break;
    }
    case "todo": {
      if (isQuestionBlock(sectIdx)) { inner = renderQuestions(b, sectIdx); break; }
      const items = (b.items || []).map((it, i) =>
        `<li><input type="checkbox" data-act="toggle-todo" data-s="${sectIdx}" data-b="${blkIdx}" data-i="${i}" ${it.done ? "checked" : ""} ${""}><span>${inline(it.text)}</span></li>`).join("");
      inner = `<ul class="checks">${items}</ul>`;
      break;
    }
    case "kv": {
      const head = `<thead><tr>${(b.head || []).map((h) => `<th>${inline(h)}</th>`).join("")}</tr></thead>`;
      const body = `<tbody>${(b.rows || []).map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("")}</tbody>`;
      inner = `<div class="tbl-wrap"><table>${head}${body}</table></div>`;
      break;
    }
    case "code": inner = `<pre class="code"><code>${hl(b.code || "")}</code></pre>`; break;
    case "image": {
      const src = resolveAsset(b.src);
      inner = `<figure class="img">${src ? `<img src="${esc(src)}" alt="${esc(b.caption || "")}" loading="lazy">` : ""}<figcaption>${inline(b.caption || "")}</figcaption></figure>`;
      break;
    }
    default: inner = `<p>${inline(b.text ? (Array.isArray(b.text) ? b.text.join(" ") : b.text) : "")}</p>`;
  }
  const tools = b.type === "h"
    ? tool("✎ Изменить", "edit") + tool("＋ После", "add-after") + tool("✕ Удалить", "del")
    : tool("✎ Изменить", "edit") + tool("↑", "up", "Выше") + tool("↓", "down", "Ниже") + tool("＋ После", "add-after") + tool("✕ Удалить", "del");
  return `<section class="sect" data-s="${sectIdx}">${inner}${`<div class="sect-tools">${tools}</div>`}</section>`;
}

function renderDoc(d) {
  const host = $("#doc");
  host.innerHTML = "";
  const head = el("div", "doc-head");
  head.innerHTML = `
    <h1>${esc(d.title || d.id)}</h1>
    <p class="sub">${esc(d.subtitle || "")}</p>
    <div class="doc-meta">
      <span class="chip"><i class="dot ${d.status || "draft"}"></i> ${esc(STATUS[d.status] || d.status || "черновик")}</span>
      <span class="chip">обновлено: ${esc((d.updated || "").slice(0, 10) || "—")}</span>
      <span class="chip">разделов: ${(d.blocks || []).length}</span>
      <span class="chip">${esc(S.origin.owner + "/" + S.origin.repo)}:${esc(S.origin.branch)}</span>
      <div class="doc-actions">
        ${'<button class="primary" id="btn-compose">＋ Добавить изменения</button><button class="ghost" id="btn-question">？ Открытый вопрос</button><button class="ghost" id="btn-edit-all">✎ Весь текст</button><button class="ghost" id="btn-add-sect">＋ Раздел</button>'}
        <button class="ghost" id="btn-json">${"JSON"}</button>
      </div>
    </div>`;
  host.appendChild(head);

  if (d._banner) { const b = el("div", "note", d._banner); host.appendChild(b); }
  {
    $("#btn-compose", host).onclick = () => openTabComposer();
    $("#btn-question", host).onclick = () => openQuestionEditor();
    $("#btn-edit-all", host).onclick = () => rawEdit();
    $("#btn-add-sect", host).onclick = () => addSection(null);
  }
  $("#btn-json", host).onclick = () => jsonView();
  (d.blocks || []).forEach((b, i) => host.insertAdjacentHTML("beforeend", renderBlock(b, i, i)));
  if (!d.blocks || !d.blocks.length) host.insertAdjacentHTML("beforeend", `<div class="end-card">Раздел пуст. Нажми «＋ Раздел» и напиши первое — или попроси агента: «заполни раздел по запросу».</div>`);

  if (d.glossary && d.glossary.length) {
    const g = el("div", "gloss");
    g.innerHTML = `<h3>Глоссарий</h3><dl>${d.glossary.map(([t, v]) => `<dt>${inline(t)}</dt><dd>${inline(v)}</dd>`).join("")}</dl>`;
    host.appendChild(g);
  }
  const end = el("div", "end-card");
  const repoPath = `${SRC_PREFIX}/content/${S.contentFile || ""}`;
  const brief = `работай по README.md в корне rewg40/my-godot-game и добавь в ${repoPath}: `;
  end.innerHTML = `Файл этого раздела: <code>${esc(repoPath)}</code> · репозиторий = единственное хранилище, правки уходят туда же (⤒ или Ctrl+S), агент читает те же файлы.
    <div class="end-actions">
      <button class="tiny ghost" data-act="path">Скопировать путь</button>
      <button class="tiny ghost" data-act="brief">Скопировать задачу для агента</button>
      <a class="tiny ghost" href="${esc(fileUrl(S.contentFile))}" target="_blank" rel="noopener">Открыть на GitHub</a>
    </div>`;
  end.onclick = (e) => {
    const b = e.target.closest("button[data-act]");
    if (!b) return;
    if (b.dataset.act === "path") copyText(repoPath);
    else copyText(brief);
  };
  host.appendChild(end);
}

/* ----------------------------- блок: текст ⇄ данные ------------------------ */
function blockToText(b) {
  switch (b.type) {
    case "h": return "## " + (b.text || "");
    case "p": return (b.text || []).join("\n\n");
    case "note": return "> " + (b.text || "");
    case "list": return (b.items || []).map((t, i) => (b.ordered ? `${i + 1}. ` : "- ") + t).join("\n");
    case "todo": return (b.items || []).map((t) => {
      const answer = String(t.answer || "").trim();
      const lines = answer ? answer.split("\n").map((line, i) => "  " + (i === 0 ? "Ответ: " : "") + line).join("\n") : "";
      return `- [${t.done ? "x" : " "}] ${t.text}` + (lines ? "\n" + lines : "");
    }).join("\n");
    case "kv": return [(b.head || []).join(" | "), (b.head || []).map(() => "---").join(" | "), ...(b.rows || []).map((r) => r.join(" | "))].join("\n");
    case "code": return "```" + (b.lang || "") + "\n" + (b.code || "") + "\n```";
    case "image": return "![" + (b.caption || "") + "](" + (b.src || "") + ")";
    default: return JSON.stringify(b, null, 2);
  }
}
function parseBlocks(text) {
  const lines = String(text).replace(/\r/g, "").split("\n");
  const out = [];
  let i = 0;
  while (i < lines.length) {
    let line = lines[i];
    if (!line.trim()) { i++; continue; }
    if (line.startsWith("```")) {
      const lang = line.slice(3).trim(); i++;
      const buf = [];
      while (i < lines.length && !lines[i].startsWith("```")) { buf.push(lines[i]); i++; }
      i++;
      out.push({ type: "code", lang: lang || "text", code: buf.join("\n") });
      continue;
    }
    if (/^##\s?/.test(line)) { out.push({ type: "h", text: line.replace(/^##\s?/, "").trim() }); i++; continue; }
    if (/^&gt;\s?|^>\s?/.test(line)) {
      const buf = [];
      while (i < lines.length && (/^>\s?/.test(lines[i]) || /^&gt;\s?/.test(lines[i]))) { buf.push(lines[i].replace(/^>\s?/, "").replace(/^&gt;\s?/, "")); i++; }
      out.push({ type: "note", text: buf.join(" ") });
      continue;
    }
    if (/^- \[[ xX]\]/.test(line)) {
      const items = [];
      while (i < lines.length && /^- \[[ xX]\]/.test(lines[i])) {
        const m = lines[i].match(/^- \[( |x|X)\]\s*(.*)$/);
        const item = { text: m[2], done: m[1].toLowerCase() === "x" }; i++;
        const answer = [];
        while (i < lines.length && /^ {2,}\S/.test(lines[i]) && !/^ {2,}- \[/.test(lines[i])) {
          answer.push(lines[i].trim().replace(/^Ответ:\s?/i, "")); i++;
        }
        if (answer.length) item.answer = answer.join("\n");
        items.push(item);
      }
      out.push({ type: "todo", items });
      continue;
    }
    if (/^[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^[-*]\s+/.test(lines[i])) { items.push(lines[i].replace(/^[-*]\s+/, "").trim()); i++; }
      out.push({ type: "list", ordered: false, items });
      continue;
    }
    if (/^\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\d+\.\s+/.test(lines[i])) { items.push(lines[i].replace(/^\d+\.\s+/, "").trim()); i++; }
      out.push({ type: "list", ordered: true, items });
      continue;
    }
    if (line.includes("|") && lines[i + 1] && /^\s*:?-{2,}/.test(lines[i + 1])) {
      const head = splitRow(line); i += 2;
      const rows = [];
      while (i < lines.length && lines[i].includes("|")) { rows.push(splitRow(lines[i])); i++; }
      out.push({ type: "kv", head, rows });
      continue;
    }
    const img = line.match(/^!\[([^\]]*)\]\(([^)]+)\)\s*$/);
    if (img) { out.push({ type: "image", caption: img[1], src: img[2] }); i++; continue; }
    const paras = [];
    let buf = [];
    while (i < lines.length && lines[i].trim() && !/^(##|>|```|[-*]\s|\d+\.\s)/.test(lines[i]) && !/^- \[/.test(lines[i]) && !lines[i].includes("|")) {
      buf.push(lines[i].trim()); i++;
      if (lines[i] && !lines[i].trim()) { i++; break; }
    }
    if (!buf.length) { buf.push(lines[i]); i++; }
    out.push({ type: "p", text: [buf.join(" ")] });
    void paras;
  }
  return out;
  function splitRow(l) { return l.split("|").map((c) => c.trim()).filter((c, idx, a) => !(c === "" && (idx === 0 || idx === a.length - 1))); }
}

/* ----------------------------- редактирование ------------------------------ */
function editSection(idx) {
  if (!assertEditable()) return;
  const d = S.content;
  const b = d.blocks[idx];
  const isHead = b.type === "h";
  const modal = openModal(isHead ? "Раздел (заголовок)" : "Правка блока", `
    <label class="f"><span>Тип</span>
      <select id="ed-type">
        ${["p", "note", "list", "todo", "kv", "code", "image", "h"].map((t) => `<option value="${t}" ${t === b.type ? "selected" : ""}>${{ p: "абзацы", note: "заметка/врезка", list: "список", todo: "чек-лист", kv: "таблица", code: "код", image: "картинка", h: "заголовок раздела" }[t]}</option>`).join("")}
      </select></label>
    <label class="f"><span>Содержимое</span>
      <textarea id="ed-text" spellcheck="false"></textarea></label>
    <div class="hint">Для заголовка — одна строка (можно вставить несколько строк: 1-я станет заголовком, остальные — блоками).
    Пустая строка = новый абзац; <code>- </code> список; <code>1. </code> нумерованный; <code>- [ ]</code> чек-лист;
    <code>|</code> таблица (2-я строка — <code>---</code>); тройной бэкскрип — код; <code>&gt;</code> врезка; <code>![подпись](images/…)</code> картинка.</div>
    <div class="foot-row">
      <button class="primary" id="ed-ok">Сохранить во вкладке</button>
      <button class="ghost" id="ed-cancel">Отмена</button>
      <span style="flex:1"></span>
      <button class="ghost" id="ed-del">Удалить блок</button>
    </div>`);
  const ta = $("#ed-text", modal);
  ta.value = blockToText(b);
  const sel = $("#ed-type", modal);
  sel.onchange = () => {
    const t = sel.value;
    if (t === b.type) { ta.value = blockToText(b); return; }
    const probe = parseBlocks(ta.value);
    const pick = probe.find((x) => x.type === t) || probe[0];
    ta.value = pick ? blockToText({ ...pick, type: t }) : "";
    if (t === "h") ta.value = (b.type === "h" ? b.text : "") || "";
    if (t === "p") ta.value = Array.isArray(b.text) ? b.text.join("\n\n") : (b.text || "");
    if (t === "note") ta.value = b.text || "";
  };
  $("#ed-ok", modal).onclick = () => {
    const type = sel.value;
    const raw = ta.value.replace(/\r/g, "");
    let blocks = [];
    if (type === "h") {
      const nl = raw.indexOf("\n");
      const headTxt = (nl === -1 ? raw : raw.slice(0, nl)).replace(/^##\s?/, "").trim();
      blocks = [{ type: "h", text: headTxt }];
      if (nl !== -1) blocks = blocks.concat(parseBlocks(raw.slice(nl + 1)));
    } else if (type === "p") {
      blocks = [{ type: "p", text: raw.split(/\n{2,}/).map((x) => x.trim()).filter(Boolean) }];
    } else if (type === "note") {
      blocks = [{ type: "note", text: raw.trim() }];
    } else if (type === "code") {
      const probe = parseBlocks(raw);
      const src = probe.find((x) => x.type === "code");
      blocks = [{ type: "code", lang: (src && src.lang) || "gdscript", code: src ? src.code : raw.replace(/^```[a-z]*\n?/, "").replace(/\n?```$/, "") }];
    } else {
      blocks = parseBlocks(raw).map((x) => (x.type === "h" && type !== "h" ? { type: "p", text: [x.text] } : x));
      if (!blocks.length) blocks = [{ type, text: raw.trim() }];
    }
    const previous = d.blocks.slice();
    d.blocks.splice(idx, 1, ...blocks);
    if (!markDirty(S.contentFile, d)) { d.blocks = previous; return; }
    closeModal(); renderActiveDoc(); localSavedToast(true, "Блок");
  };
  $("#ed-del", modal).onclick = () => {
    if (!confirm("Удалить этот блок?")) return;
    const previous = d.blocks.slice();
    d.blocks.splice(idx, 1);
    if (!markDirty(S.contentFile, d)) { d.blocks = previous; return; }
    closeModal(); renderActiveDoc(); localSavedToast(true, "Удаление блока");
  };
  $("#ed-cancel", modal).onclick = closeModal;
}
function addSection(afterIdx) {
  if (!assertEditable()) return;
  const modal = openModal("Новый раздел", `
    <label class="f"><span>Заголовок</span><input id="ns-title" placeholder="Например: Правила стрельбы"></label>
    <label class="f"><span>Содержимое (формат как в Markdown)</span><textarea id="ns-body" placeholder="- пункт&#10;- пункт&#10;&#10;| Колонка | Значение |&#10;| --- | --- |&#10;| a | b |"></textarea></label>
    <div class="foot-row"><button class="primary" id="ns-ok">Добавить</button><button class="ghost" id="ns-cancel">Отмена</button></div>`);
  $("#ns-ok", modal).onclick = () => {
    const title = $("#ns-title", modal).value.trim();
    const blocks = parseBlocks($("#ns-body", modal).value);
    const d = S.content;
    const ins = [];
    if (title) ins.push({ type: "h", text: title });
    ins.push(...(blocks.length ? blocks : [{ type: "p", text: ["—"] }]));
    const at = afterIdx == null ? d.blocks.length : afterIdx + 1;
    d.blocks.splice(at, 0, ...ins);
    if (!markDirty(S.contentFile, d)) { d.blocks.splice(at, ins.length); return; }
    closeModal(); renderActiveDoc(); localSavedToast(true, "Раздел");
  };
  $("#ns-cancel", modal).onclick = closeModal;
}
function moveBlock(idx, dir) {
  if (!assertEditable()) return;
  const b = S.content.blocks, j = idx + dir;
  if (j < 0 || j >= b.length) return;
  [b[idx], b[j]] = [b[j], b[idx]];
  markDirty(); renderDoc(S.content);
}
function markDirty(file = S.contentFile, doc = S.content) {
  if (!file || !doc) return false;
  S.dirty.add(file); S.revision++;
  let saved = true;
  try { localStorage.setItem(draftKey(file), JSON.stringify(cleanDoc(doc))); S.draftErrors.delete(file); }
  catch (e) { saved = false; S.draftErrors.add(file); toast("Браузер не сохранил черновик: " + esc(e.message) + ". Скачай JSON или опубликуй, не закрывая страницу.", "bad", 9000); }
  setPill(saved ? "warn" : "bad", saved ? "черновик в браузере" : "черновик не сохранён");
  updateFoot(); renderSubtabs();
  return saved;
}
function jsonView() {
  const modal = openModal("JSON раздела (" + S.contentFile + ")", `
    <label class="f"><textarea id="jv" style="min-height:420px"></textarea></label>
    <div class="foot-row">${'<button class="primary" id="jv-ok">Применить</button>'}<button class="ghost" id="jv-cc">Скопировать</button><button class="ghost" id="jv-x">Закрыть</button></div>`);
  $("#jv", modal).value = JSON.stringify(S.content, null, 2);
  $("#jv", modal).readOnly = false;
  $("#jv-ok", modal).onclick = () => {
    try {
      const next = JSON.parse($("#jv", modal).value);
      if (!next || !Array.isArray(next.blocks)) throw new Error("Нужен объект со списком blocks");
      const previous = S.content; S.content = next;
      if (!markDirty(S.contentFile, next)) { S.content = previous; return; }
      renderActiveDoc(); closeModal(); localSavedToast(true, "JSON");
    }
    catch (e) { toast("Ошибка JSON: " + esc(e.message), "bad", 6000); }
  };
  $("#jv-cc", modal).onclick = () => { copy($("#jv", modal).value); toast("Скопировано", "ok"); };
  $("#jv-x", modal).onclick = closeModal;
}

/* ----------------------------- прямые правки вкладки ----------------------- */
function renderActiveDoc() {
  if (S.mainTab === "preview") loadPreview();
  else if (S.content) renderDoc(S.content);
}
function isQuestionBlock(idx, doc = S.content) {
  if (!doc || !doc.blocks[idx] || doc.blocks[idx].type !== "todo") return false;
  for (let i = idx - 1; i >= 0; i--) {
    if (doc.blocks[i].type === "h") return /вопрос|question/i.test(doc.blocks[i].text || "");
  }
  return false;
}
function questionBlockIndex(doc = S.content) {
  return doc ? doc.blocks.findIndex((b, i) => b.type === "todo" && isQuestionBlock(i, doc)) : -1;
}
function renderQuestions(b, blockIdx) {
  const items = (b.items || []).map((it, i) => `
    <article class="question-item ${it.done ? "resolved" : ""}">
      <div class="question-top"><span class="question-state">${it.done ? "✓ Решено" : "● Открыт"}</span>
        ${`<div class="question-actions">
          <button type="button" class="tiny ghost" data-qact="edit" data-s="${blockIdx}" data-i="${i}">✎ Изменить</button>
          <button type="button" class="tiny ghost" data-qact="answer" data-s="${blockIdx}" data-i="${i}">Ответить</button>
          <button type="button" class="tiny ghost" data-qact="toggle" data-s="${blockIdx}" data-i="${i}">${it.done ? "Вернуть" : "Решено"}</button>
          <button type="button" class="tiny ghost danger" data-qact="delete" data-s="${blockIdx}" data-i="${i}" aria-label="Удалить вопрос">✕</button>
        </div>`}
      </div>
      <div class="question-text">${esc(it.text || "")}</div>
      ${String(it.answer || "").trim() ? `<div class="question-answer"><b>Ответ / решение</b><div>${esc(it.answer)}</div></div>` : `<div class="question-empty">Ответа пока нет</div>`}
    </article>`).join("");
  return `<div class="question-panel" data-qblock="${blockIdx}">
    <div class="question-list">${items || '<p class="hint">Пока нет вопросов. Добавь первый ниже.</p>'}</div>
    ${`<form class="question-add" data-qform="${blockIdx}">
      <div class="question-add-title">Новый открытый вопрос <span>→ эта вкладка · Открытые вопросы</span></div>
      <label class="f"><span>Вопрос</span><textarea name="question" rows="2" required placeholder="Например: что должно происходить с зомби при потере цели?"></textarea></label>
      <label class="f"><span>Ответ / решение · необязательно</span><textarea name="answer" rows="2" placeholder="Можно заполнить сейчас или позже кнопкой «Ответить»"></textarea></label>
      <div class="foot-row"><button class="primary" type="submit">＋ Добавить вопрос</button><button class="ghost" type="button" data-qai="${blockIdx}">＋ Добавить и отправить ИИ</button><span class="hint">ИИ получит задачу на обработку, а не просто вопрос</span></div>
      <p class="field-status" role="status" aria-live="polite" hidden></p>
    </form>`}
  </div>`;
}
function localSavedToast(ok, what) {
  if (ok) toast(what + " сохранено во вкладке в этом браузере. Для всех — «Опубликовать вкладку».", "ok", 5500);
}
function openQuestionEditor(blockIndex, itemIndex, focusAnswer) {
  if (!assertEditable() || !S.docReady) return;
  const doc = S.content, file = S.contentFile;
  let bi = Number.isInteger(blockIndex) ? blockIndex : questionBlockIndex(doc);
  const newBlock = bi < 0;
  const block = newBlock ? { type: "todo", items: [] } : doc.blocks[bi];
  const isNew = !Number.isInteger(itemIndex);
  const old = isNew ? { text: "", answer: "", done: false } : block.items[itemIndex];
  if (!old) return;
  const modal = openModal((isNew ? "Новый открытый вопрос" : "Открытый вопрос") + " · " + (doc.title || ""), `
    <p class="hint">Пиши прямо здесь. Вопрос попадёт в текущую вкладку, а не в очередь агенту. Локальное сохранение не требует GitHub; публикация делает правку общей.</p>
    <label class="f"><span>Вопрос</span><textarea id="q-text" rows="3" required>${esc(old.text || "")}</textarea></label>
    <label class="f"><span>Ответ / решение · необязательно</span><textarea id="q-answer" rows="4">${esc(old.answer || "")}</textarea></label>
    <label class="check-line"><input id="q-done" type="checkbox" ${old.done ? "checked" : ""}> Вопрос решён</label>
    <p class="hint">Куда: <b>${esc(doc.title || file)}</b> → Открытые вопросы</p>
    <label class="f"><span>Как ИИ должен обработать</span><select id="q-scope">${aiScopeOptions(file)}</select></label>
    <div class="foot-row"><button class="primary" id="q-ai">Сохранить и отправить ИИ</button><button class="ghost" id="q-save">Только сохранить</button><button class="ghost" id="q-publish">Сохранить и опубликовать</button><button class="ghost" id="q-cancel">Отмена</button></div>
    <p id="q-status" class="field-status" role="status" aria-live="polite" hidden></p>`, true);
  const save = async (mode) => {
    if (S.content !== doc || S.contentFile !== file) { toast("Вкладка изменилась — открой форму заново.", "warn"); return; }
    const text = $("#q-text", modal).value.trim();
    if (!text) { $("#q-status", modal).hidden = false; $("#q-status", modal).textContent = "Напиши текст вопроса."; return; }
    const item = { ...old, text, answer: $("#q-answer", modal).value.trim(), done: $("#q-done", modal).checked };
    if (newBlock) { bi = doc.blocks.length; doc.blocks.push({ type: "h", text: "Открытые вопросы" }, block); }
    if (isNew) block.items.push(item); else block.items[itemIndex] = item;
    $$("#q-save,#q-publish,#q-ai", modal).forEach((b) => b.disabled = true);
    const ok = markDirty(file, doc);
    if (!ok) { $("#q-status", modal).hidden = false; $("#q-status", modal).textContent = "Черновик не поместился в хранилище браузера. Правка остаётся в форме: скачай JSON или освободи место."; $$("#q-save,#q-publish,#q-ai", modal).forEach((b) => b.disabled = false); return; }
    const task = buildAiTask({ kind: "question", text, answer: item.answer, doc, file, scope: $("#q-scope", modal).value, target: "Открытые вопросы" });
    closeModal(); renderActiveDoc(); localSavedToast(true, "Изменение вопроса");
    if (mode === "publish") await pushCurrent();
    if (mode === "ai") await queueAgentTask(task);
  };
  $("#q-save", modal).onclick = () => save("local");
  $("#q-publish", modal).onclick = () => save("publish");
  $("#q-ai", modal).onclick = () => save("ai");
  $("#q-cancel", modal).onclick = closeModal;
  $(focusAnswer ? "#q-answer" : "#q-text", modal).focus();
}
function questionAction(button) {
  if (!assertEditable() || S.publishing) return;
  const bi = +button.dataset.s, i = +button.dataset.i;
  const block = S.content && S.content.blocks[bi], item = block && block.items[i];
  if (!item) return;
  const act = button.dataset.qact;
  if (act === "edit" || act === "answer") { openQuestionEditor(bi, i, act === "answer"); return; }
  if (act === "toggle") {
    item.done = !item.done;
    const ok = markDirty(); renderActiveDoc(); localSavedToast(ok, item.done ? "Решение" : "Возврат вопроса");
  }
  if (act === "delete" && confirm("Удалить этот вопрос из вкладки?")) {
    block.items.splice(i, 1);
    const ok = markDirty(); renderActiveDoc(); localSavedToast(ok, "Удаление вопроса");
  }
}
function submitQuestionForm(form, sendAi) {
  if (!assertEditable() || S.publishing) return;
  const bi = +form.dataset.qform, block = S.content && S.content.blocks[bi];
  if (!block) return;
  const text = form.elements.question.value.trim(), answer = form.elements.answer.value.trim();
  const status = form.querySelector(".field-status");
  if (!text) { status.hidden = false; status.textContent = "Напиши текст вопроса."; return; }
  block.items.push({ text, answer, done: false });
  const ok = markDirty();
  if (!ok) { block.items.pop(); status.hidden = false; status.textContent = "Браузер не сохранил черновик. Текст остаётся в форме."; return; }
  const task = sendAi ? buildAiTask({ kind: "question", text, answer, doc: S.content, file: S.contentFile, scope: defaultAiScope(S.contentFile), target: "Открытые вопросы" }) : null;
  renderActiveDoc(); localSavedToast(true, "Вопрос");
  const next = document.querySelector(`[data-qform="${bi}"] textarea[name="question"]`);
  if (next) next.focus();
  if (task) queueAgentTask(task);
}
function sectionEnd(blocks, headingIndex) {
  for (let i = headingIndex + 1; i < blocks.length; i++) if (blocks[i].type === "h") return i;
  return blocks.length;
}
function openTabComposer() {
  if (!assertEditable() || !S.docReady || !S.content) return;
  const doc = S.content, file = S.contentFile;
  const headings = doc.blocks.map((b, i) => b.type === "h" ? `<option value="${i}">${esc(b.text || "Раздел " + (i + 1))}</option>` : "").join("");
  const modal = openModal("Изменения во вкладке · " + (doc.title || file), `
    <p class="hint">Пиши обычным текстом: он появится прямо в этой вкладке, не в очереди агенту. «Сохранить во вкладке» оставляет правку в этом браузере; «Опубликовать» показывает её всем посетителям после обновления GitHub Pages.</p>
    <label class="f"><span>Что добавить</span><textarea id="tc-text" placeholder="Например: при потере цели зомби возвращается к последней точке патруля. Добавь это как правило поведения и отметь открытый вопрос по поиску пути."></textarea></label>
    <label class="f"><span>Куда добавить</span><select id="tc-target"><option value="">В конец вкладки</option>${headings}</select></label>
    <label class="f"><span>Как ИИ должен обработать</span><select id="tc-scope">${aiScopeOptions(file)}</select></label>
    <p class="hint">Можно писать абзацы, списки и подзаголовки <code>##</code>. «Отправить ИИ» создаёт задачу на целостную переработку: агент должен не просто вставить текст, а согласовать его с остальной библией.</p>
    <div class="foot-row"><button class="primary" id="tc-ai">Сохранить и отправить ИИ</button><button class="ghost" id="tc-save">Только сохранить</button><button class="ghost" id="tc-publish">Сохранить и опубликовать</button><button class="ghost" id="tc-cancel">Отмена</button></div>
    <p id="tc-status" class="field-status" role="status" aria-live="polite" hidden></p>`, true);
  const save = async (mode) => {
    if (S.content !== doc || S.contentFile !== file) { toast("Вкладка изменилась — открой форму заново.", "warn"); return; }
    const raw = $("#tc-text", modal).value.trim();
    const status = $("#tc-status", modal);
    if (!raw) { status.hidden = false; status.textContent = "Напиши, что добавить во вкладку."; return; }
    const added = parseBlocks(raw);
    if (!added.length) { status.hidden = false; status.textContent = "Не удалось разобрать текст."; return; }
    const target = $("#tc-target", modal).value;
    const at = target === "" ? doc.blocks.length : sectionEnd(doc.blocks, +target);
    doc.blocks.splice(at, 0, ...added);
    $$("#tc-save,#tc-publish,#tc-ai", modal).forEach((b) => b.disabled = true);
    const ok = markDirty(file, doc);
    if (!ok) { doc.blocks.splice(at, added.length); status.hidden = false; status.textContent = "Браузер не сохранил черновик. Текст остаётся в форме."; $$("#tc-save,#tc-publish,#tc-ai", modal).forEach((b) => b.disabled = false); return; }
    const targetLabel = target === "" ? "В конец вкладки" : (doc.blocks[+target] && doc.blocks[+target].text) || "Раздел";
    const task = buildAiTask({ kind: "change", text: raw, doc, file, scope: $("#tc-scope", modal).value, target: targetLabel });
    closeModal(); renderActiveDoc(); localSavedToast(true, "Изменение");
    const node = document.querySelector(`.sect[data-s="${at}"]`);
    if (node && node.scrollIntoView) node.scrollIntoView({ block: "center", behavior: "smooth" });
    if (mode === "publish") await pushCurrent();
    if (mode === "ai") await queueAgentTask(task);
  };
  $("#tc-save", modal).onclick = () => save("local");
  $("#tc-publish", modal).onclick = () => save("publish");
  $("#tc-ai", modal).onclick = () => save("ai");
  $("#tc-cancel", modal).onclick = closeModal;
  $("#tc-text", modal).focus();
}

/* ----------------------------- модалки ------------------------------------- */
let modalStack = [];
let saveManifests = () => {};
function openModal(title, html, narrow) {
  const root = $("#modal-root");
  root.hidden = false; root.style.display = "grid";
  const m = el("div", "modal" + (narrow ? " narrow" : ""));
  m.innerHTML = `<header><h3>${esc(title)}</h3><button class="ghost" data-close>✕</button></header><div class="content">${html}</div>`;
  root.innerHTML = "";
  root.appendChild(m);
  modalStack = [m];
  $("[data-close]", m).onclick = closeModal;
  root.onclick = (e) => { if (e.target === root) closeModal(); };
  document.onkeydown = (e) => { if (e.key === "Escape" && !root.hidden) closeModal(); };
  return m;
}
function closeModal() { const r = $("#modal-root"); r.hidden = true; r.style.display = "none"; r.innerHTML = ""; }

/* ----------------------------- загрузка контента --------------------------- */
function fileFor(tabId, sub) {
  if (tabId === "scenario") return "scenario.json";
  if (tabId === "preview") return "preview.json";
  const m = MECH.find((x) => x.id === (sub || S.sub));
  return m ? m.file : MECH[0].file;
}
async function loadCurrent(showLoader = true) {
  const file = fileFor(S.mainTab, S.sub);
  if (showLoader) $("#doc").innerHTML = `<div class="loading">Загрузка ${esc(file)}…</div>`;
  try {
    let text = null;
    try { text = localStorage.getItem(draftKey(file)); } catch (e) { /* published copy still works */ }
    let fromDraft = false;
    let d = null;
    if (text) {
      try { d = JSON.parse(text); fromDraft = true; }
      catch (e) { toast("Локальный черновик повреждён и не удалён. Загружена опубликованная копия.", "warn", 7000); }
    }
    if (!d) d = JSON.parse(await loadText("content/" + file));
    if (!d || !Array.isArray(d.blocks)) throw new Error("В файле нет списка blocks");
    if (S.mainTab === "mechanics" && d.kind !== "mechanics") d.kind = "mechanics";
    if (fromDraft) {
      S.dirty.add(file);
      d._banner = "Локальная правка сохранена в этом браузере. Чтобы её увидели все, нажми «Опубликовать вкладку».";
    }
    S.content = d; S.contentFile = file; S.docReady = true;
    if (MECH.some((m) => m.file === file)) { statusCache[file] = d.status; renderSubtabs(); }
    renderDoc(d);
    setPill(fromDraft ? "warn" : "ok", fromDraft ? "черновик в браузере" : "из репозитория");
    updateFoot();
  } catch (e) {
    S.docReady = false; S.lastErr = e.message;
    $("#doc").innerHTML = `<div class="end-card">Не удалось загрузить <code>content/${esc(file)}</code>: ${esc(e.message)}<br>
      Проверь <b>⚙ Настройки</b> (репозиторий/ветка/токен). Если в репозитории файл есть — это кэш браузера или блокировка: нажми «Перезагрузить начисто».
      <div class="end-actions">
        <button class="tiny" id="ec-fresh">Перезагрузить начисто</button>
        <button class="tiny ghost" id="ec-copy">Скопировать диагностику</button>
      </div></div>`;
    const f = $("#ec-fresh"); if (f) f.onclick = () => { const u = new URL(location.href); u.searchParams.set("fresh", "1"); location.replace(u.href); };
    const cp = $("#ec-copy"); if (cp) cp.onclick = () => copyText(siteStatus() + "\nlast err: " + e.message);
    setPill("bad", "ошибка загрузки");
  }
}
function setPill(kind, text) { const p = $("#sync-pill"); p.className = "pill " + kind; p.textContent = text; }
function updateFoot() {
  const writable = canWrite();
  const localOnly = !S.token;
  $("#foot-info").textContent = `${S.origin.owner}/${S.origin.repo} · ${S.origin.branch} · ${S.publishing ? "публикация…" : writable ? "редактор · публикация в GitHub" : localOnly ? "редактор · локальные черновики" : "редактор · публикация недоступна"}`;
  $("#btn-save").disabled = S.publishing || (!writable && !localOnly);
  $("#btn-save").textContent = S.publishing ? "Публикация…" : localOnly ? "⤒ Подключить GitHub" : "⤒ Опубликовать вкладку";
  $("#btn-edit-tab").disabled = !S.docReady || S.publishing;
  const dirty = S.dirty.size > 0;
  $("#dirty-bar").hidden = !dirty;
  const failed = S.draftErrors.has(S.contentFile);
  $("#dirty-text").textContent = failed
    ? "Правка есть на экране, но браузер не смог сохранить черновик. Не закрывай страницу: скачай JSON или опубликуй правку."
    : "Изменения сохранены в этом браузере. Для других посетителей они появятся только после публикации.";
  $("#btn-dirty-save").textContent = localOnly ? "Подключить GitHub" : "Опубликовать вкладку";
  $("#btn-dirty-save").disabled = S.publishing || (!writable && !localOnly);
  $("#btn-dirty-reset").disabled = S.publishing;
  const bar = $("#readonly-bar");
  bar.hidden = writable;
  if (S.readonlyGate) {
    bar.innerHTML = 'Конфигурация не загружена — публикация временно отключена, локальное редактирование доступно. <button class="tiny" id="ro-retry">Повторить проверку</button>';
    $("#ro-retry", bar).onclick = async () => {
      $("#ro-retry", bar).disabled = true;
      await loadConfig().catch(() => {});
      updateFoot();
    };
  } else {
    bar.innerHTML = 'Редактирование включено: правки сохраняются в этом браузере. Чтобы изменения видели все, подключи GitHub. <button class="tiny" id="btn-token-now">Подключить GitHub</button>';
    $("#btn-token-now", bar).onclick = () => openSettings("github");
  }
}

/* ----------------------------- навигация ----------------------------------- */
function wireSelfTest() {
  const link = $("#lnk-selftest"), out = $("#selftest-out");
  if (!link || !out) return;
  link.onclick = () => {
    setTimeout(() => {
      const txt = out.textContent || "";
      if (!/app.js/.test(txt)) return;              // сторож уже всё подписал
      const add = "app.js: " + SITE_BUILD + " \u00b7 документ: " + (S.docReady ? "загружен" : "не загружен (" + (S.lastErr || "ждём сеть") + ")");
      out.textContent = txt.replace(/app.js:.*/, add);
    }, 60);
  };
}

function buildMainTabs() {
  $$("#main-tabs .tab-btn").forEach((b) => {
    b.classList.toggle("active", b.dataset.tab === S.mainTab);
    b.onclick = () => {
      S.mainTab = b.dataset.tab;
      $("#subtabs").hidden = S.mainTab !== "mechanics";
      buildMainTabs(); buildSubtabs(); syncHash();
      S.docReady = false; S.content = null;            // повторный клик по активной вкладке тоже грузит
      if (!S.inside) { openSite(); boot2(); } else goTab();
    };
  });
}
function buildSubtabs() {
  const host = $("#subtabs");
  if (S.mainTab !== "mechanics") { host.hidden = true; host.innerHTML = ""; return; }
  host.hidden = false;
  host.innerHTML = "";
  MECH.forEach((m, i) => {
    const st = statusOf(m);
    const b = el("button", "subtab" + (m.id === S.sub ? " active" : ""), `<i>${i + 1}</i> ${esc(m.label)} <span class="dot ${st}" title="${esc(STATUS[st] || "")}"></span>`);
    b.onclick = () => { S.sub = m.id; buildSubtabs(); syncHash(); loadCurrent(); };
    host.appendChild(b);
  });
  host.insertAdjacentHTML("beforeend", `<span class="subtab-note">${MECH.length} разделов: три опоры (крафт · исследование · выживание), сеть и PvP, плюс техника (бой, физика, ассеты, аудио/UI)</span>`);
}
const statusCache = {};
function statusOf(m) {
  const key = m.file;
  let dr = null;
  try { dr = JSON.parse(localStorage.getItem(draftKey(key)) || "null"); } catch (e) { /* ignore bad draft */ }
  if (dr && dr.status) return dr.status;
  return statusCache[key] || "draft";
}
async function primeStatuses() {
  for (const m of MECH) {
    try {
      const j = JSON.parse(await loadText("content/" + m.file));
      statusCache[m.file] = j.status;
    } catch (e) { /* нет файла/нет сети — не критично */ }
  }
  renderSubtabs();
}
function renderSubtabs() { if (S.mainTab === "mechanics") buildSubtabs(); }
function syncHash() {
  const h = S.mainTab === "mechanics" ? `#mechanics/${S.sub}` : `#${S.mainTab}`;
  const u = new URL(location.href);
  u.hash = h;
  history.replaceState(null, "", u.href);
}
function readHash() {
  const h = location.hash.replace(/^#/, "");
  if (!h) return;
  if (h.startsWith("mechanics/")) { S.mainTab = "mechanics"; S.sub = h.split("/")[1] || S.sub; }
  else if (TABS.some((t) => t.id === h)) S.mainTab = h;
}

/* ----------------------------- депозит: правки в GitHub -------------------- */
async function pushCurrent(silent) {
  if (S.publishing) return false;
  if (!canWrite()) {
    toast(writeBlockReason(), "warn", 6500);
    if (!S.token && !S.readonlyGate) openSettings("github");
    return false;
  }
  const file = S.contentFile, d = S.content, revision = S.revision;
  if (!file || !d) return false;
  S.publishing = true; updateFoot();
  setPill("", "публикация…");
  try {
    const published = cleanDoc(d);
    published.updated = nowIso();
    const path = `${S.config.contentPath}/${file}`;
    await ghPutText(path, JSON.stringify(published, null, 2) + "\n", `docs(${file.replace(/\.json$/, "")}): правка через сайт`);
    // Do not erase a newer edit made while the network request was in flight.
    if (S.contentFile !== file || S.revision === revision) {
      try { localStorage.removeItem(draftKey(file)); } catch (e) { /* remote save succeeded */ }
      S.dirty.delete(file); S.draftErrors.delete(file);
      if (S.contentFile === file) { d.updated = published.updated; delete d._banner; renderActiveDoc(); }
    }
    setPill("ok", "опубликовано");
    if (!silent) toast("Вкладка опубликована в " + S.origin.branch + ". GitHub Pages обновится примерно через минуту.", "ok", 6500);
    updateFoot();
    return true;
  } catch (e) {
    setPill("bad", S.draftErrors.has(file) ? "не опубликовано · скачай JSON" : "не опубликовано · черновик сохранён");
    toast("Публикация не выполнена: " + esc(e.hint || e.message) + (S.draftErrors.has(file) ? " Скачай JSON: браузер не смог сохранить черновик." : " Локальная правка остаётся во вкладке."), "bad", 9000);
    if (e.status === 401) openSettings("github");
    updateFoot();
    return false;
  } finally { S.publishing = false; updateFoot(); }
}
async function pullCurrent() {
  if (S.publishing) return;
  if (!confirm("Отменить локальные правки этой вкладки и загрузить опубликованную версию?")) return;
  const file = S.contentFile;
  try { localStorage.removeItem(draftKey(file)); } catch (e) { /* continue */ }
  S.draftErrors.delete(file);
  S.dirty.delete(file);
  $("#dirty-bar").hidden = !!S.dirty.size;
  await loadCurrent();
}
async function refreshAll() {
  try {
    await Promise.all([loadConfig(), loadCurrent(false)]);
    toast("Свежие данные подтянуты", "ok", 2200);
  } catch (e) { toast("Обновление: " + esc(e.message), "warn"); }
}

/* ----------------------------- настройки / доступ -------------------------- */
function openSettings(tab) {
  const editLink = makeEditLink();
  const modal = openModal("Настройки сайта · ссылка и GitHub", `
    <div class="tabs-mini">
      <button data-m="github">GitHub</button>
      <button data-m="access">Ссылка</button>
      <button data-m="sync">Синхронизация</button>
    </div>
    <div id="st-github" hidden>
      <p class="hint">Редактор открыт без кода. Локальные правки сохраняются в этом браузере. Подключение GitHub нужно только для публикации изменений для всех посетителей.</p>
      <label class="f"><span>Владелец</span><input id="st-owner" value="${esc(S.origin.owner)}"></label>
      <label class="f"><span>Репозиторий</span><input id="st-repo" value="${esc(S.origin.repo)}"></label>
      <label class="f"><span>Ветка (куда пишем / откуда читаем)</span><input id="st-branch" value="${esc(S.origin.branch)}"></label>
      <label class="f"><span>Токен GitHub (fine-grained: Contents Read and write)</span>
        <input id="st-token" type="password" autocomplete="off" placeholder="Вставить токен только в этом браузере" value="${esc(S.token)}"></label>
      <p class="hint">Токен хранится в этом браузере и отправляется только на api.github.com. Не добавляй его в ссылку или файлы репозитория.</p>
      <div class="foot-row"><button class="primary" id="st-save-gh">Сохранить и проверить доступ</button>
      <a class="ghost" style="text-decoration:none" target="_blank" rel="noopener" href="https://github.com/settings/personal-access-tokens/new">Создать fine-grained токен</a></div>
      <p id="st-gh-status" class="field-status" role="status" aria-live="polite" hidden></p>
    </div>
    <div id="st-access" hidden>
      <section class="share-panel editor-link-panel" aria-labelledby="edit-link-heading">
        <h4 id="edit-link-heading">Рабочая ссылка · полный редактор</h4>
        <p>Ссылка сразу открывает редактор без кода доступа и без режима «только чтение». Правки можно сохранять в браузере; для общей публикации нужен GitHub владельца.</p>
        <label class="f"><span>Ссылка для редактирования</span><input id="st-edit-link" readonly value="${esc(editLink)}"></label>
        <div class="foot-row"><button class="primary" id="st-copy-edit">Скопировать рабочую ссылку</button><a class="ghost" id="st-open-edit" href="${esc(editLink)}">Открыть редактор</a></div>
      </section>
      <p class="hint">Ссылка не содержит токен и не даёт права записи в GitHub. Не помещай в публичный сайт секретные материалы.</p>
    </div>
    <div id="st-sync" hidden>
      <label class="f"><input type="checkbox" id="st-auto" ${localStorage.getItem(LS.refresh) === "1" ? "checked" : ""}> Автообновление каждые 90 с (когда нет несохранённых правок)</label>
      <div class="foot-row"><button class="ghost" id="st-pull-now">Подтянуть всё сейчас</button></div>
      <p class="hint">После записи в ветку <code>${esc(S.origin.branch)}</code> GitHub Actions обновляет Pages.</p>
    </div>`);
  const show = (t) => {
    ["github", "access", "sync"].forEach((k) => { $("#st-" + k, modal).hidden = k !== t; });
    $$(".tabs-mini button", modal).forEach((b) => b.classList.toggle("on", b.dataset.m === t));
  };
  $$(".tabs-mini button", modal).forEach((b) => b.onclick = () => show(b.dataset.m));
  show(tab === "github" ? "github" : tab === "sync" ? "sync" : "access");
  const report = (sel, text, bad) => { const n = $(sel, modal); if (!n) return; n.textContent = text; n.hidden = false; n.style.color = bad ? "var(--red)" : "var(--tx2)"; };
  $("#st-save-gh", modal).onclick = async () => {
    const owner = $("#st-owner", modal).value.trim(), repo = $("#st-repo", modal).value.trim();
    const branch = $("#st-branch", modal).value.trim() || "main", token = $("#st-token", modal).value.trim();
    if (!owner || !repo || !token) { report("#st-gh-status", "Заполни владельца, репозиторий и токен.", true); return; }
    report("#st-gh-status", "Проверяю токен…", false);
    try {
      const r = await fetch(`https://api.github.com/repos/${owner}/${repo}`, { headers: ghHeaders(token), cache: "no-store" });
      if (!r.ok) throw new Error("GitHub HTTP " + r.status);
      const meta = await r.json();
      if (meta.permissions && meta.permissions.push === false) throw new Error("Токен не имеет права записи в этот репозиторий");
      S.origin = { owner, repo, branch }; S.token = token;
      localStorage.setItem(LS.origin, JSON.stringify(S.origin)); localStorage.setItem(LS.token, token);
      S.readonlyGate = false; updateFoot();
      report("#st-gh-status", "GitHub подключён. Теперь можно публиковать вкладки.", false);
      toast("GitHub подключён", "ok");
    } catch (e) {
      if (/401/.test(e.message)) {
        S.token = "";
        try { localStorage.removeItem(LS.token); } catch (err) { /* ignore */ }
        $("#st-token", modal).value = "";
        updateFoot();
      }
      report("#st-gh-status", "Не подключилось: " + e.message, true);
    }
  };
  $("#st-copy-edit", modal).onclick = () => copyText(editLink).then(() => toast("Рабочая ссылка скопирована", "ok"));
  $("#st-auto", modal).onchange = (e) => localStorage.setItem(LS.refresh, e.target.checked ? "1" : "0");
  $("#st-pull-now", modal).onclick = async () => { await loadConfig(); await loadCurrent(true); toast("Подтянуто из GitHub", "ok"); };
}

async function loadConfig() {
  let raw = null;
  try { raw = await loadText("config.json"); S.cfgOk = true; S.cfgFailed = false; }
  catch (e) { S.cfgOk = false; S.cfgFailed = true; }
  if (raw) {
    try {
      const loaded = JSON.parse(raw);
      delete loaded.token; delete loaded.githubToken; // Public configuration must never become a credential store.
      S.config = { ...S.config, ...loaded };
    } catch (e) { S.cfgOk = false; S.cfgFailed = true; }
  }
  S.cfgLoaded = true;
  S.readonlyGate = !S.cfgOk;
  const host = location.hostname || "";
  if (host.endsWith(".github.io")) {
    const owner = host.split(".")[0];
    const repo = (location.pathname.split("/")[1] || "").replace(/\.html$/, "");
    if (owner && repo) {
      S.origin = { owner, repo, branch: (S.config.origin && S.config.origin.branch) || REPO_DEFAULT.branch };
    }
  }
}
function download(name, text, mime) {
  const a = el("a"); a.href = URL.createObjectURL(new Blob([text], { type: mime || "text/plain" })); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

function dismissWatchdog() {
  // приложение поднялось и работает: убираем «преждевременную» карточку сторожа
  try { if (typeof window.__ZOMBI_DISMISS__ === "function") window.__ZOMBI_DISMISS__(); } catch (e) { /* не критично */ }
}

function guardStaleBuild() {
  const LS_BUILD = "zombi-docs:build";
  let prev = null;
  try { prev = localStorage.getItem(LS_BUILD); } catch (e) { return false; }
  try { localStorage.setItem(LS_BUILD, SITE_BUILD); } catch (e) {}
  const htmlStamp = document.documentElement.getAttribute("data-build") || "";
  const realPrev = prev && prev !== "inline" ? prev : "";
  const mismatch = (!!realPrev && realPrev !== SITE_BUILD) || (!!htmlStamp && htmlStamp !== SITE_BUILD);
  if (mismatch && !location.search.includes("fresh=1")) {
    try {
      const u = new URL(location.href);
      u.searchParams.set("fresh", "1");
      window.__ZOMBI_RELOAD__ = u.href;    // видно в консоли/диагностике, что сработал страж кэша
      location.replace(u.href);
      return true;
    } catch (e) { return false; }
  }
  return false;
}

function siteStatus() {
  return [
    "ZOMBI docs site " + SITE_BUILD,
    "url " + location.href,
    "origin " + S.origin.owner + "/" + S.origin.repo + "@" + S.origin.branch,
    "config " + (S.cfgOk ? "ok" : S.cfgFailed ? "failed" : "loading"),
    "token " + (S.token ? "yes" : "no"),
    "inside " + (S.inside ? "yes" : "no"),
    "last err " + (S.lastErr || "—"),
  ].join("\n");
}
function showSiteStatus() {
  const txt = siteStatus();
  openModal("Диагностика сайта", `<pre class="diag">${esc(txt)}</pre><div class="foot-row"><button class="primary" id="diag-copy">Скопировать</button></div>`, false);
  $("#diag-copy").onclick = () => copyText(txt);
}
function openSite() {
  S.inside = true;
  const app = $("#app"); if (app) { app.hidden = false; app.style.display = "flex"; }
  const ld = document.getElementById("site-loader");
  if (ld) ld.textContent = "редактор открыт · жду app.js…";
}
window.zombiOpenSite = openSite;

/* ----------------------------- картинки ------------------------------------ */
function dataUrlBytes(dataUrl) {
  const b64 = dataUrl.slice(dataUrl.indexOf(",") + 1);
  return bytesFromB64(b64);
}
async function fileToDataUrl(file) {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file); });
}
async function compressImage(file, maxSide = 1400, quality = 0.85) {
  const bmp = await createImageBitmap(file).catch(() => null);
  if (!bmp) return { bytes: new Uint8Array(await file.arrayBuffer()), name: file.name.replace(/\.[^.]+$/, "") + ".png", mime: file.type || "image/png" };
  const k = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
  const w = Math.max(1, Math.round(bmp.width * k)), h = Math.max(1, Math.round(bmp.height * k));
  const c = document.createElement("canvas"); c.width = w; c.height = h;
  const ctx = c.getContext("2d"); ctx.fillStyle = "#000"; ctx.fillRect(0, 0, w, h); ctx.drawImage(bmp, 0, 0, w, h);
  let mime = "image/webp", q = quality, url = c.toDataURL(mime, q);
  if (url.length * 0.75 > MAX_IMG) { mime = "image/jpeg"; url = c.toDataURL(mime, q); }
  let bytes = dataUrlBytes(url);
  while (bytes.length > MAX_IMG && q > 0.4) { q -= 0.12; url = c.toDataURL(mime, q); bytes = dataUrlBytes(url); }
  const ext = mime === "image/webp" ? "webp" : "jpg";
  return { bytes, name: file.name.replace(/\.[^.]+$/, "") + "." + ext, mime, url, w, h };
}
function slug(s) {
  const map = { а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh", з: "z", и: "i", й: "y", к: "k", л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "h", ц: "ts", ч: "ch", ш: "sh", щ: "sch", ъ: "", ы: "y", ь: "", э: "e", ю: "yu", я: "ya", " ": "-", "/": "-" };
  return String(s).toLowerCase().split("").map((c) => (c in map ? map[c] : /[a-z0-9\-_.]/.test(c) ? c : "")).join("").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 60) || "image";
}
async function addImageUI() {
  if (!S.token) { addImageByURL(); return; }
  const modal = openModal("Новая картинка → репозиторий", `
    <div class="drop" id="dr">Перетащи файл сюда или <label style="color:var(--acc2);cursor:pointer">выбери<input id="im-file" type="file" accept="image/*" hidden></label></div>
    <div id="im-prev" style="display:none;margin:12px 0"><img style="max-width:100%;max-height:220px;border-radius:9px;border:1px solid var(--line)"><div class="hint" id="im-info"></div></div>
    <label class="f"><span>Имя файла (в репозитории)</span><input id="im-name" placeholder="images/preview/concept-island.webp"></label>
    <label class="f"><span>Подпись</span><input id="im-cap" placeholder="Берег в тумане — обложка"></label>
    <label class="f"><span>Теги (через запятую)</span><input id="im-tags" placeholder="concept, cover"></label>
    <label class="f"><span>Привязать к вкладке</span><select id="im-tab">${tabOptions()}</select></label>
    <div class="foot-row"><button class="primary" id="im-up">Загрузить в GitHub</button><button class="ghost" id="im-url">Вместо файла — ссылка</button></div>`);
  let packed = null;
  const drop = $("#dr", modal), fi = $("#im-file", modal);
  const handle = async (f) => {
    if (!f) return;
    const p = await compressImage(f);
    packed = p;
    $("#im-prev", modal).style.display = "";
    $("#im-prev img", modal).src = p.url;
    $("#im-info", modal).innerHTML = `${p.w}×${p.h} · ${(p.bytes.length / 1024).toFixed(0)} КБ · ${p.mime} → <code>${SRC_PREFIX}/${S.config.imagesPath.replace(SRC_PREFIX + "/content/", "content/")}/…</code>`;
    if (!$("#im-name", modal).value) $("#im-name", modal).value = "preview/" + slug(f.name.replace(/\.[^.]+$/, "")) + "." + p.name.split(".").pop();
    if (!$("#im-cap", modal).value) $("#im-cap", modal).value = f.name.replace(/\.[^.]+$/, "");
  };
  fi.onchange = () => handle(fi.files[0]);
  ["dragover", "dragenter"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add("on"); }));
  ["dragleave", "drop"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove("on"); if (ev === "drop") handle(e.dataTransfer.files[0]); }));
  $("#im-url", modal).onclick = () => { closeModal(); addImageByURL(); };
  $("#im-up", modal).onclick = async () => {
    if (!packed) { toast("Сначала выбери файл", "warn"); return; }
    const rel = $("#im-name", modal).value.trim().replace(/^\/+/, "");
    const full = `${S.config.imagesPath}/${rel.replace(/^images\//, "")}`;
    try {
      await ghPutBytes(full, packed.bytes, `docs(img): ${rel}`);
      const entry = { id: slug(rel), name: $("#im-cap", modal).value.trim() || rel, file: "images/" + rel.replace(/^images\//, ""),
        caption: $("#im-cap", modal).value.trim(), tags: $("#im-tags", modal).value.split(",").map((s) => s.trim()).filter(Boolean),
        tab: $("#im-tab", modal).value, author: "web", date: nowIso().slice(0, 10) };
      S.images.items = S.images.items.filter((i) => i.file !== entry.file);
      S.images.items.unshift(entry);
      await ghPutText(`${S.config.contentPath}/images.json`, JSON.stringify(S.images, null, 2) + "\n", `docs(img-manifest): + ${rel}`);
      closeModal(); toast("Картинка в репозитории и в списке", "ok");
      if (S.mainTab === "preview") loadCurrent(false);
    } catch (e) { toast("Загрузка не удалась: " + esc(e.message), "bad", 9000); }
  };
}
function tabOptions() {
  return `<option value="">— без привязки —</option><option value="scenario">Сценарий</option><option value="preview">Картинки/превью</option>` +
    MECH.map((m) => `<option value="mechanics/${m.id}">Механика · ${esc(m.label)}</option>`).join("");
}
function addImageByURL() {
  const modal = openModal("Картинка по ссылке", `
    <label class="f"><span>URL (например raw.githubusercontent.com/…)</span><input id="u-src" placeholder="https://raw.githubusercontent.com/${S.origin.owner}/${S.origin.repo}/${S.origin.branch}/game-docs/src/content/images/preview/xxx.png"></label>
    <label class="f"><span>Подпись</span><input id="u-cap"></label>
    <label class="f"><span>Теги</span><input id="u-tags" placeholder="screenshot, location"></label>
    <label class="f"><span>Привязка</span><select id="u-tab">${tabOptions()}</select></label>
    <p class="hint">Такой способ не требует токена: файл должен уже лежать в репозитории (закинул агент или ты через web editor GitHub).</p>
    <div class="foot-row"><button class="primary" id="u-ok">Добавить</button></div>`);
  $("#u-ok", modal).onclick = async () => {
    const entry = { id: "url-" + Math.random().toString(36).slice(2, 7), name: $("#u-cap", modal).value.trim() || "Картинка", file: $("#u-src", modal).value.trim(),
      caption: $("#u-cap", modal).value.trim(), tags: $("#u-tags", modal).value.split(",").map((s) => s.trim()).filter(Boolean), tab: $("#u-tab", modal).value, author: "web", date: nowIso().slice(0, 10) };
    S.images.items.unshift(entry);
    if (S.token) { try { await ghPutText(`${S.config.contentPath}/images.json`, JSON.stringify(S.images, null, 2) + "\n", "docs(img-manifest): + ссылка"); toast("Сохранено в репозиторий", "ok"); } catch (e) { toast("В браузер добавлено, в GitHub не удалось: " + esc(e.message), "warn", 7000); } }
    else toast("Добавлено локально (без токена — только в этом браузере)", "warn", 6000);
    localStorage.setItem("zombi-docs:images", JSON.stringify(S.images));
    closeModal(); if (S.mainTab === "preview") loadPreview();
  };
}

/* ----------------------------- 3D-модели ----------------------------------- */
async function addModelUI() {
  const modal = openModal("3D-модель → репозиторий", `
    <div class="drop" id="md">Перетащи GLB/GLTF/FBX/OBJ <label style="color:var(--acc2);cursor:pointer">или выбери<input id="md-file" type="file" accept=".glb,.gltf,.fbx,.obj,.zip,.blend" hidden></label></div>
    <div class="hint" id="md-info"></div>
    <label class="f"><span>Имя файла в репозитории</span><input id="md-name" placeholder="models/chr_mark_01.glb"></label>
    <label class="f"><span>Название</span><input id="md-title" placeholder="Персонаж Марк — базовая модель"></label>
    <label class="f"><span>Описание</span><textarea id="md-desc" style="min-height:70px" placeholder="Бюджет, из чего, что осталось сделать"></textarea></label>
    <label class="f"><span>Привязка к вкладке</span><select id="md-tab">${tabOptions()}</select></label>
    <div class="foot-row"><button class="primary" id="md-up" ${S.token ? "" : "disabled"}>Загрузить (нужен токен)</button>
    <button class="ghost" id="md-ref">Только запись в реестр</button></div>`);
  let picked = null;
  $("#md-file", modal).onchange = (e) => {
    const f = e.target.files[0]; if (!f) return;
    picked = f;
    $("#md-info", modal).innerHTML = `${esc(f.name)} · ${(f.size / 1048576).toFixed(2)} МБ ${f.size > MAX_MODEL ? "<b style='color:var(--bad)'>— слишком большой для GitHub web-коммита, разбей или используй Git LFS</b>" : ""}`;
    if (!$("#md-name", modal).value) $("#md-name", modal).value = slug(f.name).replace(/\.(glb|gltf|fbx|obj|zip|blend)$/, "") + "." + (f.name.split(".").pop() || "glb");
    if (!$("#md-title", modal).value) $("#md-title", modal).value = f.name.replace(/\.[^.]+$/, "");
  };
  const entry = () => ({ id: slug($("#md-name", modal).value || "model"), name: $("#md-title", modal).value.trim() || $("#md-name", modal).value,
    file: "models/" + $("#md-name", modal).value.trim().replace(/^models\//, ""), description: $("#md-desc", modal).value.trim(),
    tab: $("#md-tab", modal).value, size_mb: picked ? +(picked.size / 1048576).toFixed(2) : null, date: nowIso().slice(0, 10) });
  $("#md-up", modal).onclick = async () => {
    if (!picked) { toast("Выбери файл", "warn"); return; }
    if (picked.size > MAX_MODEL) { toast("Файл больше 24 МБ — GitHub не примет. Сожми или положи через Git LFS", "bad", 8000); return; }
    const bytes = new Uint8Array(await picked.arrayBuffer());
    const rel = $("#md-name", modal).value.trim();
    try {
      await ghPutBytes(`${S.config.modelsPath}/${rel.replace(/^models\//, "")}`, bytes, `docs(model): ${rel}`);
      const e = entry(); S.models.items = S.models.items.filter((i) => i.file !== e.file); S.models.items.unshift(e);
      await ghPutText(`${S.config.contentPath}/models.json`, JSON.stringify(S.models, null, 2) + "\n", `docs(model-manifest): ${rel}`);
      closeModal(); toast("Модель в репозитории", "ok"); loadPreview();
    } catch (err) { toast("Ошибка: " + esc(err.message), "bad", 9000); }
  };
  $("#md-ref", modal).onclick = () => {
    const e = entry(); S.models.items.unshift(e);
    localStorage.setItem("zombi-docs:models", JSON.stringify(S.models));
    if (S.token) ghPutText(`${S.config.contentPath}/models.json`, JSON.stringify(S.models, null, 2) + "\n", "docs(model-manifest): запись").catch(() => {});
    closeModal(); loadPreview(); toast("Запись добавлена", "ok");
  };
}
function resolveAsset(file) {
  if (!file) return "";
  if (/^https?:/.test(file)) return file;
  const local = "content/" + file.replace(/^\/+/, "");
  return (location.protocol.startsWith("http") || location.protocol === "file:") ? local :
    `https://raw.githubusercontent.com/${S.origin.owner}/${S.origin.repo}/${encodeURIComponent(S.origin.branch)}/${S.config.contentPath}/${file}`;
}
async function view3D(file, name) {
  const modal = openModal("3D-превью · " + (name || file), `<div class="viewer" id="v3"><div class="spin" style="margin-top:140px"></div></div>
    <div class="foot-row"><a class="ghost" style="text-decoration:none" target="_blank" href="${esc(resolveAsset(file))}">Скачать / открыть файл</a>
    <span class="hint">Крути мышью, колесо — зум. Работает для GLB/GLTF (three.js из CDN).</span></div>`);
  const host = $("#v3", modal);
  const url = resolveAsset(file);
  try {
    const THREE = await import("three");
    const { GLTFLoader } = await import("three/addons/loaders/GLTFLoader.js");
    const { OrbitControls } = await import("three/addons/controls/OrbitControls.js");
    host.innerHTML = "";
    const w = host.clientWidth, h = host.clientHeight;
    const scene = new THREE.Scene(); scene.background = new THREE.Color(0x0a1017);
    const cam = new THREE.PerspectiveCamera(45, w / h, 0.05, 500);
    cam.position.set(2.2, 1.6, 2.6);
    const rn = new THREE.WebGLRenderer({ antialias: true }); rn.setSize(w, h); rn.setPixelRatio(Math.min(2, devicePixelRatio));
    rn.useLegacyLights = false; host.appendChild(rn.domElement);
    scene.add(new THREE.HemisphereLight(0xbfd4ff, 0x141a20, 1.4));
    const dl = new THREE.DirectionalLight(0xffffff, 2.2); dl.position.set(3, 6, 4); scene.add(dl);
    const grid = new THREE.GridHelper(10, 20, 0x2f3f52, 0x1b242f); scene.add(grid);
    const gltf = await new GLTFLoader().loadAsync(url);
    const root = gltf.scene;
    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3()), center = box.getCenter(new THREE.Vector3());
    const s = 3 / Math.max(size.x, size.y, size.z, 0.001);
    root.scale.setScalar(s); root.position.copy(center.multiplyScalar(-s));
    scene.add(root);
    const controls = new OrbitControls(cam, rn.domElement); controls.enableDamping = true;
    (function loop() { requestAnimationFrame(loop); controls.update(); rn.render(scene, cam); })();
    host.insertAdjacentHTML("beforeend", `<div class="tip">триангл-счётчик: ${root.traverse ? "?" : "?"} · масштаб авто</div>`);
    addEventListener("resize", () => { rn.setSize(host.clientWidth, host.clientHeight); cam.aspect = host.clientWidth / host.clientHeight; cam.updateProjectionMatrix(); });
  } catch (e) {
    host.innerHTML = `<div class="err">Не удалось показать превью (${esc(e.message)}).<br>Скачай файл кнопкой ниже и открой в <a href="https://gltf-viewer.donmccurdy.com/" target="_blank">gltf-viewer</a> или Godot.</div>`;
  }
}

/* ----------------------------- вкладка превью ------------------------------ */
async function loadManifests() {
  const fallback = (k, p) => { try { return JSON.parse(localStorage.getItem("zombi-docs:" + k)); } catch (e) { return null; } void p; };
  saveManifests = () => { localStorage.setItem("zombi-docs:images", JSON.stringify(S.images)); localStorage.setItem("zombi-docs:models", JSON.stringify(S.models)); };
  try { S.images = JSON.parse(await loadText("content/images.json")); } catch (e) { S.images = fallback("images") || { items: [] }; }
  try { S.models = JSON.parse(await loadText("content/models.json")); } catch (e) { S.models = fallback("models") || { items: [] }; }
  const lI = fallback("images"), lM = fallback("models");
  if (lI && lI.items) lI.items.forEach((i) => { if (!S.images.items.some((x) => x.file === i.file)) S.images.items.unshift(i); });
  if (lM && lM.items) lM.items.forEach((i) => { if (!S.models.items.some((x) => x.file === i.file)) S.models.items.unshift(i); });
}
async function loadPreview() {
  await loadCurrent(false);
  await loadManifests();
  const host = $("#doc");
  const box = el("div");
  box.innerHTML = `<div class="h3row"><h2>Картинки · ${S.images.items.length}</h2><span class="spacer"></span>
      ${'<button class="primary" id="p-add-img">＋ Картинка</button>'}</div>`;
  const grid = el("div", "prev-grid");
  S.images.items.forEach((it, i) => grid.appendChild(imgCard(it, i)));
  {
    const add = el("button", "card add-card", "＋ добавить картинку"); add.onclick = () => addImageUI();
    grid.appendChild(add);
  }
  box.appendChild(grid);

  box.insertAdjacentHTML("beforeend", `<div class="h3row"><h2>3D-модели · ${S.models.items.length}</h2><span class="spacer"></span>
      ${'<button class="primary" id="p-add-md">＋ 3D-модель</button>'}</div>`);
  const g2 = el("div", "prev-grid");
  S.models.items.forEach((it, i) => g2.appendChild(modelCard(it, i)));
  {
    g2.appendChild(el("button", "card add-card", "＋ добавить модель"));
    g2.lastChild.onclick = () => addModelUI();
  }
  box.appendChild(g2);

  box.insertAdjacentHTML("beforeend", `<div class="h3row"><h2>Куда смотреть дальше</h2></div>
    <div class="note">Архивы в корне репозитория (<code>ZOMBI.7z.*</code>, <code>остров 1.7z.*</code>, <code>персонаж 1.7z.*</code>) — это, судя по всему, исходники проекта. Скажи агенту: «распакуй и разложи превью по вкладке „Картинки / превью“» — он распакует, отрежет превьюшки, зальёт в <code>game-docs/src/content/images/</code> и обновит реестр.</div>`);
  host.appendChild(box);
  {
    $("#p-add-img", host).onclick = () => addImageUI();
    $("#p-add-md", host).onclick = () => addModelUI();
  }
}
function imgCard(it, i) {
  const c = el("div", "card");
  const src = resolveAsset(it.file);
  c.innerHTML = `<div class="thumb"><img src="${esc(src)}" alt="${esc(it.name)}" loading="lazy" onerror="this.parentNode.innerHTML='⚠️ нет файла'"></div>
    <div class="body"><b>${esc(it.name)}</b><p>${esc(it.caption || "")}</p>
    <div class="tags">${(it.tags || []).map((t) => `<span>${esc(t)}</span>`).join("")}${it.tab ? `<span>→ ${esc(it.tab)}</span>` : ""}</div>
    <div class="row"><a class="tiny" style="text-decoration:none" target="_blank" href="${esc(src)}">открыть</a>
    ${`<button class="tiny" data-x="${i}" data-kind="img">в реестр ✕</button>`}</div></div>`;
  $("[data-x]", c).onclick = () => { S.images.items.splice(i, 1); localStorage.setItem("zombi-docs:images", JSON.stringify(S.images)); loadPreview(); toast("Убрано из списка (файл в репозитории остался)", "warn", 5000); };
  return c;
}
function modelCard(it, i) {
  const c = el("div", "card");
  const isGlb = /\.(glb|gltf)$/i.test(it.file || "");
  c.innerHTML = `<div class="thumb"><div class="no3d">${isGlb ? "🧊" : "📦"}</div></div>
    <div class="body"><b>${esc(it.name)}</b><p>${esc(it.description || "")}</p>
    <div class="tags"><code style="font-size:11px">${esc(it.file || "")}</code>${it.size_mb ? `<span>${it.size_mb} МБ</span>` : ""}${it.tab ? `<span>→ ${esc(it.tab)}</span>` : ""}</div>
    <div class="row"><button class="tiny" data-view>👁 превью</button>
    <a class="tiny" style="text-decoration:none" target="_blank" href="${esc(resolveAsset(it.file))}">скачать</a>
    ${'<button class="tiny" data-x>убрать ✕</button>'}</div></div>`;
  $("[data-view]", c).onclick = () => view3D(it.file, it.name);
  $("[data-x]", c).onclick = () => { S.models.items.splice(i, 1); localStorage.setItem("zombi-docs:models", JSON.stringify(S.models)); loadPreview(); };
  return c;
}

/* ----------------------------- задача на обработку ИИ ---------------------- */
function defaultAiScope(file) { return file === "mech_character.json" ? "character-concept" : "linked"; }
function aiScopeOptions(file) {
  const selected = defaultAiScope(file);
  return [
    ["section", "Только этот фрагмент / вопрос"],
    ["tab", "Пересобрать всю текущую вкладку"],
    ["linked", "Вкладку и связанные системы"],
    ["character-concept", "Всю концепцию построения персонажа"],
  ].map(([v, label]) => `<option value="${v}" ${v === selected ? "selected" : ""}>${label}</option>`).join("");
}
function docContextForAi(doc) {
  const headings = (doc.blocks || []).filter((b) => b.type === "h").map((b) => "- " + (b.text || ""));
  const questions = [];
  (doc.blocks || []).forEach((b, i) => {
    if (b.type === "todo" && isQuestionBlock(i, doc)) (b.items || []).forEach((it) => questions.push(`- [${it.done ? "x" : " "}] ${it.text}${it.answer ? " Ответ: " + it.answer : ""}`));
  });
  return ["Заголовок: " + (doc.title || ""), "Подзаголовок: " + (doc.subtitle || ""), "", "Подразделы:", ...(headings.length ? headings : ["- нет"]), "", "Открытые вопросы:", ...(questions.length ? questions : ["- нет"])].join("\n");
}
function buildAiTask({ kind, text, answer, doc, file, scope, target }) {
  const id = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6);
  const name = `${id}-${slug(text).slice(0, 40) || "pravka"}.md`;
  const tab = sectionHash().slice(1);
  const scopeText = {
    section: "Только указанный фрагмент, но проверить, что он не противоречит вкладке.",
    tab: "Пересобрать текущую вкладку целиком вокруг изменения.",
    linked: "Обновить текущую вкладку и все связанные системы/числа.",
    "character-concept": "Пересмотреть всю концепцию построения персонажа: происхождение, тело, практика, специализация, снаряжение, связи с крафтом/исследованием/боем/сценарием/сетью.",
  }[scope] || scope;
  const body = [
    "# Задача ИИ: " + (kind === "question" ? "открытый вопрос" : "изменение вкладки"),
    "",
    "- id: " + id,
    "- created: " + nowIso(),
    "- status: pending",
    "- source: site-editor",
    "- tab: " + tab,
    "- file: game-docs/src/content/" + file,
    "- target: " + (target || "вся вкладка"),
    "- scope: " + scope,
    "- local_draft_saved: yes",
    "",
    "## Запрос автора",
    "",
    text,
    "",
    ...(answer ? ["## Ответ / решение автора", "", answer, ""] : []),
    "## Контекст вкладки",
    "",
    docContextForAi(doc),
    "",
    "## Что должен сделать ИИ",
    "",
    "1. Прочитать `game-docs/src/docs/AGENT-GUIDE.md` и `README.md` в корне репозитория.",
    "2. Не ограничиваться вставкой текста: применить изменение так, чтобы система осталась целостной. Область: " + scopeText,
    "3. Найти связанные вкладки в `game-docs/src/content/` и согласовать числа, термины, зависимости и открытые вопросы. Для концепции персонажа обязательно проверить `scenario.json`, `mech_craft.json`, `mech_research.json`, `mech_inventory.json`, `mech_combat.json`, `mech_zombies.json`, `mech_multiplayer.json`.",
    "4. Сохранять канон проекта: Пелена, «Горизонт», вирус/Порог, отсутствие героических уровней и XP за убийства. Если изменение требует нового канонического решения — явно записать его и последствия.",
    "5. Ответить на затронутые открытые вопросы через `answer` и `done`; если решение неполное — добавить новые конкретные вопросы, а не оставлять «проработать».",
    "6. Обновить `updated` в изменённых JSON, проверить валидность JSON и выполнить `npm test --prefix game-docs`.",
    "7. Закоммитить и запушить только рабочую ветку, дождаться GitHub Pages, затем перенести этот файл в `agent-inbox/done/` с итогом: изменённые файлы, новые числа, оставшиеся вопросы.",
    "",
    "## Критерии готовности",
    "",
    "- Изменение отражено не только в одном абзаце, но и в правилах/числах/связях.",
    "- Нет противоречий между вкладками и сценарием.",
    "- Есть конкретные значения, формулы или таблицы там, где они нужны.",
    "- Открытые вопросы имеют ответы или новые точные формулировки.",
    "- Сайт собирается, тесты проходят, Pages опубликован.",
    "",
    "## Как запустить обработку",
    "",
    "Автор пишет агенту в Arena: «разбери inbox». Агент читает этот файл, выполняет задачу и переносит его в done/."
  ].join("\n");
  return { id, name, body, summary: text.slice(0, 60), scope };
}
function openAgentTaskPreview(task, error) {
  const modal = openModal("Задача для ИИ · " + task.name, `
    <p class="hint">${error ? "Отправка в GitHub не выполнена: " + esc(error) + ". " : ""}Правка сохранена во вкладке. Задачу можно скопировать в чат агенту или подключить GitHub и отправить в agent-inbox.</p>
    <label class="f"><span>Текст задачи</span><textarea id="ai-task-body" readonly style="min-height:45vh">${esc(task.body)}</textarea></label>
    <div class="foot-row"><button class="primary" id="ai-task-copy">Скопировать задачу</button>${'<button class="ghost" id="ai-task-gh">Подключить GitHub</button>'}<button class="ghost" id="ai-task-close">Закрыть</button></div>`, false);
  $("#ai-task-copy", modal).onclick = () => copyText(task.body);
  $("#ai-task-close", modal).onclick = closeModal;
  $("#ai-task-gh", modal).onclick = () => openSettings("github");
}
async function queueAgentTask(task) {
  if (!canWrite()) { openAgentTaskPreview(task); return false; }
  try {
    setPill("", "отправка задачи ИИ…");
    await ghPutText(`${S.config.inboxPath}/${task.name}`, task.body, `docs(inbox): ${task.summary}`);
    setPill("ok", "задача ИИ отправлена");
    toast("Задача отправлена в agent-inbox: " + task.name + ". Напишите агенту «разбери inbox», чтобы он обработал изменение.", "ok", 9000);
    return true;
  } catch (e) {
    setPill("bad", "задача ИИ не отправлена");
    openAgentTaskPreview(task, e.hint || e.message);
    return false;
  }
}

/* ----------------------------- запросы агенту ------------------------------ */
async function openInbox() {
  const files = S.token || S.origin.owner ? await ghListDir(S.config.inboxPath).catch(() => []) : [];
  const list = files.filter((f) => !/README/.test(f.name)).sort((a, b) => b.name.localeCompare(a.name)).slice(0, 25);
  const modal = openModal("Очередь агенту · " + S.config.inboxPath, `
    <p class="hint">Ты пишешь сюда короткую задачу → файл коммитится в <code>game-docs/src/content/agent-inbox/NNNN-slug.md</code>.
    Дальше достаточно написать агенту в Arena «разбери inbox» — он прочитает, внесёт правки в нужные вкладки и отметит файл выполненным (переименует в <code>done/</code>).</p>
    <label class="f"><span>Что нужно сделать</span><textarea id="in-text" placeholder="Пример: в «Механика → Погода» добавь таблицу 6 сезонов и эффект на скорость зомби; в «Локации» добавь зону «затопленный тоннель metro»"></textarea></label>
    <label class="f"><span>Куда отнести (необязательно)</span><select id="in-tab"><option value="">сам решу</option>${tabOptions()}</select></label>
    <div class="foot-row"><button class="primary" id="in-send"${S.token ? "" : " disabled"}>Отправить агенту (commit)</button>
    <button class="ghost" id="in-copy">Скопировать как сообщение агенту</button></div>
    <div class="h3row" style="margin-top:20px"><h2 style="font-size:15px">Файлы в очереди</h2></div>
    <div id="in-list">${list.length ? list.map((f) => `<div class="inbox-item"><b>${esc(f.name)}</b><span class="st">${(f.size / 1024).toFixed(1)} КБ</span></div>`).join("") : `<p class="hint">Пока пусто${S.token ? "" : " (список не подтянут: нет токена)"}.</p>`}</div>`);
  $("#in-copy", modal).onclick = () => {
    const txt = "Сайт-библия: " + ($("#in-text", modal).value.trim() || "(пусто)") + "\nОтнеси в: " + ($("#in-tab", modal).value || "на усмотрение агента") +
      "\nЗатем: 1) отредактируй нужный JSON в game-docs/src/content/, 2) выполни требования из game-docs/src/docs/AGENT-GUIDE.md, 3) закоммить и запуш, 4) добавь отметку в agent-inbox/.";
    copy(txt); toast("Скопировано — вставь в чат с агентом", "ok");
  };
  $("#in-send", modal).onclick = async () => {
    const t = $("#in-text", modal).value.trim();
    if (!t) { toast("Пустой запрос", "warn"); return; }
    const n = String(1000 + (S.inboxSeq = (S.inboxSeq || Date.now() % 900) + 1)).slice(-4);
    const name = `${n}-${slug(t).slice(0, 34)}.md`;
    const body = ["# " + name, "", "- отправлено: " + nowIso(), "- вкладка: " + ($("#in-tab", modal).value || "на усмотрение агента"), "- сайт: " + location.href, "", "## Запрос", "", t, "", "## Что сделать агенту", "", "1. Прочитать `game-docs/src/docs/AGENT-GUIDE.md` (правила проекта + стандарт детализации).", "2. Внести правки в нужный JSON в `game-docs/src/content/`.", "3. Проверить JSON, закоммитить, запушить, дождаться деплоя Pages.", "4. Переместить этот файл в `agent-inbox/done/` с кратким итогом в конце."].join("\n");
    try {
      await ghPutText(`${S.config.inboxPath}/${name}`, body, `docs(inbox): ${t.slice(0, 40)}`);
      toast("Запрос закоммичен: " + name, "ok"); closeModal();
    } catch (e) { toast("Не вышло: " + esc(e.message), "bad", 8000); }
  };
}

/* ----------------------------- документация сайта -------------------------- */
async function showDoc(which, title) {
  const files = { agent: "docs/AGENT-GUIDE.md", usage: "docs/USAGE.md" };
  let text = "";
  try { text = await loadText(files[which]); } catch (e) { text = "Не удалось загрузить `" + files[which] + "`: " + e.message; }
  openModal(title, `<div class="md">${md(text)}</div>`);
}
function md(src) {
  const lines = String(src).split("\n");
  let out = "", inCode = false, listStack = [], inTable = false, headDone = false;
  const closeLists = () => { while (listStack.length) { out += listStack.pop() === "o" ? "</ol>" : "</ul>"; } };
  const closeTable = () => { if (inTable) { out += "</tbody></table>"; inTable = false; headDone = false; } };
  for (let l of lines) {
    if (/^\s*```/.test(l)) {
      if (inCode) { out += "</code></pre>"; inCode = false; } else { closeLists(); closeTable(); out += "<pre><code>"; inCode = true; }
      continue;
    }
    if (inCode) { out += esc(l) + "\n"; continue; }
    if (/^\s*\|/.test(l)) {
      if (/^\s*\|[\s:|-]+\|\s*$/.test(l)) continue;
      closeLists();
      const cells = l.split("|").map((c) => c.trim()).filter((c, i, a) => !(c === "" && (i === 0 || i === a.length - 1)));
      if (!inTable) { out += "<table><thead>"; inTable = true; headDone = false; }
      if (headDone) out += "<tbody>";
      const tag = headDone ? "td" : "th";
      out += "<tr>" + cells.map((c) => `<${tag}>${inline(c)}</${tag}>`).join("") + `</tr>`;
      headDone = true;
      continue;
    }
    closeTable(); closeLists();
    if (!l.trim()) continue;
    let m;
    if ((m = l.match(/^(#{1,4})\s+(.*)$/))) { const lvl = m[1].length; out += `<h${lvl}>${inline(m[2])}</h${lvl}>`; continue; }
    if (/^>\s?/.test(l)) { out += "<blockquote>" + inline(l.replace(/^>\s?/, "")) + "</blockquote>"; continue; }
    if ((m = l.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/))) {
      const depth = Math.floor(m[1].length / 2) + 1;
      const ordered = /\d/.test(m[2]);
      while (listStack.length > depth) out += listStack.pop() === "o" ? "</ol>" : "</ul>";
      while (listStack.length < depth) { out += ordered ? "<ol>" : "<ul>"; listStack.push(ordered ? "o" : "u"); }
      out += "<li>" + inline(m[3]) + "</li>";
      continue;
    }
    out += "<p>" + inline(l) + "</p>";
  }
  closeLists(); closeTable();
  if (inCode) out += "</code></pre>";
  return out;
}

/* ----------------------------- события документа --------------------------- */
let docWired = false;
function wireDoc() {
  if (docWired) return; docWired = true;
  $("#doc").addEventListener("submit", (e) => {
    const form = e.target.closest("[data-qform]");
    if (!form) return;
    e.preventDefault(); submitQuestionForm(form);
  });
  $("#doc").addEventListener("click", (e) => {
    const ai = e.target.closest("[data-qai]");
    if (ai) { const form = ai.closest("[data-qform]"); if (form) submitQuestionForm(form, true); return; }
    const q = e.target.closest("[data-qact]");
    if (q) { questionAction(q); return; }
    const b = e.target.closest("[data-act]");
    if (!b) return;
    if (!assertEditable()) return;
    const s = +b.dataset.s, act = b.dataset.act;
    if (act === "edit") editSection(findBlockIndex(s));
    if (act === "add-after") addSection(findBlockIndex(s));
    if (act === "del") { if (confirm("Удалить блок?")) { S.content.blocks.splice(findBlockIndex(s), 1); markDirty(); renderDoc(S.content); } }
    if (act === "up") moveBlock(findBlockIndex(s), -1);
    if (act === "down") moveBlock(findBlockIndex(s), 1);
  });
  $("#doc").addEventListener("change", (e) => {
    const b = e.target.closest("[data-act='toggle-todo']");
    if (!b || !assertEditable()) return;
    const s = findBlockIndex(+b.dataset.s);
    const it = S.content.blocks[s].items[+b.dataset.i];
    it.done = e.target.checked;
    markDirty(); renderDoc(S.content); // publication is always an explicit action
  });
  // (кнопки шапки навешаны в renderDoc)
  // «Быстрое редактирование» = raw-режим всего раздела
  $("#doc").addEventListener("dblclick", (e) => {
    if (e.target.closest("button,input,textarea,select,a,form,.question-panel")) return;
    const sec = e.target.closest(".sect");
    if (sec && assertEditable()) editSection(findBlockIndex(+sec.dataset.s));
  });
}
function findBlockIndex(sectIdx) { return sectIdx; }
/* куда идти по главному табу: превью = doc + галерея */
function goTab() { if (S.mainTab === "preview") loadPreview(); else loadCurrent(); }

/* ----------------------------- raw-редактор раздела ------------------------- */
function serializeDoc(d) {
  const parts = [];
  (d.blocks || []).forEach((b) => {
    if (b.type === "h") { parts.push(""); parts.push("## " + (b.text || "")); return; }
    parts.push(blockToText(b));
  });
  return parts.join("\n\n").trim() + "\n";
}
function rawEdit() {
  if (!assertEditable()) return;
  const d = S.content;
  const modal = openModal("Режим текста · " + (d.title || d.id) + " (весь раздел сразу)", `
    <p class="hint">Пиши как в Markdown: <code>## Заголовок подраздела</code>, абзацы через пустую строку,
    <code>- список</code>, <code>1. нумерация</code>, <code>- [ ] задача</code>, <code>&gt; врезка</code>,
    <code>\`\`\`код\`\`\`</code>, таблица строками с <code>|</code> (вторая строка — <code>| --- |</code>),
    <code>![подпись](images/…)</code>. Кнопка «Применить» пересобирает блоки раздела.</p>
    <label class="f"><textarea id="rx" style="min-height:56vh"></textarea></label>
    <div class="foot-row"><button class="primary" id="rx-ok">Сохранить во вкладке</button><button class="ghost" id="rx-publish">Сохранить и опубликовать</button>
    <button class="ghost" id="rx-cancel">Отмена</button>
    <span style="flex:1"></span><button class="ghost" id="rx-dl">Скачать .md</button></div>`);
  const ta = $("#rx", modal);
  ta.value = serializeDoc(d);
  const applyRaw = async (publish) => {
    const previous = d.blocks;
    d.blocks = parseBlocks(ta.value);
    if (!markDirty(S.contentFile, d)) { d.blocks = previous; return; }
    closeModal(); renderActiveDoc(); localSavedToast(true, "Текст вкладки");
    if (publish) await pushCurrent();
  };
  $("#rx-ok", modal).onclick = () => applyRaw(false);
  $("#rx-publish", modal).onclick = () => applyRaw(true);
  $("#rx-cancel", modal).onclick = closeModal;
  $("#rx-dl", modal).onclick = () => download((S.contentFile || "doc").replace(/\.json$/, "") + ".md", ta.value, "text/markdown");
  ta.focus(); ta.setSelectionRange(0, 0);
}

/* ----------------------------- boot ---------------------------------------- */
let chromeWired = false;
function wireChrome() {
  if (chromeWired) return; chromeWired = true;
  $("#btn-refresh").onclick = () => refreshAll(); // refresh must never silently discard a local draft
  $("#btn-share").onclick = () => openSettings("access");
  $("#btn-save").onclick = () => pushCurrent();
  $("#btn-edit-tab").onclick = () => openTabComposer();
  $("#btn-settings").onclick = () => openSettings();
  if ($("#btn-token-now")) $("#btn-token-now").onclick = () => openSettings("github");
  $("#btn-dirty-save").onclick = () => pushCurrent();
  $("#btn-dirty-reset").onclick = () => pullCurrent();
  $("#lnk-agent").onclick = (e) => { e.preventDefault(); showDoc("agent", "Инструкция для агента · создание детально проработанных игр на Godot"); };
  $("#lnk-usage").onclick = (e) => { e.preventDefault(); showDoc("usage", "Как пользоваться сайтом"); };
  $("#lnk-inbox").onclick = (e) => { e.preventDefault(); openInbox(); };
  addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") { e.preventDefault(); pushCurrent(); }
    if (e.key === "r" && e.shiftKey && !e.ctrlKey) { e.preventDefault(); refreshAll(); }
  });
  addEventListener("hashchange", () => { readHash(); buildMainTabs(); buildSubtabs(); goTab(); });
}
// earlyBoot() выполняется СРАЗУ при вычислении скрипта (он может приехать с зеркала уже после
// готовности документа), поэтому здесь только флаги и обработчики вкладок — они не требуют,
// чтобы тело страницы было построено целиком. Полностью boot() докрутится на DOMContentLoaded.
function earlyBoot() {
  window.__ZOMBI_BOOTED__ = 1;
  window.__ZOMBI_APP__ = SITE_BUILD;   // флаг для сторожа из index.html: скрипт жив
  window.__ZOMBI_STAMP__ = SITE_BUILD;
  S.base = USER_BASE;                  // адрес зеркала известен ещё до boot()
  // обработчики — ДО стража кэша: даже на переходе «перезагрузиться начисто» клик не должен молчать
  try { wireChrome(); buildMainTabs(); wireDoc(); } catch (e) { /* разметка ещё не готова — повторим в boot() */ }
  if (guardStaleBuild()) return;       // устаревший кэш — уходим на перезагрузку (один раз, ?fresh=1)
}
async function boot() {
  earlyBoot();
  normalizeEditorLink();
  try { wireChrome(); buildMainTabs(); wireDoc(); } catch (e) { /* уже сделано */ }
  try {
    const o = JSON.parse(localStorage.getItem(LS.origin) || "null"); if (o) S.origin = { ...S.origin, ...o };
    S.token = localStorage.getItem(LS.token) || "";
  } catch (e) { /* ignore */ }
  readHash(); buildMainTabs(); updateFoot();
  if (S.base) setTimeout(() => toast("Файлы сайта читаются с зеркала: " + S.base + " (github.io недоступен)", "warn", 9000), 400);
  dismissWatchdog();
  openSite();
  loadConfig().then(() => {
    const cfg = S.config.origin;
    if (cfg && cfg.repo && !localStorage.getItem(LS.origin)) S.origin = { ...S.origin, owner: cfg.owner || S.origin.owner, repo: cfg.repo, branch: cfg.branch || S.origin.branch };
    if (S.config.token || S.config.githubToken) { delete S.config.token; delete S.config.githubToken; }
    updateFoot();
  }).catch(() => {});
  primeStatuses();
  boot2();
}
let booted = false;
async function boot2() {
  if (booted) return; booted = true;
  buildSubtabs();
  setTimeout(() => {
    if (S.docReady) return;
    const d = $("#doc");
    if (!d || d.querySelector(".end-card")) return;
    d.innerHTML = `<div class="end-card">Редактор открыт, но документ не загрузился: <code>content/${esc(fileFor(S.mainTab, S.sub))}</code> не отвечает ни рядом с сайтом, ни через GitHub API.<br>
      Частая причина — браузер держит старый <code>app.js</code> (кэш провайдера) или Pages ещё не пересобрался.
      <div class="end-actions">
        <button class="tiny" id="ec-fresh">Перезагрузить начисто</button>
        <button class="tiny ghost" id="ec-retry">Повторить</button>
        <button class="tiny ghost" id="ec-copy">Скопировать диагностику</button>
      </div></div>`;
    const f = $("#ec-fresh"); if (f) f.onclick = () => { const u = new URL(location.href); u.searchParams.set("fresh", "1"); location.replace(u.href); };
    const r = $("#ec-retry"); if (r) r.onclick = () => { S.cfgOk = false; S.cfgFailed = false; loadConfig().then(() => goTab()); };
    const cp = $("#ec-copy"); if (cp) cp.onclick = () => copyText(siteStatus() + "\nlast err: " + (S.lastErr || "—"));
  }, 6000);
  if (S.mainTab === "preview") await loadPreview(); else await loadCurrent();
  if (localStorage.getItem(LS.refresh) === "1") {
    setInterval(() => { if (!S.dirty.size) loadCurrent(false).catch(() => {}); }, 90000);
  }
}
// скрипт могут подгрузить ПОСЛЕ готовности документа (загрузчик в index.html, зеркало, отложенная вставка) — тогда DOMContentLoaded уже не случится и boot() не запустился бы никогда: именно так выглядели «вкладки не реагируют» при загрузке app.js из зеркала.
earlyBoot();   // флаги и клики — немедленно: скрипт мог подключиться после DOMContentLoaded
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
else boot();
})();
