#!/usr/bin/env python3
# perf_mix.py SPEDATA PID [TOP]: the operations ARM SPE sampled (perf-awfy.sh spe) in machine code: per piece of code
# (named by /tmp/jit-PID.dump, SAMALTAK_PERF_MAP=jitdump), its hottest instructions, and the kind of every sampled
# instruction (class checks, tag checks, frame traffic, polls, ...), disassembled with objdump from the dump.
import sys, struct, subprocess, collections, re, tempfile, os
data, pid = sys.argv[1], sys.argv[2]; top = int(sys.argv[3]) if len(sys.argv) > 3 else 6
cnt = collections.Counter(); total = 0
p = subprocess.Popen(["sudo", "-n", "perf", "script", "-i", data, "-F", "event,ip"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
for l in p.stdout:
    s = l.split()
    if len(s) == 2 and s[0] == "instructions:":
        cnt[int(s[1], 16)] += 1; total += 1
recs = []
d = open("/tmp/jit-%s.dump" % pid, "rb").read(); o = 40
while o + 16 <= len(d):
    rid, size, ts = struct.unpack_from("<IIQ", d, o)
    if size == 0: break
    if rid == 0:
        _, _, vma, addr, n, idx = struct.unpack_from("<IIQQQQ", d, o + 16)
        e = d.index(b"\0", o + 56); name = d[o + 56:e].decode(errors="replace"); code = d[e + 1:e + 1 + n]
        recs.append((addr, n, name, code))
    o += size
recs.sort()
import bisect
starts = [r[0] for r in recs]
bysym = collections.Counter(); perins = collections.defaultdict(collections.Counter); jit = 0
for ip, c in cnt.items():
    i = bisect.bisect_right(starts, ip) - 1
    if i >= 0 and ip < recs[i][0] + recs[i][1]:
        bysym[i] += c; perins[i][ip] += c; jit += c
print("samples %d, in JIT code %.1f%%" % (total, 100.0 * jit / max(total, 1)))
def disasm(r):
    f = tempfile.NamedTemporaryFile(delete=False); f.write(r[3]); f.close()
    out = subprocess.run(["objdump", "-D", "-b", "binary", "-maarch64", "--adjust-vma=%#x" % r[0], f.name], capture_output=True, text=True).stdout
    os.unlink(f.name); res = {}
    for l in out.splitlines():
        m = re.match(r"^\s*([0-9a-f]+):\s+[0-9a-f]{8}\s+(.*)$", l)
        if m: res[int(m.group(1), 16)] = re.sub(r"\s+", " ", m.group(2).split("//")[0]).strip()
    return res
def cat(ins, prev):
    op = ins.split(" ")[0]
    if re.match(r"ldr w16, \[x22, #24\]", ins) or (op == "cbnz" and prev == "poll"): return "poll"
    if re.match(r"ldr x1[67], \[x22, #(88|304)\]", ins) or re.match(r"cmp x(20|16), x1[67]$", ins) and prev == "stack" or (op.startswith("b.") and prev == "stack"): return "stack"
    if (op == "adr" and ins.startswith("adr x16")) or re.match(r"ldr w16, \[x16, #36\]", ins) or re.match(r"tst w16, #0x2", ins) or (op.startswith("b.") and prev == "deopt"): return "deopt"
    if re.match(r"tst x\d+, #0x7$", ins) or re.match(r"csel x16, x\d+, x22", ins) or re.match(r"ldr x16, \[x16, #8\]", ins) or re.match(r"ldr x17, 0x", ins) or re.match(r"cmp x16, x17", ins) or (op.startswith("b.") and prev == "class"): return "class"
    if re.match(r"tst x\d+, #0x1$", ins) or (op.startswith("b.") and prev == "tag"): return "tag"
    if op == "b.vs": return "overflow"
    if re.match(r"(stp x23, x23|str x23), \[x(19|20)", ins): return "nil-init"
    if re.match(r"(str|stp|stur)\w* .*\[x(19|20)[,\]]", ins): return "frame-store"
    if re.match(r"(ldr|ldp|ldur)\w* .*\[x(19|20)[,\]]", ins): return "frame-load"
    if re.match(r"(add|sub) x(19|20), x(19|20)", ins) or re.match(r"(stp|ldp) x29, x30", ins) or op in ("bl", "blr", "ret", "br") or ins == "mov x29, sp": return "call/ret"
    if re.match(r"(mov|fmov) [xd]\d+, [xd]\d+$", ins): return "reg-move"
    if op.startswith("f") or re.search(r"\bd\d+\b", ins): return "float"
    if op in ("b", "cbz", "cbnz", "tbz", "tbnz") or op.startswith("b."): return "branch"
    if op.startswith("ld"): return "heap-load"
    if op.startswith("st"): return "heap-store"
    return "alu"
mix = collections.Counter()
for k, (i, c) in enumerate(bysym.most_common()):
    r = recs[i]; dis = disasm(r); prev = None; lm = collections.Counter()
    for a in sorted(dis):
        cc = cat(dis[a], prev); prev = cc
        lm[cc] += perins[i].get(a, 0)
    mix.update(lm)
    if k < top:
        print("%5.1f%% %s  (%d bytes)" % (100.0 * c / total, r[2], r[1]))
        if k < 2:
            for a, n in sorted(perins[i].items(), key=lambda x: -x[1])[:12]:
                print("        %5.2f%%  +%#x  %s" % (100.0 * n / c, a - r[0], dis.get(a, "?")))
t = sum(mix.values())
print("dynamic mix of JIT code: " + ", ".join("%s %.1f%%" % (k, 100.0 * v / t) for k, v in mix.most_common()))
