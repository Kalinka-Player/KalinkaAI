#!/usr/bin/env python3
"""Build assets/fonts/KalinkaIcons.ttf from the SVGs in scripts/icons/.

Glyphs Material Icons lacks. Each keeps the code point given here, which
lib/theme/kalinka_icons.dart refers to. Needs fonttools.
"""

import pathlib
import re

from fontTools.fontBuilder import FontBuilder
from fontTools.misc.timeTools import timestampSinceEpoch
from fontTools.misc.transform import Transform
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path

GLYPHS = {
    0xE000: "usb_flash_drive",
    0xE001: "hard_drive_outlined",
}

UPM = 960
ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "scripts" / "icons"
OUT = ROOT / "assets" / "fonts" / "KalinkaIcons.ttf"


def glyph(name: str):
    svg = (SOURCES / f"{name}.svg").read_text()
    min_x, min_y, width, _ = map(float, re.search(r'viewBox="([^"]+)"', svg).group(1).split())
    scale = UPM / width
    # SVG runs down from the top of the box; a font runs up from the baseline.
    em = Transform(scale, 0, 0, -scale, -min_x * scale, UPM + min_y * scale)
    pen = TTGlyphPen(None)
    for path in re.findall(r"<path\b[^>]*>", svg):
        if 'fill="none"' in path:
            continue
        d = re.search(r'\bd="([^"]+)"', path).group(1)
        parse_path(d, TransformPen(Cu2QuPen(pen, max_err=1.0, reverse_direction=True), em))
    return pen.glyph()


def main() -> None:
    names = list(GLYPHS.values())
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder([".notdef", *names])
    fb.setupCharacterMap(GLYPHS)
    fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), **{n: glyph(n) for n in names}})
    glyf = fb.font["glyf"]
    fb.setupHorizontalMetrics({n: (UPM, getattr(glyf[n], "xMin", 0)) for n in [".notdef", *names]})
    fb.setupHorizontalHeader(ascent=UPM, descent=0)
    fb.setupOS2(sTypoAscender=UPM, sTypoDescender=0, sTypoLineGap=0, usWinAscent=UPM, usWinDescent=0, fsType=0)
    fb.setupNameTable({"familyName": "KalinkaIcons", "styleName": "Regular"})
    fb.setupPost()
    # The same SVGs build the same file.
    fb.font.recalcTimestamp = False
    fb.font["head"].created = fb.font["head"].modified = timestampSinceEpoch(0)
    fb.save(str(OUT))


if __name__ == "__main__":
    main()
