#!/usr/bin/env bash
# 14 - fetch: getting the bytes back to re-hash them.
#   Every record names its bytes by HASH; plankton stores NO bytes. So "verify by re-hashing" needs the
#   bytes from somewhere. A signed dcat:downloadURL located-at claim says WHERE they can be had; the
#   `kton fetch` cockpit command dereferences it and checks sha256(bytes)==hash BEFORE trusting a single
#   byte. That is the Trust chapter's middle rung: record-authentic (always) < CONTENT-PRESENT (this
#   example, needs bytes) < reproduced. The kernels never dereference a URI; resolving is kton's job.
#
#   TWO defences, and the example shows both, because each catches what the other cannot:
#     the TRUST POLICY decides whose location is even opened - a dereference is a request made from
#       YOUR host, and for file:// a read of YOUR disk, which no later check can retract;
#     the HASH decides whether the bytes that came back are the ones the record named.
#   The second is the older lesson ("the URI is a hint, the hash is the authority"). The first arrived
#   with kton #81 and is why --trust-keys is required: a stranger must not get to choose what this
#   process opens, however carefully it inspects the result afterwards.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/plankton"     # results + the local content (blob) store kton pins into
export NEKTON_DIR="$PWD/.work/nekton"         # the signed located-at claims
rm -rf "$PWD/.work"
mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys" "$PWD/.work/store" "$PWD/.work/mirror"
plankton keygen "$PWD/.work/keys/lab" --seed "$(demoseed lab)"      >/dev/null   # the producer
nekton  keygen "$PWD/.work/keys/stranger" --seed "$(demoseed stranger)" >/dev/null    # an UNTRUSTED third party (Stage C)
# A trust policy is a DIRECTORY OF PUBLIC KEYS the consumer chose. Two of them here, because the
# difference between them is the point of Stage C.
mkdir -p "$PWD/.work/trust-lab" "$PWD/.work/trust-both"
cp "$PWD/.work/keys/lab.pub"      "$PWD/.work/trust-lab/"
cp "$PWD/.work/keys/lab.pub"      "$PWD/.work/trust-both/"
cp "$PWD/.work/keys/stranger.pub" "$PWD/.work/trust-both/"
# --allow-local: these locators are file:// under .work. A signature about CONTENT says nothing about
# a path on this machine, so reading one takes a second, explicit yes from the operator.
FETCH=(kton fetch --trust-keys "$PWD/.work/trust-lab" --allow-local)

echo "########## A - a record names its bytes by HASH; the local content store is empty ##########"
echo "dose,conc" > .work/data.csv
echo "result=42" > .work/result.txt
FOTON="$(plankton author --cmd "analyze data.csv result.txt" \
  --in .work/data.csv --out .work/result.txt --sign "$PWD/.work/keys/lab.key" --add --print-id)"
RESULT="$(plankton hash .work/result.txt)"
echo "  foton = $FOTON"
echo "  its result is named by content hash: $RESULT"
# The bytes live on the producer's side (a server, an object store, a mirror), NOT in the consumer's
# content store - plankton stores only hashes. `kton blob` asks the LOCAL store, which is empty:
cp .work/result.txt .work/store/result.bytes     # the producer keeps the bytes here
echo -n "  is the content pinned locally? "; expect_fail "the local blob lookup (the bytes are deliberately NOT held)" kton blob "$RESULT"
echo "  -> you hold the record (the hash), but you cannot re-hash bytes you do not have."

echo; echo "########## B - a signed dcat:downloadURL says WHERE; kton fetch verifies sha256==hash ##########"
# located-at = the published DCAT term dcat:downloadURL (REUSED, not minted): subject = the content
# hash, object = a URI. It is a signed, post-hoc, plural SUGGESTION - the kernel never dereferences it.
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/dcat#downloadURL","object":{"uri":"file://.work/store/result.bytes"},"by":"CN=lab","when":"2026-07-16T00:00:00Z"}' \
  "$RESULT" > .work/loc.json
nekton claim .work/loc.json "$PWD/.work/keys/lab.key" --add >/dev/null
"${FETCH[@]}" "$RESULT"
echo -n "  pinned now? "; kton blob "$RESULT"
echo "  -> content-present: the bytes are here AND they hash to what the record named. Now you can"
echo "     re-run them (that is the 'reproduced' rung, examples 03/10)."

echo; echo "########## C1 - an untrusted stranger's location is never even opened ##########"
# an UNTRUSTED stranger publishes a SECOND signed location pointing at FORGED bytes.
echo "result=999 (forged)" > .work/mirror/result.bytes
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/dcat#downloadURL","object":{"uri":"file://.work/mirror/result.bytes"},"by":"CN=stranger","when":"2026-07-16T00:00:00Z"}' \
  "$RESULT" > .work/bad.json
nekton claim .work/bad.json "$PWD/.work/keys/stranger.key" --add >/dev/null
CLAIMED=$(nekton about "$RESULT" --json 2>/dev/null | jq 'length')
SEEN=$("${FETCH[@]}" "$RESULT" 2>&1 | sed -n 's/.*, \([0-9]*\) signed by a trusted key.*/\1/p')
echo "  located-at claims in the registry: $CLAIMED    signed by a key we trust: $SEEN"
[ "$CLAIMED" = "2" ] && [ "$SEEN" = "1" ] || { echo "  ASSERTION FAILED: expected 2 claims, 1 trusted (got $CLAIMED / $SEEN)" >&2; exit 1; }
echo "  -> the stranger's file:// URI is never dereferenced. That matters because dereferencing is a"
echo "     request FROM THIS HOST - and for file://, a read of this disk - which the hash check that"
echo "     follows cannot undo. A stranger does not get to choose what this process opens."

echo; echo "########## C2 - and if we DO trust them, the hash still catches the forgery ##########"
# Trust the stranger too, and make the good copy unreachable, so the forged location is the one tried.
# Without that, fetch returns on the first location that resolves and the mismatch below never runs -
# the narration would be prose over a silent success.
mv .work/store/result.bytes .work/store/result.bytes.away
expect_fail "the fetch (every reachable location fails its hash check)" \
  kton fetch --trust-keys "$PWD/.work/trust-both" --allow-local "$RESULT"
mv .work/store/result.bytes.away .work/store/result.bytes
echo "  -> a TRUSTED signer's bytes are checked exactly as hard: sha256(bytes) != the named hash, so"
echo "     they are rejected and nothing is pinned. Trust decides whose location is opened; the hash"
echo "     decides whether what came back is what the record named. Neither replaces the other."

echo; echo "########## the boundary: availability is liveness the hash cannot give ##########"
echo "  If every located byte-store were gone or corrupt, kton fetch would fail: the record stays"
echo "  fully verifiable (signature + id), but the CONTENT is unavailable. Bytes are LOCATED, not"
echo "  stored, and kept per a retention policy - a named obligation, not a trust problem."

echo
# the viewer shows the result foton and the located-at claims (both the good and the forged locator):
# the graph shows CLAIMED locations - verification happens at fetch, on arrival, not in the picture.
snapshot 14-fetch "$PWD/.work/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
