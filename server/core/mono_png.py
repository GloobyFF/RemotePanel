from __future__ import annotations

import struct
import zlib
from PIL import Image

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def save_l_png_no_filter(img: Image.Image) -> bytes:
    gray = img.convert("L")
    width, height = gray.size
    px = gray.load()
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.append(0 if px[x, y] < 128 else 255)
    png = PNG_MAGIC
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
    png += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += _chunk(b"IEND", b"")
    return png
