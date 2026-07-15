#!/usr/bin/env bash
# 08 - sign a kton record with your GitHub identity (Sigstore keyless). This is tier 3 from example 07
# (authority-backed identity), made real. Unlike 01-07 it is NOT fully headless: keyless signing needs
# an interactive GitHub login, so exactly ONE step is run by you. The script is re-entrant: run it, do
# the sign step it prints, then run it again to verify.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh
COSIGN="${COSIGN:-$HOME/.local/bin/cosign}"
W="$PWD/.work"; mkdir -p "$W"

# --- Part 1 (automatic): make a kton record to sign ---
if [ ! -f "$W/foton.dsse.json" ]; then
  export PLANKTON_DIR="$W/plankton"
  echo "id,auc,verdict"        > "$W/result.csv"
  echo "1,42.0,within-range"  >> "$W/result.csv"
  [ -f "$W/author.key" ] || plankton keygen "$W/author" >/dev/null 2>&1
  plankton author --cmd "assess result.csv" --in "$W/result.csv" --out "$W/result.csv" \
    --sign "$W/author.key" --add -o "$W/foton.dsse.json" >/dev/null
fi
REC="$W/foton.dsse.json"
echo "kton record to sign: foton.dsse.json"
echo "  content hash: $(plankton hash "$REC")"

# --- Part 2 (YOU run this once): sign it with your GitHub identity ---
if [ ! -f "$W/sig.bundle" ]; then
  cat <<EOF

==> NOW SIGN IT WITH YOUR GITHUB IDENTITY. Run this yourself and choose GitHub at the login prompt:

    $COSIGN sign-blob --yes --new-bundle-format --bundle "$W/sig.bundle" "$REC"

  Keyless: an OIDC login binds *your GitHub identity* to a short-lived Fulcio certificate over an
  ephemeral key; the signature + cert go into the public Rekor transparency log. No long-lived key.
  Then re-run this script (bash run.sh) to verify.
EOF
  exit 0
fi

# --- Part 3 (automatic): verify + read who signed ---
echo ""
echo "== verify: valid signature, GitHub identity, Rekor inclusion =="
"$COSIGN" verify-blob --new-bundle-format --bundle "$W/sig.bundle" \
  --certificate-identity-regexp '.+' --certificate-oidc-issuer-regexp '.+' "$REC" 2>&1 | sed 's/^/  /'
echo ""
echo "== who signed it (read the identity from the Fulcio cert in the bundle) =="
python3 - "$W/sig.bundle" > "$W/cert.der" <<'PY'
import sys, json, base64
b = json.load(open(sys.argv[1]))
raw = (b.get("verificationMaterial", {}).get("certificate", {}) or {}).get("rawBytes")
if not raw:
    chain = b.get("verificationMaterial", {}).get("x509CertificateChain", {}).get("certificates", [])
    raw = chain[0]["rawBytes"] if chain else None
sys.stdout.buffer.write(base64.b64decode(raw)) if raw else sys.exit("no cert in bundle")
PY
echo "  identity (SAN): $(openssl x509 -inform DER -in "$W/cert.der" -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//')"
echo "  the OIDC issuer + identity above are what a verifier PINS (never accept '.+' in production)."
echo ""
echo "This ties a GitHub person to the kton record's content hash, verifiable via Fulcio + Rekor,"
echo "with no long-lived key and no trust in us. That is the authority-backed tier of example 07."
