#!/usr/bin/env python3
# A FOREIGN verifier: it imports no kton code - only the standard `cryptography` library. It verifies a
# kton foton exactly as any DSSE-aware tool would, because a kton record IS an in-toto Statement inside
# a DSSE envelope (the language of SLSA, sigstore, in-toto). Usage: verify_foreign.py <foton.dsse.json> <pubkey.hex|.pub>
import sys, json, base64, binascii
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

env = json.load(open(sys.argv[1]))                 # the DSSE envelope (a kton foton)
pub_hex = open(sys.argv[2]).read().strip()         # the signer's Ed25519 public key (hex)

payload = base64.b64decode(env["payload"])
pt = env["payloadType"].encode()
# DSSE Pre-Authentication Encoding, the standard: "DSSEv1 <len(pt)> <pt> <len(payload)> <payload>".
pae = b"DSSEv1 %d %b %d %b" % (len(pt), pt, len(payload), payload)

pub = Ed25519PublicKey.from_public_bytes(binascii.unhexlify(pub_hex))
ok = False
for s in env["signatures"]:
    try:
        pub.verify(base64.b64decode(s["sig"]), pae)
        ok = True
        break
    except InvalidSignature:
        pass

st = json.loads(payload)                            # the payload is a plain in-toto Statement
print(f"  payloadType  : {env['payloadType']}")
print(f"  in-toto _type: {st.get('_type')}")
print(f"  predicateType: {st.get('predicateType')}")
print(f"  subjects     : {[s.get('name') for s in st.get('subject', [])]}")
print(f"  DSSE / Ed25519 signature: {'VERIFIED' if ok else 'FAILED'}  (python-cryptography only, no kton code)")
sys.exit(0 if ok else 1)
