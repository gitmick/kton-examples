#!/usr/bin/env python3
# Turn one or more example registries into the three files the graph viewer reads:
#   union.json  - every foton/claim record (deduped by id)
#   keys.json   - keyid -> public-key hex (drives the "verified" ring)
#   names.json  - keyid -> a human label (drives colour / grouping)
# Usage: build_union.py --out <dir> --keydir <dir> --reg <registry-dir> [--reg ...]
# keyid = first 16 hex of sha256(raw 32-byte public key), the same rule the kernels use.
import argparse, glob, hashlib, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--keydir", required=True)
ap.add_argument("--reg", action="append", default=[])
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

def keyid(pubhex):
    return hashlib.sha256(bytes.fromhex(pubhex)).hexdigest()[:16]

keys, names = {}, {}
for pub in glob.glob(os.path.join(a.keydir, "*.pub")):
    hx = open(pub).read().strip()
    if len(hx) == 64:
        kid = keyid(hx)
        keys[kid] = hx
        names.setdefault(kid, os.path.splitext(os.path.basename(pub))[0])

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

json.dump(union, open(os.path.join(a.out, "union.json"), "w"))
json.dump(keys, open(os.path.join(a.out, "keys.json"), "w"))
json.dump(names, open(os.path.join(a.out, "names.json"), "w"))
nf = sum(1 for r in union if "fotonId" in r)
print(f"  viewer data: {len(union)} records ({nf} fotons, {len(union)-nf} claims), {len(keys)} identities -> {a.out}")
