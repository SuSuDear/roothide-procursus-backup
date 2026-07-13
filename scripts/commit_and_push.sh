#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BRANCH_NAME="${BRANCH_NAME:-main}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git lfs install

if [ ! -f .gitattributes ] || ! grep -q '*.deb' .gitattributes; then
  printf '%s\n' '*.deb filter=lfs diff=lfs merge=lfs -text' > .gitattributes
fi

git lfs track "*.deb"
git add .gitattributes
git add -A debs Packages Packages.gz Packages.bz2 Release scripts .github/workflows .gitattributes || true

git lfs status || true
git lfs ls-files | head -50 || true

if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi

# Ensure staged large debs are LFS pointers
python3 - <<'PY'
import subprocess, sys
out = subprocess.check_output(["git", "diff", "--cached", "--name-only"], text=True)
bad = []
for f in out.splitlines():
    if not f.endswith(".deb"):
        continue
    try:
        blob = subprocess.check_output(["git", "show", f":{f}"], stderr=subprocess.DEVNULL)
    except Exception:
        continue
    if (not blob.startswith(b"version https://git-lfs.github.com/spec")
            and len(blob) > 100 * 1024 * 1024):
        bad.append((f, len(blob)))
if bad:
    print("ERROR: staged deb files exceed 100MB and are not LFS pointers:")
    for f, s in bad:
        print(f"  {f}: {s/1024/1024:.1f} MB")
    sys.exit(1)
print("pre-commit size check OK")
PY

git commit -m "chore: sync llvm debs and regenerate Packages $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push origin "HEAD:${BRANCH_NAME}"
echo "push ok"
