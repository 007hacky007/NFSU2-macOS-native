#!/usr/bin/env python3
"""check_texpacks.py [--full] [list]: does every Download in the launcher's texture pack list
(launcher/texture-packs.json) still serve the release it was tested with?

For each pack with a download it asks the server for the file's size (HEAD, or a GET of
one byte) and compares it with the list's; with --full it downloads the file and compares
its SHA-256 too.  Prints one line per pack and a summary:
  OK       the size (and with --full the SHA-256) is the list's
  CHANGED  the server has another file there: the author uploaded a new release; download
           it from the pack's page, test it, then put its URL, size and SHA-256 in the list
  GONE     no file there any more (HTTP error, no answer)
Exit status 0 when all are OK.  Standard library only."""
import hashlib, json, os, sys, urllib.request, urllib.error

UA = {"User-Agent": "NFSU2Recomp-texture-pack-check"}


def size_of(url):
    for method, extra in (("HEAD", {}), ("GET", {"Range": "bytes=0-0"})):
        req = urllib.request.Request(url, method=method, headers={**UA, **extra})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                cr = r.headers.get("Content-Range")
                if cr and "/" in cr:
                    return int(cr.rsplit("/", 1)[1])
                if method == "HEAD" and r.headers.get("Content-Length"):
                    return int(r.headers["Content-Length"])
        except urllib.error.HTTPError as e:
            if method == "GET":
                raise
            if e.code not in (403, 405, 501):
                raise
    return None


def sha256_of(url):
    h = hashlib.sha256()
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def main():
    args = [a for a in sys.argv[1:] if a != "--full"]
    full = "--full" in sys.argv[1:]
    path = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "launcher", "texture-packs.json")
    with open(path, encoding="utf-8") as f:
        packs = json.load(f)["packs"]
    count = {"OK": 0, "CHANGED": 0, "GONE": 0}
    for p in packs:
        url = p.get("download")
        if not url:
            continue
        try:
            n = size_of(url)
            if n is None:
                state, why = "GONE", "the server gives no size"
            elif n != p["size"]:
                state, why = "CHANGED", f"{n} bytes, the list has {p['size']}"
            elif full:
                s = sha256_of(url)
                state, why = ("OK", "size and SHA-256") if s == p["sha256"] else ("CHANGED", f"SHA-256 {s[:16]}..., the list has {p['sha256'][:16]}...")
            else:
                state, why = "OK", "size"
        except (urllib.error.URLError, OSError, ValueError) as e:
            state, why = "GONE", str(getattr(e, "reason", e))
        count[state] += 1
        print(f"{state:8} {p['id']:24} {p['name'][:40]:40} {why}")
    print(f"\n{count['OK']} OK, {count['CHANGED']} changed, {count['GONE']} gone"
          + ("" if full else " (sizes only; --full also compares the SHA-256)"))
    return 0 if count["CHANGED"] == 0 and count["GONE"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
