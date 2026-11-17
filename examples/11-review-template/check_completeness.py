#!/usr/bin/env python3
# Load the exported RDF (foton lineage Turtle + review nanopub TriG) into one dataset and run the
# shipped SPARQL query completeness.rq, bound to the foton under review. Then apply the completeness
# policy: every required reviewer must appear under schema:AcceptAction and none under RejectAction.
# The query does the graph work (join each review's verdict to its provenance agent); this only reads
# off the tallies and prints a verdict. Usage: check_completeness.py lineage.ttl reviews.trig query.rq fotonHash required...
#
# EXIT CODES - a verdict and a non-run are NOT the same thing:
#   0  COMPLETE   - the policy is satisfied
#   1  INCOMPLETE - the policy is not satisfied (a real refusal)
#   2  GATE ERROR - the gate could not run: the RDF it was handed contains no reviews at all
# Before this had exit codes it had NONE: it printed "REVIEW COMPLETE: False" and fell off the end with
# status 0, so the example passed either way. That is how this example once passed on a 21-byte
# reviews.trig - zero reviews parse to zero approvals, which reads as "incomplete", which reported
# success. An empty graph is a broken export, not a failed review.
import sys
import rdflib

lineage, reviews, query_path, fhash, *required = sys.argv[1:]

def gate_error(msg):
    print(f"  GATE ERROR - {msg}")
    print("  (this is NOT a verdict: nothing was read, so there is no review to be complete or not)")
    sys.exit(2)

ds = rdflib.Dataset(default_union=True)
ds.parse(lineage, format="turtle")
ds.parse(reviews, format="trig")

# COVERAGE, before any verdict. Both inputs must actually carry something: the policy below is
# "enough approvals and no rejects", and on an empty graph that reads as a considered INCOMPLETE
# rather than as the export failure it really is.
n_lineage = len(rdflib.Graph().parse(lineage, format="turtle"))
n_reviews = len(rdflib.Dataset().parse(reviews, format="trig"))
print(f"  parsed {n_lineage} lineage triple(s) + {n_reviews} review triple(s) from the export")
if not n_lineage:
    gate_error(f"{lineage} parsed to 0 triples - the plankton RDF export produced nothing")
if not n_reviews:
    gate_error(f"{reviews} parsed to 0 triples - the nanopub export produced nothing")

query = open(query_path).read()
foton = rdflib.URIRef("https://kton.dev/o/" + fhash)
ACCEPT = "https://schema.org/AcceptAction"
REJECT = "https://schema.org/RejectAction"

# tally[(verdict, verified)] = distinct reviewer count
tally = {}
for row in ds.query(query, initBindings={"foton": foton}):
    tally[(str(row.verdict), bool(row.verified.toPython()))] = int(row.reviewers)

approvals_verified = tally.get((ACCEPT, True), 0)
approvals_claimed = tally.get((ACCEPT, False), 0)
rejects_verified = tally.get((REJECT, True), 0)
rejects_claimed = tally.get((REJECT, False), 0)
rejects_total = rejects_verified + rejects_claimed
need = len(required)

print("  SPARQL tally (distinct reviewers per verdict):")
print(f"    approve: {approvals_verified} verified, {approvals_claimed} unverified")
print(f"    reject : {rejects_verified} verified, {rejects_claimed} unverified")
# Completeness: enough VERIFIED approvals (an unverified approval is not trusted) AND NO reject on record
# - verified OR claimed. A reject whose signer is not in the export trust-keys must still BLOCK, never be
# silently dropped (completeness-gate F1): a real reviewer's key may just be absent from this export's
# trust set, and an on-record "no" is a strong signal to surface, not swallow.
complete = approvals_verified >= need and rejects_total == 0
print(f"  policy: >= {need} required reviewers ({', '.join(required)}) approve VERIFIED, and NO reject (verified or claimed)")
print(f"  REVIEW COMPLETE: {complete}  (verified approvals={approvals_verified}/{need}, rejects={rejects_total})")

# A tally of all zeros is not "no approvals yet", it is a query that matched nothing - the reviews
# parsed but the join to their provenance agents found no verdict at all. Say so as an error.
if approvals_verified + approvals_claimed + rejects_total == 0:
    gate_error(f"{reviews} parsed, but the query matched no verdict for foton {fhash[:16]}... "
               "(the reviews and the foton did not join)")

if not complete:
    if rejects_total:
        print(f"  -> BLOCKED by {rejects_total} reject(s) on record ({rejects_claimed} from an UNVERIFIED signer - NOT dropped).")
    else:
        print("  -> a missing verified approval makes this INCOMPLETE; the query is the gate.")
    sys.exit(1)
sys.exit(0)
