# Защита от записи по устаревшему `sha` (правка `app.js`) — куски для ручного переноса

Файл `patches/appjs-409-guard.patch` — это обычный diff (`git apply -3 patches/appjs-409-guard.patch`).
Если он не ложится (ветки `app.js` разошлись), внесите правки руками — ниже готовый код.

## 1. Запросы к API — мимо кэша браузера

Корень ошибки «GitHub 409: … does not match <старый sha>»: GET `/contents` отдавался из
HTTP-кэша, поэтому в PUT уезжал `sha` многочасовой давности.

```js
async function ghFetch(path, opts = {}) {
  const url = api(path);
  if (!url) throw new Error("Не задан репозиторий");
  // cache: "no-store" — браузер не должен отдавать старый ответ API: иначе GET /contents
  // вернёт sha шестичасовой давности и PUT закончится 409 «does not match <старый sha>».
  const res = await fetch(url, { cache: "no-store", ...opts, headers: { ...ghHeaders(!!opts.body), ...(opts.headers || {}) } });
  if (!res.ok) {
    let detail = "";
    try { detail = (await res.json()).message || ""; } catch (e) { /* ignore */ }
    const err = new Error(`GitHub ${res.status}: ${detail || res.statusText}`);
    err.status = res.status;
    if (res.status === 401) err.hint = "GitHub 401: токен не принят — он отсутствует, истёк или отозван. Для просмотра токен не нужен — скопируй ссылку в разделе «Доступ». Для изменения кодов нужен новый токен с Contents: Read and write.";
    if (res.status === 403) err.hint = "GitHub запретил запись. У токена должны быть доступ к этому репозиторию и Contents: Read and write. Для просмотра используй гостевую ссылку.";
    throw err;
  }
  if (res.status === 204) return null;
  const ct = res.headers.get("content-type") || "";
  return ct.includes("json") ? res.json() : res.text();
}
```

## 2. Запись с одним повтором по свежему `sha`

```js
async function ghPutOnce(path, text, message) {
  assertWriteAccess();
  const sha = await ghGetSha(path);
  const body = { message, content: b64FromBytes(utf8.enc(text)), branch: S.origin.branch };
  if (sha) body.sha = sha;
  return ghFetch(`/contents/${encodeURI(path)}`, { method: "PUT", body: JSON.stringify(body) });
}
async function ghPutText(path, text, message, retryOnConflict) {
  try {
    return await ghPutOnce(path, text, message);
  } catch (e) {
    if (e.status !== 409 || !retryOnConflict) throw e;
    return await ghPutOnce(path, text, message);
  }
}
```

Вызов в `pushCurrent` — повтор разрешён только когда автор уже видел окно отличий:

```js
    await ghPutText(path, JSON.stringify(published, null, 2) + "\n",
      `docs(${file.replace(/\.json$/, "")}): правка через сайт`, !!(opts && opts.force));
```

## 3. 409 больше не тупик: открываем окно отличий

```js
    if (e.status === 409) {
      // Копия на сервере уехала вперёд (кэш, чужое окно, агент). Не оставляем автора с ошибкой:
      // показываем те же отличия и те же три действия.
      const remoteText = await remotePublishedText(file);
      if (remoteText) {
        setPill("warn", "вкладку изменили · нужны действия");
        openStaleModal(file, remoteText, "GitHub отклонил запись: пока вы правили, файл в ветке изменился.");
      } else {
        toast("Вкладку уже изменили в ветке " + esc(S.origin.branch) + ": обновите страницу и внесите правку заново. Локальная правка остаётся во вкладке.", "warn", 9000);
      }
```

## 4. Окно отличий принимает пояснение

```js
function staleModalHtml(file, remote, diff, note) {
  return `
    <p>Пока вкладка была открыта, <code>${esc(file)}</code> изменили в ветке <code>${esc(S.origin.branch)}</code>.</p>
    ${note ? `<p class="hint">${esc(note)}</p>` : ""}
    <p>В репозитории: <b>${esc(remote.updated || "без метки")}</b> · у вас на экране: <b>${esc((S.content && S.content.updated) || "без метки")}</b>.
    Публикация сейчас затрёт ту, чужую правку.</p>
    <pre class="code">${esc(diff)}</pre>
    <p class="hint">«−» — чего нет в вашей копии (уже есть в репозитории); «+» — что вы опубликуете поверх.</p>`;
}
```

```js
function openStaleModal(file, remoteText, note) {
  let remote = null;
  try { remote = JSON.parse(remoteText); } catch (e) { toast("Версия из репозитория не читается как JSON — публикация отменена.", "warn", 6000); return; }
  const diff = textDiff(JSON.stringify(remote, null, 2), JSON.stringify(S.content, null, 2), 24);
  const modal = openModal("Вкладка в репозитории изменилась", staleModalHtml(file, remote, diff, note) + `
    <div class="foot-row">
      <button class="primary" id="stl-reload">Перечитать с сервера</button>
      <button class="ghost" id="stl-publish">Всё равно опубликовать</button>
      <button class="ghost" id="stl-cancel">Отмена</button>
    </div>`);
  $("#stl-cance
```

## 5. Штамп сборки

Поднимите `const SITE_BUILD = "…"`, чтобы в долго открытых вкладках сработало напоминание
обновить страницу (старый `app.js` в памяти браузера не знает этих проверок).
