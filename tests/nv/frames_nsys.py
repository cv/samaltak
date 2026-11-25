#!/usr/bin/env python3
"""Kernel and launch times per scenario from an nsys profile of tests/nv/frames.sh (NV_FRAMES_NSYS=1).

RenderScenarios brackets each scenario with marker launches (samaltak_stamp kernels of 1000 + i blocks at its start,
2000 + i at its end, NvComputeGPU>>mark:). Per scenario and presented frame (frames from OUT/nv/frames-cuda.txt): the
kernels launched and their GPU time (each kernel's start to end, summed: busy, not waiting for the GPU), per kernel
name, and the CPU time of the driver calls that launch them (cuLaunchKernel) or write fences (cuStreamWriteValue64).

    tests/nv/frames_nsys.py [OUT]       (default build)
"""
import os, sqlite3, subprocess, sys

out = sys.argv[1] if len(sys.argv) > 1 else "build"
rep = os.path.join(out, "nv", "frames-cuda.nsys-rep")
db = os.path.join(out, "nv", "frames-cuda.sqlite")
if not os.path.exists(db) or os.path.getmtime(db) < os.path.getmtime(rep):
    subprocess.run([os.environ.get("NSYS", "/usr/local/cuda/bin/nsys"), "export", "--type", "sqlite", "--force-overwrite",
                    "true", "-o", db, rep], check=True, stdout=subprocess.DEVNULL)
frames = {}
txt = os.path.join(out, "nv", "frames-cuda.txt")
names_in_order = []
if os.path.exists(txt):
    for line in open(txt).read().replace("\r", "\n").splitlines():
        parts = line.split()
        if len(parts) > 2 and "/" in parts[1] and parts[1].split("/")[0].isdigit():
            frames[parts[0]] = int(parts[1].split("/")[0])
            names_in_order.append(parts[0])
c = sqlite3.connect(db)
s = dict(c.execute("select id, value from StringIds"))
kernels = [(st, en, s[sn], gx, corr) for st, en, sn, gx, corr in
           c.execute("select start, end, shortName, gridX, correlationId from CUPTI_ACTIVITY_KIND_KERNEL order by start")]
api = {}
for st, en, nid, corr in c.execute("select start, end, nameId, correlationId from CUPTI_ACTIVITY_KIND_RUNTIME"):
    api[corr] = (st, en, s[nid])
calls = sorted((st, en, n) for st, en, n in api.values())
marks = {}
for st, en, name, gx, corr in kernels:
    if name == "samaltak_stamp" and gx >= 1000:
        marks[gx] = api.get(corr, (st,))[0]
print("scenario frames | per frame: kernels busy_us (raster_batch_prims raster_batch_tiles raster_fill raster_blit raster_copy samaltak_stamp: n/us) | cuLaunchKernel n cpu_us | cuStreamWriteValue64 n cpu_us")
for i in range(1, 20):
    if 1000 + i not in marks or 2000 + i not in marks:
        continue
    a, b = marks[1000 + i], marks[2000 + i]
    name = names_in_order[i - 1] if i - 1 < len(names_in_order) else str(i)
    n = max(frames.get(name, 1), 1)
    ks = [k for k in kernels if a <= (api.get(k[4], (k[0],))[0]) <= b and not (k[2] == "samaltak_stamp" and k[3] >= 1000)]
    by = {}
    for st, en, kn, gx, corr in ks:
        e = by.setdefault(kn, [0, 0])
        e[0] += 1
        e[1] += en - st
    busy = sum(en - st for st, en, *_ in ks)
    cl = [x for x in calls if a <= x[0] <= b]
    def cpu(nm):
        v = [en - st for st, en, x in cl if x.startswith(nm)]
        return "%.1f %.0f" % (len(v) / n, sum(v) / n / 1000)
    detail = " ".join("%s:%.1f/%.0f" % (k.replace("raster_", "").replace("samaltak_", ""), by[k][0] / n, by[k][1] / n / 1000) for k in sorted(by))
    print("%s %d | %.1f %.0f (%s) | %s | %s" % (name, n, len(ks) / n, busy / n / 1000, detail, cpu("cuLaunchKernel"), cpu("cuStreamWriteValue64")))
