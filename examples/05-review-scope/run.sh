#!/usr/bin/env bash
# 05 - review scope: a chain of signed claims sealed by one head. Because each claim id covers the
# previous one, publishing the head makes the whole chain tamper-evident - edit any earlier claim and
# the head no longer matches.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export NEKTON_DIR="$PWD/.work/nekton"
rm -rf "$PWD/.work"; mkdir -p "$NEKTON_DIR" "$PWD/.work/keys"
nekton keygen "$PWD/.work/keys/chair" >/dev/null

echo "== Create: open a review SCOPE (a seed) =="
SCOPE="$(nekton seed drug-review --sign "$PWD/.work/keys/chair.key" --by "CN=Chair" -o .work/seed.dsse.json | grep -oE 'sha256:[0-9a-f]+' | head -1)"
nekton add .work/seed.dsse.json >/dev/null
echo "  scope id = $SCOPE"

echo "== Create: chain two review claims under the scope =="
# first claim: prev = the scope id itself. Each subject here is a URI (any thing can be a subject).
mkclaim(){ # $1 subj  $2 verdict  $3 prev  $4 out
  printf '{"subject":[{"uri":"%s"}],"predicate":"pav:reviewedBy","object":{"value":"%s"},"by":"CN=Chair","when":"2026-07-15T00:00:00Z","scope":"%s","prev":"%s"}' "$1" "$2" "$SCOPE" "$3" > .work/c.spec.json
  nekton claim .work/c.spec.json "$PWD/.work/keys/chair.key" "$4" | grep -oE 'sha256:[0-9a-f]+' | head -1
}
C1="$(mkclaim urn:doc:protocol "protocol approved" "$SCOPE" .work/c1.dsse.json)"; nekton add .work/c1.dsse.json >/dev/null
C2="$(mkclaim urn:doc:results  "results approved"  "$C1"    .work/c2.dsse.json)"; nekton add .work/c2.dsse.json >/dev/null
echo "  link1 = $C1"
echo "  link2 = $C2"

echo ""
echo "== Use: seal the scope =="
nekton head "$SCOPE"
echo "-- a claim with a dangling prev is rejected (chain gap / tamper) --"
printf '{"subject":[{"uri":"urn:doc:x"}],"predicate":"pav:reviewedBy","object":{"value":"forged"},"by":"CN=Chair","when":"2026-07-15T00:00:00Z","scope":"%s","prev":"sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' "$SCOPE" > .work/bad.spec.json
nekton claim .work/bad.spec.json "$PWD/.work/keys/chair.key" .work/bad.dsse.json >/dev/null
echo -n "  add forged link: "; nekton add .work/bad.dsse.json 2>&1 | head -1 || true

echo ""
snapshot 05-review-scope "$PWD/.work/keys" --reg "$NEKTON_DIR"
