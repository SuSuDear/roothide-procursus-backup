#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SRC_OWNER="${SRC_OWNER:-SuSuDear}"
SRC_REPO="${SRC_REPO:-roothide.github.io}"
SRC_BRANCH="${SRC_BRANCH:-main}"
# 整个 1900 目录（所有包），不是只 llvm
SRC_PATH="${SRC_PATH:-procursus/pool/main/iphoneos-arm64e/1900}"
DEBS_DIR="${DEBS_DIR:-debs}"

mkdir -p "$DEBS_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[*] Sync ALL .deb under ${SRC_OWNER}/${SRC_REPO}/${SRC_PATH}"
echo "[*] Flat output: ${DEBS_DIR}/<filename>.deb  (no subdirs)"

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

# Use recursive git tree API to list every file under the repo, then filter by SRC_PATH
TREE_URL="https://api.github.com/repos/${SRC_OWNER}/${SRC_REPO}/git/trees/${SRC_BRANCH}?recursive=1"
echo "[*] Fetching recursive tree: $TREE_URL"
if ! curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: roothide-procursus-backup-bot" \
  "${AUTH_HEADER[@]}" \
  "$TREE_URL" -o "$TMP_DIR/tree.json"; then
  echo "ERROR: failed to fetch git tree (API). Check token/rate limit." >&2
  exit 1
fi

python3 - "$TMP_DIR/tree.json" "$SRC_PATH" > "$TMP_DIR/files.tsv" <<'PY'
import json, sys
tree = json.load(open(sys.argv[1]))
prefix = sys.argv[2].strip("/") + "/"
items = tree.get("tree") or []
if tree.get("truncated"):
    print("WARNING: github tree truncated; some files may be missing", file=sys.stderr)

count = 0
for it in items:
    if it.get("type") != "blob":
        continue
    path = it.get("path") or ""
    if not path.startswith(prefix):
        continue
    if not path.endswith(".deb"):
        continue
    # relative path under SRC_PATH, and basename for flat dest
    rel = path[len(prefix):]
    name = rel.split("/")[-1]
    # path\tbasename
    print(f"{path}\t{name}")
    count += 1
print(f"[*] Matched {count} deb files under {prefix}", file=sys.stderr)
if count == 0:
    sys.exit(2)
PY

COUNT="$(wc -l < "$TMP_DIR/files.tsv" | tr -d ' ')"
if [ "${COUNT}" -eq 0 ]; then
  echo "ERROR: no deb files found under $SRC_PATH" >&2
  exit 1
fi
echo "[*] Will download ${COUNT} deb files into ${DEBS_DIR}/"

DOWNLOADED=0
SKIPPED=0
FAILED=0
COLLISIONS=0

while IFS=$'\t' read -r repo_path name; do
  [ -n "$name" ] || continue
  dest="${DEBS_DIR}/${name}"

  # If same basename already exists from another package dir, keep first / overwrite with note
  if [ -f "$dest" ]; then
    # same size? skip redownload if already valid deb
    if head -c 7 "$dest" 2>/dev/null | grep -q '!<arch>'; then
      # still re-download to refresh; but log collision
      echo "  ! name collision / refresh: $name  (from $repo_path)"
      COLLISIONS=$((COLLISIONS + 1))
    fi
  fi

  enc_path="$(python3 -c 'import urllib.parse,sys; print("/".join(urllib.parse.quote(p, safe="._-") for p in sys.argv[1].split("/")))' "$repo_path")"
  url1="https://github.com/${SRC_OWNER}/${SRC_REPO}/raw/${SRC_BRANCH}/${enc_path}"
  url2="https://media.githubusercontent.com/media/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${enc_path}"
  url3="https://raw.githubusercontent.com/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${enc_path}"

  ok=0
  for url in "$url1" "$url2" "$url3"; do
    rm -f "$dest.partial"
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 \
      -A "Mozilla/5.0" -o "$dest.partial" "$url"; then
      if head -c 80 "$dest.partial" | grep -q "git-lfs.github.com/spec"; then
        rm -f "$dest.partial"
        continue
      fi
      magic="$(head -c 7 "$dest.partial" || true)"
      if [ "$magic" != "!<arch>" ]; then
        rm -f "$dest.partial"
        continue
      fi
      mv -f "$dest.partial" "$dest"
      ok=1
      break
    fi
    rm -f "$dest.partial" || true
  done

  if [ "$ok" -eq 1 ]; then
    DOWNLOADED=$((DOWNLOADED + 1))
    if [ $((DOWNLOADED % 25)) -eq 0 ]; then
      echo "[*] progress: ${DOWNLOADED}/${COUNT}"
    fi
  else
    echo "ERROR: failed $repo_path" >&2
    FAILED=$((FAILED + 1))
    # 不立刻退出：尽量多下；最后汇总失败
  fi
done < "$TMP_DIR/files.tsv"

# forbid nested directories
if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: nested dirs under debs/ are not allowed" >&2
  find "$DEBS_DIR" -mindepth 1 -type d >&2
  exit 1
fi

echo "[*] Done"
echo "    total listed : $COUNT"
echo "    downloaded   : $DOWNLOADED"
echo "    failed       : $FAILED"
echo "    collisions   : $COLLISIONS"
echo "    files in debs: $(find "$DEBS_DIR" -type f -name '*.deb' | wc -l | tr -d ' ')"

if [ "$FAILED" -gt 0 ]; then
  echo "ERROR: some downloads failed" >&2
  exit 1
fi
if [ "$DOWNLOADED" -eq 0 ]; then
  echo "ERROR: nothing downloaded" >&2
  exit 1
fi
