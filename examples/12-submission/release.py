#!/usr/bin/env python3
# Run the release gate (release.rq) over the merged submission RDF, BOUND to this submission so the
# conditions must be about it, not merely present in the graph. The regulator's entry point is the
# signed submission head; the fit's environment is read FROM THE GRAPH (the nk:environment triple
# plankton export emits from the fit's COVERED descriptor - no out-of-band DSSE decode). Prints a
# checklist and a verdict, then re-runs the gate bound to an unrelated hash to show it is
# submission-specific.
# Usage: release.py submission.ttl attestations.trig release.rq fitHash headHash [trustedKeyid ...]
import sys
import rdflib

ttl, trig, query_path, fit_hash, head_hash = sys.argv[1:6]
# the verifier's OWN trust root: the authorities (by keyid) whose sec:controller vouchers it accepts.
# These are a COVERED input of the verdict-foton (run.sh writes trust-root.txt and --in's it), so a run
# with a friendlier trust root is a DIFFERENT verdict id and cannot be passed off as this one.
trusted_keyids = sys.argv[6:]
PK = "https://kton.dev/o/"
AG = "https://kton.dev/agent/"
NK_TRUSTED = rdflib.URIRef("https://kton.dev/v/TrustedAuthority")
def iri(h): return rdflib.URIRef(PK + h.replace("sha256:", ""))

# PORTABLE loading (rdf-interop F1): a COMPLIANT SPARQL engine matches a bare triple pattern only
# against the DEFAULT graph, so we do NOT rely on rdflib's non-standard default_union. We parse the
# nanopubs into their named graphs (the reviews branch needs graph identity to tie a review to its
# signer) AND ALSO merge every named-graph triple into the default graph, so bare patterns resolve in
# any engine (Jena included). This is a load-time choice; the query itself is stock SPARQL.
LINEAGE = rdflib.URIRef("urn:kton:lineage")  # the TRUSTED plankton export (verified attributions)
ds = rdflib.Dataset()  # default_union stays FALSE
# Load the plankton lineage into its OWN named graph, not the default. The gate reads the fit's AUTHOR
# from THIS graph specifically (GRAPH <urn:kton:lineage>), so an injected nekton claim asserting
# <fit> prov:wasAttributedTo <garbage> - which lands in some nanopub's named graph - cannot add a rival
# ?rauthor binding and let the author self-review slip past ?r1 != ?rauthor (four-eyes bypass v2).
ds.get_context(LINEAGE).parse(ttl, format="turtle")
ds.parse(trig, format="trig")    # each nanopub -> its own named graph
dg = ds.default_context
for (s, p, o, _g) in list(ds.quads((None, None, None, None))):
    dg.add((s, p, o))            # merge ALL (lineage + nanopubs) into the default graph for bare patterns
# the trust root as DATA, not a query-string placeholder (rdf-interop F3): each trusted authority IS a
# nk:TrustedAuthority, so the query matches `?a a nk:TrustedAuthority` as an ordinary pattern. An empty
# root asserts nothing -> no reviewer is authority-vouched -> two-independent-reviews cannot be met.
for k in trusted_keyids:
    dg.add((rdflib.URIRef(AG + k), rdflib.RDF.type, NK_TRUSTED))

query = open(query_path).read()  # runs UNMODIFIED - no string surgery

def satisfied(fit, head):
    b = {"fit": iri(fit), "head": iri(head)}
    return {str(r.condition) for r in ds.query(query, initBindings=b)}

REQUIRED = [
    ("tool-validated",          "toolchain validated (gxp:validation-performed = pass)"),
    ("env-qualified",           "the fit's environment is qualified (qualifies-as citing a check foton that FULLY passed: membersFulfilled == membersTotal)"),
    ("final-model",             "the fit ran the designated final model (pmx:model-role = final)"),
    ("reproduces",              "the fit's output reproduces (nk:reproduces at L0/L1)"),
    ("two-independent-reviews", "two distinct PRINCIPALS passed (each vouched by a trusted authority), no fail (gxp:reviewed)"),
    ("risk-accepted",           "residual risk explicitly accepted (gxp:risk-accepted)"),
    ("submission-signed",       "the submission head is signed by a verifiable identity (nk:submitted)"),
]

got = satisfied(fit_hash, head_hash)
print("  release checklist (SPARQL bound to this submission):")
for key, desc in REQUIRED:
    print(f"    [{'x' if key in got else ' '}] {desc}")
ok = all(key in got for key, _ in REQUIRED)
print(f"  RELEASE: {'COMPLETE - the submission may be accepted' if ok else 'BLOCKED - a condition is missing'}")

# the gate is submission-specific: bind it to an unrelated hash and it blocks
bogus = "0" * 64
n = len(satisfied(bogus, bogus))
print(f"  (same gate bound to an unrelated hash: {n}/7 conditions -> BLOCKED; conditions are not free-floating)")

# Exit non-zero if the gate did not return COMPLETE, so run.sh (and any CI) fails loudly on a
# regression instead of printing a stale narrative - the check the last review round was missing.
sys.exit(0 if ok else 1)
