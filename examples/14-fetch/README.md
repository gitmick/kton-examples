# 14 - fetch: getting the bytes back to re-hash them

The front page promises you can *re-check a result by re-hashing and re-running* it. But plankton
stores **no bytes** - only hashes. So: re-hash **which** bytes? This example is the answer. A record
names its content by hash; a signed **`dcat:downloadURL`** located-at claim says *where* those bytes can
be had; and **`kton fetch`** dereferences that suggestion and verifies `sha256(bytes) == hash` before
trusting a single byte.

Assumes `plankton`, `nekton`, and `kton` are on your PATH. (`kton` is the cockpit; the kernels never
dereference a URI - resolving one is `kton`'s job, [example 05](../05-review-scope/) explains the split.)

## Verification is two operations

Verifying the **record** - its signature (who signed) and its id (integrity) - needs only the record.
It works offline, forever, and is exactly what [example 01](../01-hello-foton/) and multi-source read
([example 02](../02-federation/)) give you. Verifying the **content** - that a file really hashes to its
recorded hash, or that re-running reproduces it - needs the actual **bytes**, which travel separately.
So assurance is a ladder (the protocol's [Trust chapter](https://github.com/gitmick/plankton/blob/main/docs/trust.md),
section 5):

| rung | proves | needs |
|---|---|---|
| **record-authentic** | signature + id ([01](../01-hello-foton/)) | the record only - always |
| **content-present** | the bytes hash to the recorded hash | **this example** - byte availability |
| **reproduced** | re-run in a qualified env ([03](../03-reproduce/)/[10](../10-tool-spectrum/)) at L0/L1 | bytes + an executor |

You cannot climb to *content-present* or *reproduced* without first getting the bytes. That is what
`fetch` is for.

## Walk through it

**A. A record names its bytes by hash; the local content store is empty.** The producer records a
foton; its result is named by a content hash. You hold the record - but plankton stored no bytes, so
your local content store is empty. You cannot re-hash what you do not have.

```
plankton blob "$RESULT"
# absent sha256:7f6e...     <- the record is filed; the bytes are not here
```

**B. A signed `dcat:downloadURL` says where; `kton fetch` verifies before trusting.** The location is
the published **DCAT** term (reused, not minted): subject = the content hash, object = a URI. It is a
signed, post-hoc, *plural* suggestion - "you can get these bytes here." `kton fetch` reads it,
dereferences the URI, re-hashes, and pins **only if the hash matches**:

```
nekton claim loc.json lab.key --add          # <RESULT> dcat:downloadURL file://.../result.bytes
kton fetch --trust-keys trust-lab --allow-local "$RESULT"
# sha256:7f6e...: 1 located-at claim(s), 1 signed by a trusted key
#   [1] file://.../result.bytes  (verified signer key:6de19b30...) ... OK - 10 bytes, verified & pinned
plankton blob "$RESULT"
# PINNED sha256:7f6e...        <- content-present: the bytes are here, and they hash to what was named
```

`--trust-keys` is a **directory of public keys you chose**, and it is required. The keyid printed is
the one that actually *verified*, never the envelope's self-declared field. `--allow-local` is a
second, separate yes: these locators are `file://`, and a signature about **content** says nothing
about a path on **your** machine.

**C. Two defences, and neither replaces the other.** An **untrusted stranger** publishes a second
signed location pointing at *forged* bytes.

**C1 - a stranger's location is never opened at all.** With only the lab trusted, the registry holds
two located-at claims and exactly one is dereferenceable:

```
# located-at claims in the registry: 2    signed by a key we trust: 1
```

This is the defence a hash cannot provide. Dereferencing is a **request made from your host** - and
for `file://`, a read of your disk - and no check performed on the result retracts the request. For a
file whose hash an attacker already knows, the content check does not even reject the outcome. So a
stranger does not get to choose what your process opens.

**C2 - and a trusted signer's bytes are still checked exactly as hard.** Trust the stranger too, put
the good copy out of reach, and the forged location is the one tried:

```
kton fetch --trust-keys trust-both --allow-local "$RESULT"
#   [1] file://.../store/result.bytes   ... unreachable
#   [2] file://.../mirror/result.bytes  (verified signer key:b41627af...) ... HASH MISMATCH - rejected
# error: no suggested location resolved to bytes matching sha256:7f6e...
```

**The trust policy decides whose location is opened; the hash decides whether what came back is what
the record named.** The older half of that sentence is still true - content addressing self-checks on
arrival, so *bytes* from an untrusted mirror cannot fool you. What changed is that the *request* is
its own exposure, and that one is settled before anything is opened, not after.

## Two ways to say where the bytes are

- **The located-at claim (this example).** A nekton `dcat:downloadURL` claim: signed, plural, post-hoc,
  and third-party (anyone can add one; a mirror can announce itself). This is what `kton fetch`
  resolves, and what [example 12](../12-submission/) uses so a regulator can fetch every evidence PDF it
  holds a hash for.
- **The carried FileRef `uri` (the author's inline hint).** A foton's own FileRef may carry a `uri`
  alongside the hash - the producer's single suggestion, riding *with* the record. It is carried, not
  covered, so it never changes the foton id. (Exposing it through `plankton author` is
  [plankton issue #22](https://github.com/gitmick/plankton/issues/22).)

Both are hints under the same rule: the hash decides, the URI only points.

## The boundary this example names

**Availability is a *liveness* property the hash cannot give.** If every located byte-store were gone or
corrupt, `kton fetch` would fail - the record stays fully verifiable (signature + id), but the content
is simply unavailable. Bytes are **located, not stored**, and kept per a retention policy; that they
still exist *somewhere* is a retention obligation, stated rather than assumed (Trust chapter, the
retention boundary). Availability is never a *trust* problem - only a liveness one.

## What this example needs from which binary

This is the **only** example that needs the `kton` cockpit binary, and after `plankton blob`
absorbed the blob store (kton #102) it needs exactly one command from it: **`kton fetch`**.
Everything else here — authoring the foton, signing the `located-at` claim, asking the local store
whether the bytes are present — is kernel.

`kton fetch` cannot move into `plankton` or `nekton`, and that is a decision rather than an
omission. The resolver says so where it lives (`kton/reference/cmd/kton/fetch.go`):

> the one place a URI is dereferenced. It belongs in kton and only in kton: plankton and nekton are
> strictly neutral, they CARRY a URI as an opaque signed string and never execute it.

It is the same line the substrate draws everywhere else. plankton never executes a protocol
([01](../01-hello-foton/)); nekton stores verification material and never evaluates it
([15](../15-attach-material/)); and here, the kernels record *where somebody says* bytes can be had
and never go and ask. Dereferencing is a request made **from your host** — for `file://`, a read of
your disk — and that is an act with consequences a later hash check cannot retract. Putting it in a
kernel would make every reader of a record a potential client of whatever a stranger signed.

So if the cockpit ever leaves this repository, the cut is already drawn:

| part | needs | goes where |
|---|---|---|
| A — a record names its bytes, the local store is empty | `plankton author`, `plankton hash`, `plankton blob` | stays |
| the signed `dcat:downloadURL` locator itself | `nekton claim` | stays |
| B, C1, C2 — dereference, verify on arrival, trust policy | **`kton fetch`** | goes with the cockpit |

Measured rather than assumed: with the `kton` binary removed from `PATH`, sixteen of the seventeen
examples still pass, and this one fails at the first `kton fetch` — everything above it, through
signing and filing the locator claim, has already run.

Part A plus the claim is a complete kernel-side lesson on its own: a record names bytes it does not
hold, and the hash is the only thing that will ever decide whether what comes back is the right
thing. What the cockpit adds is the going-and-getting.

## Run it yourself

```
bash run.sh
```

## See it

The viewer shows the result foton with its located-at claims folded into per-file locators - including
the forged one. The graph shows *claimed* locations; verification happens at `fetch`, on arrival, not in
the picture.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/14-fetch/union.json&keys=data/14-fetch/keys.json&names=data/14-fetch/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
