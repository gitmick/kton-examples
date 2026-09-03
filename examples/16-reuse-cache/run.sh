#!/usr/bin/env bash
# 16 - the action key: "has anyone computed this already?" - and why a HIT is not an answer.
#
# Every example so far asks about a computation that HAPPENED. This one asks BEFORE: given the inputs
# and the protocol I am about to run, has someone already run it? plankton answers from the records it
# holds, with no execution and no network - the question is a hash.
#
# The catch is the whole lesson. The action key covers INPUTS + PROTOCOL and deliberately NOT the
# output (SPEC 6.3) - the output is the thing you were going to compute. So a HIT means "somebody
# asked the same question", never "here is the answer": two signers can hit the same key and disagree
# about the result. A cache that told you otherwise would be a trust system, and this one refuses to
# be one.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/plankton"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$PWD/.work/keys"
W=".work"
plankton keygen "$W/keys/alice" --seed "$(demoseed alice)" >/dev/null   # runs it first
plankton keygen "$W/keys/mallory" --seed "$(demoseed mallory)" >/dev/null   # runs the same thing later

# hits <statement> - how many prior computations plankton reports for this action key.
# --json carries per hit what the printed form only hints at in a stderr note: `declaredSigner` and
# `verified: false`. That belongs on the record you act on, not in a warning beside it - an action
# key binds inputs and protocol, never the signer, so the hits COMPETE and the keyid on each is the
# envelope's unauthenticated hint.
hits(){ plankton reuse "$1" --json 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin)['hits']))"; }

echo "########## Part 1 - alice records a computation ##########"
echo "id,conc"  > "$W/pk.csv"; printf '1,4.2\n' >> "$W/pk.csv"
echo "cl=4.200" > "$W/fit.out"
plankton author --cmd "fit pk.csv" --in "$W/pk.csv" --out "$W/fit.out" \
  --sign "$W/keys/alice.key" -o "$W/alice.dsse.json" --add >/dev/null
echo "  alice's foton is on record."

echo
echo "########## Part 2 - bob is about to run the SAME thing, and asks first ##########"
# The question is the statement, not the answer: same inputs, same protocol. Bob has not computed
# anything yet, so he asks with alice's record as the shape of the question.
plankton reuse "$W/alice.dsse.json" | sed 's/^/  /'
N=$(hits "$W/alice.dsse.json"); [ "$N" = "1" ] || { echo "  !! expected 1 hit, got '${N:-none}'" >&2; exit 1; }
echo "  [asserted: exactly 1 prior computation]"

echo
echo "########## Part 3 - mallory answers the same question DIFFERENTLY ##########"
# Same inputs, same command - a different result. Nothing here is forged: mallory signs her own
# honest-looking foton. The action key does not care what the output is, so it collides on purpose.
echo "cl=9.999" > "$W/fit.out"
plankton author --cmd "fit pk.csv" --in "$W/pk.csv" --out "$W/fit.out" \
  --sign "$W/keys/mallory.key" -o "$W/mallory.dsse.json" --add >/dev/null
plankton reuse "$W/alice.dsse.json" | sed 's/^/  /'
N=$(hits "$W/alice.dsse.json"); [ "$N" = "2" ] || { echo "  !! expected 2 hits, got '${N:-none}'" >&2; exit 1; }
echo "  [asserted: 2 prior computations, same action key, DIFFERENT outputs]"
echo "  -> This is what the note means. The cache matched the QUESTION. The two answers disagree,"
echo "     and no amount of hashing decides between them; only a signer you trust does."

echo
echo "== so the consumer picks a signer and checks, instead of taking the cache's word =="
echo "-- alice's foton, against alice's key --"
plankton verify "$W/alice.dsse.json" "$W/keys/alice.pub" | sed 's/^/    /'
echo "-- mallory's foton, against alice's key (must NOT verify) --"
expect_fail "mallory's foton verified against alice's key" \
  plankton verify "$W/mallory.dsse.json" "$W/keys/alice.pub"
echo "  (WRONG KEY, as it must be: the cache offered both, the signature separates them)"

echo
echo "########## Part 4 - change one input byte and it is a different question ##########"
printf '2,3.8\n' >> "$W/pk.csv"                    # one row more: a different input hash
echo "cl=4.000" > "$W/fit2.out"
plankton author --cmd "fit pk.csv" --in "$W/pk.csv" --out "$W/fit2.out" \
  --sign "$W/keys/alice.key" -o "$W/other.dsse.json" >/dev/null      # authored, NOT filed
plankton reuse "$W/other.dsse.json" | sed 's/^/  /'
plankton reuse "$W/other.dsse.json" 2>/dev/null | grep -q '^cache: MISS' || {
  echo "  !! expected a MISS after changing an input - the action key is not covering the inputs" >&2; exit 1; }
echo "  [asserted: MISS - inputs are part of the key]"

echo
echo "########## Part 5 - two ways to poison a cache, both refused ##########"
# 5a. A foton may carry its protocol as a DESCRIPTOR (the real thing) plus a `ref` (its hash). If the
# two disagree the record is malformed (SPEC 6.2) - and a cache key computed from the lie would file
# a result under someone else's question. plankton recomputes the ref from the descriptor and refuses.
python3 - "$W/alice.dsse.json" "$W/poisoned.json" <<'PY'
import json, base64, sys
p = json.loads(base64.b64decode(json.load(open(sys.argv[1]))["payload"]))
p["predicate"]["protocol"]["ref"] = "sha256:" + "b" * 64      # claim a different protocol
json.dump(p, open(sys.argv[2], "w"))
PY
echo "-- a wire ref that disagrees with its own descriptor --"
expect_fail "a foton whose protocol.ref contradicts its descriptor" plankton reuse "$W/poisoned.json"

# 5b. The key is a {relpath -> hash} map, so two inputs at the same path are ambiguous: a silent
# last-wins would drop an input from the computation's identity and let a 2-input foton reuse a
# 1-input result. Refused rather than resolved.
python3 - "$W/alice.dsse.json" "$W/ambiguous.json" <<'PY'
import json, base64, sys
p = json.loads(base64.b64decode(json.load(open(sys.argv[1]))["payload"]))
ins = p["predicate"]["inputs"]
dup = json.loads(json.dumps(ins[0])); dup["digest"]["sha256"] = "c" * 64
p["predicate"]["inputs"] = ins + [dup]                         # same path, different bytes
json.dump(p, open(sys.argv[2], "w"))
PY
echo "-- two inputs at the same relative path --"
expect_fail "a foton with an ambiguous computation identity" plankton reuse "$W/ambiguous.json"

echo
echo "The cache answers 'was this asked?'. Example 03 answers 'do two results match?' and"
echo "example 17 answers 'how many INDEPENDENT signers got this same output?'. Three different"
echo "questions; only the last two are about trust."
echo
snapshot 16-reuse-cache "$W/keys" --reg "$PLANKTON_DIR"
