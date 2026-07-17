#!/usr/bin/env bash
# 05 - a review is its own (sub)nekton. A nekton is a CONTEXT ("a talk"): the claims of one conversation,
# kept together. A review is such a context - and here it is LITERALLY its own registry, so you can hand
# it over WHOLE to someone to verify, and it stands on its own as a valid seedchain. You OPEN it by
# seeding it FROM a public scope (--parent), HOLD it as a chain (each claim covers the previous, so one
# head seals it), CLOSE it by writing a CLAIM BACK to that parent naming the review + its head, and a
# consumer VERIFIES it two ways: (1) the sub-nekton resolves to its head on its own; (2) the public
# parent's close pins that head+seed. "Close" is no new verb - an ordinary claim, same shape as a verdict
# (SPEC 7.4: parent->child registration + sealing are convention, checked by consumers).
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

rm -rf "$PWD/.work"; mkdir -p "$PWD/.work/keys"
PUB_DIR="$PWD/.work/public"; REV_DIR="$PWD/.work/review"; HANDED="$PWD/.work/handed"
nekton keygen "$PWD/.work/keys/board" >/dev/null   # authority over the public record
nekton keygen "$PWD/.work/keys/chair" >/dev/null   # runs the review
K(){ echo "$PWD/.work/keys/$1.key"; }
# a seed prints its parent hash BEFORE its own claim id, so the SCOPE id is the LAST hash in the output.
seedid(){ echo "$1" | grep -oE 'sha256:[0-9a-f]{64}' | tail -1; }

echo "== The public record: a standing PARENT scope, in its own store =="
PUB=$(seedid "$(NEKTON_DIR=$PUB_DIR nekton seed public-record --sign "$(K board)" --by 'CN=Board' --add)")
echo "  public scope = $PUB"

echo ""
echo "== Open the REVIEW as its OWN nekton (its own store), seeded FROM the public scope (--parent) =="
REV=$(seedid "$(NEKTON_DIR=$REV_DIR nekton seed drug-review --parent "$PUB" --sign "$(K chair)" --by 'CN=Chair' --add)")
echo "  review scope = $REV   (the --parent link rides in the signed seed; it cannot be stripped)"

echo ""
echo "== Hold the review: chain signed claims INSIDE the review's own store =="
mkrev(){ printf '{"subject":[{"uri":"%s"}],"predicate":"pav:reviewedBy","object":{"value":"%s"},"by":"CN=Chair","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}' "$1" "$2" "$REV" "$3" > .work/c.json
  NEKTON_DIR=$REV_DIR nekton claim .work/c.json "$(K chair)" --add | grep -oE 'sha256:[0-9a-f]{64}' | head -1; }
C1=$(mkrev urn:doc:protocol "protocol approved" "$REV")
C2=$(mkrev urn:doc:results  "results approved"  "$C1")
HEAD=$(NEKTON_DIR=$REV_DIR nekton head "$REV" | awk '/^head:/{print $2}')
echo "  chain: seed -> $C1 -> $C2   head = $HEAD"

echo ""
echo "== HAND IT OVER: the review store is self-contained. Copy it to a recipient who verifies it ALONE =="
cp -r "$REV_DIR" "$HANDED"                              # in the wild: `nekton mirror`, or fetch by hash
echo "  the recipient, with only the review (no parent, no other attestations), checks the seedchain:"
NEKTON_DIR=$HANDED nekton head "$REV" | sed 's/^/    /'
echo "  -> resolves to the same head, 0 unresolved: a valid, COMPLETE seedchain on its own (leg 1)."

echo ""
echo "== CLOSE: a claim to the PARENT naming the review + its head (written into the public record) =="
# NOT a new verb: subject = the review scope, object = its sealed head, scoped into PUB. Swap the
# predicate for a verdict and it is a verdict. WHO may write it is trust policy (the board; a scope's
# `responsible` set names it). Whether the review was CONDUCTED honestly - every input captured, the
# signer saw what they signed - is a validated system's job, behind kton's boundary; kton documents it.
printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/closed","object":{"hash":"%s"},"by":"CN=Board","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}' "$REV" "$HEAD" "$PUB" "$PUB" > .work/close.json
NEKTON_DIR=$PUB_DIR nekton claim .work/close.json "$(K board)" --add >/dev/null
echo "  the board wrote 'drug-review closed at $HEAD' into the public record"

echo ""
echo "== The PARENT binds it: look up the review in the public record (leg 2) =="
NEKTON_DIR=$PUB_DIR nekton about "$REV" | sed 's/^/  /'
echo "  a consumer with the public parent confirms the close names THIS seed and THIS head - so the head"
echo "  the recipient resolved in leg 1 is the authoritative one (this defeats a rewind to a shorter chain)."
echo "  Over a public parent this same binding is a SPARQL check - the release gate in example 12."

echo ""
echo "== Tamper-evidence + 'you can still add, but it is over' =="
# a dangling prev never joins; and a valid claim added AFTER the closed head is simply outside the review.
printf '{"subject":[{"uri":"urn:doc:x"}],"predicate":"pav:reviewedBy","object":{"value":"forged"},"by":"CN=Chair","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' "$REV" > .work/bad.json
NEKTON_DIR=$REV_DIR nekton claim .work/bad.json "$(K chair)" --add >/dev/null 2>&1
echo -n "  head after a forged dangling link (UNCHANGED - never joined): "; NEKTON_DIR=$REV_DIR nekton head "$REV" | awk '/^head:/{print $2}'
C3=$(mkrev urn:doc:addendum "late addendum" "$HEAD")
echo -n "  the review's LIVE head moved to: "; NEKTON_DIR=$REV_DIR nekton head "$REV" | awk '/^head:/{print $2}'
echo "  but the public record still pins closed@$HEAD, so $C3 is a valid claim AFTER the close,"
echo "  outside the closed conversation. The handed-over review (leg 1) + the parent (leg 2) agree it is over."

echo ""
snapshot 05-review-scope "$PWD/.work/keys" --reg "$PUB_DIR" --reg "$REV_DIR"
