"""Re-sign an Android boot v2 image that carries MediaTek cert1/cert2 sections after its payload.

cert1 is reused verbatim. In cert2, OID 2.16.886.2454.2.4 (SHA-256 of the 2048-byte header page) and
OID 2.16.886.2454.2.1 (SHA-256 of the payload from the end of the header page to the cert section) are
recomputed, and the TBS is re-signed with RSASSA-PSS (SHA-256, MGF1-SHA-256, salt 32) using the image key.

Usage (needs `openssl` on PATH):
  resign_boot.py IN.img IMAGE_prvk.pem OUT.img [--cmdline TEXT]
  resign_boot.py --verify IMG ROOT_pub.pem IMAGE_pub.pem
"""
import hashlib, os, struct, subprocess, sys, tempfile

PAGE_DEFAULT = 2048
MTK_MAGIC = b"\x88\x16\x88\x58"
OID_PREFIX = bytes.fromhex("0607608676931602")  # 06 07 + 2.16.886.2454.2
PSS_OPTS = ["-sigopt", "rsa_padding_mode:pss", "-sigopt", "rsa_pss_saltlen:32", "-sigopt", "rsa_mgf1_md:sha256"]


def der_len(buf, off):
    """Return (header_length, content_length) of the DER element at off."""
    first = buf[off + 1]
    if first < 0x80:
        return 2, first
    n = first & 0x7F
    return 2 + n, int.from_bytes(buf[off + 2:off + 2 + n], "big")


def payload_end(img):
    if img[:8] != b"ANDROID!":
        raise ValueError("not an Android boot image")
    ksz, _, rsz, _, ssz, _, _, page, hver = struct.unpack_from("<9I", img, 8)
    if hver != 2:
        raise ValueError(f"unsupported header version {hver}")
    pg = lambda n: (n + page - 1) // page * page
    rdtbo, = struct.unpack_from("<I", img, 1632)
    dtb, = struct.unpack_from("<I", img, 1648)
    return page, page + pg(ksz) + pg(rsz) + pg(ssz) + pg(rdtbo) + pg(dtb)


def sections(img, off):
    out = []
    while img[off:off + 4] == MTK_MAGIC:
        size, = struct.unpack_from("<I", img, off + 4)
        name = img[off + 8:off + 40].split(b"\0")[0].decode()
        hdr, = struct.unpack_from("<I", img, off + 0x34)
        out.append((name, off, hdr, size))
        off = (off + hdr + size + 15) & ~15
    return out


def hash_field(der, oid_last):
    """Offset of the 32-byte value inside the BIT STRING that follows OID 2.16.886.2454.2.<oid_last>."""
    i = der.find(OID_PREFIX + bytes([oid_last]))
    if i < 0:
        raise ValueError(f"OID 2.4 .2.{oid_last} not found")
    bs = i + len(OID_PREFIX) + 1
    if der[bs] != 0x03 or der[bs + 1] != 0x21 or der[bs + 2] != 0x00:
        raise ValueError("unexpected BIT STRING layout")
    return bs + 3


def tbs_and_sig(der):
    """Return (tbs_start, tbs_end, sig_offset) for SEQUENCE{tbs, alg, BIT STRING sig}."""
    oh, _ = der_len(der, 0)
    tbs_start = oh
    th, tl = der_len(der, tbs_start)
    tbs_end = tbs_start + th + tl
    ah, al = der_len(der, tbs_end)
    sig = tbs_end + ah + al
    sh, sl = der_len(der, sig)
    if der[sig] != 0x03 or der[sig + sh] != 0x00:
        raise ValueError("signature is not a BIT STRING")
    return tbs_start, tbs_end, sig + sh + 1


def openssl(args, data=None):
    return subprocess.run(["openssl"] + args, input=data, capture_output=True, check=True).stdout


def resign(src, key, dst, cmdline=None):
    img = bytearray(open(src, "rb").read())
    page, end = payload_end(img)
    secs = sections(img, end)
    names = [s[0] for s in secs]
    if names[:2] != ["cert1", "cert2"]:
        raise ValueError(f"expected cert1, cert2 after payload, got {names}")
    if cmdline is not None:
        raw = cmdline.encode()
        if len(raw) >= 512:
            raise ValueError("cmdline too long")
        img[64:576] = raw + b"\0" * (512 - len(raw))
    _, c2_off, c2_hdr, c2_size = secs[1]
    der = bytearray(img[c2_off + c2_hdr:c2_off + c2_hdr + c2_size])
    h_hdr = hashlib.sha256(img[:page]).digest()
    h_pay = hashlib.sha256(img[page:end]).digest()
    der[hash_field(der, 4):hash_field(der, 4) + 32] = h_hdr
    der[hash_field(der, 1):hash_field(der, 1) + 32] = h_pay
    t0, t1, s0 = tbs_and_sig(der)
    with tempfile.TemporaryDirectory() as td:
        tbs = os.path.join(td, "tbs")
        open(tbs, "wb").write(der[t0:t1])
        sig = openssl(["dgst", "-sha256", "-sign", key] + PSS_OPTS + [tbs])
    if len(sig) != len(der) - s0:
        raise ValueError("signature length changed")
    der[s0:] = sig
    img[c2_off + c2_hdr:c2_off + c2_hdr + c2_size] = der
    open(dst, "wb").write(img)


def verify(path, root_pub, img_pub):
    img = open(path, "rb").read()
    page, end = payload_end(img)
    secs = {s[0]: s for s in sections(img, end)}
    ok = True
    with tempfile.TemporaryDirectory() as td:
        for name, pub in (("cert1", root_pub), ("cert2", img_pub)):
            _, off, hdr, size = secs[name]
            der = img[off + hdr:off + hdr + size]
            t0, t1, s0 = tbs_and_sig(der)
            tbs, sig = os.path.join(td, "tbs"), os.path.join(td, "sig")
            open(tbs, "wb").write(der[t0:t1]); open(sig, "wb").write(der[s0:])
            r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", sig] + PSS_OPTS + [tbs],
                               capture_output=True, text=True)
            good = r.returncode == 0
            ok &= good
            print(f"{name} signature: {'OK' if good else 'FAIL'}")
        _, off, hdr, size = secs["cert2"]
        der = img[off + hdr:off + hdr + size]
        for label, oid, data in (("header hash (2.4)", 4, img[:page]), ("payload hash (2.1)", 1, img[page:end])):
            o = hash_field(der, oid)
            good = der[o:o + 32] == hashlib.sha256(data).digest()
            ok &= good
            print(f"{label}: {'OK' if good else 'MISMATCH'}")
    print("RESULT:", "PASS" if ok else "FAIL")
    return ok


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--verify":
        sys.exit(0 if verify(a[1], a[2], a[3]) else 1)
    cmd = None
    if "--cmdline" in a:
        i = a.index("--cmdline"); cmd = a[i + 1]; del a[i:i + 2]
    resign(a[0], a[1], a[2], cmd)
    print("wrote", a[2])
