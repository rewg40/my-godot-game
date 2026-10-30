#!/usr/bin/env python3
"""Package the stand-alone nature island; generated ZIP stays outside Git."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'assets/models/island_nature_4km'


def build(output: Path) -> None:
    files = sorted(p for p in KIT.rglob('*') if p.is_file() and not p.name.endswith(('.import', '.blend1')))
    files += [ROOT / 'docs/ASSET_CREDITS.md', ROOT / 'docs/licenses/CC0-1.0.md']
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, 'w', compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr('README_RU.md', (KIT / 'README.md').read_text(encoding='utf-8'))
        archive.write(KIT / 'island_model_preview.jpg', 'PREVIEW_3D_MODEL.jpg')
        archive.write(KIT / 'concept_reference.jpg', 'CONCEPT_REFERENCE.jpg')
        for path in files:
            assert path.is_file(), path
            archive.write(path, path.relative_to(ROOT).as_posix())
    with ZipFile(output) as archive:
        names = archive.namelist()
        available = set(names)
        assert len(names) == len(available) and archive.testzip() is None
        for name in ('assets/models/island_nature_4km/blender/.gdignore',
                     'assets/models/island_nature_4km/glb/.gdignore',
                     'assets/models/island_nature_4km/blender/island_nature_4km.blend',
                     'assets/models/island_nature_4km/glb/island_4km_complete.glb',
                     'assets/models/island_nature_4km/godot/island_4km.tscn',
                     'assets/models/island_nature_4km/godot/forest_positions.json'):
            assert name in available, f'Missing {name}'
        for name in ('PREVIEW_3D_MODEL.jpg', 'CONCEPT_REFERENCE.jpg'):
            image = archive.read(name)
            assert image.startswith(b'\xff\xd8') and image.endswith(b'\xff\xd9')
        scene = archive.read('assets/models/island_nature_4km/godot/island_4km.tscn').decode('utf-8')
        script = archive.read('assets/models/island_nature_4km/godot/island_4km.gd').decode('utf-8')
        for resource in re.findall(r'(?:path=|preload\()"res://([^\"]+)"', scene + '\n' + script):
            assert resource in available, f'Missing Godot resource {resource}'
        metrics = json.loads(archive.read('assets/models/island_nature_4km/island_metrics.json'))
        forest = json.loads(archive.read('assets/models/island_nature_4km/godot/forest_positions.json'))
        assert len(forest) == metrics['tree_count'] > 10000
        print(f'ISLAND 4KM ARCHIVE CREATED: {output} ({len(names)} files, {output.stat().st_size / 1048576:.2f} MiB)')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path, help='destination ZIP, preferably outside the repository')
    build(parser.parse_args().output)


if __name__ == '__main__':
    main()
