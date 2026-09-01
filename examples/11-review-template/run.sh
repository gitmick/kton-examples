#!/usr/bin/env bash
# 11 - review template: the classical way to author a claim is a TEMPLATE, not hand-written JSON.
# A `review/decision` template turns "approve/reject this foton + attach a comment file" into one
# `nekton annotate` call, with the vocabulary REUSED (no minted terms): pav:reviewedBy for the review
# relation, schema.org AcceptAction/RejectAction for the verdict. Three independent reviewers each
# approve; nothing is overwritten (every review is its own content-addressed signed claim). Then we
# register the template itself in a separate nekton registry (it is federated data), export the RDF,
# and run a SPARQL query that tests the review is COMPLETE.
set -euo pipefail
EXDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$EXDIR"; source ../../lib/common.sh
export PLANKTON_DIR=".work/plankton"
export NEKTON_DIR=".work/nekton"                 # the reviews registry
export NEKTON_TEMPLATES="$EXROOT/templates"             # the shared, curated template set
export NEKTON_ALIASES="$EXROOT/aliases.json"
rm -rf ".work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" ".work/keys"
W=".work"
APPROVE="https://schema.org/AcceptAction"               # reused schema.org verdicts (no minted terms)
REJECT="https://schema.org/RejectAction"

echo "########## Part 1 - the template (the classical mechanism, vs the raw claim of example 04) ##########"
nekton templates --show review/decision | sed 's/^/  /'

echo; echo "########## Part 2 - a foton to review ##########"
plankton keygen "$W/keys/author" >/dev/null
printf "auc\n42.0\n" > "$W/result.csv"; echo "verdict=within-range" > "$W/assessment.txt"
FOTON=$(plankton author --cmd "assess result.csv" --in "$W/result.csv" --out "$W/assessment.txt" \
  --sign "$W/keys/author.key" --add -o "$W/foton.dsse.json" | awk '/indexed foton/{print $3}')
echo "  foton = $FOTON"

echo; echo "########## Part 3 - THREE reviewers, each APPROVE with a comment file (nothing overwritten) #####"
for who in alice bob carol; do
  nekton keygen "$W/keys/$who" >/dev/null
  printf "# %s\nReproduced locally; AUC within range. Approve.\n" "$who" > "$W/$who.md"
  nekton annotate --foton "$W/foton.dsse.json" --template review/decision \
    --set decision="$APPROVE" --set comment="$W/$who.md" \
    --by "CN=${who^}" --sign "$W/keys/$who.key" --add >/dev/null
  echo "  $who approved (schema:AcceptAction) + attached $who.md"
done
echo "  --- correctness checks ---"
# The claims are the thing under test, so read them with the ASSERTING form: three reviewers went in,
# at least three records must come out. A reader that sees an empty store returns an empty list rather
# than an error (briefing B1), and every check below then measures nothing while looking fine.
records_required "$NEKTON_DIR" "review claims" 3 > "$W/records.jsonl"
echo "  distinct review claims on disk (append-only, nothing overwritten): $(grep -c '' < "$W/records.jsonl")"
# "nothing was overwritten" is a CLAIM, so check it rather than print it: three reviewers must show up
# as three distinct signing keys. Printed bare, a 1 here - the overwrite this example exists to
# disprove - would read as just another line of output.
NKEYS=$(nekton by predicate http://purl.org/pav/reviewedBy | grep -oE 'keyid=[0-9a-f]+' | sort -u | wc -l | tr -d ' ')
echo "  distinct signing keyids among the reviews:                         $NKEYS"
[ "$NKEYS" -eq 3 ] || { echo "  !! expected 3 distinct signers, saw $NKEYS - reviews are being overwritten or lost" >&2; exit 1; }
echo "  reviews recorded ABOUT the foton:"
nekton about "$FOTON" | sed 's/^/    /'

echo; echo "########## Part 4 - register the template itself in a SEPARATE nekton registry (federated) #####"
TPLHASH=$(plankton hash "$NEKTON_TEMPLATES/review-decision.json")
echo "  template content hash = $TPLHASH"
PUB="$W/nekton-publisher"; mkdir -p "$PUB"
nekton keygen "$W/keys/standards" >/dev/null
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/1999/02/22-rdf-syntax-ns#type","object":{"id":"https://kton.dev/template/v0"},"why":"the review/decision template (approve/reject a foton + a comment file)","by":"CN=Standards","when":"2026-07-16T00:00:00Z"}' \
  "$TPLHASH" > "$W/register.spec.json"
nekton claim "$W/register.spec.json" "$W/keys/standards.key" --registry "$PUB" --add | sed 's/^/  /'
echo "  a consumer federates the two registries (like example 02); the template DEFINITION now"
echo "  resolves by hash next to the reviews built from it:"
nekton mirror "$PUB" | sed 's/^/  /'
nekton about "$TPLHASH" | sed 's/^/    /'

echo; echo "########## Part 5 - export the RDF and TEST review completeness with SPARQL ##########"
plankton export --rdf -o "$W/lineage.ttl" >/dev/null 2>&1 || plankton export --rdf > "$W/lineage.ttl"
: > "$W/reviews.trig"
# COUNT the exports instead of assuming them. Every failed export appends nothing, so a loop that
# ignores its exit status yields a near-empty .trig and the SPARQL gate below then queries an empty
# graph - which it reads as "not enough approvals", i.e. as a verdict. This example once passed with a
# 21-byte reviews.trig for exactly that reason.
# Re-read here rather than reusing the Part 3 snapshot: Part 4 mirrored the template registration in,
# so the registry now holds MORE than the three reviews, and the export is meant to carry all of it.
records_required "$NEKTON_DIR" "records to export" 3 > "$W/export-records.jsonl"
exported=0
while IFS= read -r rec; do
  printf '%s\n' "$rec" > "$W/rec.json"
  if nekton export --nanopub --trust-keys "$W/keys" "$W/rec.json" >> "$W/reviews.trig" 2>>"$W/export.err"; then
    exported=$((exported + 1)); echo >> "$W/reviews.trig"
  fi
done < "$W/export-records.jsonl"
echo "  exported: lineage.ttl (foton, PROV) + reviews.trig ($exported nanopublication(s), $(wc -c < "$W/reviews.trig" | tr -d ' ') bytes)"
if [ "$exported" -lt 3 ]; then
  echo "  !! only $exported of the 3 reviews exported as nanopublications - the gate below would run on a"
  echo "     near-empty graph and call that 'incomplete'. Refusing. nekton export said:" >&2
  sed 's/^/       /' "$W/export.err" >&2
  exit 1
fi
if python3 -c "import rdflib" 2>/dev/null; then
  python3 "$EXDIR/check_completeness.py" "$W/lineage.ttl" "$W/reviews.trig" "$EXDIR/completeness.rq" "${FOTON#sha256:}" alice bob carol
elif [ "${KTON_ALLOW_SKIP:-}" = "1" ]; then
  echo "  !! SPARQL completeness check SKIPPED (no rdflib, KTON_ALLOW_SKIP=1). This is NOT a pass."
else
  # A check that did not run must not report success. CI installs rdflib, so this only ever fires on a
  # local box that is missing it - where the honest answer is "install it", not a green line.
  echo "  the SPARQL completeness check needs rdflib: pip install rdflib" >&2
  echo "  (set KTON_ALLOW_SKIP=1 to run the rest of the example without it - it will say so out loud)" >&2
  exit 1
fi

echo
snapshot 11-review-template "$W/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
