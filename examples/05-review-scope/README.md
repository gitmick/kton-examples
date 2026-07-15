# 05 - review scope

A chain of signed claims sealed by one head. Publishing the head makes the whole chain
tamper-evident.

## What `run.sh` does

- **ANLEGEN (create):** open a review **scope** with `nekton seed`, then chain two review claims
  under it (each names the scope and a `prev`).
- **VERWENDEN (use):** `nekton head <scope>` returns the tip (the seal); a claim with a dangling
  `prev` is rejected.

## Key idea

Within a scope, each claim's id covers its `prev`, so the claims form a hash chain. The **head** (the
last claim's id) transitively commits to the entire chain: edit any earlier claim and its id changes,
which breaks the next `prev`, which changes the head. Publish (or `kton anchor`) the head and anyone
holding it can detect tampering with the review history. `add` refuses a claim whose `prev` does not
resolve in the scope - a chain gap is a tamper.

## Run

```
bash run.sh
```

## Expected output (abridged)

```
scope id = sha256:1ff2bb7c...
link1 = sha256:849fdfd4...
link2 = sha256:85e362c8...
head:    sha256:85e362c8...   (2 claim(s) chained)
add forged link: error: prev sha256:deadbeef... does not resolve in scope ... (chain gap / tamper)
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/05-review-scope/union.json&keys=data/05-review-scope/keys.json&names=data/05-review-scope/names.json)
