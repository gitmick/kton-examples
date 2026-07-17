#!/usr/bin/env python3
# Turn one or more example registries into the three files the graph viewer reads:
#   union.json  - every foton/claim record (deduped by id)
#   keys.json   - keyid -> public-key hex (drives the "verified" ring)
#   names.json  - keyid -> a human label (drives colour / grouping)
# The label is ATTESTED only when a signed sec:controller claim binds a key to a principal AND that
# claim was signed by an AUTHORITY the caller trusts (--authority <keyid>, repeatable). A binding is
# only worth the authority that signed it (example 07): a self-issued binding, or a ring of mutual
# attestations (K2 vouches K3, K3 vouches K2), is NOT signed by a trusted authority and therefore is
# NOT shown as attested - it falls back to the .pub site label. With no --authority given, nothing is
# attested (you trust no voucher). Usage:
#   build_union.py --out <dir> --keydir <dir> --reg <registry-dir> [--reg ...] [--authority <keyid> ...]
import argparse, base64, glob, hashlib, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--keydir", required=True)
ap.add_argument("--reg", action="append", default=[])
ap.add_argument("--authority", action="append", default=[])  # trusted authority keyids (16 hex)
a = ap.parse_args()
TRUSTED = set(a.authority)
os.makedirs(a.out, exist_ok=True)

def keyid(pubhex):
    return hashlib.sha256(bytes.fromhex(pubhex)).hexdigest()[:16]

# 1. the union of all records, deduped by content id.
seen, union = set(), []
for reg in a.reg:
    for f in sorted(glob.glob(os.path.join(reg, "objects", "sha256", "*.json"))):
        try:
            rec = json.load(open(f))
        except Exception:
            continue
        rid = rec.get("fotonId") or rec.get("claimId")
        if rid and rid not in seen:
            seen.add(rid)
            union.append(rec)

# 2. attested identity bindings: signed sec:controller claims (subject = a key's content IRI) whose
# OWN signer is a trusted authority. The signer keyid comes from the DSSE envelope, so a self-issued or
# ring-signed binding (signer not in TRUSTED) never becomes an attested label.
CONTROLLER = "https://w3id.org/security#controller"
bindings = {}  # key content IRI -> principal (only if vouched by a trusted authority)
for rec in union:
    try:
        p = json.loads(base64.b64decode(rec["envelope"]["payload"]))
        signer = rec["envelope"]["signatures"][0]["keyid"]
    except Exception:
        continue
    body = p.get("predicate", {})
    if isinstance(body.get("predicate"), dict) and body["predicate"].get("uri") == CONTROLLER:
        if signer not in TRUSTED:
            continue                       # a binding is only worth the authority that signed it
        obj = body.get("object", {}) or {}
        principal = obj.get("id") or obj.get("value")
        for s in p.get("subject", []):
            iri = s.get("uri", "")
            if iri and principal:
                bindings[iri] = principal

def short(principal):  # did:web:host/people/analyst -> analyst ; model:anthropic/claude-opus-4-8 -> claude-opus-4-8
    return principal.rstrip("/").split("/")[-1].split(":")[-1] or principal

# 3. keys + names: the label is the SIGNED principal where a binding exists, else the keyfile label.
# attested_kids records WHICH labels are authenticated (a trusted-authority sec:controller binding), so
# the viewer can distinguish an authenticated human identity from a mere .pub filename. Without this the
# viewer renders both identically next to the green "signature-verified" ring, and a screenshot of
# "senior person approved ✓" reads as authenticated when the corpus only proves SOME key signed it
# (cold-session screenshot-deception). The green ring is about the KEY; attestation is about the LABEL.
keys, names = {}, {}
attested_kids = []
for pub in glob.glob(os.path.join(a.keydir, "*.pub")):
    hx = open(pub).read().strip()
    if len(hx) != 64:
        continue
    kid = keyid(hx)
    keys[kid] = hx
    iri = "https://kton.dev/o/" + hashlib.sha256(bytes.fromhex(hx)).hexdigest()
    if iri in bindings:
        names[kid] = short(bindings[iri])                                  # attested (signed sec:controller)
        attested_kids.append(kid)
    else:
        names.setdefault(kid, os.path.splitext(os.path.basename(pub))[0])  # site label (unattested)
attested = len(attested_kids)

json.dump(union, open(os.path.join(a.out, "union.json"), "w"))
json.dump(keys, open(os.path.join(a.out, "keys.json"), "w"))
json.dump(names, open(os.path.join(a.out, "names.json"), "w"))
json.dump(sorted(attested_kids), open(os.path.join(a.out, "attested.json"), "w"))
nf = sum(1 for r in union if "fotonId" in r)
print(f"  viewer data: {len(union)} records ({nf} fotons, {len(union)-nf} claims), {len(keys)} identities ({attested} attested) -> {a.out}")
