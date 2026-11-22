#!/usr/bin/env python3
"""Build the raster kernels (gpu/nv/raster.cu) for the GB10 (sm_121) and generate src/System-Devices/NvRasterKernels.st,
which holds the cubin in Base64 and its ABI (entry names, parameter layouts, registers, shared memory, constant banks),
so that building the image never needs nvcc (CI has none). docs/nv-kernels.md describes the kernels and the ABI.

usage: tools/nv-kernels.py build [--nvcc PATH]   compile (nvcc 13.0: -cubin -arch=sm_121 -O3 -fmad=false), regenerate
       tools/nv-kernels.py check [--nvcc PATH]   compile, and fail if the checked-in source is not what that generates
       tools/nv-kernels.py extract CUBIN         write the checked-in cubin to CUBIN (needs no CUDA)
       tools/nv-kernels.py abi [CUBIN]           print the ABI read from gpu/nv/raster_abi.h and a cubin (default: the
                                                 checked-in one)

The parameter layouts come from the structs of gpu/nv/raster_abi.h; each kernel's parameter size and offset in constant
bank 0, register count, frame and stack sizes come from the cubin's .nv.info, its shared memory and constant banks from
its sections. A kernel's parameter size must equal its struct's. Standard library only.
"""
import base64, hashlib, os, re, struct, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'gpu', 'nv', 'raster.cu')
HEADER = os.path.join(ROOT, 'gpu', 'nv', 'raster_abi.h')
OUTPUT = os.path.join(ROOT, 'src', 'System-Devices', 'NvRasterKernels.st')
NVCC = '/usr/local/cuda/bin/nvcc'
FLAGS = ['-cubin', '-arch=sm_121', '-O3', '-fmad=false']
# kernel -> (parameter struct, threads per block it is written for)
KERNELS = [('raster_prims', 'RasterDrawParams', 256), ('raster_tiles', 'RasterDrawParams', 256),
           ('raster_fill', 'RasterFillParams', 256), ('raster_copy', 'RasterCopyParams', 256),
           ('raster_blit', 'RasterBlitParams', 256), ('raster_batch_prims', 'RasterBatchParams', 64),
           ('raster_batch_tiles', 'RasterBatchParams', 256)]
TYPES = {'uint64_t': ('uint64', 8), 'int64_t': ('int64', 8), 'double': ('float64', 8), 'int32_t': ('int32', 4),
         'uint32_t': ('uint32', 4)}
CHUNK = 4096  # Base64 characters per string literal (a multiple of 4: each decodes on its own)


def header_abi():
    """The #defines and the structs of raster_abi.h: {name: value}, {struct: (size, [(field, type, offset, count)])}."""
    text = open(HEADER).read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    defines = {m.group(1): int(m.group(2)) for m in re.finditer(r'#define\s+(\w+)\s+(\d+)\s*$', text, re.M)}
    structs = {}
    for m in re.finditer(r'typedef struct \{(.*?)\}\s*(\w+);', text, re.S):
        fields, offset = [], 0
        for line in m.group(1).split(';'):
            line = line.strip()
            if not line:
                continue
            f = re.fullmatch(r'(\w+)\s+(\w+)(?:\[(\d+)\])?', line)
            if not f or f.group(1) not in TYPES:
                sys.exit('%s: %s: unsupported field %r' % (HEADER, m.group(2), line))
            kind, size = TYPES[f.group(1)]
            count = int(f.group(3) or 1)
            if offset % size:
                sys.exit('%s: %s.%s would be padded' % (HEADER, m.group(2), f.group(2)))
            fields.append((f.group(2), kind, offset, count))
            offset += size * count
        if offset % 8:
            sys.exit('%s: %s is not a multiple of 8 bytes' % (HEADER, m.group(2)))
        structs[m.group(2)] = (offset, fields)
    return defines, structs


def elf_sections(data):
    """{name: (type, offset, size, link, info)} and the symbols [(name, value, size, info, shndx)] of an ELF64 file."""
    if data[:4] != b'\x7fELF' or data[4] != 2:
        sys.exit('not an ELF64 cubin')
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    raw = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    names = raw[shstrndx]
    def name_at(table, off):
        start = table[4] + off
        return data[start:data.index(b'\0', start)].decode()
    sections, by_index = {}, []
    for s in raw:
        n = name_at(names, s[0])
        sections[n] = (s[1], s[4], s[5], s[6], s[7])
        by_index.append(n)
    symbols = []
    symtab = sections.get('.symtab')
    if symtab:
        strtab = raw[symtab[3]]
        for off in range(symtab[1], symtab[1] + symtab[2], 24):
            nm, info, other, shndx, value, size = struct.unpack_from('<IBBHQQ', data, off)
            symbols.append((name_at(strtab, nm), value, size, info, shndx))
    return sections, symbols, by_index


def nv_info(data, section):
    """The attributes of an .nv.info section: [(attribute, value bytes)]. An entry: a format byte, an attribute byte,
    then 2 bytes (formats 1-3: none, byte, half) or a 2-byte size and that many bytes (format 4)."""
    _, off, size, _, _ = section
    out, i = [], off
    while i < off + size:
        fmt, attr = data[i], data[i + 1]
        i += 2
        if fmt in (1, 2, 3):  # none, a byte, a half: each in two bytes (entries are 4-byte units)
            value, i = data[i:i + 2], i + 2
        elif fmt == 4:
            n, = struct.unpack_from('<H', data, i)
            value, i = data[i + 2:i + 2 + n], i + 2 + n
        else:
            sys.exit('unknown .nv.info format %d' % fmt)
        out.append((attr, value))
    return out


EIATTR_PARAM_CBANK, EIATTR_FRAME_SIZE, EIATTR_MIN_STACK_SIZE, EIATTR_CBANK_PARAM_SIZE = 0x0a, 0x11, 0x12, 0x19
EIATTR_MAX_STACK_SIZE, EIATTR_REGCOUNT = 0x23, 0x2f


def cubin_abi(data):
    """Each kernel's {entry, registers, frame, stack, shared, paramOffset, paramBytes, constantBank0Bytes, constantBank2}."""
    sections, symbols, by_index = elf_sections(data)
    index_of = {s[0]: i for i, s in enumerate(symbols)}
    per_symbol = {}
    for attr, value in nv_info(data, sections['.nv.info']):
        if attr in (EIATTR_REGCOUNT, EIATTR_FRAME_SIZE, EIATTR_MIN_STACK_SIZE, EIATTR_MAX_STACK_SIZE) and len(value) == 8:
            sym, v = struct.unpack('<II', value)
            per_symbol.setdefault(sym, {})[attr] = v
    kernels = {}
    for name, params, block in KERNELS:
        if '.text.' + name not in sections:
            sys.exit('the cubin has no kernel %s' % name)
        attrs = per_symbol.get(index_of[name], {})
        info = nv_info(data, sections['.nv.info.' + name])
        cbank = [v for a, v in info if a == EIATTR_PARAM_CBANK]
        psize = [v for a, v in info if a == EIATTR_CBANK_PARAM_SIZE]
        if len(cbank) != 1 or len(psize) != 1:
            sys.exit('%s: no single parameter bank in .nv.info' % name)
        _, off_and_size = struct.unpack('<II', cbank[0])
        c2 = sections.get('.nv.constant2.' + name)
        kernels[name] = {
            'entry': name, 'params': params, 'block': block,
            'registers': attrs.get(EIATTR_REGCOUNT, 0), 'frameBytes': attrs.get(EIATTR_FRAME_SIZE, 0),
            'stackBytes': max(attrs.get(EIATTR_MIN_STACK_SIZE, 0), attrs.get(EIATTR_MAX_STACK_SIZE, 0)),
            # the CTA's static shared memory, with the 1 KB sm_90 and later reserve in every CTA (docs/nv.md)
            'sharedBytes': sections['.nv.shared.' + name][2] if '.nv.shared.' + name in sections else 0x400,
            'paramOffset': off_and_size & 0xFFFF, 'paramBytes': off_and_size >> 16,
            'constantBank0Bytes': sections['.nv.constant0.' + name][2],
            'constantBank2': data[c2[1]:c2[1] + c2[2]] if c2 else None,
            'textBytes': sections['.text.' + name][2],
        }
        if struct.unpack('<H', psize[0])[0] != kernels[name]['paramBytes']:
            sys.exit('%s: the parameter sizes in .nv.info disagree' % name)
    return kernels


def check_abi(defines, structs, kernels):
    for k in kernels.values():
        size = structs[k['params']][0]
        if k['paramBytes'] != size:
            sys.exit('%s: %d parameter bytes in the cubin, %s is %d' % (k['entry'], k['paramBytes'], k['params'], size))


def st_string(s):
    return "'" + s.replace("'", "''") + "'"


def st_literal(v):
    if v is None:
        return 'nil'
    if isinstance(v, bytes):
        return '#[' + ' '.join(str(b) for b in v) + ']'
    if isinstance(v, str):
        return st_string(v)
    return str(v)


def generate(cubin, nvcc_version):
    defines, structs = header_abi()
    kernels = cubin_abi(cubin)
    check_abi(defines, structs, kernels)
    b64 = base64.b64encode(cubin).decode()
    digest = hashlib.sha256(cubin).hexdigest()
    source_digest = hashlib.sha256(open(SOURCE, 'rb').read() + open(HEADER, 'rb').read()).hexdigest()
    L = []
    L.append("Object subclass: #NvRasterKernels")
    L.append("\tinstanceVariableNames: ''")
    L.append("\tclassVariableNames: 'Cubin'")
    L.append("\tpackage: 'System-Devices'!")
    L.append("")
    L.append("NvRasterKernels comment: " + st_string(
        "I am generated by tools/nv-kernels.py from gpu/nv/raster.cu and gpu/nv/raster_abi.h (SHA-256 of the two %s) with "
        "%s (%s); do not edit me, regenerate me (docs/nv-kernels.md). I hold the raster kernels: PlatformRaster's work "
        "(SoftwareRaster: the Renderer's uber-shader on a draw's vertices, fills, blits, copies) as CUDA kernels for the "
        "NVIDIA GB10 (sm_121), bit-exact with the C reference without floating-point contraction, and their ABI, for a "
        "launcher that loads the cubin itself (no CUDA libraries).\n\n"
        "\tNvRasterKernels cubin                         \"the ELF image: %d bytes, SHA-256 %s\"\n"
        "\tNvRasterKernels kernel: 'raster_tiles'        \"its entry, parameter struct, registers, shared memory, constant banks\"\n"
        "\tNvRasterKernels params: #RasterDrawParams with: {#pixels -> a. #width -> 1920. ...}   \"the parameter bytes\"\n\n"
        "A draw is raster_prims then raster_tiles with the same RasterDrawParams; fills, copies and blits are one launch "
        "each. Parameters go into constant bank 0 at the kernel's paramOffset; a kernel with constantBank2 needs those bytes "
        "bound as constant bank 2. Grids and blocks: docs/nv-kernels.md."
        % (source_digest[:16], ' '.join(['nvcc'] + FLAGS), nvcc_version, len(cubin), digest)) + "!")
    L.append("")
    L.append("!NvRasterKernels class methodsFor: 'cubin'!")
    L.append("cubin")
    L.append('\t"The kernels\' ELF image (decoded once)."')
    L.append("\t| out |")
    L.append("\tCubin isNil ifTrue: [")
    L.append("\t\tout := WriteStream on: (ByteArray new: self cubinSize).")
    L.append("\t\tself cubinBase64 do: [:each | out nextPutAll: (Base64 decode: each)].")
    L.append("\t\tCubin := out contents].")
    L.append("\t^Cubin")
    L.append("!")
    L.append("cubinSize")
    L.append("\t^%d" % len(cubin))
    L.append("!")
    L.append("cubinSHA256")
    L.append("\t^%s" % st_string(digest))
    L.append("!")
    L.append("cubinBase64")
    L.append('\t"The cubin in Base64, in pieces of %d characters."' % CHUNK)
    L.append("\t^#(")
    for i in range(0, len(b64), CHUNK):
        L.append("\t\t" + st_string(b64[i:i + CHUNK]))
    L.append("\t)")
    L.append("! !")
    L.append("")
    L.append("!NvRasterKernels class methodsFor: 'abi'!")
    L.append("kernelNames")
    L.append("\t^#(%s)" % ' '.join(st_string(k[0]) for k in KERNELS))
    L.append("!")
    L.append("kernel: aString")
    L.append('\t"The kernel named aString: a Dictionary of entry (its symbol), params (the name of its parameter struct), '
             'block (the threads per block it is written for), registers, frameBytes and stackBytes (per thread: local '
             'memory), sharedBytes (the static shared memory a block needs, the 1 KB sm_90 and later reserve included), paramOffset and '
             'paramBytes (its parameters in constant bank 0), constantBank0Bytes (the bank\'s size), constantBank2 (bytes '
             'to bind as constant bank 2, or nil), textBytes."')
    L.append("\t| d |")
    L.append("\td := Dictionary new.")
    for name, _, _ in KERNELS:
        k = kernels[name]
        L.append("\taString = %s ifTrue: [" % st_string(name))
        keys = ['entry', 'params', 'block', 'registers', 'frameBytes', 'stackBytes', 'sharedBytes',
                'paramOffset', 'paramBytes', 'constantBank0Bytes', 'constantBank2', 'textBytes']
        L.append("\t\td " + ";\n\t\t\t".join("at: #%s put: %s" % (key, st_literal(k.get(key, 0))) for key in keys) + ".")
        L.append("\t\t^d].")
    L.append("\t^self error: 'no raster kernel ', aString printString")
    L.append("!")
    L.append("structNames")
    L.append("\t^#(%s)" % ' '.join('#' + s for s in sorted(structs)))
    L.append("!")
    L.append("layoutOf: aSymbol")
    L.append('\t"The fields of the parameter struct aSymbol (raster_abi.h): {name. type (#uint64 #int64 #float64 #int32 '
             '#uint32). byte offset. count}."')
    for s in sorted(structs):
        size, fields = structs[s]
        L.append("\taSymbol = #%s ifTrue: [^#(%s)]." % (
            s, ' '.join('#(#%s #%s %d %d)' % (f, t, o, c) for f, t, o, c in fields)))
    L.append("\t^self error: 'no parameter struct ', aSymbol printString")
    L.append("!")
    L.append("sizeOf: aSymbol")
    for s in sorted(structs):
        L.append("\taSymbol = #%s ifTrue: [^%d]." % (s, structs[s][0]))
    L.append("\t^self error: 'no parameter struct ', aSymbol printString")
    L.append("!")
    for d in sorted(defines):
        sel = d[len('RASTER_'):].lower() if d.startswith('RASTER_') else d.lower()
        sel = re.sub(r'_(\w)', lambda m: m.group(1).upper(), sel)
        L.append(sel)
        L.append("\t\"%s (raster_abi.h).\"" % d)
        L.append("\t^%d" % defines[d])
        L.append("!")
    L.append("drawScratchBytes: vertexCount")
    L.append('\t"The scratch a draw of vertexCount vertices needs (RasterDrawParams prims)."')
    L.append("\t^self scratchHeader + (self primBytes * (vertexCount // 3))")
    L.append("! !")
    L.append("")
    L.append("!NvRasterKernels class methodsFor: 'parameters'!")
    L.append("params: aSymbol with: associations")
    L.append('\t"The bytes of the parameter struct aSymbol with the fields named in associations (field -> value; an array '
             'field takes an Array); the others zero. Integers as two\'s complement, floats as IEEE doubles, booleans 0 or 1."')
    L.append("\t| bytes values |")
    L.append("\tbytes := ByteArray new: (self sizeOf: aSymbol).")
    L.append("\tvalues := Dictionary new.")
    L.append("\tassociations do: [:a | values at: a key put: a value].")
    L.append("\t(self layoutOf: aSymbol) do: [:f |")
    L.append("\t\t(values includesKey: f first) ifTrue: [")
    L.append("\t\t\t| v |")
    L.append("\t\t\tv := values removeKey: f first.")
    L.append("\t\t\t(f at: 4) = 1")
    L.append("\t\t\t\tifTrue: [self put: v type: (f at: 2) at: (f at: 3) into: bytes]")
    L.append("\t\t\t\tifFalse: [")
    L.append("\t\t\t\t\tv size = (f at: 4) ifFalse: [^self error: f first , ' takes ' , (f at: 4) printString , ' values'].")
    L.append("\t\t\t\t\tv doWithIndex: [:x :i | self put: x type: (f at: 2) at: (f at: 3) + ((i - 1) * ((f at: 2) == #int32 | ((f at: 2) == #uint32) ifTrue: [4] ifFalse: [8])) into: bytes]]]].")
    L.append("\tvalues isEmpty ifFalse: [^self error: aSymbol , ' has no field ' , values keys asArray first printString].")
    L.append("\t^bytes")
    L.append("!")
    L.append("put: aValue type: aType at: offset into: bytes")
    L.append('\t"Store aValue as aType at the 0-based byte offset of bytes."')
    L.append("\t| v |")
    L.append("\taType == #float64 ifTrue: [^bytes float64At: offset + 1 put: aValue asFloat].")
    L.append("\tv := aValue == true ifTrue: [1] ifFalse: [aValue == false ifTrue: [0] ifFalse: [aValue]].")
    L.append("\tbytes uint32At: offset + 1 put: (v bitAnd: 16rFFFFFFFF).")
    L.append("\t(aType == #int32 or: [aType == #uint32]) ifFalse: [bytes uint32At: offset + 5 put: ((v bitShift: -32) bitAnd: 16rFFFFFFFF)]")
    L.append("! !")
    return '\n'.join(L) + '\n'


def compile_cubin(nvcc):
    out = tempfile.NamedTemporaryFile(suffix='.cubin', delete=False).name
    subprocess.run([nvcc] + FLAGS + ['-o', out, SOURCE], check=True, cwd=os.path.dirname(SOURCE))
    data = open(out, 'rb').read()
    os.unlink(out)
    version = subprocess.run([nvcc, '--version'], capture_output=True, text=True).stdout.strip().splitlines()[-1]
    return data, version


def checked_in_cubin():
    text = open(OUTPUT).read()
    m = re.search(r'^cubinBase64\n.*?\^#\((.*?)\)', text, re.S | re.M)
    if not m:
        sys.exit('%s: no cubinBase64' % OUTPUT)
    return base64.b64decode(''.join(re.findall(r"'([^']*)'", m.group(1))))


def print_abi(cubin):
    defines, structs = header_abi()
    kernels = cubin_abi(cubin)
    check_abi(defines, structs, kernels)
    for name, k in kernels.items():
        print('%s: %s (%d bytes at c[0x0][0x%x]), %d registers, frame %d, stack %d, shared %d, cbank0 %d, cbank2 %s, text %d' % (
            name, k['params'], k['paramBytes'], k['paramOffset'], k['registers'], k['frameBytes'], k['stackBytes'],
            k['sharedBytes'], k['constantBank0Bytes'], len(k['constantBank2']) if k['constantBank2'] else '-', k['textBytes']))
    for s in sorted(structs):
        size, fields = structs[s]
        print('%s (%d bytes): %s' % (s, size, ', '.join('%s %s@%d%s' % (t, f, o, '[%d]' % c if c > 1 else '') for f, t, o, c in fields)))


def main(argv):
    nvcc = NVCC
    if '--nvcc' in argv:
        i = argv.index('--nvcc')
        nvcc = argv[i + 1]
        del argv[i:i + 2]
    cmd = argv[1] if len(argv) > 1 else ''
    if cmd == 'build':
        cubin, version = compile_cubin(nvcc)
        open(OUTPUT, 'w', newline='\n').write(generate(cubin, version))
        print('%s: %d-byte cubin (%s)' % (os.path.relpath(OUTPUT, ROOT), len(cubin), version))
    elif cmd == 'check':
        cubin, version = compile_cubin(nvcc)
        if generate(cubin, version) != open(OUTPUT).read():
            sys.exit('%s is not what gpu/nv generates: run tools/nv-kernels.py build' % os.path.relpath(OUTPUT, ROOT))
        print('%s is up to date' % os.path.relpath(OUTPUT, ROOT))
    elif cmd == 'extract' and len(argv) == 3:
        cubin = checked_in_cubin()
        open(argv[2], 'wb').write(cubin)
        print('%s: %d bytes, SHA-256 %s' % (argv[2], len(cubin), hashlib.sha256(cubin).hexdigest()))
    elif cmd == 'abi':
        print_abi(open(argv[2], 'rb').read() if len(argv) > 2 else checked_in_cubin())
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
