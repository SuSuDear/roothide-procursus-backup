#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SRC_OWNER="${SRC_OWNER:-SuSuDear}"
SRC_REPO="${SRC_REPO:-roothide.github.io}"
SRC_BRANCH="${SRC_BRANCH:-main}"
SRC_PATH="${SRC_PATH:-procursus/pool/main/iphoneos-arm64e/1900/llvm}"
DEBS_DIR="${DEBS_DIR:-debs}"

mkdir -p "$DEBS_DIR"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "[*] Fetching file list from ${SRC_OWNER}/${SRC_REPO}:${SRC_PATH}"

# Prefer GitHub API; fall back to HTML embedded JSON
LIST_JSON="$TMP_DIR/list.json"
API_URL="https://api.github.com/repos/${SRC_OWNER}/${SRC_REPO}/contents/${SRC_PATH}?ref=${SRC_BRANCH}"
if curl -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: roothide-procursus-backup-bot" \
  ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
  "$API_URL" -o "$LIST_JSON"; then
  python3 - <<'PY' "$LIST_JSON" > "$TMP_DIR/files.txt"
import json,sys
items=json.load(open(sys.argv[1]))
for it in items:
    if it.get("type")=="file" and it.get("name","").endswith(".deb"):
        print(it["name"])
PY
else
  echo "[!] API failed, fallback to HTML parse"
  HTML_URL="https://github.com/${SRC_OWNER}/${SRC_REPO}/tree/${SRC_BRANCH}/${SRC_PATH}"
  curl -fsSL -A "Mozilla/5.0" "$HTML_URL" -o "$TMP_DIR/page.html"
  python3 - <<'PY' "$TMP_DIR/page.html" > "$TMP_DIR/files.txt"
import re,json,sys
html=open(sys.argv[1],encoding='utf-8',errors='replace').read()
m=re.search(r'data-target="react-app.embeddedData"[^>]*>(\{.*?\})</script>', html, re.S)
if not m:
    raise SystemExit('cannot parse github page')
data=json.loads(m.group(1))
items=data['payload']['codeViewTreeRoute']['tree']['items']
for it in items:
    name=it.get('name','')
    if name.endswith('.deb') and it.get('contentType')=='file':
        print(name)
PY
fi

mapfile -t FILES < <(grep -E '\.deb$' "$TMP_DIR/files.txt" || true)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: no .deb found under $SRC_PATH" >&2
  exit 1
fi

echo "[*] Found ${#FILES[@]} deb files"
DOWNLOADED=0
for name in "${FILES[@]}"; do
  # Flat only: debs/filename.deb  (no debs/llvm/...)
  dest="${DEBS_DIR}/${name}"
  # Prefer github raw entry (handles LFS redirect to media.githubusercontent.com)
  # Encode ~ as %7E for safety
  enc_name="$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('''$name''', safe='._-'))
PY
)"
  url1="https://github.com/${SRC_OWNER}/${SRC_REPO}/raw/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"
  url2="https://media.githubusercontent.com/media/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"
  url3="https://raw.githubusercontent.com/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"

  ok=0
  for url in "$url1" "$url2" "$url3"; do
    echo "  - $name <= $url"
    if curl -fL --retry 3 --retry-delay 2 -A "Mozilla/5.0" -o "$dest.partial" "$url"; then
      # Reject Git LFS pointer
      if head -c 64 "$dest.partial" | grep -q "git-lfs.github.com/spec"; then
        echo "    LFS pointer, try next mirror"
        rm -f "$dest.partial"
        continue
      fi
      # deb must start with !<arch>
      magic="$(head -c 7 "$dest.partial" || true)"
      if [[ "$magic" != "!<arch>" ]]; then
        echo "    invalid deb magic: $magic"
        rm -f "$dest.partial"
        continue
      fi
      mv -f "$dest.partial" "$dest"
      ok=1
      DOWNLOADED=$((DOWNLOADED+1))
      break
    fi
    rm -f "$dest.partial" || true
  done
  if [[ $ok -ne 1 ]]; then
    echo "ERROR: failed to download $name" >&2
    exit 1
  fi
done

# Ensure no subdirectories were created
if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: debs/ 下出现了子目录" >&2
  find "$DEBS_DIR" -mindepth 1 -type d >&2
  exit 1
fi

echo "[*] Downloaded $DOWNLOADED deb files into $DEBS_DIR/ (flat)"
ls -la "$DEBS_DIR" | head -50
