#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEBS_DIR="debs"
if [[ ! -d "$DEBS_DIR" ]]; then
  mkdir -p "$DEBS_DIR"
fi

# Flatten safety: no nested dirs under debs
if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: debs/ 下不允许有子目录，请全部平铺 .deb" >&2
  find "$DEBS_DIR" -mindepth 1 -type d >&2
  exit 1
fi

# Prefer dpkg-scanpackages
if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y dpkg-dev
  else
    echo "ERROR: 需要 dpkg-scanpackages (dpkg-dev)" >&2
    exit 1
  fi
fi

echo "[*] Scanning $DEBS_DIR ..."
# -m: multiple versions allowed
dpkg-scanpackages -m "$DEBS_DIR" /dev/null > Packages

# Normalize Filename to ./debs/xxx.deb
# dpkg-scanpackages usually already outputs Filename: debs/xxx.deb
python3 - <<'PY'
from pathlib import Path
p = Path("Packages")
text = p.read_text(errors="replace")
lines = []
for line in text.splitlines(True):
    if line.startswith("Filename: "):
        fn = line[len("Filename: "):].strip()
        fn = fn.lstrip("./")
        if not fn.startswith("debs/"):
            # if somehow only basename
            if "/" not in fn:
                fn = f"debs/{fn}"
        line = f"Filename: ./{fn}\n"
    lines.append(line)
p.write_text("".join(lines))
print(f"[*] Packages entries: {sum(1 for l in lines if l.startswith('Package: '))}")
PY

gzip -9c Packages > Packages.gz
if command -v bzip2 >/dev/null 2>&1; then
  bzip2 -9ck Packages > Packages.bz2
fi

# Update Release checksum block, keep metadata header
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

# Keep only metadata keys before hash sections
meta_keys = {
    "Origin","Label","Suite","Version","Codename","Architectures",
    "Components","Description","Date","Acquire-By-Hash"
}
meta = []
seen = set()
for line in old:
    if not line or line.endswith(":"):
        # stop at MD5Sum:/SHA1: etc
        if line.rstrip(":") in {"MD5Sum","SHA1","SHA256","SHA512"}:
            break
    if ":" in line:
        k = line.split(":",1)[0]
        if k in meta_keys and k not in seen and k != "Date":
            meta.append(line)
            seen.add(k)

# Always refresh Date
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
ls -la Packages Packages.gz Release ${DEBS_DIR}/*.deb 2>/dev/null | head -50 || true
