# 05 - a review is its own (sub)nekton

A single signed claim (example 04) says one thing. A **review** is a *conversation*: a sequence of
decisions that must hang together, be handed over whole, and whose rejections cannot be silently
stripped. Think of a nekton as a **context - a "talk"**: the things that belong to one conversation,
kept together. A review is such a context, and here it is **literally its own registry**, so you can
hand it over whole to someone who verifies it **two ways**: (1) the sub-nekton resolves to its head *on
its own* - a valid seedchain, no other attestations attached; (2) if the parent is public, the parent's
**close** claim pins that seed and head. You **open** the review by seeding it *from* a public scope, you
**hold** it as a chain (each claim covers the previous, so one **head** seals the history), and you
**close** it by writing a **claim back to the parent** naming the review and its head.

Closing is **not a new verb**. It is an ordinary claim - the same shape as a verdict - and the predicate
is the only thing that says "closed". The kernel gains nothing: SPEC §7.4 already reserves parent→child
registration and sealing as *convention, checked by consumers*, over the seed/chain grammar it does
mandate.

Assumes `nekton` is on your PATH. Each claim points at the previous by id, so every command captures the
id it needs into a shell variable.

## Walk through it, one command at a time

**1. Two identities, two stores.** The board owns the public record; the chair runs the review. The
review gets **its own registry** - that is what lets you hand it over on its own.

```
nekton keygen board ; nekton keygen chair
PUB_DIR=./public ; REV_DIR=./review
```

**2. The public record - a standing parent scope**, in the public store.

```
PUB=$(NEKTON_DIR=$PUB_DIR nekton seed public-record --sign board.key --by "CN=Board" --add \
      | grep -oE 'sha256:[0-9a-f]+' | tail -1)     # a seed prints its parent hash first, so take the LAST
```

**3. Open the review as its OWN nekton, seeded FROM the public scope.** The `--parent` link rides
*inside* the signed seed, so it cannot be stripped without changing the review's identity - from any
copy of the review you can find its parent.

```
REV=$(NEKTON_DIR=$REV_DIR nekton seed drug-review --parent "$PUB" --sign chair.key --by "CN=Chair" --add \
      | grep -oE 'sha256:[0-9a-f]+' | tail -1)
```

**4. Hold the review: chain the claims inside the review's store.** Every scoped claim names the scope
and a `prev`; for the first, `prev` is the scope id itself.

```
# c1: prev = $REV ; c2: prev = $C1 ; ... ; then read the sealed head
NEKTON_DIR=$REV_DIR nekton head "$REV"        # head: sha256:...  (the tip that seals the whole chain)
```

**5. Hand it over, and verify it alone (leg 1).** The review store is self-contained. Give someone only
that store - `cp -r`, `nekton mirror`, or a fetch by hash - and they verify the seedchain with no parent
and no other attestations:

```
NEKTON_DIR=$HANDED nekton head "$REV"
# resolves to the same head, 0 unresolved -> a valid, COMPLETE seedchain on its own
```

**6. Close it: a claim to the PARENT (leg 2).** An ordinary claim whose `subject` is the review scope,
whose `object` is its sealed head, scoped **into** the public record. Swap the predicate for a verdict and
it *is* a verdict - one shape, two meanings.

```
cat > close.spec.json <<JSON
{ "subject":[{"hash":"$REV"}], "predicate":"https://kton.dev/v/closed",
  "object":{"hash":"$HEAD"}, "by":"CN=Board", "when":"2026-07-16T00:00:00Z",
  "scope":"$PUB", "prev":"$PUB" }
JSON
NEKTON_DIR=$PUB_DIR nekton claim close.spec.json board.key --add
NEKTON_DIR=$PUB_DIR nekton about "$REV"    # -> predicate=.../closed  by=CN=Board  (closed at $HEAD)
```

That is the whole contract: the review travels as one bounded context and **self-verifies** (leg 1); the
public parent **binds** its seed and head (leg 2), so the head the recipient resolved is the authoritative
one - which is what defeats a rewind to a shorter, cleaner chain. Over a public parent, leg 2 is a SPARQL
check ("a `nk:closed` claim whose subject is `$REV` and object is `$HEAD`") - the release gate of
[example 12](../12-submission/). You hand over one review, not a pile of a hundred unrelated attestations.

## The boundaries - what "closed" does and does not settle

**The head proves integrity, not currency.** A published head is tamper-evident, but by itself it does
not prove it is the *latest*: an earlier, shorter chain (a **rewind**) verifies just as cleanly.
Anchoring the parent's close in a transparency log (`kton anchor`, example 08) time-orders it so a rewind
is undeniable; confirming you hold the latest anchored close is a consumer **freshness** step.

**Sealing is tamper-evidence, not append-control - and the substrate is append-only.** The chain
guarantees no *committed* link is silently dropped or edited (remove an inconvenient reject and the head
stops matching). It does **not** stop anyone from signing a well-formed claim that extends the review.
That is fine: what closes the conversation is the **parent's record**, which pins the head at close time.
A claim added *after* that head is a valid claim that is simply **outside** the closed review - "you can
still add, but look it up, it is over." Try it: extend the review after the close and its *live* head
moves, but the parent still pins `closed@HEAD`, so the addendum is visibly post-close.

**Who may close, and whether the review was conducted honestly, are behind kton's boundary.** *Who* may
write the close is trust policy - here the board, the parent's authority; a scope's `responsible` set
(SPEC §7.4) names it. And whether every input was captured and whether a signer *saw what they signed* is
a validated system's job (a transactional trail + a validated UI) - kton **documents** the review and
makes tampering, rewinds and post-close additions *detectable*; it does not *conduct* the review.

**A dangling `prev` never joins the chain.** A claim naming this scope but with a `prev` that resolves
nowhere is **persisted** - its `prev` might arrive from another peer later, so the substrate treats it as
*incomplete, not invalid* - but it never joins the scope, so it is never the head. This is the
open-substrate rule (the same one federation needs), not a special sealed-scope fatality: a resolved
chain is complete and tamper-evident; a dangling link is deferred, not rejected on the spot.

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/05-review-scope/union.json&keys=data/05-review-scope/keys.json&names=data/05-review-scope/names.json)
