#!/usr/bin/env bash
# 02 - federation, in three acts, each sharing LESS than the last:
#   Act 1: two people, ONE shared registry (max coupling - like a shared database).
#   Act 2: two SEPARATE registries, read together as a union of sources (--source).
#          No shared store, no copy, neither store mutated - THIS is the federation primitive.
#   Act 3: `mirror` copies records into one store - an optimization for offline / single-store reads.
# The lineage of model.txt is complete in Act 1, incomplete from either store alone in Act 2, and
# complete again the moment both stores are named as sources - convergence by content hash, not copy.
#
# (A "registry" is a STORE, a folder of records - PLANKTON_DIR. Not an execution environment like a
# container or an OS. plankton stores NO file bytes, only hashes.)
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

rm -rf "$PWD/.work"; mkdir -p "$PWD/.work/keys"
plankton keygen "$PWD/.work/keys/alice" --seed "$(demoseed alice)" >/dev/null
plankton keygen "$PWD/.work/keys/bob" --seed "$(demoseed bob)"   >/dev/null
# The file bytes live in this working directory the whole time; on one machine every act just reads
# them from here. plankton stores none of these bytes, only their hashes.
echo "raw,data"     > .work/dataset.csv
echo "cleaned,data" > .work/cleaned.csv
echo "model=fit"    > .work/model.txt
MODEL="$(plankton hash .work/model.txt)"

echo "########## ACT 1 - two people, ONE shared registry (max coupling) ##########"
# What is shared here: the REGISTRY (the records). alice and bob both `plankton add` into the same
# PLANKTON_DIR, like a shared database, or a git remote everyone pushes to.
S="$PWD/.work/shared"; mkdir -p "$S"
# --add ingests into the shared store (--registry "$S") in one step; we keep the envelope files (-o)
# so the later acts can re-file the SAME records into separate registries.
plankton author --cmd "clean dataset.csv cleaned.csv" \
  --in .work/dataset.csv --out .work/cleaned.csv --sign "$PWD/.work/keys/alice.key" \
  --add --registry "$S" -o .work/alice.foton.json >/dev/null
plankton author --cmd "fit cleaned.csv model.txt" \
  --in .work/cleaned.csv --out .work/model.txt --sign "$PWD/.work/keys/bob.key" \
  --add --registry "$S" -o .work/bob.foton.json >/dev/null
echo "-- closing query: full lineage of model.txt, from the shared store --"
PLANKTON_DIR="$S" plankton lineage "$MODEL"

echo ""
echo "########## ACT 2 - two SEPARATE registries, read as one (the primitive) ##########"
# Often you cannot share a store: different orgs, an air-gap, no server. Each person keeps their OWN
# registry, and NOTHING is shared between them.
A="$PWD/.work/reg-a"; B="$PWD/.work/reg-b"; mkdir -p "$A" "$B"
plankton add .work/alice.foton.json --registry "$A"   # alice's record -> registry A
plankton add .work/bob.foton.json   --registry "$B"   # bob's record   -> registry B
echo "-- bob's store ALONE: the fit is here, but alice's clean is missing (incomplete, not wrong) --"
PLANKTON_DIR="$B" plankton lineage "$MODEL"
echo "-- name BOTH stores as sources: no mirror, no shared store, neither store is mutated --"
plankton lineage --source "$A" --source "$B" "$MODEL"
echo "   ^ complete again - the two records meet at the shared input hash the moment both are read."
# ASSERT the thesis instead of printing it. Every command above exits 0 and prints "(none)" on an
# empty store, so a lineage that silently returned nothing read exactly like one that worked - and
# this example's whole claim is that the SECOND read finds strictly more than the first.
ALONE=$(PLANKTON_DIR="$B" plankton lineage "$MODEL" --json | jq '.records | length')
BOTH=$(plankton lineage --source "$A" --source "$B" "$MODEL" --json | jq '.records | length')
echo "   [asserted: one store sees $ALONE record, both sources see $BOTH]"
[ "$ALONE" = "1" ] && [ "$BOTH" = "2" ] || {
  echo "   ASSERTION FAILED: expected 1 then 2, got $ALONE then $BOTH" >&2; exit 1; }
# "carol" is literally the same read command - which is the point: a read needs no identity, so ANYONE
# who names both sources gets this lineage. The stranger is not a third keyholder, just a third reader.
echo "-- a stranger (carol) who knows neither alice nor bob names both sources: identical result --"
plankton lineage --source "$A" --source "$B" "$MODEL" | sed 's/^/   carol sees:  /'

echo ""
echo "########## ACT 3 - mirror: copy records into one store (an optimization) ##########"
# mirror is a convenience ON TOP of the multi-source read (Act 2), for when you want one store that
# answers alone - offline, or a single cache. It copies RECORDS (hashes), never file bytes.
echo "-- B mirrors A: moves records (hashes), never bytes --"
PLANKTON_DIR="$B" plankton mirror "$A"
echo "-- now reg-b answers ALONE, same merged lineage as Act 2 --"
PLANKTON_DIR="$B" plankton lineage "$MODEL"
# The point of Act 3 is that mirroring reaches the SAME answer as Act 2's multi-source read, so the
# two are compared rather than both printed and eyeballed.
MIRRORED=$(PLANKTON_DIR="$B" plankton lineage "$MODEL" --json | jq '.records | length')
echo "   [asserted: after mirroring, one store alone sees $MIRRORED - the same as both sources]"
[ "$MIRRORED" = "$BOTH" ] || {
  echo "   ASSERTION FAILED: mirror gave $MIRRORED, the multi-source read gave $BOTH" >&2; exit 1; }
echo "   ^ mirror is convenience on top of the read - not what makes federation work."

echo ""
# the viewer shows the two registries as one federated graph, coloured per participant
snapshot 02-federation "$PWD/.work/keys" --reg "$A" --reg "$B"
