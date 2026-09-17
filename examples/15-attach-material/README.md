# 15 - external verification material

Everything in examples 01-14 is checkable with kton alone: a hash you re-compute, a signature you
check against a key. Real records also arrive carrying evidence from **outside** that vocabulary — a
Sigstore bundle, a Rekor entry, an RFC 3161 timestamp, an eIDAS or CAdES signature.

SPEC §8.1 gives that evidence three things: a **place** (`attach`), a **binding** (a record's content
address), and a **boundary**. The kernel stores it, indexes it, hands it back — and never decides
whether it is any good. That is not an omission. *Which issuers count* is a trust policy, not a fact
about bytes, and a kernel that ruled on it would be making your policy decisions for you.

So this example does both halves: kton carries, and then a verifier that is **not** kton evaluates.

Assumes `plankton`, `nekton` on your PATH, and `python3` with `cryptography`
(`pip install cryptography`). You have seen fotons ([01](../01-hello-foton/)) and claims
([04](../04-claim/)); the foreign-verifier shape is [13](../13-foreign-verify/).

## The trap, first — because it decides whether your check can ever succeed

An outside attestation commits to the record's **envelope payload**. A Rekor entry does exactly this.
So a consumer checking one has to hash the payload — and the record id is not always that hash:

```
foton  record id      sha256:4211c41fb3762d881e0…
       sha256(payload) sha256:660cce2c8c2db5c4c9c…   -> DIFFERENT
claim  record id      sha256:bd2f2d61febce308f00…
       sha256(payload) sha256:bd2f2d61febce308f00…   -> THE SAME
```

A **claim** id *is* the sha256 of its payload. A **foton** id is not: it is computed over the COVERED
projection (SPEC §6.3), which excludes the carried `uri`/`id`/`mediaType` fields — so the same
envelope has two different hashes and only one of them is the id.

Nothing is wrong with either record. The trap is that the claim case works if you assume id ==
payload hash, which is exactly what makes people assume the foton case does too. It does not, the
check simply never matches, and nothing tells you why. Reach the payload *through the envelope* and
both cases are one line of code.

## Attach

```
plankton attach <foton-id> --scheme example-notary/v0 --file token.json --media application/json
nekton   attach <claim-id> --scheme example-notary/v0 --file token.json --media application/json
# attached example-notary/v0 (333 bytes, application/json) to sha256:...
# note: stored, NOT verified - the kernel never evaluates verification material (SPEC §8.1)
```

`--scheme` names six tokens (`sigstore-bundle`, `rekor-entry`, `rfc3161`, `cms-detached`, `jades`,
`pgp-detached`), and **the list is open**: an unnamed scheme is carried rather than refused, but it
needs `--media` so a reader knows how to read the bytes. Read it back with `plankton material` /
`nekton material` (`--json` for the machine form, which includes the evidence itself, base64'd).

## What kton refuses, and what it will not do

Two refusals, both demonstrated in `run.sh` as negative controls that fail the example if they ever
start succeeding:

- **attaching to a record the registry does not hold.** Material binds to a content address, not to a
  file sitting in a directory — a record nobody filed cannot acquire evidence.
- **an unnamed scheme with no `--media`.** An open list still has to be readable.

And one thing it deliberately will not do: say whether the evidence is valid. Both `attach` and
`material` print `NOT verified` every time, unprompted. In `run.sh` the consumer then does the job the
kernel left alone — and gets it right only because it goes through the envelope, per the trap above.
A token made for the *claim*, checked against the *foton*, is rejected.

## Or just run the whole thing

`run.sh` is a file in this example's directory — clone the repo and run it from there:

```
git clone https://github.com/gitmick/kton-examples && cd kton-examples/examples/15-attach-material
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/15-attach-material/union.json&keys=data/15-attach-material/keys.json&names=data/15-attach-material/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*

Note the graph shows the foton and the claim, and **not** the attached material: material is indexed
beside the records, read after them, and never fed into them. It is evidence about a node, not an
edge in the lineage.
