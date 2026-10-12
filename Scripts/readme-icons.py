#!/usr/bin/env python3
"""Writes the README's tool marks, Docs/icons/<name>.svg, from the app's own.

The app's marks in Sources/Pulse/Resources are drawn in `currentColor`, which
an <img> in a README cannot set: GitHub would draw every one black, and on its
dark theme they would vanish. So each README mark is the app's mark in white on
a dark rounded tile, which reads on both themes. The shape is the app's, copied
and not redrawn, so the two cannot drift; run this again after a mark changes.

`extension.svg` is left out. It is Pulse's own puzzle piece for a product the
icon set has no mark for, and in the README such a row draws no mark at all.

    ./Scripts/readme-icons.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/Pulse/Resources"
OUTPUT = ROOT / "Docs/icons"

TILE = 32
MARK = 20
TILE_RADIUS = 7
TILE_FILL = "#24292f"
MARK_FILL = "#ffffff"

# Attributes of the root <svg> that size or place it, which the tile decides.
DROPPED = {"height", "width", "style", "xmlns", "viewBox", "x", "y"}


def tile(svg: str) -> str:
    root = re.search(r"<svg\b([^>]*)>", svg)
    if not root:
        raise ValueError("no <svg> element")
    attributes = dict(re.findall(r'([\w:-]+)="([^"]*)"', root.group(1)))
    view_box = attributes.get("viewBox", "0 0 24 24")
    kept = " ".join(
        f'{key}="{value}"' for key, value in attributes.items() if key not in DROPPED
    )
    body = svg[root.end():svg.rindex("</svg>")]
    body = re.sub(r"<title>.*?</title>", "", body, flags=re.S)
    kept = kept.replace("currentColor", MARK_FILL)
    body = body.replace("currentColor", MARK_FILL)
    offset = (TILE - MARK) // 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{TILE}" height="{TILE}" viewBox="0 0 {TILE} {TILE}">'
        f'<rect width="{TILE}" height="{TILE}" rx="{TILE_RADIUS}" fill="{TILE_FILL}"/>'
        f'<svg x="{offset}" y="{offset}" width="{MARK}" height="{MARK}" viewBox="{view_box}" {kept}>'
        f"{body}</svg></svg>\n"
    )


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    written = 0
    for source in sorted(SOURCE.glob("*.svg")):
        if source.stem == "extension":
            continue
        (OUTPUT / source.name).write_text(tile(source.read_text()))
        written += 1
    print(f"Wrote {written} marks to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
