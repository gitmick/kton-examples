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
kton blob "$RESULT"
# absent sha256:7f6e...     <- the record is filed; the bytes are not here
```

**B. A signed `dcat:downloadURL` says where; `kton fetch` verifies before trusting.** The location is
the published **DCAT** term (reused, not minted): subject = the content hash, object = a URI. It is a
signed, post-hoc, *plural* suggestion - "you can get these bytes here." `kton fetch` reads it,
dereferences the URI, re-hashes, and pins **only if the hash matches**:

```
nekton claim loc.json lab.key --add          # <RESULT> dcat:downloadURL file://.../result.bytes
kton fetch "$RESULT"
# sha256:7f6e...: 1 signed location(s) suggested
#   [1] file://.../result.bytes  (signed by CN=lab) ... OK - 10 bytes, verified & pinned
kton blob "$RESULT"
# PINNED sha256:7f6e...        <- content-present: the bytes are here, and they hash to what was named
```

**C. A location is a hint, not an authority.** Now an **untrusted stranger** publishes a second signed
location pointing at *forged* bytes. `kton fetch` tries every suggestion and checks each on arrival:

```
kton fetch "$RESULT"
# sha256:7f6e...: 2 signed location(s) suggested
#   [1] file://.../mirror/result.bytes  (signed by CN=stranger) ... HASH MISMATCH (got sha256:aa06...) - rejected
#   [2] file://.../store/result.bytes   (signed by CN=lab)      ... OK - 10 bytes, verified & pinned
```

The forged mirror hash-mismatches and is thrown out; a good location still verifies. This is the whole
point of content addressing: **the hash is the authority, the URI is only a hint.** Bytes may come from
*any* mirror - even an untrusted one, even a public CDN - because corruption or tampering is caught on
arrival (`sha256 != hash`), never trusted. A signed pointer to bad bytes cannot fool you.

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

## Run it yourself

```
bash run.sh
```

## See it

The viewer shows the result foton with its located-at claims folded into per-file locators - including
the forged one. The graph shows *claimed* locations; verification happens at `fetch`, on arrival, not in
the picture.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/14-fetch/union.json&keys=data/14-fetch/keys.json&names=data/14-fetch/names.json)
