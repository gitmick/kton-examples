#!/usr/bin/env bash
# 02 - environments + federation: TWO independent registries that never share a filesystem, they only
# exchange records BY HASH. This is the example for the two things people found unclear: how
# environments (registry directories) are used, and how the files are named across them.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

# ---- TWO ENVIRONMENTS -------------------------------------------------------
# Each environment is its own directory. We NEVER point both at the same PLANKTON_DIR; we set it
# per-command with an inline `PLANKTON_DIR=... plankton ...`. Naming convention used here:
#   env-a/, env-b/          the two registries (the "environments")
#   keys/<who>.key/.pub     one identity per participant
#   <who>-<step>.foton.json the signed envelope (who made it + what it is)
rm -rf "$PWD/.work"; mkdir -p "$PWD/.work/keys"
A="$PWD/.work/env-a"; B="$PWD/.work/env-b"; mkdir -p "$A" "$B"
plankton keygen "$PWD/.work/keys/alice" >/dev/null
plankton keygen "$PWD/.work/keys/bob"   >/dev/null

echo "== Create: alice records a foton in environment A =="
# plankton hashes EXISTING files (it never runs --cmd), so both input and output must exist first.
echo "raw,data"     > .work/dataset.csv
echo "cleaned,data" > .work/cleaned.csv
PLANKTON_DIR="$A" plankton author --cmd "clean dataset.csv cleaned.csv" \
  --in .work/dataset.csv --out .work/cleaned.csv \
  --sign "$PWD/.work/keys/alice.key" -o .work/alice-clean.foton.json >/dev/null
PLANKTON_DIR="$A" plankton add .work/alice-clean.foton.json

echo "== Create: bob records a foton in environment B (consuming alice's output) =="
echo "model=fit" > .work/model.txt
PLANKTON_DIR="$B" plankton author --cmd "fit cleaned.csv model.txt" \
  --in .work/cleaned.csv --out .work/model.txt \
  --sign "$PWD/.work/keys/bob.key" -o .work/bob-fit.foton.json >/dev/null
PLANKTON_DIR="$B" plankton add .work/bob-fit.foton.json

echo ""
echo "== FEDERATION: environment B mirrors environment A (by hash, no server) =="
# `mirror` copies A's records into B by content hash. No network, no shared directory - B simply
# gains A's fotons. This is how work moves between environments.
PLANKTON_DIR="$B" plankton mirror "$A"

echo ""
echo "== Use: from B, the two environments are now one lineage =="
CLEANED="$(PLANKTON_DIR="$B" plankton hash .work/cleaned.csv)"
echo "-- who USED alice's cleaned.csv as input? (bob's fit, now visible in B) --"
PLANKTON_DIR="$B" plankton uses "$CLEANED"
echo "-- full backward lineage of bob's model.txt --"
PLANKTON_DIR="$B" plankton lineage "$(PLANKTON_DIR="$B" plankton hash .work/model.txt)"

echo ""
# the viewer shows BOTH environments as one federated graph, coloured per participant
snapshot 02-environments-federation "$PWD/.work/keys" --reg "$A" --reg "$B"
