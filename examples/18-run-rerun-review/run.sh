#!/usr/bin/env bash
# 18 - run, rerun, review: the whole cycle on one script, as small as it gets.
#
#   1. llm (an agent session with its own key) runs whales.R and writes the step's description and
#      rationale. Same key: the record shows which session ran what and said what about it.
#   2. michael, a person, reruns it: same bytes, same foton, his signature lands on it: ↻2.
#   3. ana and ben review it, in a review scope of its own. michael, who owns the review, first says
#      which keys are people and which is an agent; the rule is anchored in the parent before anyone
#      reviews; the seal of the finished review goes back into the parent.
#   4. Is the review valid? four-eyes.rq decides, in Oxigraph: four eyes, people only, nobody approving
#      their own work. The check is a foton whose inputs are the signed records themselves (both scopes,
#      the foton), the trusted keys, the rule and check.sh; rerun it and plankton compares: L0.
#      Four rehearsals must say no: the llm approves; the run only is approved; the llm runs a review of
#      its own; the llm, declared a person by mistake, approves its own run.
#
# Every input and output carries a raw GitHub permalink (lib/common.sh), so a viewer can fetch the
# exact bytes. Keys are demo fixtures from fixed seeds; the data are simulated.
set -euo pipefail
cd "$(dirname "$0")"
# Example 18 is not in the v0.4.0 tag. Until a release tag holds it, its permalinks point at commits of
# its own history: the run's bytes (whales.R, whales.svg) at the first line, the records the verdict
# reads at the second. At that release, drop both lines and regenerate with the suite's pin.
: "${KTON_RAW_COMMIT:=23fd4136142f9373f4faef8804c55fe11748a699}"
: "${KTON_RECORDS_COMMIT:=963eff6a2d8d6b93bb0b7297481c82edbea6ae93}"
source ../../lib/common.sh

W=.work; D="$PWD/$W"
rm -rf "$W"; mkdir -p "$W/keys" "$W/run" "$W/check"
for who in llm michael ana ben; do plankton keygen "$W/keys/$who" --seed "$(demoseed "$who")" >/dev/null 2>&1; done
mkdir -p trust; cp "$W"/keys/*.pub trust/      # the keys we trust: public halves only, committed
export OXIGRAPH="oxigraph/oxigraph@sha256:10677fb643f8c5a7bfb03dd8f7971c79a84b01e795c24201c8cfa12fd569f1c0"
K(){ echo "$W/keys/$1.key"; }
kid(){ plankton keyid "$W/keys/$1.pub"; }
WHEN="2026-11-18T10:00:00Z"
export NEKTON_DIR="$D/nekton"
firstid(){ grep -oE 'sha256:[0-9a-f]{64}' | head -1; }
seedid(){ grep -oE 'sha256:[0-9a-f]{64}' | tail -1; }
claim(){ # claim <dir> <signer> <json>  -> claim id
  printf '%s' "$3" > "$W/c.json"; NEKTON_DIR="$1" nekton claim "$W/c.json" "$(K "$2")" --add 2>&1 | firstid; }

echo "== 1. llm runs whales.R"
export PLANKTON_DIR="$D/plankton"
cp whales.R "$W/run/"; (cd "$W/run" && Rscript whales.R)
F=$(plankton author --cmd "Rscript whales.R" \
      --in "whales.R=$W/run/whales.R" --out "whales.svg=$W/run/whales.svg" --sign "$(K llm)" --add --print-id 2>/dev/null)
echo "   foton $F, signed by llm"
# description and rationale: claims ABOUT the foton (dc:description, ep-plan:hasRationale), signed by llm
say(){ claim "$NEKTON_DIR" "$1" "$(printf '{"subject":[{"hash":"%s"}],"predicate":"%s","object":{"value":"%s"},"by":"%s","when":"%s"}' "$F" "$2" "$3" "$1" "$WHEN")"; }
DESC=$(say llm "http://purl.org/dc/terms/description" \
  "Simulates 24 months of plankton density and whale sightings and draws both in one figure: plankton as a line, whale sightings as bars.")
RAT=$(say llm "https://w3id.org/ep-plan#hasRationale" \
  "To see whether whale sightings rise a month after the plankton does. The data are simulated with a fixed seed, so anyone who reruns the script should get the same bytes.")
echo "   description ${DESC:7:8} and rationale ${RAT:7:8}, signed by llm"

echo "== 2. michael reruns it: delete the figure, run the script again"
FIRST=$(plankton hash "$W/run/whales.svg"); rm "$W/run/whales.svg"
(cd "$W/run" && Rscript whales.R)
F2=$(plankton author --cmd "Rscript whales.R" \
       --in "whales.R=$W/run/whales.R" --out "whales.svg=$W/run/whales.svg" --sign "$(K michael)" --add --print-id 2>/dev/null)
[ "$F2" = "$F" ] || { echo "   !! the rerun gave another foton: $F2" >&2; exit 1; }
OUT=$(plankton hash "$W/run/whales.svg")
echo -n "   "; plankton reproduces "$FIRST" "$OUT" | head -1
plankton reproductions --trust-keys "$W/keys" "$OUT" 2>/dev/null | head -1 | sed 's/^/   /'

echo "== 3. the review, as its own scope"
# declare <signer> <who> <Kind>: in the parent scope, <signer> says that <who>'s key is a prov:<Kind>
declare(){
  prev=$(claim "$PUBD" "$1" "$(printf '{"subject":[{"uri":"https://kton.dev/agent/%s"}],"predicateBody":{"predicate":{"uri":"http://www.w3.org/1999/02/22-rdf-syntax-ns#type"},"object":{"uri":"http://www.w3.org/ns/prov#%s"},"by":"%s","when":"%s","scope":"%s","prev":"%s"}}' "$(kid "$2")" "$3" "$1" "$WHEN" "$PUB" "$prev")")
  echo "   $1: $2 is a $3"
}
# public <dir> <who:Kind>...: the parent scope, michael's; first he says who is who
public(){
  PUBD="$1"; shift
  PUB=$(NEKTON_DIR="$PUBD" nekton seed examples --sign "$(K michael)" --by michael --when "$WHEN" --add 2>&1 | seedid)
  prev="$PUB"
  local d; for d in "$@"; do declare michael "${d%%:*}" "${d##*:}"; done
}
# who is who: michael says which keys are people and which is an agent. Without it, nobody counts.
public "$D/public" llm:SoftwareAgent ana:Person ben:Person
# review <name> <who:verdict...>   -> the review scope's deliveries, in $W/<name>.deliveries
# OWNER (default michael) seeds the review scope, writes the rule, anchors and seals it
review(){
  local NAME="$1"; shift; local RD="$D/$NAME" O="${OWNER:-michael}"
  local REV; REV=$(NEKTON_DIR="$RD" nekton seed "$NAME" --parent "$PUB" --sign "$(K "$O")" --by "$O" --when "$WHEN" --add 2>&1 | seedid)
  echo "$REV" > "$W/$NAME.scope"   # check reads this scope's file by its id (the store also holds its root scope)
  local rule; rule=$(claim "$RD" "$O" "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"object":{"hash":"%s"},"foton":"%s","by":"%s","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$(plankton hash four-eyes.rq)" "$F" "$O" "$WHEN" "$REV" "$REV")")
  local anchor; anchor=$(claim "$PUBD" "$O" "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"object":{"hash":"%s"},"by":"%s","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$rule" "$O" "$WHEN" "$PUB" "$prev")")
  local p="$rule" d who v; : > "$W/$NAME.deliveries"
  local items="$F $DESC $RAT"; [ "${RUN_ONLY:-}" ] && items="$F"
  for d in "$@"; do who="${d%%:*}"; v="${d##*:}"
    # what is reviewed: the run AND the llm's description and rationale, each by its id (a hash of its
    # exact text), one signed approval per item. A changed description is a new claim, not covered.
    local x; for x in $items; do
      p=$(claim "$RD" "$who" "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/reviewed"},"object":{"value":"%s"},"by":"%s","when":"%s","scope":"%s","prev":"%s"}}' \
        "$x" "$v" "$who" "$WHEN" "$REV" "$p")")
    done
    echo "$p" >> "$W/$NAME.deliveries"
  done
  local HEAD; HEAD=$(NEKTON_DIR="$RD" nekton head "$REV" | awk '/^head:/{print $2}')
  prev=$(claim "$PUBD" "$O" "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/closed"},"object":{"hash":"%s"},"by":"%s","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$HEAD" "$O" "$WHEN" "$PUB" "$anchor")")
  echo "   $NAME: $O's rule (four-eyes.rq) -> anchored in the parent by $O -> $* -> sealed in the parent"
}
# check <name>: the review check as a recorded step. Its inputs are the signed records themselves (the
# parent scope, the review scope, the foton), the keys we trust, the rule and the script; its output is
# the verdict. check.sh projects the records to RDF and asks Oxigraph (pinned by digest) four-eyes.rq.
check(){
  local NAME="$1" C="$W/check/$1"; mkdir -p "$C"
  local fr="$PLANKTON_DIR/objects/sha256/${F#sha256:}.json"
  # each scope's file by its id: since kton 0.4 every store also holds its root scope's file
  local ps="$PUBD/objects/scope/${PUB#sha256:}.nekton.jsonl" rs; rs="$D/$NAME/objects/scope/$(sed 's/^sha256://' "$W/$NAME.scope").nekton.jsonl"
  [ -f "$ps" ] && [ -f "$rs" ] || { echo "  !! no scope file for $PUB or $(cat "$W/$NAME.scope")" >&2; exit 1; }
  # the llm's description and rationale: since kton 0.4 they chain in the store's root scope, its only
  # scope file here (there is no unscoped nekton any more); more than one would make the input ambiguous
  local ts; ts=$(ls "$NEKTON_DIR"/objects/scope/*.nekton.jsonl)
  [ "$(printf '%s\n' "$ts" | wc -l)" -eq 1 ] || { echo "  !! $NEKTON_DIR holds more than one scope file" >&2; exit 1; }
  fr="${fr#"$PWD"/}"; ps="${ps#"$PWD"/}"; rs="${rs#"$PWD"/}"; ts="${ts#"$PWD"/}"
  ./check.sh trust trust/michael.pub "$fr" "$ts" "$ps" "$rs" > "$C/verdict.csv"
  sed 's/^/     /' "$C/verdict.csv"
  local ins=(--in check.sh --in four-eyes.rq --in "$fr" --in "$ts" --in "$ps" --in "$rs") k
  for k in trust/*.pub; do ins+=(--in "$k"); done
  # its inputs include record files, which carry the run's permalinks; so its own permalinks point at the
  # commit that holds those records (KTON_RECORDS_COMMIT), not at the one that holds the run's bytes
  KTON_RAW_COMMIT="${KTON_RECORDS_COMMIT:-${KTON_RAW_COMMIT:-}}" plankton author --cmd "./check.sh trust trust/michael.pub $fr $ts $ps $rs   (oxigraph 0.5.12, ${OXIGRAPH##*@})" \
    "${ins[@]}" --out "$C/verdict.csv" --sign "$(K michael)" --add --print-id 2>/dev/null > "$C/foton.txt"
  echo "$fr $ts $ps $rs" > "$C/inputs"
}
review review-whales ana:approve ben:approve

echo "== 4. is the review valid? one query decides, plankton records it"
check review-whales
echo "   verdict recorded as foton $(cat "$W/check/review-whales/foton.txt")"
# re-derive: anyone with the same records, keys and rule runs the check again; same verdict bytes?
read -r fr ts ps rs < "$W/check/review-whales/inputs"
./check.sh trust trust/michael.pub "$fr" "$ts" "$ps" "$rs" > "$W/check/rederived.csv"
echo -n "   re-derived: "; plankton reproduces "$(plankton hash "$W/check/review-whales/verdict.csv")" "$(plankton hash "$W/check/rederived.csv")" | head -1

echo
snapshot 18-run-rerun-review "$D/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR" --reg "$PUBD" --reg "$D/review-whales"

# after the snapshot, and on a copy of the parent, so the graph and the committed inputs show only the real review
echo "-- rehearsal: ana and the llm approve; the llm's approval does not count"
cp -r "$PUBD" "$D/rehearsal-public"; PUBD="$D/rehearsal-public"
review review-llm ana:approve llm:approve
check review-llm
echo "-- rehearsal: ana and ben approve the run only, not the texts; neither approval counts"
RUN_ONLY=1 review review-runonly ana:approve ben:approve
check review-runonly
echo "-- rehearsal: the llm runs a review of its own: it seeds the review scope, anchors its rule in the parent"
echo "   and says there that it is a person; ana and the llm approve. Only michael's word counts in the parent"
declare llm llm Person
OWNER=llm review review-byllm ana:approve llm:approve
check review-byllm
echo "-- rehearsal: michael declares the llm a person by mistake; the llm approves its own run with ana."
echo "   Whoever signed the foton (the llm ran it, michael reran it) does not count, person or not"
public "$D/rehearsal-mistake" llm:Person ana:Person ben:Person
review review-ownrun ana:approve llm:approve
check review-ownrun
