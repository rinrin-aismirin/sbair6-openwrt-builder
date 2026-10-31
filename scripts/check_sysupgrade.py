#!/usr/bin/env python3
"""Check out/STAMP/sysupgrade.bin against the build's boot.img and rootfs.img.

Usage: check_sysupgrade.py IMAGE_DIR POLICY MODEM_VERSION
POLICY is trial or normal (from the boot image), MODEM_VERSION is V.._.._P.. or empty. Env FWTOOL: the build tree's
fwtool; it must read the metadata back (it checks the trailer CRC, header and type). Without FWTOOL the check fails.
Prints one "OK ..." or "FAIL ..." line per check; exit status 0 only when every check passed.
Checks: fwtool trailer and metadata (supported_devices softbank,air6, compat_version 1.x); the tar members (exactly
the directory and CONTROL, kernel, root as regular files, in this order); CONTROL keys and values; kernel = boot.img;
root = rootfs.img cut to the squashfs bytes_used rounded up to 4 KiB, the rest of rootfs.img zero.
"""
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
import tarfile
import tempfile

DIR = "sysupgrade-softbank_air6"
KEYS = ["BOARD", "format", "kernel_size", "kernel_sha256", "root_size", "root_sha256", "squashfs_bytes_used",
        "trial", "modem_version", "fork", "kit"]
FWIMAGE_MAGIC = 0x46577830  # "FWx0"

fails = 0


def ok(msg):
    print(f"OK   sysupgrade.bin: {msg}")


def ng(msg):
    global fails
    fails += 1
    print(f"FAIL sysupgrade.bin: {msg}")


def main():
    d, policy, modem = sys.argv[1:4]
    try:
        blob = open(f"{d}/sysupgrade.bin", "rb").read()
    except OSError as e:
        ng(f"not readable ({e})")
        return 1
    if len(blob) < 16 or struct.unpack(">I", blob[-16:-12])[0] != FWIMAGE_MAGIC:
        ng("no fwtool trailer")
        return 1
    size = struct.unpack(">I", blob[-4:])[0]
    if size < 24 or size > len(blob):
        ng("fwtool trailer size out of range")
        return 1
    # The metadata block is struct fwimage_header (8 bytes), the JSON, then the 16-byte trailer.
    meta_raw, body = blob[-size + 8:-16], blob[:-size]
    fwtool = os.environ.get("FWTOOL", "")
    if not fwtool:
        ng("metadata not verified: FWTOOL (the build tree's fwtool) not set")
    else:
        with tempfile.TemporaryDirectory() as t:
            r = subprocess.run([fwtool, "-q", "-i", f"{t}/meta.json", f"{d}/sysupgrade.bin"], capture_output=True)
            try:
                got = open(f"{t}/meta.json", "rb").read()
            except OSError:
                got = b""
            if r.returncode == 0 and got.strip() == meta_raw.strip():
                ok("fwtool reads the metadata back (trailer CRC, header, type)")
            else:
                ng(f"fwtool cannot read the metadata back (rc {r.returncode})")
    try:
        meta = json.loads(meta_raw.decode())
        devs = meta.get("supported_devices", [])
        compat = str(meta.get("compat_version", ""))
        if "softbank,air6" in devs and compat.startswith("1."):
            ok(f"metadata (supported_devices {devs}, compat_version {compat})")
        else:
            ng(f"metadata supported_devices {devs} compat_version {compat!r}")
    except ValueError:
        ng("metadata is not JSON")

    try:
        tar = tarfile.open(fileobj=io.BytesIO(body), mode="r:")
        members = tar.getmembers()
    except tarfile.TarError as e:
        ng(f"not a tar ({e})")
        return 1
    want = [(DIR, tarfile.DIRTYPE), (f"{DIR}/CONTROL", tarfile.REGTYPE), (f"{DIR}/kernel", tarfile.REGTYPE),
            (f"{DIR}/root", tarfile.REGTYPE)]
    got = [(m.name.rstrip("/"), m.type) for m in members]
    if got != want:
        ng(f"members {got}")
        return 1
    ok("members: the directory, CONTROL, kernel, root")
    control = tar.extractfile(members[1]).read().decode()
    kernel = tar.extractfile(members[2]).read()
    root = tar.extractfile(members[3]).read()
    lines = control.splitlines()
    c = {}
    if [ln.split("=", 1)[0] for ln in lines] != KEYS or not control.endswith("\n"):
        ng(f"CONTROL keys {[ln.split('=', 1)[0] for ln in lines]}")
        return 1
    for ln in lines:
        k, v = ln.split("=", 1)
        c[k] = v
    boot = open(f"{d}/boot.img", "rb").read()
    rootfs = open(f"{d}/rootfs.img", "rb").read()
    checks = [
        ("BOARD", c["BOARD"] == "softbank_air6"),
        ("format", c["format"] == "air6-sysupgrade/1"),
        ("kernel = boot.img", kernel == boot and c["kernel_size"] == str(len(kernel))
         and c["kernel_sha256"] == hashlib.sha256(kernel).hexdigest()),
        ("root sizes and hash", c["root_size"] == str(len(root)) and c["root_sha256"] == hashlib.sha256(root).hexdigest()),
        ("squashfs_bytes_used", root[:4] == b"hsqs"
         and c["squashfs_bytes_used"] == str(struct.unpack_from("<Q", root, 40)[0])
         and (int(c["squashfs_bytes_used"]) + 4095) // 4096 * 4096 == len(root)),
        ("root = start of rootfs.img, rest zero", rootfs[:len(root)] == root and not rootfs[len(root):].strip(b"\0")),
        (f"trial={c['trial']} matches the boot image policy {policy}", c["trial"] == ("1" if policy == "trial" else "0")),
        (f"modem_version={c['modem_version'] or 'none'} matches the build", c["modem_version"] == modem),
        ("fork commit", re.fullmatch(r"[0-9a-f]{40}", c["fork"]) is not None),
        ("kit commit", c["kit"] == "none" or re.fullmatch(r"[0-9a-f]{40}", c["kit"]) is not None),
    ]
    for name, good in checks:
        (ok if good else ng)(name)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
