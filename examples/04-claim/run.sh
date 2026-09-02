#!/usr/bin/env bash
# 04 - claim: plankton records a reproducible foton; nekton records a signed OPINION about it. This
# shows the two layers meeting: a claim's subject is the foton's id, so they join by hash.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

# TWO registries here: plankton (results) and nekton (claims). Both are just directories.
export PLANKTON_DIR="$PWD/.work/plankton"
export NEKTON_DIR="$PWD/.work/nekton"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys"
plankton keygen "$PWD/.work/keys/analyst" --seed "$(demoseed analyst)"  >/dev/null   # makes the foton
nekton  keygen "$PWD/.work/keys/reviewer" --seed "$(demoseed reviewer)" >/dev/null    # makes the claim

echo "== Create: analyst records a foton (plankton) =="
echo "raw" > .work/data.csv; echo "fit" > .work/model.txt
# author + ingest in one step; the foton id is in the --add output
FOTON="$(plankton author --cmd "fit data.csv model.txt" \
  --in .work/data.csv --out .work/model.txt \
  --sign "$PWD/.work/keys/analyst.key" --add --print-id)"
echo "  foton id = $FOTON"

echo "== Create: reviewer records a CLAIM about that foton (nekton) =="
# A claim spec: subject is the foton id; predicate is an opaque IRI (here https://kton.dev/v/reviewed).
# The predicate is ACTIVE and unary on purpose. The obvious choice, pav:reviewedBy, is passive - "X was
# reviewed BY Y" - so its object slot belongs to the REVIEWER, and putting the verdict there says the
# foton was reviewed by "looks correct". The reviewer would then appear nowhere in what the claim
# asserts, only in `by`, which signs it. `reviewed` takes the verdict as its object and leaves the
# identity to the signature, which is where this record actually establishes it.
printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/reviewed","object":{"value":"looks correct"},"by":"CN=Reviewer","when":"2026-07-16T00:00:00Z"}' "$FOTON" > .work/review.spec.json
nekton claim .work/review.spec.json "$PWD/.work/keys/reviewer.key" .work/review.dsse.json --add >/dev/null

echo ""
echo "== Use: query the claim by its subject (the foton) =="
echo "-- what is said ABOUT the foton? --"
nekton about "$FOTON"
echo "-- show the claim --"
nekton show .work/review.dsse.json
echo "-- verify the reviewer's signature --"
nekton verify .work/review.dsse.json "$PWD/.work/keys/reviewer.pub"

echo ""
# the viewer shows the foton and the claim as one graph (claim joins the foton by hash)
snapshot 04-claim "$PWD/.work/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
