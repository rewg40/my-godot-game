#!/usr/bin/env python3
"""Проверка, что все пути res:// в проекте ведут на существующие файлы.

Тяжёлые ассеты (GLB и точки растительности) намеренно отсутствуют в git —
они подключаются локально, поэтому их пути проверяются отдельно и не считаются
ошибкой.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OPTIONAL_PREFIXES = ("assets/models/", "assets/data/")
PATH_RE = re.compile(r'res://([^"\'\s)]+)')


def collect_files() -> list[Path]:
    files = list(PROJECT.glob("*.godot")) + list(PROJECT.rglob("*.gd")) + list(PROJECT.rglob("*.tscn"))
    return sorted(files)


def main() -> int:
    missing = []
    checked = 0
    for path in collect_files():
        text = path.read_text(encoding="utf-8")
        for relative in PATH_RE.findall(text):
            relative = relative.rstrip("/")
            if not relative:
                continue
            if relative.startswith(OPTIONAL_PREFIXES):
                continue
            checked += 1
            target = PROJECT / relative
            if not target.exists():
                missing.append((path.relative_to(PROJECT), relative))

    for source, relative in missing:
        print("Нет файла: res://%s (ссылка из %s)" % (relative, source))
    print("Проверено путей: %d, отсутствует: %d" % (checked, len(missing)))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
