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

## Run it yourself

```
bash run.sh      # needs python3 + cryptography (pip install cryptography)
```
