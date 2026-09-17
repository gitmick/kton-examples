#!/usr/bin/env python3
# The consumer's completeness gate for a review sub-nekton. This is what makes "is the review complete"
# MECHANICAL rather than corpus-relative: the review defines its own corpus. Given only the review store
# (leg 1) and the public parent (leg 2), it decides COMPLETE or BLOCKED - and a withheld reject becomes a
# LIVENESS failure (the enrolled reviewer is missing -> incomplete -> BLOCKED), never a silent pass.
#
# Rules, all anchored so they cannot be rolled back:
#   - the review is INITIALISED by a first-link claim carrying its conditions (enrolled reviewer keyids);
#     the signer of that claim is the CLOSE AUTHORITY (the party that set the rules is the one that closes).
#   - those conditions are ANCHORED BACK to the public parent (an init record naming the review + the
#     init head), so a second, friendlier ruleset cannot be swapped in.
#   - the review is CLOSED by a claim on the parent naming the sealed head, signed by that SAME authority.
#     A close by anyone else does not count (condition B: not "any" close, the authorised one).
# Then: every enrolled reviewer must have a delivery in the sealed chain (completeness), and none may be a
# reject (safety). Miss either and the gate BLOCKS.
#
# EXIT CODES - a verdict and a non-run are NOT the same thing:
#   0  COMPLETE   - the gate ran and passed
#   1  BLOCKED    - the gate ran and refused
#   2  GATE ERROR - the gate could not run (it read nothing, so it has no opinion to give)
# 2 exists because of the failure this gate actually had: it read zero claims, printed BLOCKED, and the
# example passed anyway behind a `|| true`. An empty read looked exactly like a considered refusal. It
# must not: an empty store, or one written in a layout this reader does not know (briefing B1), is a
# broken gate, not a blocked release.
import json, base64, glob, os, sys

REV_DIR, PUB_DIR, REV = sys.argv[1:4]
INIT = "https://kton.dev/v/review-initialised"
CLOSED = "https://kton.dev/v/closed"
REVIEWED = "https://kton.dev/v/reviewed"

def store_records(reg):
    """Every record in a registry, as parsed dicts.

    A registry files a scope's claims as ONE FILE PER (SUB)NEKTON -
    objects/scope/<scope_id>.nekton.jsonl and objects/unscoped.nekton.jsonl, one record per line -
    and older stores kept one file per claim at objects/<algo>/<hash>.json. Read both, so a
    non-recursive glob can never silently show you half a store.
    """
    out = []
    for f in sorted(glob.glob(os.path.join(reg, "objects", "**", "*.nekton.jsonl"), recursive=True)):
        with open(f) as fh:
            for line in fh:
                line = line.strip()
                if line:
                    try:
                        out.append(json.loads(line))
                    except Exception:
                        continue
    for f in sorted(glob.glob(os.path.join(reg, "objects", "**", "*.json"), recursive=True)):
        try:
            out.append(json.load(open(f)))
        except Exception:
            continue
    return out

def load(d):
    recs = {}
    for r in store_records(d):
        cid = r.get("claimId") or r.get("fotonId")
        if not cid or "envelope" not in r:
            continue
        st = json.loads(base64.b64decode(r["envelope"]["payload"]))
        sigs = r["envelope"].get("signatures") or [{}]
        recs[cid] = {"body": st.get("predicate", {}), "kid": sigs[0].get("keyid", ""), "subj": st.get("subject", [])}
    return recs

def fail(msg):
    print(f"  RELEASE: BLOCKED - {msg}")
    sys.exit(1)

def gate_error(msg):
    """The gate could not run. Distinct from BLOCKED, and distinct from PASS."""
    print(f"  GATE ERROR - {msg}")
    print("  (this is NOT a verdict: the gate read nothing, so it has nothing to say about the review)")
    sys.exit(2)

def subj_has(r, val):
    v = val.replace("sha256:", "")
    for s in r["subj"]:
        if s.get("hash", "").replace("sha256:", "") == v:
            return True
        if s.get("digest", {}).get("sha256", "") == v:   # in-toto subjects store the digest form
            return True
        if s.get("uri") == val:
            return True
    return False

rev, pub = load(REV_DIR), load(PUB_DIR)

# 0. COVERAGE, before any verdict: prove there was something to judge. Every rule below is of the form
# "no record satisfies X -> BLOCKED", so on an empty read all of them fire and the gate refuses for the
# wrong reason - it would look like a decision when it is a broken read. State what was actually read.
print(f"  gate read {len(rev)} record(s) from the review and {len(pub)} from the public parent")
if not rev:
    gate_error(f"read 0 records from the review store {REV_DIR}")
if not pub:
    gate_error(f"read 0 records from the public parent store {PUB_DIR}")

# 1. the initialise claim (in the review): its conditions + its signer = the close authority
init = [(cid, r) for cid, r in rev.items() if r["body"].get("predicate", {}).get("uri") == INIT]
if len(init) != 1:
    fail(f"the review must be initialised exactly once with its conditions (found {len(init)})")
h_init, ir = init[0]
enrolled = set(ir["body"].get("reviewers", []))
authority = ir["kid"]
if not enrolled:
    fail("the review enrols no reviewers - it has no completeness definition")

# 2. the conditions are anchored back to the public parent, by the same authority, at this init head
anchored = any(r["body"].get("predicate", {}).get("uri") == INIT
               and r["body"].get("object", {}).get("hash") == h_init
               and subj_has(r, REV) and r["kid"] == authority
               for r in pub.values())
# 3. the review is CLOSED on the parent by that same authority; take that head (a close by anyone else
#    does not count). The closed head is the object hash of the authorised close claim.
closes = [r for r in pub.values() if r["body"].get("predicate", {}).get("uri") == CLOSED
          and subj_has(r, REV) and r["kid"] == authority]
if not closes:
    fail("no close by the review's own authority (an unauthorised close does not count)")
h_final = closes[0]["body"].get("object", {}).get("hash", "")

# 4. walk the sealed chain from the closed head back to the seed; the conditions must be on it
sealed, cur = set(), h_final
while cur and cur in rev:
    sealed.add(cur)
    cur = rev[cur]["body"].get("prev", "")
if REV not in sealed:
    fail("the closed head does not chain back to the review seed (a broken or foreign chain)")
if h_init not in sealed:
    fail("the initialised conditions are not on the sealed chain (they were rolled back)")
if not anchored:
    fail("the conditions were never anchored back to the public parent (rollback-able)")

# 5. every enrolled reviewer delivered in the sealed chain (COMPLETENESS), and none is a reject (SAFETY)
delivered, rejected = set(), []
for cid in sealed:
    r = rev[cid]
    if r["body"].get("predicate", {}).get("uri") == REVIEWED:
        verdict = str(r["body"].get("object", {}).get("value", ""))
        if verdict == "reject":
            rejected.append(r["kid"])
        else:
            delivered.add(r["kid"])
if rejected:
    fail(f"a reviewer REJECTED (keyid {rejected[0][:8]}...) - a reject blocks release")
missing = enrolled - delivered
if missing:
    fail(f"enrolled reviewer(s) did not deliver: {sorted(m[:8]+'...' for m in missing)} - INCOMPLETE")

print(f"  RELEASE: COMPLETE - {len(enrolled)} enrolled reviewers all delivered a pass, sealed at {h_final[:19]}..., closed by its own authority")
sys.exit(0)
