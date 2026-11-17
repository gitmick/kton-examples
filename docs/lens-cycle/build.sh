#!/usr/bin/env bash
# Lens cycle "Pygoscelis" - the penguin report in three stages, behind docs/lens-cycle.html.
#
#   ./build.sh                                   rebuild in place, relative locators
#   ./build.sh --serve 8414                      rebuild and serve docs/ for a look
#   ./build.sh --base <raw URL of commit A>/docs/lens-cycle [--records-base <raw URL of commit B>/docs/lens-cycle]
#
# 1. the llm      an agent session with its own key runs the station's analysis and signs what the
#                 step is (dc:description) and why it was done (ep-plan:hasRationale)
# 2. + the rerun  a person at the station reruns the published step: same descriptor, same foton,
#                 her signature lands on it (↻2)
# 3. + the review the editor opens a review scope, anchors the rule (four-eyes.rq, by hash) in the
#                 journal's scope first, says who is a person and who is an agent; two reviewers
#                 approve; the seal goes back into the journal's scope. Is the review valid? check.sh
#                 runs four-eyes.rq in Oxigraph (pinned by digest) over the signed records themselves,
#                 and that check is a foton too: rerun it, plankton compares, L0.
#    ethics       the data-sovereignty layer of docs/lens-paper, unchanged: the named source file is
#                 known by hash only; it carries an address only in the committee's own view.
#
# Three commits, because a permalink names the commit that carries the bytes:
#   A  payload (files, figures, ethics, reviewer, review)          ./build.sh
#   B  records (reg/, records/), locators -> A                     ./build.sh --base A
#   C  the check's record, whose inputs are records -> B           ./build.sh --base A --records-base B
# The records are byte-identical between B and C (fixed seeds, fixed times); C only changes the check.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS="$(dirname "$HERE")"
SRC="$DOCS/lens-paper/src"            # the penguin data and scripts: one copy, the lens paper's
cd "$HERE"

BASE=""; RBASE=""; SERVE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)         BASE="${2%/}";  shift 2 ;;
    --records-base) RBASE="${2%/}"; shift 2 ;;
    --serve)        SERVE="$2";     shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
RBASE="${RBASE:-$BASE}"
for t in Rscript plankton nekton jq docker; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
export OXIGRAPH="oxigraph/oxigraph@sha256:10677fb643f8c5a7bfb03dd8f7971c79a84b01e795c24201c8cfa12fd569f1c0"

W="$HERE/.work"
rm -rf "$W" "$HERE"/{files,figures,ethics,reviewer,review,reg,records,trust}
mkdir -p "$W"/{figures,out,keys} "$HERE"/{files,figures,ethics,reviewer,review,records,trust}
loc()  { printf '%s=%s' "$1" "${BASE:+$BASE/}$2"; }
rloc() { printf '%s=%s' "$1" "${RBASE:+$RBASE/}$2"; }
say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
firstid(){ grep -oE 'sha256:[0-9a-f]{64}' | head -1; }
seedid(){ grep -oE 'sha256:[0-9a-f]{64}' | tail -1; }

# ---------------------------------------------------------------- identities
say "1 · identities"
key(){ plankton keygen "$W/keys/$1" --seed "$(printf "$2%.0s" {1..64})" >/dev/null 2>&1; }
key llm 7; key lena 8; key editor 9; key reviewer1 a; key reviewer2 5; key ethics 6
K(){ echo "$W/keys/$1.key"; }
kid(){ plankton keyid "$W/keys/$1.key"; }
for who in llm lena editor reviewer1 reviewer2; do cp "$W/keys/$who.pub" "$HERE/trust/"; done

# ------------------------------------------------------------------- the run
say "2 · the analysis"
cd "$W"
cp "$SRC/"*.R "$SRC/SOURCE.txt" .; cp "$SRC/penguins.csv" ./penguins-source.csv
run(){ Rscript "$@" >/dev/null; }
run name-animals.R    penguins-source.csv penguins-named.csv
run anonymise.R       penguins-named.csv  penguins.csv
cmp -s penguins-source.csv penguins.csv || { echo "anonymise.R no longer reproduces the source file" >&2; exit 1; }
run drop-incomplete.R penguins.csv          penguins-complete.csv
run bill-pooled.R     penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt
run flipper-mass.R    penguins-complete.csv figures/fig2-flipper-mass.svg
run composition.R     penguins-complete.csv figures/fig3-composition.svg
run bill-by-species.R penguins-complete.csv figures/bill-by-species.svg  out/bill-by-species.txt
run audit.R           penguins-named.csv    ethics-audit.txt
run anonymise.R       penguins-named.csv    ethics-recheck.csv

R="$W/reg"; mkdir -p "$R"/{llm,rerun,review,ethics,ethics-internal}/{plankton,nekton} "$W/pub" "$W/rev"
claim(){ # claim NEKTON_DIR KEY JSON -> claim id
  printf '%s' "$3" > "$W/c.json"; NEKTON_DIR="$1" nekton claim "$W/c.json" "$2" --add 2>&1 | firstid; }
desc(){ # desc PARTY FOTON TEXT [WHY]: a short dc:description (the node's label in the graph), and its rationale
  local reg="$R/$1/nekton" key name; case "$1" in llm) key=llm; name="Station LLM";; rerun) key=lena; name="Lena Moreau";;
    review) key="${5:-editor}"; name="${6:-Journal editor}";; ethics|ethics-internal) key=ethics; name="Animal Welfare and Ethics Committee";; esac
  claim "$reg" "$(K $key)" "$(jq -nc --arg f "$2" --arg v "$3" --arg by "$name" '{subject:[{hash:$f}],predicate:"http://purl.org/dc/terms/description",object:{value:$v},by:$by,when:"2026-04-02T09:00:00Z"}')" >/dev/null
  if [[ -n "${4:-}" ]]; then claim "$reg" "$(K $key)" "$(jq -nc --arg f "$2" --arg v "$4" --arg by "$name" '{subject:[{hash:$f}],predicate:"https://w3id.org/ep-plan#hasRationale",object:{value:$v},by:$by,when:"2026-04-02T09:00:00Z"}')" >/dev/null; fi; }

# the published step, authored by whoever signs it
pooled(){ # pooled REGISTRY KEY [more --in ...]
  local reg="$1" key="$2"; shift 2
  plankton author --registry "$reg" --add --sign "$key" --print-id "$@" \
    --cmd "Rscript bill-pooled.R penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt" \
    --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
    --in bill-pooled.R         --located "$(loc bill-pooled.R files/bill-pooled.R)" \
    --out figures/fig1-bill-pooled.svg --located "$(loc figures/fig1-bill-pooled.svg figures/fig1-bill-pooled.svg)" \
    --out out/bill-pooled.txt          --located "$(loc out/bill-pooled.txt files/bill-pooled.txt)" 2>/dev/null; }

# -- stage 1: the llm --------------------------------------------------------
say "3 · stage 1: the llm runs it"
P="$R/llm/plankton"
A1=$(plankton author --print-id --registry "$P" --add --sign "$(K llm)" \
  --cmd "Rscript anonymise.R penguins-named.csv penguins.csv" \
  --in penguins-named.csv \
  --in anonymise.R --located "$(loc anonymise.R files/anonymise.R)" \
  --out penguins.csv --located "$(loc penguins.csv files/penguins.csv)" 2>/dev/null)
A2=$(plankton author --print-id --registry "$P" --add --sign "$(K llm)" \
  --cmd "Rscript drop-incomplete.R penguins.csv penguins-complete.csv" \
  --in penguins.csv           --located "$(loc penguins.csv files/penguins.csv)" \
  --in drop-incomplete.R      --located "$(loc drop-incomplete.R files/drop-incomplete.R)" \
  --out penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" 2>/dev/null)
F=$(pooled "$P" "$(K llm)")
A4=$(plankton author --print-id --registry "$P" --add --sign "$(K llm)" \
  --cmd "Rscript flipper-mass.R penguins-complete.csv figures/fig2-flipper-mass.svg" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in flipper-mass.R        --located "$(loc flipper-mass.R files/flipper-mass.R)" \
  --out figures/fig2-flipper-mass.svg --located "$(loc figures/fig2-flipper-mass.svg figures/fig2-flipper-mass.svg)" 2>/dev/null)
# figure 3 is deliberately not authored (see docs/lens-paper): the lens has nothing to say about it.
WHEN="2026-04-02T09:00:00Z"
desc llm "$A1" "Strip the animal names" "The released file must not identify animals: the named records stay with the ethics committee, known here by hash only."
desc llm "$A2" "Drop incomplete records" "Two animals lack bill measurements; the fits need complete rows."
desc llm "$F"  "Bill length vs depth, all species (fig. 1)" "The field guide asks whether bill length can stand in for bill shape. One pooled fit over all 342 complete records answers that for the whole sample; the data are the released file, so anyone can rerun it."
desc llm "$A4" "Flipper length vs body mass (fig. 2)" "A sanity check: the expected strong positive relation."
echo "  foton $F, signed by the llm, with its description and rationale"

# -- stage 2: the rerun ------------------------------------------------------
say "4 · stage 2: Lena reruns it"
# Lena reruns it in her own R and records which R that was (lena-env.txt): her record names her
# environment, so it is a record of its own - and the bytes it made are the llm's, byte for byte (L0).
cd "$W"; cp figures/fig1-bill-pooled.svg first.svg; rm figures/fig1-bill-pooled.svg out/bill-pooled.txt
Rscript -e 'writeLines(R.version.string, "lena-env.txt")'
run bill-pooled.R penguins-complete.csv figures/fig1-bill-pooled.svg out/bill-pooled.txt
F2=$(pooled "$R/rerun/plankton" "$(K lena)" --in lena-env.txt --located "$(loc lena-env.txt files/lena-env.txt)")
[[ "$F2" != "$F" ]] || { echo "the rerun should be a record of its own" >&2; exit 1; }
LEVEL=$(plankton reproduces "$(plankton hash first.svg)" "$(plankton hash figures/fig1-bill-pooled.svg)" | grep -o 'L[012]' | head -1)
[[ "$LEVEL" == L0 ]] || { echo "the rerun did not give the same bytes" >&2; exit 1; }
claim "$R/rerun/nekton" "$(K lena)" "$(jq -nc --arg s "$F2" --arg f "$F" '{subject:[{hash:$s}],predicate:"https://kton.dev/v/reproduces",
  object:{L0:{hash:$f}},why:"reran bill-pooled.R in my own R from the released data: the same figure and numbers, byte for byte",
  by:"Lena Moreau",when:"2026-04-20T14:00:00Z"}')" >/dev/null
desc rerun "$F2" "Rerun of fig. 1, in Lena's own R" "Before the report goes out, a person reruns the published step from the released data; her record names the R it ran in."
echo "  rerun $F2 by Lena reproduces $F at L0 (same bytes); signed as a reproduces claim"

# -- stage 3: the review -----------------------------------------------------
say "5 · stage 3: the review"
WHEN="2026-05-11T09:00:00Z"
scl(){ # scl DIR SIGNER SUBJECT-JSON PREDICATE OBJECT-JSON SCOPE PREV [extra-json]
  claim "$1" "$(K "$2")" "$(jq -nc --argjson s "$3" --arg p "$4" --argjson o "$5" --arg by "$2" --arg w "$WHEN" \
    --arg sc "$6" --arg pv "$7" --argjson x "${8:-null}" \
    '{subject:[$s],predicateBody:({predicate:{uri:$p},object:$o,by:$by,when:$w,scope:$sc,prev:$pv}+($x // {}))}')"; }
PUB=$(NEKTON_DIR="$W/pub" nekton seed journal --sign "$(K editor)" --by editor --when "$WHEN" --add 2>&1 | seedid)
prev="$PUB"
for who in llm lena reviewer1 reviewer2; do
  kind=Person; [[ "$who" == llm ]] && kind=SoftwareAgent
  prev=$(scl "$W/pub" editor "{\"uri\":\"https://kton.dev/agent/$(kid $who)\"}" \
    "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" "{\"uri\":\"http://www.w3.org/ns/prov#$kind\"}" "$PUB" "$prev")
  echo "  editor: $who is a $kind"
done
REV=$(NEKTON_DIR="$W/rev" nekton seed review-fs-2026-04 --parent "$PUB" --sign "$(K editor)" --by editor --when "$WHEN" --add 2>&1 | seedid)
RULE=$(scl "$W/rev" editor "{\"hash\":\"$REV\"}" "https://kton.dev/v/review-initialised" \
  "{\"hash\":\"$(plankton hash "$HERE/four-eyes.rq")\"}" "$REV" "$REV" "{\"foton\":\"$F\"}")
prev=$(scl "$W/pub" editor "{\"hash\":\"$REV\"}" "https://kton.dev/v/review-initialised" "{\"hash\":\"$RULE\"}" "$PUB" "$prev")
p="$RULE"
for who in reviewer1 reviewer2; do
  p=$(scl "$W/rev" "$who" "{\"hash\":\"$F\"}" "https://kton.dev/v/reviewed" '{"value":"approve"}' "$REV" "$p")
done
HEAD=$(NEKTON_DIR="$W/rev" nekton head "$REV" | awk '/^head:/{print $2}')
prev=$(scl "$W/pub" editor "{\"hash\":\"$REV\"}" "https://kton.dev/v/closed" "{\"hash\":\"$HEAD\"}" "$PUB" "$prev")
echo "  rule anchored -> reviewer1, reviewer2 approve -> sealed into the journal's scope"

# the records the check reads, published under records/ (commit B)
cp "$R/llm/plankton/objects/sha256/${F#sha256:}.json" "$HERE/records/foton.json"
cp "$W"/pub/objects/scope/*.nekton.jsonl "$HERE/records/journal.nekton.jsonl"
cp "$W"/rev/objects/scope/*.nekton.jsonl "$HERE/records/review.nekton.jsonl"
cd "$HERE"
CHECK_IN=(records/foton.json records/journal.nekton.jsonl records/review.nekton.jsonl)
./check.sh trust "${CHECK_IN[@]}" > review/verdict.csv
sed 's/^/  /' review/verdict.csv
tr -d '\r' < review/verdict.csv | grep -q ',yes$' || { echo "the review check did not say yes" >&2; exit 1; }
./check.sh trust "${CHECK_IN[@]}" > "$W/rederived.csv"
echo -n "  re-derived: "; plankton reproduces "$(plankton hash review/verdict.csv)" "$(plankton hash "$W/rederived.csv")" | head -1
cp "$HERE/verdict.R" review/verdict.R
(cd review && Rscript verdict.R verdict.csv verdict.svg >/dev/null)

P="$R/review/plankton"
ins=(); for f in check.sh four-eyes.rq; do ins+=(--in "$f" --located "$(loc "$f" "$f")"); done
for f in "${CHECK_IN[@]}"; do ins+=(--in "$f" --located "$(rloc "$f" "$f")"); done
for f in trust/*.pub; do ins+=(--in "$f" --located "$(loc "$f" "$f")"); done
CHECKF=$(plankton author --registry "$P" --add --sign "$(K editor)" --print-id \
  --cmd "./check.sh trust ${CHECK_IN[*]}   (oxigraph 0.5.12, ${OXIGRAPH##*@})" "${ins[@]}" \
  --out review/verdict.csv --located "$(loc review/verdict.csv review/verdict.csv)" 2>/dev/null)
VF=$(plankton author --print-id --registry "$P" --add --sign "$(K editor)" \
  --cmd "Rscript verdict.R verdict.csv verdict.svg" \
  --in review/verdict.csv --located "$(loc review/verdict.csv review/verdict.csv)" \
  --in review/verdict.R   --located "$(loc review/verdict.R review/verdict.R)" \
  --out review/verdict.svg --located "$(loc review/verdict.svg review/verdict.svg)" 2>/dev/null)
desc review "$CHECKF" "Review check: four eyes, people only" "The rule anchored before anyone reviewed, run in Oxigraph over the signed records themselves: two approvals by declared people, nobody approving their own work."
desc review "$VF" "Draw the review verdict"
# what the check found, said about what was reviewed: the check's run -> the figure's step, "reviewed · valid"
claim "$R/review/nekton" "$(K editor)" "$(jq -nc --arg c "$CHECKF" --arg f "$F" --arg v "sha256:$(sha256sum "$HERE/review/verdict.csv" | cut -d' ' -f1)" \
  '{subject:[{hash:$c}],predicate:"https://kton.dev/v/review-valid",object:{"review-valid":{hash:$f}},
  why:"four-eyes.rq over the signed records: two approvals by declared people, no rejects, nobody approving their own work",
  evidence:[{hash:$v}],by:"Journal editor",when:"2026-05-11T09:30:00Z"}')" >/dev/null
echo "  the check is foton $CHECKF; verdict.svg builds on it"
mkdir -p "$R/review/nekton/objects/scope"; cp "$W"/pub/objects/scope/*.nekton.jsonl "$W"/rev/objects/scope/*.nekton.jsonl "$R/review/nekton/objects/scope/"
cd "$W"

# Reviewer 2 approved: the step reproduces and the number is right. And asked for the species split,
# which the report does not carry - the same story as the lens paper.
P="$R/review/plankton"
FS=$(plankton author --registry "$P" --add --sign "$(K reviewer2)" --print-id \
  --cmd "Rscript bill-by-species.R penguins-complete.csv figures/bill-by-species.svg out/bill-by-species.txt" \
  --in penguins-complete.csv --located "$(loc penguins-complete.csv files/penguins-complete.csv)" \
  --in bill-by-species.R     --located "$(loc bill-by-species.R reviewer/bill-by-species.R)" \
  --out figures/bill-by-species.svg --located "$(loc figures/bill-by-species.svg reviewer/bill-by-species.svg)" \
  --out out/bill-by-species.txt     --located "$(loc out/bill-by-species.txt reviewer/bill-by-species.txt)" 2>/dev/null)
desc review "$FS" "Bill length vs depth, by species" "Asked for in review: the same question once species is taken into account." reviewer2 "Reviewer 2"
claim "$R/review/nekton" "$(K reviewer2)" "$(jq -nc --arg f "$FS" '{subject:[{hash:$f}],
  predicate:"https://kton.dev/v/the-same-question-split-by-species",
  object:{value:"what the published analysis looks like once species is taken into account. Same data, same code path, one grouping added."},
  by:"Reviewer 2",when:"2026-05-11T08:15:00Z"}')" >/dev/null
claim "$R/review/nekton" "$(K reviewer2)" "$(jq -nc --arg h "sha256:$(sha256sum figures/fig1-bill-pooled.svg | cut -d' ' -f1)" --arg f "$FS" \
  '{subject:[{hash:$h}],predicate:"https://kton.dev/v/does-not-hold-within-species",
  object:{value:"approved: it reproduces and the numbers are right. But the downward line is a difference between species. Within every species the relationship runs the other way: Adelie +0.391, Chinstrap +0.654, Gentoo +0.643. Asked for in review; not in the report."},
  evidence:[{hash:$f}],by:"Reviewer 2",when:"2026-05-11T08:30:00Z"}')" >/dev/null

# -- ethics: the data-sovereignty layer (as in docs/lens-paper) ---------------
say "6 · the ethics committee"
FR=$(plankton author --registry "$R/ethics/plankton" --add --sign "$(K ethics)" --print-id \
  --cmd "Rscript anonymise.R penguins-named.csv ethics-recheck.csv" \
  --in penguins-named.csv \
  --in anonymise.R --located "$(loc anonymise.R files/anonymise.R)" \
  --out ethics-recheck.csv --located "$(loc ethics-recheck.csv ethics/ethics-recheck.csv)" 2>/dev/null)
claim "$R/ethics/nekton" "$(K ethics)" "$(jq -nc --arg f "$FR" '{subject:[{hash:$f}],
  predicate:"https://kton.dev/v/anonymisation-verified",
  object:{value:"re-ran on the held source records; output identical to the released file; 344 animals, no direct identifiers remain"},
  by:"Animal Welfare and Ethics Committee",why:"The source records remain with the committee and are not released.",
  when:"2026-03-02T11:00:00Z"}')" >/dev/null
FI=$(plankton author --print-id --registry "$R/ethics-internal/plankton" --add --sign "$(K ethics)" \
  --cmd "Rscript audit.R penguins-named.csv ethics-audit.txt" \
  --in penguins-named.csv --located "$(loc penguins-named.csv ethics/penguins-named.csv)" \
  --in audit.R            --located "$(loc audit.R ethics/audit.R)" \
  --out ethics-audit.txt  --located "$(loc ethics-audit.txt ethics/ethics-audit.txt)" 2>/dev/null)
desc ethics "$FR" "Re-run the anonymisation on the held records"
desc ethics-internal "$FI" "Audit the named records"

# ------------------------------------------------------------------- publish
say "7 · files under docs/lens-cycle/"
cp "$W"/{penguins.csv,penguins-complete.csv,anonymise.R,drop-incomplete.R,bill-pooled.R,flipper-mass.R,SOURCE.txt} "$HERE/files/"
cp "$W/out/bill-pooled.txt" "$W/lena-env.txt" "$HERE/files/"
cp "$W"/figures/fig[123]-*.svg "$HERE/figures/"
cp "$W"/{penguins-named.csv,audit.R,ethics-audit.txt,ethics-recheck.csv} "$HERE/ethics/"
cp "$W/bill-by-species.R" "$W/figures/bill-by-species.svg" "$W/out/bill-by-species.txt" "$HERE/reviewer/"

python3 - "$W/keys" "$R" "$HERE/reg" <<'PY'
import json, sys, glob, os, subprocess
keys, src, dst = sys.argv[1:4]
names = {"llm": "Station LLM (agent session)", "lena": "Lena Moreau (Palmer Field Station)",
         "editor": "Journal editor", "reviewer1": "Reviewer 1", "reviewer2": "Reviewer 2",
         "ethics": "Animal Welfare and Ethics Committee"}
kj, nj = {}, {}
for who, label in names.items():
    k = os.path.join(keys, who + ".key")
    kid = subprocess.check_output(["plankton", "keyid", k], text=True).strip()
    kj[kid] = subprocess.check_output(["plankton", "pubkey", k], text=True).strip()
    nj[kid] = label
def records(r):
    out = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(src, r, "plankton", "objects", "sha256", "*.json")))]
    for f in sorted(glob.glob(os.path.join(src, r, "nekton", "objects", "**", "*.jsonl"), recursive=True)):
        out += [json.loads(l) for l in open(f) if l.strip()]
    return out
# one registry per party: the lens adds them one by one, and they splice by hash in the reader's browser
for r in ["llm", "rerun", "review", "ethics", "ethics-internal"]:
    d = os.path.join(dst, r); os.makedirs(d, exist_ok=True)
    json.dump(dict(sorted(kj.items())), open(os.path.join(d, "keys.json"), "w"), indent=2)
    json.dump(nj, open(os.path.join(d, "names.json"), "w"), indent=2)
    out = records(r)
    with open(os.path.join(d, "union.json"), "w") as fh:
        json.dump(out, fh, indent=2); fh.write("\n")
    print("  %-16s %d record(s)" % (r, len(out)))
PY
rm -rf "$W"

say "done"
echo "  locators: ${BASE:-relative (local preview only)}   records: ${RBASE:-relative}"
if [[ -n "$SERVE" ]]; then
  echo "  http://localhost:$SERVE/lens-cycle.html - Ctrl-C to stop"
  cd "$DOCS" && exec python3 -m http.server "$SERVE"
fi
