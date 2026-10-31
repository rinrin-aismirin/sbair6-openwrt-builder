#!/usr/bin/env python3
"""Build the Air 6 sysupgrade package (before its fwtool metadata is appended).

Usage: make_sysupgrade.py OUT BOOT_IMG ROOTFS_IMG FORK_COMMIT KIT_COMMIT TRIAL MODEM_VERSION

OUT is an uncompressed ustar archive holding exactly the directory sysupgrade-softbank_air6/ and the regular files
CONTROL, kernel and root, in this order (owner 0, mode 0644/0755, mtime 0). kernel = BOOT_IMG as installed (32 MiB);
root = the squashfs from ROOTFS_IMG cut to its bytes_used rounded up to 4 KiB (the kit pads rootfs.img to 128 MiB
with zeros; that padding must be zero). CONTROL lists the keys in the order /lib/air6/upgrade.sh expects.
TRIAL is 0 or 1, MODEM_VERSION is V.._.._P.. or empty, KIT_COMMIT is 40 hex or "none".
"""
import hashlib
import io
import re
import struct
import sys
import tarfile

DIR = "sysupgrade-softbank_air6"
KERNEL_SIZE = 33554432


def die(msg):
    print(f"make_sysupgrade: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 8:
        die(__doc__.strip().splitlines()[2])
    out, boot_path, rootfs_path, fork, kit, trial, modem = sys.argv[1:]
    if not re.fullmatch(r"[0-9a-f]{40}", fork):
        die(f"fork commit {fork!r} is not 40 hex digits")
    if kit != "none" and not re.fullmatch(r"[0-9a-f]{40}", kit):
        die(f"kit commit {kit!r} is not 40 hex digits or none")
    if trial not in ("0", "1"):
        die("TRIAL must be 0 or 1")
    if modem and not re.fullmatch(r"V[0-9]+_[0-9]+_P[0-9]+", modem):
        die(f"modem version {modem!r} is not V.._.._P..")

    kernel = open(boot_path, "rb").read()
    if len(kernel) != KERNEL_SIZE or not kernel.startswith(b"ANDROID!"):
        die("boot image is not a 32 MiB Android boot image")
    rootfs = open(rootfs_path, "rb").read()
    if rootfs[:4] != b"hsqs":
        die("rootfs image is not a squashfs")
    bytes_used = struct.unpack_from("<Q", rootfs, 40)[0]
    root_size = (bytes_used + 4095) // 4096 * 4096
    if bytes_used <= 96 or root_size > len(rootfs):
        die(f"squashfs bytes_used {bytes_used} does not fit the rootfs image")
    if rootfs[root_size:].strip(b"\0"):
        die("the rootfs image has non-zero bytes after the squashfs")
    root = rootfs[:root_size]

    control = "".join(f"{k}={v}\n" for k, v in [
        ("BOARD", "softbank_air6"),
        ("format", "air6-sysupgrade/1"),
        ("kernel_size", len(kernel)),
        ("kernel_sha256", hashlib.sha256(kernel).hexdigest()),
        ("root_size", root_size),
        ("root_sha256", hashlib.sha256(root).hexdigest()),
        ("squashfs_bytes_used", bytes_used),
        ("trial", trial),
        ("modem_version", modem),
        ("fork", fork),
        ("kit", kit),
    ]).encode()

    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as tar:
        def add(name, data=None):
            ti = tarfile.TarInfo(name)
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = ""
            ti.mtime = 0
            if data is None:
                ti.type = tarfile.DIRTYPE
                ti.mode = 0o755
                tar.addfile(ti)
            else:
                ti.mode = 0o644
                ti.size = len(data)
                tar.addfile(ti, io.BytesIO(data))
        add(DIR)
        add(f"{DIR}/CONTROL", control)
        add(f"{DIR}/kernel", kernel)
        add(f"{DIR}/root", root)
    print(f"sysupgrade package: kernel {len(kernel)} bytes, root {root_size} bytes (squashfs {bytes_used}), "
          f"trial={trial}, modem={modem or 'none'}")


if __name__ == "__main__":
    main()
