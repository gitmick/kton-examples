#!/usr/bin/env bash
# The review check, as one recorded step. Its inputs are the signed records themselves:
#   check.sh <trusted-keys-dir> <foton-record.json> <scope.nekton.jsonl>... <review-scope.nekton.jsonl>
#     -> the verdict, CSV, on stdout
# It projects them to RDF with the kernel's own projections (plankton export --rdf, nekton export
# --nanopub, signatures checked against the trusted keys on both), loads them into Oxigraph and runs
# four-eyes.rq. The foton's lineage goes into the graph <urn:kton:lineage>. What is checked goes in as
# the graph <urn:kton:check>, every id computed by the kernel from content, none taken from a file name:
# the foton (the id plankton computes from its envelope), the review scope (the scope of the genesis
# claim that opens the LAST scope file, as nekton projects it) and the hash of the four-eyes.rq that runs.
# The Oxigraph image is pinned by digest (OXIGRAPH); it is the step's environment.
set -euo pipefail
OXIGRAPH="${OXIGRAPH:-oxigraph/oxigraph@sha256:10677fb643f8c5a7bfb03dd8f7971c79a84b01e795c24201c8cfa12fd569f1c0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TRUST="$(cd "$1" && pwd)"; FOTON="$2"; shift 2
RULE="$(command plankton hash "$HERE/four-eyes.rq")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# plankton: the foton, with all its signatures -> PROV; its id as plankton computes it
mkdir -p "$T/p"; jq .envelope "$FOTON" > "$T/foton.dsse.json"
FID="$(PLANKTON_DIR="$T/p" command plankton add "$T/foton.dsse.json" 2>&1 | sed -n 's/^indexed foton sha256:\([0-9a-f]\{64\}\).*/\1/p')"
[ -n "$FID" ] || { echo "check.sh: plankton did not index $FOTON as a foton" >&2; exit 1; }
# the review scope: the genesis claim that opens the last scope file names it
head -n 1 "${@: -1}" | jq .envelope > "$T/genesis.dsse.json"
nekton export --nanopub "$T/genesis.dsse.json" > "$T/genesis.trig" 2>/dev/null
grep -q 'nk:genesis true' "$T/genesis.trig" || { echo "check.sh: ${*: -1} does not open with a genesis claim" >&2; exit 1; }
REVIEW="$(sed -n 's/.*nk:scope pk:\([0-9a-f]\{64\}\).*/\1/p' "$T/genesis.trig" | head -n 1)"
PLANKTON_DIR="$T/p" command plankton export --rdf --trust-keys "$TRUST" -o "$T/lineage.ttl" >/dev/null 2>&1
# nekton: every claim of the scopes -> its nanopublication
: > "$T/review.trig"; i=0
for scope in "$@"; do
  while IFS= read -r line; do i=$((i + 1))
    printf '%s' "$line" | jq .envelope > "$T/c$i.dsse.json"
    nekton export --nanopub "$T/c$i.dsse.json" --trust-keys "$TRUST" >> "$T/review.trig" 2>/dev/null && echo >> "$T/review.trig"
  done < "$scope"
done
printf '<urn:kton:check> { <urn:kton:check> <https://kton.dev/v/reviewScope> <https://kton.dev/o/%s> ;\n  <https://kton.dev/v/foton> <https://kton.dev/o/%s> ; <https://kton.dev/v/ruleFile> <https://kton.dev/o/%s> . }\n' \
  "$REVIEW" "$FID" "${RULE#sha256:}" > "$T/check.trig"
cp "$HERE/four-eyes.rq" "$T/"
docker run --rm -u "$(id -u):$(id -g)" -v "$T:/d" "$OXIGRAPH" load --location /d/db --file /d/lineage.ttl --graph urn:kton:lineage >/dev/null 2>&1
docker run --rm -u "$(id -u):$(id -g)" -v "$T:/d" "$OXIGRAPH" load --location /d/db --file /d/review.trig /d/check.trig >/dev/null 2>&1
docker run --rm -u "$(id -u):$(id -g)" -v "$T:/d" "$OXIGRAPH" query --location /d/db --query-file /d/four-eyes.rq \
  --results-format csv --union-default-graph
