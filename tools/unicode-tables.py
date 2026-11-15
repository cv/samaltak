#!/usr/bin/env python3
"""Unicode character data for the image: writes src/Kernel-Collections/UnicodeTables.st and the grapheme break test cases
src/Tests-Kernel/GraphemeBreakTestData.st from the Unicode Character Database.

The UCD files of the pinned version (VERSION) are downloaded once into a cache directory outside the repository
($SAMALTAK_UCD_CACHE, default ~/.cache/samaltak-ucd/VERSION).

UnicodeTables properties (Unicode propertiesOf:): one word per code point, run-length encoded: propertyStarts (the
sorted first code points of the runs) and propertyIndices (each run's word, an index into the distinct propertyWords);
bits of a word:
  0-4   general category, an index into categories (1-based)
  5-8   Grapheme_Cluster_Break, an index into graphemeBreakProperties (0-based: 0 = Other)
  9     Extended_Pictographic
  10-11 Indic_Conjunct_Break: 0 None, 1 Consonant, 2 Linker, 3 Extend
  12-13 display width 0, 1 or 2 (as wcwidth): 0 for Mn Me Cf (but U+00AD) Cc and Hangul medial vowels and final
        consonants (U+1160-11FF, U+D7B0-D7FF); 2 for East_Asian_Width W and F; else 1
  14    White_Space
  15    Emoji_Presentation
latin1Properties: the words of U+0000-00FF, for direct indexing.
Case mappings (simple, from UnicodeData.txt) and simple case folding (CaseFolding.txt status C and S) as runs
{start. stop. stride. delta}: every stride-th code point from start to stop maps to itself + delta. titlecaseExceptions
and caseFoldExceptions list only where titlecase differs from uppercase and the folding from lowercase.
decimalDigitZeros: the code point of each decimal digit (Nd) zero; Nd digits come in runs of ten from 0 to 9, so a
digit's value is its distance from the last zero at or below it (the generator checks this).
usage: tools/unicode-tables.py   (from anywhere; Python 3, standard library only)
"""
import os
import re
import sys
import urllib.request

VERSION = '17.0.0'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'src/Kernel-Collections/UnicodeTables.st')
TEST_OUT = os.path.join(ROOT, 'src/Tests-Kernel/GraphemeBreakTestData.st')
CACHE = os.environ.get('SAMALTAK_UCD_CACHE') or os.path.join(os.path.expanduser('~'), '.cache', 'samaltak-ucd', VERSION)
FILES = ['UnicodeData.txt', 'PropList.txt', 'DerivedCoreProperties.txt', 'EastAsianWidth.txt', 'CaseFolding.txt',
         'auxiliary/GraphemeBreakProperty.txt', 'auxiliary/GraphemeBreakTest.txt', 'emoji/emoji-data.txt']
N = 0x110000

CATEGORIES = ['Lu', 'Ll', 'Lt', 'Lm', 'Lo', 'Mn', 'Mc', 'Me', 'Nd', 'Nl', 'No', 'Pc', 'Pd', 'Ps', 'Pe', 'Pi', 'Pf', 'Po',
              'Sm', 'Sc', 'Sk', 'So', 'Zs', 'Zl', 'Zp', 'Cc', 'Cf', 'Cs', 'Co', 'Cn']
GCB = ['Other', 'CR', 'LF', 'Control', 'Extend', 'ZWJ', 'Regional_Indicator', 'Prepend', 'SpacingMark', 'L', 'V', 'T',
       'LV', 'LVT']
INCB = {'None': 0, 'Consonant': 1, 'Linker': 2, 'Extend': 3}


def fetch(name):
    path = os.path.join(CACHE, os.path.basename(name))
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = 'https://www.unicode.org/Public/%s/ucd/%s' % (VERSION, name)
        sys.stderr.write('fetching %s\n' % url)
        with urllib.request.urlopen(url) as r:
            data = r.read()
        with open(path + '.part', 'wb') as f:
            f.write(data)
        os.rename(path + '.part', path)
    with open(path, encoding='utf-8') as f:
        return f.read()


def records(text):
    """(first, last, fields) of each data line: 'XXXX..YYYY ; field ; field # comment'."""
    for line in text.splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        fields = [f.strip() for f in line.split(';')]
        cps = fields[0].split('..')
        yield int(cps[0], 16), int(cps[-1], 16), fields[1:]


def unicode_data():
    category = ['Cn'] * N
    upper, lower, title, decimal = {}, {}, {}, {}
    first = None
    for line in fetch('UnicodeData.txt').splitlines():
        f = line.split(';')
        cp = int(f[0], 16)
        if f[1].endswith(', First>'):
            first = cp
            continue
        start = first if f[1].endswith(', Last>') else cp
        first = None
        for c in range(start, cp + 1):
            category[c] = f[2]
        if f[2] == 'Nd':
            decimal[cp] = int(f[6])
        if f[12]:
            upper[cp] = int(f[12], 16)
        if f[13]:
            lower[cp] = int(f[13], 16)
        if f[14]:
            title[cp] = int(f[14], 16)
    for c, u in upper.items():
        title.setdefault(c, u)
    return category, upper, lower, title, decimal


def properties(category):
    gcb = [0] * N
    for a, b, f in records(fetch('auxiliary/GraphemeBreakProperty.txt')):
        for c in range(a, b + 1):
            gcb[c] = GCB.index(f[0])
    pict = [False] * N
    presentation = [False] * N
    for a, b, f in records(fetch('emoji/emoji-data.txt')):
        if f[0] == 'Extended_Pictographic':
            for c in range(a, b + 1):
                pict[c] = True
        elif f[0] == 'Emoji_Presentation':
            for c in range(a, b + 1):
                presentation[c] = True
    incb = [0] * N
    for a, b, f in records(fetch('DerivedCoreProperties.txt')):
        if f[0] == 'InCB':
            for c in range(a, b + 1):
                incb[c] = INCB[f[1]]
    white = [False] * N
    for a, b, f in records(fetch('PropList.txt')):
        if f[0] == 'White_Space':
            for c in range(a, b + 1):
                white[c] = True
    eaw = ['N'] * N
    text = fetch('EastAsianWidth.txt')
    for m in re.finditer(r'^# @missing: ([0-9A-F]+)\.\.([0-9A-F]+); (\w+)', text, re.M):
        for c in range(int(m.group(1), 16), int(m.group(2), 16) + 1):
            eaw[c] = m.group(3)
    for a, b, f in records(text):
        for c in range(a, b + 1):
            eaw[c] = f[0]
    words = []
    for c in range(N):
        cat = category[c]
        if (cat in ('Mn', 'Me', 'Cf') and c != 0xAD) or cat == 'Cc' or 0x1160 <= c <= 0x11FF or 0xD7B0 <= c <= 0xD7FF:
            width = 0
        elif eaw[c] in ('W', 'F'):
            width = 2
        else:
            width = 1
        words.append((CATEGORIES.index(cat) + 1) | gcb[c] << 5 | pict[c] << 9 | incb[c] << 10 | width << 12
                     | white[c] << 14 | presentation[c] << 15)
    return words


def case_folding():
    fold = {}
    for a, _, f in records(fetch('CaseFolding.txt')):
        if f[0] in ('C', 'S'):
            fold[a] = int(f[1], 16)
    return fold


def mapping_runs(mapping):
    """{start. stop. stride. delta} runs covering the code points of mapping (code point -> code point)."""
    runs = []
    for c in sorted(mapping):
        d = mapping[c] - c
        if runs:
            r = runs[-1]
            if r[3] == d and ((r[0] == r[1] and c - r[1] in (1, 2)) or (r[0] != r[1] and c - r[1] == r[2])):
                if r[0] == r[1]:
                    r[2] = c - r[1]
                r[1] = c
                continue
        runs.append([c, c, 1, d])
    return [x for r in runs for x in r]


def literal(values, indent='\t\t', width=118):
    lines, line = [], ''
    for v in values:
        s = str(v)
        if line and len(line) + 1 + len(s) > width:
            lines.append(line)
            line = s
        else:
            line = line + ' ' + s if line else s
    lines.append(line)
    return '#(\n' + '\n'.join(indent + l for l in lines) + ')'


def method(selector, comment, body):
    return '%s\n\t"%s"\n\t^%s\n!\n' % (selector, comment, body)


def write_tables():
    category, upper, lower, title, decimal = unicode_data()
    words = properties(category)
    starts, values = [], []
    for c, w in enumerate(words):
        if not values or values[-1] != w:
            starts.append(c)
            values.append(w)
    palette = sorted(set(values))
    assert len(palette) <= 256
    fold = case_folding()
    fold_exceptions = {c: fold.get(c, c) for c in set(fold) | set(lower) if fold.get(c, c) != lower.get(c, c)}
    title_exceptions = {c: t for c, t in title.items() if t != upper.get(c, c)}
    zeros = sorted(c for c, v in decimal.items() if v == 0)
    assert len(decimal) == 10 * len(zeros) and all(decimal.get(z + i) == i for z in zeros for i in range(10))
    methods = [
        method('version', 'The version of the Unicode Character Database these tables come from.', "'%s'" % VERSION),
        method('categories', 'General categories, indexed by bits 0-4 of a property word.',
               '#(' + ' '.join('#' + c for c in CATEGORIES) + ')'),
        method('graphemeBreakProperties', 'Grapheme_Cluster_Break values, indexed by bits 5-8 of a property word + 1.',
               '#(' + ' '.join('#' + g for g in GCB) + ')'),
        method('propertyStarts', 'The first code point of each run of equal property words.', literal(starts)),
        method('propertyIndices', 'The index into propertyWords of each run.',
               '#[' + literal([palette.index(v) + 1 for v in values])[2:-1] + ']'),
        method('propertyWords', 'The distinct property words.', literal(palette)),
        method('latin1Properties', 'The property words of U+0000-00FF.', literal(words[:256])),
        method('uppercaseRuns', 'Simple uppercase mappings: {start. stop. stride. delta} runs.', literal(mapping_runs(upper))),
        method('lowercaseRuns', 'Simple lowercase mappings: {start. stop. stride. delta} runs.', literal(mapping_runs(lower))),
        method('titlecaseExceptions', 'Simple titlecase mappings that differ from the uppercase ones, as runs.',
               literal(mapping_runs(title_exceptions))),
        method('caseFoldExceptions', 'Simple case foldings (status C and S) that differ from the lowercase mappings, as runs.',
               literal(mapping_runs(fold_exceptions))),
        method('decimalDigitZeros', 'The digits zero of the decimal digits (Nd), each the first of a run of ten from 0 to 9.',
               literal(zeros)),
    ]
    src = ("Object subclass: #UnicodeTables\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n"
           "\tpackage: 'Kernel-Collections'!\n\n"
           "UnicodeTables comment: 'Generated by tools/unicode-tables.py from the Unicode Character Database %s. Do not edit. "
           "Unicode answers the queries; the encoding is described in the generator.'!\n\n"
           "!UnicodeTables class methodsFor: 'tables'!\n%s! !\n") % (VERSION, ''.join(methods))
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(src)
    sys.stderr.write('%s: %d bytes, %d property runs\n' % (OUT, len(src.encode()), len(starts)))


def write_tests():
    cases = []
    for line in fetch('auxiliary/GraphemeBreakTest.txt').splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        clusters, cluster = [], []
        for tok in line.split()[1:]:
            if tok == '÷':
                clusters.append(cluster)
                cluster = []
            elif tok != '×':
                cluster.append(int(tok, 16))
        cases.append('(' + ' '.join('(' + ' '.join(str(c) for c in cl) + ')' for cl in clusters) + ')')
    body = '#(\n' + '\n'.join('\t\t' + c for c in cases) + ')'
    src = ("Object subclass: #GraphemeBreakTestData\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n"
           "\tpackage: 'Tests-Kernel'!\n\n"
           "GraphemeBreakTestData comment: 'Generated by tools/unicode-tables.py from GraphemeBreakTest.txt of the Unicode "
           "Character Database %s. Do not edit.'!\n\n"
           "!GraphemeBreakTestData class methodsFor: 'cases'!\n%s! !\n") % (
        VERSION, method('cases', 'Each line of GraphemeBreakTest.txt: its extended grapheme clusters, each an Array of code points.', body))
    with open(TEST_OUT, 'w', encoding='utf-8') as f:
        f.write(src)
    sys.stderr.write('%s: %d bytes, %d cases\n' % (TEST_OUT, len(src.encode()), len(cases)))


if __name__ == '__main__':
    write_tables()
    write_tests()
