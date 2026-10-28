#!/usr/bin/env python3
"""Recover the ruined-city GLB models from the UTF-8-mangled chunks.

The chunks in assets/city_3d/*.glb.NNN.bin were split by
scripts/assemble_city_models.py, but the upload pipeline re-encoded the
raw bytes as text: every byte >= 0x80 became a 2-byte UTF-8 sequence
(c2/c3 prefix). The damage is reversible:

    stored bytes --decode utf-8--> unicode code points 0x00..0xFF
                 --encode latin-1--> original binary

Usage (from the repository root):
    python3 tools/recover_city_models.py \
        [--ref origin/arena/3014eb04-my-godot-game] [--out DIR]

Chunks are read straight from git objects, so the city branch does not
need to be checked out. Restored files are written to --out.
"""
import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path

DEFAULT_REF = 'origin/arena/3014eb04-my-godot-game'
CHUNK_DIR = 'assets/city_3d'
MODELS = ['ruined_building_2f', 'ruined_building_3f_a',
          'ruined_building_3f_b', 'ruined_building_3f_c']
GLB_MAGIC = 0x46546C67  # 'glTF'


def git_blob(ref: str, path: str) -> bytes:
    raw = subprocess.run(['git', 'cat-file', 'blob', f'{ref}:{path}'],
                         capture_output=True, check=True).stdout
    return unmojibake(raw)


def unmojibake(raw: bytes) -> bytes:
    """Reverse the text-mode upload corruption."""
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw  # already clean binary
    codes = [ord(ch) for ch in text]
    if max(codes) > 0xFF:
        # Code points beyond Latin-1 mean the encoder used a legacy
        # code page (e.g. cp1252 smart quotes); map them back.
        out = bytearray()
        for cp in codes:
            out.append(cp if cp <= 0xFF else _cp1252_reverse(cp))
        return bytes(out)
    return bytes(codes)


_CP1252_SPECIAL = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
    0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
    0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
    0x017E: 0x9E, 0x0178: 0x9F,
}


def _cp1252_reverse(cp: int) -> int:
    return _CP1252_SPECIAL.get(cp, 0x3F)  # '?' fallback


def assemble(name: str, ref: str, out_dir: Path) -> Path:
    ls = subprocess.run(['git', 'ls-tree', '-r', '--name-only', ref,
                         CHUNK_DIR], capture_output=True, check=True, text=True)
    parts = sorted(line for line in ls.stdout.splitlines()
                   if line.startswith(f'{CHUNK_DIR}/{name}.glb.'))
    if not parts:
        raise SystemExit(f'нет чанков для {name}')
    blob = bytearray()
    for part in parts:
        blob += git_blob(ref, part)
    out = out_dir / f'{name}.glb'
    out.write_bytes(blob)
    # Validate the GLB container.
    magic, version, length = struct.unpack_from('<III', blob, 0)
    ok = magic == GLB_MAGIC and version == 2 and length == len(blob)
    info = f'{name}.glb: {len(parts)} чанков, {len(blob)//1048576} МБ, '
    info += 'заголовок OK' if ok else f'заголовок БИТ (magic={magic:#x}, len={length})'
    print(info)
    if not ok:
        raise SystemExit(f'{name}: GLB не восстановился')
    # Validate the JSON chunk and count the payload.
    jlen, jtype = struct.unpack_from('<I4s', blob, 12)
    assert jtype == b'JSON', 'первый чанк не JSON'
    doc = json.loads(blob[20:20 + jlen].decode('utf-8'))
    meshes = len(doc.get('meshes', []))
    images = len(doc.get('images', []))
    nodes = len(doc.get('nodes', []))
    print(f'  JSON OK: мешей={meshes}, изображений={images}, нод={nodes}')
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--ref', default=DEFAULT_REF)
    ap.add_argument('--out', default='assets/city_3d')
    ap.add_argument('--models', nargs='*', default=MODELS)
    args = ap.parse_args()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    failed = []
    for name in args.models:
        try:
            assemble(name, args.ref, out_dir)
        except SystemExit as exc:
            failed.append(name)
            print(exc, file=sys.stderr)
    if failed:
        print('Не восстановлено:', ', '.join(failed))
        return 1
    print('Все модели восстановлены.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
