"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const SRC = path.join(__dirname, "..", "src", "content");
const read = (name) => JSON.parse(fs.readFileSync(path.join(SRC, name), "utf8"));
const textOf = (doc) => JSON.stringify(doc.blocks);

test("character concept is origin + practice, not a locked class", () => {
  const d = read("mech_character.json");
  const headings = d.blocks.filter((b) => b.type === "h").map((b) => b.text);
  assert.ok(headings.includes("Происхождение: стартовая должность, не класс"));
  assert.ok(headings.includes("Практика вместо уровней"));
  assert.ok(headings.includes("Специализация: приёмы, а не перки"));
  const txt = textOf(d);
  for (const origin of ["Медик", "Инженер", "Военный", "Строитель"]) assert.ok(txt.includes(origin), origin);
  assert.ok(txt.includes("R0 = 0–19") && txt.includes("R4 = 80–100"));
  const answered = d.blocks.find((b) => b.type === "todo").items.find((i) => i.done && i.answer);
  assert.ok(answered, "old fixed-vs-constructor question is answered");
});

test("carry weight and scenario origin stay consistent across tabs", () => {
  const char = textOf(read("mech_character.json"));
  const inv = textOf(read("mech_inventory.json"));
  const scenario = textOf(read("scenario.json"));
  assert.ok(char.includes("18 кг + 1.5 кг за каждый ранг Атлетики"));
  assert.ok(inv.includes("18 кг + 1.5 кг за ранг Атлетики"));
  assert.ok(scenario.includes("стартовая должность — за игроком"));
  assert.ok(scenario.includes("Должность — происхождение, а не класс"));
  assert.ok(!scenario.includes("техник-сварщик форпоста «Пелена», 28–40 лет; имя, пол, внешность — за игроком"));
});


test("zombie rules reflect author decisions", () => {
  const zombies = textOf(read("mech_zombies.json"));
  const scenario = JSON.stringify(read("scenario.json"));
  assert.ok(zombies.includes("не открывает закрытые двери"));
  assert.ok(zombies.includes("деревянную дверь"));
  assert.ok(zombies.includes("во всех актах"));
  assert.ok(!scenario.includes("откроет ключом"));
});
