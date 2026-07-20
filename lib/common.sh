# Sourced by every example. Deliberately tiny: the registry handling stays VISIBLE in each
# example (that is the thing people found unclear), this only puts the binaries on PATH and turns a
# finished registry into data the graph viewer can render.
EXROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$EXROOT/bin:$PATH"

# ---- byte locators: every recorded input/output gets a fetch `uri` = its committed permalink ------
# Each example PERSISTS its .work/ (see .gitignore), so a foton's recorded input/output path IS a real
# file in this repo. We shadow `plankton` so that `plankton author` automatically attaches, to EVERY
# --in/--out, a CARRIED `uri` = that path's raw permalink (carried => NOT part of the foton id, so it
# never changes lineage). A reader can then fetch the exact bytes behind any node. RAWBASE is derived
# from the calling example's own directory; the pin below is the ONE line rewritten at each release/
# migration (gitmick -> kton-protocol, main -> the release commit SHA).
KTON_RAW_REPO="${KTON_RAW_REPO:-gitmick/kton-examples}"
KTON_RAW_COMMIT="${KTON_RAW_COMMIT:-main}"            # PIN: set to the release commit SHA at publish
RAWBASE="https://raw.githubusercontent.com/${KTON_RAW_REPO}/${KTON_RAW_COMMIT}/${PWD#"$EXROOT"/}"

plankton() {
  if [ "${1:-}" != "author" ]; then command plankton "$@"; return; fi
  shift
  local -a a=("$@") extra=()
  local i v logical localp
  for ((i = 0; i < ${#a[@]}; i++)); do
    case "${a[i]}" in
      --in | --out)
        v="${a[i + 1]:-}"; [ -n "$v" ] || continue
        if [[ "$v" == *=* ]]; then logical="${v%%=*}"; localp="${v#*=}"; else logical="$v"; localp="$v"; fi
        logical="${logical#./}"; localp="${localp#./}"
        case "$localp" in /*) : ;;                    # absolute path: no repo home, cannot locate
          *) extra+=(--located "$logical=$RAWBASE/$localp") ;;
        esac
        ;;
    esac
  done
  command plankton author "$@" ${extra[@]+"${extra[@]}"}
}

# snapshot <example-name> <keydir> --reg <registry-dir> [--reg ...]
# Writes docs/data/<name>/{union,keys,names}.json (committed) so the viewer shows this example.
snapshot() {
  local name="$1" keydir="$2"; shift 2
  python3 "$EXROOT/viewer/build_union.py" --out "$EXROOT/docs/data/$name" --keydir "$keydir" "$@"
  echo "  SEE IT: docs/viewer.html?union=data/$name/union.json&keys=data/$name/keys.json&names=data/$name/names.json"
}
