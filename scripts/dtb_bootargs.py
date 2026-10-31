#!/usr/bin/env python3
"""Print the image policy (trial or normal) from /chosen/bootargs of the Air 6 DTB inside a boot image.

Usage: dtb_bootargs.py BOOT_IMG          print the policy
       dtb_bootargs.py --root BOOT_IMG   print the value of the single root= token of the same bootargs
Every flattened device tree in the file (magic d00dfeed with a consistent header) is walked; the policy comes from
the /chosen/bootargs value that holds the token air6_dt_bootargs=1. It is "trial" when that value also holds the
token air6.trial=1 (as air6-slot reads it from the kernel command line), else "normal". Exit status 0 and one of
those two words on success; exit status 1 and "unknown: <reason>" when there is not exactly one such value.
"""
import struct
import sys

MARKER = b"air6_dt_bootargs=1"
TRIAL = b"air6.trial=1"
FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def chosen_bootargs(blob):
    """Return the /chosen/bootargs value of one FDT (bytes without the trailing NUL), or None."""
    (magic, total, off_struct, off_strings, _rsv, version, _lc, _cpu, size_strings,
     size_struct) = struct.unpack(">10I", blob[:40])
    if magic != FDT_MAGIC or version < 17 or total > len(blob):
        raise ValueError("bad header")
    if off_struct + size_struct > total or off_strings + size_strings > total:
        raise ValueError("bad block offsets")
    strings = blob[off_strings:off_strings + size_strings]
    pos, end, path, found = off_struct, off_struct + size_struct, [], None
    while pos + 4 <= end:
        tok, = struct.unpack(">I", blob[pos:pos + 4])
        pos += 4
        if tok == FDT_BEGIN_NODE:
            nul = blob.index(b"\0", pos, end)
            path.append(blob[pos:nul])
            pos = (nul + 4) & ~3
        elif tok == FDT_END_NODE:
            if not path:
                raise ValueError("unbalanced nodes")
            path.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack(">II", blob[pos:pos + 8])
            pos += 8
            if pos + length > end or nameoff >= len(strings):
                raise ValueError("bad property")
            name = strings[nameoff:strings.index(b"\0", nameoff)]
            if path == [b"", b"chosen"] and name == b"bootargs":
                if found is not None:
                    raise ValueError("bootargs twice")
                found = blob[pos:pos + length].rstrip(b"\0")
            pos = (pos + length + 3) & ~3
        elif tok == FDT_NOP:
            continue
        elif tok == FDT_END:
            return found
        else:
            raise ValueError("bad token %d" % tok)
    raise ValueError("no FDT_END")


def main():
    args = sys.argv[1:]
    want_root = args[:1] == ["--root"]
    if want_root:
        args = args[1:]
    data = open(args[0], "rb").read()
    values, i = [], data.find(struct.pack(">I", FDT_MAGIC))
    while i >= 0:
        try:
            v = chosen_bootargs(data[i:])
        except (ValueError, struct.error):
            v = None
        if v is not None and MARKER in v.split():
            values.append(v)
        i = data.find(struct.pack(">I", FDT_MAGIC), i + 4)
    if len(values) != 1:
        print("unknown: %d DTBs with /chosen/bootargs holding %s" % (len(values), MARKER.decode()))
        return 1
    if want_root:
        roots = [t[5:].decode(errors="replace") for t in values[0].split() if t.startswith(b"root=")]
        if len(roots) != 1:
            print("unknown: %d root= tokens" % len(roots))
            return 1
        print(roots[0])
        return 0
    print("trial" if TRIAL in values[0].split() else "normal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
