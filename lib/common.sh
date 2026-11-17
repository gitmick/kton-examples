# Sourced by every example. Deliberately tiny: the registry handling stays VISIBLE in each
# example (that is the thing people found unclear), this only puts the binaries on PATH and turns a
# finished registry into data the graph viewer can render.
EXROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$EXROOT/bin:$PATH"
EXNAME="$(basename "$PWD")"     # captured HERE: 09 cds into .work/ after sourcing this file

# ---- reproducible demo identities and a fixed clock -------------------------------------------
# The graph snapshots under docs/data/ are COMMITTED, so every run diffs against the last one. Two
# things used to make that diff meaningless: a fresh random keypair per run - the public key lands
# inside the signed payload, and in example 07 it IS the identity IRI - and a wall-clock `when` on
# `nekton seed`/`annotate`. Both are fixable since kton 0.2 (`keygen --seed`, `--when`), so the
# examples pass them EXPLICITLY at each call rather than through a wrapper that quietly rewrites
# `keygen`. Someone reading a run.sh should be able to see why the snapshot is stable, and the flag
# that does it is a real part of the CLI, worth showing.
#
# These are DEMO keys and nothing else. The seed is a published string, so the private key is public
# and the identity is worthless - which is correct for a fixture and catastrophic for anything real.
# A key whose seed is written down is a key everyone has. Real use: plain `keygen`, no --seed.
KTON_WHEN="${KTON_WHEN:-2026-07-16T00:00:00Z}"   # the same fixed instant the claim specs already use

# demoseed <label> - the 64-hex seed for this example's <label> identity.
demoseed() { printf 'kton-examples/demo/%s/%s' "$EXNAME" "$1" | sha256sum | cut -d" " -f1; }

# TWO EXAMPLES STAY VOLATILE ON PURPOSE, and must not be "fixed": 10-tool-spectrum and
# 12-submission print a session banner carrying a pid and a wall clock (tests/test-predict.R,
# tools/fit.R, tools/pmxtest.R). That volatility IS their subject - it is what makes two runs differ
# byte-for-byte (no L0) while still agreeing once the normalizer strips the banner (L1), and in 12
# the release gate turns on exactly that L1 reproduction. Their snapshots therefore change on every
# run; every other example's is now a function of the repository, not of the clock.

# ---- byte locators: every recorded input/output gets a fetch `uri` = its committed permalink ------
# Each example PERSISTS its .work/ (see .gitignore), so a foton's recorded input/output path IS a real
# file in this repo. We shadow `plankton` so that `plankton author` automatically attaches, to EVERY
# --in/--out, a CARRIED `uri` = that path's raw permalink (carried => NOT part of the foton id, so it
# never changes lineage). A reader can then fetch the exact bytes behind any node. RAWBASE is derived
# from the directory the example is authoring IN; the pin below is the ONE line rewritten at each
# release/migration (gitmick -> kton-protocol, main -> the release commit SHA).
KTON_RAW_REPO="${KTON_RAW_REPO:-gitmick/kton-examples}"
KTON_RAW_COMMIT="${KTON_RAW_COMMIT:-v0.2.0}"          # PIN: the published ref these records point at

plankton() {
  if [ "${1:-}" != "author" ]; then command plankton "$@"; return; fi
  shift
  local -a a=("$@") extra=()
  local i v logical localp rel rawbase
  # Derive the repo home HERE, per call - not once when this file was sourced. An example may `cd`
  # in between (09 cds into .work/ after sourcing), and a base frozen at source time then mints
  # permalinks for a directory the files are not in: a well-formed, signed record whose `uri` 404s,
  # invisible from inside the run. That is exactly what bin/check-permalinks.py caught in 09, where
  # all 12 locators pointed one directory too high.
  rel="${PWD#"$EXROOT"/}"
  if [ "$rel" = "$PWD" ]; then command plankton author "$@"; return; fi   # outside the repo: no home
  rawbase="https://raw.githubusercontent.com/${KTON_RAW_REPO}/${KTON_RAW_COMMIT}/${rel}"
  for ((i = 0; i < ${#a[@]}; i++)); do
    case "${a[i]}" in
      --in | --out)
        v="${a[i + 1]:-}"; [ -n "$v" ] || continue
        if [[ "$v" == *=* ]]; then logical="${v%%=*}"; localp="${v#*=}"; else logical="$v"; localp="$v"; fi
        logical="${logical#./}"; localp="${localp#./}"
        case "$localp" in /*) : ;;                    # absolute path: no repo home, cannot locate
          *) extra+=(--located "$logical=$rawbase/$localp") ;;
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

# expect_fail <what> <cmd...> - run a command that is SUPPOSED to fail, and abort if it SUCCEEDS.
#
# For negative controls: a tampered re-run that must not reproduce, bytes that must not be present.
# `|| true` cannot express that. It accepts both outcomes, so on the day tamper-detection silently
# starts passing, the example still exits 0 and the narration above it still reads like a
# demonstration - the exact shape of failure catalogued in docs/briefing-2026-09.md B3. The command's
# own output still goes to stdout, so the example reads the same as before.
# Call this DIRECTLY, not through a pipe. Piping runs it in a subshell, so its `exit 1` ends only
# that subshell; the script then survives on `set -o pipefail` alone propagating the status. Every
# example here sets pipefail, so a pipe does still abort - but the guard would be resting on a shell
# option rather than on its own exit, and that is a thin thing for a negative control to stand on.
expect_fail(){
  local what="$1"; shift
  if "$@"; then
    echo "  !! NEGATIVE CONTROL BROKEN: $what was supposed to fail, and it SUCCEEDED" >&2
    exit 1
  fi
}

# head_of <scope-id> - the scope's ONE head, or an abort.
#
# `nekton head --json` reports `branched` and `unresolved` as fields rather than as prose beside the
# answer, so a script can REQUIRE what the old `awk '/^head:/{print $2}'` silently assumed: exactly
# one head, and no dangling link. A branched scope used to yield whichever line printed first.
#
# There is deliberately no `sealed` field to ask for, and that absence is load-bearing: a WITHHELD
# later claim is not detectable in-band - the shortened chain stays internally valid - so no value
# could answer it honestly. That question is settled by matching a published or anchored head, not
# by reading a field. See example 05, which does exactly that as its leg 2.
head_of(){
  nekton head "$1" --json | python3 -c "
import json,sys
h=json.load(sys.stdin)
if h['branched'] or len(h['heads'])!=1:
    sys.exit(f\"  !! scope has {len(h['heads'])} head(s), branched={h['branched']} - refusing to pick one\")
if h['unresolved']:
    sys.exit(f\"  !! {h['unresolved']} unresolved link(s) - the head is not the whole chain\")
print(h['heads'][0])"
}

# Reading a registry: one file per (sub)nekton, plus the legacy per-claim form.
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"
