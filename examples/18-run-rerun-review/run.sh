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
#      A rehearsal where the llm approves shows that an agent's approval does not count.
#
# Every input and output carries a raw GitHub permalink (lib/common.sh), so a viewer can fetch the
# exact bytes. Keys are demo fixtures from fixed seeds; the data are simulated.
set -euo pipefail
cd "$(dirname "$0")"
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
PUBD="$D/public"
PUB=$(NEKTON_DIR="$PUBD" nekton seed examples --sign "$(K michael)" --by michael --when "$WHEN" --add 2>&1 | seedid)
# who is who: michael says which keys are people and which is an agent. Without it, nobody counts.
prev="$PUB"
for who in llm ana ben; do
  kind=Person; [ "$who" = llm ] && kind=SoftwareAgent
  prev=$(claim "$PUBD" michael "$(printf '{"subject":[{"uri":"https://kton.dev/agent/%s"}],"predicateBody":{"predicate":{"uri":"http://www.w3.org/1999/02/22-rdf-syntax-ns#type"},"object":{"uri":"http://www.w3.org/ns/prov#%s"},"by":"michael","when":"%s","scope":"%s","prev":"%s"}}' "$(kid $who)" "$kind" "$WHEN" "$PUB" "$prev")")
  echo "$prev" >> "$W/kinds"
  echo "   michael: $who is a $kind"
done
# review <name> <who:verdict...>   -> the review scope's deliveries, in $W/<name>.deliveries
review(){
  local NAME="$1"; shift; local RD="$D/$NAME"
  local REV; REV=$(NEKTON_DIR="$RD" nekton seed "$NAME" --parent "$PUB" --sign "$(K michael)" --by michael --when "$WHEN" --add 2>&1 | seedid)
  local rule; rule=$(claim "$RD" michael "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"object":{"hash":"%s"},"foton":"%s","by":"michael","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$(plankton hash four-eyes.rq)" "$F" "$WHEN" "$REV" "$REV")")
  local anchor; anchor=$(claim "$PUBD" michael "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"object":{"hash":"%s"},"by":"michael","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$rule" "$WHEN" "$PUB" "$prev")")
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
  prev=$(claim "$PUBD" michael "$(printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/closed"},"object":{"hash":"%s"},"by":"michael","when":"%s","scope":"%s","prev":"%s"}}' \
    "$REV" "$HEAD" "$WHEN" "$PUB" "$anchor")")
  echo "   $NAME: rule (four-eyes.rq) -> anchored in the parent -> $* -> sealed in the parent"
}
# check <name>: the review check as a recorded step. Its inputs are the signed records themselves (the
# parent scope, the review scope, the foton), the keys we trust, the rule and the script; its output is
# the verdict. check.sh projects the records to RDF and asks Oxigraph (pinned by digest) four-eyes.rq.
check(){
  local NAME="$1" C="$W/check/$1"; mkdir -p "$C"
  local fr="$PLANKTON_DIR/objects/sha256/${F#sha256:}.json"
  local ps; ps=$(ls "$PUBD"/objects/scope/*.nekton.jsonl); local rs; rs=$(ls "$D/$NAME"/objects/scope/*.nekton.jsonl)
  local ts="$NEKTON_DIR/objects/unscoped.nekton.jsonl"     # the llm's description and rationale
  fr="${fr#"$PWD"/}"; ps="${ps#"$PWD"/}"; rs="${rs#"$PWD"/}"; ts="${ts#"$PWD"/}"
  ./check.sh trust "$fr" "$ts" "$ps" "$rs" > "$C/verdict.csv"
  sed 's/^/     /' "$C/verdict.csv"
  local ins=(--in check.sh --in four-eyes.rq --in "$fr" --in "$ts" --in "$ps" --in "$rs") k
  for k in trust/*.pub; do ins+=(--in "$k"); done
  # its inputs include record files, which carry the run's permalinks; so its own permalinks point at the
  # commit that holds those records (KTON_RECORDS_COMMIT), not at the one that holds the run's bytes
  KTON_RAW_COMMIT="${KTON_RECORDS_COMMIT:-${KTON_RAW_COMMIT:-}}" plankton author --cmd "./check.sh trust $fr $ts $ps $rs   (oxigraph 0.5.12, ${OXIGRAPH##*@})" \
    "${ins[@]}" --out "$C/verdict.csv" --sign "$(K michael)" --add --print-id 2>/dev/null > "$C/foton.txt"
  echo "$fr $ts $ps $rs" > "$C/inputs"
}
review review-whales ana:approve ben:approve

echo "== 4. is the review valid? plankton checks"
check review-whales
echo "   verdict recorded as foton $(cat "$W/check/review-whales/foton.txt")"
# re-derive: anyone with the same records, keys and rule runs the check again; same verdict bytes?
read -r fr ts ps rs < "$W/check/review-whales/inputs"
./check.sh trust "$fr" "$ts" "$ps" "$rs" > "$W/check/rederived.csv"
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
