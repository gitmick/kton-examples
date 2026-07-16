#!/usr/bin/env python3
# Load the exported RDF (foton lineage Turtle + review nanopub TriG) into one dataset and run the
# shipped SPARQL query completeness.rq, bound to the foton under review. Then apply the completeness
# policy: every required reviewer must appear under schema:AcceptAction and none under RejectAction.
# The query does the graph work (join each review's verdict to its provenance agent); this only reads
# off the tallies and prints a verdict. Usage: check_completeness.py lineage.ttl reviews.trig query.rq fotonHash required...
import sys
import rdflib

lineage, reviews, query_path, fhash, *required = sys.argv[1:]

ds = rdflib.Dataset(default_union=True)
ds.parse(lineage, format="turtle")
ds.parse(reviews, format="trig")

query = open(query_path).read()
foton = rdflib.URIRef("https://kton.dev/o/" + fhash)
ACCEPT = "https://schema.org/AcceptAction"
REJECT = "https://schema.org/RejectAction"

tally = {}
for row in ds.query(query, initBindings={"foton": foton}):
    tally[str(row.verdict)] = int(row.reviewers)

approvals = tally.get(ACCEPT, 0)
rejects = tally.get(REJECT, 0)
need = len(required)

print("  SPARQL tally (distinct reviewers per verdict):")
print(f"    approve (schema:AcceptAction): {approvals}")
print(f"    reject  (schema:RejectAction): {rejects}")
complete = approvals >= need and rejects == 0
print(f"  policy: all {need} required reviewers ({', '.join(required)}) approve, no rejects")
print(f"  REVIEW COMPLETE: {complete}  (approvals={approvals}/{need}, rejects={rejects})")
if not complete:
    print("  -> a missing approval or any reject would make this INCOMPLETE; the query is the gate.")
