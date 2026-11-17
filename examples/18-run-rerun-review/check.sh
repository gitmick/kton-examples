#!/usr/bin/env bash
# The review check, as one recorded step. Its inputs are the signed records themselves:
#   check.sh <trusted-keys-dir> <foton-record.json> <scope.nekton.jsonl>...   -> the verdict, CSV, on stdout
# It projects them to RDF with the kernel's own projections (plankton export --rdf, nekton export
# --nanopub, signatures checked against the trusted keys), loads them into Oxigraph and runs four-eyes.rq.
# The Oxigraph image is pinned by digest (OXIGRAPH); it is the step's environment.
set -euo pipefail
OXIGRAPH="${OXIGRAPH:-oxigraph/oxigraph@sha256:10677fb643f8c5a7bfb03dd8f7971c79a84b01e795c24201c8cfa12fd569f1c0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TRUST="$(cd "$1" && pwd)"; FOTON="$2"; shift 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# plankton: the foton, with all its signatures -> PROV
mkdir -p "$T/p"; jq .envelope "$FOTON" > "$T/foton.dsse.json"
PLANKTON_DIR="$T/p" command plankton add "$T/foton.dsse.json" >/dev/null 2>&1
PLANKTON_DIR="$T/p" command plankton export --rdf -o "$T/lineage.ttl" >/dev/null 2>&1
# nekton: every claim of the scopes -> its nanopublication
: > "$T/review.trig"; i=0
for scope in "$@"; do
  while IFS= read -r line; do i=$((i + 1))
    printf '%s' "$line" | jq .envelope > "$T/c$i.dsse.json"
    nekton export --nanopub "$T/c$i.dsse.json" --trust-keys "$TRUST" >> "$T/review.trig" 2>/dev/null && echo >> "$T/review.trig"
  done < "$scope"
done
cp "$HERE/four-eyes.rq" "$T/"
docker run --rm -u "$(id -u):$(id -g)" -v "$T:/d" "$OXIGRAPH" load --location /d/db --file /d/lineage.ttl /d/review.trig >/dev/null 2>&1
docker run --rm -u "$(id -u):$(id -g)" -v "$T:/d" "$OXIGRAPH" query --location /d/db --query-file /d/four-eyes.rq \
  --results-format csv --union-default-graph
