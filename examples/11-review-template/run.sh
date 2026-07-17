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
echo "  distinct review claims on disk (append-only, nothing overwritten): $(ls "$NEKTON_DIR"/objects/sha256/*.json | wc -l | tr -d ' ')"
echo "  distinct signing keyids among the reviews:                         $(nekton by predicate http://purl.org/pav/reviewedBy | grep -oE 'keyid=[0-9a-f]+' | sort -u | wc -l | tr -d ' ')"
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
for f in "$NEKTON_DIR"/objects/sha256/*.json; do nekton export --nanopub --trust-keys "$W/keys" "$f" >> "$W/reviews.trig"; echo >> "$W/reviews.trig"; done
echo "  exported: lineage.ttl (foton, PROV) + reviews.trig (each review as a nanopublication)"
if python3 -c "import rdflib" 2>/dev/null; then
  python3 "$EXDIR/check_completeness.py" "$W/lineage.ttl" "$W/reviews.trig" "$EXDIR/completeness.rq" "${FOTON#sha256:}" alice bob carol
else
  echo "  (SPARQL step needs rdflib: 'pip install rdflib' - skipping the completeness check)"
fi

echo
snapshot 11-review-template "$W/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
