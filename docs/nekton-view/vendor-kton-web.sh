#!/usr/bin/env bash
# The nekton viewer (and the graph and compass it opens) from kton-web at a pinned commit, into kw/.
#   ./vendor-kton-web.sh [kton-web checkout] [commit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KW="${1:-/mnt/c/dev/git-repos/kton-web}"; REV=$(git -C "$KW" rev-parse "${2:-HEAD}")
[ -f "$KW/runtime/wasm/kton-full.wasm" ] || { echo "no built wasm in $KW/runtime/wasm - run wasm/build.sh there" >&2; exit 1; }
rm -rf "$HERE/kw"; mkdir -p "$HERE/kw"
git -C "$KW" archive "$REV" core runtime viewers/nekton viewers/graph viewers/compass sketches | tar -x -C "$HERE/kw"
mkdir -p "$HERE/kw/runtime/wasm"; cp "$KW/runtime/wasm/kton-full.wasm" "$KW/runtime/wasm/manifest.json" "$HERE/kw/runtime/wasm/"
{ echo "kton-web $REV"; echo "kernel pin $(grep -o 'KTON_COMMIT:-[0-9a-f]*' "$KW/wasm/fetch-kernel.sh" | cut -d- -f2)"; } > "$HERE/KTON-WEB.txt"
cat "$HERE/KTON-WEB.txt"
