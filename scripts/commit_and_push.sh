#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BRANCH_NAME="${BRANCH_NAME:-main}"
REPO_OWNER="${REPO_OWNER:-SuSuDear}"
REPO_NAME="${REPO_NAME:-roothide-procursus-backup}"
RELEASE_TAG="${RELEASE_TAG:-debs-large}"
LIMIT=$((100 * 1024 * 1024))

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Ensure no LFS for deb
cat > .gitattributes <<'ATTR'
# deb files must NOT use Git LFS (Pages cannot serve LFS content).
ATTR

# Split large debs out of git tree
mkdir -p .large-debs
large_count=0
if compgen -G 'debs/*.deb' > /dev/null; then
  for f in debs/*.deb; do
    sz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
    if [ "$sz" -gt "$LIMIT" ]; then
      echo "[*] large deb -> release: $f ($sz bytes)"
      mv -f "$f" ".large-debs/$(basename "$f")"
      large_count=$((large_count+1))
    fi
  done
fi

# Upload large debs to GitHub Release if any
if [ "$large_count" -gt 0 ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI required to upload large debs" >&2
    exit 1
  fi
  if ! gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release create "$RELEASE_TAG" --title "Large debs (>100MB)" --notes "Auto-uploaded packages larger than GitHub 100MB limit"
  fi
  for f in .large-debs/*.deb; do
    [ -f "$f" ] || continue
    echo "[*] upload release asset $(basename "$f")"
    # clobber if exists
    gh release upload "$RELEASE_TAG" "$f" --clobber
  done
fi

# Stage normal files only
git add .gitattributes Packages Packages.gz Packages.bz2 Release scripts .github/workflows || true
# add only small debs
if compgen -G 'debs/*.deb' > /dev/null; then
  git add debs/*.deb
fi
# if some large were previously tracked, remove from git index (keep release)
if [ "$large_count" -gt 0 ]; then
  for f in .large-debs/*.deb; do
    bn="$(basename "$f")"
    git rm -f --cached "debs/$bn" 2>/dev/null || true
  done
fi

# Safety: refuse staged LFS pointers / >100MB blobs
python3 - <<'PY'
import subprocess, os, sys
out=subprocess.check_output(['git','diff','--cached','--name-only'], text=True)
bad=[]
for f in out.splitlines():
    if not f.endswith('.deb'):
        continue
    if not os.path.isfile(f):
        continue
    data=open(f,'rb').read(100)
    size=os.path.getsize(f)
    if data.startswith(b'version https://git-lfs.github.com/spec'):
        bad.append((f, size, 'LFS pointer'))
    elif size > 100*1024*1024:
        bad.append((f, size, 'too large for git blob'))
    elif not data.startswith(b'!<arch>'):
        bad.append((f, size, 'invalid deb'))
if bad:
    print('ERROR staged deb issues:')
    for f,s,why in bad:
        print(f'  {f}: {s} ({why})')
    sys.exit(1)
print('pre-commit deb checks OK')
PY

if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi

git commit -m "chore: publish real debs without LFS $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push origin "HEAD:${BRANCH_NAME}"
echo "push ok"
