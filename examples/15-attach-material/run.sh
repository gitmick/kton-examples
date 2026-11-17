#!/usr/bin/env bash
# 15 - external verification material: kton CARRIES it and never evaluates it.
#
# Everything up to here is verifiable with kton alone: a hash you re-compute, a signature you check
# against a key. Real records also arrive with evidence from OUTSIDE that vocabulary - a Sigstore
# bundle, a Rekor entry, an RFC 3161 timestamp, an eIDAS or CAdES signature. SPEC 8.1 gives that
# evidence a place (`attach`), a binding (a record's content address) and a BOUNDARY: the kernel
# stores it, indexes it, hands it back, and never decides whether it is any good. Deciding is the
# consumer's job, because "which issuers count" is a trust policy, not a fact about bytes.
#
# So this example does both halves: kton carries, and then a verifier that is NOT kton evaluates.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh
python3 -c "import cryptography" 2>/dev/null || { echo "this example needs python3 + cryptography (pip install cryptography)"; exit 1; }

export PLANKTON_DIR="$PWD/.work/plankton"
export NEKTON_DIR="$PWD/.work/nekton"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys"
W=".work"
plankton keygen "$W/keys/analyst"  --seed "$(demoseed analyst)"  >/dev/null
nekton   keygen "$W/keys/reviewer" --seed "$(demoseed reviewer)" >/dev/null

echo "########## Part 1 - two ordinary records: a foton and a claim about it ##########"
echo "raw" > "$W/data.csv"; echo "fit" > "$W/model.txt"
FOTON=$(plankton author --cmd "fit data.csv model.txt" --in "$W/data.csv" --out "$W/model.txt" \
  --sign "$W/keys/analyst.key" -o "$W/foton.dsse.json" --add --print-id)
printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/reviewed","object":{"value":"looks correct"},"by":"CN=Reviewer","when":"%s"}' \
  "$FOTON" "$KTON_WHEN" > "$W/review.spec.json"
CLAIM=$(nekton claim "$W/review.spec.json" "$W/keys/reviewer.key" "$W/claim.dsse.json" --add --print-id)
echo "  foton = $FOTON"
echo "  claim = $CLAIM"

echo
echo "########## Part 2 - THE TRAP: what an outside notary actually commits to ##########"
# An outside attestation (a Rekor entry, an RFC 3161 token) commits to the ENVELOPE PAYLOAD's hash.
# For a CLAIM that is the record id itself. For a FOTON it is NOT: a foton id is computed over the
# COVERED projection (SPEC 6.3), which excludes carried uri/id/mediaType - so the same envelope has
# two different hashes and only one of them is the id. Get this backwards and you will "check" a
# Rekor entry against a hash the entry never committed to, and it will simply never match.
python3 - "$W/foton.dsse.json" "$FOTON" "$W/claim.dsse.json" "$CLAIM" <<'PY'
import sys, json, base64, hashlib
for kind, env_path, rid in (("foton", sys.argv[1], sys.argv[2]), ("claim", sys.argv[3], sys.argv[4])):
    ph = hashlib.sha256(base64.b64decode(json.load(open(env_path))["payload"])).hexdigest()
    same = (ph == rid.replace("sha256:", ""))
    print(f"  {kind:6s} record id      {rid[:26]}…")
    print(f"         sha256(payload) sha256:{ph[:19]}…   -> {'THE SAME' if same else 'DIFFERENT'}")
PY
echo "  A claim id IS its payload hash; a foton id is one hop away from it. Both records are fine;"
echo "  the consumer just has to reach the payload through the envelope instead of assuming the id."

echo
echo "########## Part 3 - an outside notary vouches for each record ##########"
# Stand-in for a transparency log or a timestamping authority, but a REAL signature: python +
# cryptography, no kton code (same shape as example 13's foreign verifier).
python3 notary.py sign "$W/foton.dsse.json" "$(demoseed notary)" "$W/foton.token.json"
python3 notary.py sign "$W/claim.dsse.json" "$(demoseed notary)" "$W/claim.token.json"

echo
echo "########## Part 4 - attach: bind the evidence to the record's content address ##########"
# `example-notary/v0` is not one of the tokens SPEC 8.1 names, so it needs --media: the scheme list
# is OPEN, and an unknown scheme is carried rather than refused - but a reader must be told how to
# read the bytes.
plankton attach "$FOTON" --scheme example-notary/v0 --file "$W/foton.token.json" --media application/json | sed 's/^/  /'
nekton   attach "$CLAIM" --scheme example-notary/v0 --file "$W/claim.token.json" --media application/json | sed 's/^/  /'

echo
echo "== what is attached to each record =="
echo "-- foton --"; plankton material "$FOTON" | sed 's/^/  /'
echo "-- claim --"; nekton   material "$CLAIM" | sed 's/^/  /'
# Assert we can read back what we attached: `material` returning nothing is what a broken binding
# looks like, and it would otherwise read as "no evidence yet" (docs/briefing-2026-09.md B3).
NMAT=$(plankton material "$FOTON" --json | python3 -c "import json,sys;print(len(json.load(sys.stdin)['material']))")
[ "$NMAT" -eq 1 ] || { echo "  !! expected 1 piece of material on the foton, read $NMAT" >&2; exit 1; }
echo "  [asserted: the foton carries exactly 1 piece of material, read back through --json]"

echo
echo "########## Part 5 - the boundary, in both directions ##########"
echo "== kton refuses to bind evidence to a record it does not hold =="
# Material binds to a content address, not to a file lying around: a record the registry never saw
# cannot acquire evidence.
expect_fail "attaching to a record this registry does not hold" \
  plankton attach "sha256:$(printf '0%.0s' $(seq 64))" --scheme rekor-entry --file "$W/foton.token.json"
echo "  (refused, as it must be)"

echo "== kton refuses an unnamed scheme with no media type =="
expect_fail "an unknown scheme with no --media" \
  plankton attach "$FOTON" --scheme something-nobody-named --file "$W/foton.token.json"
echo "  (refused: an open list still has to be readable)"

echo
echo "== and kton NEVER says whether the evidence is any good - so the consumer does =="
# This is the half the kernel deliberately leaves undone. Note it goes through the ENVELOPE, using
# Part 2's distinction: the notary committed to the payload, not to the record id.
python3 notary.py verify "$W/foton.dsse.json" "$W/foton.token.json"
python3 notary.py verify "$W/claim.dsse.json" "$W/claim.token.json"

echo "== a token from a DIFFERENT record does not check out against this one =="
expect_fail "the claim's token checked against the foton" \
  python3 notary.py verify "$W/foton.dsse.json" "$W/claim.token.json"

echo
snapshot 15-attach-material "$W/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
