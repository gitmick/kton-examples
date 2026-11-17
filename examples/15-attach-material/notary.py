#!/usr/bin/env python3
# A NOTARY THAT IS NOT KTON. It imports no kton code - only the standard `cryptography` library - and
# it plays the part a Rekor entry, an RFC 3161 token or an eIDAS signature plays in the real world:
# an outside party that commits to a record and says "I saw this, at this point, and I vouch for it."
#
# It commits to the record's ENVELOPE PAYLOAD, which is what a Rekor entry commits to as well. That
# choice is the whole reason this example exists - see the trap in run.sh: a nekton claim id IS the
# sha256 of its payload, and a plankton foton id is NOT.
#
#   notary.py sign   <record.dsse.json> <seed-hex> <out.token.json>
#   notary.py verify <record.dsse.json> <token.json>
import sys, json, base64, hashlib, binascii
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

def payload_of(path):
    return base64.b64decode(json.load(open(path))["payload"])

mode = sys.argv[1]

if mode == "sign":
    record, seed_hex, out = sys.argv[2], sys.argv[3], sys.argv[4]
    priv = Ed25519PrivateKey.from_private_bytes(binascii.unhexlify(seed_hex))
    payload = payload_of(record)
    digest = hashlib.sha256(payload).hexdigest()
    token = {
        "notary": "example-notary/v0",          # a scheme kton does not name - carried, not blessed
        "payloadSha256": digest,                # what the notary committed to
        "signedAt": "2026-07-16T00:00:00Z",     # fixed, so this example stays reproducible
        "sig": base64.b64encode(priv.sign(bytes.fromhex(digest))).decode(),
        "pub": priv.public_key().public_bytes_raw().hex(),
    }
    json.dump(token, open(out, "w"), indent=1, sort_keys=True)
    print(f"  notarised {digest[:16]}… (the record's PAYLOAD hash, not its record id)")

elif mode == "verify":
    record, tokpath = sys.argv[2], sys.argv[3]
    tok = json.load(open(tokpath))
    payload = payload_of(record)
    digest = hashlib.sha256(payload).hexdigest()
    if digest != tok["payloadSha256"]:
        print(f"  REJECTED: the token commits to {tok['payloadSha256'][:16]}…, this record's payload is {digest[:16]}…")
        sys.exit(1)
    try:
        Ed25519PublicKey.from_public_bytes(binascii.unhexlify(tok["pub"])).verify(
            base64.b64decode(tok["sig"]), bytes.fromhex(digest))
    except InvalidSignature:
        print("  REJECTED: the notary's signature does not verify")
        sys.exit(1)
    print(f"  ACCEPTED: notary {tok['pub'][:16]}… vouches for this record's payload, signed at {tok['signedAt']}")
    sys.exit(0)
else:
    sys.exit("usage: notary.py sign|verify ...")
