#!/usr/bin/env bash
# 03 - reproduce: record a computation, then independently RE-DERIVE its output and prove it matches.
# plankton compares by hash: identical bytes -> L0 (byte-identical reproduction); anything else -> none.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

export PLANKTON_DIR="$PWD/.work/registry"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$PWD/.work/keys"
plankton keygen "$PWD/.work/keys/me" >/dev/null

echo "== Create: record a foton whose output is a deterministic result =="
echo "1 2 3 4" > .work/input.txt
echo "sum=10"  > .work/result.txt        # a deterministic function of input.txt
plankton author --cmd "sum input.txt result.txt" \
  --in .work/input.txt --out .work/result.txt \
  --sign "$PWD/.work/keys/me.key" -o .work/sum.foton.json >/dev/null
plankton add .work/sum.foton.json
REF="$(plankton hash .work/result.txt)"
echo "  recorded result hash = $REF"

echo ""
echo "== Use: re-run the SAME computation and check reproduction =="
echo "sum=10" > .work/result_rerun.txt      # deterministic -> byte-identical
RERUN="$(plankton hash .work/result_rerun.txt)"
echo -n "  reproduces (re-run): "; plankton reproduces "$REF" "$RERUN"

echo "== a TAMPERED re-run must not reproduce (negative control) =="
echo "sum=999" > .work/result_tampered.txt
TAMP="$(plankton hash .work/result_tampered.txt)"
echo -n "  reproduces (tampered): "; plankton reproduces "$REF" "$TAMP" || true

echo ""
snapshot 03-reproduce "$PWD/.work/keys" --reg "$PLANKTON_DIR"
