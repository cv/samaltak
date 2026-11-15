#!/usr/bin/env python3
"""Makes the Noto fallback faces in fonts/ from Google Fonts (github.com/google/fonts, ofl/, pinned commit below).

Variable fonts are instanced at wght 400 (the CJK ones default to Thin); every face is then subset to all its code
points (Noto Sans KR to Hangul only) without hinting, layout features or vertical metrics, names kept. The upstream
files are checked against their SHA-256; the outputs keep the upstream head.modified, so they come out the same each run.

Usage (fontTools pinned: another version may write different bytes):
    python3 -m venv /tmp/fallback-fonts && /tmp/fallback-fonts/bin/pip install fonttools==4.68.0
    /tmp/fallback-fonts/bin/python tools/fallback-fonts.py fonts
"""
import hashlib
import os
import sys
import tempfile
import urllib.parse
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

COMMIT = 'cc39c4c2c304bc368c9b7c311ea2bcc6013299fe'
BASE = 'https://raw.githubusercontent.com/google/fonts/%s/ofl/' % COMMIT
HANGUL = [(0x1100, 0x11FF), (0x3130, 0x318F), (0xA960, 0xA97F), (0xAC00, 0xD7AF), (0xD7B0, 0xD7FF)]

# output, upstream path, upstream SHA-256, code points (None: all of the face's)
FACES = [
    ('NotoEmoji-Regular.ttf', 'notoemoji/NotoEmoji[wght].ttf',
     'de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551', None),
    ('NotoSansSymbols2-Regular.ttf', 'notosanssymbols2/NotoSansSymbols2-Regular.ttf',
     '7d5fb73b7ca67a6798101741f5d280a3d016a56a197afcd4199dbb57b4b82a21', None),
    ('NotoSansSC-Regular.ttf', 'notosanssc/NotoSansSC[wght].ttf',
     'a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da', None),
    ('NotoSansKR-Hangul.ttf', 'notosanskr/NotoSansKR[wght].ttf',
     '194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252',
     [c for a, b in HANGUL for c in range(a, b + 1)]),
]


def fetch(path, sha256, directory):
    out = os.path.join(directory, os.path.basename(path))
    urllib.request.urlretrieve(BASE + urllib.parse.quote(path), out)
    with open(out, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    if digest != sha256:
        sys.exit('%s: SHA-256 %s, expected %s' % (path, digest, sha256))
    return out


def make(source, output, unicodes):
    font = TTFont(source, recalcTimestamp=False)
    if 'fvar' in font:
        font = instancer.instantiateVariableFont(font, {'wght': 400}, updateFontNames=False)
    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.name_IDs = ['*']
    options.name_languages = ['*']
    options.notdef_outline = True
    options.glyph_names = False
    options.drop_tables += ['vmtx', 'vhea', 'VORG', 'DSIG', 'MATH', 'STAT']
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=unicodes if unicodes is not None else list(font.getBestCmap()))
    subsetter.subset(font)
    font.recalcTimestamp = False
    font.save(output)
    print('%s: %d bytes, %d code points' % (output, os.path.getsize(output), len(font.getBestCmap())))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with tempfile.TemporaryDirectory() as tmp:
        for output, path, sha256, unicodes in FACES:
            make(fetch(path, sha256, tmp), os.path.join(sys.argv[1], output), unicodes)


if __name__ == '__main__':
    main()
