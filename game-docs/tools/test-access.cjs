"use strict";
// Browser-level regression tests. All network calls are intercepted: tests never
// read credentials from the environment or write anything to the real repository.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { webcrypto } = require("node:crypto");
const { JSDOM, VirtualConsole } = require("jsdom");

const SRC = path.join(__dirname, "..", "src");
const BASE = "https://rewg40.github.io/my-godot-game/";
const BRANCH = "arena/d4678daa-my-godot-game";
const TOKEN = "test-only-NOT-A-REAL-TOKEN";
const config = JSON.parse(fs.readFileSync(path.join(SRC, "config.json"), "utf8"));
const html = fs.readFileSync(path.join(SRC, "index.html"), "utf8");
const app = fs.readFileSync(path.join(SRC, "app.js"), "utf8");
const gateStart = html.indexOf("<!-- INLINE-GATE:START -->");
const gateEnd = html.indexOf("<!-- INLINE-GATE:END -->");
const gateScript = html.slice(html.indexOf("<script>", gateStart) + 8, html.indexOf("</script>", gateStart));
assert.ok(gateEnd > gateStart);

const fileForHash = (hash) => hash.startsWith("#mechanics/") ? "mech_" + (hash.split("/")[1] || "character") + ".json" : hash === "#preview" ? "preview.json" : "scenario.json";
const wait = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(predicate, label, timeout = 2500) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (predicate()) return;
    await wait(10);
  }
  assert.fail("Timed out: " + (typeof label === "function" ? label() : label));
}
function reply(data, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 401 ? "Unauthorized" : "Mock response",
    headers: { get: () => "application/json" },
    json: async () => typeof data === "string" ? JSON.parse(data) : data,
    text: async () => typeof data === "string" ? data : JSON.stringify(data),
  };
}

async function makePage(t, options = {}) {
  const url = new URL(options.url || BASE);
  const errors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on("jsdomError", (error) => errors.push(error.message));
  virtualConsole.on("error", (...args) => errors.push(args.map(String).join(" ")));
  const dom = new JSDOM(html, { url: url.href, runScripts: "outside-only", pretendToBeVisual: true, virtualConsole });
  const { window } = dom;
  const doc = window.document;
  const calls = [];
  const copied = [];
  let writes = 0;
  let pending = 0;
  const owner = options.owner !== false;
  window.localStorage.setItem("zombi-docs:token", options.token === undefined ? TOKEN : options.token);
  if (owner) {
    window.localStorage.setItem("zombi-docs:unlocked", config.gate.ownerCode);
    window.localStorage.setItem("zombi-docs:admin", "1");
  }
  if (options.draft) window.localStorage.setItem("zombi-docs:draft:" + (options.draftFile || fileForHash(url.hash)), JSON.stringify(options.draft));
  if (options.storageFail) {
    const proto = Object.getPrototypeOf(window.localStorage);
    const original = proto.setItem;
    proto.setItem = function (key, value) {
      if (String(key).startsWith("zombi-docs:draft:")) throw new window.DOMException("Mock storage quota", "QuotaExceededError");
      return original.call(this, key, value);
    };
    t.after(() => { proto.setItem = original; });
  }
  Object.defineProperty(window, "crypto", { value: webcrypto, configurable: true });
  window.TextEncoder = TextEncoder;
  window.TextDecoder = TextDecoder;
  Object.defineProperty(window.navigator, "clipboard", { configurable: true, value: { writeText: async (text) => { copied.push(text); } } });
  doc.execCommand = () => false;
  window.fetch = async (input, init = {}) => {
    pending++;
    try {
    const href = new URL(String(input), url.href).href;
    const parsed = new URL(href);
    const method = (init.method || "GET").toUpperCase();
    const headers = init.headers || {};
    calls.push({ href, method, headers, body: init.body });
    if (method !== "GET") writes++;
    if (parsed.hostname === "api.github.com") {
      if (options.api401 && (method === "PUT" || options.api401 === "all")) return reply({ message: "Requires authentication" }, 401);
      if (parsed.pathname.endsWith("/contents/game-docs/src/config.json")) {
        if (options.configFails) return reply({ message: "Mock config outage" }, 503);
        if (method === "PUT") return reply({ commit: { sha: "mock-commit" } });
        return reply({ sha: "mock-config-sha" });
      }
      if (/\/branches\//.test(parsed.pathname)) return reply({ name: BRANCH });
      if (/\/contents\/game-docs\/src\/content\/agent-inbox\/.+\.md$/.test(parsed.pathname)) {
        if (method === "PUT") return reply({ commit: { sha: "mock-inbox-commit" }, content: { sha: "mock-inbox-sha" } });
        return reply([]);
      }
      if (/\/contents\/game-docs\/src\/content\/.+\.json$/.test(parsed.pathname)) {
        if (method === "PUT") {
          if (options.contentPutStatus) return reply({ message: "Mock content write failure" }, options.contentPutStatus);
          return reply({ commit: { sha: "mock-content-commit" }, content: { sha: "mock-content-new-sha" } });
        }
        return reply({ sha: "mock-content-sha" });
      }
      return reply({ full_name: "rewg40/my-godot-game", permissions: { push: true, pull: true } });
    }
    if (parsed.origin === url.origin) {
      const relative = decodeURIComponent(parsed.pathname.replace(/^\/my-godot-game\//, ""));
      if (relative === "config.json" && options.configFails) return reply({ message: "Mock config outage" }, 503);
      const file = path.resolve(SRC, relative);
      if (file.startsWith(SRC + path.sep) && fs.existsSync(file) && fs.statSync(file).isFile()) {
        return reply(fs.readFileSync(file, "utf8"));
      }
    }
    return reply({ message: "External network disabled in test" }, 503);
    } finally { pending--; }
  };
  t.after(() => window.close());
  if (doc.readyState === "loading") {
    await new Promise((resolve) => doc.addEventListener("DOMContentLoaded", resolve, { once: true }));
  }
  // Execute the actual inline gate and app, not the external mirror loader.
  window.eval(gateScript);
  window.addEventListener("unhandledrejection", (e) => errors.push("unhandled: " + (e.reason?.stack || e.reason)));
  window.eval(app);
  const expectedTitle = (file) => JSON.parse(fs.readFileSync(path.join(SRC, "content", file), "utf8")).title;
  const initialFile = fileForHash(url.hash);
  await until(() => doc.querySelector("#doc h1")?.textContent === expectedTitle(initialFile),
    () => "initial document loaded: " + JSON.stringify({ title: doc.querySelector("#doc h1")?.textContent, expected: expectedTitle(initialFile), doc: doc.querySelector("#doc").textContent.slice(0, 250), errors }));
  await until(() => doc.querySelector("#foot-info").textContent.includes(BRANCH), "config loaded");
  await until(() => pending === 0, "background loads settle");
  assert.deepEqual(errors, [], "no browser runtime errors");
  return { window, doc, calls, copied, errors, get writes() { return writes; }, expectedTitle,
    apiCalls: () => calls.filter((c) => new URL(c.href).hostname === "api.github.com"),
    click: (selector) => { const node = doc.querySelector(selector); assert.ok(node, selector); node.click(); },
  };
}

function openAccess(p) {
  p.click("#btn-share");
  assert.equal(p.doc.querySelector("#st-access").hidden, false);
  return p.doc.querySelector("#st-view-link").value;
}

test("owner can create and copy a section link without a GitHub API request", async (t) => {
  const p = await makePage(t, { url: BASE + "?token=do-not-share&code=do-not-share#mechanics/assets" });
  const before = p.apiCalls().length;
  const link = openAccess(p);
  assert.equal(link, BASE + "?open=1#mechanics/assets");
  assert.equal(p.doc.querySelector("#st-open-view").getAttribute("href"), link);
  p.click("#st-copy-view");
  await until(() => p.copied.includes(link), "share link copied");
  assert.equal(p.apiCalls().length, before, "sharing must not call GitHub API");
  assert.equal(p.writes, 0);
  assert.ok(!link.includes(TOKEN) && !link.includes("do-not-share"));
  assert.equal(p.errors.length, 0);
});

test("guest link ignores saved owner credentials and drafts, with all writes blocked", async (t) => {
  const draft = { title: "LOCAL OWNER DRAFT", status: "draft", blocks: [{ type: "todo", items: [{ text: "private task", done: false }] }] };
  const p = await makePage(t, { url: BASE + "?open=1#mechanics/assets", draft });
  assert.equal(p.doc.querySelector("#gate").hidden, true);
  assert.equal(p.doc.querySelector("#app").hidden, false);
  assert.equal(p.doc.querySelector("#doc h1").textContent, p.expectedTitle("mech_assets.json"));
  assert.ok(p.doc.querySelector("#foot-info").textContent.includes("гостевой просмотр"));
  assert.equal(p.doc.querySelector("#btn-save").hidden, true);
  assert.equal(p.doc.querySelector("#readonly-bar").hidden, false);
  assert.equal(p.doc.querySelectorAll(".sect-tools").length, 0);
  assert.equal(p.doc.querySelector("#btn-edit-all"), null);
  assert.equal(p.doc.querySelector("#lnk-inbox").hidden, true);
  assert.ok([...p.doc.querySelectorAll("input[type=checkbox]")].every((x) => x.disabled));
  assert.equal(p.window.localStorage.getItem("zombi-docs:token"), TOKEN, "guest view must not delete the owner's saved token");
  const writesBefore = p.writes;
  p.doc.querySelector("#btn-save").click();
  p.window.dispatchEvent(new p.window.KeyboardEvent("keydown", { key: "s", ctrlKey: true, bubbles: true, cancelable: true }));
  p.doc.querySelector(".sect").dispatchEvent(new p.window.MouseEvent("dblclick", { bubbles: true }));
  await wait(25);
  assert.equal(p.writes, writesBefore);
  assert.equal(p.doc.querySelector("#modal-root").hidden, true, "double-click must not open editor");
  p.click("#btn-json");
  assert.equal(p.doc.querySelector("#jv").readOnly, true);
  assert.equal(p.doc.querySelector("#jv-ok"), null);
  p.click("[data-close]");
  const link = openAccess(p);
  assert.equal(link, BASE + "?open=1#mechanics/assets");
  assert.equal(p.doc.querySelector('[data-m="github"]'), null);
  assert.equal(p.doc.querySelector("#st-advanced"), null);
  assert.ok(p.calls.every((c) => !Object.keys(c.headers).some((h) => h.toLowerCase() === "authorization")), "no request may reuse owner authorization");
  assert.ok(p.apiCalls().every((c) => c.method === "GET"));
  assert.equal(p.errors.length, 0);
});

test("sharing still works without a token and advanced access controls stay disabled", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "#scenario" });
  const link = openAccess(p);
  assert.equal(link, BASE + "?open=1#scenario");
  assert.equal(p.doc.querySelector("#st-access-fields").hasAttribute("disabled"), true);
  assert.equal(p.doc.querySelector("#st-save-access").disabled, true);
  assert.equal(p.apiCalls().length, 0);
  assert.equal(p.writes, 0);
});

test("401 on access-code save is explained in place and does not break sharing", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/assets", api401: true });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner write controls ready");
  const link = openAccess(p);
  p.doc.querySelector("#st-advanced").open = true;
  p.click("#st-save-access");
  await until(() => p.doc.querySelector("#st-access-status").textContent.includes("401"), "401 explanation visible");
  const status = p.doc.querySelector("#st-access-status");
  assert.match(status.textContent, /401/);
  assert.match(status.textContent, /токен/i);
  assert.match(status.textContent, /просмотр/i);
  assert.equal(status.classList.contains("bad"), true);
  assert.equal(p.doc.querySelector("#st-save-access").disabled, false, "failed save releases button");
  p.click("#st-copy-view");
  await until(() => p.copied.includes(link), "sharing works after GitHub rejects write");
  assert.equal(p.errors.length, 0);
});

test("rejected GitHub settings token is cleared without destroying share access", async (t) => {
  const p = await makePage(t, { api401: "all" });
  p.click("#btn-settings");
  p.click('[data-m="github"]');
  p.click("#st-save-gh");
  await until(() => p.doc.querySelector("#st-gh-status").textContent.includes("401"), "settings explain 401");
  assert.equal(p.window.localStorage.getItem("zombi-docs:token"), null);
  assert.equal(p.doc.querySelector("#st-token").value, "");
  assert.equal(p.doc.querySelector("#st-save-gh").disabled, false);
  p.click('[data-m="access"]');
  assert.equal(p.doc.querySelector("#st-view-link").value, BASE + "?open=1#scenario");
  assert.equal(p.writes, 0);
});

test("configuration outage leaves owner read-only but sharing available", async (t) => {
  const p = await makePage(t, { configFails: true });
  assert.equal(p.doc.querySelector("#btn-save").disabled, true);
  assert.match(p.doc.querySelector("#readonly-bar").textContent, /Конфигурация не загружена/);
  assert.equal(openAccess(p), BASE + "?open=1#scenario");
  p.doc.querySelector("#st-advanced").open = true;
  assert.equal(p.doc.querySelector("#st-access-fields").hasAttribute("disabled"), true);
  assert.equal(p.writes, 0);
});

test("all mechanics subtabs and preview remain readable in guest mode", async (t) => {
  const p = await makePage(t, { owner: false, token: "", url: BASE + "?open=1#mechanics/assets" });
  const ids = ["character", "craft", "research", "weather", "npc", "quests", "locations", "destruction", "physics", "zombies", "combat", "inventory", "assets", "production", "multiplayer"];
  for (const id of ids) {
    const button = [...p.doc.querySelectorAll("#subtabs .subtab")].find((x) => x.textContent.includes(({ character: "Персонаж", craft: "Крафт", research: "Исследование", weather: "Погода", npc: "NPC", quests: "Квесты", locations: "Локации", destruction: "Разрушаемые", physics: "Физика", zombies: "ИИ монстров", combat: "Бой", inventory: "Инвентарь", assets: "3D-модели", production: "Аудио", multiplayer: "Сетевая" })[id]));
    assert.ok(button, "subtab " + id);
    button.click();
    await until(() => p.doc.querySelector("#doc h1")?.textContent === p.expectedTitle("mech_" + id + ".json"), "read " + id);
    assert.equal(p.window.location.search, "?open=1", "navigation preserves guest mode");
    assert.equal(p.window.location.hash, "#mechanics/" + id);
    assert.equal(p.doc.querySelectorAll(".sect-tools").length, 0);
  }
  assert.equal(openAccess(p), BASE + "?open=1#mechanics/multiplayer");
  p.click("[data-close]");
  p.click('[data-tab="preview"]');
  await until(() => p.doc.querySelector("#doc h1")?.textContent === p.expectedTitle("preview.json"), "preview loads");
  await until(() => p.doc.querySelector(".prev-grid"), "preview gallery loads");
  assert.equal(p.doc.querySelector("#p-add-img"), null);
  assert.equal(p.doc.querySelector("#p-add-md"), null);
  assert.equal(p.doc.querySelectorAll(".add-card").length, 0);
  assert.equal(p.doc.querySelectorAll("[data-x]").length, 0);
  assert.equal(p.writes, 0);
  assert.equal(p.errors.length, 0);
});

test("existing owner code-generation and commit path still works against a mocked API", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/assets" });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner ready");
  openAccess(p);
  p.doc.querySelector("#st-advanced").open = true;
  assert.equal(p.doc.querySelector("#st-access-fields").disabled, false);
  p.click("#st-gen");
  await until(() => p.doc.querySelector("#st-allowed").value.split("\n").filter(Boolean).length === 1, "guest hash generated");
  const code = p.doc.querySelector("#st-newcode").value;
  assert.match(code, /^ZOMBI-[0-9a-f]{24}$/);
  p.click("#st-save-access");
  await until(() => p.doc.querySelector("#st-access-status").textContent.includes("Коды сохранены"), () => "mock commit completes: " + p.doc.querySelector("#st-access-status").textContent + " ERRORS " + p.errors.join("; "));
  const put = p.calls.find((c) => c.method === "PUT");
  assert.ok(put);
  const body = JSON.parse(put.body);
  assert.equal(body.branch, BRANCH);
  assert.equal(body.sha, "mock-config-sha");
  const committed = JSON.parse(Buffer.from(body.content, "base64").toString("utf8"));
  assert.equal(committed.gate.allowed.length, 1);
  assert.ok(!committed.gate.allowed.includes(code));
  assert.ok(!JSON.stringify(committed).includes(TOKEN));
  assert.equal(committed.origin.branch, BRANCH);
  assert.equal(p.errors.length, 0);
});

test("public config contains no credential fields and workflow deploys this source branch", () => {
  assert.ok(!Object.prototype.hasOwnProperty.call(config, "token"));
  assert.ok(!Object.prototype.hasOwnProperty.call(config, "githubToken"));
  assert.equal(config.origin.branch, BRANCH);
  assert.ok(!JSON.stringify(config).includes("ZOMBI-2026"));
  const workflow = fs.readFileSync(path.join(__dirname, "..", "..", ".github", "workflows", "deploy-docs-site.yml"), "utf8");
  assert.ok(workflow.includes("      - " + BRANCH + "\n"));
  assert.ok(workflow.includes("npm test --prefix game-docs"));
});

/* ----------------------------- full local editor -------------------------- */
function submitForm(p, form) {
  form.dispatchEvent(new p.window.Event("submit", { bubbles: true, cancelable: true }));
}
function draftOf(p, file) {
  return JSON.parse(p.window.localStorage.getItem("zombi-docs:draft:" + file));
}
function addInlineQuestion(p, text, answer = "") {
  const form = p.doc.querySelector("[data-qform]");
  assert.ok(form, "inline question form is visible");
  form.elements.question.value = text;
  form.elements.answer.value = answer;
  submitForm(p, form);
}

test("normal editor entry without a token adds, answers, resolves and keeps questions locally", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "?edit=1#mechanics/zombies" });
  assert.equal(p.doc.querySelector("#btn-edit-tab").hidden, false);
  assert.equal(p.doc.querySelector("#btn-save").disabled, false, "publication button explains how to connect GitHub");
  assert.match(p.doc.querySelector("#readonly-bar").textContent, /Редактирование включено/);
  const before = p.doc.querySelectorAll(".question-item").length;
  addInlineQuestion(p, "Как зомби теряет цель?", "После десяти секунд без видимости.");
  await until(() => p.doc.querySelectorAll(".question-item").length === before + 1, "question rendered");
  assert.equal(p.writes, 0, "local editing must not call GitHub");
  assert.equal(p.doc.querySelector("#dirty-bar").hidden, false);
  let draft = draftOf(p, "mech_zombies.json");
  let block = draft.blocks.find((b, i) => b.type === "todo" && draft.blocks[i - 1]?.text === "Открытые вопросы");
  assert.equal(block.items.at(-1).text, "Как зомби теряет цель?");
  assert.equal(block.items.at(-1).answer, "После десяти секунд без видимости.");
  assert.ok(!("_banner" in draft), "transient UI banner is not persisted");
  const last = p.doc.querySelectorAll(".question-item")[before];
  last.querySelector('[data-qact="toggle"]').click();
  await until(() => p.doc.querySelectorAll(".question-item")[before].classList.contains("resolved"), "resolved locally");
  p.doc.querySelectorAll(".question-item")[before].querySelector('[data-qact="answer"]').click();
  p.doc.querySelector("#q-answer").value = "Возвращается к точке патруля.";
  p.click("#q-save");
  await until(() => p.doc.querySelector("#modal-root").hidden, "answer modal closes");
  draft = draftOf(p, "mech_zombies.json");
  block = draft.blocks.find((b, i) => b.type === "todo" && draft.blocks[i - 1]?.text === "Открытые вопросы");
  assert.equal(block.items.at(-1).done, true);
  assert.equal(block.items.at(-1).answer, "Возвращается к точке патруля.");
  // Navigating away and back reloads the same local draft and keeps the dirty indicator.
  [...p.doc.querySelectorAll("#subtabs .subtab")].find((x) => x.textContent.includes("Персонаж")).click();
  await until(() => p.doc.querySelector("#doc h1")?.textContent === p.expectedTitle("mech_character.json"), "other tab");
  [...p.doc.querySelectorAll("#subtabs .subtab")].find((x) => x.textContent.includes("ИИ монстров")).click();
  await until(() => p.doc.querySelector("#doc h1")?.textContent === p.expectedTitle("mech_zombies.json"), "return to draft");
  assert.ok(p.doc.querySelector("#doc").textContent.includes("Возвращается к точке патруля."));
  assert.equal(p.doc.querySelector("#dirty-bar").hidden, false);
  p.click("#btn-save");
  assert.equal(p.doc.querySelector("#st-github").hidden, false, "missing token opens publication settings");
  assert.equal(p.writes, 0);
  assert.equal(p.errors.length, 0);
});

test("question text is escaped, deletion is confirmed, and refresh never discards the draft", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "#mechanics/zombies" });
  addInlineQuestion(p, '<img src=x onerror="window.__xss=1"> Вопрос?');
  await until(() => p.doc.querySelector("#doc").textContent.includes("Вопрос?"), "escaped question appears");
  assert.equal(p.window.__xss, undefined);
  assert.equal(p.doc.querySelector(".question-text img"), null);
  p.click("#btn-refresh");
  await until(() => p.doc.querySelector("#toast-root").textContent.includes("Свежие данные подтянуты"), "refresh completes");
  assert.ok(p.doc.querySelector("#doc").textContent.includes("Вопрос?"), "refresh preserves local draft");
  p.window.confirm = () => false;
  const count = p.doc.querySelectorAll(".question-item").length;
  p.doc.querySelector('.question-item [data-qact="delete"]').click();
  assert.equal(p.doc.querySelectorAll(".question-item").length, count);
  p.window.confirm = () => true;
  p.doc.querySelector('.question-item [data-qact="delete"]').click();
  await until(() => p.doc.querySelectorAll(".question-item").length === count - 1, "delete persists");
  assert.equal(p.writes, 0);
  assert.equal(p.errors.length, 0);
});

test("tab composer inserts text into the chosen section and saves without GitHub", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "#mechanics/zombies" });
  p.click("#btn-edit-tab");
  assert.equal(p.doc.querySelector("#modal-root").hidden, false);
  p.doc.querySelector("#tc-text").value = "## Новое правило\nЗомби обходит препятствие слева.";
  const heading = [...p.doc.querySelectorAll("#tc-target option")].find((o) => o.textContent === "Открытые вопросы");
  assert.ok(heading);
  p.doc.querySelector("#tc-target").value = heading.value;
  p.click("#tc-save");
  await until(() => p.doc.querySelector("#modal-root").hidden, "composer closes");
  const draft = draftOf(p, "mech_zombies.json");
  const at = draft.blocks.findIndex((b) => b.type === "h" && b.text === "Новое правило");
  assert.ok(at > +heading.value);
  assert.equal(draft.blocks[at + 1].text[0], "Зомби обходит препятствие слева.");
  assert.ok(p.doc.querySelector("#doc").textContent.includes("Зомби обходит препятствие слева."));
  assert.equal(p.writes, 0);
  assert.equal(p.errors.length, 0);
});

test("explicit publication commits the current tab and removes only its published draft", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/zombies" });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner ready");
  addInlineQuestion(p, "Публикуемый вопрос", "Публикуемый ответ");
  await until(() => p.doc.querySelector("#doc").textContent.includes("Публикуемый вопрос"), "local question");
  p.click("#btn-save");
  await until(() => p.writes === 1, () => "one content PUT: " + JSON.stringify({ writes: p.writes, pill: p.doc.querySelector("#sync-pill").textContent, errors: p.errors, calls: p.calls.map((c) => c.method + " " + c.href) }));
  const put = p.calls.find((c) => c.method === "PUT");
  assert.ok(put.href.includes("/contents/game-docs/src/content/mech_zombies.json"));
  const body = JSON.parse(put.body);
  assert.equal(body.branch, BRANCH);
  const committed = JSON.parse(Buffer.from(body.content, "base64").toString("utf8"));
  assert.ok(JSON.stringify(committed).includes("Публикуемый ответ"));
  assert.ok(!("_banner" in committed));
  assert.ok(!JSON.stringify(committed).includes(TOKEN));
  await until(() => p.window.localStorage.getItem("zombi-docs:draft:mech_zombies.json") === null, "published draft cleared");
  assert.equal(p.doc.querySelector("#dirty-bar").hidden, true);
  assert.equal(p.errors.length, 0);
});

test("failed publication keeps the local question and explains the error", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/zombies", contentPutStatus: 403 });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner ready");
  addInlineQuestion(p, "Не опубликовано, но сохранено");
  await until(() => p.doc.querySelector("#doc").textContent.includes("Не опубликовано, но сохранено"), "local question");
  p.click("#btn-save");
  await until(() => p.doc.querySelector("#sync-pill").textContent.includes("не опубликовано"), "failure visible");
  assert.ok(draftOf(p, "mech_zombies.json").blocks.some((b) => (b.items || []).some((i) => i.text === "Не опубликовано, но сохранено")));
  assert.equal(p.doc.querySelector("#dirty-bar").hidden, false);
  assert.equal(p.errors.length, 0);
});

test("storage quota failure keeps the question form open instead of claiming a save", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "#mechanics/zombies", storageFail: true });
  const form = p.doc.querySelector("[data-qform]");
  form.elements.question.value = "Вопрос при переполненном хранилище";
  submitForm(p, form);
  assert.equal(p.doc.querySelector("[data-qform] textarea[name=question]").value, "Вопрос при переполненном хранилище", "form text remains");
  assert.match(p.doc.querySelector("[data-qform] .field-status").textContent, /не сохранил/);
  assert.match(p.doc.querySelector("#dirty-text").textContent, /не смог сохранить/);
  assert.equal(p.writes, 0);
});

test("editor link overrides an old guest bookmark only after owner gate; guest link stays read-only", async (t) => {
  const makeGate = async (url, owner) => {
    const dom = new JSDOM(html, { url, runScripts: "outside-only" });
    t.after(() => dom.window.close());
    if (owner) dom.window.localStorage.setItem("zombi-docs:unlocked", config.gate.ownerCode);
    if (dom.window.document.readyState === "loading") await new Promise((resolve) => dom.window.document.addEventListener("DOMContentLoaded", resolve, { once: true }));
    dom.window.eval(gateScript);
    return dom.window;
  };
  const ownerEdit = await makeGate(BASE + "?open=1&edit=1#mechanics/zombies", true);
  assert.equal(ownerEdit.document.querySelector("#gate").hidden, true);
  assert.equal(ownerEdit.__ZOMBI_GATE__.readonly, false);
  const anonymousEdit = await makeGate(BASE + "?edit=1#mechanics/zombies", false);
  assert.equal(anonymousEdit.document.querySelector("#gate").hidden, false, "edit link is not an authentication bypass");
  const guest = await makeGate(BASE + "?open=1#mechanics/zombies", true);
  assert.equal(guest.__ZOMBI_GATE__.readonly, true);
  const p = await makePage(t, { url: BASE + "?open=1&edit=1#mechanics/zombies" });
  assert.equal(p.doc.querySelector("#btn-edit-tab").hidden, false);
  assert.ok(p.doc.querySelector("[data-qform]"));
  const settingsLink = openAccess(p);
  assert.equal(settingsLink, BASE + "?open=1#mechanics/zombies");
  assert.equal(p.doc.querySelector("#st-edit-link").value, BASE + "?edit=1#mechanics/zombies");
});

test("composer can save locally and queue a structured AI task without publishing the tab", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/character" });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner ready");
  p.click("#btn-edit-tab");
  p.doc.querySelector("#tc-text").value = "Пересобери концепцию персонажа вокруг происхождения и практики.";
  p.doc.querySelector("#tc-scope").value = "character-concept";
  p.click("#tc-ai");
  await until(() => p.writes === 1, () => "one inbox PUT: " + JSON.stringify({ writes: p.writes, errors: p.errors, calls: p.calls.map((c) => c.method + " " + c.href) }));
  const put = p.calls.find((c) => c.method === "PUT");
  assert.ok(put.href.includes("/contents/game-docs/src/content/agent-inbox/"));
  const body = JSON.parse(put.body);
  const md = Buffer.from(body.content, "base64").toString("utf8");
  assert.match(md, /scope: character-concept/);
  assert.match(md, /всю концепцию построения персонажа/i);
  assert.match(md, /разбери inbox/);
  assert.match(md, /mech_craft\.json/);
  assert.ok(draftOf(p, "mech_character.json").blocks.some((b) => (b.text || []).join && (b.text || []).join(" ").includes("происхождения и практики")));
  assert.ok(p.calls.every((c) => !c.href.includes("/contents/game-docs/src/content/mech_character.json") || c.method === "GET"), "AI queue must not silently publish the tab");
  assert.equal(p.errors.length, 0);
});

test("AI task without a token is kept as a copyable task instead of being lost", async (t) => {
  const p = await makePage(t, { token: "", url: BASE + "#mechanics/zombies" });
  p.click("#btn-edit-tab");
  p.doc.querySelector("#tc-text").value = "ИИ должен согласовать поведение зомби с шумом персонажа.";
  p.click("#tc-ai");
  await until(() => p.doc.querySelector("#ai-task-body"), "task preview opens");
  assert.match(p.doc.querySelector("#ai-task-body").value, /scope: linked/);
  assert.equal(p.writes, 0);
  p.click("#ai-task-copy");
  await until(() => p.copied.some((x) => x.includes("Задача ИИ")), "task copied");
  assert.ok(draftOf(p, "mech_zombies.json").blocks.some((b) => (b.text || []).join && (b.text || []).join(" ").includes("согласовать поведение зомби")));
  p.click("#ai-task-close");
  assert.equal(p.doc.querySelector("#modal-root").hidden, true);
  assert.equal(p.errors.length, 0);
});

test("inline open question can be added and sent to AI processing", async (t) => {
  const p = await makePage(t, { url: BASE + "#mechanics/zombies" });
  await until(() => !p.doc.querySelector("#btn-save").disabled, "owner ready");
  const form = p.doc.querySelector("[data-qform]");
  form.elements.question.value = "Как потеря цели связана с шумом и стаминой персонажа?";
  form.querySelector("[data-qai]").click();
  await until(() => p.writes === 1, "inbox task created");
  const put = p.calls.find((c) => c.method === "PUT");
  const md = Buffer.from(JSON.parse(put.body).content, "base64").toString("utf8");
  assert.match(md, /открытый вопрос/);
  assert.match(md, /Как потеря цели связана/);
  assert.ok(draftOf(p, "mech_zombies.json").blocks.some((b) => (b.items || []).some((i) => String(i.text || "").includes("Как потеря цели"))));
  assert.equal(p.errors.length, 0);
});
