#!/usr/bin/env bash
# 02 - federation, in two acts.
#   Act 1: two people, ONE shared registry (the familiar baseline - like a shared database).
#   Act 2: two SEPARATE registries that still converge to the same lineage by content hash, via mirror.
# The same closing query runs in both acts, so you see: same result, without the shared store.
#
# (A "registry" is a STORE, a folder of records - PLANKTON_DIR. Not an execution environment like a
# container or an OS. plankton stores NO file bytes, only hashes.)
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

rm -rf "$PWD/.work"; mkdir -p "$PWD/.work/keys"
plankton keygen "$PWD/.work/keys/alice" >/dev/null
plankton keygen "$PWD/.work/keys/bob"   >/dev/null
# The file bytes live in this working directory the whole time; on one machine both acts just read
# them from here. plankton stores none of these bytes, only their hashes.
echo "raw,data"     > .work/dataset.csv
echo "cleaned,data" > .work/cleaned.csv
echo "model=fit"    > .work/model.txt
MODEL="$(plankton hash .work/model.txt)"

echo "########## ACT 1 - two people, ONE shared registry ##########"
# What is shared here: the REGISTRY (the records). alice and bob both `plankton add` into the same
# PLANKTON_DIR, like a shared database, or a git remote everyone pushes to.
S="$PWD/.work/shared"; mkdir -p "$S"
PLANKTON_DIR="$S" plankton author --cmd "clean dataset.csv cleaned.csv" \
  --in .work/dataset.csv --out .work/cleaned.csv --sign "$PWD/.work/keys/alice.key" -o .work/alice.foton.json >/dev/null
PLANKTON_DIR="$S" plankton add .work/alice.foton.json
PLANKTON_DIR="$S" plankton author --cmd "fit cleaned.csv model.txt" \
  --in .work/cleaned.csv --out .work/model.txt --sign "$PWD/.work/keys/bob.key" -o .work/bob.foton.json >/dev/null
PLANKTON_DIR="$S" plankton add .work/bob.foton.json
echo "-- closing query: full lineage of model.txt, from the shared store --"
PLANKTON_DIR="$S" plankton lineage "$MODEL"

echo ""
echo "########## ACT 2 - two SEPARATE registries, federated ##########"
# But often you cannot share a store: different orgs, an air-gap, no server. Each person keeps their
# OWN registry. Nothing is shared between the two registries except records-by-hash, via `mirror`.
A="$PWD/.work/reg-a"; B="$PWD/.work/reg-b"; mkdir -p "$A" "$B"
PLANKTON_DIR="$A" plankton add .work/alice.foton.json   # alice's record -> registry A
PLANKTON_DIR="$B" plankton add .work/bob.foton.json     # bob's record   -> registry B
echo "-- B mirrors A: this moves RECORDS (hashes), never the file bytes --"
PLANKTON_DIR="$B" plankton mirror "$A"
echo "-- the SAME closing query, now from registry B --"
PLANKTON_DIR="$B" plankton lineage "$MODEL"
echo "   ^ identical to Act 1: one merged lineage, with no shared store."

echo ""
# the viewer shows Act 2's two registries as one federated graph, coloured per participant
snapshot 02-federation "$PWD/.work/keys" --reg "$A" --reg "$B"
