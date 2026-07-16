#!/usr/bin/env python3
# Run the release gate (release.rq) over the merged submission RDF, BOUND to this submission so the
# conditions must be about it, not merely present in the graph. The regulator's entry point is the
# signed submission head; from the fit it DERIVES the environment (reads the fit's own protocol
# descriptor - not the sponsor's word). Prints a checklist and a verdict, then re-runs the gate bound
# to an unrelated hash to show it is submission-specific.
# Usage: release.py submission.ttl attestations.trig release.rq fit.dsse.json fitHash headHash
import sys, json, base64
import rdflib

ttl, trig, query_path, fit_env_path, fit_hash, head_hash = sys.argv[1:7]

# derive the environment the fit declares, from the fit envelope itself (COVERED in its descriptor)
# NOTE (soundness boundary): the env is read from the fit envelope's own descriptor. This gate does
# NOT itself re-verify that this envelope IS the attested fit; that is the regulator's obligation,
# done in Act 7 (verify the analyst signature and that its foton id == the bound fit_hash) before the
# gate is trusted. A gate handed a doctored envelope would bind whatever env it claims.
env = json.loads(base64.b64decode(json.load(open(fit_env_path))["payload"]))["predicate"]["protocol"]["descriptor"]["environment"]
PK = "https://kton.dev/o/"
def iri(h): return rdflib.URIRef(PK + h.replace("sha256:", ""))

ds = rdflib.Dataset(default_union=True)
ds.parse(ttl, format="turtle")
ds.parse(trig, format="trig")
query = open(query_path).read()

def satisfied(fit, head, envh):
    b = {"fit": iri(fit), "env": iri(envh), "head": iri(head)}
    return {str(r.condition) for r in ds.query(query, initBindings=b)}

REQUIRED = [
    ("tool-validated",          "toolchain validated (gxp:validation-performed = pass)"),
    ("env-qualified",           "the fit's environment is qualified (a signed qualifies-as binding)"),
    ("final-model",             "the fit ran the designated final model (pmx:model-role = final)"),
    ("reproduces",              "the fit's output reproduces (nk:reproduces at L0/L1)"),
    ("two-independent-reviews", "two distinct reviewers passed, no fail (gxp:reviewed)"),
    ("risk-accepted",           "residual risk explicitly accepted (gxp:risk-accepted)"),
    ("submission-signed",       "the submission head is signed by a verifiable identity (nk:submitted)"),
]

got = satisfied(fit_hash, head_hash, env)
print("  release checklist (SPARQL bound to this submission):")
for key, desc in REQUIRED:
    print(f"    [{'x' if key in got else ' '}] {desc}")
ok = all(key in got for key, _ in REQUIRED)
print(f"  RELEASE: {'COMPLETE - the submission may be accepted' if ok else 'BLOCKED - a condition is missing'}")

# the gate is submission-specific: bind it to an unrelated hash and it blocks
bogus = "0" * 64
n = len(satisfied(bogus, bogus, bogus))
print(f"  (same gate bound to an unrelated hash: {n}/7 conditions -> BLOCKED; conditions are not free-floating)")

# Exit non-zero if the gate did not return COMPLETE, so run.sh (and any CI) fails loudly on a
# regression instead of printing a stale narrative - the check the last review round was missing.
sys.exit(0 if ok else 1)
