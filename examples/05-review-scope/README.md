# 05 - a review is its own (sub)nekton, and completeness is mechanical

A single signed claim (example 04) says one thing. A **review** is a *conversation* - a nekton is a
**context ("a talk")**: the claims that belong to one conversation, kept together. Here the review is
**literally its own registry**, which buys two things:

1. **You can hand it over whole.** A recipient verifies it two ways: leg 1, the seedchain is **intact**
   on its own (resolves to its head, nothing dangling); leg 2, the public parent's **close** pins that
   head, so the head they hold is the authoritative one (this is what defeats a rewind to a shorter chain).
2. **Its completeness is *mechanical*, not "what you happened to load."** Right after the seed the review
   is **initialised** with its conditions - the enrolled reviewers - and those conditions are **anchored
   back** to the public parent. So the corpus is **defined**. A withheld reject stops being a silent pass
   and becomes a **liveness** failure: the missing reviewer makes the review *incomplete*, and incomplete
   **blocks**. You cannot cut a reject out to get a clean review - you get an incomplete one, fail-closed.

Nothing new in the kernel. SPEC §7.4 reserves parent→child registration and sealing as *consumer
convention* over the seed/chain grammar; "close", "initialised" and the completeness decision are all
ordinary claims plus a consumer check ([`check.py`](check.py)). "Close" is not a verb - it is a claim to
the parent, the same shape as a verdict; the predicate is the only thing that says "closed".

## Two words that are easy to conflate

- **intact** = leg 1: the seedchain resolves, 0 unresolved. That is **integrity**, and it is *not*
  "finished". A review can be intact and still missing a reviewer.
- **complete** = every *enrolled* reviewer delivered. That is a **different** check, done against the
  conditions the review carries. Seeing leg 1 green does **not** mean the review is complete.

## The lifecycle

1. **Public record + review as its own nekton.** Seed the public parent; seed the review `--parent` it,
   in its own store. The `--parent` link rides inside the signed seed, so it cannot be stripped.
2. **Initialise the conditions in the review** (the first chain link): the enrolled reviewers, signed by
   the authority - which, being the party that sets the rules, is also the one that may **close**.
3. **Anchor the conditions back to the parent** (an init record naming the review + its init head). Now
   the ruleset is double-locked: the chain seal makes it unrollbackable in the review, and the parent
   pins it - nobody can swap in a friendlier ruleset.
4. **Hold** the review: reviewers chain their deliveries.
5. **Close**: a claim on the parent naming the sealed head, **by that same authority**. A close by anyone
   else does not count - otherwise an attacker writes a close on a short head and "any close" is just a
   rewind with an extra step.
6. **The gate** (`check.py`) decides COMPLETE or BLOCKED: the chain is intact and reaches the seed, the
   conditions are on the sealed chain and anchored, the close is by the authority, **every enrolled
   reviewer delivered** (completeness), and **none rejected** (safety).
7. **The verdict is documented in plankton, with the nekton as input.** The decision is not an ephemeral
   print: it is authored as a plankton **foton** whose COVERED inputs are the review and the public
   parent (bundled by hash) plus `check.py`, and whose output is the verdict. So it is content-addressed
   and **reproducible** - re-run the check over the same nekton and you get the same verdict (L0). That is
   the plankton/nekton division: nekton is the signed review, plankton is the reproducible decision over
   it - example 12's "nekton in, verdict out".

## The exhibit - `bash run.sh` runs three scenarios

```
Scenario 1  both enrolled reviewers PASS   -> RELEASE: COMPLETE
Scenario 2  reviewer b REJECTS             -> RELEASE: BLOCKED (a reject blocks release)
Scenario 3  close WITHOUT b (strip it)     -> RELEASE: BLOCKED (enrolled reviewer did not deliver - INCOMPLETE)
```

Scenario 3 is the point: stripping the reject does not yield a clean review, it yields an **incomplete**
one, because `b` is enrolled in the review's own signed, anchored conditions. Safety (no reject) and
liveness (all enrolled delivered) both fail closed.

## The boundaries - what this does and does not settle

**Integrity, not currency.** The parent's close is tamper-evident but does not prove it is the *latest*;
a rewind verifies just as cleanly. Anchoring the close in a transparency log (`kton anchor`, example 08)
time-orders it; holding the latest anchored close is a consumer **freshness** step.

**Append-only, so "closed" is documented, not enforced.** Anyone can still sign a claim extending the
review; what closes it is the parent's record pinning the head. A claim added *after* that head is valid
but **outside** the closed review - "you can still add, but look it up, it is over."

**Conducting the review is behind kton's boundary.** *Who* is enrolled and *who* may close is trust
policy, carried in the review's own conditions. Whether every input was captured and whether a signer
*saw what they signed* is a validated system's job (a transactional trail + a validated UI). kton
**documents** the review and makes tampering, rewinds, missing reviewers and rejects *detectable*; it
does not *conduct* it.

**A dangling `prev` never joins the chain.** A claim with a `prev` that resolves nowhere is *persisted*
(it might resolve from another peer later - incomplete, not invalid) but never joins the scope, so it is
never the head. The open-substrate rule, not a sealed-scope fatality.

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/05-review-scope/union.json&keys=data/05-review-scope/keys.json&names=data/05-review-scope/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
