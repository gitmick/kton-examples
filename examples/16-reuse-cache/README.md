# 16 - the action key: "has anyone computed this already?"

Every example so far asks about a computation that **happened**. This one asks **before**: given the
inputs and the protocol I am about to run, has someone already run it? plankton answers from the
records it holds — no execution, no network. The question is a hash.

```
plankton reuse alice.dsse.json
# action key: sha256:4bd4077...
# cache: HIT -> 1 prior computation(s) with these inputs+protocol:
#   sha256:d4649f5...  declared-signer=3bc40114432b6a6f (unverified)  output=sha256:178411b...
# note: these are COMPETING cache-key matches, not a trusted result ...
```

The **action key** is `sha256(canonicalJSON({inputs: {relpath -> hash}, protocol: {kind, ref}}))`
(SPEC §6.3). Note what is not in it: **the output**. That is the thing you were going to compute.

## Why a HIT is not an answer

Because outputs are outside the key, two signers can hit the same key and **disagree about the
result** — and that is not an edge case, it is the normal state of a world where anyone may author a
record. `run.sh` makes it happen: alice records `cl=4.200`, mallory records `cl=9.999` from the same
inputs and the same command, and the cache reports both under one action key.

Nothing is forged. Both fotons are honestly signed by their own authors. The cache matched the
**question**; it has no opinion about the answers, and no amount of hashing produces one. Only a
signer you trust does — so the example ends that part by verifying alice's foton against alice's key
(VALID) and mallory's against alice's key (WRONG KEY).

A cache that hid this would be a trust system wearing a cache's clothes. `plankton reuse` prints the
warning on every hit rather than letting you forget.

## What changes the key, and what does not

- change an **input** byte → different key → `cache: MISS`.
- change the **output** → same key, one more competing hit.
- the **ref** used is the *effective* one, derived from the carried descriptor when there is one —
  not the `ref` field as written on the wire.

That last point is a defence, and `run.sh` demonstrates both halves of it as negative controls that
fail the example if they ever start succeeding:

- **a wire `ref` that disagrees with its own descriptor** is malformed (SPEC §6.2) and refused. A key
  computed from the lie would file a result under somebody else's question.
- **two inputs at the same relative path with different hashes** are refused as an ambiguous
  computation identity. The key is a `{relpath -> hash}` map, so a silent last-wins would erase an
  input and let a two-input foton reuse a one-input result.

A foton that carries no descriptor at all is namespaced separately (`refUnverified`), so a bare
pointer to an off-record protocol can never share a key with a verifiable one.

## Three questions that sound alike

| | question | answer is about |
|---|---|---|
| `plankton reuse` (here) | was this *asked* before? | the computation's identity |
| `plankton reproduces` ([03](../03-reproduce/)) | do these two results *match*? | two records |
| `plankton reproductions` ([17](../17-reproductions/)) | how many *independent* signers got this output? | trust |

Only the last two are about trust. This one is about work you might not have to repeat.

## Or just run the whole thing

```
git clone https://github.com/gitmick/kton-examples && cd kton-examples/examples/16-reuse-cache
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/16-reuse-cache/union.json&keys=data/16-reuse-cache/keys.json&names=data/16-reuse-cache/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*

Two fotons, one action key, two different outputs — the disagreement is the picture.

---

`plankton reuse --json` (kton #74) carries per hit what the printed form only hints at in a stderr
note: `declaredSigner` and `verified: false`. That is the right place for it. An action key binds
inputs and protocol and never the signer, so the hits **compete**, and the keyid on each is the
envelope's unauthenticated hint — anyone choosing a hit mechanically has to see that on the record
they act on, not in a warning next to it.
