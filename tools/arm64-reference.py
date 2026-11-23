#!/usr/bin/env python3
"""Reference arm64 encodings for the tests, from the system assembler (cc, objdump): writes src/Tests-VM/Arm64Reference.st.

The instruction sources are the case: strings of src/Tests-VM/Arm64AssemblerCases.st (instructions separated by |).
Logical immediates: a deterministic sample of the encodable values of each width, and values the assembler rejects.
Disassembly: random words from the instruction classes Arm64Disassembler decodes, with objdump's text (or .word when
objdump does not decode the word or decodes it to an instruction outside the disassembler's set).
usage: tools/arm64-reference.py   (from the repository root; needs Xcode's cc and objdump)
"""
import os
import random
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES = os.path.join(ROOT, 'src/Tests-VM/Arm64AssemblerCases.st')
OUT = os.path.join(ROOT, 'src/Tests-VM/Arm64Reference.st')


def case_sources():
    text = open(CASES).read()
    return [m.group(1).replace("''", "'").replace('!!', '!') for m in re.finditer(r"case: '((?:[^']|'')*)' emit:", text)]


def assemble(lines, tmp):
    """Assemble lines; answer (ok, output): output is the list of (offset, word, text) or the error lines (1-based)."""
    src = os.path.join(tmp, 'ref.s')
    obj = os.path.join(tmp, 'ref.o')
    with open(src, 'w') as f:
        f.write('.text\n')
        for line in lines:
            f.write(line + '\n')
    r = subprocess.run(['cc', '-c', src, '-o', obj], capture_output=True, text=True)
    if r.returncode != 0:
        bad = sorted({int(m.group(1)) - 2 for m in re.finditer(r'ref\.s:(\d+):\d+: error', r.stderr)})
        return False, bad
    dump = subprocess.run(['objdump', '-d', obj], capture_output=True, text=True, check=True).stdout
    out = []
    for line in dump.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(.*)$', line)
        if not m:
            continue
        insn = re.sub(r'\s*;.*$', '', m.group(3))
        insn = re.sub(r'\s*<[^>]*>', '', insn)
        insn = re.sub(r'\s+', ' ', insn.strip())
        out.append((int(m.group(1), 16), int(m.group(2), 16), insn))
    return True, out


def logical_values(width):
    """Every encodable logical immediate of width bits."""
    values = set()
    for size in (2, 4, 8, 16, 32, 64):
        if size > width:
            continue
        for ones in range(1, size):
            for rot in range(size):
                elem = (1 << ones) - 1
                elem = ((elem >> rot) | (elem << (size - rot))) & ((1 << size) - 1)
                v = 0
                for i in range(width // size):
                    v |= elem << (i * size)
                values.add(v)
    return sorted(values)


# Encoding classes of the disassembler's instruction set: bit 31 first, x random, spaces ignored.
DISASM_CLASSES = [
    'xxx 10001 x x xxxxxxxxxxxx xxxxx xxxxx',  # add/sub immediate (bit 23: tagged forms)
    'xxx 01011 xx 0 xxxxx xxxxxx xxxxx xxxxx',  # add/sub shifted register
    'xxx 01011 xx 1 xxxxx xxx xxx xxxxx xxxxx',  # add/sub extended register
    'xxx 01010 xx x xxxxx xxxxxx xxxxx xxxxx',  # logical shifted register
    'xxx 100100 x xxxxxx xxxxxx xxxxx xxxxx',  # logical immediate
    'xxx 100101 xx xxxxxxxxxxxxxxxx xxxxx',  # move wide
    'xxx 100110 x xxxxxx xxxxxx xxxxx xxxxx',  # bitfield
    'xxx 100111 x x xxxxx xxxxxx xxxxx xxxxx',  # extract
    'x0x 11010110 xxxxx 00xxxx xxxxx xxxxx',  # data processing, 2 sources
    'x1x 11010110 xxxxx xxxxxx xxxxx xxxxx',  # data processing, 1 source
    'x00 11011 xxx xxxxx x xxxxx xxxxx xxxxx',  # data processing, 3 sources
    'xxx 11010100 xxxxx xxxx xx xxxxx xxxxx',  # conditional select
    'xx 111 x 01 xx xxxxxxxxxxxx xxxxx xxxxx',  # load/store, unsigned offset
    'xx 111 x 00 xx 0 xxxxxxxxx xx xxxxx xxxxx',  # load/store, unscaled, pre and post index
    'xx 111 x 00 xx 1 xxxxx xxx x 10 xxxxx xxxxx',  # load/store, register offset
    'xx 101 x 0 xx x xxxxxxx xxxxx xxxxx xxxxx',  # load/store pair
    'xx 011 x 00 xxxxxxxxxxxxxxxxxxx xxxxx',  # load literal
    'x xx 10000 xxxxxxxxxxxxxxxxxxx xxxxx',  # adr, adrp
    'x 00101 xxxxxxxxxxxxxxxxxxxxxxxxxx',  # b, bl
    '0101010 x xxxxxxxxxxxxxxxxxxx x xxxx',  # b.cond
    'x 011010 x xxxxxxxxxxxxxxxxxxx xxxxx',  # cbz, cbnz
    'x 011011 x xxxxx xxxxxxxxxxxxxx xxxxx',  # tbz, tbnz
    '1101011 0 0xx 11111 000000 xxxxx 00000',  # br, blr, ret
    '1101011 x xxx xxxxx xxxxxx xxxxx xxxxx',  # branch to register, other
    '11010100 xxx xxxxxxxxxxxxxxxx xxx xx',  # exceptions (brk)
    '1101010100 0 00 011 0010 xxxx xxx 11111',  # hints (nop)
    '1101010100 0 00 011 0011 xxxx xxx 11111',  # barriers
    'x 0 x 11110 xx 1 xxxxx xxxx 10 xxxxx xxxxx',  # FP 2 sources
    '0 0 0 11110 01 1 xxxxx xxxx 10 xxxxx xxxxx',  # FP 2 sources, double
    '0 0 0 11110 xx 1 xxxxxx 10000 xxxxx xxxxx',  # FP 1 source
    '0 0 0 11110 01 1 0 xxxxx 10000 xxxxx xxxxx',  # FP 1 source, double
    'x 0 x 11110 xx 1 xxxxx xx 1000 xxxxx xxxxx',  # FP compare
    '0 0 0 11110 01 1 xxxxx xxxx 11 xxxxx xxxxx',  # FP conditional select
    'x 0 x 11110 xx 1 xxxxxxxx 100 xxxxx xxxxx',  # FP immediate
    '0 0 0 11110 01 1 xxxxxxxx 100 00000 xxxxx',  # FP immediate, double
    'x 0 x 11110 xx 1 xx xxx 000000 xxxxx xxxxx',  # FP <-> integer
    'x 0 0 11110 01 1 xx xxx 000000 xxxxx xxxxx',  # FP <-> integer, double
    'x x 1 11010010 xxxxx xxxx x 0 xxxxx 0 xxxx',  # conditional compare (last: the classes before keep their sample)
]

# Field values that select aliases, set with some probability where the class leaves the field random: (lsb, width, value).
DISASM_FIELDS = [(0, 5, 31), (5, 5, 31), (16, 5, 31), (10, 5, 31), (10, 6, 63), (10, 6, 31), (10, 6, 7), (10, 6, 15),
                 (16, 6, 0), (5, 16, 0), (5, 16, 0xFFFF), (12, 4, 15)]

DISASM_MNEMONICS = set('''add sub adds subs cmp cmn neg negs mov and orr eor ands bic bics orn eon tst mvn movz movk movn
    lsl lsr asr ror mul madd msub mneg smulh umulh sdiv udiv csel csinc csinv csneg cset csetm cinc cinv cneg ccmp ccmn
    ubfx sbfx ubfiz sbfiz bfi bfxil sxtb sxth sxtw uxtb uxth extr clz rev
    ldr str ldrb strb ldrh strh ldrsb ldrsh ldrsw ldur stur ldurb sturb ldurh sturh ldursb ldursh ldursw ldp stp
    adr adrp b bl cbz cbnz tbz tbnz br blr ret nop brk dmb dsb isb ssbb pssbb dfb
    fmov fadd fsub fmul fdiv fsqrt fneg fabs fcmp fcsel scvtf ucvtf fcvtzs frintm frintp frintz frintn'''.split())


def disassembler_supports(text):
    """Whether text is an instruction of Arm64Disassembler's set: those mnemonics, on X, W and D registers only."""
    if not text:
        return False
    mnemonic, _, operands = text.partition(' ')
    if mnemonic not in DISASM_MNEMONICS and not re.fullmatch(r'b\.(eq|ne|hs|lo|mi|pl|vs|vc|hi|ls|ge|lt|gt|le|al|nv)', mnemonic):
        return False
    if re.search(r'\b([bhsqvzp]\d+|[a-z]+\d*\.)', operands):
        return False
    return not (mnemonic in ('scvtf', 'ucvtf', 'fcvtzs') and '#' in operands)


def disassembly_sample(tmp, rnd, generate, keep, keep_unsupported):
    """[(word, text)]: per class up to keep supported and keep_unsupported other words (text .word) of generate random
    ones; the text is objdump's at offset 4 * index."""
    def random_word(pattern):
        bits = pattern.replace(' ', '')
        assert len(bits) == 32, pattern
        free = int(bits.replace('1', '0').replace('x', '1'), 2)
        w = int(bits.replace('x', '0'), 2) | (rnd.getrandbits(32) & free)
        for lsb, width, value in DISASM_FIELDS:
            mask = ((1 << width) - 1) << lsb
            if free & mask == mask and rnd.random() < 0.12:
                w = (w & ~mask) | (value << lsb)
        if free & 0x1F03E0 == 0x1F03E0 and rnd.random() < 0.15:
            w = (w & ~0x1F0000) | (((w >> 5) & 31) << 16)
        return w

    candidates = []
    for pattern in DISASM_CLASSES:
        words = {}
        for _ in range(4 * generate):
            words[random_word(pattern)] = True
            if len(words) == generate:
                break
        candidates.append(list(words))
    ok, out = assemble(['.word 0x%08x' % w for words in candidates for w in words], tmp)
    if not ok:
        sys.exit('the system assembler rejects .word')
    texts = iter(t for _, _, t in out)
    chosen = []
    for words in candidates:
        good, bad = [], []
        for w in words:
            (good if disassembler_supports(next(texts)) else bad).append(w)
        chosen += good[:keep] + bad[:keep_unsupported]
    ok, out = assemble(['.word 0x%08x' % w for w in chosen], tmp)
    return [(w, t if disassembler_supports(t) else '.word 0x%08x' % w) for _, w, t in out]


def st_string(s):
    return "'" + s.replace("'", "''").replace('!', '!!') + "'"


def main():
    tmp = tempfile.mkdtemp()
    sources = case_sources()
    lines = []
    for s in sources:
        lines.extend(s.split('|'))
    ok, out = assemble(lines, tmp)
    if not ok:
        sys.exit('the system assembler rejects: ' + ', '.join(lines[i] for i in out))
    if len(out) != len(lines):
        sys.exit('objdump answered %d instructions for %d lines' % (len(out), len(lines)))
    cases = []
    i = 0
    for s in sources:
        n = len(s.split('|'))
        cases.append((s, out[i][0], [w for _, w, _ in out[i:i + n]], [t for _, _, t in out[i:i + n]]))
        i += n

    rnd = random.Random(20261024)
    logical = {}
    for width, reg, count in ((64, 'x', 1200), (32, 'w', 600)):
        encodable = logical_values(width)
        sample = sorted(rnd.sample(encodable, count))
        # near misses of encodable values and random values; the assembler decides which are unencodable
        candidates = set()
        while len(candidates) < 400:
            v = rnd.choice(encodable) ^ (1 << rnd.randrange(width)) if rnd.random() < 0.6 else rnd.getrandbits(width)
            candidates.add(v)
        candidates = sorted(candidates)
        ok, bad = assemble(['and %s0, %s1, #0x%x' % (reg, reg, v) for v in candidates], tmp)
        rejected = [candidates[i] for i in bad] if not ok else []
        accepted = sorted(set(sample) | (set(candidates) - set(rejected)))
        ok, out = assemble(['and %s0, %s1, #0x%x' % (reg, reg, v) for v in accepted], tmp)
        if not ok:
            sys.exit('the system assembler rejects encodable logical immediates')
        logical[width] = ([(v, (w >> 10) & 0x1FFF) for v, (_, w, _) in zip(accepted, out)], rejected[:200])

    st = []
    st.append("Object subclass: #Arm64Reference\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Tests-VM'!\n")
    st.append("Arm64Reference comment: 'Generated by tools/arm64-reference.py from the system assembler (cc, objdump). Do not edit.'!\n")
    st.append('!Arm64Reference class methodsFor: \'reference\'!')
    st.append('cases\n\t"{source. offset in the object file. words. objdump text of each word} of each case of Arm64AssemblerCases"\n\t^#(')
    for s, offset, words, texts in cases:
        st.append('\t\t(%s %d (%s) (%s))' % (st_string(s), offset, ' '.join('16r%08X' % w for w in words), ' '.join(st_string(t) for t in texts)))
    st.append('\t)\n!')
    for width in (64, 32):
        pairs, rejected = logical[width]
        st.append('logicalImmediates%d\n\t"value, N:immr:imms, ... (and from the system assembler)"\n\t^#(' % width)
        for k in range(0, len(pairs), 4):
            st.append('\t\t' + ' '.join('16r%X 16r%X' % p for p in pairs[k:k + 4]))
        st.append('\t)\n!')
        st.append('unencodableLogical%d\n\t"values the system assembler rejects as logical immediates"\n\t^#(' % width)
        for k in range(0, len(rejected), 6):
            st.append('\t\t' + ' '.join('16r%X' % v for v in rejected[k:k + 6]))
        st.append('\t)\n!' if width == 32 else '\t)\n!')
    disassembly = disassembly_sample(tmp, rnd, 400, 44, 6)
    st.append('disassembly\n\t"word, objdump text of the word at address 4 * (its index - 1), ... (.word: not in Arm64Disassembler\'s set)"\n\t^#(')
    for k in range(0, len(disassembly), 3):
        st.append('\t\t' + ' '.join('16r%08X %s' % (w, st_string(t)) for w, t in disassembly[k:k + 3]))
    st.append('\t)\n!')
    st[-1] = st[-1] + ' !'
    with open(OUT, 'w') as f:
        f.write('\n'.join(st) + '\n')
    print('%s: %d cases, %d+%d logical immediates, %d+%d unencodable, %d disassembly words' % (
        os.path.relpath(OUT, ROOT), len(cases), len(logical[64][0]), len(logical[32][0]), len(logical[64][1]),
        len(logical[32][1]), len(disassembly)))


if __name__ == '__main__':
    main()
