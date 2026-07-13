#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
DEBS_DIR="${DEBS_DIR:-debs}"
REPO_OWNER="${REPO_OWNER:-SuSuDear}"
REPO_NAME="${REPO_NAME:-roothide-procursus-backup}"
REPO_BRANCH="${REPO_BRANCH:-main}"
SRC_OWNER="${SRC_OWNER:-SuSuDear}"
SRC_REPO="${SRC_REPO:-roothide.github.io}"
SRC_BRANCH="${SRC_BRANCH:-main}"
SRC_PATH="${SRC_PATH:-procursus/pool/main/iphoneos-arm64e/1900}"

mkdir -p "$DEBS_DIR"
count=0
fixed=0
ok=0
for f in "$DEBS_DIR"/*.deb; do
  [ -f "$f" ] || continue
  count=$((count+1))
  headc="$(head -c 80 "$f" || true)"
  if ! printf '%s' "$headc" | grep -q 'git-lfs.github.com/spec'; then
    # already real?
    magic="$(head -c 7 "$f" || true)"
    if [ "$magic" = '!<arch>' ]; then
      ok=$((ok+1))
      continue
    fi
  fi
  name="$(basename "$f")"
  enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="._-"))' "$name")"
  urls=(
    "https://media.githubusercontent.com/media/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/debs/${enc}"
    "https://github.com/${REPO_OWNER}/${REPO_NAME}/raw/${REPO_BRANCH}/debs/${enc}"
  )
  # also try source pool recursively basename search via media on source if path known from Packages? skip
  got=0
  for url in "${urls[@]}"; do
    rm -f "$f.partial"
    if curl -fL --retry 3 --retry-delay 1 --connect-timeout 15 --max-time 600 -A 'Mozilla/5.0' -o "$f.partial" "$url"; then
      if head -c 80 "$f.partial" | grep -q 'git-lfs.github.com/spec'; then
        rm -f "$f.partial"; continue
      fi
      if [ "$(head -c 7 "$f.partial" || true)" != '!<arch>' ]; then
        rm -f "$f.partial"; continue
      fi
      mv -f "$f.partial" "$f"
      fixed=$((fixed+1))
      got=1
      break
    fi
    rm -f "$f.partial" || true
  done
  if [ "$got" -ne 1 ]; then
    echo "WARN: could not materialize $name" >&2
  fi
done
echo "[*] materialize done: total=$count already_ok=$ok fixed=$fixed"
