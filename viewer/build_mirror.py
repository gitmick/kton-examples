#!/usr/bin/env python3
"""build_mirror.py - turn a union.json into a STATIC, content-addressed mirror.

A mirror is just files-by-hash, so it serves off any CDN/S3/IPFS/Pages with no server
compute and scales to any number of records - a client fetches only the hashes it needs
and re-hashes every object it gets back (the mirror can withhold, but cannot forge):

  objects/sha256/<id>.json      the record itself (foton or claim), keyed by its content id
  output/sha256/<hash>.json     -> [foton ids that OUTPUT these bytes]   (producers; the lens's core lookup)
  input/sha256/<hash>.json      -> [foton ids that CONSUME it]           (downstream)
  about/sha256/<hash>.json      -> [claim ids ABOUT this subject]        (attestations)
  keys.json / names.json        copied for verification / labels

Usage: build_mirror.py <union.json> <out-dir>
"""
import json, os, sys, base64

union_path, out_dir = sys.argv[1], sys.argv[2]
recs = json.load(open(union_path))
strip = lambda h: (h or "").replace("sha256:", "").lower()

def write(sub, key, data):
    # shard by 2-hex prefix (like git's .git/objects/ab/…) so no directory holds millions of files.
    # On object storage (S3/R2/IPFS) keys are flat with no count limit, so this only helps filesystem/git hosts.
    d = os.path.join(out_dir, sub, "sha256", key[:2]); os.makedirs(d, exist_ok=True)
    json.dump(data, open(os.path.join(d, key + ".json"), "w"), separators=(",", ":"))

outmap, inmap, aboutmap = {}, {}, {}
for r in recs:
    rid = r.get("fotonId") or r.get("claimId")
    if not rid or not r.get("envelope"): continue
    write("objects", strip(rid), r)                                   # the record, by its content id
    try: p = json.loads(base64.b64decode(r["envelope"]["payload"]))
    except Exception: continue
    def dig(s): return strip(((s.get("digest") or {}).get("sha256")) or "")
    if r.get("fotonId"):                                              # a FOTON: subjects are OUTPUTS, predicate.inputs are consumed
        for s in p.get("subject", []) or []:
            h = dig(s);  outmap.setdefault(h, set()).add(rid) if h else None
        for s in ((p.get("predicate") or {}).get("inputs") or []):
            h = dig(s);  inmap.setdefault(h, set()).add(rid) if h else None
    else:                                                            # a CLAIM: subject is what it is ABOUT
        for s in p.get("subject", []) or []:
            h = dig(s);  aboutmap.setdefault(h, set()).add(rid) if h else None

for h, ids in outmap.items():   write("output", h, sorted(ids))
for h, ids in inmap.items():    write("input",  h, sorted(ids))
for h, ids in aboutmap.items(): write("about",  h, sorted(ids))

base = os.path.dirname(union_path)
for f in ("keys.json", "names.json"):
    src = os.path.join(base, f)
    if os.path.exists(src): json.dump(json.load(open(src)), open(os.path.join(out_dir, f), "w"), separators=(",", ":"))

print("mirror -> %s  (%d objects, %d output-hashes, %d input-hashes, %d about-subjects)"
      % (out_dir, len(recs), len(outmap), len(inmap), len(aboutmap)))
