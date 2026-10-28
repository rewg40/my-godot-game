#!/usr/bin/env python3
"""Inspect and optimize the recovered city GLB models.

Textures dominate these files (dense but modest meshes, 2K-4K PNGs).
This tool rewrites each GLB keeping the original geometry buffers intact
and re-encoding embedded images to JPEG/PNG at a smaller edge length.

Usage:
    python3 tools/optimize_city_models.py [--max-edge 1024] [--quality 82]
"""
import argparse
import io
import json
import struct
from pathlib import Path

from PIL import Image

GLB_MAGIC = 0x46546C67


def read_glb(path: Path):
    blob = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', blob, 0)
    assert magic == GLB_MAGIC and version == 2 and length == len(blob)
    jlen, jtype = struct.unpack_from('<I4s', blob, 12)
    assert jtype == b'JSON'
    doc = json.loads(blob[20:20 + jlen].decode('utf-8'))
    off = 20 + jlen
    blen, btype = struct.unpack_from('<I4s', blob, off)
    assert btype == b'BIN\x00'
    bin_data = blob[off + 8:off + 8 + blen]
    return doc, bin_data


def write_glb(path: Path, doc: dict, bin_data: bytes) -> None:
    json_bytes = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    pad = (4 - len(json_bytes) % 4) % 4
    json_bytes += b' ' * pad
    bin_pad = (4 - len(bin_data) % 4) % 4
    bin_data += b'\x00' * bin_pad
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    out = struct.pack('<III', GLB_MAGIC, 2, total)
    out += struct.pack('<I4s', len(json_bytes), b'JSON') + json_bytes
    out += struct.pack('<I4s', len(bin_data), b'BIN\x00') + bin_data
    path.write_bytes(out)


def pad4(n: int) -> int:
    return (4 - n % 4) % 4


def optimize(path: Path, max_edge: int, quality: int) -> None:
    doc, bin_data = read_glb(path)
    images = doc.get('images', [])
    views = doc['bufferViews']
    buffer = doc['buffers'][0]

    # --- stats before ---
    mesh = doc['meshes'][0]
    prims = mesh['primitives']
    acc = doc['accessors']
    verts = sum(acc[p['attributes']['POSITION']]['count'] for p in prims)
    idx = sum(acc[p['indices']]['count'] for p in prims)
    print(f'{path.name}: вершин={verts}, индексов={idx}, изображений={len(images)}')

    keep = bytearray()
    # bufferViews used by images are re-encoded; everything else is copied
    # byte-for-byte, so accessor byteOffsets stay untouched.
    image_view_ids = {img.get('bufferView') for img in images}
    copy_map = {}
    for vi, view in enumerate(views):
        if vi in image_view_ids:
            continue
        start = view.get('byteOffset', 0)
        end = start + view['byteLength']
        copy_map[vi] = (len(keep), end - start)
        keep += bin_data[start:end]
        keep += b'\x00' * pad4(len(keep))

    new_views = []
    for vi, view in enumerate(views):
        if vi in copy_map:
            new_off, n = copy_map[vi]
            v = dict(view)
            v['byteOffset'] = new_off
            v['byteLength'] = n
            new_views.append(v)

    stats = []
    for img in images:
        vi = img['bufferView']
        view = views[vi]
        start = view.get('byteOffset', 0)
        raw = bin_data[start:start + view['byteLength']]
        im = Image.open(io.BytesIO(raw))
        w, h = im.size
        edge = max(w, h)
        scale = min(1.0, max_edge / edge)
        if scale < 1.0:
            im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))),
                           Image.LANCZOS)
        alpha = im.mode in ('RGBA', 'LA')
        if alpha:
            buf = io.BytesIO()
            im.save(buf, 'PNG', optimize=True)
            mime = 'image/png'
        else:
            im = im.convert('RGB')
            buf = io.BytesIO()
            im.save(buf, 'JPEG', quality=quality, optimize=True)
            mime = 'image/jpeg'
        data = buf.getvalue()
        new_vi = len(new_views)
        new_views.append({'buffer': 0, 'byteOffset': len(keep),
                          'byteLength': len(data)})
        keep += data
        keep += b'\x00' * pad4(len(keep))
        img['uri'] = None
        img['bufferView'] = new_vi
        img['mimeType'] = mime
        stats.append(f'{w}x{h}->{im.size[0]}x{im.size[1]}')

    for vi, view in enumerate(views):        # drop stale image views
        if vi not in copy_map and vi not in image_view_ids:
            new_views.append(view)

    doc['bufferViews'] = new_views
    buffer['byteLength'] = len(keep)
    write_glb(path, doc, bytes(keep))
    print(f'  текстуры: {", ".join(stats)}')
    print(f'  размер: {path.stat().st_size // 1048576} МБ')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--max-edge', type=int, default=1024)
    ap.add_argument('--quality', type=int, default=82)
    ap.add_argument('files', nargs='+')
    args = ap.parse_args()
    for f in args.files:
        optimize(Path(f), args.max_edge, args.quality)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
