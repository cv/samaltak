"""A Benchmarks Game Pharo program as Pharo 14 files it in (Pharo 12 reads it too): one method per methodsFor:
preamble, followed by an empty chunk (Pharo 14 evaluates a category's third method as a statement); the package
named BenchmarksGame (Pharo 14 rejects lowercase package names); the global newline that revcomp-pharo-1 reads
(Pharo 14 does not compile undeclared variables).   usage: pharo14.py IN OUT"""
import sys


def convert(text):
    i, n, out = 0, len(text), ['Smalltalk at: #newline put: nil!\n']

    def chunk():
        nonlocal i
        buf = []
        while i < n:
            c = text[i]
            if c == '!':
                if i + 1 < n and text[i + 1] == '!':
                    buf.append('!'); i += 2; continue
                i += 1
                return ''.join(buf)
            buf.append(c); i += 1
        return ''.join(buf)

    esc = lambda s: s.replace('!', '!!')
    while True:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        if text[i] == '!':
            i += 1
            pre = chunk()
            if 'methodsFor:' not in pre:
                raise SystemExit('unsupported preamble: ' + pre)
            while i < n:
                m = chunk()
                if not m.strip():
                    break
                out.append('!' + pre + '!' + esc(m) + '! !\n\n')
        else:
            out.append(esc(chunk()).replace("category: 'benchmarks game'", "category: 'BenchmarksGame'") + '!\n')
    return ''.join(out)


open(sys.argv[2], 'w').write(convert(open(sys.argv[1]).read()))
