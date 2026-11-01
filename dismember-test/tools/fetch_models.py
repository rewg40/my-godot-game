#!/usr/bin/env python3
"""Скачивает модели полигона из репозитория ассетов и раскладывает их по местам.

Модели живут в репозитории `rewg40/pepel-i-zvezdy`, но не в корне, а папками
и разрезанными архивами (у GitHub лимит 100 МБ на файл)::

    зомби/ZOMBI.zip  + ZOMBI.z01…z03     -> assets/models/zombie.glb
    персонаж/медик.zip + медик.z01, z02  -> assets/models/character.glb
    остров/2 остров улучшенный.zip + .z01, z02
                                         -> assets/models/island_improved.glb
    предмет/Dragon Broadsword with Cyan Hilt.glb
                                         -> assets/models/sword.glb

После скачивания зомби и медик сразу нарезаются на части (тело, две руки,
две ноги) — тем же кодом, что и `prepare_assets.py`.

Примеры::

    python tools/fetch_models.py                  # скачать всё
    python tools/fetch_models.py --only sword     # только меч
    python tools/fetch_models.py --from-dir /tmp  # без сети: файлы уже скачаны
    python tools/fetch_models.py --skip-split     # только скачать

Зависимости: только стандартная библиотека (для нарезки нужен numpy).
"""
from __future__ import annotations

import argparse
import io
import shutil
import struct
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
RAW = "https://raw.githubusercontent.com/rewg40/pepel-i-zvezdy/main"

# имя файла в проеке -> (части архива по порядку, что искать внутри)
ASSETS = {
    "island_improved.glb": (
        [
            "остров/2 остров улучшенный.z01",
            "остров/2 остров улучшенный.z02",
            "остров/2 остров улучшенный.zip",
        ],
        "*.glb",
    ),
    "zombie.glb": (
        ["зомби/ZOMBI.z01", "зомби/ZOMBI.z02", "зомби/ZOMBI.z03", "зомби/ZOMBI.zip"],
        "*.glb",
    ),
    "character.glb": (
        ["персонаж/медик.z01", "персонаж/медик.z02", "персонаж/медик.zip"],
        "*.glb",
    ),
    "sword.glb": (
        ["предмет/Dragon Broadsword with Cyan Hilt.glb"],
        None,
    ),
}

SPLIT = {"zombie.glb": "zombie", "character.glb": "character"}


def download(url: str, target: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "dismember-test"})
    with urllib.request.urlopen(request, timeout=120) as response, open(target, "wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            handle.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r    {done / 1048576:6.1f} / {total / 1048576:.1f} МБ", end="")
    print()


def _open_archive(path: Path) -> zipfile.ZipFile:
    """Открывает zip, склеенный из томов .z01/.z02/.zip.

    Архивы в репозитории ассетов многотомные: смещение центрального каталога
    в последнем томе считается от начала этого тома, а не от начала всего файла.
    После склейки смещение приходится поправить, иначе Python ищет каталог
    не там («Bad magic number for file header»).
    """
    data = bytearray(path.read_bytes())
    end = data.rfind(b"PK\x05\x06")
    if end < 0:
        raise zipfile.BadZipFile(f"{path.name}: нет конца центрального каталога")
    declared = struct.unpack("<I", data[end + 16:end + 20])[0]
    real = data.rfind(b"PK\x01\x02", 0, end)
    if real > 0 and real != declared:
        struct.pack_into("<I", data, end + 16, real)
    archive = zipfile.ZipFile(io.BytesIO(bytes(data)))
    for info in archive.infolist():
        if data[info.header_offset:info.header_offset + 4] != b"PK\x03\x04":
            raise zipfile.BadZipFile(f"{path.name}: смещение записи {info.filename} не сходится")
    return archive


def fetch_asset(name: str, parts: list[str], pattern: str | None, models_dir: Path,
                source_dir: Path | None) -> bool:
    target = models_dir / name
    if target.exists():
        print(f"[есть] {name}")
        return True

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        blobs = []
        for index, relative in enumerate(parts):
            local = tmp_dir / f"part{index:02d}"
            if source_dir is not None:
                source = source_dir / Path(relative).name
                if not source.exists():
                    print(f"[пропуск] нет {source}")
                    return False
                shutil.copyfile(source, local)
            else:
                url = f"{RAW}/{urllib.parse.quote(relative)}"
                print(f"[скачать] {relative}")
                try:
                    download(url, local)
                except Exception as error:  # noqa: BLE001 - сеть бывает любой
                    print(f"[ошибка] {relative}: {error}")
                    return False
            blobs.append(local)

        merged = tmp_dir / "merged.zip"
        with open(merged, "wb") as out:
            for blob in blobs:
                with open(blob, "rb") as source_file:
                    shutil.copyfileobj(source_file, out, length=1024 * 1024)

        if pattern is None:
            shutil.copyfile(merged, target)
        else:
            archive = _open_archive(merged)
            with archive:
                names = [n for n in archive.namelist() if n.lower().endswith(".glb")]
                if not names:
                    print(f"[ошибка] в архиве {name} нет GLB")
                    return False
                biggest = max(names, key=lambda n: archive.getinfo(n).file_size)
                with archive.open(biggest) as source_file, open(target, "wb") as out:
                    shutil.copyfileobj(source_file, out, length=1024 * 1024)
                print(f"[распаковано] {biggest} ({archive.getinfo(biggest).file_size / 1048576:.0f} МБ)")

    size_mb = target.stat().st_size / 1048576
    print(f"[готово] {name} — {size_mb:.0f} МБ")
    return True


def split(models_dir: Path, out_dir: Path) -> None:
    try:
        import json

        import numpy as np  # noqa: F401
    except ImportError:
        print("\nНарезка пропущена: нужен numpy (python -m pip install numpy)")
        return

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from prepare_assets import split_model  # noqa: PLC0415

    profiles = json.loads((Path(__file__).resolve().parent / "split_profiles.json")
                          .read_text(encoding="utf-8"))
    for file_name, key in SPLIT.items():
        source = models_dir / file_name
        if not source.exists() or key not in profiles:
            continue
        target = out_dir / f"{key}_parts.glb"
        meta = split_model(source, target, profiles[key])
        print(f"[нарезка] {target.name}: " + ", ".join(
            f"{part}={meta['triangles'][part]}" for part in meta["order"]))


def main() -> int:
    parser = argparse.ArgumentParser(description="Скачать модели полигона")
    parser.add_argument("--models-dir", default=str(PROJECT / "assets" / "models"))
    parser.add_argument("--from-dir", default="", help="взять уже скачанные части отсюда")
    parser.add_argument("--only", default="", help="имена через запятую: zombie, character, island, sword")
    parser.add_argument("--skip-split", action="store_true")
    parser.add_argument("--force", action="store_true", help="скачать заново")
    args = parser.parse_args()

    models_dir = Path(args.models_dir)
    models_dir.mkdir(parents=True, exist_ok=True)
    source_dir = Path(args.from_dir) if args.from_dir else None

    wanted = set()
    if args.only:
        wanted = {item.strip() for item in args.only.split(",") if item.strip()}

    for name, (parts, pattern) in ASSETS.items():
        if wanted and not (wanted & {name.split(".")[0], name.split(".")[0].split("_")[0]}):
            continue
        target = models_dir / name
        if args.force and target.exists():
            target.unlink()
        fetch_asset(name, parts, pattern, models_dir, source_dir)

    if not args.skip_split:
        split(models_dir, models_dir)

    print("\nОстров берётся из assets/models: сначала island_improved.glb, потом island.glb.")
    print("Если улучшенного острова нет — положите island.glb или запустите prepare_assets.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
