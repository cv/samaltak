#!/usr/bin/env python3
"""Reference x86-64 encodings for the tests, from GNU as and objdump (binutils): writes src/Tests-VM/Amd64Reference.st.

Cases: the case: strings of src/Tests-VM/Amd64AssemblerCases.st (Intel syntax, instructions separated by |, a part
'1:' a local label), assembled with as --64 -msyntax=intel -mnaked-reg; each instruction's bytes and the text
objdump -d -M intel prints for it.
Disassembly: random instructions of every opcode Amd64Disassembler decodes, with random 66 and REX prefixes (unused
REX bits too), ModRM, SIB, displacements and immediates, each at its own address (two address ranges, one near 0 so
that targets wrap), with objdump's text; .byte 0x.. (its first byte) where objdump shows that the instruction does not
use a prefix it has (data16 ...) or does not decode it.
usage: tools/amd64-reference.py   (from the repository root; needs as and objdump for x86-64)
"""
import os
import random
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES = os.path.join(ROOT, 'src/Tests-VM/Amd64AssemblerCases.st')
OUT = os.path.join(ROOT, 'src/Tests-VM/Amd64Reference.st')
LABEL = re.compile(r'\d+:$')


def case_sources():
    text = open(CASES).read()
    return [m.group(1).replace("''", "'").replace('!!', '!') for m in re.finditer(r"case: '((?:[^']|'')*)' emit:", text)]


def objdump_lines(text, base=0):
    """(offset, bytes, text) of each instruction objdump printed (one line each: --insn-width=16)"""
    out = []
    for line in text.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\t([0-9a-f ]+?)\s*(?:\t(.*))?$', line)
        if m:
            out.append((int(m.group(1), 16) - base, bytes.fromhex(m.group(2).replace(' ', '')), (m.group(3) or '').rstrip()))
    return out


def assemble(lines, tmp):
    """Assemble lines; answer (ok, output): output is the list of (offset, bytes, text) or the error lines (1-based)."""
    src = os.path.join(tmp, 'ref.s')
    obj = os.path.join(tmp, 'ref.o')
    with open(src, 'w') as f:
        f.write('.text\n')
        for line in lines:
            f.write(line + '\n')
    r = subprocess.run(['as', '--64', '-msyntax=intel', '-mnaked-reg', '-o', obj, src], capture_output=True, text=True)
    if r.returncode != 0:
        return False, sorted({int(m.group(1)) - 1 for m in re.finditer(r'ref\.s:(\d+): Error', r.stderr)})
    dump = subprocess.run(['objdump', '-d', '-z', '-M', 'intel', '--insn-width=16', obj], capture_output=True, text=True,
                          check=True).stdout
    return True, objdump_lines(dump)


# The opcodes of the disassembler: (opcode bytes, ModRM ('any' or 'mem': register-direct too or not; None: none), reg
# field (None: random, an int, or a tuple to choose from), immediate (None 'b' 'w' 'd'; 'z' 2 or 4 bytes, 'v' 2, 4 or 8
# by the operand size), whether a 66 prefix may come before it, its mandatory prefix (66 F2 F3) or None.
def templates():
    t = []
    for op in range(0x40):
        if op & 7 < 4:
            t.append(([op], 'any', None, None, op & 1 == 1, None))
        elif op & 7 == 4:
            t.append(([op], None, None, 'b', False, None))
        elif op & 7 == 5:
            t.append(([op], None, None, 'z', True, None))
    t += [([0x50 + r], None, None, None, False, None) for r in range(8)]
    t += [([0x58 + r], None, None, None, False, None) for r in range(8)]
    t += [([0x63], 'any', None, None, True, None)]
    t += [([0x68], None, None, 'd', False, None), ([0x6a], None, None, 'b', False, None)]
    t += [([0x69], 'any', None, 'z', True, None), ([0x6b], 'any', None, 'b', True, None)]
    t += [([0x70 + c], None, None, 'b', False, None) for c in range(16)]
    t += [([0x80], 'any', None, 'b', False, None), ([0x81], 'any', None, 'z', True, None), ([0x83], 'any', None, 'b', True, None)]
    t += [([0x84], 'any', None, None, False, None), ([0x85], 'any', None, None, True, None)]
    t += [([0x86], 'any', None, None, False, None), ([0x87], 'any', None, None, True, None)]
    t += [([op], 'any', None, None, op & 1 == 1, None) for op in (0x88, 0x89, 0x8a, 0x8b)]
    t += [([0x8d], 'mem', None, None, True, None)]
    t += [([0x8f], 'any', 0, None, False, None)]
    t += [([0x90 + r], None, None, None, True, None) for r in range(8)]
    t += [([0x98], None, None, None, True, None), ([0x99], None, None, None, True, None)]
    t += [([0xa8], None, None, 'b', False, None), ([0xa9], None, None, 'z', True, None)]
    t += [([0xb0 + r], None, None, 'b', False, None) for r in range(8)]
    t += [([0xb8 + r], None, None, 'v', True, None) for r in range(8)]
    t += [([0xc0], 'any', None, 'b', False, None), ([0xc1], 'any', None, 'b', True, None)]
    t += [([0xc2], None, None, 'w', False, None), ([0xc3], None, None, None, False, None)]
    t += [([0xc6], 'any', 0, 'b', False, None), ([0xc7], 'any', 0, 'z', True, None)]
    t += [([0xcc], None, None, None, False, None)]
    t += [([0xd0], 'any', None, None, False, None), ([0xd1], 'any', None, None, True, None)]
    t += [([0xd2], 'any', None, None, False, None), ([0xd3], 'any', None, None, True, None)]
    t += [([0xe8], None, None, 'd', False, None), ([0xe9], None, None, 'd', False, None), ([0xeb], None, None, 'b', False, None)]
    t += [([0xf6], 'any', (0, 1), 'b', False, None), ([0xf6], 'any', (2, 3, 4, 5, 6, 7), None, False, None)]
    t += [([0xf7], 'any', (0, 1), 'z', True, None), ([0xf7], 'any', (2, 3, 4, 5, 6, 7), None, True, None)]
    t += [([0xfe], 'any', (0, 1), None, False, None)]
    t += [([0xff], 'any', (0, 1), None, True, None), ([0xff], 'any', (2, 4, 6), None, False, None)]
    t += [([0x0f, 0x0b], None, None, None, False, None)]
    t += [([0x0f, op], 'any', None, None, False, p) for op in (0x10, 0x11) for p in (0xf2, 0x66)]
    t += [([0x0f, 0x1f], 'any', None, None, True, None)]
    t += [([0x0f, op], 'any', None, None, False, 0x66) for op in (0x28, 0x29, 0x2e, 0x2f, 0x54, 0x55, 0x56, 0x57, 0x6e, 0x7e, 0xd6)]
    t += [([0x0f, op], 'any', None, None, False, 0xf2) for op in (0x2a, 0x2c, 0x2d, 0x51, 0x58, 0x59, 0x5c, 0x5d, 0x5e, 0x5f)]
    t += [([0x0f, 0x7e], 'any', None, None, False, 0xf3)]
    t += [([0x0f, 0x40 + c], 'any', None, None, True, None) for c in range(16)]
    t += [([0x0f, 0x80 + c], None, None, 'd', False, None) for c in range(16)]
    t += [([0x0f, 0x90 + c], 'any', None, None, False, None) for c in range(16)]
    t += [([0x0f, op], 'any', None, None, True, None) for op in (0xa3, 0xab, 0xb3, 0xbb, 0xaf, 0xb6, 0xb7, 0xbe, 0xbf)]
    t += [([0x0f, 0xba], 'any', (4, 5, 6, 7), 'b', True, None)]
    return t


def le(value, n):
    return [(value >> (8 * i)) & 0xff for i in range(n)]


def random_immediate(rnd, n):
    special = {1: [0, 1, 0x7f, 0x80, 0xff], 2: [0, 0x7fff, 0x8000, 0xffff],
               4: [0, 1, 0x7fffffff, 0x80000000, 0xffffffff, 0xfffffff0],
               8: [0, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff, 0x100000000]}[n]
    if rnd.random() < 0.3:
        return le(rnd.choice(special), n)
    return [rnd.randrange(256) for _ in range(n)]


def random_operand(rnd, kind, reg3):
    """ModRM, SIB and displacement bytes of a random r/m operand: a register (only for 'any'), or memory of every form"""
    if kind == 'any' and rnd.random() < 0.3:
        return [0xc0 | (reg3 << 3) | rnd.randrange(8)]
    mod = rnd.choice([0, 0, 1, 2])
    rm = rnd.choice([0, 1, 2, 3, 4, 4, 4, 5, 5, 6, 7])
    out = [(mod << 6) | (reg3 << 3) | rm]
    base = None
    if rm == 4:
        base = rnd.choice([0, 1, 2, 3, 4, 4, 5, 5, 6, 7])
        out.append((rnd.randrange(4) << 6) | (rnd.choice([0, 1, 2, 3, 4, 4, 5, 6, 7]) << 3) | base)
    if mod == 1:
        out += random_immediate(rnd, 1)
    elif mod == 2 or (mod == 0 and (rm == 5 or base == 5)):
        out += random_immediate(rnd, 4)
    return out


def random_instruction(rnd, template):
    ops, modrm, regfield, imm, p66, mandatory = template
    prefixes = [mandatory] if mandatory else [0x66] if p66 and rnd.random() < 0.2 else []
    rex = 0
    if rnd.random() < 0.55:
        rex = 0x40 | rnd.randrange(16)
        if rnd.random() < 0.5:
            rex &= 0x4f if rnd.random() < 0.5 else 0x48
    out = prefixes + ([rex] if rex else []) + list(ops)
    if modrm:
        reg3 = rnd.randrange(8) if regfield is None else rnd.choice(regfield) if isinstance(regfield, tuple) else regfield
        out += random_operand(rnd, modrm, reg3)
    w = rex & 8
    o16 = 0x66 in prefixes and not w
    size = {None: 0, 'b': 1, 'w': 2, 'd': 4, 'z': 2 if o16 else 4, 'v': 8 if w else 2 if o16 else 4}[imm]
    return out + (random_immediate(rnd, size) if size else [])


def disassembly_sample(tmp, rnd, count):
    """[(bytes, address, text)]: count random instructions of each template, half from a high address, half from 0;
    each in a 16-byte slot (int3 after it), objdump's text, .byte where objdump does not decode it or shows a prefix
    the instruction does not use; dropped where objdump decodes another length"""
    instructions = [random_instruction(rnd, t) for _ in range(count) for t in templates()]
    rnd.shuffle(instructions)
    sample = []
    half = len(instructions) // 2
    for vma, part in ((0x7f3a5c201000, instructions[:half]), (0, instructions[half:])):
        path = os.path.join(tmp, 'sample.bin')
        with open(path, 'wb') as f:
            for insn in part:
                f.write(bytes(insn) + b'\xcc' * (16 - len(insn)))
        dump = subprocess.run(['objdump', '-D', '-z', '-b', 'binary', '-m', 'i386:x86-64', '-M', 'intel',
                               '--insn-width=16', '--adjust-vma=0x%x' % vma, path], capture_output=True, text=True,
                              check=True).stdout
        decoded = {offset: (data, text) for offset, data, text in objdump_lines(dump, vma)}
        for i, insn in enumerate(part):
            data, text = decoded.get(16 * i, (b'', ''))
            if data != bytes(insn):
                continue
            if (re.match(r'(data16|repz|repnz|rex(\.[WRXB]+)?$)', text) or '(bad)' in text):
                text = '.byte 0x%02x' % insn[0]
            sample.append((bytes(insn), vma + 16 * i, text))
    return sample


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
        sys.exit('as rejects: ' + ', '.join(lines[i - 1] for i in out))
    counts = [sum(1 for part in s.split('|') if not LABEL.match(part)) for s in sources]
    if len(out) != sum(counts):
        sys.exit('objdump answered %d instructions for %d' % (len(out), sum(counts)))
    cases = []
    i = 0
    for s, n in zip(sources, counts):
        cases.append((s, out[i][0], [(data, text) for _, data, text in out[i:i + n]]))
        i += n
    disassembly = disassembly_sample(tmp, random.Random(20261114), 6)

    st = []
    st.append("Object subclass: #Amd64Reference\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Tests-VM'!\n")
    st.append("Amd64Reference comment: 'Generated by tools/amd64-reference.py from GNU as and objdump -M intel. Do not edit.'!\n")
    st.append("!Amd64Reference class methodsFor: 'reference'!")
    st.append('cases\n\t"{source. offset in the object file. {bytes in hex. objdump text} of each instruction} of each case of '
              'Amd64AssemblerCases"\n\t^#(')
    for s, offset, insns in cases:
        st.append('\t\t(%s %d (%s))' % (st_string(s), offset, ' '.join('%s %s' % (st_string(d.hex()), st_string(t)) for d, t in insns)))
    st.append('\t)\n!')
    st.append('disassembly\n\t"bytes in hex, address, objdump text, ... (.byte: objdump decodes no instruction, or shows a '
              'prefix the instruction does not use)"\n\t^#(')
    for data, address, text in disassembly:
        st.append('\t\t%s 16r%X %s' % (st_string(data.hex()), address, st_string(text)))
    st.append('\t)\n! !')
    with open(OUT, 'w') as f:
        f.write('\n'.join(st) + '\n')
    print('%s: %d cases (%d instructions), %d disassembly instructions' % (
        os.path.relpath(OUT, ROOT), len(cases), sum(counts), len(disassembly)))


if __name__ == '__main__':
    main()
