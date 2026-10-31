"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const SRC = path.join(__dirname, "..", "src", "content");
const read = (name) => JSON.parse(fs.readFileSync(path.join(SRC, name), "utf8"));
const textOf = (doc) => JSON.stringify(doc.blocks);

// Канон: четыре стартовые должности (медик, инженер, военный, строитель) закрывают
// четыре опоры выживания. Водолаз и связист — не старты, а «перевод должности» в v1.
const ORIGINS = [
  "Медик (карантинный фельдшер)",
  "Инженер (энергетик «Горизонта»)",
  "Военный (караульный «Пелены»)",
  "Строитель (плотник Бродяг)",
];

test("character concept is origin + practice, not a locked class", () => {
  const d = read("mech_character.json");
  const headings = d.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Четыре происхождения: медик, инженер, военный, строитель"));
  assert.ok(headings.includes("Практика вместо уровней"));
  assert.ok(headings.includes("Специализация: приёмы, а не перки"));
  const txt = textOf(d);
  for (const origin of ORIGINS) assert.ok(txt.includes(origin), origin);
  assert.ok(txt.includes("R0 = 0–19") && txt.includes("R4 = 80–100"));
  assert.ok(txt.includes("Строительство"), "восьмой навык есть");
  // навыков ровно восемь, и «Строительство» среди них
  const skills = d.blocks.find((b) => b.type === "kv" && b.head[0] === "Навык" && b.head[1] === "Что тренирует");
  assert.equal(skills.rows.length, 8);
  assert.ok(skills.rows.some((r) => r[0] === "Строительство"));
  // приёмов — по одному набору на каждый навык
  const tech = d.blocks.find((b) => b.type === "kv" && b.head[0] === "Навык" && b.head[1] === "Приём R2");
  assert.equal(tech.rows.length, 8);
  // старые стартовые должности больше не выдаются на старте
  for (const old of ["Техник-сварщик «Пелены»", "Водолаз-разведчик", "Связист-картограф", "Медик-биолог"]) {
    assert.ok(!txt.includes(old), `старый старт убран: ${old}`);
  }
  // водолаз и связист остались как перевод должности
  assert.ok(txt.includes("водолаз") && txt.includes("связист"));
  // специализации: третий слой сборки, не класс и не девятый навык
  const spec = d.blocks.find((b) => b.type === "kv" && b.head[0] === "Специализация");
  assert.equal(spec.rows.length, 8);
  for (const name of ["Хирург", "Энергетик", "Дозорный", "Фортификатор", "Следопыт", "Тихий охотник", "Носильщик", "Забойщик"]) {
    assert.ok(spec.rows.some((r) => r[0] === name), name);
  }
  assert.ok(spec.rows.every((r) => /R3 \+/.test(r[1])), "требование = R3 основного + R1 вспомогательного");
  const specTxt = textOf(d);
  assert.ok(specTxt.includes("вершинный приём") && specTxt.includes("наставника фракции"));
  assert.ok(specTxt.includes("MVP — 4 специализации"));
  const todos = d.blocks.find((b) => b.type === "todo").items;
  const answered = todos.filter((i) => i.done && i.answer);
  assert.ok(answered.length >= 4, "открытые вопросы имеют ответы");
  assert.ok(todos.filter((i) => !i.done).length >= 3, "остались новые точные вопросы");
});

test("four origins are consistent across tabs", () => {
  const char = textOf(read("mech_character.json"));
  const inv = textOf(read("mech_inventory.json"));
  const scenario = textOf(read("scenario.json"));
  const mp = textOf(read("mech_multiplayer.json"));
  const quests = textOf(read("mech_quests.json"));
  const craft = textOf(read("mech_craft.json"));
  const research = textOf(read("mech_research.json"));
  const npc = textOf(read("mech_npc.json"));
  const loc = textOf(read("mech_locations.json"));

  // вес и норма переноса не разъезжаются
  assert.ok(char.includes("18 кг + 1.5 кг за каждый ранг Атлетики"));
  assert.ok(inv.includes("18 кг + 1.5 кг за ранг Атлетики"));
  // сценарий называет те же четыре старта и тот же набор предметов
  assert.ok(scenario.includes("стартовая должность — за игроком"));
  assert.ok(scenario.includes("Должность — происхождение, а не класс"));
  assert.ok(scenario.includes("медик, инженер, военный или строитель"));
  assert.ok(!scenario.includes("техник, водолаз, связист или медик"));
  // инвентарь учитывает стартовый вес каждого происхождения
  assert.ok(inv.includes("11,6 кг") && inv.includes("10,2 кг") && inv.includes("6,4 кг"));
  // крафт фильтрует рецепты по допуску происхождения
  assert.ok(craft.includes("происхождение-допуск") && craft.includes("плотницкий двор"));
  // исследование требует ту же практику, что дают происхождения
  assert.ok(research.includes("Ремесло, Строительство, Медицина или Материк"));
  // у каждой должности есть контакт и стартовая репутация
  for (const tag of ["карантинная служба", "мастерские Артели", "комендатура «Пелены»", "плотницкий двор Бродяг"]) {
    assert.ok(npc.includes(tag), `контакт: ${tag}`);
    assert.ok(char.includes(tag), `допуск в Персонаже: ${tag}`);
  }
  // сеть: четыре опоры и бонус «Сборка»
  assert.ok(mp.includes("Четыре опоры отряда") && mp.includes("«Сборка»"));
  // локации: стройка считает навык «Строительство»
  assert.ok(loc.includes("Строительство"));
  // наставники фракций учат специализации на репутации +50
  for (const spec of ["Хирург", "Энергетик", "Дозорный", "Фортификатор"]) {
    assert.ok(npc.includes(spec), `наставник: ${spec}`);
  }
  assert.ok(research.includes("вершинный приём специализации"));
  assert.ok(mp.includes("листе отряда"));
  // акт I: у каждого происхождения свой стартовый контракт
  for (const code of ["q1_medic", "q1_eng", "q1_soldier", "q1_builder"]) {
    assert.ok(quests.includes(code), `стартовый квест: ${code}`);
  }
});

test("apex technique can be looted from a node infected", () => {
  const z = read("mech_zombies.json");
  const char = read("mech_character.json");
  const research = read("mech_research.json");
  const quests = read("mech_quests.json");
  const mp = textOf(read("mech_multiplayer.json"));

  const headings = z.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Узловые: трофеи и вершинные приёмы"));
  const nodes = z.blocks.find((b) => b.type === "kv" && b.head[0] === "Узловой");
  assert.equal(nodes.rows.length, 3);
  for (const name of ["Тень", "Бронированный", "Стужа"]) {
    assert.ok(nodes.rows.some((r) => r[0].includes(name)), name);
  }
  const zt = textOf(z);
  assert.ok(zt.includes("живой образец") && zt.includes("12 игровых часов"));
  assert.ok(zt.includes("огонь и взрыв сжигают образец"), "добыча — доставка, а не убийство");

  // персонаж: четвёртый путь получения вершинного приёма
  const ct = textOf(char);
  assert.ok(ct.includes("Четыре пути получить"));
  const todo = char.blocks.find((b) => b.type === "todo").items;
  const apex = todo.find((i) => i.text.startsWith("Можно ли выучить вершинный приём специализации"));
  assert.ok(apex && apex.done && apex.answer, "вопрос про вершинный приём закрыт ответом");
  assert.ok(apex.answer.includes("Тени") && apex.answer.includes("образец"));
  // восемь навыков и фиксированный стартовый набор — решения автора зафиксированы
  for (const prefix of ["Оставлять восемь навыков", "Стартовый набор: фиксированный"]) {
    const it = todo.find((i) => i.text.startsWith(prefix));
    assert.ok(it && it.done && it.answer, `закрыт вопрос: ${prefix}`);
  }
  assert.ok(todo.filter((i) => i.done && i.answer).length >= 7, "ответов не меньше семи");

  // исследование: живой образец как источник и «грязный» эксперимент
  const rt = textOf(research);
  assert.ok(rt.includes("Живой образец (нулевой узел)"));
  assert.ok(rt.includes("Порог") && rt.includes("+6 ч"), "расшифровка двигает Порог");
  // квест на добычу Тени
  assert.ok(textOf(quests).includes("q2_shadow"));
  // серверное событие: образец достаётся тому, кто донёс
  assert.ok(mp.includes("Тень"));
});

test("craft is gated by colony tech level (UT)", () => {
  const craft = read("mech_craft.json");
  const research = read("mech_research.json");
  const scenario = textOf(read("scenario.json"));
  const combat = textOf(read("mech_combat.json"));
  const loc = textOf(read("mech_locations.json"));
  const inv = textOf(read("mech_inventory.json"));
  const prod = textOf(read("mech_production.json"));
  const char = textOf(read("mech_character.json"));

  const headings = craft.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Уровень технологий (УТ)"));
  const levels = craft.blocks.find((b) => b.type === "kv" && b.head[0] === "УТ");
  assert.equal(levels.rows.length, 4);
  for (const id of ["УТ0", "УТ1", "УТ2", "УТ3"]) {
    assert.ok(levels.rows.some((r) => r[0] === id), id);
  }
  const total = levels.rows.reduce((s, r) => s + Number(r[4]), 0);
  assert.equal(total, 140, "рецепты на v1 распределены по уровням");

  // рецепты требуют УТ, а не только станцию
  const recipes = craft.blocks.find((b) => b.type === "kv" && b.head[0] === "Предмет");
  assert.ok(recipes.head.includes("УТ"), "у таблицы рецептов есть колонка УТ");
  assert.ok(recipes.rows.every((r) => /^УТ[0-3]$/.test(r[4])));
  const ct = textOf(craft);
  assert.ok(ct.includes("двумя ключами") && ct.includes("min_tech"));
  assert.ok(ct.includes("46 рецептов"), "MVP: 46 рецептов на УТ0–УТ1");
  assert.ok(ct.includes("tech-пуле"), "УТ растёт из узлов Исследования");
  const ctodo = craft.blocks.find((b) => b.type === "todo").items;
  assert.ok(ctodo.some((i) => i.done && i.answer && i.text.startsWith("Сколько всего рецептов на v1")));
  assert.ok(ctodo.filter((i) => !i.done).length >= 3, "остались новые точные вопросы");

  // стык с Исследованием
  const rh = research.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(rh.includes("Уровень технологий (стык с Крафтом)"));
  const rlevels = research.blocks.find((b) => b.type === "kv" && b.head[0] === "УТ");
  assert.equal(rlevels.rows.length, 4);

  // сценарий: T0–T3 актов — это УТ
  assert.ok(scenario.includes("уровень технологий колонии (УТ"));
  // оружие, станции, лут, UI и персонаж ссылаются на тот же уровень
  assert.ok(combat.includes("УТ2") && combat.includes("уровню технологий колонии"));
  assert.ok(loc.includes("уровень технологий"));
  assert.ok(inv.includes("Лут от УТ не зависит"));
  assert.ok(prod.includes("плашка УТ"));
  assert.ok(char.includes("уровень технологий колонии"));
});

test("infected break doors, they never open them", () => {
  const z = read("mech_zombies.json");
  const loc = textOf(read("mech_locations.json"));
  const craft = textOf(read("mech_craft.json"));

  const headings = z.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Преграды: не открывают, а выбивают"));
  const doors = z.blocks.find((b) => b.type === "kv" && b.head[0] === "Преграда");
  assert.ok(doors.rows.length >= 5);
  assert.ok(doors.rows.some((r) => r[1] === "60 HP"), "жилая дверь = 60 HP");
  assert.ok(doors.rows.some((r) => r[0].includes("Баррикада")), "баррикада как слой");

  const zt = textOf(z);
  assert.ok(zt.includes("нет ни «взять ручку»"), "дверь как понятие недоступна");
  assert.ok(zt.includes("6 HP за удар") && zt.includes("≈ 12 с"), "жилая дверь держит 12 с");
  assert.ok(zt.includes("BREAK_MUL"), "множители поломки в коде");
  const todo = z.blocks.find((b) => b.type === "todo").items;
  const q = todo.find((i) => i.text.startsWith("Умеют ли зомби открывать двери"));
  assert.ok(q && q.done && q.answer.includes("выбить"), "вопрос про двери закрыт");
  assert.ok(todo.filter((i) => !i.done).length >= 3, "остались новые точные вопросы");

  // стык: баррикада есть и в локациях, и в крафте
  assert.ok(loc.includes("+40 HP двери") && loc.includes("≈ 53 с"));
  assert.ok(craft.includes("Баррикада (1 слой, макс. 3)"));
});

test("runners stay rare for the whole game", () => {
  const z = read("mech_zombies.json");
  const types = z.blocks.find((b) => b.type === "kv" && b.head[0] === "Тип");
  const runner = types.rows.find((r) => r[0].startsWith("Бегун"));
  assert.ok(runner[0].includes("Искры, 1–3 ч"), "бегун = свежая стадия");
  assert.ok(runner[3].includes("1 на 12"), "редкий: не чаще одного на двенадцать");
  assert.ok(runner[4].includes("переждать"), "контра — переждать рывок");

  const headings = z.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Стадии → типы: во что превращается заражённый"));
  const stages = z.blocks.find((b) => b.type === "kv" && b.head[0] === "Стадия (часы)");
  assert.equal(stages.rows.length, 4);
  for (const st of ["Искры", "Тень", "Порог", "Стужа"]) {
    assert.ok(stages.rows.some((r) => r[0].startsWith(st)), st);
  }
  const todo = z.blocks.find((b) => b.type === "todo").items;
  const q = todo.find((i) => i.text.startsWith("Бегуны: оставить на всю игру"));
  assert.ok(q && q.done && q.answer.startsWith("Да"), "вопрос про бегунов закрыт");
  assert.ok(textOf(z).includes("12 с на 7.2"), "окно рывка зафиксировано");
});

test("pheromone craft diverts the horde", () => {
  const z = read("mech_zombies.json");
  const craft = read("mech_craft.json");
  const research = textOf(read("mech_research.json"));
  const quests = textOf(read("mech_quests.json"));
  const combat = read("mech_combat.json");
  const inv = textOf(read("mech_inventory.json"));
  const mp = textOf(read("mech_multiplayer.json"));

  const headings = z.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Запах как управление: привада и отвод"));
  const tools = z.blocks.find((b) => b.type === "kv" && b.head[0] === "Средство");
  assert.equal(tools.rows.length, 3);
  assert.ok(tools.rows.some((r) => r[0].includes("Грубая привада")));
  assert.ok(tools.rows.some((r) => r[0].includes("Отвод")));
  const zt = textOf(z);
  assert.ok(zt.includes("хим-стол T3, УТ2"), "феромон требует химии и УТ2");
  assert.ok(zt.includes("дождь −70 %"), "погода важнее рецепта");
  assert.ok(zt.includes("На Тень и волну «Стужа» не действует"), "трофейную охоту не упрощает");
  const todo = z.blocks.find((b) => b.type === "todo").items;
  const q = todo.find((i) => i.text.startsWith("Нужен ли «феромон»-крафт"));
  assert.ok(q && q.done && q.answer.startsWith("Нужен"), "вопрос про феромон закрыт");

  // крафт: рецепты запаха
  const ch = craft.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(ch.includes("Запах как инструмент (стык с ИИ монстров)"));
  const recipes = craft.blocks.find((b) => b.type === "kv" && b.head[0] === "Рецепт");
  assert.equal(recipes.rows.length, 4);
  // стык с остальными вкладками
  assert.ok(research.includes("Феромонный синтез"));
  assert.ok(quests.includes("q2_lure"));
  const toolsTable = combat.blocks.find((b) => b.type === "kv" && b.head[0] === "Инструмент");
  assert.ok(toolsTable.rows.some((r) => r[0].includes("привада")));
  assert.ok(toolsTable.rows.some((r) => r[0].includes("отвод")));
  assert.ok(inv.includes("привада") && inv.includes("0.4 кг"));
  assert.ok(mp.includes("Привада — серверный объект"));
});
