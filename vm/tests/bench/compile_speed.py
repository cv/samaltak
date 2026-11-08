#!/usr/bin/env python3
"""Compile-speed corpus and reports (docs/benchmarks.md, Compile speed).

gen OUTDIR [KEEP]   every method of the AWFY benchmark classes as a probe with an early exit: the same sources on both
                    systems. pNx: probeNil k1: a ... probeNil ifNil: [^0]. <the real body>, sent with nil, runs in O(1)
                    while the JIT compiles every bytecode. Writes OUTDIR/Probes.st (probes and the driver, K timed sends
                    per probe) and OUTDIR/{Samaltak,Pharo}.st. KEEP: a file of probe indices to generate only those.
noblock S P         the probe indices (of a full round's output S, Samaltak, and P, Pharo) without real blocks on either side.
report DIR          the per-round summary and the table of the rounds in DIR (named corpus-config-round.out).
report-awfy FILE... first-iteration compile share from awfy.sh -n 1 outputs (named config-round.out).
"""
import re
import statistics as st
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
AWFY = HERE / "awfy"
FILES = "Core Bounce CD DeltaBlue Havlak Json List Mandelbrot NBody Permute Queens Richards Sieve Storage Towers".split()
K = 6  # sends per probe: Cog compiles at the 2nd, Samaltak at the 3rd (opt eager: both tiers then)
CHUNK = 50  # probes per driver method: over Cog's 60-literal limit, so that the drivers stay interpreted
GUARD = "probeNil ifNil: [ ^ 0 ].\n\t"

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
BINARY = re.compile(r"[-+*/\\~<>=@%|&?,]+")


def chunks(text):
    """The chunks of a chunk-format file; '!!' is a literal '!'."""
    out, buf, i = [], [], 0
    while i < len(text):
        c = text[i]
        if c == "!":
            if i + 1 < len(text) and text[i + 1] == "!":
                buf.append("!")
                i += 2
                continue
            out.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    out.append("".join(buf))
    return out


def skip(src, i):
    """i past whitespace and comments."""
    while i < len(src):
        if src[i].isspace():
            i += 1
        elif src[i] == '"':
            j = src.find('"', i + 1)
            i = len(src) if j < 0 else j + 1
        else:
            break
    return i


def pattern(src):
    """Parse a method's message pattern: (keywords, args, index after the pattern)."""
    i = skip(src, 0)
    m = IDENT.match(src, i)
    if m and m.end() < len(src) and src[m.end()] == ":":  # keyword message
        keys, args = [], []
        while True:
            m = IDENT.match(src, i)
            if not (m and m.end() < len(src) and src[m.end()] == ":"):
                break
            keys.append(src[i : m.end() + 1])
            i = skip(src, m.end() + 1)
            a = IDENT.match(src, i)
            args.append(a.group())
            i = skip(src, a.end())
        return keys, args, i
    if m:  # unary
        return [m.group()], [], m.end()
    b = BINARY.match(src, i)  # binary
    i2 = skip(src, b.end())
    a = IDENT.match(src, i2)
    return [b.group()], [a.group()], a.end()


def body_start(src, i):
    """The index of the first statement: past temporaries and pragmas after the pattern."""
    while True:
        i = skip(src, i)
        if src.startswith("|", i):
            j = src.find("|", i + 1)
            i = j + 1
        elif src.startswith("<", i) and re.match(r"<\s*[A-Za-z_]\w*[: >]", src[i:]):
            i = src.find(">", i + 1) + 1
        else:
            return i


def parse_file(path):
    """(class name, class side?, category, method source) of the methods of an AWFY chunk file."""
    methods = []
    state = None  # (class, meta, category) while reading a method list
    for c in chunks(path.read_text()):
        s = c.strip()
        if state is not None:
            if s == "":
                state = None
            else:
                methods.append((state[0], state[1], state[2], c.strip("\n")))
            continue
        m = re.match(r"(\w+)( class)? methodsFor: '([^']*)'$", s)
        if m:
            state = (m.group(1), m.group(2) is not None, m.group(3))
    return methods


def escape(src):
    return src.replace("!", "!!")


def sym(s):
    return "#" + (s if re.fullmatch(r"[A-Za-z0-9_:]+", s) else "'" + s.replace("'", "''") + "'")


def gen(outdir, keep=None):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    keep = None if keep is None else {int(x) for x in Path(keep).read_text().split()}
    probes, bodies = [], {}
    for f in FILES:
        for cls, meta, cat, src in parse_file(AWFY / f"{f}.st"):
            n = len(probes)
            if keep is not None and n not in keep:
                probes.append(None)  # keeps the full corpus's numbering
                continue
            keys, args, end = pattern(src)
            selector = "".join(keys)
            start = body_start(src, end)
            psel = f"p{n}x:" + "".join(f"k{j}:" for j in range(1, len(args) + 1))
            head = f"p{n}x: probeNil" + "".join(f" k{j}: {a}" for j, a in enumerate(args, 1))
            new = head + src[end:start] + ("\n\t" if not src[end:start].endswith("\t") else "") + GUARD + src[start:]
            probes.append((n, cls, meta, selector, psel, len(args), f))
            bodies.setdefault((cls, meta), []).append(new)
    live = [p for p in probes if p is not None]
    out = [
        "Object subclass: #CompileSpeedDriver\n"
        "\tinstanceVariableNames: ''\n"
        "\tclassVariableNames: 'Times Pos CodeSizes'\n"
        "\tpackage: 'AWFY'!\n\n"
    ]
    for (cls, meta), srcs in bodies.items():
        out.append(f"!{cls}{' class' if meta else ''} methodsFor: 'probe'!\n")
        out.extend(escape(s) + "\n!\n" for s in srcs)
        out.append(" !\n\n")
    out.append("!CompileSpeedDriver class methodsFor: 'table'!\ntable\n\t^#(")
    for n, cls, meta, sel, psel, _, f in live:
        out.append(f"\n\t\t#({n} #{cls} {'true' if meta else 'false'} {sym(sel)} {sym(psel)} {sym(f)})")
    out.append(")\n! !\n\n!CompileSpeedDriver class methodsFor: 'driving'!\n")
    # send every probe K times from interpreted drivers, timing each send
    nchunks = 0
    for start in range(0, len(live), CHUNK):
        out.append(f"chunk{nchunks}\n\t| t |\n")
        for n, cls, meta, sel, psel, nargs, f in live[start : start + CHUNK]:
            call = (cls if meta else f"{cls} basicNew") + f" p{n}x: nil" + "".join(f" k{a}: nil" for a in range(1, nargs + 1))
            for _ in range(K):
                out.append(f"\tt := AwfyPlatform microseconds. {call}. Times at: (Pos := Pos + 1) put: AwfyPlatform microseconds - t.\n")
        out.append("!\n")
        nchunks += 1
    out.append(f"runAll\n\tTimes := Array new: {len(live) * K}.\n\tPos := 0.")
    out.extend(f"\n\tself chunk{c}." for c in range(nchunks))
    out.append("\n!\n")
    out.append(
        "reportTimes\n"
        "\t\"One line per probe: its number and the K send times in microseconds.\"\n"
        "\t| t s |\n"
        "\tt := self table.\n"
        "\tt doWithIndex: [:row :i |\n"
        "\t\ts := WriteStream on: String new.\n"
        "\t\ts nextPutAll: 'probe,'; print: (row at: 1).\n"
        f"\t\t1 to: {K} do: [:k | s nextPut: $,; print: (Times at: i - 1 * {K} + k)].\n"
        "\t\tScriptConsole println: s contents]\n"
        "!\n"
        "reportMethods\n"
        "\t\"One line per probe: number, class, side, benchmark file, then what describe: answers.\"\n"
        "\t| t s cls m |\n"
        "\tt := self table.\n"
        "\tt do: [:row |\n"
        "\t\tcls := Smalltalk at: (row at: 2).\n"
        "\t\t(row at: 3) ifTrue: [cls := cls class].\n"
        "\t\tm := cls compiledMethodAt: (row at: 5).\n"
        "\t\ts := WriteStream on: String new.\n"
        "\t\ts nextPutAll: 'method,'; print: (row at: 1); nextPut: $,; nextPutAll: (row at: 2); nextPut: $,; print: (row at: 3); nextPut: $,; nextPutAll: (row at: 6).\n"
        "\t\t(self describe: m) do: [:x | s nextPut: $,; print: x].\n"
        "\t\tScriptConsole println: s contents]\n"
        "! !\n"
    )
    (outdir / "Probes.st").write_text("".join(out))
    (outdir / "Samaltak.st").write_text(SAMALTAK)
    (outdir / "Pharo.st").write_text(PHARO)
    print(f"{len(live)} probes, {nchunks} driver chunks")


SAMALTAK = """!CompileSpeedDriver class methodsFor: 'describing'!
describe: aMethod
	"{bytes of bytecode. instructions. bytes in blocks. closures}: blocks are part of the method."
	| lines closures blockBytes end |
	lines := aMethod symbolic lines.
	closures := lines select: [:l | l includesSubstring: 'pushClosure'].
	blockBytes := 0.
	end := -1.
	closures do: [:l | | words pc to |
		words := l substrings.
		pc := words first asInteger.
		to := words last asInteger.
		pc >= end ifTrue: [
			blockBytes := blockBytes + (to - pc - 6).
			end := to]].
	^{aMethod bytecodes size. lines size. blockBytes. closures size}
!
statNames
	^#(#jitMethodsCompiled #jitBytecodesCompiled #jitCompileMicroseconds #jitCodeBytes #jitCompileFailures #optMethodsCompiled #optBytecodesCompiled #optCompileMicroseconds #optCodeBytes #optCompileFailures)
!
stats
	| s |
	s := Smalltalk vm statistics.
	^self statNames collect: [:n | s perform: n]
!
reportStats: before
	| now |
	now := self stats.
	self statNames doWithIndex: [:n :i | ScriptConsole println: 'stat,', n, ',', ((now at: i) - (before at: i)) printString]
! !
"""

PHARO = """!CompiledCode methodsFor: 'compile speed'!
csXray
	"Bit 1: the method has machine code (primitiveMethodXray)."
	<primitive: 216>
	^-1
! !

!VirtualMachine methodsFor: 'compile speed'!
csCodeZone
	"The machine-code zone's contents: element, address, element, address... (primitiveCollectCogCodeConstituents)."
	<primitive: 253>
	^#()
! !

!CompileSpeedDriver class methodsFor: 'describing'!
collectCodeSizes
	"Bytes in the code zone (CogMethod header, code, literals, map) of each method."
	| a |
	CodeSizes := IdentityDictionary new.
	a := Smalltalk vm csCodeZone.
	1 to: a size - 2 by: 2 do: [:i |
		((a at: i) isKindOf: CompiledCode) ifTrue: [CodeSizes at: (a at: i) put: (a at: i + 3) - (a at: i + 1)]]
!
describe: aMethod
	"{bytes of bytecode. instructions. bytes in blocks. CompiledBlocks. xray flags. machine-code bytes}."
	| blocks |
	blocks := aMethod allBlocks copyWithout: aMethod.
	^{aMethod endPC - aMethod initialPC + 1. aMethod symbolicBytecodes size. blocks inject: 0 into: [:a :b | a + (b endPC - b initialPC + 1)]. blocks size. aMethod csXray. CodeSizes at: aMethod ifAbsent: [0]}
!
statIndices
	"Cog's counters (VirtualMachine>>parameterLabels): methods, milliseconds, blocks, milliseconds, compactions, their milliseconds, methods with machine code."
	^#(75 76 77 78 62 63 64)
!
stats
	^self statIndices collect: [:i | Smalltalk vm parameterAt: i]
!
reportStats: before
	| now |
	now := self stats.
	self statIndices doWithIndex: [:n :i | ScriptConsole println: 'stat,param', n printString, ',', ((now at: i) - (before at: i)) printString]
! !
"""


def parse_round(path):
    stats, probes, methods = {}, {}, {}
    for line in Path(path).read_text(errors="replace").splitlines():
        p = line.split(",")
        if p[0] == "stat" and len(p) == 3:
            stats[p[1]] = int(p[2])
        elif p[0] == "probe":
            probes[int(p[1])] = [int(x) for x in p[2:]]
        elif p[0] == "method":
            methods[int(p[1])] = p[2:]
    return stats, probes, methods


def noblock(s_path, p_path):
    _, _, s = parse_round(s_path)
    _, _, p = parse_round(p_path)
    # a method line: class side file bytes instrs blockBytes blocks ...
    keep = [i for i in s if int(s[i][6]) == 0 and int(p[i][6]) == 0]
    print("\n".join(map(str, sorted(keep))))


def excess(probes):
    """Sum over the probes of the longest send minus the steady state (the last two sends' median), in microseconds."""
    return sum(max(t) - st.median(t[-2:]) for t in probes.values())


def report(directory):
    rows = {}
    files = sorted(Path(directory).glob("*-*-*.out"))
    print("# corpus,config,round,probes,compiled,bytes,instrs,compile_us,wall_us,code_bytes,extra")
    for f in files:
        corpus, config, rnd = f.stem.rsplit("-", 2)
        stats, probes, methods = parse_round(f)
        if not probes:
            print(f"# no data in {f.name}", file=sys.stderr)
            continue
        bytes_, instrs = sum(int(m[3]) for m in methods.values()), sum(int(m[4]) for m in methods.values())
        wall = excess(probes)
        extra = ""
        if config == "cog":
            compile_us = stats["param76"] * 1000 + stats["param78"] * 1000
            compiled = stats["param75"] + stats["param77"]
            code = sum(int(m[8]) for m in methods.values())
            xray = sum(1 for m in methods.values() if int(m[7]) & 2)
            extra = f"xray={xray} blocks={stats['param77']} compactions={stats['param62']}"
        elif config == "opt":
            compile_us = stats["optCompileMicroseconds"]
            compiled = stats["optMethodsCompiled"]
            code = stats["optCodeBytes"]
            # the VM's jitCompileMicroseconds includes the optimizing compilations
            extra = f"lowerUs={stats['jitCompileMicroseconds'] - stats['optCompileMicroseconds']} failures={stats['optCompileFailures']} countedBytes={stats['optBytecodesCompiled']}"
        else:
            compile_us = stats["jitCompileMicroseconds"]
            compiled = stats["jitMethodsCompiled"]
            code = stats["jitCodeBytes"]
            extra = f"countedBytes={stats['jitBytecodesCompiled']} failures={stats['jitCompileFailures']}"
        print(f"{corpus},{config},{rnd},{len(probes)},{compiled},{bytes_},{instrs},{compile_us},{wall:.0f},{code},{extra}")
        rows.setdefault((corpus, config), []).append((len(probes), compiled, bytes_, instrs, compile_us, wall, code))
    print("#")
    print("# corpus config rounds probes compiled bytes instrs compile_us(median; cog: mean) us/method us/byte us/instr wall_us(median) wall/method code/byte code/instr")
    for (corpus, config), rs in sorted(rows.items()):
        p, c, b, i = rs[0][0], st.median(r[1] for r in rs), rs[0][2], rs[0][3]
        # Cog reports whole milliseconds: their mean over the rounds; the others are in microseconds: their median
        us = st.fmean(r[4] for r in rs) if config == "cog" else st.median(r[4] for r in rs)
        wall = st.median(r[5] for r in rs)
        code = st.median(r[6] for r in rs)
        print(f"# {corpus:8} {config:9} {len(rs):3} {p:4} {c:6.0f} {b:6} {i:6} {us:9.1f} {us / c:7.2f} {us / b:7.4f} {us / i:7.4f} {wall:9.1f} {wall / p:7.2f} {code / b:6.1f} {code / i:6.1f}")


def report_awfy(paths):
    """awfy.sh -n 1 outputs named config-round.out: per config and benchmark, first iteration and compile time; totals."""
    data = {}
    for path in paths:
        config = Path(path).stem.rsplit("-", 1)[0]
        for line in Path(path).read_text(errors="replace").splitlines():
            m = re.match(r"([A-Za-z0-9]+),1,(-?\d+)$", line)
            if m:
                data.setdefault(config, {}).setdefault(m.group(1), {"first": [], "stats": []})["first"].append(int(m.group(2)))
            elif line.startswith("# stats "):
                _, _, name, rest = line.split(" ", 3)
                pairs = dict(kv.split("=") for kv in rest.split() if "=" in kv)
                data.setdefault(config, {}).setdefault(name, {"first": [], "stats": []})["stats"].append(pairs)
    print("# config benchmark runs first_ms(median) compile_ms(mean) share_of_first% compiled_units code_compaction_ms")
    totals = {}
    for config, benches in data.items():
        for b, d in sorted(benches.items()):
            first = st.median(d["first"]) / 1000.0
            comps = [compile_us_of(config, s) for s in d["stats"]]
            comp = st.fmean(c[0] for c in comps) / 1000.0
            units = st.fmean(c[1] for c in comps)
            compaction = st.fmean(c[2] for c in comps) / 1000.0
            print(f"# {config:9} {b:12} {len(d['first']):3} {first:10.2f} {comp:10.3f} {100 * comp / first:7.1f} {units:8.1f} {compaction:8.2f}")
            t = totals.setdefault(config, [0.0, 0.0])
            t[0] += first
            t[1] += comp
    for config, (first, comp) in totals.items():
        print(f"# {config:9} TOTAL first iterations {first:.1f} ms, compile {comp:.1f} ms, {100 * comp / first:.1f}%")


def compile_us_of(config, s):
    """(microseconds compiling, units compiled, microseconds of code compaction) of a '# stats' line."""
    if config.startswith("cog"):
        return (int(s["cogMethodMs"]) + int(s["cogBlockMs"])) * 1000, int(s["cogMethods"]) + int(s["cogBlocks"]), int(s["cogCompactionMs"]) * 1000
    return int(s["jitCompileMicroseconds"]), int(s["jitMethodsCompiled"]), 0  # the VM's jit counters include the optimizing compilations


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "gen" and len(sys.argv) in (3, 4):
        gen(*sys.argv[2:])
    elif cmd == "noblock" and len(sys.argv) == 4:
        noblock(sys.argv[2], sys.argv[3])
    elif cmd == "report" and len(sys.argv) == 3:
        report(sys.argv[2])
    elif cmd == "report-awfy" and len(sys.argv) > 2:
        report_awfy(sys.argv[2:])
    else:
        raise SystemExit(__doc__)
