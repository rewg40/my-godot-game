#!/usr/bin/env python3
"""Применяет patches/content-bundle.json к содержимому ветки (по умолчанию game-docs/src/content).

Зачем: содержимое двух веток разошлось, поэтому построчный diff не ложится. Бандл — это
набор смысловых операций (вставить раздел перед таким-то заголовком, заменить строку,
добавить строку в таблицу, обновить список вопросов). Каждая операция идемпотентна:
повторный запуск ничего не ломает, а то, чего в целевой ветке нет, пропускается с
предупреждением в отчёте — так видно, что переносить руками.

    python3 patches/apply_bundle.py                      # применить к game-docs/src/content
    python3 patches/apply_bundle.py --root /tmp/target   # применить к другой папке
    python3 patches/apply_bundle.py --dry-run            # только отчёт, без записи

Код выхода: 0 — всё применено, 1 — есть пропуски (смотрите отчёт), 2 — ошибка.
"""
from __future__ import annotations
import argparse
import copy
import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUNDLE = os.path.join(HERE, "content-bundle.json")
DEFAULT_ROOT = os.path.join(HERE, "..", "game-docs", "src", "content")


def walk_strings(node, fn):
    """Обходит все строки внутри структуры и подменяет их результатом fn."""
    if isinstance(node, str):
        return fn(node)
    if isinstance(node, list):
        return [walk_strings(x, fn) for x in node]
    if isinstance(node, dict):
        return {k: walk_strings(v, fn) for k, v in node.items()}
    return node


def find_kv(blocks, head0):
    for b in blocks:
        if b.get("type") == "kv" and b.get("head") and b["head"][0] == head0:
            return b
    return None


def find_list(blocks, needle):
    for b in blocks:
        if b.get("type") == "list" and any(isinstance(x, str) and needle in x for x in b["items"]):
            return b
    return None


def heading_index(blocks, text):
    for i, b in enumerate(blocks):
        if b.get("type") == "h" and b.get("text") == text:
            return i
    return -1


def as_list(value):
    """Операции в бандле бывают и списком, и одиночным объектом."""
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def section_range(blocks, heading):
    """Индексы содержимого раздела: от заголовка до следующего заголовка."""
    start = heading_index(blocks, heading)
    if start < 0:
        return -1, -1
    end = len(blocks)
    for i in range(start + 1, len(blocks)):
        if blocks[i].get("type") == "h":
            end = i
            break
    return start, end


def section_list(blocks, heading, create=False):
    """Первый список внутри раздела. Если списка нет и create=True — создаёт в конце раздела."""
    start, end = section_range(blocks, heading)
    if start < 0:
        return None
    for b in blocks[start + 1:end]:
        if b.get("type") == "list":
            return b
    if not create:
        return None
    lb = {"type": "list", "ordered": False, "items": []}
    blocks.insert(end, lb)
    return lb


def apply_ops(doc, ops, notes):
    """Изменяет doc на месте, складывая пояснения в notes. Возвращает True, если что-то поменялось."""
    blocks = doc["blocks"]
    changed = False

    # 1. Новые разделы целиком
    for item in ops.get("insert_before_heading", []):
        head = item["blocks"][0].get("text")
        if any(b.get("type") == "h" and b.get("text") == head for b in blocks):
            notes.append("уже есть: раздел «%s»" % head)
            continue
        idx = heading_index(blocks, item["before"])
        if idx < 0:
            notes.append("НЕ НАЙДЕН якорь «%s» — раздел «%s» не вставлен" % (item["before"], head))
            continue
        blocks[idx:idx] = copy.deepcopy(item["blocks"])
        notes.append("вставлен раздел «%s» (перед «%s»)" % (head, item["before"]))
        changed = True

    # 2. Замена подстроки где угодно в документе
    for item in ops.get("replace_substring", []):
        hits = [0]

        def repl(s):
            if item["find"] in s:
                hits[0] += 1
                return s.replace(item["find"], item["replace"])
            return s

        doc["blocks"] = walk_strings(doc["blocks"], repl)
        if hits[0]:
            notes.append("заменено вхождений: %d — «%s…»" % (hits[0], item["find"][:48]))
            changed = True
        elif item["replace"] in json.dumps(doc["blocks"], ensure_ascii=False):
            notes.append("уже применено: «%s…»" % item["replace"][:48])
        else:
            notes.append("НЕ НАЙДЕНО: «%s…» — правка пропущена" % item["find"][:48])

    # 3. Обновление строки таблицы целиком
    for item in as_list(ops.get("kv_row_update")):
        kv = find_kv(blocks, item["head0"])
        if not kv:
            notes.append("НЕ НАЙДЕНА таблица «%s»" % item["head0"])
            continue
        done = False
        for i, r in enumerate(kv["rows"]):
            if r and isinstance(r[0], str) and r[0].startswith(item["match_prefix"]):
                if r == item["row"]:
                    notes.append("уже обновлено: строка «%s»" % item["match_prefix"])
                else:
                    kv["rows"][i] = copy.deepcopy(item["row"])
                    notes.append("обновлена строка «%s» в таблице «%s»" % (item["match_prefix"], item["head0"]))
                    changed = True
                done = True
                break
        if not done:
            notes.append("НЕ НАЙДЕНА строка «%s» в таблице «%s»" % (item["match_prefix"], item["head0"]))

    # 4. Добавление строк в таблицу
    for item in as_list(ops.get("kv_row_append")):
        kv = find_kv(blocks, item["head0"])
        if not kv:
            notes.append("НЕ НАЙДЕНА таблица «%s»" % item["head0"])
            continue
        existing = {r[0] for r in kv["rows"] if r}
        added = 0
        for r in item["rows"]:
            if r[0] in existing:
                continue
            kv["rows"].append(copy.deepcopy(r))
            added += 1
        if added:
            notes.append("добавлено строк в «%s»: %d" % (item["head0"], added))
            changed = True
        else:
            notes.append("строки в «%s» уже на месте" % item["head0"])

    # 5. Дописывание в ячейку таблицы
    for item in as_list(ops.get("kv_cell_append")):
        kv = find_kv(blocks, item["head0"])
        if not kv:
            notes.append("НЕ НАЙДЕНА таблица «%s»" % item["head0"])
            continue
        done = False
        for r in kv["rows"]:
            if r and r[0].startswith(item["match_prefix"]):
                cell = r[item["cell"]]
                if item["append"].strip("; ") in cell:
                    notes.append("ячейка «%s» уже дополнена" % item["match_prefix"])
                else:
                    r[item["cell"]] = cell + item["append"]
                    notes.append("дополнена ячейка «%s»" % item["match_prefix"])
                    changed = True
                done = True
                break
        if not done:
            notes.append("НЕ НАЙДЕНА строка «%s» в таблице «%s»" % (item["match_prefix"], item["head0"]))

    # 6. Новая колонка в таблице
    for item in as_list(ops.get("kv_add_column")):
        kv = find_kv(blocks, item["head0"])
        if not kv:
            notes.append("НЕ НАЙДЕНА таблица «%s»" % item["head0"])
            continue
        if item["column"] in kv["head"]:
            notes.append("колонка «%s» уже есть" % item["column"])
            continue
        if len(kv["rows"]) != len(item["values"]):
            notes.append("НЕ СОВПАЛО число строк (%d) и значений (%d) — колонка «%s» не добавлена"
                         % (len(kv["rows"]), len(item["values"]), item["column"]))
            continue
        at = item.get("at", len(kv["head"]))
        kv["head"].insert(at, item["column"])
        for r, v in zip(kv["rows"], item["values"]):
            r.insert(at, v)
        notes.append("добавлена колонка «%s» в «%s»" % (item["column"], item["head0"]))
        changed = True

    # 7. Дописывание пунктов в список
    for item in as_list(ops.get("list_append")):
        lb = find_list(blocks, item["needle"])
        if not lb:
            notes.append("НЕ НАЙДЕН список с «%s»" % item["needle"])
            continue
        added = 0
        for text in item["items"]:
            if any(text[:40] in x for x in lb["items"]):
                continue
            lb["items"].append(text)
            added += 1
        if added:
            notes.append("добавлено пунктов в список «%s…»: %d" % (item["needle"][:32], added))
            changed = True
        else:
            notes.append("пункты списка «%s…» уже на месте" % item["needle"][:32])

    # 7b. Дописывание пунктов в список внутри раздела (при отсутствии — список создаётся)
    for item in as_list(ops.get("append_after_heading")):
        heading = item["heading"]
        fallback = item.get("fallback_heading")
        lb = section_list(blocks, heading)
        target_heading = heading
        if not lb and fallback:
            lb = section_list(blocks, fallback)
            target_heading = fallback
        if not lb:
            lb = section_list(blocks, heading, create=True)
            target_heading = heading
            if not lb:
                notes.append("НЕ НАЙДЕН раздел «%s» — пункты не перенесены" % heading)
                continue
        added = 0
        for text in item["items"]:
            if any(text[:40] in x for x in lb["items"]):
                continue
            lb["items"].append(text)
            added += 1
        if added:
            notes.append("добавлено пунктов в раздел «%s»: %d" % (target_heading, added))
            changed = True
        else:
            notes.append("пункты раздела «%s» уже на месте" % target_heading)

    # 8. Открытые вопросы: удалить решённые, добавить новые
    todo = ops.get("todo")
    requires = ops.get("todo_requires")
    if todo and requires:
        text = json.dumps(blocks, ensure_ascii=False)
        missing = [r for r in requires if r not in text]
        if missing:
            notes.append("ПРОПУСК вопросов: в целевой вкладке нет понятий %s — вопросы не переносим"
                         % ", ".join("«%s»" % m for m in missing))
            todo = None
    if todo:
        removed = 0
        added = 0
        prefixes = tuple(todo.get("remove_prefixes", []))
        for b in blocks:
            if b.get("type") != "todo":
                continue
            before = len(b["items"])
            if prefixes:
                b["items"] = [it for it in b["items"] if not it.get("text", "").startswith(prefixes)]
            removed += before - len(b["items"])
            have = {it.get("text", "")[:40] for it in b["items"]}
            for q in todo.get("add", []):
                if q[:40] in have:
                    continue
                b["items"].append({"text": q, "done": False})
                added += 1
        if removed:
            notes.append("удалено решённых вопросов: %d" % removed)
            changed = True
        if added:
            notes.append("добавлено новых вопросов: %d" % added)
            changed = True
        if not removed and not added:
            notes.append("вопросы уже приведены к правилу")

    if changed:
        doc["updated"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", default=DEFAULT_BUNDLE)
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    bundle = json.load(open(args.bundle, encoding="utf-8"))
    print("Бандл %s (ветка-источник %s)" % (bundle.get("version"), bundle.get("source_branch")))
    print("Папка контента: %s%s" % (os.path.abspath(args.root), "  [dry-run, записи не будет]" if args.dry_run else ""))
    missed = 0
    for fname, ops in bundle["files"].items():
        path = os.path.join(args.root, fname)
        print("\n" + fname)
        if not os.path.exists(path):
            print("   НЕТ ФАЙЛА в целевой ветке")
            missed += 1
            continue
        doc = json.load(open(path, encoding="utf-8"))
        notes = []
        try:
            changed = apply_ops(doc, ops, notes)
        except Exception as exc:  # noqa: BLE001 - отчёт важнее падения
            print("   ОШИБКА: %s" % exc)
            missed += 1
            continue
        for line in notes:
            print("   - " + line)
            if line.startswith(("НЕ НАЙДЕН", "НЕ СОВПАЛО", "НЕ НАЙДЕНА", "НЕТ ФАЙЛА")):
                missed += 1
        if not notes:
            print("   - операций нет")
        if changed and not args.dry_run:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
            print("   записано")
        elif changed:
            print("   было бы записано")
    print("\nИтого пропусков: %d" % missed)
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
