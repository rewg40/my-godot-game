/* ============================================================================
   ZOMBI · Библия проекта — одностраничный сайт-документация
   Хранение: GitHub Contents API (репозиторий rewg40/my-godot-game)
   Доступ:  код доступа (SHA-256) + токен с правом записи у тех, кого впустили
   Автор:   редактирует в браузере; агент правит те же JSON в репозитории.
   ========================================================================== */
(() => {
"use strict";

/* ----------------------------- константы ---------------------------------- */
const API = "https://api.github.com";
const REPO_DEFAULT = { owner: "rewg40", repo: "my-godot-game", branch: "arena/73c7370f-my-godot-game" };
/* Запас, если config.json не читается (CORS/прокси/офлайн-кэш): вход обязан остаться возможным. */
const FALLBACK_HASHES = ["db258780332270ce4543227fe8cf0ac342d8659305e912ec8320a5d6b904700e"];  // запасной список
const FALLBACK_OWNER_HASH = FALLBACK_HASHES[0];        // владелец: синхронная сверка, сеть не нужна
const MIRRORS = [                                  // где ещё искать config/content
  (o) => `https://rewg40.github.io/my-godot-game/${o}`,
  (o) => `https://cdn.jsdelivr.net/gh/rewg40/my-godot-game@gh-pages/${o}`,
];
const SRC_PREFIX = "game-docs/src";
const MAX_IMG = 1_400_000;      // байт после сжатия
const MAX_MODEL = 24_000_000;  // байт (GitHub limit ~25 МБ на файл)
const LS = { draft: "zombi-docs:draft:", origin: "zombi-docs:origin", token: "zombi-docs:token",
             unlocked: "zombi-docs:unlocked", admin: "zombi-docs:admin", refresh: "zombi-docs:refresh" };

const TABS = [
  { id: "scenario",  label: "Сценарий",           file: "scenario.json" },
  { id: "mechanics", label: "Механика",            file: null },
  { id: "preview",   label: "Картинки / превью",   file: "preview.json" },
];
const MECH = [
  { id: "character",   label: "Персонаж",            file: "mech_character.json" },
  { id: "craft",       label: "Крафт",               file: "mech_craft.json" },
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
];
const STATUS = { draft: "черновик", wip: "в работе", done: "готово", idea: "идея" };

/* ----------------------------- утилиты ------------------------------------ */
const $ = (s, r = document) => r.querySelector(s);
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
const SITE_BUILD = "2026-10-31.7 · inline gate + guest check";
/* Чистый JS-хеш нужен, когда crypto.subtle недоступен: http-прокси, file://,
   старые WebView. Иначе «нет доступа» не из-за кода, а потому что хеш не считается. */
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
async function sha256Hex(str) {
  try {
    if (globalThis.crypto && crypto.subtle && crypto.subtle.digest) {
      const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
      return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
    }
  } catch (e) { /* ниже — JS-фолбэк */ }
  return sha256Pure(str);
}
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
  config: { gate: { enabled: true, ownerCode: "", allowed: [] }, contentPath: SRC_PREFIX + "/content", imagesPath: SRC_PREFIX + "/content/images", modelsPath: SRC_PREFIX + "/content/models", inboxPath: SRC_PREFIX + "/content/agent-inbox", origin: { ...REPO_DEFAULT } },
  origin: { ...REPO_DEFAULT },
  token: "", admin: false, cfgLoaded: false, cfgOk: false, cfgFailed: false, inside: false, mirror: null, readonlyGate: false,
  mainTab: "scenario", mechIndex: MECH.map((m) => m.id), sub: "character",
  content: null, contentFile: null, contentSha: null, contentName: "",
  images: null, models: null, dirty: new Set(),
};
const draftKey = (file) => LS.draft + file;
const hasDraft = (file) => !!localStorage.getItem(draftKey(file));

/* ----------------------------- GitHub API ---------------------------------- */
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
  const sha = await ghGetSha(path);
  const body = { message, content: b64FromBytes(utf8.enc(text)), branch: S.origin.branch };
  if (sha) body.sha = sha;
  return ghFetch(`/contents/${encodeURI(path)}`, { method: "PUT", body: JSON.stringify(body) });
}
async function ghPutBytes(path, bytes, message) {
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
  if (location.protocol === "http:" || location.protocol === "https:") {
    try { return await fetchText(encodeURI(sitePath) + "?v=" + Date.now(), "same-origin", 4000); } catch (e) { /* следующее зеркало */ }
  }
  if (S.mirror != null && MIRRORS[S.mirror]) {
    try { return await fetchText(MIRRORS[S.mirror](sitePath), "cors", 3500); } catch (e) { /* следующее */ }
  }
  for (let i = 0; i < MIRRORS.length; i++) {
    if (i === S.mirror) continue;
    try { const t = await fetchText(MIRRORS[i](sitePath), "cors", 3500); S.mirror = i; return t; } catch (e) { /* следующее */ }
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
      const items = (b.items || []).map((it, i) =>
        `<li><input type="checkbox" data-act="toggle-todo" data-s="${sectIdx}" data-b="${blkIdx}" data-i="${i}" ${it.done ? "checked" : ""}><span>${inline(it.text)}</span></li>`).join("");
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
    ? tool("✎", "edit") + tool("＋", "add-after") + tool("✕", "del")
    : tool("✎", "edit") + tool("↑", "up") + tool("↓", "down") + tool("＋", "add-after") + tool("✕", "del");
  return `<section class="sect" data-s="${sectIdx}">${inner}<div class="sect-tools">${tools}</div></section>`;
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
        <button class="ghost" id="btn-edit-all">✎ Быстрое редактирование</button>
        <button class="ghost" id="btn-add-sect">＋ Раздел</button>
        <button class="ghost" id="btn-json">JSON</button>
      </div>
    </div>`;
  host.appendChild(head);

  if (d._banner) { const b = el("div", "note", d._banner); host.appendChild(b); }
  $("#btn-edit-all", host).onclick = () => rawEdit();
  $("#btn-add-sect", host).onclick = () => addSection(null);
  $("#btn-json", host).onclick = () => jsonView();
  (d.blocks || []).forEach((b, i) => host.insertAdjacentHTML("beforeend", renderBlock(b, i, i)));
  if (!d.blocks || !d.blocks.length) host.insertAdjacentHTML("beforeend", `<div class="end-card">Раздел пуст. Нажми «＋ Раздел» и напиши первое — или попроси агента: «заполни раздел по запросу».</div>`);

  if (d.glossary && d.glossary.length) {
    const g = el("div", "gloss");
    g.innerHTML = `<h3>Глоссарий</h3><dl>${d.glossary.map(([t, v]) => `<dt>${inline(t)}</dt><dd>${inline(v)}</dd>`).join("")}</dl>`;
    host.appendChild(g);
  }
  const end = el("div", "end-card");
  end.innerHTML = `Файл: <code>${esc(S.contentFile || "")}</code> · правки сохраняются в репозиторий (⤒ Ctrl+S), агент читает те же файлы.`;
  host.appendChild(end);
}

/* ----------------------------- блок: текст ⇄ данные ------------------------ */
function blockToText(b) {
  switch (b.type) {
    case "h": return "## " + (b.text || "");
    case "p": return (b.text || []).join("\n\n");
    case "note": return "> " + (b.text || "");
    case "list": return (b.items || []).map((t, i) => (b.ordered ? `${i + 1}. ` : "- ") + t).join("\n");
    case "todo": return (b.items || []).map((t) => `- [${t.done ? "x" : " "}] ${t.text}`).join("\n");
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
        items.push({ text: m[2], done: m[1].toLowerCase() === "x" }); i++;
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
      <button class="primary" id="ed-ok">Применить</button>
      <button class="ghost" id="ed-cancel">Отмена</button>
      <span style="flex:1"></span>
      <button class="ghost" id="ed-del">Удалить блок</button>
    </div>`);
  const ta = $("#ed-text", modal);
  ta.value = blockToText(b);
  $("#ed-type", modal).onchange = (e) => {
    const t = e.target.value;
    if (t !== b.type) ta.value = t === "p" ? (b.items || b.rows ? "" : (b.text || b.code || "")) : "";
  };
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
    d.blocks.splice(idx, 1, ...blocks);
    markDirty(); closeModal(); renderDoc(S.content);
    toast("Блок обновлён. Не забудь ⤒ Ctrl+S — пока правка только у тебя в браузере.", "ok");
  };
  $("#ed-del", modal).onclick = () => {
    if (!confirm("Удалить этот блок?")) return;
    d.blocks.splice(idx, 1); markDirty(); closeModal(); renderDoc(S.content);
  };
  $("#ed-cancel", modal).onclick = closeModal;
}
function addSection(afterIdx) {
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
    d.blocks.splice(afterIdx == null ? d.blocks.length : afterIdx + 1, 0, ...ins);
    markDirty(); closeModal(); renderDoc(d);
    toast("Добавлено.", "ok");
  };
  $("#ns-cancel", modal).onclick = closeModal;
}
function moveBlock(idx, dir) {
  const b = S.content.blocks, j = idx + dir;
  if (j < 0 || j >= b.length) return;
  [b[idx], b[j]] = [b[j], b[idx]];
  markDirty(); renderDoc(S.content);
}
function markDirty() {
  S.dirty.add(S.contentFile);
  localStorage.setItem(draftKey(S.contentFile), JSON.stringify(S.content));
  $("#dirty-bar").hidden = !S.dirty.size;
  renderSubtabs();
}
function jsonView() {
  const modal = openModal("JSON раздела (" + S.contentFile + ")", `
    <label class="f"><textarea id="jv" style="min-height:420px"></textarea></label>
    <div class="foot-row"><button class="primary" id="jv-ok">Применить</button><button class="ghost" id="jv-cc">Скопировать</button><button class="ghost" id="jv-x">Закрыть</button></div>`);
  $("#jv", modal).value = JSON.stringify(S.content, null, 2);
  $("#jv-ok", modal).onclick = () => {
    try { S.content = JSON.parse($("#jv", modal).value); markDirty(); renderDoc(S.content); closeModal(); toast("JSON применён", "ok"); }
    catch (e) { toast("Ошибка JSON: " + esc(e.message), "bad", 6000); }
  };
  $("#jv-cc", modal).onclick = () => { copy($("#jv", modal).value); toast("Скопировано", "ok"); };
  $("#jv-x", modal).onclick = closeModal;
}

/* ----------------------------- модалки ------------------------------------- */
let modalStack = [];
let saveManifests = () => {};
function openModal(title, html, narrow) {
  const root = $("#modal-root");
  root.hidden = false;
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
function closeModal() { $("#modal-root").hidden = true; $("#modal-root").innerHTML = ""; }

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
    let text = localStorage.getItem(draftKey(file));
    let fromDraft = !!text;
    if (!text) text = await loadText("content/" + file);
    const d = JSON.parse(text);
    if (S.mainTab === "mechanics" && d.kind !== "mechanics") d.kind = "mechanics";
    if (fromDraft) d._banner = "Ты видишь свою черновую правку из этого браузера (не сохранена в GitHub).";
    S.content = d; S.contentFile = file;
    if (MECH.some((m) => m.file === file)) { statusCache[file] = d.status; renderSubtabs(); }
    renderDoc(d);
    setPill(fromDraft ? "warn" : "ok", fromDraft ? "черновик в браузере" : "из репозитория");
    updateFoot();
  } catch (e) {
    $("#doc").innerHTML = `<div class="end-card">Не удалось загрузить <code>${esc(file)}</code>: ${esc(e.message)}<br>
      Проверь <b>⚙ Настройки</b> (репозиторий/ветка/токен) или открой сайт из папки <code>game-docs/src/</code> локальным сервером.</div>`;
    setPill("bad", "ошибка загрузки");
  }
}
function setPill(kind, text) { const p = $("#sync-pill"); p.className = "pill " + kind; p.textContent = text; }
function updateFoot() {
  $("#foot-info").textContent = `${S.origin.owner}/${S.origin.repo} · ${S.origin.branch} · ${S.token ? "запись разрешена" : "только чтение"}`;
  $("#readonly-bar").hidden = !!S.token;
  if (S.readonlyGate) {
    const bar = $("#readonly-bar");
    bar.hidden = false;
    bar.innerHTML = "Ты внутри без проверки конфига репозитория (сеть до config.json недоступна) — чтение открыто, запись отключена. "
      + '<button class="tiny" id="ro-retry">повторить</button>';
    const b = $("#ro-retry", bar); if (b) b.onclick = () => { S.cfgOk = false; refreshAll().then(() => { S.readonlyGate = !S.cfgOk; updateFoot(); }); };
  }
}

/* ----------------------------- навигация ----------------------------------- */
function buildMainTabs() {
  $$("#main-tabs .tab-btn").forEach((b) => {
    b.classList.toggle("active", b.dataset.tab === S.mainTab);
    b.onclick = () => { S.mainTab = b.dataset.tab; $("#subtabs").hidden = S.mainTab !== "mechanics"; buildMainTabs(); buildSubtabs(); syncHash(); goTab(); };
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
  host.insertAdjacentHTML("beforeend", `<span class="subtab-note">${MECH.length} разделов: 10 из твоего списка + «Физика» + 2 технических (3D-ассеты, аудио/UI/структура)</span>`);
}
const statusCache = {};
function statusOf(m) {
  const key = m.file;
  const dr = JSON.parse(localStorage.getItem(draftKey("content/" + key)) || "null");
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
  history.replaceState(null, "", h);
}
function readHash() {
  const h = location.hash.replace(/^#/, "");
  if (!h) return;
  if (h.startsWith("mechanics/")) { S.mainTab = "mechanics"; S.sub = h.split("/")[1] || S.sub; }
  else if (TABS.some((t) => t.id === h)) S.mainTab = h;
}

/* ----------------------------- депозит: правки в GitHub -------------------- */
async function pushCurrent(silent) {
  if (!S.token) { toast("Нужен токен GitHub с правом записи — ⚙ Настройки", "bad"); openSettings("github"); return; }
  const file = S.contentFile, d = S.content;
  if (!file) return;
  setPill("", "отправка…");
  try {
    d.updated = nowIso();
    const path = `${S.config.contentPath}/${file}`;
    await ghPutText(path, JSON.stringify(d, null, 2) + "\n", `docs(${file.replace(/\.json$/, "")}): правка через сайт`);
    localStorage.removeItem(draftKey(file));
    S.dirty.delete(file);
    $("#dirty-bar").hidden = !!S.dirty.size;
    setPill("ok", "сохранено");
    if (!silent) toast("Закоммичено в " + S.origin.branch + ". Через ~1 минуту обновится на GitHub Pages.", "ok");
    renderDoc(d);
  } catch (e) {
    setPill("bad", "ошибка записи");
    toast("GitHub: " + esc(e.message), "bad", 8000);
  }
}
async function pullCurrent() {
  const file = S.contentFile;
  localStorage.removeItem(draftKey(file));
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
  const modal = openModal("Настройки сайта · доступ, репозиторий, синхронизация", `
    <div class="tabs-mini">
      <button data-m="github" class="on">GitHub</button>
      <button data-m="access">Доступ</button>
      <button data-m="sync">Синхронизация</button>
    </div>
    <div id="st-github">
      <label class="f"><span>Владелец</span><input id="st-owner" value="${esc(S.origin.owner)}"></label>
      <label class="f"><span>Репозиторий</span><input id="st-repo" value="${esc(S.origin.repo)}"></label>
      <label class="f"><span>Ветка (куда пишем / откуда читаем)</span><input id="st-branch" value="${esc(S.origin.branch)}"></label>
      <label class="f"><span>Токен GitHub <b>repo</b> (или fine-grained: Contents Read&Write)</span>
        <input id="st-token" type="password" placeholder="ghp_... / github_pat_..." value="${esc(S.token)}"></label>
      <p class="hint">Токен хранится <b>только в этом браузере</b> (localStorage) и уходит напрямую на api.github.com.
      Кто имеет токен — тот и пишет. У кого нет — тот читает то, что уже на GitHub Pages.</p>
      <div class="foot-row"><button class="primary" id="st-save-gh">Сохранить и проверить</button>
      <a class="ghost" style="text-decoration:none" target="_blank" href="https://github.com/settings/tokens/new?scopes=repo&description=ZOMBI%20docs">Создать токен</a></div>
    </div>
    <div id="st-access" hidden>
      <p class="hint">Замок включается файлом <code>${SRC_PREFIX}/config.json</code> в репозитории: <code>gate.enabled</code> + список кодов.
      Коды хранятся как SHA-256, поэтому их нельзя подсмотреть из исходников сайта. Полный контроль — у владельца кода из <code>ownerCode</code>.</p>
      <label class="f"><input type="checkbox" id="st-gate" ${S.config.gate.enabled ? "checked" : ""}> Требуется код доступа</label>
      <label class="f"><span>Сгенерировать новый код</span>
        <div style="display:flex;gap:8px"><input id="st-newcode" readonly placeholder="нажми «Сгенерировать»"><button class="ghost" id="st-gen">Сгенерировать</button></div></label>
      <label class="f"><span>Разрешённые коды (SHA-256, по одному в строке)</span>
        <textarea id="st-allowed" spellcheck="false" placeholder="db258780332270ce...">${esc((S.config.gate.allowed || []).join("\n"))}</textarea></label>
      <label class="f"><span>Код владельца (тоже SHA-256)</span><input id="st-ownercode" value="${esc(S.config.gate.ownerCode || "")}"></label>
      <div class="foot-row"><button class="primary" id="st-save-access">Отправить config.json в репозиторий</button>
      <button class="ghost" id="st-dl">Скачать config.json</button></div>
      ${S.admin ? "" : `<p class="hint">Чтобы менять список, нужен режим владельца: войди по коду владельца.</p>`}
    </div>
    <div id="st-sync" hidden>
      <label class="f"><input type="checkbox" id="st-auto" ${localStorage.getItem(LS.refresh) === "1" ? "checked" : ""}> Автообновление каждые 90 с (когда нет несохранённых правок)</label>
      <div class="foot-row"><button class="ghost" id="st-pull-now">Подтянуть всё сейчас</button></div>
      <p class="hint">После коммита в ветку <code>${esc(S.origin.branch)}</code> GitHub Actions пересобирает сайт на Pages (~40–90 с). Кнопка «⤒ Сохранить в GitHub» пишет в ту же ветку, что и агент.</p>
    </div>`);
  const show = (t) => { ["github", "access", "sync"].forEach((k) => { $("#st-" + k, modal).hidden = k !== t; }); $$(".tabs-mini button", modal).forEach((b) => b.classList.toggle("on", b.dataset.m === t)); };
  $$(".tabs-mini button", modal).forEach((b) => b.onclick = () => show(b.dataset.m));
  if (tab) show(tab);

  $("#st-gen", modal).onclick = async () => {
    const raw = "ZOMBI-" + Math.random().toString(36).slice(2, 8).toUpperCase();
    $("#st-newcode", modal).value = raw;
    const hash = await sha256Hex(raw);
    $("#st-allowed", modal).value = ($("#st-allowed", modal).value.trim() + "\n" + hash).trim();
    copy(raw);
    toast("Код: <b>" + raw + "</b> (скопирован). Не забудь отправить config.json — иначе код не заработает.", "warn", 12000);
  };
  $("#st-save-gh", modal).onclick = async () => {
    S.origin = { owner: $("#st-owner", modal).value.trim(), repo: $("#st-repo", modal).value.trim(), branch: $("#st-branch", modal).value.trim() };
    S.token = $("#st-token", modal).value.trim();
    localStorage.setItem(LS.origin, JSON.stringify(S.origin));
    localStorage.setItem(LS.token, S.token);
    updateFoot();
    try {
      const me = await ghFetch("");
      toast("Подключено: " + esc(me.full_name) + " (ветки: " + (await ghFetch("/branches")).length + ")", "ok", 6000);
      setPill("ok", "github ok");
      closeModal(); loadCurrent();
    } catch (e) { toast("Проверка: " + esc(e.message), e.status === 401 ? "bad" : "warn", 8000); }
  };
  $("#st-save-access", modal).onclick = async () => {
    const cfg = { ...S.config, gate: { enabled: $("#st-gate", modal).checked, ownerCode: $("#st-ownercode", modal).value.trim(), allowed: $("#st-allowed", modal).value.split("\n").map((s) => s.trim()).filter(Boolean) } };
    try {
      await ghPutText(`${SRC_PREFIX}/config.json`, JSON.stringify(cfg, null, 2) + "\n", "docs(gate): обновление кодов доступа");
      S.config = cfg; toast("config.json отправлен в репозиторий", "ok"); closeModal();
    } catch (e) { toast("Не вышло: " + esc(e.message), "bad", 8000); }
  };
  $("#st-dl", modal).onclick = () => {
    const cfg = { ...S.config, gate: { enabled: $("#st-gate", modal).checked, ownerCode: $("#st-ownercode", modal).value.trim(), allowed: $("#st-allowed", modal).value.split("\n").map((s) => s.trim()).filter(Boolean) } };
    download("config.json", JSON.stringify(cfg, null, 2), "application/json");
  };
  $("#st-auto", modal).onchange = (e) => localStorage.setItem(LS.refresh, e.target.checked ? "1" : "0");
  $("#st-pull-now", modal).onclick = () => { closeModal(); refreshAll(); };
}
function download(name, text, mime) {
  const a = el("a"); a.href = URL.createObjectURL(new Blob([text], { type: mime || "text/plain" })); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

/* ----------------------------- доступ (замок) ------------------------------ */
async function loadConfig() {
  let raw = null;
  try { raw = await loadText("config.json"); S.cfgOk = true; S.cfgFailed = false; }
  catch (e) { S.cfgOk = false; S.cfgFailed = true; }
  if (raw) { try { S.config = { ...S.config, ...JSON.parse(raw), gate: { ...S.config.gate, ...(JSON.parse(raw).gate || {}) } }; } catch (e) { /* ignore */ } }
  S.cfgLoaded = true;
  const host = location.hostname || "";
  if (host.endsWith(".github.io")) {
    const owner = host.split(".")[0];
    const repo = (location.pathname.split("/")[1] || "").replace(/\.html$/, "");
    if (owner && repo) {
      S.origin = { owner, repo, branch: (S.config.origin && S.config.origin.branch) || REPO_DEFAULT.branch };
    }
  }
}
/* Проверка кода НЕ должна ничего качать: сеть в России у github.io живёт своей жизнью.
   Шаги: (1) синхронно сверяем хеш с константой в app.js → пуск; (2) если есть config.json —
   сверяемся с ним (это право записи); (3) если config не прочитан — пускаем на чтение. */
async function tryUnlock(raw, quiet) {
  const code = String(raw == null ? "" : raw).trim().normalize("NFC");
  if (!code) { gateMsg("Пусто. Введи код доступа (регистр важен, пробелы можно убрать).", true); return false; }
  let h = "";
  try { h = String(await sha256Hex(code)).toLowerCase(); }
  catch (e) { gateMsg("Хеш не вычисляется: " + ((e && e.message) || e) + " — обнови страницу по https:// (Ctrl+F5).", true); return false; }
  if (h.length !== 64) { gateMsg("Хеш неполный (" + h.length + " симв.) — скрипт устарел, обнови Ctrl+F5.", true); return false; }
  const g = S.config.gate || {};
  const owner = String(g.ownerCode || "").toLowerCase();
  const cfgList = (g.allowed || []).map((x) => String(x).toLowerCase()).filter(Boolean);
  const inside = (admin) => {
    try { localStorage.setItem(LS.unlocked, h); localStorage.setItem(LS.admin, admin ? "1" : "0"); } catch (e) { /* private mode */ }
    S.admin = admin; gateMsg("", false);
  };
  if (h === FALLBACK_OWNER_HASH) {                       // владелец — всегда, даже без сети
    inside(true);
    if (owner && owner !== h) gateMsg("Код владельца в config.json отличается от встроенного — обнови конфиг.", false);
    S.readonlyGate = !S.cfgOk && !S.cfgLoaded;
    return true;
  }
  if (S.cfgOk) {                                          // конфиг прочитан: решают списки из него
    if (owner && h === owner) { inside(true); return true; }
    if (cfgList.includes(h)) { inside(false); return true; }
    if (!quiet) gateMsg("Код не подходит. Хеш введённого: " + h.slice(0, 12)
      + "… — такой строки нет в config.json (владелец + " + cfgList.length + " гостевых).", true);
    return false;
  }
  S.readonlyGate = true;                                  // сети нет — только чтение, но вход есть
  gateMsg("config.json сейчас не читается — пускаю на чтение. Для записи дождись сети и нажми «⟳ Перепроверить конфиг».", false);
  return true;
}
function gateStatus() {
  const g = S.config.gate || {};
  return [
    "site " + SITE_BUILD,
    "href " + location.href.slice(0, 120),
    "config " + (S.cfgOk ? "ok (владелец + " + ((g.allowed || []).length) + " гостей)" : "не загружен"),
    "mirror " + (S.mirror == null ? "нет" : S.mirror),
    "origin " + S.origin.owner + "/" + S.origin.repo + "@" + S.origin.branch,
    "token " + (S.token ? "есть" : "нет"),
    "inside " + (S.inside ? "да" : "нет") + ", admin " + (S.admin ? "да" : "нет"),
    "webcrypto " + (window.crypto && crypto.subtle ? "да" : "нет (использую JS-хеш)"),
    "storage " + (() => { try { localStorage.setItem("zombi-probe", "1"); localStorage.removeItem("zombi-probe"); return "работает"; } catch (e) { return "заблокирован"; } })(),
  ].join("\n");
}
function gateMsg(text, isError) {
  const m = document.getElementById("gate-msg");
  if (!m) return;
  m.textContent = text || "";
  m.hidden = !text;
  m.style.color = isError ? "var(--bad)" : "var(--tx3)";
  m.title = "Нажми, чтобы открыть диагностику для агента";
  m.onclick = showGateStatus;
}
function showGateStatus() {
  const txt = gateStatus();
  openModal("Диагностика замка", `<p class="muted">Скопируй это и отправь агенту — по этим строкам причина ясна за 10 секунд.</p>
    <textarea id="dg-out" readonly style="width:100%;min-height:190px;font-family:var(--mono);font-size:12px">${esc(txt)}</textarea>
    <div style="display:flex;gap:8px;margin-top:8px"><button id="dg-copy">Скопировать</button><button class="ghost" id="dg-reload">Перезагрузить страницу</button></div>`, true);
  $("#dg-copy").onclick = () => {
    const ta = $("#dg-out"); ta.select(); ta.focus();
    let ok = false; try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    if (!ok && navigator.clipboard) navigator.clipboard.writeText(txt).then(() => toast("Скопировано", "ok", 2000), () => toast("Скопируй вручную: Ctrl+C", "warn", 5000));
    else toast(ok ? "Скопировано" : "Скопируй вручную: Ctrl+C", ok ? "ok" : "warn", 3500);
  };
  $("#dg-reload").onclick = () => location.reload();
}
function openSite() {
  const g = document.getElementById("gate"), a = document.getElementById("app");
  if (g) g.hidden = true;
  if (a) a.hidden = false;
  S.inside = true;
  const ld = document.getElementById("gate-loader");
  if (ld) ld.textContent = "app.js живой · " + SITE_BUILD;
  return true;
}
window.zombiOpenSite = openSite;   // встроенный в index.html замок пользуется этим, чтобы не пло логику
/* Если браузер притащил app.js другой версии (кэш провайдера / Pages max-age=600) —
   один раз принудительно перезагружаемся с ?fresh=1, чтобы вытащить свежий файл. */
function guardStaleBuild() {
  const LS_BUILD = "zombi-docs:build";
  let prev = null;
  try { prev = localStorage.getItem(LS_BUILD); } catch (e) { return false; }
  try { localStorage.setItem(LS_BUILD, SITE_BUILD); } catch (e) {}
  if (prev && prev !== SITE_BUILD && !location.search.includes("fresh=1")) {
    try {
      const u = new URL(location.href);
      u.searchParams.set("fresh", "1");
      location.replace(u.href);
      return true;
    } catch (e) { return false; }
  }
  return false;
}
function wireGate() {
  const g = S.config.gate || {};
  // замок включаем по умолчанию только если конфиг реально не удалось прочитать;
  // «ещё не дочитался» — не повод светить контент
  const fb = document.getElementById("gate-fallback");
  if (fb) fb.innerHTML = "код принят · код проверяется в браузере, сеть для входа не нужна · «Сбросить кэш» перезакачает app.js/app.css";
  const gateOn = S.cfgFailed ? true : (g.enabled !== false);
  const badge = document.getElementById("gate-build");
  if (badge) { badge.textContent = "site " + SITE_BUILD + " · " + (S.cfgOk
    ? ("config: " + ((g.allowed || []).length ? g.allowed.length + " доп. код(ов) + владелец" : "только код владельца"))
    : "config не загружен (сеть) — вход по встроенному коду владельца, только чтение");
    badge.onclick = showGateStatus; badge.style.cursor = "pointer"; badge.title = "Показать диагностику"; }
  const local = ["localhost", "127.0.0.1", ""].includes(location.hostname);
  const forceOpen = new URLSearchParams(location.search).has("open") || location.hash.includes("open=1");
  if (forceOpen) S.readonlyGate = true;
  if (forceOpen || !gateOn || localStorage.getItem("zombi-docs:demomode") === "1") { return openSite(); }
  let saved = null;
  try { saved = localStorage.getItem(LS.unlocked); } catch (e) { /* ignore */ }
  const all = [...(g.allowed || []), g.ownerCode || "", ...FALLBACK_HASHES].map((x) => String(x).toLowerCase()).filter(Boolean);
  if (saved && all.includes(saved)) { S.admin = localStorage.getItem(LS.admin) === "1"; return openSite(); }
  $("#gate").hidden = false; $("#app").hidden = true;
  const dm = document.getElementById("gate-demo");
  if (dm) {
    dm.hidden = !local;                                   // «демо» показываем только на локальном предпросмотре
    dm.onclick = () => { try { localStorage.setItem("zombi-docs:demomode", "1"); } catch (e) {}
      openSite(); boot2(); toast("Демо-режим: замок отключён только в этом браузере.", "warn", 5000); };
  }
  const eye = document.getElementById("gate-eye");
  if (eye) eye.onclick = () => { const i = $("#gate-code"); i.type = i.type === "password" ? "text" : "password"; eye.textContent = i.type === "password" ? "👁" : "🙈"; };
  $("#gate-form").onsubmit = async (e) => {
    e.preventDefault();
    if (window.__ZOMBI_INLINE_GATE__) return;   // пока config не прочитан, решает встроенный замок (он умеет фолбэк)
    const btn = e.target.querySelector("button[type=submit]");
    if (btn) btn.disabled = true;
    gateMsg("Проверяю…", false);
    let ok = false;
    try { ok = await tryUnlock($("#gate-code").value); }
    catch (err) { gateMsg("Ошибка проверки кода: " + err.message, true); }
    if (btn) btn.disabled = false;
    if (ok) { openSite(); boot2(); }
  };
  const auto = (location.hash.match(/[#&]code=([^&]+)/) || [])[1];
  if (auto) { $("#gate-code").value = decodeURIComponent(auto); setTimeout(() => { const f = $("#gate-form"); if (f.requestSubmit) f.requestSubmit(); else f.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); }, 250); }
  const retry = document.getElementById("gate-retry");
  if (retry) retry.onclick = async () => {
    retry.disabled = true; gateMsg("Перечитываю config.json…", false);
    S.cfgOk = false;
    try { await loadConfig(); } catch (e) { /* ignore */ }
    retry.disabled = false;
    wireGate();
    if (!S.cfgOk) gateMsg("Конфиг всё ещё недоступен. Вход по запасному коду владельца работает; гостевые коды — когда появится сеть до github.com.", true);
  };
  if (!S.cfgOk) setTimeout(() => { const f = $("#gate-form"); if (!$("#gate").hidden && f && f.checkValidity()) { const i = $("#gate-code"); if (i && !i.value) i.focus(); } }, 8000);
  setTimeout(() => { const i = $("#gate-code"); if (i) i.focus(); }, 150);
}

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
      <button class="primary" id="p-add-img">＋ Картинка</button></div>`;
  const grid = el("div", "prev-grid");
  S.images.items.forEach((it, i) => grid.appendChild(imgCard(it, i)));
  const add = el("button", "card add-card", "＋ добавить картинку"); add.onclick = () => addImageUI();
  grid.appendChild(add);
  box.appendChild(grid);

  box.insertAdjacentHTML("beforeend", `<div class="h3row"><h2>3D-модели · ${S.models.items.length}</h2><span class="spacer"></span>
      <button class="primary" id="p-add-md">＋ 3D-модель</button></div>`);
  const g2 = el("div", "prev-grid");
  S.models.items.forEach((it, i) => g2.appendChild(modelCard(it, i)));
  g2.appendChild(el("button", "card add-card", "＋ добавить модель"));
  g2.lastChild.onclick = () => addModelUI();
  box.appendChild(g2);

  box.insertAdjacentHTML("beforeend", `<div class="h3row"><h2>Куда смотреть дальше</h2></div>
    <div class="note">Архивы в корне репозитория (<code>ZOMBI.7z.*</code>, <code>остров 1.7z.*</code>, <code>персонаж 1.7z.*</code>) — это, судя по всему, исходники проекта. Скажи агенту: «распакуй и разложи превью по вкладке „Картинки / превью“» — он распакует, отрежет превьюшки, зальёт в <code>game-docs/src/content/images/</code> и обновит реестр.</div>`);
  host.appendChild(box);
  $("#p-add-img", host).onclick = () => addImageUI();
  $("#p-add-md", host).onclick = () => addModelUI();
}
function imgCard(it, i) {
  const c = el("div", "card");
  const src = resolveAsset(it.file);
  c.innerHTML = `<div class="thumb"><img src="${esc(src)}" alt="${esc(it.name)}" loading="lazy" onerror="this.parentNode.innerHTML='⚠️ нет файла'"></div>
    <div class="body"><b>${esc(it.name)}</b><p>${esc(it.caption || "")}</p>
    <div class="tags">${(it.tags || []).map((t) => `<span>${esc(t)}</span>`).join("")}${it.tab ? `<span>→ ${esc(it.tab)}</span>` : ""}</div>
    <div class="row"><a class="tiny" style="text-decoration:none" target="_blank" href="${esc(src)}">открыть</a>
    <button class="tiny" data-x="${i}" data-kind="img">в реестр ✕</button></div></div>`;
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
    <button class="tiny" data-x>убрать ✕</button></div></div>`;
  $("[data-view]", c).onclick = () => view3D(it.file, it.name);
  $("[data-x]", c).onclick = () => { S.models.items.splice(i, 1); localStorage.setItem("zombi-docs:models", JSON.stringify(S.models)); loadPreview(); };
  return c;
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
function wireDoc() {
  $("#doc").addEventListener("click", (e) => {
    const b = e.target.closest("[data-act]");
    if (!b) return;
    const s = +b.dataset.s, act = b.dataset.act;
    if (act === "edit") editSection(findBlockIndex(s));
    if (act === "add-after") addSection(findBlockIndex(s));
    if (act === "del") { if (confirm("Удалить блок?")) { S.content.blocks.splice(findBlockIndex(s), 1); markDirty(); renderDoc(S.content); } }
    if (act === "up") moveBlock(findBlockIndex(s), -1);
    if (act === "down") moveBlock(findBlockIndex(s), 1);
  });
  $("#doc").addEventListener("change", (e) => {
    const b = e.target.closest("[data-act='toggle-todo']");
    if (!b) return;
    const s = findBlockIndex(+b.dataset.s);
    const it = S.content.blocks[s].items[+b.dataset.i];
    it.done = e.target.checked;
    if (!e.target.closest(".sect") && !S.token) { localStorage.setItem(draftKey(S.contentFile), JSON.stringify(S.content)); return; }
    markDirty(); renderDoc(S.content);
    if (S.token) pushCurrent(true);
  });
  // (кнопки шапки навешаны в renderDoc)
  // «Быстрое редактирование» = raw-режим всего раздела
  $("#doc").addEventListener("dblclick", (e) => {
    const sec = e.target.closest(".sect");
    if (sec) editSection(findBlockIndex(+sec.dataset.s));
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
  const d = S.content;
  const modal = openModal("Режим текста · " + (d.title || d.id) + " (весь раздел сразу)", `
    <p class="hint">Пиши как в Markdown: <code>## Заголовок подраздела</code>, абзацы через пустую строку,
    <code>- список</code>, <code>1. нумерация</code>, <code>- [ ] задача</code>, <code>&gt; врезка</code>,
    <code>\`\`\`код\`\`\`</code>, таблица строками с <code>|</code> (вторая строка — <code>| --- |</code>),
    <code>![подпись](images/…)</code>. Кнопка «Применить» пересобирает блоки раздела.</p>
    <label class="f"><textarea id="rx" style="min-height:56vh"></textarea></label>
    <div class="foot-row"><button class="primary" id="rx-ok">Применить</button>
    <button class="ghost" id="rx-cancel">Отмена</button>
    <span style="flex:1"></span><button class="ghost" id="rx-dl">Скачать .md</button></div>`);
  const ta = $("#rx", modal);
  ta.value = serializeDoc(d);
  $("#rx-ok", modal).onclick = () => {
    const blocks = parseBlocks(ta.value);
    d.blocks = blocks;
    markDirty(); closeModal(); renderDoc(d);
    toast("Раздел пересобран из текста. Ctrl+S — отправить в репозиторий.", "ok", 5000);
  };
  $("#rx-cancel", modal).onclick = closeModal;
  $("#rx-dl", modal).onclick = () => download((S.contentFile || "doc").replace(/\.json$/, "") + ".md", ta.value, "text/markdown");
  ta.focus(); ta.setSelectionRange(0, 0);
}

/* ----------------------------- boot ---------------------------------------- */
function wireChrome() {
  $("#btn-refresh").onclick = () => { localStorage.removeItem(draftKey(S.contentFile)); refreshAll(); };
  $("#btn-save").onclick = () => pushCurrent();
  $("#btn-settings").onclick = () => openSettings();
  $("#btn-token-now").onclick = () => openSettings("github");
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
async function boot() {
  window.__ZOMBI_BOOTED__ = 1;
  const ig = window.__ZOMBI_GATE__;        // замок уже прошёл встроенный скрипт в index.html
  if (ig && ig.unlockedBy) { S.admin = !!ig.admin; S.readonlyGate = !!ig.readonly; }
  if (!(ig && ig.unlockedBy) && guardStaleBuild()) return;   // устаревший кэш — перезагрузимся
  try {
    const o = JSON.parse(localStorage.getItem(LS.origin) || "null"); if (o) S.origin = { ...S.origin, ...o };
    S.token = localStorage.getItem(LS.token) || "";
  } catch (e) { /* ignore */ }
  wireGate();                        // замок сразу: проверка кода не зависит от сети
  const cfgP = loadConfig().catch(() => {});
  const cfg = S.config.origin;
  if (cfg && cfg.repo && !localStorage.getItem(LS.origin)) S.origin = { ...S.origin, owner: cfg.owner || S.origin.owner, repo: cfg.repo, branch: cfg.branch || S.origin.branch };
  if (S.config.token || S.config.githubToken) { delete S.config.token; delete S.config.githubToken; }  // на всякий случай: токены в репо не хранятся
  wireChrome();
  readHash();
  buildMainTabs();
  wireDoc();
  updateFoot();
  primeStatuses();
  if (ig && ig.unlockedBy) { openSite(); boot2(); return; }   // не держим замок, который уже открыт
  const open = !!S.inside;                  // решение замка, а не состояние DOM
  cfgP.then(async () => {
    updateFoot();
    if (S.inside) return;                            // уже внутри — не мешаем
    const v = $("#gate-code") ? String($("#gate-code").value).trim() : "";
    if (!v) { wireGate(); return; }                       // сам не вмешиваемся, пока поля пустые
    if (await tryUnlock(v, true)) { openSite(); boot2(); }
    else wireGate();
  });
  if (!open) return;   // ждём код
  boot2();
}
let booted = false;
async function boot2() {
  if (booted) return; booted = true;
  buildSubtabs();
  if (S.mainTab === "preview") await loadPreview(); else await loadCurrent();
  if (localStorage.getItem(LS.refresh) === "1") {
    setInterval(() => { if (!S.dirty.size) loadCurrent(false).catch(() => {}); }, 90000);
  }
}
document.addEventListener("DOMContentLoaded", boot);
})();
