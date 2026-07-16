#!/usr/bin/env bash
# 14 - fetch: getting the bytes back to re-hash them.
#   Every record names its bytes by HASH; plankton stores NO bytes. So "verify by re-hashing" needs the
#   bytes from somewhere. A signed dcat:downloadURL located-at claim says WHERE they can be had; the
#   `kton fetch` cockpit command dereferences it and checks sha256(bytes)==hash BEFORE trusting a single
#   byte. That is the Trust chapter's middle rung: record-authentic (always) < CONTENT-PRESENT (this
#   example, needs bytes) < reproduced. The kernels never dereference a URI; resolving is kton's job.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/plankton"     # results + the local content (blob) store kton pins into
export NEKTON_DIR="$PWD/.work/nekton"         # the signed located-at claims
rm -rf "$PWD/.work"
mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys" "$PWD/.work/store" "$PWD/.work/mirror"
plankton keygen "$PWD/.work/keys/lab"      >/dev/null   # the producer
nekton  keygen "$PWD/.work/keys/stranger" >/dev/null    # an UNTRUSTED third party (Stage C)

echo "########## A - a record names its bytes by HASH; the local content store is empty ##########"
echo "dose,conc" > .work/data.csv
echo "result=42" > .work/result.txt
FOTON="$(plankton author --cmd "analyze data.csv result.txt" \
  --in .work/data.csv --out .work/result.txt --sign "$PWD/.work/keys/lab.key" --add | awk '/indexed foton/{print $3}')"
RESULT="$(plankton hash .work/result.txt)"
echo "  foton = $FOTON"
echo "  its result is named by content hash: $RESULT"
# The bytes live on the producer's side (a server, an object store, a mirror), NOT in the consumer's
# content store - plankton stores only hashes. `kton blob` asks the LOCAL store, which is empty:
cp .work/result.txt .work/store/result.bytes     # the producer keeps the bytes here
echo -n "  is the content pinned locally? "; kton blob "$RESULT" || true
echo "  -> you hold the record (the hash), but you cannot re-hash bytes you do not have."

echo; echo "########## B - a signed dcat:downloadURL says WHERE; kton fetch verifies sha256==hash ##########"
# located-at = the published DCAT term dcat:downloadURL (REUSED, not minted): subject = the content
# hash, object = a URI. It is a signed, post-hoc, plural SUGGESTION - the kernel never dereferences it.
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/dcat#downloadURL","object":{"uri":"file://.work/store/result.bytes"},"by":"CN=lab","when":"2026-07-16T00:00:00Z"}' \
  "$RESULT" > .work/loc.json
nekton claim .work/loc.json "$PWD/.work/keys/lab.key" --add >/dev/null
kton fetch "$RESULT"
echo -n "  pinned now? "; kton blob "$RESULT"
echo "  -> content-present: the bytes are here AND they hash to what the record named. Now you can"
echo "     re-run them (that is the 'reproduced' rung, examples 03/10)."

echo; echo "########## C - a location is a HINT, not an authority: a tampered mirror is caught ##########"
# an UNTRUSTED stranger publishes a SECOND signed location pointing at FORGED bytes.
echo "result=999 (forged)" > .work/mirror/result.bytes
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/dcat#downloadURL","object":{"uri":"file://.work/mirror/result.bytes"},"by":"CN=stranger","when":"2026-07-16T00:00:00Z"}' \
  "$RESULT" > .work/bad.json
nekton claim .work/bad.json "$PWD/.work/keys/stranger.key" --add >/dev/null
kton fetch "$RESULT"
echo "  -> the forged mirror HASH-MISMATCHES and is rejected; a good location still verifies."
echo "     Content addressing self-checks on arrival, so bytes may come from ANY mirror - even an"
echo "     untrusted one - because the hash is the authority and the URI is only a hint."

echo; echo "########## the boundary: availability is liveness the hash cannot give ##########"
echo "  If every located byte-store were gone or corrupt, kton fetch would fail: the record stays"
echo "  fully verifiable (signature + id), but the CONTENT is unavailable. Bytes are LOCATED, not"
echo "  stored, and kept per a retention policy - a named obligation, not a trust problem."

echo
# the viewer shows the result foton and the located-at claims (both the good and the forged locator):
# the graph shows CLAIMED locations - verification happens at fetch, on arrival, not in the picture.
snapshot 14-fetch "$PWD/.work/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
