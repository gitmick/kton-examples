# 17 - ↻N: how many independent signers produced this output?

Example [03](../03-reproduce/) asks whether two results match. This asks what a reviewer actually
wants to know: **how many separate parties got here.** That is the difference between "someone says
so" and "several people, who do not answer to each other, agree".

It is also the single most forgeable number in the system, because a `keyid` inside an envelope is an
unauthenticated hint until somebody checks it. So plankton reports it two ways and will not let you
confuse them.

## Independent reproduction is a co-signature, not a second document

alice records the computation. bob runs the same thing and records it too — and the registry still
holds **one** foton:

```
plankton reproductions --trust-keys trusted/ <output-hash>
# reproductions: 2 distinct verified signer(s) produced sha256:6456552...  (↻2; 1 producer foton(s))
```

Two signers, *one* producer foton. A foton id is computed over the COVERED projection, which does not
include the signatures — so an identical computation by a different party is not a copy of the record,
it is another signature **on** it. Agreement is structural here rather than editorial.

## The cheap number warns you about itself

```
plankton reproductions <output-hash>
# warning: this ↻N is over SELF-DECLARED keyids and is FORGEABLE (a relabeled keyid inflates it
#          and mis-attributes); pass --trust-keys <dir> to count only authenticated signers
```

Unprompted, every time. The `keyid` field is not covered by the signature, so rewriting it is free.

## What that buys an attacker

`run.sh` does it. mallory authors three variants of the same command over the same input — same
output, three *different* producer fotons — and relabels each with a keyid she does not hold:

| | ↻N | producer fotons |
|---|---|---|
| self-declared | **4** | 4 |
| verified, against `trusted/` | **2** | 4 (3 excluded) |

Nothing was detected. Nothing was blocked. The forged records are still in the registry, still
well-formed, still signed — by mallory, who is entitled to sign her own records. The only thing that
changed is **which question was asked**: over declared labels, or over signatures against keys
somebody vouched for.

`trusted/` holds alice's and bob's public keys. mallory is not in it, and not because she is
suspected — because nobody vouched for her. That is the entire mechanism, and it is the same one
example [07](../07-identity/) builds up and example [12](../12-submission/) turns into a release gate.

The example asserts **both** numbers, including that the forgery really did inflate the naive count.
Without that second assertion it would keep passing if the attack silently stopped working, and
would then be demonstrating nothing while looking exactly the same.

## Or just run the whole thing

```
git clone https://github.com/gitmick/kton-examples && cd kton-examples/examples/17-reproductions
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/17-reproductions/union.json&keys=data/17-reproductions/keys.json&names=data/17-reproductions/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*

Four producer fotons for one output: the honest one carrying two signatures, and mallory's three.
The graph cannot tell you which is which — `--trust-keys` can.
