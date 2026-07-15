# Sourced by every example. Deliberately tiny: the registry handling stays VISIBLE in each
# example (that is the thing people found unclear), this only puts the binaries on PATH and turns a
# finished registry into data the graph viewer can render.
EXROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$EXROOT/bin:$PATH"

# snapshot <example-name> <keydir> --reg <registry-dir> [--reg ...]
# Writes docs/data/<name>/{union,keys,names}.json (committed) so the viewer shows this example.
snapshot() {
  local name="$1" keydir="$2"; shift 2
  python3 "$EXROOT/viewer/build_union.py" --out "$EXROOT/docs/data/$name" --keydir "$keydir" "$@"
  echo "  SEE IT: docs/viewer.html?union=data/$name/union.json&keys=data/$name/keys.json&names=data/$name/names.json"
}
