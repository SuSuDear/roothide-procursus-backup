#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEBS_DIR="debs"
LIMIT=$((100 * 1024 * 1024))
SRC_MEDIA_BASE="${SRC_MEDIA_BASE:-https://media.githubusercontent.com/media/SuSuDear/roothide.github.io/main}"

mkdir -p "$DEBS_DIR"
if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: debs/ must be flat" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import sys
bad=[]
for p in Path('debs').glob('*.deb'):
    b=p.read_bytes()[:100]
    if b.startswith(b'version https://git-lfs.github.com/spec') or not b.startswith(b'!<arch>'):
        # large files may be absent (served from source media); allow missing later
        if p.stat().st_size < 1024:
            bad.append(p.name)
if bad:
    print('WARN small/invalid local debs:', bad[:20])
print('[*] local scan note done')
PY

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y dpkg-dev
fi

# Prefer scanning local real debs. If some large ones moved away, still ok if they remain for hash.
echo "[*] dpkg-scanpackages..."
dpkg-scanpackages -m "$DEBS_DIR" /dev/null > Packages || true

python3 - <<PY
import re
from pathlib import Path
from urllib.parse import quote
limit = ${LIMIT}
src_media = "${SRC_MEDIA_BASE}".rstrip("/")
KNOWN = {
  "swift-5.7.2_5.7.2~RELEASE_iphoneos-arm64e.deb":
    "https://github.com/SuSuDear/roothide-procursus-backup/releases/download/debs-large/swift-5.7.2_5.7.2.RELEASE_iphoneos-arm64e.deb",
  "llvm-14-dev_14.0.0~5.7.2~RELEASE_iphoneos-arm64e.deb":
    "https://github.com/SuSuDear/roothide-procursus-backup/releases/download/debs-large/llvm-14-dev_14.0.0.5.7.2.RELEASE_iphoneos-arm64e.deb",
  "libclang-14-dev_14.0.0~5.7.2~RELEASE_iphoneos-arm64e.deb":
    "https://github.com/SuSuDear/roothide-procursus-backup/releases/download/debs-large/libclang-14-dev_14.0.0.5.7.2.RELEASE_iphoneos-arm64e.deb",
}

def fix_name(name: str) -> str:
    n = name.split("?")[0]
    n = n.replace(".RELEASE_", "~RELEASE_")
    n = re.sub(r"(\d+\.\d+\.\d+)\.(\d+\.\d+\.\d+)\.RELEASE_", r"\1~\2~RELEASE_", n)
    n = re.sub(r"_(\d+\.\d+\.\d+)\.RELEASE_", r"_\1~RELEASE_", n)
    return n

def media_url(path: str) -> str:
    enc = "/".join(quote(p, safe="._-") for p in path.split("/"))
    return f"{src_media}/{enc}"

text = Path("Packages").read_text(errors="replace")
blocks = [b for b in text.strip().split("\n\n") if b.strip()]
out=[]
rel=med=0
for b in blocks:
    lines=b.splitlines(); meta={}; order=[]
    for line in lines:
        if ": " in line:
            k,v=line.split(": ",1); meta[k]=v; order.append(k)
        else:
            order.append(line)
    name = fix_name(meta.get("Filename","").rstrip("/").split("/")[-1])
    size = int(meta.get("Size","0") or 0)
    if name in KNOWN or size > limit:
        url = KNOWN.get(name)
        if url and url.startswith("http"):
            meta["Filename"] = url
        else:
            path = url or f"procursus/pool/main/iphoneos-arm64e/1900/{meta.get('Package','unknown')}/{name}"
            meta["Filename"] = media_url(path)
        med += 1
    else:
        meta["Filename"] = f"./debs/{name}"
        rel += 1
    new=[]; seen=set()
    for item in order:
        if item in meta and item not in seen:
            new.append(f"{item}: {meta[item]}"); seen.add(item)
        elif item not in meta:
            new.append(item)
    for k,v in meta.items():
        if k not in seen:
            new.append(f"{k}: {v}")
    out.append("\n".join(new))
Path("Packages").write_text("\n\n".join(out)+"\n")
print(f"[*] Filename relative={rel} media_large={med}")
PY

gzip -9c Packages > Packages.gz
if command -v bzip2 >/dev/null 2>&1; then bzip2 -9ck Packages > Packages.bz2; fi

python3 - <<'PY'
import hashlib
from pathlib import Path
from datetime import datetime, timezone
release_path=Path('Release')
old=release_path.read_text(errors='replace').splitlines() if release_path.exists() else []
meta_keys={"Origin","Label","Suite","Version","Codename","Architectures","Components","Description","Date"}
meta=[]; seen=set()
for line in old:
    if line.rstrip(':') in {"MD5Sum","SHA1","SHA256","SHA512"}: break
    if ':' in line:
        k=line.split(':',1)[0]
        if k in meta_keys and k not in seen and k!='Date':
            meta.append(line); seen.add(k)
meta.append('Date: '+datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000'))
files=['Packages','Packages.gz'] + (['Packages.bz2'] if Path('Packages.bz2').exists() else [])
def dig(p):
 d=Path(p).read_bytes();
 return len(d),hashlib.md5(d).hexdigest(),hashlib.sha1(d).hexdigest(),hashlib.sha256(d).hexdigest(),hashlib.sha512(d).hexdigest()
info={f:dig(f) for f in files}
out=meta+['MD5Sum:']+[f' {info[f][1]} {info[f][0]:>16} {f}' for f in files]+['SHA1:']+[f' {info[f][2]} {info[f][0]:>16} {f}' for f in files]+['SHA256:']+[f' {info[f][3]} {info[f][0]:>16} {f}' for f in files]+['SHA512:']+[f' {info[f][4]} {info[f][0]:>16} {f}' for f in files]+['']
Path('Release').write_text('\n'.join(out))
print('[*] Release updated')
PY
echo '[*] generate_packages done'
