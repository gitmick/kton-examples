#!/usr/bin/env python3
# Load the exported submission RDF (foton lineage Turtle + attestation nanopub TriG) into one dataset,
# run release.rq, and apply the release policy: the submission is releasable only if EVERY required
# condition is satisfied. The query does the graph work; this just checks the returned set is complete
# and prints a regulator-style checklist. Usage: release.py submission.ttl attestations.trig release.rq
import sys
import rdflib

ttl, trig, query_path = sys.argv[1:4]
ds = rdflib.Dataset(default_union=True)
ds.parse(ttl, format="turtle")
ds.parse(trig, format="trig")

satisfied = {str(row.condition) for row in ds.query(open(query_path).read())}

REQUIRED = [
    ("tool-validated",          "toolchain validated (gxp:validation-performed = pass)"),
    ("env-qualified",           "environment qualified (a signed qualifies-as binding)"),
    ("final-model",             "a final model is designated (pmx:model-role = final)"),
    ("reproduces",              "the fit reproduces (nk:reproduces at L0/L1)"),
    ("two-independent-reviews", "two independent reviewers passed, no fail (gxp:reviewed)"),
    ("risk-accepted",           "residual risk explicitly accepted (gxp:risk-accepted)"),
    ("submission-signed",       "submission signed by a verifiable identity (nk:submitted)"),
]

print("  release checklist (SPARQL over the merged graph):")
for key, desc in REQUIRED:
    print(f"    [{'x' if key in satisfied else ' '}] {desc}")
ok = all(key in satisfied for key, _ in REQUIRED)
print(f"  RELEASE: {'COMPLETE - the submission may be accepted' if ok else 'BLOCKED - a condition is missing'}")
