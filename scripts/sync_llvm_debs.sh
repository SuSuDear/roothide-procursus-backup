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
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[*] Listing ${SRC_OWNER}/${SRC_REPO}/${SRC_PATH}"

API_URL="https://api.github.com/repos/${SRC_OWNER}/${SRC_REPO}/contents/${SRC_PATH}?ref=${SRC_BRANCH}"
AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

if ! curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: roothide-procursus-backup-bot" \
  "${AUTH_HEADER[@]}" \
  "$API_URL" -o "$TMP_DIR/list.json"; then
  echo "[!] API failed, fallback HTML"
  curl -fsSL -A "Mozilla/5.0" \
    "https://github.com/${SRC_OWNER}/${SRC_REPO}/tree/${SRC_BRANCH}/${SRC_PATH}" \
    -o "$TMP_DIR/page.html"
  python3 - "$TMP_DIR/page.html" > "$TMP_DIR/files.txt" <<'PY'
import re, json, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'data-target="react-app.embeddedData"[^>]*>(\{.*?\})</script>', html, re.S)
if not m:
    raise SystemExit("cannot parse github html")
data = json.loads(m.group(1))
items = data["payload"]["codeViewTreeRoute"]["tree"]["items"]
for it in items:
    name = it.get("name", "")
    if name.endswith(".deb") and it.get("contentType") == "file":
        print(name)
PY
else
  python3 - "$TMP_DIR/list.json" > "$TMP_DIR/files.txt" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))
for it in items:
    if it.get("type") == "file" and str(it.get("name", "")).endswith(".deb"):
        print(it["name"])
PY
fi

COUNT="$(grep -c '\.deb$' "$TMP_DIR/files.txt" || true)"
if [ "${COUNT}" -eq 0 ]; then
  echo "ERROR: no deb files found" >&2
  exit 1
fi
echo "[*] Found ${COUNT} deb files"

while IFS= read -r name; do
  [ -n "$name" ] || continue
  dest="${DEBS_DIR}/${name}"
  enc_name="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="._-"))' "$name")"
  url1="https://github.com/${SRC_OWNER}/${SRC_REPO}/raw/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"
  url2="https://media.githubusercontent.com/media/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"
  url3="https://raw.githubusercontent.com/${SRC_OWNER}/${SRC_REPO}/${SRC_BRANCH}/${SRC_PATH}/${enc_name}"

  ok=0
  for url in "$url1" "$url2" "$url3"; do
    echo "  - download $name"
    echo "    $url"
    rm -f "$dest.partial"
    if curl -fL --retry 3 --retry-delay 2 -A "Mozilla/5.0" -o "$dest.partial" "$url"; then
      if head -c 80 "$dest.partial" | grep -q "git-lfs.github.com/spec"; then
        echo "    skip LFS pointer"
        rm -f "$dest.partial"
        continue
      fi
      magic="$(head -c 7 "$dest.partial" || true)"
      if [ "$magic" != "!<arch>" ]; then
        echo "    invalid deb magic: $magic"
        rm -f "$dest.partial"
        continue
      fi
      mv -f "$dest.partial" "$dest"
      ok=1
      break
    fi
    rm -f "$dest.partial" || true
  done

  if [ "$ok" -ne 1 ]; then
    echo "ERROR: failed $name" >&2
    exit 1
  fi
done < "$TMP_DIR/files.txt"

# no nested dirs
if find "$DEBS_DIR" -mindepth 1 -type d | grep -q .; then
  echo "ERROR: nested dirs under debs/ are not allowed" >&2
  find "$DEBS_DIR" -mindepth 1 -type d >&2
  exit 1
fi

echo "[*] Done. files in debs/:"
ls -la "$DEBS_DIR" | head -80
