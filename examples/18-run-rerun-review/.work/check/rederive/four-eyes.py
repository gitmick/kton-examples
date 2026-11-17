#!/usr/bin/env python3
"""Run four-eyes.rq for one foton and decide.
Rule: at least two distinct approvers, each declared a person by the review's owner, none of whom
signed the foton, and no reject. An approval by a software agent (an LLM session) is not counted.
Usage: four-eyes.py <lineage.ttl> <review.trig> <four-eyes.rq> <fotonId> <ownerKeyid> <out.txt>"""
import sys, rdflib
lineage, review, rq, foton, owner, out = sys.argv[1:7]
ds = rdflib.Dataset(default_union=True)
ds.parse(lineage, format="turtle"); ds.parse(review, format="trig")
names = {str(s).rsplit("/", 1)[-1]: str(o) for s, o in ds.subject_objects(rdflib.RDFS.label) if "/agent/" in str(s)}
rows = ds.query(open(rq).read(), initBindings={
    "foton": rdflib.URIRef("https://kton.dev/o/" + foton.replace("sha256:", "")),
    "owner": rdflib.URIRef("https://kton.dev/agent/" + owner)})
seen = sorted({(str(r.who).rsplit("/", 1)[-1], str(r.verdict), r.isAuthor.toPython(), r.isPerson.toPython(), r.isAgent.toPython()) for r in rows})
def why(a, p, g):
    return "software agent" if g else "signed the foton" if a else "not declared a person" if not p else ""
counted = {w for w, v, a, p, g in seen if v == "approve" and not why(a, p, g)}
rejects = {w for w, v, a, p, g in seen if v == "reject"}
ok = len(counted) >= 2 and not rejects
lines = [f"foton {foton}"]
lines += [f"  {names.get(w, w):8} {v:8} {'counted' if w in counted else 'not counted: ' + why(a, p, g)}" for w, v, a, p, g in seen]
lines += [f"approvals by people: {len(counted)}", f"rejects: {len(rejects)}", f"four eyes, people only: {'yes' if ok else 'no'}"]
open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
