#!/usr/bin/env python3
"""Print the EFI global variables of an edk2 (OVMF/AAVMF) variable store file, for make test-install.

usage: tests/uefi/efivars.py VARS.fd

One line each: Boot#### <attributes> <description> <file path>, BootOrder, BootNext, BootCurrent,
OsIndications as hex words. Reads the firmware volume's variable store (authenticated or not) and
keeps the live copy of each variable (state VAR_ADDED, or in deleted transition if that is all there is).
"""
import struct
import sys

GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
AUTH_STORE = "aaf32c78-947b-439a-a180-2e144ec37792"
NORMAL_STORE = "ddcf3616-3275-4164-98b6-fe85707ffe7d"


def guid(b):
    a, b2, c = struct.unpack_from("<IHH", b)
    rest = b[8:16].hex()
    return f"{a:08x}-{b2:04x}-{c:04x}-{rest[:4]}-{rest[4:]}"


def variables(data):
    if data[40:44] != b"_FVH":
        raise SystemExit("not a firmware volume")
    fv_header = struct.unpack_from("<H", data, 48)[0]
    store = fv_header
    kind = guid(data[store:store + 16])
    if kind not in (AUTH_STORE, NORMAL_STORE):
        raise SystemExit(f"unknown variable store {kind}")
    size = struct.unpack_from("<I", data, store + 16)[0]
    end = store + size
    p = store + 28
    header = 60 if kind == AUTH_STORE else 32
    live, transition = {}, {}
    while p + header <= end:
        start_id, state, _, attrs = struct.unpack_from("<HBBI", data, p)
        if start_id != 0x55AA:
            break
        if kind == AUTH_STORE:
            name_size, data_size = struct.unpack_from("<II", data, p + 36)
            vendor = guid(data[p + 44:p + 60])
        else:
            name_size, data_size = struct.unpack_from("<II", data, p + 8)
            vendor = guid(data[p + 16:p + 32])
        name = data[p + header:p + header + name_size].decode("utf-16-le").rstrip("\0")
        n = p + header + name_size  # edk2's data follows the name unpadded (ALIGNMENT 1)
        value = data[n:n + data_size]
        if state == 0x3F:
            live[(vendor, name)] = (attrs, value)
        elif state == 0x3E:
            transition[(vendor, name)] = (attrs, value)
        p = n + data_size
        p += (4 - p % 4) % 4
    for key, v in transition.items():
        live.setdefault(key, v)
    return live


def load_option(value):
    attrs, path_len = struct.unpack_from("<IH", value)
    i = 6
    desc = []
    while i + 1 < len(value):
        c = struct.unpack_from("<H", value, i)[0]
        i += 2
        if c == 0:
            break
        desc.append(chr(c))
    path = value[i:i + path_len]
    files, part = [], None
    j = 0
    while j + 4 <= len(path):
        t, s, ln = struct.unpack_from("<BBH", path, j)
        if t == 0x7F or ln < 4:
            break
        node = path[j + 4:j + ln]
        if t == 4 and s == 4:
            files.append(node.decode("utf-16-le").rstrip("\0"))
        if t == 4 and s == 1:
            part = f"HD({struct.unpack_from('<I', node)[0]},GPT,{guid(node[20:36])})"
        j += ln
    return attrs, "".join(desc), part, "\\".join(f.strip("\\") for f in files)


def main():
    data = open(sys.argv[1], "rb").read()
    for (vendor, name), (attrs, value) in sorted(variables(data).items()):
        if vendor != GLOBAL:
            continue
        if name.startswith("Boot") and len(name) == 8 and all(c in "0123456789ABCDEF" for c in name[4:]):
            a, desc, part, path = load_option(value)
            print(f"{name} {attrs} {a:x} {desc!r} {part or '-'} {chr(92) + path if path else '-'}")
        elif name in ("BootOrder", "BootNext", "BootCurrent"):
            words = struct.unpack_from(f"<{len(value) // 2}H", value)
            print(name, ",".join(f"{w:04X}" for w in words))
        elif name in ("OsIndications", "OsIndicationsSupported"):
            print(name, value.hex())


if __name__ == "__main__":
    main()
