#!/usr/bin/env bash
# Backward-compatible wrapper: now syncs the whole 1900 tree, not only llvm.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SRC_PATH="${SRC_PATH:-procursus/pool/main/iphoneos-arm64e/1900}"
exec "$ROOT_DIR/scripts/sync_pool_debs.sh"
