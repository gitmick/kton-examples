#!/usr/bin/env bash
# 06 - export as RDF: the plankton lineage and the nekton claims export to RDF that MERGES at the same
# pk:<hash> IRIs, so a reasoner sees the foton's provenance and the claim about it as one graph.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/plankton"
export NEKTON_DIR="$PWD/.work/nekton"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys" "$PWD/.work/exports"
plankton keygen "$PWD/.work/keys/analyst"  >/dev/null
nekton  keygen "$PWD/.work/keys/reviewer" >/dev/null

echo "== Create: a foton + a claim about it =="
echo "raw" > .work/data.csv; echo "model" > .work/model.txt
FOTON="$(plankton author --cmd "fit data.csv model.txt" --in .work/data.csv --out .work/model.txt \
  --sign "$PWD/.work/keys/analyst.key" --add | awk '/indexed foton/{print $3}')"
printf '{"subject":[{"hash":"%s"}],"predicate":"pav:reviewedBy","object":{"value":"approved"},"by":"CN=Reviewer","when":"2026-07-16T00:00:00Z"}' "$FOTON" > .work/review.spec.json
# keep the envelope file (for the nanopub export below) AND ingest, in one step
nekton claim .work/review.spec.json "$PWD/.work/keys/reviewer.key" .work/review.dsse.json --add >/dev/null

echo ""
echo "== Use: export both layers as RDF =="
echo "-- plankton lineage as RDF/Turtle (PROV) --"
plankton export --rdf -o .work/exports/lineage.ttl
grep -E "a prov:Activity|prov:wasGeneratedBy" .work/exports/lineage.ttl | sed 's/^/    /'
echo "-- nekton claim as nanopublication (RDF/TriG) --"
nekton export --nanopub .work/review.dsse.json -o .work/exports/claim.trig 2>/dev/null
grep -E "pav:reviewedBy" .work/exports/claim.trig | sed 's/^/    /'
FHEX="${FOTON#sha256:}"
echo "-- the JOIN: both name the same node pk:${FHEX:0:16}... --"
echo "    plankton: $(grep -c "pk:$FHEX a prov:Activity" .work/exports/lineage.ttl) activity"
echo "    nekton:   $(grep -c "pk:$FHEX" .work/exports/claim.trig) reference(s) to the same node"

echo ""
snapshot 06-nanopub-rdf "$PWD/.work/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
