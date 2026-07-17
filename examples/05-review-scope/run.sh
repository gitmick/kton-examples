#!/usr/bin/env bash
# 05 - a review is its own (sub)nekton, and its completeness is MECHANICAL. A nekton is a CONTEXT
# ("a talk"). A review is one you can hand over WHOLE: it is literally its own registry, so a recipient
# verifies it two ways - (1) the seedchain is INTACT on its own; (2) the public parent's close pins its
# head. Crucially the review carries its OWN completeness definition: right after the seed it is
# INITIALISED with its conditions (the enrolled reviewers), and those conditions are ANCHORED BACK to the
# public parent - so the corpus is DEFINED, not "what you happened to load". A withheld reject is then not
# a silent pass but a LIVENESS failure: the missing reviewer makes the review INCOMPLETE, and incomplete
# BLOCKS. Nothing new in the kernel (SPEC 7.4: parent->child registration + sealing are consumer
# convention); the gate is check.py, the consumer's own completeness decision.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

rm -rf "$PWD/.work"; mkdir -p "$PWD/.work/keys"
PUB_DIR="$PWD/.work/public"
nekton keygen "$PWD/.work/keys/board"       >/dev/null   # authority: sets the rules AND closes
nekton keygen "$PWD/.work/keys/reviewer-a"  >/dev/null
nekton keygen "$PWD/.work/keys/reviewer-b"  >/dev/null
K(){ echo "$PWD/.work/keys/$1.key"; }
kid16(){ python3 -c "import hashlib;print(hashlib.sha256(bytes.fromhex(open('$PWD/.work/keys/$1.pub').read().strip())).hexdigest()[:16])"; }
seedid(){ echo "$1" | grep -oE 'sha256:[0-9a-f]{64}' | tail -1; }
KA=$(kid16 reviewer-a); KB=$(kid16 reviewer-b)

echo "== The public record: a standing PARENT scope, in its own store =="
PUB=$(seedid "$(NEKTON_DIR=$PUB_DIR nekton seed drug-reviews --sign "$(K board)" --by 'CN=Board' --add)")
echo "  public scope = $PUB   (enrolled reviewers this run: a=$KA  b=$KB)"

# build_review <name> <revStore> <delivery...>   delivery = "a:pass" | "b:reject"  -> prints the scope id.
# The name must differ per review, else identical seeds (same parent+signer+second) collide to one scope id.
build_review(){
  local NAME="$1" RD="$2"; shift 2
  local REV; REV=$(seedid "$(NEKTON_DIR=$RD nekton seed "$NAME" --parent "$PUB" --sign "$(K board)" --by 'CN=Board' --add)")
  # INITIALISE (first link): the review's conditions - who is enrolled - signed by the board, which is
  # therefore the close authority. predicateBody carries the exact signed body (the reviewers array).
  printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"reviewers":["%s","%s"],"by":"CN=Board","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}}' "$REV" "$KA" "$KB" "$REV" "$REV" > .work/init.json
  local HINIT; HINIT=$(NEKTON_DIR=$RD nekton claim .work/init.json "$(K board)" --add | grep -oE 'sha256:[0-9a-f]{64}' | head -1)
  # ANCHOR the conditions back to the public parent (an init record naming the review + its init head)
  printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/review-initialised"},"object":{"hash":"%s"},"by":"CN=Board","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}}' "$REV" "$HINIT" "$PUB" "$PUB" > .work/anchor.json
  NEKTON_DIR=$PUB_DIR nekton claim .work/anchor.json "$(K board)" --add >/dev/null
  # DELIVERIES chained under the review
  local prev="$HINIT" d who verdict kf
  for d in "$@"; do who="${d%%:*}"; verdict="${d##*:}"; kf="reviewer-$who"
    printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/reviewed"},"object":{"value":"%s"},"by":"reviewer-%s","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}}' "$REV" "$verdict" "$who" "$REV" "$prev" > .work/rev.json
    prev=$(NEKTON_DIR=$RD nekton claim .work/rev.json "$(K $kf)" --add | grep -oE 'sha256:[0-9a-f]{64}' | head -1)
  done
  local HEAD; HEAD=$(NEKTON_DIR=$RD nekton head "$REV" | awk '/^head:/{print $2}')
  # CLOSE on the parent, signed by the board (the authority that initialised)
  printf '{"subject":[{"hash":"%s"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/closed"},"object":{"hash":"%s"},"by":"CN=Board","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"%s"}}' "$REV" "$HEAD" "$PUB" "$PUB" > .work/close.json
  NEKTON_DIR=$PUB_DIR nekton claim .work/close.json "$(K board)" --add >/dev/null
  echo "$REV"
}

echo ""
echo "########## Scenario 1: both enrolled reviewers PASS - the review is complete ##########"
R1=$(build_review review-happy "$PWD/.work/r1" a:pass b:pass)
echo "== Hand it over: the review store is self-contained; a recipient checks the seedchain INTACT (leg 1) =="
cp -r "$PWD/.work/r1" "$PWD/.work/handed"
NEKTON_DIR="$PWD/.work/handed" nekton head "$R1" | sed 's/^/    /'
echo "  -> resolves to its head, 0 unresolved: the seedchain is INTACT (integrity - not yet 'complete')."
echo "== The consumer's completeness gate (leg 2: conditions + close from the public parent) =="
python3 check.py "$PWD/.work/r1" "$PUB_DIR" "$R1" || true

echo ""
echo "########## Scenario 2: reviewer b REJECTS - a reject BLOCKS (it cannot be hidden) ##########"
R2=$(build_review review-reject "$PWD/.work/r2" a:pass b:reject)
python3 check.py "$PWD/.work/r2" "$PUB_DIR" "$R2" || true

echo ""
echo "########## Scenario 3: strip b's reject by closing WITHOUT it - now the review is INCOMPLETE ##########"
# The sponsor omits reviewer b entirely and closes on just a's pass. The reject is gone - but so is b's
# delivery, and b is ENROLLED (in the signed, anchored conditions). Missing enrolled reviewer -> INCOMPLETE
# -> BLOCKED. That is the whole point: you cannot cut the reject out to get a clean review; you get an
# incomplete one, and incomplete fails closed.
R3=$(build_review review-strip "$PWD/.work/r3" a:pass)
python3 check.py "$PWD/.work/r3" "$PUB_DIR" "$R3" || true

echo ""
echo "== Tamper-evidence still holds: a dangling prev never joins the chain =="
printf '{"subject":[{"uri":"urn:doc:x"}],"predicateBody":{"predicate":{"uri":"https://kton.dev/v/reviewed"},"object":{"value":"forged"},"by":"CN=Board","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}}' "$R1" > .work/bad.json
NEKTON_DIR="$PWD/.work/r1" nekton claim .work/bad.json "$(K board)" --add >/dev/null 2>&1
echo -n "  head of r1 after a forged dangling link (UNCHANGED): "; NEKTON_DIR="$PWD/.work/r1" nekton head "$R1" | awk '/^head:/{print $2}'

echo ""
snapshot 05-review-scope "$PWD/.work/keys" --reg "$PUB_DIR" --reg "$PWD/.work/r1"
