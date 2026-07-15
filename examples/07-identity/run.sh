#!/usr/bin/env bash
# 07 - identity: a key IS an identity. Give a model its own signing key and you can trace exactly
# which claims came from which model. Then: who says a key belongs to a named model? A separate,
# single-signed claim - so a model attribution is verifiable, not just asserted.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh
export NEKTON_DIR="$PWD/.work/nekton"
rm -rf "$PWD/.work"; mkdir -p "$NEKTON_DIR" "$PWD/.work/keys"

echo "########## Part 1 - a key is an identity (self-asserted) ##########"
# Give two models their own signing keys. The keyid is the fingerprint of the public key: it IS the
# cryptographic identity. The human 'by' label, by contrast, is just text anyone could type.
OPUS=$(nekton keygen "$PWD/.work/keys/opus"     | grep -oE 'keyid=[0-9a-f]+' | cut -d= -f2)
SONNET=$(nekton keygen "$PWD/.work/keys/sonnet" | grep -oE 'keyid=[0-9a-f]+' | cut -d= -f2)
echo "  opus   keyid = $OPUS"
echo "  sonnet keyid = $SONNET"

# each model signs a claim about a result; --add files it directly.
mkclaim(){ # $1 keyfile  $2 by-label  $3 statement
  printf '{"subject":[{"uri":"urn:result:auc"}],"predicate":"nk:assessed","object":{"value":"%s"},"by":"%s","when":"2026-07-15T00:00:00Z"}' "$3" "$2" > .work/c.spec.json
  nekton claim .work/c.spec.json "$1" --add >/dev/null
}
mkclaim "$PWD/.work/keys/opus.key"   "claude-opus-4-8" "AUC is within the expected range"
mkclaim "$PWD/.work/keys/sonnet.key" "claude-sonnet-5" "AUC looks plausible"

echo "-- which claims came from the opus key? --"
nekton by signer "$OPUS"
echo "-- which from the sonnet key? --"
nekton by signer "$SONNET"
echo "  ^ every claim is traceable by keyid. 'by=claude-opus-4-8' is a self-asserted LABEL; the"
echo "    keyid is the cryptographic fact. That is the whole mechanism: give a model a key,"
echo "    trace which claims it made."

echo ""
echo "########## Part 2 - binding a key to a named model (attested) ##########"
# Who says keyid $OPUS really belongs to 'claude-opus-4-8'? An AUTHORITY signs an identity claim
# ABOUT the key. A consumer believes the attribution only if they trust that authority. Note this is
# just another single-signed claim (decision: one claim, one signer) - no new machinery.
nekton keygen "$PWD/.work/keys/deployer" >/dev/null
printf '{"subject":[{"uri":"urn:kton:key:%s"}],"predicate":"nk:actsAs","object":{"value":"model:anthropic/claude-opus-4-8"},"by":"CN=Deployment","when":"2026-07-15T00:00:00Z"}' "$OPUS" > .work/id.spec.json
nekton claim .work/id.spec.json "$PWD/.work/keys/deployer.key" --add >/dev/null
echo "-- what is asserted about the opus key? --"
nekton about "urn:kton:key:$OPUS"
echo "  ^ a separate, single-signed claim binds keyid -> model name, vouched by the deployer's key."
echo "    (the urn:kton:key: form is illustrative; the exact vocabulary is still being settled.)"

echo ""
# the viewer colours records by their signer, so each model's claims show in its own colour
snapshot 07-identity "$PWD/.work/keys" --reg "$NEKTON_DIR"
