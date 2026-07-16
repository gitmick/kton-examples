#!/usr/bin/env python3
# Turn one or more example registries into the three files the graph viewer reads:
#   union.json  - every foton/claim record (deduped by id)
#   keys.json   - keyid -> public-key hex (drives the "verified" ring)
#   names.json  - keyid -> a human label (drives colour / grouping)
# The label is ATTESTED where possible: if a signed sec:controller claim binds a key to a principal
# (the identity binding of example 07), that principal is the label - what was SIGNED, not a
# site-operator keyfile name. A key with no such binding falls back to its .pub filename, a site label
# (unattested). Usage: build_union.py --out <dir> --keydir <dir> --reg <registry-dir> [--reg ...]
import argparse, base64, glob, hashlib, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--keydir", required=True)
ap.add_argument("--reg", action="append", default=[])
a = ap.parse_args()
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

# 2. attested identity bindings from signed sec:controller claims (subject = a key's content IRI).
CONTROLLER = "https://w3id.org/security#controller"
bindings = {}  # key content IRI -> principal
for rec in union:
    try:
        p = json.loads(base64.b64decode(rec["envelope"]["payload"]))
    except Exception:
        continue
    body = p.get("predicate", {})
    if isinstance(body.get("predicate"), dict) and body["predicate"].get("uri") == CONTROLLER:
        obj = body.get("object", {}) or {}
        principal = obj.get("id") or obj.get("value")
        for s in p.get("subject", []):
            iri = s.get("uri", "")
            if iri and principal:
                bindings[iri] = principal

def short(principal):  # did:web:host/people/analyst -> analyst ; model:anthropic/claude-opus-4-8 -> claude-opus-4-8
    return principal.rstrip("/").split("/")[-1].split(":")[-1] or principal

# 3. keys + names: the label is the SIGNED principal where a binding exists, else the keyfile label.
keys, names = {}, {}
attested = 0
for pub in glob.glob(os.path.join(a.keydir, "*.pub")):
    hx = open(pub).read().strip()
    if len(hx) != 64:
        continue
    kid = keyid(hx)
    keys[kid] = hx
    iri = "https://kton.dev/o/" + hashlib.sha256(bytes.fromhex(hx)).hexdigest()
    if iri in bindings:
        names[kid] = short(bindings[iri])                                  # attested (signed sec:controller)
        attested += 1
    else:
        names.setdefault(kid, os.path.splitext(os.path.basename(pub))[0])  # site label (unattested)

json.dump(union, open(os.path.join(a.out, "union.json"), "w"))
json.dump(keys, open(os.path.join(a.out, "keys.json"), "w"))
json.dump(names, open(os.path.join(a.out, "names.json"), "w"))
nf = sum(1 for r in union if "fotonId" in r)
print(f"  viewer data: {len(union)} records ({nf} fotons, {len(union)-nf} claims), {len(keys)} identities ({attested} attested) -> {a.out}")
