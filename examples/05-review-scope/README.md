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

Nothing new in the kernel. SPEC §7.4 — the kton protocol spec, which lives in the kernel repo at
[`kton-protocol/kton`](https://github.com/kton-protocol/kton) rather than here — reserves parent→child
registration and sealing as *consumer convention* over the seed/chain grammar; "close", "initialised" and the completeness decision are all
ordinary claims plus a consumer check ([`check.py`](check.py)). "Close" is not a verb - it is a claim to
the parent, the same shape as a verdict; the predicate is the only thing that says "closed".

## Words this example needs

Four of them are new here, and one is an old friend under a new name:

- a **seed** is the first record of a scope: a self-signed claim with no `prev`, which every later
  claim in that scope chains back to. Its own claim id **is** the scope id, so "the scope" and "its
  first record" are the same hash. `nekton seed` writes one. Examples 01-04 never needed it because
  a loose claim belongs to no conversation; a review is a conversation, so it starts with one.
  The **seedchain** is that seed plus everything chained onto it.
- a **store** is a registry — the same directory-of-records from examples 01-04 (`NEKTON_DIR`). This
  page says "store" because a review *is* one, handed over whole.
- the **kernel** is kton's core: the part that stores, indexes and verifies records. It is not the
  part that decides anything — `check.py` here is a *consumer*, and consumers make the decisions.
- a claim can name a **`prev`** claim, which chains them into a sequence.
- the **head** is the latest claim in that chain — the one nothing else points back to yet.
- a **chain link** is any claim carrying a `prev`, i.e. a link in that sequence.

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
   print: it is authored as a plankton **foton** whose COVERED inputs (covered = hash-verified as part
   of the record's identity, rather than merely carried alongside it — example 09 draws the line) are the review and the public
   parent (bundled by hash) plus `check.py`, and whose output is the verdict. So it is content-addressed
   and **reproducible** - re-run the check over the same nekton and you get the same verdict (L0). That is
   the plankton/nekton division: nekton is the signed review, plankton is the reproducible decision over
   it - example 12's "nekton in, verdict out".

## Walk through it, one command at a time

The lifecycle above as commands. Everything is typed in one directory and the whole thing runs — this
is the happy path; `run.sh` then does the two scenarios where it must refuse.

```
mkdir -p /tmp/ex05 && cd /tmp/ex05
nekton keygen board ; nekton keygen reviewer-a
PUBDIR="$PWD/public" ; REVDIR="$PWD/review"     # two stores: the public record, and the review
W='"when":"2026-07-16T00:00:00Z"'               # a fixed instant, so this is reproducible
```

**1. Seed the public parent, then the review as its own store under it.** `--parent` rides inside the
signed seed, so it cannot be stripped later. The seed's claim id **is** the scope id.

```
PUB=$(NEKTON_DIR="$PUBDIR" nekton seed drug-reviews \
        --sign board.key --by 'CN=Board' --when 2026-07-16T00:00:00Z --add --print-id)
REV=$(NEKTON_DIR="$REVDIR" nekton seed review-42 --parent "$PUB" \
        --sign board.key --by 'CN=Board' --when 2026-07-16T00:00:00Z --add --print-id)
KA=$(nekton keyid reviewer-a.pub)               # the id a claim carries for this key
```

**2. Initialise the conditions** — who is enrolled — as the review's first chain link, signed by the
board. Signing this is what makes the board the close authority: the party that sets the rules is the
one that may close.

```
cat > init.json <<JSON
{ "subject":[{"hash":"$REV"}], "predicateBody":{
    "predicate":{"uri":"https://kton.dev/v/review-initialised"},
    "reviewers":["$KA"], "by":"CN=Board", $W, "scope":"$REV", "prev":"$REV" } }
JSON
HINIT=$(NEKTON_DIR="$REVDIR" nekton claim init.json board.key --add --print-id)
```

**3. Anchor those conditions back to the parent**, naming the review and the init head. Now the
ruleset is double-locked: the chain seal stops a rollback inside the review, and the parent pins
which ruleset was in force.

```
cat > anchor.json <<JSON
{ "subject":[{"hash":"$REV"}], "predicateBody":{
    "predicate":{"uri":"https://kton.dev/v/review-initialised"},
    "object":{"hash":"$HINIT"}, "by":"CN=Board", $W, "scope":"$PUB", "prev":"$PUB" } }
JSON
NEKTON_DIR="$PUBDIR" nekton claim anchor.json board.key --add
```

**4. The reviewer delivers**, chaining onto the init head.

```
cat > deliver.json <<JSON
{ "subject":[{"hash":"$REV"}], "predicateBody":{
    "predicate":{"uri":"https://kton.dev/v/reviewed"}, "object":{"value":"pass"},
    "by":"CN=Reviewer A", $W, "scope":"$REV", "prev":"$HINIT" } }
JSON
NEKTON_DIR="$REVDIR" nekton claim deliver.json reviewer-a.key --add
```

**5. Read the head and close on the parent**, by that same authority. "Close" is not a verb — it is an
ordinary claim whose predicate says `closed`.

```
HEAD=$(NEKTON_DIR="$REVDIR" nekton head "$REV" --json \
       | python3 -c "import json,sys; print(json.load(sys.stdin)['heads'][0])")

cat > close.json <<JSON
{ "subject":[{"hash":"$REV"}], "predicateBody":{
    "predicate":{"uri":"https://kton.dev/v/closed"}, "object":{"hash":"$HEAD"},
    "by":"CN=Board", $W, "scope":"$PUB", "prev":"$PUB" } }
JSON
NEKTON_DIR="$PUBDIR" nekton claim close.json board.key --add
```

**6. The gate decides**, from the two stores alone:

```
python3 <path-to-repo>/examples/05-review-scope/check.py "$REVDIR" "$PUBDIR" "$REV"
# gate read 3 record(s) from the review and 3 from the public parent
# RELEASE: COMPLETE - 1 enrolled reviewers all delivered a pass, sealed at sha256:..., closed by its own authority
```

Nothing above is a kton verb for "review" or "close": every step is an ordinary signed claim, and the
predicate is the only thing that says what it means. The decision is `check.py`'s — a consumer's, not
the kernel's.

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
