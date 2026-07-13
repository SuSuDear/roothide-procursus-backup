#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEBS_DIR="debs"
REPO_OWNER="${REPO_OWNER:-SuSuDear}"
REPO_NAME="${REPO_NAME:-roothide-procursus-backup}"
RELEASE_TAG="${RELEASE_TAG:-debs-large}"
RELEASE_BASE="${RELEASE_BASE:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${RELEASE_TAG}}"
LIMIT=$((100 * 1024 * 1024))

mkdir -p "$DEBS_DIR"

if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: debs/ must be flat" >&2
  exit 1
fi

# Fail if any pointer remains
python3 - <<'PY'
from pathlib import Path
import sys
bad=[]
for p in Path('debs').glob('*.deb'):
    b=p.read_bytes()[:100]
    if b.startswith(b'version https://git-lfs.github.com/spec') or not b.startswith(b'!<arch>'):
        bad.append((p.name, p.stat().st_size, b[:20]))
if bad:
    print('ERROR: non-real deb files present (LFS pointer or invalid):', file=sys.stderr)
    for n,s,h in bad[:30]:
        print(f'  {n}: {s}B head={h!r}', file=sys.stderr)
    print('Run scripts/sync_pool_debs.sh first (downloads real debs).', file=sys.stderr)
    sys.exit(1)
print('[*] all deb files are real ar archives')
PY

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y dpkg-dev
fi

echo "[*] Scanning $DEBS_DIR ..."
dpkg-scanpackages -m "$DEBS_DIR" /dev/null > Packages

python3 - <<PY
from pathlib import Path
limit = ${LIMIT}
release_base = "${RELEASE_BASE}".rstrip('/')
text = Path('Packages').read_text(errors='replace')
out=[]
small=large=0
for line in text.splitlines(True):
    if line.startswith('Filename: '):
        fn = line[len('Filename: '):].strip().lstrip('./')
        name = fn.split('/')[-1]
        path = Path('debs')/name
        size = path.stat().st_size if path.exists() else 0
        if size > limit:
            line = f'Filename: {release_base}/{name}\n'
            large += 1
        else:
            # 相对路径：同域 Pages/自定义域名可直接下到真实 deb（非 LFS）
            line = f'Filename: ./debs/{name}\n'
            small += 1
    out.append(line)
Path('Packages').write_text(''.join(out))
print(f'[*] Filename small(relative)= {small}, large(release)= {large}')
# show llvm-14
lines=''.join(out).splitlines()
for i,l in enumerate(lines):
    if l=='Package: llvm-14':
        print('\\n'.join(lines[i:i+10])); break
PY

gzip -9c Packages > Packages.gz
if command -v bzip2 >/dev/null 2>&1; then
  bzip2 -9ck Packages > Packages.bz2
fi

python3 - <<'PY'
import hashlib
from pathlib import Path
from datetime import datetime, timezone
release_path=Path('Release')
old=release_path.read_text(errors='replace').splitlines() if release_path.exists() else [
 'Origin: -苏苏源','Label: 苏苏自用源','Suite: stable','Version: 1.0','Codename: ios',
 'Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e','Components: main','Description: QQ2914115314'
]
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
release_path.write_text('\n'.join(out))
print('[*] Release updated')
PY
echo '[*] Done generate_packages'
