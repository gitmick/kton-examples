# 13 - foreign verify: a kton record read by a tool that is not kton

The whole series says a reader can verify records themselves, and that records are *copyable between
tools*. This example proves the second half concretely: a kton foton is verified by a tool that is **not
kton** and imports **no kton code**.

It can be, because a kton record is not a bespoke format - it is an **in-toto Statement inside a DSSE
envelope**, the language of SLSA, sigstore, and in-toto:

```json
{ "payloadType": "application/vnd.in-toto+json",
  "payload": "<base64 in-toto Statement>",
  "signatures": [{ "keyid": "...", "sig": "<base64 Ed25519 over the DSSE PAE>" }] }
```

So verifying it needs only the DSSE Pre-Authentication Encoding and an Ed25519 check - both standard.
[`verify_foreign.py`](verify_foreign.py) does exactly that with the widely used `cryptography` library
and nothing else:

```
== verified by a FOREIGN tool: python + cryptography only, NO kton import ==
  payloadType  : application/vnd.in-toto+json
  in-toto _type: https://in-toto.io/Statement/v1
  predicateType: https://kton.dev/foton/v0
  DSSE / Ed25519 signature: VERIFIED  (python-cryptography only, no kton code)
```

The run also tampers one byte of the payload and shows the foreign verifier **rejects** it - the
signature covers the exact bytes, so corruption is caught by whoever checks, not just by kton.

## Why this matters

"Verify it yourself" is only true if you are not forced to run *our* verifier. Because the record is a
standard in-toto attestation in a DSSE envelope, the SLSA / sigstore / in-toto toolchain reads it as-is,
and a twenty-line standard-crypto check confirms it - a kton record needs no kton tool to be verified,
only the signer's public key. (This is also the readability answer: the payload is one `base64 -d | jq`
from human-readable; no bespoke format to learn.)

## Verify with OpenSSL (no Python, no kton)

kton stores a public key as **raw 32-byte hex**; OpenSSL wants it as an Ed25519 **SPKI** key. That is a
fixed 12-byte DER prefix + the key - no tooling, just a prefix:

```
# 1. raw hex pubkey -> an Ed25519 PEM (the 302a3005...2100 prefix is the SPKI header for Ed25519)
printf -- "-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n" \
  "$(printf '302a300506032b6570032100%s' "$(cat analyst.pub)" | xxd -r -p | base64 -w0)" > analyst.pem

# 2. reconstruct the exact bytes DSSE signs (the PAE) and the raw signature, from the envelope
python3 - analyst  <<'PY'   # (the one binary step - PAE has length prefixes; any language does it)
import json,base64,sys
e=json.load(open("foton.dsse.json")); p=base64.b64decode(e["payload"]); t=e["payloadType"].encode()
open("pae.bin","wb").write(b"DSSEv1 %d %b %d %b"%(len(t),t,len(p),p))
open("sig.bin","wb").write(base64.b64decode(e["signatures"][0]["sig"]))
PY

# 3. verify - pure OpenSSL, no kton, no cryptography library
openssl pkeyutl -verify -pubin -inkey analyst.pem -rawin -in pae.bin -sigfile sig.bin
# -> Signature Verified Successfully   (tamper one byte of pae.bin and it fails)
```

That is the whole trust root: the signature covers the PAE, the PAE is the payload, and OpenSSL is a
tool no one associates with kton. Note kton's **keyid** (`sha256(pubkey)[:16]`) is only a display
fingerprint - it is *not* the Sigstore keyid convention; cross-tool identity is by the public key
itself. For the full **Sigstore/cosign keyless** path (a Fulcio cert + a Rekor transparency-log entry
instead of a bare key), see [example 08](../08-sigstore-github/) - that is where cosign belongs.

## Run it yourself

```
bash run.sh      # needs python3 + cryptography (pip install cryptography)
```
