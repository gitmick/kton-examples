#!/usr/bin/env bash
# 17 - ↻N: how many INDEPENDENT signers produced this exact output?
#
# Example 03 asks whether two results match. This asks something a reviewer actually wants: how many
# separate parties got here. That number is the difference between "someone says so" and "several
# people, who do not answer to each other, agree" - and it is the single most forgeable number in the
# system, because a keyid inside an envelope is an unauthenticated hint until somebody checks it.
#
# So plankton reports it two ways and refuses to let you confuse them: over SELF-DECLARED keyids
# (cheap, and it warns you every time) or over VERIFIED signatures against keys you named
# (--trust-keys). The gap between the two numbers is exactly the forgery.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/plankton"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$PWD/.work/keys" "$PWD/.work/trusted"
W=".work"
for who in alice bob mallory; do plankton keygen "$W/keys/$who" --seed "$(demoseed "$who")" >/dev/null; done
# The verifier's OWN trust set: the two labs it knows. mallory is not in it - not because she is
# suspected, but because nobody vouched for her. That is the whole mechanism.
cp "$W/keys/alice.pub" "$W/keys/bob.pub" "$W/trusted/"

# repro_json <trust-keys-dir|-> - the machine form of the same question shown just above. stderr is
# dropped ONLY here: the human call immediately preceding printed the very same warnings, and
# repeating them for a read that exists to be asserted on would bury them.
repro_json(){
  if [ "$1" = "-" ]; then plankton reproductions "$OUT" --json 2>/dev/null
  else plankton reproductions --trust-keys "$1" "$OUT" --json 2>/dev/null; fi
}
field(){ python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

echo "########## Part 1 - alice runs it ##########"
echo "id,conc" > "$W/pk.csv"; printf '1,4.2\n2,3.8\n' >> "$W/pk.csv"
echo "cl=4.000" > "$W/fit.out"
plankton author --cmd "fit pk.csv" --in "$W/pk.csv" --out "$W/fit.out" \
  --sign "$W/keys/alice.key" --add >/dev/null
OUT=$(plankton hash "$W/fit.out")
echo "  output under discussion: $OUT"

echo
echo "########## Part 2 - bob runs the same thing, independently ##########"
# Same inputs, same protocol, same bytes out. The foton id is over the COVERED projection, so bob's
# record IS alice's record - and his signature lands on it as a CO-SIGNATURE. Independent
# reproduction is not two documents agreeing; it is two signatures on one content-addressed fact.
plankton author --cmd "fit pk.csv" --in "$W/pk.csv" --out "$W/fit.out" \
  --sign "$W/keys/bob.key" --add >/dev/null
plankton reproductions --trust-keys "$W/trusted" "$OUT" | sed 's/^/  /'
N=$(repro_json "$W/trusted" | field distinctSigners)
[ "$N" = "2" ] || { echo "  !! expected ↻2 verified, got $N" >&2; exit 1; }
echo "  [asserted: ↻2 verified signers on ONE producer foton - a co-signature, not a copy]"

echo
echo "########## Part 3 - the cheap number, and what plankton says about it ##########"
plankton reproductions "$OUT" | sed 's/^/  /'
echo "  -> Note it warns without being asked. A keyid in an envelope is a hint, not a fact."

echo
echo "########## Part 4 - mallory inflates ↻N, and it costs her nothing ##########"
# Three variants of the same command over the same input, each producing the same output - so each is
# a DIFFERENT producer foton for the SAME result. Then she relabels the keyid on each: the field is
# not covered by the signature, so rewriting it is free and breaks nothing she needs.
for i in 1 2 3; do
  plankton author --cmd "fit pk.csv # pass $i" --in "$W/pk.csv" --out "$W/fit.out" \
    --sign "$W/keys/mallory.key" -o "$W/m$i.json" >/dev/null
  python3 - "$W/m$i.json" "$W/forged$i.json" "$i" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))
env["signatures"][0]["keyid"] = ("%02d" % int(sys.argv[3])) * 8   # a keyid she does not hold
json.dump(env, open(sys.argv[2], "w"))
PY
  plankton add "$W/forged$i.json" >/dev/null 2>&1
done
echo "-- the naive count, over self-declared keyids --"
plankton reproductions "$OUT" | sed 's/^/  /'
NAIVE=$(repro_json - | field distinctSigners)
# Assert the attack WORKED. Without this the example would keep passing if the forgery silently
# stopped inflating, and would then be demonstrating nothing while looking identical.
[ "$NAIVE" -gt 2 ] || { echo "  !! the forgery did not inflate ↻N (got $NAIVE) - this example proves nothing now" >&2; exit 1; }
echo "  [asserted: the forgery really did inflate the self-declared count to ↻$NAIVE]"

echo
echo "-- the same question, asked against keys somebody vouched for --"
plankton reproductions --trust-keys "$W/trusted" "$OUT" | sed 's/^/  /'
J=$(repro_json "$W/trusted")
N=$(printf '%s' "$J" | field distinctSigners)
EXCL=$(printf '%s' "$J" | field excludedUntrusted)
[ "$N" = "2" ] || { echo "  !! expected ↻2 verified after the forgery, got $N" >&2; exit 1; }
echo "  [asserted: still ↻2 verified; $EXCL producer(s) excluded as untrusted]"
echo "  -> ↻$NAIVE became ↻$N. Nothing was detected and nothing was blocked: the forged records are"
echo "     still in the registry, still well-formed. The only thing that changed is which question"
echo "     was asked - over declared labels, or over signatures against keys you chose to trust."

echo
snapshot 17-reproductions "$W/keys" --reg "$PLANKTON_DIR"
