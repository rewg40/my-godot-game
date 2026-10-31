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
