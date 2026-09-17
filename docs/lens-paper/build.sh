#!/usr/bin/env bash
# Lens paper "Pygoscelis" - build the corpus behind docs/lens-paper.html.
#
#   ./build.sh                          rebuild in place, relative locators
#   ./build.sh --serve 8413             rebuild and serve docs/ for a look
#   ./build.sh --base https://raw.githubusercontent.com/gitmick/kton-examples/<SHA_A>/docs/lens-paper
#
# The page itself is docs/lens-paper.html and is maintained by hand, like every
# other demo page here. This script produces only what sits under it:
# files/ figures/ ethics/ reviewer/ (the payload) and reg/ (four registries).
# It shares lens.js, viewer.html, graph.wasm, wasm_exec.js, kton.css and logo.png
# with the other demos - one copy, at docs/.
#
# --base is the hen-and-egg step. A locator names where bytes live, and for a
# permalink that address contains the commit carrying them - which does not exist
# until they are committed. So: commit files/, figures/, ethics/ and reviewer/
# first, take that SHA, re-run with --base ending in it, commit reg/ second.
# Locators are CARRIED: they do not change a foton id, so both runs produce the
# same ids and only the addresses and signatures differ. Afterwards
# `python3 bin/check-permalinks.py --against-ref <SHA_A>` says whether every
# address actually carries.
#
# Reproducible throughout: signing keys from fixed seeds (the .key file IS the
# seed), animal names from set.seed(1999), claim timestamps from --when, and R's
# svg() device writes byte-identical output for the same input.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS="$(dirname "$HERE")"
cd "$HERE"

BASE=""
OUT="$HERE"
SERVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)  BASE="${2%/}"; shift 2 ;;
    --out)   OUT="$2";      shift 2 ;;
    --serve) SERVE="$2";    shift 2 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v Rscript >/dev/null || { echo "missing: Rscript" >&2; exit 1; }
PLANKTON="${PLANKTON:-$(command -v plankton || true)}"
NEKTON="${NEKTON:-$(command -v nekton || true)}"
[[ -x "${PLANKTON:-}" && -x "${NEKTON:-}" ]] || {
  echo "plankton and nekton must be on PATH (or set \$PLANKTON / \$NEKTON)" >&2; exit 1; }

OUT="$(mkdir -p "$OUT" && cd "$OUT" && pwd)"
W="$OUT/.work"                       # scratch: intermediates, keys, registries
rm -rf "$W" "$OUT"/{files,figures,ethics,reviewer,reg}
mkdir -p "$W"/{figures,out,keys} "$OUT"/{files,figures,ethics,reviewer}

loc() { printf '%s=%s' "$1" "${BASE:+$BASE/}$2"; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- identities
# Three signers, four registries that trust them differently. Fixture keys:
# their strength is the seed's, and the seed is a constant.
say "1 · identities"
"$PLANKTON" keygen "$W/keys/station"  --seed "$(printf '4%.0s' {1..64})" >/dev/null
"$PLANKTON" keygen "$W/keys/reviewer" --seed "$(printf '5%.0s' {1..64})" >/dev/null
"$PLANKTON" keygen "$W/keys/ethics"   --seed "$(printf '6%.0s' {1..64})" >/dev/null
KID_STATION=$("$PLANKTON" keyid "$W/keys/station.key")
KID_REVIEWER=$("$PLANKTON" keyid "$W/keys/reviewer.key")
KID_ETHICS=$("$PLANKTON" keyid "$W/keys/ethics.key")
printf '  station  %s\n  reviewer %s\n  ethics   %s\n' "$KID_STATION" "$KID_REVIEWER" "$KID_ETHICS"

# ------------------------------------------------------------------- the run
# penguins.csv is the Palmer Archipelago data, used unchanged (src/SOURCE.txt).
# The station receives it as named records and strips the names, so anonymise.R
# has to reproduce the published file byte for byte - checked below, because it
# is the claim the ethics committee stands on.
say "2 · the analysis"
cd "$W"
cp "$HERE/src/"*.R "$HERE/src/SOURCE.txt" .
cp "$HERE/src/penguins.csv" ./penguins-source.csv

run() { Rscript "$@" >/dev/null; }     # R's dev.off() prints "null device"
run name-animals.R    penguins-source.csv penguins-named.csv
run anonymise.R       penguins-named.csv  penguins.csv
cmp -s penguins-source.csv penguins.csv || {
  echo "anonymise.R no longer reproduces the source file byte for byte" >&2; exit 1; }
run drop-incomplete.R penguins.csv          penguins-complete.csv
run bill-pooled.R     penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt
run flipper-mass.R    penguins-complete.csv figures/fig2-flipper-mass.svg
run composition.R     penguins-complete.csv figures/fig3-composition.svg
run bill-by-species.R penguins-complete.csv figures/bill-by-species.svg  out/bill-by-species.txt
run audit.R           penguins-named.csv    ethics-audit.txt
run anonymise.R       penguins-named.csv    ethics-recheck.csv
echo "  $(( $(wc -l < penguins-complete.csv) - 1 )) complete records, $(ls figures | wc -l) figures"

# ------------------------------------------------------------- the registers
say "3 · registers"
mkdir -p "$W/reg"/{station,ethics,ethics-internal,reviewer}/{plankton,nekton}
P_STATION="$W/reg/station/plankton"
P_ETHICS="$W/reg/ethics/plankton";   N_ETHICS="$W/reg/ethics/nekton"
P_INTERN="$W/reg/ethics-internal/plankton"
P_REVIEW="$W/reg/reviewer/plankton"; N_REVIEW="$W/reg/reviewer/nekton"

# -- Palmer Field Station ----------------------------------------------------
# penguins-named.csv gets NO locator. The station knows the hash of what it was
# handed and says so; the bytes stay with the committee. That gap is the point.
"$PLANKTON" author --registry "$P_STATION" --add --sign "$W/keys/station.key" \
  --cmd "Rscript anonymise.R penguins-named.csv penguins.csv" \
  --in penguins-named.csv \
  --in anonymise.R --located "$(loc anonymise.R files/anonymise.R)" \
  --out penguins.csv --located "$(loc penguins.csv files/penguins.csv)" >/dev/null

"$PLANKTON" author --registry "$P_STATION" --add --sign "$W/keys/station.key" \
  --cmd "Rscript drop-incomplete.R penguins.csv penguins-complete.csv" \
  --in penguins.csv           --located "$(loc penguins.csv files/penguins.csv)" \
  --in drop-incomplete.R      --located "$(loc drop-incomplete.R files/drop-incomplete.R)" \
  --out penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" >/dev/null

# The published finding. The reviewer authors this same descriptor below, which
# makes it the SAME foton carrying both signatures.
FOTON_POOLED=$("$PLANKTON" author --registry "$P_STATION" --add --sign "$W/keys/station.key" --print-id \
  --cmd "Rscript bill-pooled.R penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in bill-pooled.R         --located "$(loc bill-pooled.R files/bill-pooled.R)" \
  --out figures/fig1-bill-pooled.svg --located "$(loc figures/fig1-bill-pooled.svg figures/fig1-bill-pooled.svg)" \
  --out out/bill-pooled.txt          --located "$(loc out/bill-pooled.txt files/bill-pooled.txt)" 2>/dev/null)

"$PLANKTON" author --registry "$P_STATION" --add --sign "$W/keys/station.key" \
  --cmd "Rscript flipper-mass.R penguins-complete.csv figures/fig2-flipper-mass.svg" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in flipper-mass.R        --located "$(loc flipper-mass.R files/flipper-mass.R)" \
  --out figures/fig2-flipper-mass.svg --located "$(loc figures/fig2-flipper-mass.svg figures/fig2-flipper-mass.svg)" >/dev/null

# figures/fig3-composition.svg is deliberately NOT authored. It was drawn for the
# field log while the analysis was still running and nobody recorded it. The lens
# has nothing to say about it, and saying nothing is the honest answer.

# -- Ethics Committee, public face -------------------------------------------
FOTON_RECHECK=$("$PLANKTON" author --registry "$P_ETHICS" --add --sign "$W/keys/ethics.key" --print-id \
  --cmd "Rscript anonymise.R penguins-named.csv ethics-recheck.csv" \
  --in penguins-named.csv \
  --in anonymise.R --located "$(loc anonymise.R files/anonymise.R)" \
  --out ethics-recheck.csv --located "$(loc ethics-recheck.csv ethics/ethics-recheck.csv)" 2>/dev/null)

claim() {  # claim REGISTRY KEY <<< spec-json
  local reg="$1" key="$2" spec; spec="$(mktemp)"
  cat > "$spec"
  "$NEKTON" claim "$spec" "$key" --add --registry "$reg" >/dev/null
  rm -f "$spec"
}

claim "$N_ETHICS" "$W/keys/ethics.key" <<JSON
{ "subject": [{"hash": "$FOTON_RECHECK"}],
  "predicate": "https://kton.dev/v/anonymisation-verified",
  "object": {"value": "re-ran on the held source records; output identical to the released file; 344 animals, no direct identifiers remain"},
  "by": "Animal Welfare and Ethics Committee",
  "why": "The source records remain with the committee and are not released.",
  "when": "2026-03-02T11:00:00Z" }
JSON

# -- Ethics Committee, internal register -------------------------------------
# The register it does not hand out. Here penguins-named.csv finally carries an
# address and the names become fetchable. A change of role, not another source:
# a reviewer cannot switch this one on.
"$PLANKTON" author --registry "$P_INTERN" --add --sign "$W/keys/ethics.key" \
  --cmd "Rscript audit.R penguins-named.csv ethics-audit.txt" \
  --in penguins-named.csv --located "$(loc penguins-named.csv ethics/penguins-named.csv)" \
  --in audit.R            --located "$(loc audit.R ethics/audit.R)" \
  --out ethics-audit.txt  --located "$(loc ethics-audit.txt ethics/ethics-audit.txt)" >/dev/null

# -- Reviewer 2 ---------------------------------------------------------------
# The reproduction first: byte-identical descriptor, so this IS FOTON_POOLED and
# the signature is unioned onto it. Then the analysis the report does not carry.
"$PLANKTON" author --registry "$P_REVIEW" --add --sign "$W/keys/reviewer.key" \
  --cmd "Rscript bill-pooled.R penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in bill-pooled.R         --located "$(loc bill-pooled.R files/bill-pooled.R)" \
  --out figures/fig1-bill-pooled.svg --located "$(loc figures/fig1-bill-pooled.svg figures/fig1-bill-pooled.svg)" \
  --out out/bill-pooled.txt          --located "$(loc out/bill-pooled.txt files/bill-pooled.txt)" >/dev/null

FOTON_SPECIES=$("$PLANKTON" author --registry "$P_REVIEW" --add --sign "$W/keys/reviewer.key" --print-id \
  --cmd "Rscript bill-by-species.R penguins-complete.csv figures/bill-by-species.svg out/bill-by-species.txt" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in bill-by-species.R     --located "$(loc bill-by-species.R reviewer/bill-by-species.R)" \
  --out figures/bill-by-species.svg --located "$(loc figures/bill-by-species.svg reviewer/bill-by-species.svg)" \
  --out out/bill-by-species.txt     --located "$(loc out/bill-by-species.txt reviewer/bill-by-species.txt)" 2>/dev/null)

# The hash of figure 1 itself, so the objection attaches to the picture in the
# report rather than to the run that produced it.
HASH_FIG1=sha256:$(sha256sum figures/fig1-bill-pooled.svg | cut -d' ' -f1)

claim "$N_REVIEW" "$W/keys/reviewer.key" <<JSON
{ "subject": [{"hash": "$FOTON_POOLED"}],
  "predicate": "https://kton.dev/v/reproduces",
  "object": {"value": "re-ran it from the released data; same figure, same numbers, byte for byte"},
  "by": "Reviewer 2",
  "when": "2026-05-11T07:55:00Z" }
JSON

claim "$N_REVIEW" "$W/keys/reviewer.key" <<JSON
{ "subject": [{"hash": "$FOTON_SPECIES"}],
  "predicate": "https://kton.dev/v/the-same-question-split-by-species",
  "object": {"value": "what the published analysis looks like once species is taken into account. Same data, same code path, one grouping added."},
  "by": "Reviewer 2",
  "when": "2026-05-11T08:15:00Z" }
JSON

claim "$N_REVIEW" "$W/keys/reviewer.key" <<JSON
{ "subject": [{"hash": "$HASH_FIG1"}],
  "predicate": "https://kton.dev/v/does-not-hold-within-species",
  "object": {"value": "the downward line is a difference between species. Within every species the relationship runs the other way: Adelie +0.391, Chinstrap +0.654, Gentoo +0.643. Asked for in review; not in the report."},
  "evidence": [{"hash": "$FOTON_SPECIES"}],
  "by": "Reviewer 2",
  "when": "2026-05-11T08:30:00Z" }
JSON

# ------------------------------------------------------------------- publish
say "4 · files under docs/lens-paper/"
cp "$W"/{penguins.csv,penguins-complete.csv,anonymise.R,drop-incomplete.R,bill-pooled.R,flipper-mass.R,SOURCE.txt} "$OUT/files/"
cp "$W/out/bill-pooled.txt"                                                "$OUT/files/"
cp "$W"/figures/fig[123]-*.svg                                             "$OUT/figures/"
cp "$W"/{penguins-named.csv,audit.R,ethics-audit.txt,ethics-recheck.csv}   "$OUT/ethics/"
cp "$W/bill-by-species.R" "$W/figures/bill-by-species.svg" "$W/out/bill-by-species.txt" "$OUT/reviewer/"

# Every registry publishes the same key directory. Knowing who signed something
# is not the same as being able to read it - which is what the four states show.
KEYS_JSON=$(python3 - "$KID_STATION" "$("$PLANKTON" pubkey "$W/keys/station.key")" \
                      "$KID_REVIEWER" "$("$PLANKTON" pubkey "$W/keys/reviewer.key")" \
                      "$KID_ETHICS"   "$("$PLANKTON" pubkey "$W/keys/ethics.key")" <<'PY'
import json,sys
a=sys.argv[1:]
print(json.dumps(dict(sorted(zip(a[0::2],a[1::2]))),indent=2))
PY
)
NAMES_JSON=$(python3 - "$KID_STATION" "$KID_REVIEWER" "$KID_ETHICS" <<'PY'
import json,sys
s,r,e=sys.argv[1:4]
print(json.dumps({s:"Palmer Field Station",r:"Reviewer 2",
                  e:"Animal Welfare and Ethics Committee"},indent=2))
PY
)

for r in station ethics ethics-internal reviewer; do
  mkdir -p "$OUT/reg/$r"
  printf '%s\n' "$KEYS_JSON"  > "$OUT/reg/$r/keys.json"
  printf '%s\n' "$NAMES_JSON" > "$OUT/reg/$r/names.json"
  python3 - "$W/reg/$r" "$OUT/reg/$r/union.json" <<'PY'
import json,sys,glob,os
src,dst=sys.argv[1],sys.argv[2]
out=[]
for f in sorted(glob.glob(os.path.join(src,"plankton","objects","sha256","*.json"))):
    out.append(json.load(open(f)))
for f in sorted(glob.glob(os.path.join(src,"nekton","objects","*.jsonl"))):
    out += [json.loads(l) for l in open(f) if l.strip()]
with open(dst,"w") as fh:
    json.dump(out,fh,indent=2); fh.write("\n")
print("  %-16s %d record(s)" % (os.path.basename(src), len(out)))
PY
done

rm -rf "$W"

say "done"
echo "  payload:  $OUT/{files,figures,ethics,reviewer}"
echo "  records:  $OUT/reg"
echo "  locators: ${BASE:-relative (local preview only)}"
[[ -z "$BASE" ]] && echo "            relative locators read as \"(unsafe uri)\" in the viewer and cannot be fetched."

if [[ -n "$SERVE" ]]; then
  for a in lens.js viewer.html graph.wasm wasm_exec.js kton.css logo.png; do
    [[ -f "$DOCS/$a" ]] || echo "  warning: $DOCS/$a is missing - the page will load but the marks will not work" >&2
  done
  echo
  echo "  http://localhost:$SERVE/lens-paper.html - Ctrl-C to stop"
  cd "$DOCS" && exec python3 -m http.server "$SERVE"
fi
