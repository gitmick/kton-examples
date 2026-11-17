#!/usr/bin/env bash
# The lens and the graph viewer this page uses, from kton-web at a pinned commit, into kw/ (+ lens.js,
# viewer.html). The other pages in docs/ keep docs/lens.js and docs/viewer.html; this one reads the
# current viewer: ↻N over every signature on a foton, people and keys named without a red mark.
#   ./vendor-kton-web.sh [kton-web checkout] [commit]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KW="${1:-/mnt/c/dev/git-repos/kton-web}"; REV=$(git -C "$KW" rev-parse "${2:-HEAD}")
[ -f "$KW/runtime/wasm/kton-full.wasm" ] || { echo "no built wasm in $KW/runtime/wasm - run wasm/build.sh there" >&2; exit 1; }
rm -rf "$HERE/kw"; mkdir -p "$HERE/kw"
git -C "$KW" archive "$REV" core runtime viewers/graph viewers/compass viewers/lens sketches | tar -x -C "$HERE/kw"
mkdir -p "$HERE/kw/runtime/wasm"; cp "$KW/runtime/wasm/kton-full.wasm" "$KW/runtime/wasm/manifest.json" "$HERE/kw/runtime/wasm/"
cp "$HERE/kw/viewers/lens/lens.js" "$HERE/lens.js"
cat > "$HERE/viewer.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>kton · graph viewer</title>
<script>
// hand the lens's parameters on into kw/: every ?union= (one per registry), made absolute; the
// talk view (descriptions as labels, statements folded into their steps) unless one is named
var q = new URLSearchParams(location.search), out = new URLSearchParams();
q.forEach(function (v, k) {
  out.append(k, ["union", "keys", "names", "graph", "select"].indexOf(k) >= 0 ? new URL(v, location.href).href : v); });
if (!out.has("view")) out.set("view", JSON.stringify({ preset: "pmx", graph: { hide: ["claim", "ref", "entity", "source:code", "source:single-use"] } }));
location.replace("kw/viewers/graph/index.html?" + out.toString() + location.hash);
</script>
HTML
{ echo "kton-web $REV"; echo "kernel pin $(grep -o 'KTON_COMMIT:-[0-9a-f]*' "$KW/wasm/fetch-kernel.sh" | cut -d- -f2)"; } > "$HERE/KTON-WEB.txt"
cat "$HERE/KTON-WEB.txt"
