#!/usr/bin/env python3
"""Draw the extension icon at every size the manifest asks for.

Stdlib only; see docs/building.md. The icons are committed, so this only needs
running when the drawing changes.

    scripts/make_icons.py            write src/icons/icon-*.png
"""

import struct
import zlib
from pathlib import Path

SIZES = (48, 64, 96, 128, 256, 512)
SS = 4  # supersampling factor; 4 is plenty and keeps 512px fast

PLATE = (0x15, 0x5F, 0x7A)  # deep teal, reads as "document place" without being a logo
INK = (0xFF, 0xFF, 0xFF)


def inside(x, y):
    """Is the point (x, y), in a unit square, part of the glyph?

    A shaft with a triangular head above a tray bar. Coordinates run 0..1 with y
    increasing downward.
    """
    # tray: the bar the arrow points into
    if 0.74 <= y <= 0.80 and 0.24 <= x <= 0.76:
        return True
    # shaft
    if 0.20 <= y <= 0.46 and 0.435 <= x <= 0.565:
        return True
    # head: a triangle narrowing to a point at y = 0.66
    if 0.46 <= y <= 0.66:
        half = 0.20 * (0.66 - y) / 0.20
        return abs(x - 0.5) <= half
    return False


def plate(x, y, radius=0.18):
    """The rounded square behind the glyph, as a unit-square membership test."""
    cx = min(max(x, radius), 1 - radius)
    cy = min(max(y, radius), 1 - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def render(size):
    """Return `size` x `size` RGBA rows, supersampled and box-filtered."""
    n = size * SS
    # Accumulate coverage of plate and ink separately so the glyph can be
    # antialiased against the plate and the plate against transparency.
    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            plate_hits = ink_hits = 0
            for sy in range(SS):
                y = (py * SS + sy + 0.5) / n
                for sx in range(SS):
                    x = (px * SS + sx + 0.5) / n
                    if plate(x, y):
                        plate_hits += 1
                        if inside(x, y):
                            ink_hits += 1
            total = SS * SS
            if not plate_hits:
                row += b"\x00\x00\x00\x00"
                continue
            alpha = plate_hits / total
            ink = ink_hits / plate_hits  # ink only exists on top of the plate
            colour = tuple(
                round(PLATE[c] * (1 - ink) + INK[c] * ink) for c in range(3)
            )
            row += bytes((*colour, round(alpha * 255)))
        rows.append(bytes(row))
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    out = Path(__file__).resolve().parent.parent / "src" / "icons"
    out.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        path = out / f"icon-{size}.png"
        write_png(path, size, render(size))
        print(f"  {path.name}  {path.stat().st_size:>6} bytes")


if __name__ == "__main__":
    main()
