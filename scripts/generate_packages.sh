#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEBS_DIR="debs"
REPO_OWNER="${REPO_OWNER:-SuSuDear}"
REPO_NAME="${REPO_NAME:-roothide-procursus-backup}"
REPO_BRANCH="${REPO_BRANCH:-main}"
# GitHub Pages / raw 会返回 LFS 指针(~130B)。必须用 media 地址拿真实 deb。
DEB_BASE_URL="${DEB_BASE_URL:-https://media.githubusercontent.com/media/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}}"

mkdir -p "$DEBS_DIR"

if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: debs/ must be flat (no subdirectories)" >&2
  find "$DEBS_DIR" -mindepth 1 -type d >&2
  exit 1
fi

# Reject LFS pointer files in debs/ (would poison Size/MD5)
python3 - <<'PY'
from pathlib import Path
import sys
bad=[]
for p in Path("debs").glob("*.deb"):
    head=p.read_bytes()[:120]
    if head.startswith(b"version https://git-lfs.github.com/spec"):
        bad.append((p.name, p.stat().st_size))
if bad:
    print("ERROR: these debs are Git LFS pointers, not real packages:", file=sys.stderr)
    for n,s in bad[:20]:
        print(f"  {n}: {s} bytes", file=sys.stderr)
    print("Re-run sync script / ensure LFS smudge downloads real files before scanning.", file=sys.stderr)
    sys.exit(1)
print("[*] local deb files look like real binaries (not LFS pointers)")
PY

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y dpkg-dev
  else
    echo "ERROR: dpkg-scanpackages required" >&2
    exit 1
  fi
fi

echo "[*] Scanning $DEBS_DIR ..."
dpkg-scanpackages -m "$DEBS_DIR" /dev/null > Packages

# Rewrite Filename to absolute media URL so Sileo/apt get real LFS content
# Keep Size/MD5/SHA from real local deb content.
python3 - <<PY
from pathlib import Path
base = "${DEB_BASE_URL}".rstrip("/")
text = Path("Packages").read_text(errors="replace")
out = []
count = 0
for line in text.splitlines(True):
    if line.startswith("Filename: "):
        fn = line[len("Filename: "):].strip().lstrip("./")
        # normalize to debs/name.deb
        name = fn.split("/")[-1]
        abs_url = f"{base}/debs/{name}"
        line = f"Filename: {abs_url}\n"
        count += 1
    out.append(line)
Path("Packages").write_text("".join(out))
print(f"[*] Packages entries: {sum(1 for l in out if l.startswith('Package: '))}")
print(f"[*] Filename rewritten to absolute media URLs: {count}")
print(f"[*] Example base: {base}/debs/")
PY

# sanity: no relative debs paths left
if grep -q '^Filename: \./debs/' Packages || grep -q '^Filename: debs/' Packages; then
  echo "ERROR: relative Filename still present" >&2
  grep '^Filename:' Packages | head >&2
  exit 1
fi

gzip -9c Packages > Packages.gz
if command -v bzip2 >/dev/null 2>&1; then
  bzip2 -9ck Packages > Packages.bz2
fi

python3 - <<'PY'
import hashlib
from pathlib import Path
from datetime import datetime, timezone

release_path = Path("Release")
if release_path.exists():
    old = release_path.read_text(errors="replace").splitlines()
else:
    old = [
        "Origin: -苏苏源",
        "Label: 苏苏自用源",
        "Suite: stable",
        "Version: 1.0",
        "Codename: ios",
        "Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e",
        "Components: main",
        "Description: QQ2914115314",
    ]

meta_keys = {
    "Origin","Label","Suite","Version","Codename","Architectures",
    "Components","Description","Date","Acquire-By-Hash"
}
meta = []
seen = set()
for line in old:
    if not line or line.endswith(":"):
        if line.rstrip(":") in {"MD5Sum","SHA1","SHA256","SHA512"}:
            break
    if ":" in line:
        k = line.split(":",1)[0]
        if k in meta_keys and k not in seen and k != "Date":
            meta.append(line)
            seen.add(k)

date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
meta.append(f"Date: {date}")

files = ["Packages", "Packages.gz"]
if Path("Packages.bz2").exists():
    files.append("Packages.bz2")

def digests(path: Path):
    data = path.read_bytes()
    return {
        "size": len(data),
        "md5": hashlib.md5(data).hexdigest(),
        "sha1": hashlib.sha1(data).hexdigest(),
        "sha256": hashlib.sha256(data).hexdigest(),
        "sha512": hashlib.sha512(data).hexdigest(),
    }

info = {f: digests(Path(f)) for f in files}
out = []
out.extend(meta)
out.append("MD5Sum:")
for f in files:
    i = info[f]
    out.append(f" {i['md5']} {i['size']:>16} {f}")
out.append("SHA1:")
for f in files:
    i = info[f]
    out.append(f" {i['sha1']} {i['size']:>16} {f}")
out.append("SHA256:")
for f in files:
    i = info[f]
    out.append(f" {i['sha256']} {i['size']:>16} {f}")
out.append("SHA512:")
for f in files:
    i = info[f]
    out.append(f" {i['sha512']} {i['size']:>16} {f}")
out.append("")
release_path.write_text("\n".join(out))
print("[*] Release updated")
for f in files:
    print(f"    {f}: {info[f]['size']} bytes")
PY

echo "[*] Done."
# show one example
grep -A8 '^Package: llvm-14$' Packages | head -20 || true
