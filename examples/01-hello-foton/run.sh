#!/usr/bin/env bash
# 01 - hello foton: the smallest possible create + use. Record one computation, then query it.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

# ---- ENVIRONMENT ------------------------------------------------------------
# A plankton "environment" is nothing but a DIRECTORY that holds a registry. You point plankton at
# it with the PLANKTON_DIR variable. A different directory is a different, independent registry.
# Here we use a throwaway .work/ dir (gitignored) so the example is repeatable.
export PLANKTON_DIR="$PWD/.work/registry"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$PWD/.work/keys"

echo "== Create =="
# 1) an identity. keygen writes me.key (PRIVATE - keep it) and me.pub (PUBLIC - share it).
plankton keygen "$PWD/.work/keys/me" >/dev/null

# 2) the files the computation consumes/produces. plankton stores NO bytes, only their content
#    hashes, so the files can live anywhere; we just need them to hash.
echo "3 7 2 8" > .work/data.txt
echo "mean=5"  > .work/result.txt

# 3) record the computation as a FOTON: inputs -> protocol(a command string) -> outputs. The signed
#    envelope is named <name>.foton.json by convention.
plankton author --cmd "mean data.txt result.txt" \
  --in .work/data.txt --out .work/result.txt \
  --sign "$PWD/.work/keys/me.key" -o .work/mean.foton.json >/dev/null
plankton add .work/mean.foton.json

echo ""
echo "== Use =="
echo "-- show the foton (inputs, outputs, protocol) --"
plankton show .work/mean.foton.json
echo "-- verify the signature against the public key --"
plankton verify .work/mean.foton.json "$PWD/.work/keys/me.pub"
echo "-- query by OUTPUT hash: who produced result.txt? --"
#    NOTE: hashes are written 'sha256:<hex>'. 'plankton hash' prints that form; pass it as-is.
plankton producer "$(plankton hash .work/result.txt)"

echo ""
snapshot 01-hello-foton "$PWD/.work/keys" --reg "$PLANKTON_DIR"
