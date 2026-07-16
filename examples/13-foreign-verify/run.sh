#!/usr/bin/env bash
# 13 - foreign verify: a kton record verified by a tool that is NOT kton. A foton is an in-toto
# Statement in a DSSE envelope - the language of SLSA, sigstore, and in-toto - so any DSSE-aware tool
# can read and verify it. Here a standalone verifier using only the standard `cryptography` library
# (zero kton code) checks a foton's signature and reads its in-toto Statement. The concrete proof that
# records are copyable between tools, not locked to kton.
set -euo pipefail
EXDIR="$(cd "$(dirname "$0")" && pwd)"; cd "$EXDIR"; source ../../lib/common.sh
python3 -c "import cryptography" 2>/dev/null || { echo "this example needs python3 + cryptography (pip install cryptography)"; exit 1; }
W=".work"; rm -rf "$W"; mkdir -p "$W"; export PLANKTON_DIR="$W/reg"

echo "== a kton foton, authored and signed by kton =="
printf "id,dv\n1,4.2\n" > "$W/data.csv"; echo "cl=4.2" > "$W/fit.out"
plankton keygen "$W/analyst" >/dev/null
plankton author --cmd "fit data.csv" --in "$W/data.csv" --out "$W/fit.out" \
  --sign "$W/analyst.key" -o "$W/foton.dsse.json" --add >/dev/null
echo "  foton.dsse.json  (a DSSE envelope: payloadType application/vnd.in-toto+json)"

echo; echo "== verified by a FOREIGN tool: python + cryptography only, NO kton import =="
python3 "$EXDIR/verify_foreign.py" "$W/foton.dsse.json" "$W/analyst.pub"

echo; echo "== negative control: tamper one byte of the payload, the foreign verifier rejects =="
python3 - "$W/foton.dsse.json" "$W/tampered.dsse.json" <<'PY'
import sys, json, base64
d = json.load(open(sys.argv[1]))
p = bytearray(base64.b64decode(d["payload"])); p[10] ^= 1          # flip a bit
d["payload"] = base64.b64encode(bytes(p)).decode()
json.dump(d, open(sys.argv[2], "w"))
PY
python3 "$EXDIR/verify_foreign.py" "$W/tampered.dsse.json" "$W/analyst.pub" || echo "  (rejected, as it must be)"

echo; echo "The same in-toto+DSSE shape is what cosign, in-toto, and the SLSA toolchain read - a kton"
echo "record needs no kton tool to be verified, only the signer's public key."
