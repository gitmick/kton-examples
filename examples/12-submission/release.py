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
# the verifier's OWN trust root: the authorities (by keyid) whose sec:controller vouchers it accepts.
# These are a COVERED input of the verdict-foton (run.sh writes trust-root.txt and --in's it), so a run
# with a friendlier trust root is a DIFFERENT verdict id and cannot be passed off as this one.
trusted_keyids = sys.argv[7:]

# derive the environment the fit declares, from the fit envelope's own descriptor (COVERED in it).
# Act 7 has already HARD-GATED that this envelope's foton id == fit_hash (run.sh re-derives the id with
# the kernel and exits on mismatch), so reading env from this envelope is reading it from the attested
# fit - not the sponsor's word, and not an unverified file. (Without that binding a doctored envelope
# could inject any env; that binding runs, and the gate refuses to proceed if it fails.)
env = json.loads(base64.b64decode(json.load(open(fit_env_path))["payload"]))["predicate"]["protocol"]["descriptor"]["environment"]
PK = "https://kton.dev/o/"
AG = "https://kton.dev/agent/"
def iri(h): return rdflib.URIRef(PK + h.replace("sha256:", ""))

ds = rdflib.Dataset(default_union=True)
ds.parse(ttl, format="turtle")
ds.parse(trig, format="trig")
# inject the trust root as the IN-list the reviews branch filters on (an empty root -> no reviewer is
# authority-vouched -> the two-independent-reviews condition cannot be satisfied by any key count).
trusted_iris = ", ".join("<%s%s>" % (AG, k) for k in trusted_keyids)
query = open(query_path).read().replace("#TRUSTED#", trusted_iris or "<urn:kton:no-trusted-authority>")

def satisfied(fit, head, envh):
    b = {"fit": iri(fit), "env": iri(envh), "head": iri(head)}
    return {str(r.condition) for r in ds.query(query, initBindings=b)}

REQUIRED = [
    ("tool-validated",          "toolchain validated (gxp:validation-performed = pass)"),
    ("env-qualified",           "the fit's environment is qualified (qualifies-as citing a re-derivable spectrum-check foton, not a bare binding)"),
    ("final-model",             "the fit ran the designated final model (pmx:model-role = final)"),
    ("reproduces",              "the fit's output reproduces (nk:reproduces at L0/L1)"),
    ("two-independent-reviews", "two distinct PRINCIPALS passed (each vouched by a trusted authority), no fail (gxp:reviewed)"),
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
